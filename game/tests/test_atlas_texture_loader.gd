extends SceneTree

const Loader = preload("res://app/atlas_texture_loader.gd")
const Bootstrap = preload("res://app/atlas_bootstrap.gd")


func _initialize() -> void:
	var absent: Dictionary = Bootstrap.read_manifest("user://missing-atlas-manifest.json")
	if absent["ok"] or not "user://missing-atlas-manifest.json" in absent["error"]:
		push_error("A missing atlas manifest must be reported with its path")
		quit(1)
		return
	var source := "res://tests/fixtures/native_battle/effect_000.png"
	var logical := "res://__atlas_test/virtual.png"
	var entries: Dictionary = JSON.parse_string(
		JSON.stringify(
			{
				logical: {"texture": source, "region": [0, 0, 2, 2]},
				"res://__atlas_test/invalid.png": {"texture": source, "region": [-1, 0, 2, 2]},
				"res://__atlas_test/missing_atlas.png":
				{"texture": "res://__atlas_test/no_physical_atlas.png", "region": [0, 0, 2, 2]},
				"res://__atlas_test/out_of_bounds.png":
				{"texture": source, "region": [0, 0, 9999, 9999]}
			}
		)
	)
	var loader := Loader.new(entries)
	ResourceLoader.add_resource_format_loader(loader, true)
	var texture: Resource = ResourceLoader.load(logical, "Texture2D")
	var original: Texture2D = load(source)
	if (
		not ResourceLoader.exists(logical, "Texture2D")
		or not texture is Texture2D
		or texture.get_size() != Vector2(2, 2)
		or texture.get_image().get_pixel(0, 0) != original.get_image().get_pixel(0, 0)
		or ResourceLoader.exists("res://__atlas_test/missing.png", "Texture2D")
		or ResourceLoader.exists("res://__atlas_test/invalid.png", "Texture2D")
		or ResourceLoader.exists("res://__atlas_test/missing_atlas.png", "Texture2D")
		or ResourceLoader.exists("res://__atlas_test/out_of_bounds.png", "Texture2D")
		or not ResourceLoader.exists(source, "Texture2D")
	):
		push_error("Atlas paths must load the exact region without inventing missing resources")
		quit(1)
		return
	ResourceLoader.remove_resource_format_loader(loader)
	print("PASS atlas loader: logical path, dimensions, pixels and missing references")
	quit(0)
