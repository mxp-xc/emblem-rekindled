extends SceneTree
const Session = preload("res://app/chapter_session.gd")
const Battle = preload("res://gameplay/battle_state.gd")
var draws: Array[int] = []


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var opened: Dictionary = Session.new().open(
		"res://content/chapter_1/chapter.json", "m0", {"new": true}
	)
	var content: Dictionary = opened["content"].duplicate(true)
	var actor: Dictionary = opened["battle"].unit(0)
	content["map"]["locations"] = [
		{
			"id": "chest_0",
			"sourceIndex": 0,
			"kind": "chest",
			"position": [actor["x"], actor["y"]],
			"tileId": 79,
			"weightedChoices": [{"templateId": 2, "weight": 100}],
			"openedVariant": "opened_chest"
		}
	]
	var costs: Dictionary = {}
	for group: int in range(11):
		costs[str(group)] = 1
	content["map"]["tileVariants"] = {
		"opened_chest":
		{
			"tileId": 88,
			"terrain": 1,
			"texture": content["entry"]["mapTexture"],
			"movementCosts": costs
		}
	}
	var battle: RefCounted = Battle.new(content, _roll)
	draws.clear()
	root.size = Vector2i(720, 1280)
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene._adopt_content(content, battle)
	scene.resume_battle(battle)
	await process_frame
	scene.selected_unit = 0
	scene.unit_panel.present(battle.actions_for(0))
	scene.unit_panel.show()
	await process_frame
	var button: Button = scene.unit_panel.find_child("OpenChest", true, false)
	if button == null or not button.visible or button.text != "打开宝箱":
		fail("Chest action must be a visible menu button")
		return
	var before_back: Dictionary = battle.snapshot()
	scene._handle_back()
	if scene.unit_panel.visible or battle.snapshot() != before_back:
		fail("Back from the chest menu closes it without claiming")
		return
	var selected: Vector2i = scene.map.selected
	var zoom: float = scene.map.view.zoom
	var result: Dictionary = battle.open_chest(0)
	scene.map.set_map_state(battle.map_state())
	scene.map_hud.set_map_state(battle.map_state())
	scene.map_hud.present(Vector2i(actor["x"], actor["y"]))
	if (
		scene.map.content["map"]["tiles"][actor["y"]][actor["x"]] != 88
		or (
			scene.map_hud.terrain_values
			!= {
				"defense": int(content["rules"]["terrainDefense"][1]),
				"avoid": int(content["rules"]["terrainEvasion"][1])
			}
		)
	):
		fail("Map and HUD must consume the same opened projection")
		return
	if scene.map.selected != selected or scene.map.view.zoom != zoom:
		fail("Projection update preserves view and selection")
		return
	# A second live scene projection exercises the committed group through the app.
	var group: Array[int] = []
	for unit: Dictionary in content["units"]:
		if unit["faction"] == 2 and group.size() < 4:
			group.append(int(unit["id"]))
	content["story"]["locationEvents"] = [
		{"locationId": "chest_0", "unitIds": group, "sequence": ""}
	]
	var grouped: RefCounted = Battle.new(content, _roll)
	var hidden: Dictionary = grouped.snapshot()
	for unit: Dictionary in hidden["units"]:
		if unit["id"] in group:
			unit["visible"] = false
			unit["flags"] |= 1
	if not grouped.restore_snapshot(hidden)["ok"]:
		fail("UI group fixture restores")
		return
	scene._adopt_content(content, grouped)
	scene.resume_battle(grouped)
	await process_frame
	result = grouped.open_chest(0)
	scene._present_player_action(result)
	if not scene.busy:
		fail("Committed chest action locks input during presentation")
		return
	for id: int in group:
		if id not in scene.map.presentation_hidden_ids:
			fail("All arrivals are masked before the first committed units projection")
			return
	var revealed: bool = false
	var deadline: int = Time.get_ticks_msec() + 10000
	while scene.busy and Time.get_ticks_msec() < deadline:
		await process_frame
		var count: int = 0
		for id: int in group:
			if id not in scene.map.presentation_hidden_ids:
				count += 1
		if count != 0 and count != 4:
			fail("A location group must reveal all successful arrivals in the same frame")
			return
		if count == 4:
			revealed = true
	if not revealed or scene.busy or scene.unit_panel.visible or not scene.map.selection_enabled:
		fail("Parallel presentation and reward feedback finish back on the battlefield")
		return
	var timeline: Array = preload("res://features/battle/reward_timeline.gd").sequence(
		{
			"ok": true,
			"kind": "open_chest",
			"actor": 0,
			"claimed": false,
			"reason": "WAREHOUSE_FULL"
		},
		grouped.snapshot()["units"],
		content["interface"],
		true
	)
	if timeline.is_empty() or timeline[0].get("text") != "仓库已满":
		fail("Double full must produce an automatic feedback message")
		return
	scene.queue_free()
	await process_frame
	print("PASS chest UI: explicit menu, common map/HUD projection and view preservation")
	quit(0)


func _roll(limit: int) -> int:
	draws.append(limit)
	return 0


func fail(message: String) -> void:
	push_error(message)
	quit(1)
