extends RefCounted

const LOGIC_UNITS: int = 50
const GATE_UPDATES: int = 10
var tick: int = 0
var circle_phase: int = 0
var finished: bool = false


func advance() -> void:
	if finished:
		return
	tick += 1
	circle_phase = floori(float(tick) / 2) if tick < 6 else -1
	finished = tick >= GATE_UPDATES
