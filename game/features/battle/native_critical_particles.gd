extends RefCounted

# Original critical-hit sparks use fixed-point positions and Java's shared RNG.
const INT_MIN := -2147483648

var color: int = 0xffe000
var alive: bool = true
var particles: Array[Array] = []
var _elapsed: int = 0


func _init(random: RefCounted) -> void:
	for index: int in range(20):
		var x: int = _java_abs(random.next_int()) % 8192 - 4096
		var y: int = _java_abs(random.next_int()) % 4096 - 2048
		var size: int = _java_abs(random.next_int()) % 2 + 1
		particles.append([0, 0, x, y, size])


func advance() -> void:
	if not alive:
		return
	_elapsed += 50
	color -= 263168
	for particle: Array in particles:
		particle[0] += particle[2]
		particle[1] += particle[3]
		particle[3] += 256
	if _elapsed >= 400:
		alive = false


func _java_abs(value: int) -> int:
	return value if value == INT_MIN else absi(value)
