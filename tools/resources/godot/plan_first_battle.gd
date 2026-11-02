extends SceneTree


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var loaded: Dictionary = load("res://persistence/battle_store.gd").new(content).decode(record)
	if not loaded["ok"]:
		push_error(JSON.stringify(loaded))
		quit(1)
		return
	if loaded.has("progress"):
		_write(args[2], {"kind": "completed", "progress": loaded["progress"]})
		quit(0)
		return
	var battle: RefCounted = loaded["battle"]
	var ai: RefCounted = load("res://gameplay/tactical_ai.gd").new(content)
	var assignment_record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	var assignments: Dictionary = {}
	if assignment_record.get("round") == battle.round_number:
		for key: String in assignment_record.get("values", {}):
			assignments[int(key)] = int(assignment_record["values"][key])
	for id: int in ai.order(battle.snapshot()["units"], 0):
		var actor: Dictionary = battle.unit(id)
		if not actor["visible"] or actor["hp"] <= 0 or actor["action"] != 0:
			continue
		var before: Dictionary = actor.duplicate(true)
		if id == 0 and actor["hp"] * 2 < actor["maxHp"]:
			var usable: Array = battle.item_options(id).get("use", [])
			for item_index: int in range(usable.size()):
				if usable[item_index]["templateId"] != 60:
					continue
				var healer: Dictionary = battle.unit(9)
				var destination := Vector2i(actor["x"], actor["y"])
				var best_score: int = 100000
				for cell: Vector2i in battle.movement_field(id):
					if not battle.preview_move(id, cell)["ok"]:
						continue
					var near_enemy: int = 1000
					for enemy: Dictionary in battle.snapshot()["units"]:
						if enemy["faction"] == 2 and enemy["hp"] > 0 and enemy["visible"]:
							near_enemy = mini(
								near_enemy, absi(cell.x - enemy["x"]) + absi(cell.y - enemy["y"])
							)
					var score: int = (
						(absi(cell.x - healer["x"]) + absi(cell.y - healer["y"])) * 100 - near_enemy
					)
					if score < best_score:
						best_score = score
						destination = cell
				var steps: int = 0
				if destination != Vector2i(actor["x"], actor["y"]):
					var moved: Dictionary = battle.move_unit(id, destination)
					steps = moved["path"].size() - 1
				var rows: Array[String] = ["information"]
				for key: String in ["attack", "heal", "trade", "inventory", "wait", "cancel_move"]:
					if key in battle.actions_for(id):
						rows.append(key)
				_write(
					args[2],
					{
						"kind": "action",
						"round": battle.round_number,
						"actor": before,
						"destination": [destination.x, destination.y],
						"moveSteps": steps,
						"action": "use_herb",
						"itemIndex": item_index,
						"target": {},
						"menuRows": rows,
						"assignments": {"round": battle.round_number, "values": assignments},
						"equipBeforeMove": ""
					}
				)
				quit(0)
				return
		var plan: Dictionary = ai.plan(
			actor,
			battle.snapshot()["units"],
			battle.unit(battle.commander_id),
			battle.command_policy,
			battle.round_number,
			assignments
		)
		# The player-controlled required healer must not use a disposable NPC's advance policy.
		if id == 9:
			plan = _support_plan(battle)
		if not plan["equipItem"].is_empty():
			battle.equip_unit(id, plan["equipItem"])
		var destination := Vector2i(plan["cell"])
		var move_steps: int = 0
		if destination != Vector2i(actor["x"], actor["y"]):
			var moved: Dictionary = battle.move_unit(id, destination)
			if not moved["ok"]:
				push_error(JSON.stringify(moved))
				quit(1)
				return
			move_steps = moved["path"].size() - 1
		var visible: Array[String] = ["information"]
		var available: Array = battle.actions_for(id)
		for key: String in ["attack", "heal", "trade", "inventory", "wait", "cancel_move"]:
			if key in available:
				visible.append(key)
		var action: String = (
			"attack"
			if plan["attackTarget"] >= 0
			else ("heal" if plan["healTarget"] >= 0 else "wait")
		)
		var target: Dictionary = {}
		var choices: Array = []
		var selected: String = ""
		if action == "attack":
			choices = battle.attack_weapons(id)
			selected = battle.unit(id)["equippedInstanceId"]
			target = battle.unit(int(plan["attackTarget"]))
		elif action == "heal":
			for held: Dictionary in battle.unit(id)["inventory"]:
				if not battle.heal_targets(id, held["id"]).is_empty():
					choices.append({"item": held})
			selected = plan["healItem"]
			target = battle.unit(int(plan["healTarget"]))
		var item_index: int = -1
		for index: int in range(choices.size()):
			if choices[index]["item"]["id"] == selected:
				item_index = index
		if not plan["allocation"].is_empty():
			var allocated: int = int(plan["allocation"]["unit"])
			assignments[allocated] = (
				int(assignments.get(allocated, 0)) + int(plan["allocation"]["power"])
			)
		_write(
			args[2],
			{
				"kind": "action",
				"round": battle.round_number,
				"actor": before,
				"destination": [destination.x, destination.y],
				"moveSteps": move_steps,
				"action": action,
				"target": target,
				"itemIndex": item_index,
				"menuRows": visible,
				"assignments": {"round": battle.round_number, "values": assignments},
				"equipBeforeMove":
				plan["equipItem"] if plan["equipItem"] != before["equippedInstanceId"] else ""
			}
		)
		quit(0)
		return
	_write(args[2], {"kind": "end_turn", "round": battle.round_number})
	quit(0)


func _write(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "  "))
	file.close()


func _support_plan(battle: RefCounted) -> Dictionary:
	var actor: Dictionary = battle.unit(9)
	var hero: Dictionary = battle.unit(0)
	var origin := Vector2i(actor["x"], actor["y"])
	var best_score: int = -1000000
	var result: Dictionary = {
		"cell": origin,
		"attackTarget": -1,
		"healTarget": -1,
		"healItem": "",
		"equipItem": "",
		"allocation": {}
	}
	var units: Array = battle.snapshot()["units"]
	for cell: Vector2i in battle.movement_field(9):
		if not battle.preview_move(9, cell)["ok"]:
			continue
		var margin: int = 100
		for enemy: Dictionary in units:
			if enemy["faction"] == 2 and enemy["hp"] > 0 and enemy["visible"]:
				margin = mini(
					margin,
					absi(cell.x - enemy["x"]) + absi(cell.y - enemy["y"]) - int(enemy["move"]) - 2
				)
		var score: int = (
			margin * 100
			- (absi(cell.x - hero["x"]) + absi(cell.y - hero["y"])) * 3
			- (cell - origin).length_squared()
		)
		if cell != origin:
			battle.move_unit(9, cell)
		var staff: String = ""
		if hero["hp"] < hero["maxHp"]:
			for held: Dictionary in actor["inventory"]:
				if 0 in battle.heal_targets(9, held["id"]):
					staff = held["id"]
					score += 40
					break
		if cell != origin:
			battle.cancel_move()
		if score > best_score:
			best_score = score
			result["cell"] = cell
			result["healTarget"] = 0 if not staff.is_empty() else -1
			result["healItem"] = staff
	return result
