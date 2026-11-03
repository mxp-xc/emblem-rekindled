extends RefCounted


static func calculate(fighter: Dictionary, background: Dictionary, stage: Dictionary) -> Dictionary:
	var half_width: int = int(stage["viewport"]["width"]) >> 1
	var tile_width: int = int(background["virtualWidth"])
	var frames: Array = background["frames"]
	var tile_count: int = frames.size()
	var side: int = int(fighter["I"])
	var width: int = tile_count * tile_width
	var offset: int = 0
	if width > half_width:
		tile_count = int(ceil(float(half_width) / float(tile_width)))
		width = half_width
		if side == 1:
			offset = half_width - tile_width * tile_count
	var tile_height: int = int(frames[0]["bodyHeight"])
	return {
		"x": half_width - width if side == 0 else half_width,
		"y": int(stage["stage"]["top"]) + int(stage["stage"]["height"]) - tile_height,
		"clipWidth": half_width,
		"clipHeight": tile_height,
		"tileCount": tile_count,
		"tileWidth": tile_width,
		"offsetX": offset,
		"markedTile": 2 if side == 0 else 0
	}
