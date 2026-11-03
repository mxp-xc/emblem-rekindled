extends RefCounted

# Native g.ar == 3 raster, captured from its three 24x24 cast-ring phases.
const PIXELS: Array = [
	[
		".....C....",
		"...CCCCC..",
		"..CCCWCCC.",
		".CCWWWWWCC",
		".CCWWWWWCC",
		"CCWWWWWWCC",
		".CCWWWWWCC",
		".CCWWWWWCC",
		"..CCCCCCC.",
		"...CCCCC..",
	],
	[
		"..........C.........",
		"......CCCCCCCCC.....",
		".....CCCCCCCCCCC....",
		"...CCCCWWWWWWWCCCC..",
		"...CCWWWWWWWWWWWCC..",
		"..CCWWWWWWWWWWWWWCC.",
		".CCCWWWWWWWWWWWWWCCC",
		".CCWWWWWWWWWWWWWWWCC",
		".CCWWWWWWWWWWWWWWWCC",
		".CCWWWWWWWWWWWWWWWCC",
		"CCWWWWWWWWWWWWWWWWCC",
		".CCWWWWWWWWWWWWWWWCC",
		".CCWWWWWWWWWWWWWWWCC",
		".CCWWWWWWWWWWWWWWWCC",
		".CCCWWWWWWWWWWWWWCCC",
		"..CCWWWWWWWWWWWWWCC.",
		"...CCWWWWWWWWWWWCC..",
		"...CCCCWWWWWWWCCCC..",
		".....CCCCCCCCCCC....",
		"......CCCCCCCCC.....",
	],
	[
		".......CCCCCCCCCCC......",
		".....CCCCCCCCCCCCCCC....",
		"....CCCC.........CCCC...",
		"...CCC.............CCC..",
		"..CCC...............CCC.",
		".CCC.................CCC",
		".CC...................CC",
		"CCC...................CC",
		"CC.....................C",
		"CC.....................C",
		"CC.....................C",
		"CC.....................C",
		"C......................C",
		"CC.....................C",
		"CC.....................C",
		"CC.....................C",
		"CC.....................C",
		"CCC...................CC",
		".CC...................CC",
		".CCC.................CCC",
		"..CCC...............CCC.",
		"...CCC.............CCC..",
		"....CCCC.........CCCC...",
		".....CCCCCCC.CCCCCCC....",
	],
]

static var _frames: Array = []


static func frames() -> Array:
	if not _frames.is_empty():
		return _frames
	for rows: Array in PIXELS:
		var size: int = rows.size()
		var image: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
		for y: int in range(size):
			var row: String = rows[y]
			for x: int in range(size):
				if row[x] == "C":
					image.set_pixel(x, y, Color.CYAN)
				elif row[x] == "W":
					image.set_pixel(x, y, Color.WHITE)
		_frames.append(
			{
				"texture": ImageTexture.create_from_image(image),
				"offsetX": -(size >> 1),
				"offsetY": -(size >> 1),
				"width": size,
				"height": size,
				"empty": false
			}
		)
	return _frames
