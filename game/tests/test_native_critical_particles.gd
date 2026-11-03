extends SceneTree

const NativeRandom = preload("res://features/battle/native_random.gd")
const Particles = preload("res://features/battle/native_critical_particles.gd")


func same_particles(actual: Array, expected: Array) -> bool:
	for index: int in range(actual.size()):
		for field: int in range(actual[index].size()):
			if int(actual[index][field]) != int(expected[index][field]):
				return false
	return true


func _initialize() -> void:
	var oracle: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(
			"res://tests/fixtures/chapter_1_native_critical_particles.json"
		)
	)
	var generated: RefCounted = Particles.new(NativeRandom.new(0))
	for tick: int in range(oracle["ticks"].size()):
		var expected: Dictionary = oracle["ticks"][tick]
		if (
			generated.color != int(expected["color"])
			or generated.alive != expected["alive"]
			or not same_particles(generated.particles, expected["particles"])
		):
			push_error(
				(
					"Original critical particles differ at tick %d: actual %s expected %s"
					% [tick, generated.particles[0], expected["particles"][0]]
				)
			)
			quit(1)
			return
		generated.advance()
	print("PASS: critical particles match original JAR fixed-point state")
	quit(0)
