extends Control

signal closed
signal command_requested(operation: String, details: Dictionary)

const PixelTheme = preload("res://ui/pixel_theme.gd")
const ItemDetails = preload("res://features/tactical_map/item_details.gd")
const ExchangeScreen = preload("res://features/tactical_map/exchange_screen.gd")
const MenuNavigation = preload("res://ui/menu_navigation.gd")
var page: String = "overview"
var stage: String = "tabs"
var _progress: Dictionary
var _content: Dictionary
var _model: RefCounted
var _index: int = 0
var _tab: int = 0
var _item_index: int = 0
var _click_selected: int = -1
var _operation_index: int = 0
var _shop_special: bool = false
var _source_index: int = -1
var _partner_id: int = -1
var _finish_page: String = "operations"
var _items: Array = []
var _pending: String = ""
var _pending_details: Dictionary = {}
var _notice_remaining: float = 0
var _return_stage: String
var _heading: Label
var _header_icon: TextureRect
var _gold: Label
var _price: Label
var _party: HBoxContainer
var _scroll: ScrollContainer
var _rows: VBoxContainer
var _operations: PanelContainer
var _operation_rows: VBoxContainer
var _tabs: HBoxContainer
var _footer: Control
var _exchange: Control
var _question_panel: PanelContainer
var _question: Label
var _back: Button
var _confirm: Button
var _textures: Dictionary = {}


func setup(content: Dictionary, model: RefCounted) -> void:
	_content = content
	_model = model
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var directory: String = content["entry"]["resourceDirectory"]
	for key: String in content["interface"]["textures"]:
		_textures[key] = load(directory.path_join(content["interface"]["textures"][key]["texture"]))
	_heading = Label.new()
	_heading.add_theme_color_override("font_color", Color("fff000"))
	add_child(_heading)
	_header_icon = TextureRect.new()
	_header_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_header_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_header_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_header_icon)
	_party = HBoxContainer.new()
	_party.add_theme_constant_override("separation", 0)
	add_child(_party)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 0)
	add_child(_tabs)
	_gold = Label.new()
	_price = Label.new()
	add_child(_gold)
	add_child(_price)
	for index: int in range(2):
		var tab: Button = _button("")
		tab.name = "Tab_" + str(index)
		tab.pressed.connect(_change_tab.bind(index))
		_tabs.add_child(tab)
	_scroll = ScrollContainer.new()
	_scroll.follow_focus = true
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 0)
	_scroll.add_child(_rows)
	_operations = PanelContainer.new()
	add_child(_operations)
	_operation_rows = VBoxContainer.new()
	_operation_rows.add_theme_constant_override("separation", 0)
	_operations.add_child(_operation_rows)
	for entry: Array in [["Shop", "商店"], ["Warehouse", "仓库"], ["Trade", "交换"]]:
		var button: Button = _button(entry[1])
		button.name = entry[0]
		button.add_theme_constant_override("icon_max_width", 28)
		button.focus_entered.connect(func() -> void: button.icon = _textures["finger"])
		button.focus_exited.connect(func() -> void: button.icon = null)
		button.pressed.connect(_open_operation.bind(entry[0].to_lower()))
		_operation_rows.add_child(button)
	_footer = ItemDetails.new()
	add_child(_footer)
	_footer.setup(content)
	_exchange = ExchangeScreen.new()
	_exchange.name = "WorldExchange"
	add_child(_exchange)
	_exchange.setup(content)
	_exchange.intent.connect(_exchange_intent)
	_question_panel = PanelContainer.new()
	add_child(_question_panel)
	_question = Label.new()
	_question.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_question_panel.add_child(_question)
	_confirm = _button("")
	_confirm.name = "Confirm"
	_confirm.icon = _textures["button_0"]
	_confirm.focus_mode = Control.FOCUS_NONE
	_confirm.pressed.connect(_accept)
	add_child(_confirm)
	_back = _button("")
	_back.name = "Back"
	_back.icon = _textures["button_1"]
	_back.focus_mode = Control.FOCUS_NONE
	_back.pressed.connect(go_back)
	add_child(_back)
	resized.connect(_layout)
	_operations.minimum_size_changed.connect(_layout)
	_question_panel.minimum_size_changed.connect(_layout)
	hide()


func present(progress: Dictionary) -> void:
	_progress = progress.duplicate(true)
	_click_selected = -1
	_index = 0
	_operation_index = 0
	page = "overview"
	stage = "tabs"
	_pending = ""
	_pending_details = {}
	_source_index = -1
	_clear(_party)
	for index: int in range(_progress["party"].size()):
		var member: Dictionary = _progress["party"][index]
		var button: Button = _button("")
		button.name = "Party_" + str(int(member["id"]))
		button.tooltip_text = member["name"]
		var frame: Dictionary = _content["mapAnimations"]["units"][str(int(member["id"]))]["frames"][0]
		button.icon = PixelTheme.sprite_icon(
			load(_content["entry"]["resourceDirectory"].path_join(frame["texture"]))
		)
		button.pressed.connect(_party_pressed.bind(index))
		button.focus_entered.connect(_preview_actor.bind(index))
		_party.add_child(button)
	show()
	_render()


func _button(text: String, hover_focus: bool = true) -> Button:
	var button := Button.new()
	button.text = text
	button.expand_icon = true
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	if hover_focus:
		button.mouse_entered.connect(button.grab_focus)
	return button


func _clear(container: Node) -> void:
	for child: Node in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _owner() -> Dictionary:
	return _progress["party"][_index]


func _preview_actor(index: int) -> void:
	if (
		stage in ["confirm", "notice"]
		or not _pending.is_empty()
		or page not in ["overview", "partner"]
		or index == _index
		or (page == "partner" and index == _source_index)
	):
		return
	_index = index
	_item_index = 0
	_render()


func _party_pressed(index: int) -> void:
	if stage in ["confirm", "notice"] or not _pending.is_empty():
		return
	if page == "partner" and index != _source_index:
		_index = index
		_choose_partner()
		return
	if page != "overview":
		return
	_index = index
	_operation_index = 0
	page = "operations"
	_render()


func _open_operation(kind: String) -> void:
	if stage in ["confirm", "notice"] or not _pending.is_empty():
		return
	_operation_index = ["shop", "warehouse", "trade"].find(kind)
	if kind == "shop":
		_request("open_shop", {"unit": _owner()["id"]})
		return
	if kind == "trade":
		if _progress["party"].size() < 2:
			return
		_source_index = _index
		_index = posmod(_index + 1, _progress["party"].size())
		page = "partner"
		stage = "tabs"
		_render()
		return
	if kind != "warehouse":
		return
	if _owner()["inventory"].is_empty() and _progress["warehouse"].is_empty():
		return
	page = "warehouse"
	stage = "tabs"
	_tab = 1 if _progress["warehouse"].is_empty() else 0
	_item_index = 0
	_render()


func _choose_partner() -> void:
	_partner_id = int(_owner()["id"])
	page = "exchange"
	stage = "tabs"
	_render()


func _exchange_intent(kind: String, details: Dictionary) -> void:
	if stage == "notice" or not _pending.is_empty():
		return
	if kind == "trade":
		_request("trade", details)
	elif kind == "closed":
		_finish_page = "partner"
		_request(
			"finish", {"unit": _progress["party"][_source_index]["id"], "partner": _partner_id}
		)


func _tab_items(index: int) -> Array:
	if page == "warehouse":
		return _progress["warehouse"] if index == 0 else _owner()["inventory"]
	if page == "shop" and index == 0:
		return _model.shop_stock(_progress, _shop_special)
	return _owner()["inventory"]


func _transaction() -> String:
	if page == "warehouse":
		return "take" if _tab == 0 else "deposit"
	return "buy" if _tab == 0 else "sell"


func _change_tab(index: int) -> void:
	if stage in ["confirm", "notice"] or not _pending.is_empty():
		return
	var contents: Array = _tab_items(index)
	if contents.is_empty():
		return
	_tab = index
	_item_index = 0
	_click_selected = -1
	stage = "tabs"
	_render()


func _render() -> void:
	_heading.text = _owner()["name"]
	_heading.visible = page in ["overview", "operations", "partner"]
	_header_icon.visible = _heading.visible
	_header_icon.texture = _party.get_child(_index).icon
	if page == "partner":
		_heading.text = "%s ↔ %s" % [_progress["party"][_source_index]["name"], _owner()["name"]]
	_party.visible = _heading.visible
	for button: Button in _party.get_children():
		button.disabled = (
			page not in ["overview", "partner"]
			or (page == "partner" and button.get_index() == _source_index)
		)
	_operations.visible = page == "operations"
	for button: Button in _operation_rows.get_children():
		button.disabled = stage in ["confirm", "notice"]
	_tabs.visible = page in ["warehouse", "shop"]
	_gold.visible = page == "shop"
	_price.visible = page == "shop"
	_gold.text = "%d 金" % int(_progress["gold"])
	if stage == "tabs":
		_price.text = ""
	_scroll.visible = page not in ["operations", "exchange"]
	_exchange.visible = page == "exchange"
	if page == "exchange" and stage != "notice":
		_exchange.present(_progress["party"][_source_index], _model.actor(_progress, _partner_id))
	_footer.hide()
	_question_panel.visible = stage in ["confirm", "notice"]
	_confirm.visible = stage != "notice" and page != "exchange"
	_back.visible = page != "exchange" or stage == "notice"
	if page == "warehouse":
		_tabs.get_child(0).text = "仓库"
		_tabs.get_child(1).text = _owner()["name"]
	elif page == "shop":
		_tabs.get_child(0).text = "购买"
		_tabs.get_child(1).text = "卖出"
	_items = _tab_items(_tab)
	_clear(_rows)
	for index: int in range(_items.size()):
		var held: Dictionary = _items[index]
		var metadata: Dictionary = _content["interface"]["items"][str(int(held["templateId"]))]
		var button: Button = _button("", page != "shop")
		button.name = "Item_" + str(index)
		button.disabled = stage in ["confirm", "notice"]
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var icon := TextureRect.new()
		icon.texture = _textures.get(metadata["icon"])
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(icon)
		var label := Label.new()
		label.text = metadata["name"]["text"]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if int(held["templateId"]) < 60 and not _model.can_equip(_owner(), held):
			label.add_theme_color_override("font_color", Color("a0a0a0"))
		line.add_child(label)
		var uses := Label.new()
		uses.text = str(int(held["durability"]))
		uses.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(uses)
		button.add_child(line)
		button.focus_entered.connect(_select_item.bind(index))
		button.pressed.connect(_shop_select.bind(index) if page == "shop" else _ask.bind(index))
		_rows.add_child(button)
	_item_index = mini(_item_index, maxi(0, _items.size() - 1))
	if not _items.is_empty() and page not in ["operations", "exchange"]:
		_select_item(_item_index)
	_layout()
	if stage in ["confirm", "notice"]:
		return
	if page == "operations":
		_operation_rows.get_child(_operation_index).grab_focus()
	elif page in ["warehouse", "shop"] and stage == "tabs":
		_tabs.get_child(_tab).grab_focus()
	elif page in ["overview", "partner"]:
		_party.get_child(_index).grab_focus()
	elif page in ["warehouse", "shop"] and not _items.is_empty():
		_rows.get_child(_item_index).grab_focus()


func _shop_select(index: int) -> void:
	if stage in ["confirm", "notice"] or not _pending.is_empty():
		return
	if stage == "items" and _click_selected == index:
		_ask(index)
		return
	stage = "items"
	_item_index = index
	_click_selected = index
	_render()


func _select_item(index: int) -> void:
	if stage in ["confirm", "notice"] or index < 0 or index >= _items.size():
		return
	if _item_index != index:
		_click_selected = -1
	_item_index = index
	_footer.present(_items[index])
	if page == "shop" and stage == "items":
		var price: int = (
			int(_items[index]["price"]) if _tab == 0 else _model.sale_price(_items[index])
		)
		_price.text = "%d 金" % price


func _ask(index: int) -> void:
	if stage in ["confirm", "notice"] or not _pending.is_empty():
		return
	if page not in ["warehouse", "shop"]:
		_select_item(index)
		return
	stage = "items"
	_select_item(index)
	_click_selected = index
	var operation: String = _transaction()
	_pending_details = {"unit": _owner()["id"]}
	if operation == "buy":
		_pending_details["template"] = int(_items[index]["templateId"])
		_pending_details["special"] = _shop_special
	else:
		_pending_details["item"] = _items[index]["id"]
	var preview: Dictionary = _model.apply(_progress, operation, _pending_details)
	if not preview["ok"]:
		_notice(preview["error"])
		return
	var metadata: Dictionary = _content["interface"]["items"][str(int(_items[index]["templateId"]))]
	_question.add_theme_color_override("font_color", Color.WHITE)
	_question.text = "确认要%s%s吗？" % ["取出" if _tab == 0 else "放回仓库：", metadata["name"]["text"]]
	if page == "shop":
		_question.text = (
			"%s %d金，确认购买吗？" % [metadata["name"]["text"], int(_items[index]["price"])]
			if _tab == 0
			else "确认要卖出%s吗？" % metadata["name"]["text"]
		)
	stage = "confirm"
	_render()


func _accept() -> void:
	if not _pending.is_empty() or stage == "notice":
		return
	if stage == "confirm":
		_request(_transaction(), _pending_details)
	elif page == "overview":
		page = "operations"
		_render()
	elif page == "partner":
		_choose_partner()
	elif page == "operations":
		var focused: Control = get_viewport().gui_get_focus_owner()
		if focused is Button and focused.get_parent() == _operation_rows:
			focused.pressed.emit()
	elif page in ["warehouse", "shop"] and not _items.is_empty():
		if stage == "tabs":
			stage = "items"
			_render()
		else:
			_ask(_item_index)


func _request(operation: String, details: Dictionary) -> void:
	_pending = operation
	command_requested.emit(operation, details)


func complete(result: Dictionary, progress: Dictionary) -> void:
	var operation: String = _pending
	_pending = ""
	if not result["ok"]:
		stage = "items" if stage == "confirm" else stage
		_notice(result["error"])
		return
	_progress = progress.duplicate(true)
	_click_selected = -1
	if operation == "open_shop":
		page = "shop"
		_shop_special = result["special"]
		_tab = 0
		_item_index = 0
		stage = "tabs"
	elif operation == "finish":
		page = _finish_page
		stage = "tabs"
	else:
		stage = "items"
		if page == "exchange":
			stage = "tabs"
		var contents: Array = _tab_items(_tab)
		if contents.is_empty():
			_tab = 1 - _tab
			stage = "tabs"
	_render()
	if result.get("destination") == "warehouse":
		_notice("PURCHASE_TO_WAREHOUSE")


func _notice(code: String) -> void:
	_return_stage = stage
	stage = "notice"
	_question.add_theme_color_override("font_color", Color.YELLOW)
	_question.text = (
		{
			"WAREHOUSE_FULL": "仓库已满",
			"INVENTORY_FULL": "人物携带已满",
			"INSUFFICIENT_GOLD": "你的钱不够。",
			"PURCHASE_TO_WAREHOUSE": "人物携带已满\n存入仓库",
			"SAVE_FAILED": "保存未完成，物品和资金未改变，请重试。"
		}
		. get(code, "操作未完成，请重试。")
	)
	_notice_remaining = 31 * float(_content["battleClips"]["tickMillis"]) / 1000
	_render()


func _process(delta: float) -> void:
	if not visible or stage != "notice":
		return
	_notice_remaining -= delta
	if _notice_remaining <= 0:
		stage = _return_stage
		_render()


func handle_key(event: InputEventKey) -> bool:
	if not event.pressed or event.echo or not _pending.is_empty():
		return false
	if stage == "notice":
		return true
	if page == "exchange":
		return _exchange.handle_key(event)
	if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		_accept()
		return true
	if stage == "confirm":
		return true
	if page in ["overview", "partner"] and event.keycode in [KEY_LEFT, KEY_RIGHT]:
		handle_wheel(-1 if event.keycode == KEY_LEFT else 1)
		return true
	if page in ["warehouse", "shop"]:
		if stage == "tabs" and event.keycode in [KEY_LEFT, KEY_RIGHT]:
			handle_wheel(-1 if event.keycode == KEY_LEFT else 1)
			return true
		if stage == "items" and event.keycode in [KEY_UP, KEY_DOWN]:
			handle_wheel(-1 if event.keycode == KEY_UP else 1)
			return true
		if stage == "items" and event.keycode in [KEY_LEFT, KEY_RIGHT]:
			_footer.cycle()
			return true
	return false


func handle_wheel(direction: int) -> void:
	if not _pending.is_empty() or stage in ["confirm", "notice"]:
		return
	match page:
		"exchange":
			_exchange.handle_wheel(direction)
		"overview", "partner":
			_index = posmod(_index + direction, _progress["party"].size())
			if page == "partner" and _index == _source_index:
				_index = posmod(_index + direction, _progress["party"].size())
			_item_index = 0
			_render()
		"warehouse", "shop":
			if stage == "tabs":
				_change_tab(1 - _tab)
			elif stage == "items" and not _items.is_empty():
				_item_index = posmod(_item_index + direction, _items.size())
				_rows.get_child(_item_index).grab_focus()
				_click_selected = _item_index
		"operations":
			var rows: Array[Button] = []
			for button: Button in _operation_rows.get_children():
				if (
					button.is_visible_in_tree()
					and not button.disabled
					and button.focus_mode != FOCUS_NONE
				):
					rows.append(button)
			MenuNavigation.step_buttons(rows, direction)


func go_back() -> void:
	if not _pending.is_empty():
		return
	if stage == "notice":
		stage = _return_stage
	elif stage == "confirm":
		stage = "items"
	elif page in ["warehouse", "shop"]:
		if stage == "items":
			stage = "tabs"
		else:
			_finish_page = "operations"
			_request("finish", {"unit": _owner()["id"]})
			return
	elif page == "exchange":
		_exchange.go_back()
		return
	elif page == "partner":
		_index = _source_index
		_source_index = -1
		page = "operations"
	elif page == "operations":
		page = "overview"
	else:
		hide()
		closed.emit()
		return
	_render()


func _layout() -> void:
	if _heading == null:
		return
	var area: Rect2 = PixelTheme.portrait_area(size)
	var factor: float = area.size.x / 240
	_header_icon.position = area.position + Vector2(4, 4) * factor
	_header_icon.size = Vector2(24, 24) * factor
	_heading.position = area.position + Vector2(32, 4) * factor
	_heading.size = Vector2(area.size.x - 40 * factor, 31 * factor)
	_heading.add_theme_font_size_override("font_size", roundi(14 * factor))
	_party.position = area.position + Vector2(0, 35) * factor
	for button: Button in _party.get_children():
		button.custom_minimum_size = Vector2(40, 34) * factor
		button.add_theme_constant_override("icon_max_width", roundi(24 * factor))
	_party.size = Vector2(area.size.x, 34 * factor)
	_tabs.position = area.position
	for button: Button in _tabs.get_children():
		button.custom_minimum_size = Vector2(area.size.x / 2, 19 * factor)
		button.add_theme_font_size_override("font_size", roundi(12 * factor))
	_tabs.size = Vector2(area.size.x, 19 * factor)
	for index: int in range(2):
		var label: Label = _gold if index == 0 else _price
		label.position = area.position + Vector2(4 + index * 120, 19) * factor
		label.size = Vector2(116, 23) * factor
		label.add_theme_font_size_override("font_size", roundi(12 * factor))
	var top: float = 42 if page == "shop" else 19 if page == "warehouse" else 69
	_scroll.position = area.position + Vector2(0, top) * factor
	_scroll.size = Vector2(area.size.x, maxf(0, area.size.y - (top + 67) * factor))
	for button: Button in _rows.get_children():
		button.custom_minimum_size.y = 19 * factor
		var line: HBoxContainer = button.get_child(0)
		line.get_child(0).custom_minimum_size.x = 16 * factor
		for label: Node in line.get_children():
			if label is Label:
				label.add_theme_font_size_override("font_size", roundi(12 * factor))
	_footer.position = Vector2(area.position.x, area.end.y - 67 * factor)
	_footer.size = Vector2(area.size.x, 45 * factor)
	_operations.size = Vector2(96 * factor, _operations.get_combined_minimum_size().y)
	_operations.position = area.get_center() - _operations.size / 2
	for button: Button in _operation_rows.get_children():
		button.custom_minimum_size = Vector2(0, 22 * factor)
		button.add_theme_font_size_override("font_size", roundi(12 * factor))
	_question.add_theme_font_size_override("font_size", roundi(12 * factor))
	_question_panel.size = Vector2(
		area.size.x, maxf(50 * factor, _question_panel.get_combined_minimum_size().y)
	)
	_question_panel.position = area.get_center() - _question_panel.size / 2
	for button: Button in [_confirm, _back]:
		button.add_theme_constant_override("icon_max_width", roundi(10 * factor))
		button.size = Vector2(24, 22) * factor
	_confirm.position = Vector2(area.position.x, area.end.y - 22 * factor)
	_back.position = area.end - Vector2(24, 22) * factor
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("111e24"))
	var area: Rect2 = PixelTheme.portrait_area(size)
	draw_rect(area, Color("6e4618") if page == "warehouse" else Color("244e83"))
