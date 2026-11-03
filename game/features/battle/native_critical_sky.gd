extends RefCounted


# Rectangles drawn by the original critical wind-up, in native sky coordinates.
static func rectangles(width: int, height: int, remaining: int, offset: Vector2i) -> Array[Array]:
	var band: int = height / 7
	var x: int = offset.x
	var y: int = offset.y
	var result: Array[Array] = [
		[x, y, width, height, 205],
		[x, y + band, width, height - band * 2, 10233],
		[x, y + band * 2, width, height - band * 4, 33023],
		[x, y + band * 3, width, band, 54783]
	]
	var lines: Array
	var center: int = width / 2
	if remaining in [12, 11, 6, 5]:
		lines = [
			[center + 24, 31, 0, false],
			[12, 66, 1, false],
			[center - 22, 44, 2, false],
			[width - 37, 27, 4, false],
			[12, 26, 4, true]
		]
	elif remaining in [10, 9, 4, 3]:
		lines = [
			[width - 23, 23, 0, false],
			[center - 35, 63, 1, false],
			[width - 44, 44, 2, false],
			[0, 27, 4, false],
			[36, 26, 4, true]
		]
	else:
		lines = [
			[10, 52, 0, false],
			[width - 43, 43, 1, false],
			[0, 27, 2, false],
			[center - 10, 27, 4, false],
			[width - 52, 26, 4, true]
		]
	for line: Array in lines:
		var line_y: int = band * int(line[2]) + (0 if line[3] else (band >> 1) - 1)
		result.append([x + int(line[0]), y + line_y, int(line[1]), 2, 8773628])
	return result
