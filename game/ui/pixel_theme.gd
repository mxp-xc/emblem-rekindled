extends RefCounted

const FONT = preload("res://ui/fonts/NotoSansCJKsc-Regular.otf")


static func portrait_area(viewport_size: Vector2) -> Rect2:
	var width: float = minf(viewport_size.x, viewport_size.y * 0.75)
	return Rect2(Vector2((viewport_size.x - width) / 2, 0), Vector2(width, viewport_size.y))


static func sprite_icon(texture: Texture2D) -> Texture2D:
	var used: Rect2i = texture.get_image().get_used_rect()
	if not used.has_area():
		return texture
	var icon := AtlasTexture.new()
	icon.atlas = texture
	icon.region = Rect2(used)
	icon.filter_clip = true
	return icon


static func wrap_text(
	text: String, width: float, font_size: int, font: Font = FONT
) -> PackedStringArray:
	var lines: PackedStringArray = []
	for paragraph: String in text.split("\n"):
		var line: String = ""
		for character: String in paragraph:
			if (
				font.get_string_size(line + character, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
				> width
			):
				lines.append(line)
				line = ""
			line += character
		lines.append(line)
	return lines


func create(interface_data: Dictionary, directory: String) -> Theme:
	var result := Theme.new()
	result.default_font = FONT
	result.default_font_size = 24
	result.set_color("font_color", "Label", Color.WHITE)
	var frame: Dictionary = interface_data["textures"]["window_frame"]
	var texture: Texture2D = load(directory.path_join(frame["texture"]))
	var image: Image = texture.get_image().duplicate()
	image.resize(image.get_width() * 3, image.get_height() * 3, Image.INTERPOLATE_NEAREST)
	var panel := StyleBoxTexture.new()
	panel.texture = ImageTexture.create_from_image(image)
	panel.set_texture_margin_all(15)
	panel.content_margin_left = 24
	panel.content_margin_right = 24
	panel.content_margin_top = 18
	panel.content_margin_bottom = 18
	result.set_stylebox("panel", "PanelContainer", panel)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var row := StyleBoxFlat.new()
		row.bg_color = Color("213347") if state == "normal" else Color("6888a8")
		if state == "disabled":
			row.bg_color = Color("34465d")
		row.content_margin_left = 14
		row.content_margin_right = 14
		row.content_margin_top = 8
		row.content_margin_bottom = 8
		row.border_color = Color("97b0c6")
		row.set_border_width_all(2 if state in ["hover", "focus"] else 0)
		result.set_stylebox(state, "Button", row)
	result.set_color("font_color", "Button", Color.WHITE)
	result.set_color("font_hover_color", "Button", Color("fff7bf"))
	result.set_color("font_pressed_color", "Button", Color("fff7bf"))
	result.set_color("font_disabled_color", "Button", Color("a0a9b8"))
	return result
