extends RefCounted

const NEIGHBORS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
var _map: Dictionary
var _alliances: Array


func _init(map: Dictionary, alliances: Array) -> void:
	_map = map
	_alliances = alliances


func field(
	actor: Dictionary, units: Array, origin: Vector2i = Vector2i(-1, -1), allowance: int = -1
) -> Dictionary:
	var costs: Array = _map["movementCosts"][str(int(actor["classGroup"]))]
	if origin.x < 0:
		origin = Vector2i(actor["x"], actor["y"])
	if allowance < 0:
		allowance = int(actor["move"]) + 1
	var remaining: Dictionary = {origin: allowance}
	var queue: Array[Vector2i] = [origin]
	var cursor: int = 0
	while cursor < queue.size():
		var cell: Vector2i = queue[cursor]
		cursor += 1
		for direction: Vector2i in NEIGHBORS:
			var destination := cell + direction
			if not inside(destination):
				continue
			var occupant: Dictionary = unit_at(units, destination)
			if (
				not occupant.is_empty()
				and _alliances[occupant["faction"]] != _alliances[actor["faction"]]
			):
				continue
			var value: int = remaining[cell] - int(costs[destination.y][destination.x])
			if value > int(remaining.get(destination, 0)):
				remaining[destination] = value
				queue.append(destination)
	return remaining


func unit_at(units: Array, cell: Vector2i) -> Dictionary:
	for actor: Dictionary in units:
		if actor["visible"] and actor["hp"] > 0 and Vector2i(actor["x"], actor["y"]) == cell:
			return actor
	return {}


func inside(cell: Vector2i) -> bool:
	return (
		cell.x >= 0 and cell.y >= 0 and cell.x < int(_map["width"]) and cell.y < int(_map["height"])
	)
