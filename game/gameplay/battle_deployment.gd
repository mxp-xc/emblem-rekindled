extends RefCounted

const STAT_ORDER: Array[String] = [
	"strength", "skill", "speed", "defense", "magic", "luck", "maxHp", "move"
]
const INITIAL_NOISE: Array[int] = [3, 2, 2, 2, 2, 5, 2, 0]
var _content: Dictionary
var _combat: RefCounted
var _inventory: RefCounted
var _random_source: Callable
var _definitions: Dictionary = {}
var _base_stats: Dictionary = {}
var _growth_rates: Dictionary = {}
var _map: Dictionary
var _stat_caps: Dictionary
var _chapter_id: String
var _battle_id: String
var _initialization_context: Variant


func _init(
	content: Dictionary,
	combat: RefCounted,
	inventory: RefCounted,
	roll: Callable,
	initialization_context: Variant = null
) -> void:
	_content = content
	_combat = combat
	_inventory = inventory
	_random_source = roll
	_initialization_context = initialization_context
	_map = content["map"]
	_stat_caps = content["rules"]["statCaps"]
	_chapter_id = content["entry"]["id"]
	_battle_id = content["entry"]["battleId"]
	for definition: Dictionary in content["units"]:
		_definitions[int(definition["id"])] = definition
	for row: Dictionary in content["rules"]["baseStats"]:
		_base_stats[int(row["id"])] = row
	for row: Dictionary in content["rules"]["growthRates"]:
		_growth_rates[int(row["id"])] = row


func create() -> Dictionary:
	var content: Dictionary = _content
	var units: Dictionary = {}
	var bindings: Dictionary = {}
	var occupied: Dictionary = {}
	var initialized: Dictionary = {}
	var required: Array[int] = []
	var next_temporary: int = 95
	var inherited: Dictionary = {}
	for member: Dictionary in content.get("inheritedParty", []):
		inherited[int(member["id"])] = member
	for index: int in range(content["spawns"].size()):
		var spawn: Dictionary = content["spawns"][index]
		var current: Dictionary = _definitions[int(spawn["id"])].duplicate(true)
		for field: String in [
			"id",
			"faction",
			"x",
			"y",
			"classId",
			"classGroup",
			"move",
			"hp",
			"maxHp",
			"level",
			"flags",
			"equipMask",
			"sourceId",
			"dropTemplateId",
			"proficiency",
			"experience"
		]:
			current[field] = int(current[field])
		var deployment_index: int = int(spawn.get("deploymentIndex", index))
		bindings[deployment_index] = -1
		# Source data chooses equipment before choosing a deployment cell, even when
		# there is no free cell and the record will be omitted.
		var choices: Array = spawn["itemChoices"].duplicate()
		if spawn["randomEquipment"]:
			var selected: int = int(_random_source.call(choices.size()))
			for choice: int in range(choices.size()):
				if choice != selected:
					choices[choice] = 0
		var point: Vector2i
		if spawn.has("deploymentRegions"):
			var candidates: Array[Vector2i] = []
			for x: int in range(int(_map["width"])):
				for y: int in range(int(_map["height"])):
					var cell := Vector2i(x, y)
					if occupied.has(cell):
						continue
					for region: Array in spawn["deploymentRegions"]:
						if x >= region[0] and x <= region[2] and y >= region[1] and y <= region[3]:
							candidates.append(cell)
							break
			if candidates.is_empty():
				continue
			point = candidates[int(_random_source.call(candidates.size()))]
		else:
			point = Vector2i(spawn["position"][0], spawn["position"][1])
		if spawn.get("temporary", false):
			current["id"] = next_temporary
			next_temporary += 1
		if spawn.has("deploymentIndex"):
			current["deploymentIndex"] = deployment_index
			current["temporary"] = spawn.get("temporary", false)
		current["action"] = 0
		_initialize_unit(
			current,
			spawn,
			choices,
			point,
			inherited.get(int(current["id"]), {}) if spawn["formal"] else {}
		)
		var identity: int = int(current["id"])
		bindings[deployment_index] = identity
		units[identity] = current
		initialized[identity] = current.duplicate(true)
		if not spawn.has("deploymentRegions"):
			required.append(identity)
		# The original deployment grid reserves hidden records as well.
		occupied[point] = true
	return {
		"units": units, "definitions": initialized, "requiredIds": required, "bindings": bindings
	}


func _initialize_unit(
	current: Dictionary,
	spawn: Dictionary,
	choices: Array,
	position: Vector2i,
	inherited: Dictionary = {}
) -> void:
	current["sourceId"] = int(spawn["sourceId"])
	current["formal"] = spawn["formal"]
	current["flags"] = int(spawn["flags"])
	current["policy"] = int(spawn["policy"])
	current["visible"] = spawn["visible"]
	current["level"] = int(spawn["level"])
	current["growthTemplateId"] = int(spawn["growthTemplateId"])
	current["experience"] = 0
	current["proficiency"] = 0
	current["x"] = position.x
	current["y"] = position.y
	current["inventory"] = []
	current["equippedInstanceId"] = ""
	if not inherited.is_empty():
		for field: String in [
			"classId",
			"classGroup",
			"equipMask",
			"level",
			"hp",
			"maxHp",
			"move",
			"growthTemplateId",
			"experience",
			"proficiency",
			"attributes",
			"inventory",
			"equippedInstanceId"
		]:
			if inherited.has(field):
				current[field] = (
					inherited[field].duplicate(true)
					if inherited[field] is Dictionary or inherited[field] is Array
					else inherited[field]
				)
		return
	for template_id: Variant in choices:
		_add_initial_item(current, int(template_id))
	_add_initial_item(current, int(spawn["dropTemplateId"]))
	var values: Dictionary
	if spawn.has("explicitStats"):
		values = spawn["explicitStats"].duplicate(true)
	else:
		values = {}
		var base: Dictionary = _base_stats[int(spawn["baseTemplateId"])]
		var growth: Dictionary = _growth_rates[int(spawn["initialGrowthTemplateId"])]
		var initial_weapon: Dictionary = _combat.item_definition(
			int(spawn.get("initialWeaponId", 0))
		)
		for index: int in range(STAT_ORDER.size()):
			var stat: String = STAT_ORDER[index]
			var value: int = int(base[stat]) + int(float(growth[stat]) * current["level"] / 100.0)
			if current["faction"] != 0:
				var noise: int = INITIAL_NOISE[index]
				if stat == "strength" and int(initial_weapon.get("categoryMask", 0)) == 16:
					noise = 0
				value += int(_random_source.call(noise + 1))
			if stat == "maxHp" and _combat.is_named_boss(current):
				value += 20
			if value < 0 or value > int(_stat_caps[stat]):
				value = int(_stat_caps[stat])
			values[stat] = value
	current["attributes"] = {}
	for stat: String in STAT_ORDER:
		if stat in ["maxHp", "move"]:
			current[stat] = int(values[stat])
		else:
			current["attributes"][stat] = int(values[stat])
	current["hp"] = current["maxHp"]
	if _combat.is_named_boss(current):
		for stat: String in STAT_ORDER:
			if stat == "move":
				continue
			if stat == "maxHp":
				var target: int = (
					int(_initialization_context["maxHp"])
					if _initialization_context != null
					else int(current[stat])
				)
				current[stat] = mini(99, current[stat] + (maxi(0, target - current[stat]) >> 1))
			else:
				var value: int = current["attributes"][stat]
				var target: int = (
					int(_initialization_context["attributes"][stat])
					if _initialization_context != null
					else value
				)
				current["attributes"][stat] = mini(99, value + (maxi(0, target - value) >> 1))
		var proficiency: int = int(current["proficiency"])
		var difference: int = (
			maxi(0, int(_initialization_context["maxProficiency"]) - int(proficiency / 10))
			if _initialization_context != null
			else 0
		)
		current["proficiency"] = mini(800, proficiency + (difference >> 1) * 10)
	_inventory.auto_equip(current)


func _add_initial_item(current: Dictionary, template_id: int) -> void:
	if template_id <= 0:
		return
	current["inventory"].append(
		{
			"id":
			(
				"%s:%s:unit_%d:item_%d"
				% [_chapter_id, _battle_id, current["id"], current["inventory"].size()]
			),
			"templateId": template_id,
			"durability": int(_combat.item_definition(template_id)["defaultDurability"])
		}
	)
