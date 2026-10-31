extends SceneTree


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	var ai_script: Script = load("res://gameplay/tactical_ai.gd")
	if ai_script == null:
		fail("Automatic faction planner is missing")
		return
	var samples: Array = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/fixtures/chapter_1_ai.json")
	)
	for sample: Dictionary in samples:
		var units: Array = sample["units"].duplicate(true)
		var commander: Dictionary = {}
		var actor: Dictionary = {}
		var name: String = sample["case"]
		for current: Dictionary in units:
			if current["id"] == 9:
				commander = current
			if current["id"] == sample.get("actor", -1):
				actor = current
		var ai: RefCounted = ai_script.new(content)
		if name.ends_with("sort"):
			var phase: int = 2 if name == "enemy_sort" else 1
			var expected: Array[int] = []
			for id: Variant in sample["order"]:
				expected.append(int(id))
			if ai.order(units, phase) != expected:
				fail("Original automatic queue mismatch: " + name)
				return
		else:
			var policy: int = (
				(1 if name.contains("follow") else 0) | (4 if name.contains("defend") else 0)
			)
			var plan: Dictionary = ai.plan(actor, units, commander, policy, 1)
			if (
				plan["cell"] != Vector2i(sample["x"], sample["y"])
				or plan["strategic"] != Vector2i(sample["strategicX"], sample["strategicY"])
				or (
					plan["attackTarget"]
					!= int(sample["attackTarget"] if sample["attackTarget"] != null else -1)
				)
				or (
					plan["healTarget"]
					!= int(sample["healTarget"] if sample["healTarget"] != null else -1)
				)
			):
				fail("Original automatic plan mismatch " + name + ": " + str(plan))
				return
	print("PASS AI: original seventeen queue/approach/attack/defend/follow/healing samples")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
