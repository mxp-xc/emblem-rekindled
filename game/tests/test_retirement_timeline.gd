extends SceneTree

const Timeline = preload("res://features/battle/retirement_timeline.gd")
const Player = preload("res://features/battle/retirement_player.gd")
const ContentProjection = preload("res://app/chapter_projection.gd")


func _initialize() -> void:
	var unit: Dictionary = {"id": 83, "x": 11, "y": 20, "hp": 0, "visible": true}
	var before: Dictionary = unit.duplicate(true)
	var effects: Dictionary = {
		"bomb": {"virtualWidth": 24, "virtualHeight": 24, "frames": [{}, {}]},
		"smoke": {"virtualWidth": 13, "virtualHeight": 13, "frames": [{}, {}, {}, {}]}
	}
	var original_effects: Dictionary = effects.duplicate(true)
	var model := Timeline.new(unit, effects)
	if model.effect_frame("bomb") != 0 or model.effect_frame("smoke") != 0:
		fail("Retirement must show the published index-zero frames immediately")
		return
	if model.gate_open or model.finished or model.effect_anchor("bomb") != Vector2(264, 480):
		fail("Bomb's virtual 24-pixel box must be centered on the retiring unit's tile")
		return
	if model.effect_anchor("smoke") != Vector2(264, 480):
		fail("Smoke starts at the unit's original tile origin")
		return
	model.advance()
	if model.effect_frame("bomb") != 0 or model.effect_frame("smoke") != 0:
		fail("The first 50-unit update must retain each effect's first frame")
		return
	if model.effect_anchor("smoke") != Vector2(264, 479):
		fail("Smoke rises one original pixel on every map update, including within a frame")
		return
	model.advance()
	if model.effect_frame("bomb") != 1 or model.effect_frame("smoke") != 1:
		fail("Both effects must advance to the next native index after 100 logical units")
		return
	if model.effect_anchor("smoke") != Vector2(264, 478):
		fail("Smoke motion must not use the slower sprite-frame interval")
		return
	while model.tick < 6:
		model.advance()
	if model.gate_open or model.finished or model.effect_frame("bomb") != -1:
		fail("The one-cycle bomb must end without prematurely opening the seven-update gate")
		return
	model.advance()
	if not model.gate_open or model.finished or model.effect_frame("smoke") != 3:
		fail("Update seven must release the dialogue gate while the smoke's final frame remains")
		return
	if model.effect_anchor("smoke") != Vector2(264, 473):
		fail("The last smoke frame must retain seven native pixels of upward movement")
		return
	model.advance()
	if not model.finished or not model.gate_open or model.effect_frame("smoke") != -1:
		fail("Only update eight completes all four smoke frames; it is separate from the gate")
		return
	model.advance()
	if model.tick != 8 or unit != before or effects != original_effects:
		fail("A completed timeline must stop without mutating its unit or resource definitions")
		return
	# Preserve native integer centering even if a published virtual size is odd.
	var odd: Dictionary = effects.duplicate(true)
	odd["bomb"]["virtualWidth"] = 25
	odd["bomb"]["virtualHeight"] = 27
	var centered := Timeline.new(unit, odd)
	if centered.effect_anchor("bomb") != Vector2(264, 479):
		fail("Bomb centering must follow native integer division for odd virtual dimensions")
		return
	var longer: Dictionary = effects.duplicate(true)
	longer["smoke"]["frames"].append({})
	var tail := Timeline.new(unit, longer)
	while tail.tick < 9:
		tail.advance()
	if not tail.gate_open or tail.finished or tail.effect_frame("smoke") != 4:
		fail("Effect lifetime must follow the published frame count rather than the dialogue gate")
		return
	tail.advance()
	if not tail.finished:
		fail("Every published effect frame must play once and then terminate")
		return
	if not _definitions_valid():
		return
	print(
		"PASS retirement timeline: native frames, anchors, motion, seven-update gate and effect tail"
	)
	quit(0)


func _definitions_valid() -> bool:
	var catalog: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/chapter_1/generated/library/catalog.json")
	)
	var art: Dictionary = ContentProjection.relative_resources(
		{"effects": catalog["scenes"]["scene_0"]["effects"]}
	)
	if not Player.validate_definition(art, "res://"):
		fail("Published bomb and smoke frames must pass the content boundary")
		return false
	var invalid: Array[Dictionary] = []
	var broken: Dictionary = art.duplicate(true)
	broken["effects"].erase("bomb")
	invalid.append(broken)
	broken = art.duplicate(true)
	broken["effects"]["smoke"]["frames"].clear()
	invalid.append(broken)
	for field: String in ["virtualWidth", "virtualHeight"]:
		broken = art.duplicate(true)
		broken["effects"]["bomb"][field] = 0
		invalid.append(broken)
	for field: String in ["width", "height"]:
		broken = art.duplicate(true)
		broken["effects"]["smoke"]["frames"][0][field] += 1
		invalid.append(broken)
		broken = art.duplicate(true)
		broken["effects"]["smoke"]["frames"][0][field] = 0
		invalid.append(broken)
	for field: String in ["offsetX", "offsetY"]:
		broken = art.duplicate(true)
		broken["effects"]["bomb"]["frames"][0][field] = 0.5
		invalid.append(broken)
	broken = art.duplicate(true)
	broken["effects"]["bomb"]["frames"][0].erase("texture")
	invalid.append(broken)
	broken = art.duplicate(true)
	broken["effects"]["bomb"]["frames"][0]["texture"] = "missing_retirement_frame.png"
	invalid.append(broken)
	broken = art.duplicate(true)
	broken["effects"]["bomb"]["frames"][0]["texture"] = "features/battle/retirement_timeline.gd"
	invalid.append(broken)
	for index: int in range(invalid.size()):
		if Player.validate_definition(invalid[index], "res://"):
			fail("Invalid retirement frames must fail before settlement, case " + str(index))
			return false
	return true


func fail(message: String) -> void:
	push_error(message)
	quit(1)
