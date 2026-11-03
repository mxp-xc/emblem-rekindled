extends RefCounted

# Java ME's java.util.Random 48-bit state, shared by effects and shake.
const MASK: int = (1 << 48) - 1
const MULTIPLIER: int = 25214903917
const ADDEND: int = 11
const INT_MIN: int = -2147483648

var _state: int


func _init(seed: int) -> void:
	_state = (seed ^ MULTIPLIER) & MASK


func next_int() -> int:
	_state = (_state * MULTIPLIER + ADDEND) & MASK
	var result: int = _state >> 16
	return result - 4294967296 if result >= 2147483648 else result


func native_range(minimum: int, maximum: int) -> int:
	assert(maximum >= minimum)
	var value: int = next_int()
	# Java's negation of Integer.MIN_VALUE wraps back to Integer.MIN_VALUE.
	if value < 0 and value != INT_MIN:
		value = -value
	return value % (maximum - minimum + 1) + minimum
