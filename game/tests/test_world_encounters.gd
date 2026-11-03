extends SceneTree

const Encounters = preload("res://gameplay/world_encounters.gd")
var draws: Array[int] = []
var samples: Array[int] = []


func _initialize() -> void:
	var initial: Dictionary = {"lastCheckMs": 0, "marker": {"node": 3, "classId": 28}}
	for scenario: Array in [[5, false, 10000], [6, true, 10000], [6, false, 9999]]:
		draws.clear()
		var result: Dictionary = Encounters.advance(
			initial, scenario[0], scenario[1], scenario[2], [9, 3, 5], 9, _draw
		)
		if not _check(
			result.get("ok", false) and result["state"] == initial and draws.is_empty(),
			"Progress, movement and time gates make no draws"
		):
			return
	for test: Array in [
		[0, 0, 0, 32, 3],
		[24, 1, 59, 32, 5],
		[25, 0, 0, 28, 3],
		[99, 1, 59, 28, 5],
		[0, 0, 60, -1, -1]
	]:
		samples = [test[0], test[1], test[2]]
		draws.clear()
		var result: Dictionary = Encounters.advance(initial, 6, false, 10000, [9, 5, 3], 9, _draw)
		if not _check(
			(
				result.get("ok", false)
				and draws == [100, 2, 100]
				and result["state"]["lastCheckMs"] == 10000
			),
			"Due check draws in original order and updates timer"
		):
			return
		var marker: Variant = result["state"]["marker"]
		if not _check(
			marker == null if test[3] < 0 else marker == {"node": test[4], "classId": test[3]},
			"Spawn chance, type and sorted completed node match original"
		):
			return
	if not _check(
		initial == {"lastCheckMs": 0, "marker": {"node": 3, "classId": 28}},
		"Input state stays unchanged"
	):
		return
	samples = [0, 0, 100]
	var invalid: Dictionary = Encounters.advance(initial, 6, false, 10000, [3, 5], 9, _draw)
	if not _check(not invalid["ok"] and initial["lastCheckMs"] == 0, "Invalid RNG does not commit"):
		return
	if not _check(
		not Encounters.advance(initial, 6, false, 10000, [9], 9, _draw)["ok"],
		"A due spawn requires another completed node"
	):
		return
	if not _check(
		not Encounters.advance(initial, 6, false, 10000, [3, 3, 9], 9, _draw)["ok"],
		"Duplicate completed nodes are rejected"
	):
		return
	if not _check(
		not (
			Encounters
			. advance(
				{"lastCheckMs": 0, "marker": {"node": 30, "classId": 28}},
				6,
				false,
				10000,
				[3, 9],
				9,
				_draw
			)["ok"]
		),
		"Invalid marker is rejected"
	):
		return
	for test: Array in [[16, 17], [28, 18], [32, 18], [36, 18], [40, 17]]:
		if not _check(
			Encounters.battle_for_class(test[0]) == test[1],
			"Marker class selects the original encounter map"
		):
			return
	var route: Array = [0, 3, 4, 5, 6, 11, 7, 8, 12, 16]
	if not _check(
		Encounters.travel_nodes(route, 16, 8) == [12, 8],
		"Travel visits intervening nodes in reverse order"
	):
		return
	if not _check(
		Encounters.travel_nodes(route, 7, 16) == [8, 12, 16],
		"Travel visits intervening nodes in forward order"
	):
		return
	if not _check(
		Encounters.travel_nodes(route, 8, 8).is_empty(), "Travel to the current node needs no steps"
	):
		return
	if not _check(
		Encounters.travel_nodes(route, 8, 99) == null, "Unknown destinations cannot produce travel"
	):
		return
	if not _check(
		Encounters.travel_nodes(JSON.parse_string(JSON.stringify(route)), 16, 8) == [12, 8],
		"JSON numeric route entries retain their order"
	):
		return
	if not _check(
		Encounters.travel_nodes([0, 3, 3], 0, 3) == null, "Ambiguous routes are rejected"
	):
		return
	print("PASS world encounter spawn gates, order and boundaries")
	quit(0)


func _draw(limit: int) -> int:
	draws.append(limit)
	return samples.pop_front()


func _check(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition
