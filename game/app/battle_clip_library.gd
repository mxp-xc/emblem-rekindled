extends RefCounted

const Combat = preload("res://gameplay/combat_rules.gd")
const NativeScene = preload("res://features/battle/native_scene_clock.gd")
var _catalog: Dictionary
var _art: Dictionary
var _directory: String
var _terrain: Array
var _combat: RefCounted
var _cache: Dictionary = {}
var _broken_groups: Dictionary = {}


func _init(content: Dictionary) -> void:
	rebind(content)
	_combat = Combat.new(content["rules"], content["map"]["terrain"])


# Current unit aliases change; chapter action/defense groups and their clips do not.
func rebind(content: Dictionary) -> void:
	_catalog = content["battleClips"]
	_art = content["battleArt"]
	_directory = content["entry"]["resourceDirectory"]
	_terrain = content["map"]["terrain"]


static func validate_art(art: Dictionary, directory: String, terrain: Array) -> bool:
	var verified_textures: Dictionary = {}
	for key: String in ["appearances", "terrainBackgrounds", "backgrounds"]:
		if not art.get(key) is Dictionary or art[key].is_empty():
			return false
	for appearance: Variant in art["appearances"].values():
		if not appearance is Dictionary or appearance.get("nativeSide") not in ["left", "right"]:
			return false
		if not _frames_valid(appearance.get("frames"), directory, 1, verified_textures):
			return false
	for row: Array in terrain:
		for cell: Variant in row:
			var reference: Variant = art["terrainBackgrounds"].get(str(int(cell)))
			if not reference is String or not art["backgrounds"].has(reference):
				return false
	for background: Variant in art["backgrounds"].values():
		if (
			not background is Dictionary
			or not _frames_valid(background.get("frames"), directory, 3, verified_textures)
		):
			return false
	return true


static func _frames_valid(
	frames: Variant, directory: String, minimum: int, verified_textures: Dictionary
) -> bool:
	if not frames is Array or frames.size() < minimum:
		return false
	for frame: Variant in frames:
		if not frame is Dictionary or not frame.get("texture") is String:
			return false
		var path: String = directory.path_join(frame["texture"])
		if not verified_textures.has(path):
			if not ResourceLoader.exists(path):
				return false
			verified_textures[path] = true
		if not _integer(frame.get("offsetX")) or not _integer(frame.get("offsetY")):
			return false
	return true


static func validate_catalog(value: Variant, directory: String, art: Dictionary) -> bool:
	if (
		not value is Dictionary
		or value.get("tickMillis") != 65
		or value.get("logicTickUnits") != 50
	):
		return false
	for key: String in [
		"appearances", "actionGroups", "defenseGroups", "clips", "deaths", "textures"
	]:
		if not value.get(key) is Dictionary or (key != "clips" and value[key].is_empty()):
			return false
	for texture: Variant in value["textures"].values():
		if (
			not texture is Dictionary
			or not texture.get("texture") is String
			or not ResourceLoader.exists(directory.path_join(texture["texture"]))
		):
			return false
	for group: Variant in value["actionGroups"].values():
		if (
			not group is Dictionary
			or not group.get("frames") is Array
			or group["frames"].is_empty()
			or not group.get("thrown") is bool
			or not group.get("lance") is bool
		):
			return false
	for group: Variant in value["defenseGroups"].values():
		if (
			not group is Dictionary
			or not group.get("frames") is Array
			or group["frames"].is_empty()
		):
			return false
	for death: Variant in value["deaths"].values():
		if not death is Dictionary or not death.get("ticks") is Array:
			return false
		for tick: Variant in death["ticks"]:
			if not tick is Array:
				return false
			for layer: Variant in tick:
				if not _effect_valid(layer, value["textures"]):
					return false
	var required: Dictionary = {}
	for key: String in value["appearances"]:
		if not art["appearances"].has(key):
			return false
	for key: String in art["appearances"]:
		var appearance: Variant = value["appearances"].get(key)
		if not appearance is Dictionary or not appearance.get("canAttack") is bool:
			return false
		if (
			not value["defenseGroups"].has(appearance.get("defenseGroup"))
			or not value["deaths"].has(appearance.get("defenseGroup"))
		):
			return false
		if appearance["canAttack"] and not value["actionGroups"].has(appearance.get("actionGroup")):
			return false
		var frame_count: int = art["appearances"][key]["frames"].size()
		if value["defenseGroups"][appearance["defenseGroup"]]["frames"].size() != frame_count:
			return false
		if (
			appearance["canAttack"]
			and value["actionGroups"][appearance["actionGroup"]]["frames"].size() != frame_count
		):
			return false
	for attacker: String in value["appearances"]:
		var action: Dictionary = value["appearances"][attacker]
		if not action["canAttack"]:
			continue
		var projectile: Dictionary = art["appearances"][attacker].get("projectile", {})
		var generated: bool = true
		for outcome: String in ["miss", "hit", "critical"]:
			generated = (
				generated
				and _can_generate(value["actionGroups"][action["actionGroup"]], outcome, projectile)
			)
		if generated:
			continue
		for defender: String in value["appearances"]:
			if (
				art["appearances"][attacker]["nativeSide"]
				== art["appearances"][defender]["nativeSide"]
			):
				continue
			var prefix: String = (
				action["actionGroup"] + "/" + value["appearances"][defender]["defenseGroup"]
			)
			if not required.has(prefix):
				required[prefix] = {"miss": true, "hit": true, "critical": true}
			for outcome: String in ["miss", "hit", "critical"]:
				required[prefix][outcome] = (
					required[prefix][outcome]
					and _can_generate(
						value["actionGroups"][action["actionGroup"]], outcome, projectile
					)
				)
	for prefix: String in required:
		for slot: int in range(2):
			for outcome: String in ["hit", "miss", "critical"]:
				if required[prefix][outcome]:
					continue
				var path: Variant = value["clips"].get("%s/%d/%s" % [prefix, slot, outcome])
				if not path is String or not FileAccess.file_exists(directory.path_join(path)):
					return false
	return true


func preload_pair(preview: Dictionary) -> Dictionary:
	var participants: Array = preview["participants"]
	for slot: int in range(2):
		var actor: Dictionary = participants[slot]
		if not preview["forecasts"][str(int(actor["id"]))]["canAttack"]:
			continue
		var attacker: String = _appearance(actor)
		var defender: String = _appearance(participants[1 - slot])
		var group: String = _catalog["appearances"][attacker]["actionGroup"]
		var groups: Array[String] = [group]
		if _catalog["actionGroups"][group]["thrown"] or _catalog["actionGroups"][group]["lance"]:
			groups.append(_ordinary_group(group))
		for action_group: String in groups:
			for outcome: String in ["hit", "miss", "critical"]:
				var projectile: Dictionary = _art["appearances"][attacker].get("projectile", {})
				if _can_generate(_catalog["actionGroups"][action_group], outcome, projectile):
					continue
				var key: String = (
					"%s/%s/%d/%s"
					% [
						action_group,
						_catalog["appearances"][defender]["defenseGroup"],
						slot,
						outcome
					]
				)
				var loaded: Dictionary = _read_clip(key)
				if not loaded["ok"]:
					return loaded
	return {"ok": true}


func prepare(result: Dictionary) -> Dictionary:
	var appearances: Dictionary = {}
	for actor: Dictionary in result["participants"]:
		appearances[str(int(actor["id"]))] = _appearance(actor)
	var timelines: Array[Dictionary] = []
	var initiator: int = int(result["participants"][0]["id"])
	for strike: Dictionary in result["strikes"]:
		var attacker: String = appearances[str(int(strike["attacker"]))]
		var defender: String = appearances[str(int(strike["defender"]))]
		var action: String = _catalog["appearances"][attacker]["actionGroup"]
		if (
			int(result["resolvedWeapons"][str(int(strike["attacker"]))])
			!= attacker.get_slice(":", 1).to_int()
		):
			action = _ordinary_group(action)
		var outcome: String = (
			"miss" if not strike["hit"] else ("critical" if strike["critical"] else "hit")
		)
		var slot: int = 0 if int(strike["attacker"]) == initiator else 1
		var key: String = (
			"%s/%s/%d/%s"
			% [action, _catalog["appearances"][defender]["defenseGroup"], slot, outcome]
		)
		var projectile: Dictionary = _art["appearances"][attacker].get("projectile", {})
		var generated: bool = _can_generate(_catalog["actionGroups"][action], outcome, projectile)
		var clip: Dictionary = {}
		if not generated:
			var loaded: Dictionary = _read_clip(key)
			if not loaded["ok"]:
				return loaded
			clip = loaded["clip"]
		timelines.append(
			{
				"clip": clip,
				"generated": generated,
				"sourceSlot": slot,
				"strike": strike,
				"actionGroup": action,
				"defenseGroup": _catalog["appearances"][defender]["defenseGroup"],
				"projectile": projectile
			}
		)
	return {
		"ok": true,
		"participants": result["participants"],
		"appearances": appearances,
		"timelines": timelines,
		"actionGroups": _catalog["actionGroups"],
		"defenseGroups": _catalog["defenseGroups"],
		"battleEffects": _art.get("effects", {}),
		"battleArt": _art,
		"mapTerrain": _terrain,
		"stageGeometry": {"viewport": _catalog["viewport"], "stage": _catalog["stage"]},
		"deaths": _catalog["deaths"],
		"tickMillis": _catalog["tickMillis"],
		"logicTickUnits": _catalog["logicTickUnits"]
	}


static func _can_generate(action: Dictionary, outcome: String, projectile: Dictionary) -> bool:
	return (
		NativeScene.supports(action, outcome)
		and (not action["thrown"] or not projectile.is_empty())
	)


func _appearance(actor: Dictionary) -> String:
	return "%d:%d" % [actor["id"], _combat.weapon_id(actor)]


func _ordinary_group(key: String) -> String:
	if _broken_groups.has(key):
		return _broken_groups[key]
	var original: Dictionary = _catalog["actionGroups"][key]
	if not original["thrown"] and not original["lance"]:
		return key
	var signature: Dictionary = original.duplicate(true)
	signature.erase("thrown")
	signature.erase("lance")
	for candidate: String in _catalog["actionGroups"]:
		var definition: Dictionary = _catalog["actionGroups"][candidate].duplicate(true)
		if definition["thrown"] or definition["lance"]:
			continue
		definition.erase("thrown")
		definition.erase("lance")
		if definition == signature:
			_broken_groups[key] = candidate
			return candidate
	return ""


func _read_clip(key: String) -> Dictionary:
	if _cache.has(key):
		return {"ok": true, "clip": _cache[key]}
	if not _catalog["clips"].has(key):
		return {"ok": false, "error": "缺少战斗动作: " + key}
	var path: String = _directory.path_join(_catalog["clips"][key])
	var clip: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if (
		not _valid_clip(clip)
		or int(clip["sourceSlot"]) != key.get_slice("/", 2).to_int()
		or clip["outcome"] != key.get_slice("/", 3)
	):
		return {"ok": false, "error": "战斗动作无法读取或引用无效: " + path}
	var counts: Dictionary = {
		"attacker": _catalog["actionGroups"][key.get_slice("/", 0)]["frames"].size(),
		"defender": _catalog["defenseGroups"][key.get_slice("/", 1)]["frames"].size()
	}
	for tick: Dictionary in clip["ticks"]:
		for layer: Dictionary in tick["layers"]:
			if layer.has("actor") and int(layer["frame"]) >= counts[layer["actor"]]:
				return {"ok": false, "error": "战斗动作引用不存在的人物帧: " + path}
	_cache[key] = clip
	return {"ok": true, "clip": clip}


func _valid_clip(clip: Variant) -> bool:
	if not clip is Dictionary or not clip.get("ticks") is Array or clip["ticks"].is_empty():
		return false
	if not _integer(clip.get("sourceSlot")) or not _integer(clip.get("completionWaitUnits")):
		return false
	if int(clip["sourceSlot"]) not in [0, 1] or int(clip["completionWaitUnits"]) not in [150, 500]:
		return false
	if clip.get("outcome") not in ["hit", "miss", "critical"]:
		return false
	for field: String in ["impactTick", "settleTick"]:
		if not _integer(clip.get(field)):
			return false
		var minimum: int = -1 if field == "impactTick" and clip["outcome"] == "miss" else 0
		if clip[field] < minimum or clip[field] >= clip["ticks"].size():
			return false
	if not clip.get("effectTailTicks") is Array or not clip.get("terrainPlacement") is Dictionary:
		return false
	for role: String in ["attacker", "defender"]:
		var placement: Variant = clip["terrainPlacement"].get(role)
		if not placement is Dictionary:
			return false
		for field: String in [
			"x", "y", "clipWidth", "clipHeight", "tileCount", "tileWidth", "offsetX", "markedTile"
		]:
			if not _integer(placement.get(field)):
				return false
		if (
			placement["clipWidth"] <= 0
			or placement["clipHeight"] <= 0
			or placement["tileCount"] != 3
			or placement["tileWidth"] <= 0
			or placement["markedTile"] < 0
			or placement["markedTile"] > 2
		):
			return false
	for tick: Variant in clip["ticks"]:
		if (
			not tick is Dictionary
			or not tick.get("layers") is Array
			or not tick.get("sky") is Dictionary
			or not _catalog["textures"].has(tick["sky"].get("texture"))
		):
			return false
		for field: String in ["attackerState", "attackerStep"]:
			if not _integer(tick.get(field)):
				return false
		for field: String in ["x", "y"]:
			if not _integer(tick["sky"].get(field)):
				return false
		if not tick.has("flash"):
			return false
		if (
			tick["flash"] != null
			and (not _integer(tick["flash"]) or tick["flash"] < 0 or tick["flash"] > 16777215)
		):
			return false
		if not tick.get("backgroundOffset") is Array or tick["backgroundOffset"].size() != 2:
			return false
		for offset: Variant in tick["backgroundOffset"]:
			if not _integer(offset):
				return false
		for layer: Variant in tick["layers"]:
			if not _valid_layer(layer):
				return false
	for tick: Variant in clip["effectTailTicks"]:
		if not tick is Array:
			return false
		for layer: Variant in tick:
			if not _valid_layer(layer):
				return false
	return true


func _valid_layer(layer: Variant) -> bool:
	if (
		not layer is Dictionary
		or not _integer(layer.get("x"))
		or not _integer(layer.get("y"))
		or not layer.get("foreground") is bool
	):
		return false
	if layer.has("actor"):
		return (
			layer["actor"] in ["attacker", "defender"]
			and _integer(layer.get("frame"))
			and layer["frame"] >= 0
			and layer.get("visible") is bool
		)
	return _effect_valid(layer, _catalog["textures"])


static func _effect_valid(layer: Variant, textures: Dictionary) -> bool:
	return (
		layer is Dictionary
		and _integer(layer.get("x"))
		and _integer(layer.get("y"))
		and layer.get("foreground") is bool
		and textures.has(layer.get("texture"))
		and _integer(layer.get("instance"))
	)


static func _integer(value: Variant) -> bool:
	return (
		(value is int or value is float)
		and is_finite(float(value))
		and float(value) == floorf(float(value))
	)
