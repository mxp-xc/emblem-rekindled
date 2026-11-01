extends SceneTree

const Content = preload("res://app/chapter_content.gd")


func _initialize() -> void:
	var loader := Content.new()
	var effects: Dictionary = {
		"earthquake":
		{
			"kind": "shake",
			"durationUnits": 500,
			"logicalTickUnits": 50,
			"shakeModuli": [10, 3],
			"flashUpdates": 5,
			"flashColor": 0,
			"flashOnEven": true,
			"source": "fixture"
		},
		"fire":
		{
			"kind": "sprite",
			"logicalTickUnits": 50,
			"sequence": [0],
			"cycles": 2,
			"stepUnits": 100,
			"anchor": "bottomCenter",
			"unitOffset": [12, 24],
			"shakeUpdates": 0,
			"jitterRangeX": [-4, 5],
			"jitterRangeY": [-1, 2],
			"source": "fixture",
			"sprite":
			{
				"virtualWidth": 20,
				"virtualHeight": 34,
				"frames":
				[
					{
						"texture": "content/chapter_1/generated/icon.png",
						"offsetX": 0,
						"offsetY": 14,
						"width": 20,
						"height": 20,
						"empty": false
					}
				]
			}
		}
	}
	for candidate: Dictionary in [effects, JSON.parse_string(JSON.stringify(effects))]:
		if not loader._map_effects_valid(candidate, "res://"):
			_fail("Valid effect metadata must survive JSON numeric types")
			return
	for defect: String in [
		"kind",
		"duration",
		"modulus",
		"flash",
		"sequence",
		"step",
		"anchor",
		"jitter",
		"texture",
		"offset",
		"cycles"
	]:
		var broken: Dictionary = effects.duplicate(true)
		match defect:
			"kind":
				broken["fire"]["kind"] = "callback"
			"duration":
				broken["earthquake"]["durationUnits"] = 501
			"modulus":
				broken["earthquake"]["shakeModuli"] = [0, 3]
			"flash":
				broken["earthquake"]["flashUpdates"] = 0.5
			"sequence":
				broken["fire"]["sequence"] = [1]
			"step":
				broken["fire"]["stepUnits"] = 0
			"anchor":
				broken["fire"]["anchor"] = "frameCenter"
			"jitter":
				broken["fire"]["jitterRangeX"] = [5, -4]
			"texture":
				broken["fire"]["sprite"]["frames"][0]["texture"] = "missing_effect.png"
			"offset":
				broken["fire"]["sprite"]["frames"][0]["offsetY"] = null
			"cycles":
				broken["fire"]["cycles"] = 1.5
		if loader._map_effects_valid(broken, "res://"):
			_fail("Invalid map effect must reject before opening: " + defect)
			return
	var item: Dictionary = {
		"id": 46, "damageKind": "magic", "actionMode": "map_attack", "mapEffect": "earthquake"
	}
	var rules: Dictionary = {"itemTemplates": [item]}
	var clips: Dictionary = {"appearances": {"0:46": {"canAttack": false}}}
	if not loader._action_presentations_valid(rules, clips, effects):
		_fail("Map skills must keep their real nonattacking defense appearance")
		return
	if loader._action_presentations_valid(rules, clips, {}):
		_fail("Declared map skills must require their own effect")
		return
	clips["appearances"]["0:46"]["canAttack"] = true
	if loader._action_presentations_valid(rules, clips, effects):
		_fail("A map skill cannot silently become an isolated attack clip")
		return
	item["actionMode"] = "battle_clip"
	clips["appearances"]["0:46"]["canAttack"] = false
	if loader._action_presentations_valid(rules, clips, effects):
		_fail("Ordinary damaging weapons must provide actual attack motion")
		return
	print("PASS map effect content: timing, source frames, JSON, missing effects and action modes")
	quit(0)


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
