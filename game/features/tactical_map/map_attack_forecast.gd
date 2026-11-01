extends Control

var _content: Dictionary
var _panel: PanelContainer
var _body: VBoxContainer
var _title: Label
var _summary: Label
var _scroll: ScrollContainer
var _rows: VBoxContainer
var _hint: Label
var _factor: float = 1.0


func setup(content: Dictionary) -> void:
	_content = content
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_panel = PanelContainer.new()
	_panel.name = "MapForecastPanel"
	add_child(_panel)
	_body = VBoxContainer.new()
	_panel.add_child(_body)
	_title = Label.new()
	_title.name = "MapForecastTitle"
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_title)
	_summary = Label.new()
	_summary.name = "MapForecastSummary"
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_summary)
	_scroll = ScrollContainer.new()
	_scroll.name = "MapForecastTargets"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	_body.add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_rows)
	_hint = Label.new()
	_hint.text = "确认施放　返回取消"
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_hint)
	# Wrapped labels can lower the panel minimum after its first container sort.
	_panel.minimum_size_changed.connect(_layout)
	resized.connect(_layout)
	hide()


func present(preview: Dictionary) -> void:
	for child: Node in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var weapon: String = str(int(preview["weapon"]))
	_title.text = "%s · 范围预览" % _content["interface"]["items"][weapon]["name"]["text"]
	var targets: Array = preview["targetIds"]
	_summary.text = "影响 %d 人 · HP为命中时预测\n整次耗1耐久 · 无反击/暴击 · 不收集掉落" % targets.size()
	for target: Dictionary in preview["participants"]:
		var id: int = int(target["id"])
		if not targets.has(id):
			continue
		var forecast: Dictionary = preview["forecasts"][str(id)]
		var row := VBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rows.add_child(row)
		var identity := HBoxContainer.new()
		identity.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(identity)
		var target_name := Label.new()
		target_name.name = "MapTarget_%d" % id
		target_name.text = target["name"]
		target_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		target_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		target_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		identity.add_child(target_name)
		var hp := Label.new()
		hp.name = "MapTargetHp_%d" % id
		hp.text = (
			"%sHP %d → %d"
			% [
				"（主目标）" if id == int(preview["primary"]) else "",
				int(target["hp"]),
				maxi(0, int(target["hp"]) - int(forecast["damage"]))
			]
		)
		hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		identity.add_child(hp)
		var prediction := Label.new()
		prediction.name = "MapTargetPrediction_%d" % id
		prediction.text = "伤害 %d　命中 %d%%" % [forecast["damage"], forecast["hit"]]
		prediction.add_theme_color_override("font_color", Color("fff000"))
		prediction.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(prediction)
	_scroll.scroll_vertical = 0
	show()
	_layout()


func scroll_targets(direction: int) -> void:
	_scroll.scroll_vertical += roundi(88 * _factor) * direction


func _layout() -> void:
	if _panel == null:
		return
	_factor = maxf(0.25, minf(size.x / 720.0, size.y / 960.0))
	_panel.position = Vector2.ONE * 12 * _factor
	_panel.size = Vector2(size.x - 24 * _factor, size.y - 100 * _factor)
	_body.add_theme_constant_override("separation", roundi(12 * _factor))
	_rows.add_theme_constant_override("separation", roundi(20 * _factor))
	for label: Label in [_title, _summary, _hint]:
		label.add_theme_font_size_override("font_size", roundi(28 * _factor))
	_title.add_theme_color_override("font_color", Color("fff7bf"))
	for row: VBoxContainer in _rows.get_children():
		for label: Label in row.find_children("*", "Label", true, false):
			label.add_theme_font_size_override("font_size", roundi(28 * _factor))
