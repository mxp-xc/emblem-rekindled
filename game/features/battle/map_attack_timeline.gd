extends RefCounted

var tick: int = 0
var target_index: int = 0
var phase: String = "focus"
var finished: bool = false
var hp: Dictionary = {}
var hidden: Dictionary = {}
var impact: bool = false
var _hits: Array
var _effect: Dictionary
var _updates: Array
var _has_updates: bool
var _revival_ids: Array[int] = []
var _elapsed_units: int = 0


func _init(result: Dictionary, effect: Dictionary) -> void:
	_hits = result["hits"]
	_effect = effect
	_has_updates = result.has("updates")
	_updates = result.get("updates", [])
	for revival: Dictionary in result.get("revivals", []):
		_revival_ids.append(int(revival["unit"]))
	finished = _hits.is_empty()
	for hit: Dictionary in _hits:
		hp[int(hit["target"])] = int(hit["hpBefore"])


# Native be13 waits for the camera, then 600/300 units before impact,
# 150 before death cleanup, and 550 before advancing the result queue.
func advance(camera_ready: bool = true) -> void:
	if finished:
		return
	tick += 1
	_elapsed_units += int(_effect["logicalTickUnits"])
	match phase:
		"focus":
			phase = "camera"
		"camera":
			if camera_ready:
				phase = "hold"
				_elapsed_units = 0
		"hold":
			if _elapsed_units >= (600 if target_index == 0 else 300):
				var hit: Dictionary = current_hit()
				hp[int(hit["target"])] = int(hit["hpAfter"])
				impact = true
				phase = "impact"
				_elapsed_units = 0
		"impact":
			if _elapsed_units >= 150:
				var id: int = int(current_hit()["target"])
				if _has_updates:
					for update: Dictionary in _updates:
						if int(update["triggerUnitId"]) != id:
							continue
						for unit: Dictionary in update["units"]:
							var unit_id: int = int(unit["unitId"])
							if unit_id in _revival_ids:
								hidden[unit_id] = true
							else:
								hp[unit_id] = int(unit["hp"])
								if not bool(unit["visible"]):
									hidden[unit_id] = true
				elif hp[id] <= 0:
					hidden[id] = true
				impact = false
				phase = "tail"
				_elapsed_units = 0
		"tail":
			if _elapsed_units >= 550:
				phase = "next"
		"next":
			target_index += 1
			finished = target_index >= _hits.size()
			if not finished:
				phase = "focus"
				_elapsed_units = 0


func current_hit() -> Dictionary:
	return {} if finished else _hits[target_index]


func effect_frame() -> int:
	if _effect["kind"] != "sprite":
		return -1
	var elapsed: int = tick * int(_effect["logicalTickUnits"])
	var sequence: Array = _effect["sequence"]
	var step: int = int(float(elapsed) / int(_effect["stepUnits"]))
	if step >= sequence.size() * int(_effect["cycles"]):
		return -1
	return int(sequence[step % sequence.size()])


func shaking() -> bool:
	return (
		_effect["kind"] == "shake"
		and tick * int(_effect["logicalTickUnits"]) < int(_effect["durationUnits"])
	)


func flashing() -> bool:
	if _effect["kind"] != "shake":
		return false
	var remaining: int = int(_effect["flashUpdates"]) - tick
	return remaining > 0 and (remaining % 2 == 0) == bool(_effect["flashOnEven"])
