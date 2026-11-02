extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const TacticalMap = preload("res://features/tactical_map/tactical_map.gd")
const StoryPlayer = preload("res://features/dialogue/story_player.gd")
const BattleClips = preload("res://app/battle_clip_library.gd")
const PixelTheme = preload("res://ui/pixel_theme.gd")
const Combat = preload("res://gameplay/combat_rules.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"
var _failed: bool = false
var _draws: int = 0
var _completed: bool = false


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var opened: Dictionary = Session.new().open(CHAPTER, "", {"new": true}, _roll)
	if not _check(opened["ok"], "The fixture requires the real chapter and actor resources"):
		quit(1)
		return
	var content: Dictionary = opened["content"]
	var battle: RefCounted = opened["battle"]
	var authority: Dictionary = battle.snapshot()
	var draws: int = _draws
	var families: Array[Dictionary] = []
	var combat: RefCounted = Combat.new(content["rules"], content["map"]["terrain"])
	var first_action: String = ""
	for actor: Dictionary in authority["units"]:
		var alias: String = "%d:%d" % [actor["id"], combat.weapon_id(actor)]
		if actor["faction"] != 2 or not content["battleClips"]["appearances"][alias]["canAttack"]:
			continue
		var action: String = content["battleClips"]["appearances"][alias]["actionGroup"]
		if (
			families.is_empty()
			or (actor["sprite"] != families[0]["sprite"] and action != first_action)
		):
			families.append(actor)
			first_action = action
		if families.size() == 2:
			break
	if not _check(families.size() == 2, "Two real enemy families must have distinct sprites"):
		quit(1)
		return
	var original: Dictionary = _bound(content, families[0], 105)
	var replacement: Dictionary = _bound(content, families[1], 105)
	var host := Control.new()
	host.size = Vector2(720, 720)
	host.theme = PixelTheme.new().create(
		content["interface"], content["entry"]["resourceDirectory"]
	)
	root.add_child(host)
	var map: Control = TacticalMap.new()
	map.size = host.size
	host.add_child(map)
	map.setup(original)
	map.set_process(false)
	var story: Control = StoryPlayer.new()
	host.add_child(story)
	story.setup(original, map)
	story.set_process(false)
	await process_frame
	_cache_rebind(map, original, replacement)
	await _clone_queue(story, map, replacement)
	_check(
		battle.snapshot() == authority and _draws == draws,
		"Presentation must preserve the authority snapshot, coordinates, inventory and RNG"
	)
	host.queue_free()
	await process_frame
	if not _failed:
		print(
			"PASS clone presentation: real family caches, atomic rebind, source queue and authority"
		)
	quit(1 if _failed else 0)


func _cache_rebind(map: Control, original: Dictionary, replacement: Dictionary) -> void:
	map.set_zoom(2.5)
	map.view.focus_cell(Vector2i(5, 7))
	map.view.begin_pointer(Vector2(200, 200), 4)
	map.animation_clock = 12.5
	map.frame_indices[0] = 1
	map.last_ticks[0] = 11.0
	map.selected = Vector2i(5, 7)
	var view: RefCounted = map.view
	var center: Vector2 = view.center
	var viewport := Rect2(view.viewport_origin, view.viewport_size)
	var texture: Texture2D = map.map_texture
	var theme: Theme = map.theme
	var previous: Array = map.animation_frames[105].duplicate()
	var previous_completed: Texture2D = map.completed_frames[105]
	var preserved_frames: Array = map.animation_frames[0]
	var library: RefCounted = BattleClips.new(original)
	var before: Dictionary = library.prepare(_combat_result(original))
	_check(before["ok"], "The first family must resolve a real battle clip")
	var cached: Dictionary = library._cache.duplicate()
	var changed: Array[int] = [105]
	_check(map.rebind_units(replacement, changed)["ok"], "Same-ID family replacement must load")
	library.rebind(replacement)
	var after: Dictionary = library.prepare(_combat_result(replacement))
	_check(after["ok"], "The replacement family must resolve its current battle alias")
	if before["ok"] and after["ok"]:
		_check(
			before["timelines"][0]["actionGroup"] != after["timelines"][0]["actionGroup"],
			"Same unit ID must use the new family's action group"
		)
	for key: String in cached:
		_check(library._cache[key] == cached[key], "Immutable group clips remain reusable")
	var current: Array = map.animation_frames[105]
	_check(
		current[0].get_image().get_data() != previous[0].get_image().get_data(),
		"Map frames must contain the new family's source pixels"
	)
	var definition: Dictionary = replacement["mapAnimations"]["units"]["105"]
	_check(current.size() == definition["frames"].size(), "The full frame set must be replaced")
	for index: int in range(current.size()):
		var source: Texture2D = load(
			replacement["entry"]["resourceDirectory"].path_join(
				definition["frames"][index]["texture"]
			)
		)
		_check(
			current[index].get_image().get_data() == source.get_image().get_data(),
			"Every cached frame must match its real source PNG"
		)
	_check(
		(
			map.completed_frames[105].get_image().get_data()
			!= previous_completed.get_image().get_data()
		),
		"Completed-action drawing must also replace the old family's pixels"
	)
	_check(
		(
			map.view == view
			and map.view.center == center
			and is_equal_approx(map.view.zoom, 2.5)
			and Rect2(view.viewport_origin, view.viewport_size) == viewport
			and view.pointer_id == 4
			and map.map_texture == texture
			and map.theme == theme
			and map.animation_clock == 12.5
			and map.animation_frames[0] == preserved_frames
			and map.frame_indices[0] == 1
			and map.last_ticks[0] == 11.0
			and map.frame_indices[105] == 0
			and map.last_ticks[105] == 12.5
			and map.selected == Vector2i(5, 7)
		),
		"A small rebind must preserve the map, viewport, zoom, gesture, selection and other clocks"
	)
	var invalid: Dictionary = original.duplicate(true)
	invalid["mapAnimations"]["units"]["105"]["completedFrame"]["texture"] = "missing.png"
	var frames: Dictionary = map.animation_frames.duplicate()
	var ticks: Dictionary = map.last_ticks.duplicate()
	var content_before: Dictionary = map.content.duplicate(true)
	var rejected: Array[int] = [0, 105]
	_check(
		not map.rebind_units(invalid, rejected)["ok"], "A bad resource must reject the whole batch"
	)
	_check(
		(
			map.content == content_before
			and map.animation_frames == frames
			and map.last_ticks == ticks
		),
		"A failed batch cannot partially replace valid earlier IDs or content"
	)
	var unknown: Array[int] = [999]
	_check(not map.rebind_units(replacement, unknown)["ok"], "An undeclared current ID is rejected")
	map.view.cancel_pointer()


func _clone_queue(story: Control, map: Control, content: Dictionary) -> void:
	var actors: Array = content["units"].duplicate(true)
	var source: Dictionary = actors[-1]
	source["x"] = 5
	source["y"] = 7
	source["visible"] = true
	for id: int in [106, 107]:
		var actor: Dictionary = source.duplicate(true)
		actor["id"] = id
		actor["x"] = 4 if id == 106 else 5
		actor["visible"] = id != 107
		actors.append(actor)
		content["mapAnimations"]["units"][str(id)] = content["mapAnimations"]["units"]["105"]
	content["units"] = actors
	var changed: Array[int] = [105, 106, 107]
	_check(map.rebind_units(content, changed)["ok"], "All births must be bound before playback")
	map.presentation_hidden_ids.assign([105, 106, 107])
	map.view.focus_cell(Vector2i(5, 7))
	var births: Array = [
		{"unit": 105, "from": Vector2i(5, 7), "to": Vector2i(5, 7), "revealed": true},
		{"unit": 107, "from": Vector2i(5, 7), "to": Vector2i(5, 7), "revealed": false},
		{"unit": 106, "from": Vector2i(5, 7), "to": Vector2i(4, 7), "revealed": true}
	]
	var before: Array = actors.duplicate(true)
	_completed = false
	_play_queue(story, births)
	_check(105 not in map.presentation_hidden_ids, "An unobstructed origin reveals immediately")
	_check(
		106 in map.presentation_hidden_ids and 107 in map.presentation_hidden_ids,
		"Later successful and blocked births remain masked at the first queue entry"
	)
	for update: int in range(12):
		story.advance()
		story.set_battle_area(Rect2(0, 0, 640 + update, 720))
		story.tick()
		_check(
			106 in map.presentation_hidden_ids and not _completed,
			"Input and layout cannot skip the gate"
		)
	story.tick()
	_check(107 in map.presentation_hidden_ids, "A blocked birth cannot release its hidden mask")
	for update: int in range(12):
		story.tick()
		_check(
			106 in map.presentation_hidden_ids,
			"Blocked births retain their own thirteen-update queue gate"
		)
	story.tick()
	_check(
		106 not in map.presentation_hidden_ids, "The next birth begins only after the blocked gate"
	)
	_check(
		map.presentation_positions.get(106) == Vector2(5, 7),
		"A moving clone starts at the construction origin while authority reserves its destination"
	)
	await create_timer(float(content["battleClips"]["tickMillis"]) / 1000 * 2.5).timeout
	_check(
		map.presentation_positions.get(106) == Vector2(4, 7) and not _completed,
		"One-cell movement takes two source updates and does not complete the thirteen-update gate"
	)
	for update: int in range(12):
		story.tick()
		_check(not _completed, "A landed clone still waits until the source queue threshold")
	story.tick()
	_check(
		_completed and 107 in map.presentation_hidden_ids and actors == before,
		"The queue eventually completes, preserves blocked concealment and never mutates authority"
	)
	_check(not story.visible, "The completed queue releases the story overlay")
	_completed = false
	_play_queue(
		story, [{"unit": 107, "from": Vector2i(15, 18), "to": Vector2i(15, 18), "revealed": false}]
	)
	for update: int in range(13):
		story.tick()
	_check(not _completed, "Camera travel cannot count as the fixed queue hold")
	var deadline: int = Time.get_ticks_msec() + 5000
	while story._arrival_queue_updates_remaining == 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(
		story._arrival_queue_updates_remaining == 13, "The source gate starts after focus arrival"
	)
	for update: int in range(12):
		story.tick()
		_check(not _completed, "Camera arrival retains the full thirteen-update queue hold")
	story.tick()
	_check(
		_completed and 107 in map.presentation_hidden_ids,
		"A final blocked birth finishes without revealing"
	)


func _play_queue(story: Control, births: Array) -> void:
	await story.play_unit_arrivals(births)
	_completed = true


func _bound(content: Dictionary, family: Dictionary, id: int) -> Dictionary:
	var result: Dictionary = content.duplicate(true)
	var actor: Dictionary = family.duplicate(true)
	actor["id"] = id
	result["units"] = []
	for source: Dictionary in content["units"]:
		if int(source["id"]) == 0:
			result["units"].append(source.duplicate(true))
	result["units"].append(actor)
	result["mapAnimations"]["units"][str(id)] = (
		content["mapAnimations"]["units"][str(int(family["id"]))].duplicate(true)
	)
	for field: String in ["battleArt", "battleClips"]:
		var aliases: Dictionary = result[field]["appearances"]
		for alias: String in aliases.keys():
			if alias.begins_with(str(id) + ":"):
				aliases.erase(alias)
		for alias: String in content[field]["appearances"]:
			if alias.get_slice(":", 0).to_int() == int(family["id"]):
				aliases["%d:%s" % [id, alias.get_slice(":", 1)]] = (
					content[field]["appearances"][alias].duplicate(true)
				)
	return result


func _combat_result(content: Dictionary) -> Dictionary:
	var enemy: Dictionary = content["units"][-1]
	var hero: Dictionary = content["units"][0]
	var rules: RefCounted = Combat.new(content["rules"], content["map"]["terrain"])
	return {
		"participants": [enemy, hero],
		"resolvedWeapons":
		{"105": rules.weapon_id(enemy), str(int(hero["id"])): rules.weapon_id(hero)},
		"strikes": [{"attacker": 105, "defender": hero["id"], "hit": true, "critical": false}]
	}


func _roll(_limit: int) -> int:
	_draws += 1
	return 0


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_failed = true
		push_error(message)
	return condition
