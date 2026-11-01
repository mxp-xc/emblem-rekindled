extends RefCounted

const LOGICAL_TICK_UNITS: int = 50
const FRAME_UNITS: int = 100
const GATE_UPDATES: int = 7
const TILE_PIXELS: int = 24

var tick: int = 0
var gate_open: bool = false
var finished: bool = false
var _origin: Vector2
var _effects: Dictionary


func _init(unit: Dictionary, effects: Dictionary) -> void:
	_origin = Vector2(unit["x"], unit["y"]) * TILE_PIXELS
	_effects = effects


func advance() -> void:
	if finished:
		return
	tick += 1
	gate_open = tick >= GATE_UPDATES
	finished = gate_open and effect_frame("bomb") < 0 and effect_frame("smoke") < 0


func effect_frame(kind: String) -> int:
	var index: int = floori(float(tick * LOGICAL_TICK_UNITS) / FRAME_UNITS)
	return index if index < _effects[kind]["frames"].size() else -1


# Native bomb placement uses integer division; smoke rises every map update,
# independently of its two-update frame interval and of the dialogue gate.
func effect_anchor(kind: String) -> Vector2:
	if kind == "bomb":
		var sprite: Dictionary = _effects[kind]
		return (
			_origin
			+ Vector2(
				12 - floori(float(sprite["virtualWidth"]) / 2),
				12 - floori(float(sprite["virtualHeight"]) / 2)
			)
		)
	return _origin + Vector2(0, -tick)
