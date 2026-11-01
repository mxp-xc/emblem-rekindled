extends SceneTree

const Content = preload("res://app/chapter_content.gd")
const PixelTheme = preload("res://ui/pixel_theme.gd")
var _directory: String = ""


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var content: Dictionary = Content.new().load_chapter("res://content/chapter_1/chapter.json")
	if not content["ok"]:
		fail("Theme ownership requires the actual chapter texture definitions")
		return
	var path: String = content["entry"]["resourceDirectory"].path_join(
		content["interface"]["textures"]["window_frame"]["texture"]
	)
	var source: Texture2D = load(path)
	var original: Image = source.get_image().duplicate()
	for iteration: int in range(8):
		var theme: Theme = PixelTheme.new().create(
			content["interface"], content["entry"]["resourceDirectory"]
		)
		var actual: Image = source.get_image()
		if actual.get_size() != original.get_size() or actual.get_data() != original.get_data():
			fail(
				(
					"Theme creation changed shared window_frame: %s -> %s"
					% [original.get_size(), actual.get_size()]
				)
			)
			return
		var panel: StyleBoxTexture = theme.get_stylebox("panel", "PanelContainer")
		if panel.texture.get_size() != Vector2(original.get_size()) * 3:
			fail("An owned theme frame must preserve the original three-times pixel scale")
			return
	var owned: String = "user://test_pixel_theme_ownership_%d" % Time.get_ticks_usec()
	if DirAccess.dir_exists_absolute(owned) or DirAccess.make_dir_absolute(owned) != OK:
		fail("Theme adoption tests require a fresh owned record directory")
		return
	_directory = owned
	var scene: Control = load("res://app/main.tscn").instantiate()
	scene.store.path = owned.path_join("settings.json")
	root.add_child(scene)
	await process_frame
	scene.battle_store.path = owned.path_join("continue.json")
	var state: Dictionary = scene.battle.snapshot()
	for iteration: int in range(8):
		scene._adopt_content(scene.content, scene.battle)
		await process_frame
		var actual: Image = source.get_image()
		if (
			actual.get_size() != original.get_size()
			or actual.get_data() != original.get_data()
			or scene.battle.snapshot() != state
		):
			fail(
				"Repeated content adoption cannot grow shared pixels or change the supplied battle"
			)
			return
	scene.queue_free()
	await process_frame
	if not DirAccess.get_files_at(_directory).is_empty() or not _cleanup():
		fail("Theme adoption must not write records")
		return
	print(
		"PASS theme ownership: original shared pixels, fixed 3x scale, eight repeated Main adoptions"
	)
	quit(0)


func _cleanup() -> bool:
	if _directory.is_empty():
		return true
	for name: String in DirAccess.get_files_at(_directory):
		if DirAccess.remove_absolute(_directory.path_join(name)) != OK:
			return false
	if DirAccess.remove_absolute(_directory) != OK:
		return false
	_directory = ""
	return true


func fail(message: String) -> void:
	push_error(message)
	_cleanup()
	quit(1)
