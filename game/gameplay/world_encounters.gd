extends RefCounted

const INTERVAL_MS: int = 10000


static func travel_nodes(route: Array, current: int, destination: int) -> Variant:
	var start: int = -1
	var end: int = -1
	var seen: Dictionary = {}
	for index: int in range(route.size()):
		if not _integer_in(route[index], 0, 16) or seen.has(int(route[index])):
			return null
		var node: int = int(route[index])
		seen[node] = true
		if node == current:
			start = index
		if node == destination:
			end = index
	if start < 0 or end < 0:
		return null
	var result: Array[int] = []
	if start != end:
		var direction: int = 1 if end > start else -1
		for index: int in range(start + direction, end + direction, direction):
			result.append(int(route[index]))
	return result


static func battle_for_class(class_id: int) -> int:
	if class_id < 0 or class_id > 40:
		return -1
	return 18 if int(class_id / 4) in [7, 8, 9] else 17


# The caller owns the clock and the transient marker; the input is never mutated.
static func advance(
	state: Dictionary,
	progress_step: int,
	traveling: bool,
	elapsed_ms: int,
	completed_nodes: Array,
	current_node: int,
	random_source: Callable
) -> Dictionary:
	if (
		state.size() != 2
		or not _integer_in(state.get("lastCheckMs"), 0, elapsed_ms)
		or not state.has("marker")
		or progress_step < 0
		or current_node < 0
		or current_node > 16
	):
		return {"ok": false, "error": "INVALID_ENCOUNTER_STATE"}
	var current: Variant = state["marker"]
	if (
		current != null
		and (
			not current is Dictionary
			or current.size() != 2
			or not _integer_in(current.get("node"), 0, 16)
			or not _integer_in(current.get("classId"), 0, 40)
		)
	):
		return {"ok": false, "error": "INVALID_ENCOUNTER_STATE"}
	if progress_step < 6 or traveling or elapsed_ms - int(state["lastCheckMs"]) < INTERVAL_MS:
		return {"ok": true, "state": state.duplicate(true)}
	var candidates: Array[int] = []
	var seen: Dictionary = {}
	for value: Variant in completed_nodes:
		if not _integer_in(value, 0, 16) or seen.has(int(value)):
			return {"ok": false, "error": "INVALID_ENCOUNTER_NODES"}
		seen[int(value)] = true
		if int(value) != current_node:
			candidates.append(int(value))
	candidates.sort()
	if candidates.is_empty() or not random_source.is_valid():
		return {"ok": false, "error": "INVALID_ENCOUNTER_NODES"}
	var rolls: Array[int] = []
	for limit: int in [100, candidates.size(), 100]:
		var value: Variant = random_source.call(limit)
		if not _integer_in(value, 0, limit - 1):
			return {"ok": false, "error": "INVALID_RANDOM_RESULT"}
		rolls.append(int(value))
	var marker: Variant = null
	if rolls[2] < 60:
		marker = {"node": candidates[rolls[1]], "classId": 32 if rolls[0] < 25 else 28}
	return {"ok": true, "state": {"lastCheckMs": elapsed_ms, "marker": marker}}


static func _integer_in(value: Variant, minimum: int, maximum: int) -> bool:
	return (
		(value is int or value is float)
		and is_finite(float(value))
		and float(value) == floorf(float(value))
		and value >= minimum
		and value <= maximum
	)
