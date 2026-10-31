extends RefCounted

var tick: int = 0
var hp: int
var circle_phase: int = -1
var finished: bool = false
var _target: int
var _tail: int = 0


func _init(before: int, after: int) -> void:
	hp = before
	_target = after
	finished = after < before


func advance() -> void:
	if finished:
		return
	tick += 1
	circle_phase = floori(float(tick - 1) / 2) if tick <= 6 else -1
	if tick == 1:
		return
	if _tail == 0:
		hp = mini(hp + 2, _target)
		if hp == _target:
			_tail = 2
	else:
		_tail += 1
		finished = _tail >= 12
