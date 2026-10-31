extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	if not scene.has_method("_play_minutes"):
		fail("New games need a foreground play clock for the source record duration")
		return
	scene.set_process(false)
	scene.title_screen.prologue.skip()
	for update: int in range(7):
		scene.title_screen.tick()
	scene.start_new_game()
	scene._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	if scene._play_minutes() != 0:
		fail("Starting a new game resets its cumulative duration")
		return
	scene._process(125)
	if scene._play_minutes() != 2:
		fail("Foreground story/menu time must contribute to the record's H:MM")
		return
	scene._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	scene._process(600)
	if scene._play_minutes() != 2:
		fail("Background time must not count toward the play duration")
		return
	scene._notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	scene._process(60)
	scene.title_screen.show()
	scene._process(600)
	if scene._play_minutes() != 3:
		fail("Title waiting must not add to the last active game's saved duration")
		return
	var path: String = "user://test_play_clock_%d.json" % Time.get_ticks_usec()
	scene.battle_store = load("res://persistence/battle_store.gd").new(scene.content, path)
	var written: Dictionary = scene.battle_store.write(scene.battle, scene._play_minutes())
	if not written["ok"]:
		fail("The initial stable authority is a valid isolated temporary record fixture")
		return
	scene.load_game()
	if scene._play_minutes() != 3 or scene.title_screen.visible:
		fail("Loading a timed temporary record must resume its saved cumulative duration")
		return
	scene._process(60)
	if scene._play_minutes() != 4:
		fail("Foreground timing must continue after loading, rather than restart at zero")
		return
	scene.battle_store.write(scene.battle)
	scene._show_title()
	scene.load_game()
	if scene._play_minutes() != -1:
		fail("Legacy records without a clock must remain visibly unknown")
		return
	DirAccess.remove_absolute(path)
	scene.queue_free()
	await process_frame
	print(
		"PASS play clock: new game, story/menu foreground, pause/title exclusion, continued load, unknown"
	)
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
