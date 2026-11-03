extends SceneTree

const Rewards = preload("res://features/battle/reward_timeline.gd")
const Teleport = preload("res://features/battle/teleport_timeline.gd")
const TeleportPlayer = preload("res://features/battle/teleport_player.gd")
var _scene: Control


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	root.size = Vector2i(1280, 720)
	_scene = load("res://app/main.tscn").instantiate()
	root.add_child(_scene)
	await process_frame
	_scene.title_screen.prologue.hide()
	_scene.resume_battle(_scene.battle)
	if not _messages() or not _promotions() or not _teleport_timing():
		return
	if not await _summary() or not await _map_players():
		return
	_scene.queue_free()
	await process_frame
	print(
		"PASS m10 feedback: actual gold/fruit/repair, merged promotion, teleport gate and visible revival"
	)
	quit(0)


func _messages() -> bool:
	var interface: Dictionary = _scene.content["interface"]
	var actors: Array = _scene.battle.snapshot()["units"]
	var gold: Array = Rewards.sequence(
		{"actor": 0, "kind": "use_item", "effect": "gold", "rolledGold": 3000, "creditedGold": 9},
		actors,
		interface,
		true
	)
	if not _expect(
		gold.size() == 1 and gold[0]["secondLine"] == "9金",
		"Gold feedback shows actual credited amount, never discarded roll"
	):
		return false
	for after: int in [30, 32]:
		var fruit: Array = Rewards.sequence(
			{
				"actor": 0,
				"kind": "use_item",
				"effect": "attribute",
				"templateId": 68,
				"stat": "strength",
				"statBefore": 32,
				"statAfter": after
			},
			actors,
			interface,
			true
		)
		if not _expect(
			(
				fruit[0]["secondLine"] == "力量 32→%d" % after
				and fruit[0].get("noticeIcon") == "item_10"
			),
			"Fruit shows actual decrease or unchanged value"
		):
			return false
	var repair: Array = Rewards.sequence(
		{
			"actor": 9,
			"target": 0,
			"kind": "repair",
			"repairedItem": {"id": "opaque repaired", "templateId": 65},
			"durabilityBefore": 1,
			"durabilityAfter": 4,
			"expiredItem": {"templateId": 57}
		},
		actors,
		interface,
		true
	)
	if not _expect(
		(
			repair.size() == 2
			and repair[0]["text"] == interface["items"]["65"]["name"]["text"]
			and repair[0]["secondLine"] == "修复"
			and repair[0]["durationUnits"] == 1200
			and repair[0]["unit"] == 0
			and repair[1]["unit"] == 9
		),
		"Repair target message precedes caster staff expiry"
	):
		return false
	var revival: Array = Rewards.sequence(
		{"revivals": [{"unit": 0, "expiredItem": {"templateId": 80}}, {"unit": 10}]},
		actors,
		interface,
		true
	)
	return _expect(
		(
			revival.size() == 1
			and revival[0]["text"] == interface["items"]["80"]["name"]["text"] + "消失"
		),
		"Only player revival expiry is shown, even though80 is a single-use passive"
	)


func _promotion() -> Dictionary:
	return {
		"unit": 0,
		"classBefore": 0,
		"classAfter": 1,
		"equipMaskBefore": 1,
		"equipMaskAfter": 5,
		"increments":
		{
			"strength": 2,
			"skill": 1,
			"speed": 1,
			"defense": 1,
			"magic": 0,
			"luck": 2,
			"maxHp": 4,
			"move": 1
		}
	}


func _actors() -> Array:
	var actors: Array = _scene.battle.snapshot()["units"]
	for actor: Dictionary in actors:
		if int(actor["id"]) != 0:
			continue
		actor["level"] = 10
		actor["experience"] = 7
		for stat: String in _promotion()["increments"]:
			if stat in ["maxHp", "move"]:
				actor[stat] += int(_promotion()["increments"][stat])
			else:
				actor["attributes"][stat] += int(_promotion()["increments"][stat])
	return actors


func _promotions() -> bool:
	var actors: Array = _actors()
	var manual: Array = Rewards.sequence(
		{"kind": "use_item", "effect": "promotion", "promotion": _promotion()},
		actors,
		_scene.content["interface"],
		true
	)
	if not _expect(
		(
			manual.size() == 1
			and manual[0]["kind"] == "summary"
			and manual[0]["rows"][0]["newEquipment"] == "斧"
			and manual[0]["rows"][0]["newEquipmentIcons"][0]["id"] == "item_3"
			and manual[0]["rows"][0]["classBeforeName"] == "国王"
			and manual[0]["rows"][0]["classAfterName"] == "复国王"
		),
		"Manual promotion uses one merged summary with class transition and new equipment"
	):
		return false
	var award: Dictionary = {
		"unit": 0,
		"before": 99,
		"after": 7,
		"amount": 8,
		"level": 10,
		"growth": {"strength": 1},
		"promotion": _promotion()
	}
	var automatic: Array = Rewards.sequence(
		{"rewards": {"experience": award}}, actors, _scene.content["interface"], true
	)
	var row: Dictionary = automatic[0]["rows"][0]
	return _expect(
		(
			automatic.size() == 1
			and row["increments"][1] == 3
			and row["after"][1] - row["before"][1] == 3
			and row["promotion"]["increments"]["strength"] == 2
			and row["newEquipmentIcons"][0]["id"] == "item_3"
		),
		"Automatic growth plus promotion combines deltas and retains fixed promotion facts"
	)


func _teleport_timing() -> bool:
	var model: RefCounted = Teleport.new()
	var phases: Array[int] = [model.circle_phase]
	for tick: int in range(1, 11):
		model.advance()
		phases.append(model.circle_phase)
		if not _expect(
			model.finished == (tick == 10), "Teleport never ends at the six-effect-update boundary"
		):
			return false
	return _expect(
		phases == [0, 0, 1, 1, 2, 2, -1, -1, -1, -1, -1],
		"Three native circle phases last two50-unit updates each, with a ten-update action gate"
	)


func _summary() -> bool:
	var queue: Array = Rewards.sequence(
		{"promotion": _promotion()}, _actors(), _scene.content["interface"], true
	)
	_scene.action_feedback.show()
	var summary: Control = _scene.action_feedback.summary
	summary.present(queue[0]["rows"])
	await process_frame
	if not _expect(
		(
			summary.get("_details").text.contains("国王→复国王")
			and summary.get("_details").text.contains("新增装备：斧")
			and summary.get("_attributes").get_child(0).text.contains("转职 +4")
			and summary.find_child("Equipment_item_3", true, false).texture != null
		),
		"Promotion panel shows all fixed deltas immediately, without individual waits"
	):
		return false
	for viewport: Vector2i in [Vector2i(1280, 720), Vector2i(720, 1280), Vector2i(480, 720)]:
		root.size = viewport
		for frame: int in range(8):
			await process_frame
		if not _expect(
			(
				_scene.action_feedback.get("_content_area").encloses(
					summary.panel.get_global_rect()
				)
				and summary.panel.get_global_rect().encloses(
					summary.get("_heading").get_global_rect()
				)
				and summary.panel.get_global_rect().encloses(
					summary.get("_confirm").get_global_rect()
				)
			),
			"Promotion summary stays in map area across rotation"
		):
			return false
	for area: Rect2 in [Rect2(160, 20, 440, 420), Rect2(160, 20, 320, 420)]:
		_scene.action_feedback.set_content_area(area)
		for frame: int in range(8):
			await process_frame
		var scroll: ScrollContainer = summary.get("_scroll")
		var reachable: Array[Control] = [summary.get("_details"), summary.get("_equipment")]
		for attribute: Control in summary.get("_attributes").get_children():
			reachable.append(attribute)
		for control: Control in reachable:
			scroll.ensure_control_visible(control)
			await process_frame
			if not _expect(
				(
					scroll.get_global_rect().encloses(control.get_global_rect())
					and area.encloses(summary.panel.get_global_rect())
					and summary.panel.get_global_rect().encloses(
						summary.get("_confirm").get_global_rect()
					)
				),
				"Short map area keeps fixed confirmation and every promotion detail scroll-reachable"
			):
				return false
	summary.confirm()
	return true


func _map_players() -> bool:
	var committed: Dictionary = _scene.battle.snapshot()
	var target: Dictionary = _scene.battle.unit(0).duplicate(true)
	var teleport: Control = TeleportPlayer.new()
	_scene.add_child(teleport)
	teleport.setup(_scene.content, _scene.map)
	var destination := Vector2i(3, 3)
	teleport.play(
		{
			"kind": "teleport",
			"target": 0,
			"from": Vector2i(target["x"], target["y"]),
			"to": destination
		}
	)
	teleport.set_process(false)
	if not _expect(
		teleport.playing and _shown(0)["x"] == 3 and _shown(0)["y"] == 3 and _shown(0)["visible"],
		"Teleport exposes its final location at ag0 and never hides target"
	):
		return false
	for tick: int in range(10):
		teleport._process(float(_scene.content["battleClips"]["tickMillis"]) / 1000)
	if not _expect(
		not teleport.playing and _scene.battle.snapshot() == committed,
		"Teleport gate ends without applying business a second time"
	):
		return false
	_scene.map.set_units(committed["units"])
	target["hp"] = target["maxHp"]
	var player: Control = _scene.retirement_player
	player.play_revival(target, {"unit": 0, "hpBefore": 0, "hpAfter": target["maxHp"]})
	player.set_process(false)
	if not _expect(
		_shown(0)["visible"] and _shown(0)["hp"] == 0,
		"Revival keeps the unit visible while smoke overlays HP0"
	):
		return false
	for tick: int in range(7):
		player._process(float(_scene.content["battleClips"]["tickMillis"]) / 1000)
	if not _expect(
		(
			not player.playing
			and _shown(0)["visible"]
			and _shown(0)["hp"] == target["maxHp"]
			and _scene.battle.snapshot() == committed
		),
		"Revival finishes visible/full HP without mutating domain state"
	):
		return false
	teleport.queue_free()
	return true


func _shown(identity: int) -> Dictionary:
	for actor: Dictionary in _scene.map.content["units"]:
		if int(actor["id"]) == identity:
			return actor
	return {}


func _expect(value: bool, message: String) -> bool:
	if not value:
		push_error(message)
		quit(1)
	return value
