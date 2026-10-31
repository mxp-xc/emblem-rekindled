extends RefCounted

const LOGIC_UNITS: int = 50
const GROWTH_ORDER: Array[String] = [
	"maxHp", "strength", "skill", "speed", "magic", "defense", "luck", "move"
]
var kind: String
var tick: int = 0
var finished: bool = false
var experience: int = 0
var values: Array[int] = []
var changed_index: int = -1
var _target: int
var _after: Array[int] = []
var _pending: Array[int] = []
var _growth_age: int = 4
var _remaining_units: int = -1


static func sequence(
	result: Dictionary,
	actors: Array,
	interface: Dictionary,
	tutorial_seen: bool,
	player_phase: bool = true
) -> Array[Dictionary]:
	var queue: Array[Dictionary] = []
	var expiry: Array[Dictionary] = []
	var expired: Dictionary = result.get("expiredItem", {})
	if not expired.is_empty():
		expiry.append(
			{
				"kind": "message",
				"text": interface["items"][str(int(expired["templateId"]))]["name"]["text"] + "消失",
				"durationUnits": 1200,
				"unit": result["actor"],
				"noticeIcon": interface["items"][str(int(expired["templateId"]))]["icon"]
			}
		)
	var units: Dictionary = {}
	for actor: Dictionary in actors:
		units[int(actor["id"])] = actor
	for actor: Dictionary in result.get("participants", []):
		if actor["faction"] != 0:
			continue
		var inventory: Array = actor["inventory"].duplicate()
		inventory.reverse()
		for held: Dictionary in inventory:
			for broken: Dictionary in result.get("brokenItems", []):
				if (
					broken["unit"] == actor["id"]
					and broken["templateId"] == held["templateId"]
					and broken.get("item", held["id"]) == held["id"]
					and int(held["templateId"]) < 60
				):
					queue.append(
						{
							"kind": "message",
							"text":
							interface["items"][str(int(held["templateId"]))]["name"]["text"] + "消失",
							"durationUnits": 1200,
							"unit": actor["id"],
							"noticeIcon": interface["items"][str(int(held["templateId"]))]["icon"]
						}
					)
	var rewards: Dictionary = result.get("rewards", {})
	for loot: Dictionary in rewards.get("loot", []):
		queue.append(
			{
				"kind": "message",
				"text": "获得",
				"templateId": loot["item"]["templateId"],
				"durationUnits": 1200,
				"unit": loot["unit"]
			}
		)
		if loot["destination"] == "warehouse":
			queue[-1]["warehouseNotice"] = "人物携带已满存入仓库"
	var experience: Dictionary = rewards.get("experience", {})
	if experience.is_empty():
		return queue + expiry
	queue.append(
		{
			"kind": "experience",
			"unit": experience["unit"],
			"before": experience["before"],
			"amount": experience["amount"]
		}
	)
	if not tutorial_seen and player_phase:
		queue.append({"kind": "tutorial", "unit": experience["unit"]})
	if experience["growth"].is_empty():
		return queue + expiry
	var unit: Dictionary = units[int(experience["unit"])]
	queue.append(
		{
			"kind": "message",
			"unit": unit["id"],
			"text": unit["name"],
			"secondLine": "升级",
			"durationUnits": 1500
		}
	)
	var growth: Dictionary = {
		"kind": "growth",
		"unit": unit["id"],
		"level": experience["level"],
		"before": [],
		"after": [],
		"increments": []
	}
	for stat: String in GROWTH_ORDER:
		var after: int = int(unit[stat] if stat in ["maxHp", "move"] else unit["attributes"][stat])
		var increment: int = int(experience["growth"].get(stat, 0))
		growth["before"].append(after - increment)
		growth["after"].append(after)
		growth["increments"].append(increment)
	queue.append(growth)
	return queue + expiry


func _init(step: Dictionary) -> void:
	kind = step["kind"]
	match kind:
		"message":
			_remaining_units = int(step["durationUnits"])
		"experience":
			experience = int(step["before"])
			_target = experience + int(step["amount"])
		"growth":
			for index: int in range(8):
				values.append(int(step["before"][index]))
				_after.append(int(step["after"][index]))
				_pending.append(int(step["increments"][index]))
		_:
			push_error("Unknown postbattle presentation: " + kind)
			finished = true


func advance() -> void:
	if finished:
		return
	tick += 1
	changed_index = -1
	if _remaining_units >= 0:
		if _remaining_units > 0:
			_remaining_units -= LOGIC_UNITS
		else:
			finished = true
		return
	if kind == "experience":
		var increment: int = floori(float(_target - experience) / 4)
		increment = 4 if increment <= 0 else mini(increment, 10)
		experience = mini(_target, experience + increment)
		if experience == _target:
			_remaining_units = 300
	elif kind == "growth":
		_growth_age += 1
		if _growth_age == 8:
			for index: int in range(_pending.size()):
				if _pending[index] != 0:
					changed_index = index
					values[index] = _after[index]
					_pending[index] = 0
					break
			if changed_index < 0:
				_remaining_units = 500
			_growth_age = 0
