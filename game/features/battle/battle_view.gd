extends Control

signal completed

const BattleAnimation = preload("res://features/battle/battle_animation.gd")
const Canvas = preload("res://features/battle/battle_canvas.gd")
const Hud = preload("res://features/battle/combat_hud.gd")
var playing: bool = false
var model: RefCounted
var _library: RefCounted
var _background: Control
var _foreground: Control
var _hud: Control
var _participants: Array
var _elapsed: float = 0
var _tick_millis: float


func setup(content: Dictionary, library: RefCounted) -> void:
	_library = library
	_tick_millis = float(content["battleClips"]["tickMillis"])
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_background = Canvas.new()
	add_child(_background)
	_background.setup(content, false)
	_hud = Hud.new()
	add_child(_hud)
	_hud.setup(content)
	_foreground = Canvas.new()
	add_child(_foreground)
	_foreground.setup(content, true)
	set_process(false)
	hide()


func play(result: Dictionary) -> Dictionary:
	if playing:
		return {"ok": false, "error": "战斗演出仍在播放"}
	var prepared: Dictionary = _library.prepare(result)
	if not prepared["ok"]:
		return prepared
	playing = true
	model = BattleAnimation.new(prepared)
	_participants = result["participants"]
	_hud.present(result, true)
	_elapsed = 0
	model.advance()
	_render_frame()
	show()
	set_process(true)
	await completed
	hide()
	return {"ok": true}


func _process(delta: float) -> void:
	_elapsed += delta * 1000
	while _elapsed >= _tick_millis and not model.finished:
		_elapsed -= _tick_millis
		model.advance()
	_render_frame()
	if model.finished:
		playing = false
		set_process(false)
		completed.emit()


func _render_frame() -> void:
	_background.present(model.frame, _participants)
	_hud.set_display(model.frame)
	_foreground.present(model.frame, _participants)
