extends SceneTree


func _initialize() -> void:
	var path: String = "res://features/battle/healing_timeline.gd"
	if not FileAccess.file_exists(path):
		fail("Healing must use the original map effect and incremental HP clock")
		return
	var script: Script = load(path)
	var model: RefCounted = script.new(20, 30)
	var phases: Array[int] = []
	var health: Array[int] = []
	while not model.finished and model.tick < 100:
		model.advance()
		phases.append(model.circle_phase)
		health.append(model.hp)
	if phases.slice(0, 7) != [0, 0, 1, 1, 2, 2, -1]:
		fail("Original cyan/white circle has three phases of two source updates each")
		return
	if health.slice(0, 7) != [20, 22, 24, 26, 28, 30, 30] or model.tick != 16:
		fail(
			"Ten healing HP must rise by two after the first effect update, then finish at update16"
		)
		return
	model = script.new(3, 30)
	while not model.finished and model.tick < 100:
		model.advance()
	if model.hp != 30 or model.tick != 25:
		fail("Odd healing must cap at committed HP and retain the source ten-update tail")
		return
	model = script.new(30, 30)
	for tick: int in range(12):
		model.advance()
	if not model.finished or model.hp != 30 or model.tick != 12:
		fail("A full-HP staff target still needs the original circle and twelve-update departure")
		return
	print("PASS healing timeline: source circle phases, two HP increments, odd cap and departure")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
