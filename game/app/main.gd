# Composition keeps player/AI sequencing and UI event wiring in one entry point.
# gdlint: disable=max-file-lines
extends Control

const Session = preload("res://app/chapter_session.gd")
const Settings = preload("res://persistence/settings_store.gd")
const UnitMenu = preload("res://features/tactical_map/unit_menu.gd")
const UnitInformation = preload("res://features/tactical_map/unit_information.gd")
const ItemActions = preload("res://features/tactical_map/item_actions.gd")
const ExchangeScreen = preload("res://features/tactical_map/exchange_screen.gd")
const PixelTheme = preload("res://ui/pixel_theme.gd")
const MapView = preload("res://features/tactical_map/map_view.gd")
const TacticalMap = preload("res://features/tactical_map/tactical_map.gd")
const MapHud = preload("res://features/tactical_map/map_hud.gd")
const BattleStore = preload("res://persistence/battle_store.gd")
const GameMenu = preload("res://features/menus/game_menu.gd")
const TitleScreen = preload("res://features/menus/title_screen.gd")
const SaveSlotScreen = preload("res://features/menus/save_slot_screen.gd")
const WorldInventoryScreen = preload("res://features/world/inventory_screen.gd")
const WorldInventory = preload("res://gameplay/world_inventory.gd")
const StoryPlayer = preload("res://features/dialogue/story_player.gd")
const BattleClips = preload("res://app/battle_clip_library.gd")
const BattleView = preload("res://features/battle/battle_view.gd")
const ActionFeedback = preload("res://features/battle/action_feedback.gd")
const RetirementPlayer = preload("res://features/battle/retirement_player.gd")
const MapAttackPlayer = preload("res://features/battle/map_attack_player.gd")
const TargetSelection = preload("res://features/tactical_map/target_selection.gd")
const Battle = preload("res://gameplay/battle_state.gd")
const FONT = preload("res://ui/fonts/NotoSansCJKsc-Regular.otf")
const INK := Color("e8eadb")
const GOLD := Color("e6c48b")
const WORLD_GOLD_BENEFIT: int = 1000
const WHEEL_IDLE_MILLIS: int = 180
const WHEEL_STEP_MILLIS: int = 140

var content: Dictionary
var world_progress: Dictionary = {}
var save_slots: Control
var world_inventory_screen: Control
var world_inventory: RefCounted
var battle: RefCounted
var battle_store: RefCounted
var battle_clips: RefCounted
var battle_view: Control
var action_feedback: Control
var retirement_player: Control
var map_attack_player: Control
var target_selection: Control
var title_screen: Control
var story_player: Control
var selected_unit: int = -1
var choosing_destination: bool = false
var busy: bool = false
var trade_partner: int = -1
var feedback: Label
var settings: Dictionary = {"volume": 0.45, "music_enabled": false}
var store: RefCounted = Settings.new()
var map: Control
var menu_button: Button
var map_hud: Control
var unit_panel: PanelContainer
var unit_information: Control
var item_actions: Control
var exchange_screen: Control
var menu_layer: ColorRect
var player := AudioStreamPlayer.new()
var music_started: bool = false
var _target_item: String = ""
var _target_mode: String = ""
var _last_system_back_millis: int = -1000
var _slot_operation: String
var _played_seconds: float = -1
var _application_paused: bool = false
var _safe_area: Rect2
var _pressed_pointers: Dictionary = {}
var _canceled_pointers: Dictionary = {}
var _overlay_area: Rect2
var _full_screen_menu: bool = false
var _wheel_owner: Control
var _wheel_direction: int = 0
var _wheel_last_event_millis: int = -1000
var _wheel_last_step_millis: int = -1000
var _wheel_distance: float = 0.0
var _rebuilding_interface: bool = false
var _world_transitioning: bool = false


func _ready() -> void:
	Engine.time_scale = 1
	preload("res://app/build_identity.gd").publish()
	theme = Theme.new()
	theme.default_font = FONT
	theme.default_font_size = 24
	theme.set_color("font_color", "Label", INK)
	theme.set_color("font_color", "Button", INK)
	var loaded: Dictionary = Session.new().open("res://content/chapter_1/chapter.json")
	if not loaded["ok"]:
		push_error(loaded["error"])
		add_child(_label("关卡资源无法加载\n请检查游戏文件后重试。", 28))
		return
	content = loaded["content"]
	theme = PixelTheme.new().create(content["interface"], content["entry"]["resourceDirectory"])
	battle = loaded["battle"]
	battle_clips = BattleClips.new(content)
	battle_store = BattleStore.new(content)
	var restored: Dictionary = store.read()
	if restored["ok"]:
		settings = restored["settings"]
	_build_interface()
	var music: AudioStreamOggVorbis = load(content["entry"]["titleMusic"])
	music.loop = true
	# Long BGM streams avoid Web Sample loop/resume buffer duplication.
	player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	player.stream = music
	player.volume_linear = settings["volume"]
	add_child(player)
	if not OS.has_feature("web") and settings["music_enabled"]:
		_unlock_music()
	_update_music_button()
	if not restored["ok"]:
		_report_storage_error(restored)
		_set_menu_visible(true)
	resized.connect(_layout)
	_show_title()
	_layout()
	var probe := preload("res://app/playtest_probe.gd").new()
	add_child(probe)
	var diagnostic: Dictionary = probe.setup(self)
	if not diagnostic["ok"]:
		push_warning(diagnostic["error"])
	if not diagnostic.get("enabled", false):
		probe.queue_free()


func _build_interface() -> void:
	_build_battlefield()
	_build_menu()
	map.setup(content)
	map.set_units(battle.snapshot()["units"])
	unit_panel.minimum_size_changed.connect(_layout)
	map_hud.visibility_changed.connect(_layout)
	title_screen = TitleScreen.new()
	title_screen.name = "TitleScreen"
	add_child(title_screen)
	title_screen.setup(content, battle_store.has_save())
	title_screen.new_game.connect(start_new_game)
	title_screen.continue_game.connect(load_game)
	title_screen.load_game.connect(func() -> void: _open_save_slots("load"))
	title_screen.settings_requested.connect(func() -> void: _set_menu_visible(true))
	title_screen.help_requested.connect(
		func() -> void:
			_set_menu_visible(true)
			menu_layer.show_page("help")
	)
	title_screen.interacted.connect(_unlock_music)
	story_player = StoryPlayer.new()
	story_player.name = "StoryPlayer"
	add_child(story_player)
	story_player.setup(content, map)
	story_player.music_requested.connect(_change_music)
	story_player.world_action_requested.connect(_world_action)
	story_player.world_node_requested.connect(_world_node)
	story_player.visibility_changed.connect(
		func() -> void:
			if story_player.visible:
				menu_button.hide()
			elif not busy and map.visible:
				menu_button.show()
	)
	# Settings stay above title/story; the story layer owns all battlefield input.
	move_child(menu_layer, get_child_count() - 1)
	save_slots = SaveSlotScreen.new()
	save_slots.name = "SaveSlots"
	add_child(save_slots)
	save_slots.setup(content)
	save_slots.accepted.connect(_accept_save_slot)
	world_inventory_screen = WorldInventoryScreen.new()
	world_inventory_screen.name = "WorldInventory"
	add_child(world_inventory_screen)
	world_inventory = WorldInventory.new(content)
	world_inventory_screen.setup(content, world_inventory)
	world_inventory_screen.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	world_inventory_screen.command_requested.connect(_world_inventory_command)
	for screen: Control in [
		unit_information, item_actions, exchange_screen, target_selection, battle_view
	]:
		screen.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)


func _adopt_content(next_content: Dictionary, next_battle: RefCounted = null) -> void:
	_rebuilding_interface = true
	_reset_tactical_selection()
	_wheel_owner = null
	for child: Node in get_children():
		if child is Control:
			remove_child(child)
			child.queue_free()
	content = next_content
	battle = next_battle if next_battle != null else Battle.new(content, Callable(), false)
	battle_clips = BattleClips.new(content)
	theme = PixelTheme.new().create(content["interface"], content["entry"]["resourceDirectory"])
	_build_interface()
	_rebuilding_interface = false
	_layout()
	_update_music_button()


func _reset_tactical_selection() -> void:
	selected_unit = -1
	choosing_destination = false
	trade_partner = -1
	_target_item = ""
	_target_mode = ""


func _build_battlefield() -> void:
	map = TacticalMap.new()
	map.name = "TacticalMap"
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map.cell_selected.connect(_show_cell)
	map.empty_clicked.connect(func() -> void: unit_panel.hide())
	map.cell_double_clicked.connect(_show_unit_menu)
	map.cell_hovered.connect(_hover_cell)
	map.interacted.connect(_unlock_music)
	map.view_changed.connect(_layout_overlays)
	add_child(map)
	map_hud = MapHud.new()
	map_hud.name = "MapHud"
	add_child(map_hud)
	map_hud.setup(content)
	menu_button = Button.new()
	menu_button.pressed.connect(func() -> void: _set_menu_visible(true))
	menu_button.tooltip_text = "菜单与设置"
	menu_button.focus_mode = Control.FOCUS_NONE
	menu_button.icon = load("res://ui/icons/settings.svg")
	menu_button.expand_icon = true
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style: StyleBox = (
			StyleBoxEmpty.new()
			if state == "normal"
			else get_theme_stylebox(state, "Button").duplicate()
		)
		style.content_margin_left = 4
		style.content_margin_right = 4
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		menu_button.add_theme_stylebox_override(state, style)
	add_child(menu_button)
	unit_panel = UnitMenu.new()
	unit_panel.name = "UnitStatus"
	add_child(unit_panel)
	unit_panel.setup(content)
	unit_panel.intent.connect(_unit_intent)
	unit_information = UnitInformation.new()
	add_child(unit_information)
	unit_information.setup(content)
	item_actions = ItemActions.new()
	item_actions.name = "ItemActions"
	add_child(item_actions)
	item_actions.setup(content)
	item_actions.intent.connect(_item_intent)
	exchange_screen = ExchangeScreen.new()
	exchange_screen.name = "ExchangeScreen"
	add_child(exchange_screen)
	exchange_screen.setup(content)
	exchange_screen.intent.connect(_exchange_intent)
	target_selection = TargetSelection.new()
	target_selection.name = "TargetSelection"
	add_child(target_selection)
	target_selection.setup(content)
	target_selection.intent.connect(_targeting_intent)
	battle_view = BattleView.new()
	battle_view.name = "BattleView"
	add_child(battle_view)
	battle_view.setup(content, battle_clips)
	action_feedback = ActionFeedback.new()
	action_feedback.name = "ActionFeedback"
	add_child(action_feedback)
	action_feedback.setup(content, map, map_hud)
	map_attack_player = MapAttackPlayer.new()
	map_attack_player.name = "MapAttackPlayer"
	add_child(map_attack_player)
	map_attack_player.setup(content, map, map_hud)
	retirement_player = RetirementPlayer.new()
	retirement_player.name = "RetirementPlayer"
	add_child(retirement_player)
	retirement_player.setup(content, map)
	feedback = _label("", 25, GOLD)
	feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	feedback.add_theme_color_override("font_shadow_color", Color.BLACK)
	feedback.add_theme_constant_override("shadow_offset_x", 2)
	feedback.add_theme_constant_override("shadow_offset_y", 2)
	feedback.hide()
	add_child(feedback)


func _build_menu() -> void:
	menu_layer = GameMenu.new()
	add_child(menu_layer)
	menu_layer.setup(content, settings)
	menu_layer.intent.connect(_menu_intent)


func _menu_intent(kind: String, details: Dictionary) -> void:
	match kind:
		"end_turn":
			await _end_turn()
		"close":
			_set_menu_visible(false)
		"save":
			_save_battle()
		"return_title":
			_save_and_title()
		"music":
			_toggle_music()
		"volume":
			settings["volume"] = details["value"]
			player.volume_linear = details["value"]
			_save_settings()
		"game_speed":
			if menu_layer.page == "speed" and details.get("value") in GameMenu.GAME_SPEEDS:
				Engine.time_scale = float(details["value"])
				menu_layer.set_game_speed(Engine.time_scale)
				menu_layer.show_page("settings")
		"overview":
			_show_overview()
		"zoom":
			map.set_zoom(details["value"])
		"assisted_victory":
			if (
				busy
				or title_screen.visible
				or story_player.visible
				or not map.visible
				or not world_progress.is_empty()
				or menu_layer.page != "confirm_victory"
			):
				return
			var result: Dictionary = battle.win_with_assistance()
			if not result["ok"]:
				menu_layer.show_page("assistance")
				menu_layer.set_notice("请完成当前行动后重试。")
				return
			_cancel_selection()
			await _finish_outcome()
		"commander_commit":
			var policy: int = int(details["policy"])
			var result: Dictionary = battle.configure_commander(
				details["commander"], (policy & 1) != 0, (policy & 4) != 0
			)
			if result["ok"]:
				_set_menu_visible(true)
			else:
				push_error("Commander configuration failed: " + str(result))


func _layout() -> void:
	if map == null or _rebuilding_interface:
		return
	var safe := Rect2(Vector2.ZERO, size)
	if OS.has_feature("android") or OS.has_feature("ios"):
		var area := DisplayServer.get_display_safe_area()
		var screen := Vector2(DisplayServer.screen_get_size())
		if screen.x > 0 and screen.y > 0:
			safe = Rect2(Vector2(area.position) * size / screen, Vector2(area.size) * size / screen)
	if _safe_area != safe:
		var pressed: Dictionary = _pressed_pointers.duplicate()
		_pressed_pointers.clear()
		for pointer: int in pressed:
			var release: Variant = pressed[pointer].duplicate()
			release.pressed = false
			release.canceled = true
			# Release native Button capture as well as the map's own gesture state.
			Input.parse_input_event(release)
			_canceled_pointers[pointer] = true
	_safe_area = safe
	if world_inventory_screen != null:
		world_inventory_screen.position = safe.position
		world_inventory_screen.size = safe.size
	map_hud.size = Vector2(safe.size.x, 45 * minf(safe.size.x / 240.0, safe.size.y / 320.0))
	map_hud.position = Vector2(safe.position.x, safe.end.y - map_hud.size.y)
	var footer: float = map_hud.size.y if map_hud.visible else 0
	map.set_play_area(Rect2(safe.position, Vector2(safe.size.x, safe.size.y - footer)))
	menu_button.add_theme_constant_override("icon_max_width", roundi(minf(40, map_hud.size.y / 2)))
	menu_button.size = Vector2.ONE * minf(64, map_hud.size.y - 4)
	menu_button.position.y = safe.end.y - menu_button.size.y - 2
	_layout_overlays(true)


func _layout_overlays(force: bool = false) -> void:
	if story_player == null or menu_layer == null or _rebuilding_interface:
		return
	var safe: Rect2 = _safe_area if _safe_area.has_area() else Rect2(Vector2.ZERO, size)
	var rendered: Rect2 = map.content_rect()
	if not rendered.has_area():
		return
	var area := Rect2(rendered.position.x, safe.position.y, rendered.size.x, safe.size.y)
	var full_screen: bool = title_screen.visible or story_player.background != null
	if selected_unit >= 0:
		var actor: Dictionary = battle.unit(selected_unit)
		unit_panel.place_near(
			Rect2(
				map.view.screen_at(Vector2(actor["x"], actor["y"])),
				Vector2.ONE * MapView.TILE_PIXELS * map.view.zoom
			),
			rendered.grow(-8)
		)
	if not force and area == _overlay_area and full_screen == _full_screen_menu:
		return
	_overlay_area = area
	_full_screen_menu = full_screen
	map_hud.position.x = area.position.x
	map_hud.size.x = area.size.x
	menu_button.position.x = area.end.x - menu_button.size.x - 4
	for screen: Control in [
		unit_information, item_actions, exchange_screen, target_selection, battle_view
	]:
		screen.position = area.position
		screen.size = area.size
	story_player.set_battle_area(area, safe)
	action_feedback.set_content_area(area)
	map_attack_player.set_content_area(area)
	menu_layer.set_safe_rect(safe if full_screen else area)


func _unit_at_cell(cell: Vector2i) -> int:
	for actor: Dictionary in map.visible_units():
		if actor["hp"] > 0 and Vector2i(actor["x"], actor["y"]) == cell:
			return actor["id"]
	return -1


func _hover_cell(cell: Vector2i) -> void:
	if (
		cell.x < 0
		or busy
		or story_player.visible
		or menu_layer.visible
		or unit_panel.visible
		or unit_information.visible
		or item_actions.visible
		or exchange_screen.visible
	):
		return
	map_hud.present(cell, battle.unit(_unit_at_cell(cell)))


func _show_cell(cell: Vector2i) -> void:
	if busy:
		return
	if exchange_screen.visible:
		exchange_screen.select_target(_unit_at_cell(cell))
		return
	if item_actions.visible:
		item_actions.go_back()
		return
	if target_selection.visible:
		if target_selection.page == "items":
			target_selection.go_back()
		else:
			target_selection.select_target(_unit_at_cell(cell))
		return
	# An outside tap only dismisses the popup; it never also commits a move.
	if unit_panel.visible:
		if battle.movement_committed(selected_unit):
			_wait()
		unit_panel.hide()
		return
	var clicked: int = _unit_at_cell(cell)
	if battle.movement_committed(selected_unit) and clicked != selected_unit:
		_cancel_selection()
		return
	if clicked == selected_unit and clicked >= 0:
		return
	if choosing_destination and clicked < 0:
		var moved: Dictionary = battle.move_unit(selected_unit, cell)
		if not moved["ok"]:
			return
		map.selected = cell
		busy = true
		choosing_destination = false
		map.selection_enabled = false
		map.cancel_gesture()
		map.set_movement_field({})
		map.set_units(battle.snapshot()["units"])
		await map.play_move(selected_unit, moved["path"])
		busy = false
		map.selection_enabled = true
		_refresh_selection()
		unit_panel.show()
		_layout()
		return
	if "cancel_move" in battle.actions_for(selected_unit):
		return
	map_hud.present(cell, battle.unit(clicked))
	map.selected = cell
	selected_unit = clicked
	unit_panel.hide()
	choosing_destination = false
	map.set_movement_field({})
	if clicked >= 0:
		# Enemy ranges are inspectable, but only the active faction can act.
		map.set_movement_field(
			battle.movement_field(clicked),
			"enemy" if battle.unit(clicked)["faction"] == 2 else "move"
		)
		_begin_move()


func _show_unit_menu(cell: Vector2i) -> void:
	if busy or target_selection.visible or item_actions.visible or exchange_screen.visible:
		return
	var clicked: int = _unit_at_cell(cell)
	if battle.movement_committed(selected_unit) and clicked != selected_unit:
		_cancel_selection()
		if busy:
			return
	if clicked < 0:
		unit_panel.hide()
		return
	if "cancel_move" in battle.actions_for(selected_unit) and clicked != selected_unit:
		return
	selected_unit = clicked
	map.selected = cell
	_refresh_selection()
	unit_panel.show()
	_layout()


func _refresh_selection() -> void:
	var actor: Dictionary = battle.unit(selected_unit)
	if actor.is_empty():
		unit_panel.hide()
		return
	unit_panel.present(battle.actions_for(selected_unit))
	map_hud.present(Vector2i(actor["x"], actor["y"]), actor)
	_layout()


func _unit_intent(kind: String, _details: Dictionary) -> void:
	if busy:
		return
	match kind:
		"attack", "heal":
			var choices: Array = battle.attack_weapons(selected_unit) if kind == "attack" else []
			var actor: Dictionary = battle.unit(selected_unit)
			if kind == "heal":
				for held: Dictionary in actor["inventory"]:
					if not battle.heal_targets(selected_unit, held["id"]).is_empty():
						choices.append({"item": held})
			unit_panel.hide()
			menu_button.disabled = true
			menu_button.hide()
			map.set_movement_field({})
			var screen: Vector2 = map.view.screen_at(Vector2(actor["x"] + 0.5, actor["y"] + 0.5))
			target_selection.present(choices, kind, screen.x >= size.x / 2)
		"information":
			_show_information()
		"inventory":
			unit_panel.hide()
			menu_button.disabled = true
			item_actions.present(battle.item_options(selected_unit), _item_information())
		"trade":
			_choose_trade_partner()
		"wait":
			_wait()
		"cancel_move":
			_cancel_selection()
		"back":
			_handle_back()
	_layout()


func _begin_move() -> void:
	if busy or "move" not in battle.actions_for(selected_unit):
		return
	choosing_destination = true
	var actor: Dictionary = battle.unit(selected_unit)
	map_hud.present(Vector2i(actor["x"], actor["y"]), actor)
	map.set_movement_field(battle.movement_field(selected_unit))
	unit_panel.hide()


func _item_information() -> Dictionary:
	var information: Dictionary = {}
	for held: Dictionary in battle.item_options(selected_unit).get("equip", []):
		information[held["id"]] = battle.unit_information(selected_unit, held["id"])
	return information


func _item_intent(kind: String, details: Dictionary) -> void:
	if busy:
		return
	match kind:
		"equip", "discard":
			var result: Dictionary = (
				battle.equip_unit(selected_unit, details["item"])
				if kind == "equip"
				else battle.discard_item(selected_unit, details["item"])
			)
			if result["ok"]:
				_refresh_selection()
				item_actions.refresh(battle.item_options(selected_unit), _item_information())
		"use":
			await _present_player_action(battle.use_item(selected_unit, details["item"]))
		"closed":
			menu_button.disabled = false
			_refresh_selection()
			unit_panel.show()


func _exchange_intent(kind: String, details: Dictionary) -> void:
	if busy:
		return
	match kind:
		"target_highlight":
			var target: Dictionary = battle.unit(details["target"])
			map.selected = Vector2i(target["x"], target["y"])
			map.view.focus_cell(map.selected)
			map.queue_redraw()
		"partner_selected":
			trade_partner = int(details["target"])
			if battle.begin_trade(selected_unit, trade_partner)["ok"]:
				map.set_movement_field({})
				exchange_screen.present(battle.unit(selected_unit), battle.unit(trade_partner))
		"trade":
			if (
				battle
				. trade_item(selected_unit, trade_partner, details["item"], details["exchange"])["ok"]
			):
				exchange_screen.present(battle.unit(selected_unit), battle.unit(trade_partner))
		"closed":
			menu_button.disabled = false
			map.set_movement_field({})
			var actor: Dictionary = battle.unit(selected_unit)
			map.selected = Vector2i(actor["x"], actor["y"])
			map.queue_redraw()
			_refresh_selection()
			unit_panel.show()


func _targeting_intent(kind: String, details: Dictionary) -> void:
	if busy:
		return
	match kind:
		"item_selected":
			_target_item = details["item"]
			_target_mode = "heal" if details["action"] == "heal" else "battle_clip"
			if details["action"] == "attack":
				var options: Dictionary = battle.attack_options(selected_unit, _target_item)
				if not options["ok"] or not options["available"]:
					return
				_target_mode = options["actionMode"]
				if _target_mode == "map_attack":
					if options["selection"] == "none":
						await _show_map_forecast(
							battle.map_attack_preview(selected_unit, _target_item)
						)
					else:
						var primary_targets: Array = []
						for id: int in options["primaryTargets"]:
							primary_targets.append(battle.unit(id))
						map.set_action_field(options["rangeCells"], primary_targets, "attack")
						map.action_hint = "选择施法目标"
						target_selection.show_targets(primary_targets)
					return
				var equipped: Dictionary = battle.equip_unit(selected_unit, details["item"])
				if not equipped["ok"]:
					push_error(str(equipped))
					return
			var targets: Array = []
			var ids: Array = (
				battle.heal_targets(selected_unit, details["item"])
				if details["action"] == "heal"
				else battle.attack_targets(selected_unit)
			)
			for id: int in ids:
				targets.append(battle.unit(id))
			var field: Dictionary = (
				battle.healing_field(selected_unit, details["item"])
				if details["action"] == "heal"
				else battle.attack_field(selected_unit)
			)
			map.set_action_field(field, targets, details["action"])
			target_selection.show_targets(targets)
		"target_cancelled":
			map.set_movement_field({})
		"target_highlight":
			var target: Dictionary = battle.unit(details["target"])
			if target.is_empty():
				return
			map.selected = Vector2i(target["x"], target["y"])
			map.view.focus_cell(map.selected)
			if details["action"] == "heal":
				map_hud.present(map.selected, target)
			elif _target_mode == "map_attack":
				var options: Dictionary = battle.attack_options(selected_unit, _target_item)
				var primary_targets: Array = []
				for id: int in options.get("primaryTargets", []):
					primary_targets.append(battle.unit(id))
				map.set_action_field(options.get("rangeCells", {}), primary_targets, "attack")
				map.action_hint = "选择施法目标"
				var area: Dictionary = battle.map_attack_preview(
					selected_unit, _target_item, details["target"]
				)
				map.set_affected_cells(area.get("affectedCells", {}) if area["ok"] else {})
			map.queue_redraw()
		"target_selected":
			if details["action"] == "heal":
				target_selection.hide()
				await _present_player_action(
					battle.heal_unit(selected_unit, details["target"], details["item"])
				)
				return
			if _target_mode == "map_attack":
				await _show_map_forecast(
					battle.map_attack_preview(selected_unit, _target_item, details["target"])
				)
				return
			var preview: Dictionary = battle.attack_preview(selected_unit, details["target"])
			if not preview["ok"]:
				return
			var preloaded: Dictionary = battle_clips.preload_pair(preview)
			if not preloaded["ok"]:
				push_error(preloaded["error"])
				return
			target_selection.show_forecast(preview)
		"attack_confirmed":
			target_selection.hide()
			await _present_player_action(battle.attack_unit(selected_unit, details["target"]))
		"map_attack_confirmed":
			var preview: Dictionary = battle.map_attack_preview(
				selected_unit, _target_item, details["target"]
			)
			if not preview["ok"]:
				return
			var loaded: Dictionary = map_attack_player.preload_effect(preview)
			if not loaded["ok"]:
				push_error(loaded["error"])
				return
			var cast: Dictionary = battle.cast_map_attack(
				selected_unit, _target_item, details["target"]
			)
			if not cast["ok"]:
				push_error(cast["error"])
				target_selection.show_map_forecast(preview)
				return
			target_selection.hide()
			await _present_player_action(cast)
		"closed":
			menu_button.disabled = false
			menu_button.show()
			map.set_movement_field({})
			var actor: Dictionary = battle.unit(selected_unit)
			map.selected = Vector2i(actor["x"], actor["y"])
			map.queue_redraw()
			_refresh_selection()
			unit_panel.show()


func _show_map_forecast(preview: Dictionary) -> void:
	if not preview["ok"]:
		return
	var loaded: Dictionary = map_attack_player.preload_effect(preview)
	if not loaded["ok"]:
		push_error(loaded["error"])
		return
	var affected: Array = []
	for id: int in preview["targetIds"]:
		affected.append(battle.unit(id))
	map.set_action_field(preview["rangeCells"], affected, "attack")
	map.set_affected_cells(preview["affectedCells"])
	map.action_hint = "确认施放范围"
	target_selection.show_map_forecast(preview)


func _wait() -> void:
	if busy:
		return
	var result: Dictionary = battle.wait_unit(selected_unit)
	if result["ok"]:
		choosing_destination = false
		map.set_movement_field({})
		map.set_units(battle.snapshot()["units"])
		unit_panel.hide()
		if not battle.outcome.is_empty():
			await _finish_outcome()


func _cancel_selection() -> void:
	if busy:
		return
	unit_panel.hide()
	map.cancel_gesture()
	if battle.movement_committed(selected_unit):
		_wait()
	if "cancel_move" in battle.actions_for(selected_unit):
		var result: Dictionary = battle.cancel_move()
		if not result["ok"]:
			return
		map.set_units(battle.snapshot()["units"])
		var actor: Dictionary = battle.unit(selected_unit)
		map.selected = Vector2i(actor["x"], actor["y"])
		_begin_move()
	else:
		choosing_destination = false
		selected_unit = -1
		map.selected = Vector2i(-1, -1)
		map.set_movement_field({})
		map.queue_redraw()
		_refresh_selection()


func _set_menu_visible(value: bool) -> void:
	map.cancel_gesture()
	unit_panel.hide()
	if value:
		var view_settings: Dictionary = {}
		if map.visible and not title_screen.visible:
			var minimum: float = map.view.minimum_zoom()
			view_settings = {
				"minimum": minimum, "maximum": maxf(6, minimum), "value": map.view.zoom
			}
		menu_layer.present(
			not busy and battle.can_save(),
			title_screen.visible,
			battle.command_configuration(),
			view_settings
		)
	else:
		menu_layer.hide()
	_unlock_music()
	_layout()


func _active_navigation_target() -> Control:
	for screen: Control in [
		world_inventory_screen, save_slots, menu_layer, story_player, title_screen
	]:
		if screen != null and screen.is_visible_in_tree():
			return screen
	if action_feedback != null and action_feedback.playing:
		return action_feedback
	if map_attack_player != null and map_attack_player.playing:
		return map_attack_player
	for screen: Control in [
		battle_view, target_selection, exchange_screen, item_actions, unit_information, unit_panel
	]:
		if screen != null and screen.is_visible_in_tree():
			return screen
	return null


func _input(event: InputEvent) -> void:
	if (
		event is InputEventScreenTouch
		or (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT)
	):
		var pointer: int = event.index if event is InputEventScreenTouch else -1
		if event.pressed:
			_pressed_pointers[pointer] = event.duplicate()
			_canceled_pointers.erase(pointer)
		elif event.canceled:
			_pressed_pointers.erase(pointer)
		elif _canceled_pointers.has(pointer):
			_canceled_pointers.erase(pointer)
			get_viewport().set_input_as_handled()
			return
		else:
			_pressed_pointers.erase(pointer)
	if (
		event is InputEventMouseButton
		and event.pressed
		and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]
	):
		if _wheel_selection(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1, event.factor):
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and not event.is_echo():
		if OS.get_name() == "Android":
			_handle_system_back()
		else:
			_handle_back()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		if event.pressed:
			_wheel_owner = null
		var owner: Control = _active_navigation_target()
		if owner != null and owner != battle_view and owner.handle_key(event):
			get_viewport().set_input_as_handled()
			return
		if (
			(owner == null or owner == unit_panel)
			and not busy
			and selected_unit >= 0
			and event.pressed
			and not event.echo
			and (
				event.unicode == 35
				or event.keycode == KEY_NUMBERSIGN
				or (event.keycode == KEY_3 and event.shift_pressed)
			)
		):
			_show_information()
			get_viewport().set_input_as_handled()
			return
		var focused: Control = get_viewport().gui_get_focus_owner()
		if (
			(owner == null and busy)
			or owner == battle_view
			or (
				owner != null
				and (focused == null or (focused != owner and not owner.is_ancestor_of(focused)))
			)
		):
			get_viewport().set_input_as_handled()
	elif (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
		_wheel_owner = null


func _wheel_selection(direction: int, factor: float) -> bool:
	var owner: Control = _active_navigation_target()
	if owner == null:
		_wheel_owner = null
		return busy
	var now: int = Time.get_ticks_msec()
	var beginning: bool = (
		owner != _wheel_owner
		or direction != _wheel_direction
		or now - _wheel_last_event_millis >= WHEEL_IDLE_MILLIS
	)
	_wheel_owner = owner
	_wheel_direction = direction
	_wheel_last_event_millis = now
	if beginning:
		_wheel_distance = 0.0
	else:
		# Smooth devices send many fractional detents; never queue a later replay.
		_wheel_distance = minf(1.0, _wheel_distance + absf(factor))
		if _wheel_distance < 1.0 or now - _wheel_last_step_millis < WHEEL_STEP_MILLIS:
			return true
		_wheel_distance = 0.0
	_wheel_last_step_millis = now
	if owner != battle_view:
		owner.handle_wheel(direction)
	return true


func _show_information() -> void:
	map.cancel_gesture()
	var actor: Dictionary = battle.unit(selected_unit)
	var portrait: Dictionary = content["interface"]["portraitByUnitId"][str(selected_unit)]
	var texture: Texture2D
	if portrait["texture"] != null:
		texture = load(
			content["entry"]["resourceDirectory"].path_join(
				content["interface"]["textures"][portrait["texture"]]["texture"]
			)
		)
	else:
		texture = PixelTheme.sprite_icon(
			load(content["entry"]["spriteDirectory"].path_join(actor["sprite"]))
		)
	unit_information.present(actor, battle.unit_information(selected_unit), texture)


func _handle_back() -> void:
	_wheel_owner = null
	var owner: Control = _active_navigation_target()
	if owner == menu_layer:
		if not menu_layer.go_back():
			_set_menu_visible(false)
		return
	if owner == unit_panel:
		_back_from_unit_menu()
		return
	if owner != null:
		if owner != battle_view:
			owner.go_back()
		return
	if busy:
		return
	if selected_unit >= 0:
		_cancel_selection()
	else:
		_set_menu_visible(true)


func _back_from_unit_menu() -> void:
	unit_panel.hide()
	if (
		"cancel_move" in battle.actions_for(selected_unit)
		or battle.movement_committed(selected_unit)
	):
		_cancel_selection()


func _toggle_music() -> void:
	settings["music_enabled"] = not settings["music_enabled"]
	if settings["music_enabled"]:
		_unlock_music()
	else:
		player.stream_paused = true
	_update_music_button()
	_save_settings()


func _unlock_music() -> void:
	if not settings["music_enabled"]:
		return
	if player.stream_paused:
		player.stream_paused = false
	if not player.playing:
		player.play()
	music_started = true
	_update_music_button()


func _update_music_button() -> void:
	menu_layer.set_music_state(settings["music_enabled"], music_started)


func _save_settings() -> void:
	var saved: Dictionary = store.write(settings)
	if not saved["ok"]:
		_report_storage_error(saved)
	else:
		menu_layer.set_notice("")


func _report_storage_error(result: Dictionary) -> void:
	push_error(result["error"])
	menu_layer.set_notice("设置存取失败，请检查可用存储。")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_node_ready():
		_handle_system_back()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_application_paused = true
		player.stream_paused = true
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_application_paused = false
		if music_started and settings["music_enabled"] and player.stream_paused:
			player.stream_paused = false


func _handle_system_back() -> void:
	# Android dispatcher/key paths can straddle synchronous save work.
	if Time.get_ticks_msec() - _last_system_back_millis < 100:
		return
	_handle_back()
	_last_system_back_millis = Time.get_ticks_msec()


func _process(delta: float) -> void:
	if _played_seconds >= 0 and not _application_paused and not title_screen.visible:
		_played_seconds += delta / Engine.time_scale


func _play_minutes() -> int:
	return -1 if _played_seconds < 0 else floori(_played_seconds / 60)


func _label(text: String, font_size: int, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _show_title() -> void:
	busy = true
	story_player.leave_world()
	map.hide()
	map_hud.hide()
	menu_button.hide()
	unit_panel.hide()
	unit_information.hide()
	item_actions.hide()
	exchange_screen.hide()
	target_selection.hide()
	save_slots.hide()
	world_inventory_screen.hide()
	title_screen.refresh_continue(battle_store.has_save())
	title_screen.show()
	_change_music("titleMusic")
	_layout_overlays(true)


func start_new_game() -> void:
	if not title_screen.visible or title_screen.prologue.visible:
		return
	var first: Dictionary = Session.new().open(content["entry"]["chapterPath"])
	if not first["ok"]:
		push_error(first["error"])
		title_screen.message.text = "首关资源无法读取，当前记录已保留。"
		return
	_adopt_content(first["content"], first["battle"])
	_unlock_music()
	world_progress = {}
	_played_seconds = 0
	title_screen.hide()
	map.selected = Vector2i(-1, -1)
	map.set_movement_field({})
	map.set_units(battle.snapshot()["units"])
	map.clear_presentation()
	map.prepare_opening(content["story"]["initialBattlePresentation"])
	map.show()
	var fill_height: float = (
		map.view.viewport_size.y / (float(MapView.TILE_PIXELS) * map.view.grid_size.y)
	)
	map.set_zoom(maxf(3.0, fill_height))
	busy = true
	await story_player.play(content["story"]["sequences"]["newGame"])
	await story_player.play(
		content["story"]["sequences"]["opening"], battle.command_configuration()
	)
	if not await _commit_opening_commander():
		return
	battle.complete_event("opening")
	resume_battle(battle)


func _commit_opening_commander() -> bool:
	while true:
		var configured: Dictionary = battle.configure_commander(
			story_player.selected_commander,
			bool(story_player.selected_policy & 1),
			bool(story_player.selected_policy & 4)
		)
		if configured["ok"]:
			return true
		push_warning("Commander setup rejected: " + str(configured["error"]))
		var configuration: Dictionary = battle.command_configuration()
		if configuration["candidates"].is_empty():
			await story_player.show_notice("当前没有可用指挥官，原进度已保留。", "回到标题")
			_show_title()
			return false
		await story_player.show_notice("当前选择无法配置，请重新选择指挥官。", "重新配置")
		var selected: Dictionary = await story_player.choose_commander(configuration)
		if not selected["ok"]:
			_show_title()
			return false
	return false


func resume_battle(restored_battle: RefCounted) -> void:
	battle = restored_battle
	_reset_tactical_selection()
	busy = false
	menu_button.disabled = false
	map.selection_enabled = true
	title_screen.hide()
	story_player.leave_world()
	menu_layer.hide()
	unit_panel.hide()
	unit_information.hide()
	item_actions.hide()
	exchange_screen.hide()
	target_selection.hide()
	save_slots.hide()
	world_inventory_screen.hide()
	map.clear_presentation()
	map.set_movement_field({})
	map.selected = Vector2i(-1, -1)
	map.set_units(battle.snapshot()["units"])
	var hero: Dictionary = battle.unit(map.focus_hero(false))
	map_hud.present(Vector2i(hero["x"], hero["y"]), hero)
	map.show()
	map_hud.show()
	menu_button.show()
	_change_music("music")
	_layout_overlays(true)


func load_game() -> void:
	if not title_screen.visible or title_screen.prologue.visible:
		return
	_unlock_music()
	var result: Dictionary = battle_store.read()
	if result["ok"]:
		_adopt_content(result["content"], result.get("battle"))
		if result.has("progress"):
			_played_seconds = float(result["progress"].get("elapsedMinutes", -1)) * 60
			await _show_completed_progress(result["progress"])
		else:
			_played_seconds = float(result.get("elapsedMinutes", -1)) * 60
			resume_battle(result["battle"])
	else:
		push_error(result["error"])
		title_screen.message.text = "存档无法读取，原记录已保留。"
		title_screen.message.show()


func _save_battle() -> bool:
	if busy:
		return false
	var result: Dictionary = battle_store.write(battle, _play_minutes())
	if not result["ok"]:
		push_error(result["error"])
		menu_layer.set_notice("当前进度无法保存，请完成行动后重试。")
		return false
	menu_layer.set_notice("进度已保存。", true)
	return true


func _open_save_slots(operation: String) -> void:
	if operation == "save" and world_progress.is_empty():
		return
	_slot_operation = operation
	save_slots.present(operation, _describe_save_slots())


func _describe_save_slots() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for slot: int in range(BattleStore.SLOT_COUNT):
		var result: Dictionary = battle_store.read_slot(slot)
		if result.get("missing", false):
			records.append({"status": "empty"})
		elif not result["ok"]:
			records.append({"status": "invalid"})
		else:
			var progress: Dictionary = result["progress"]
			var minutes: int = int(progress.get("elapsedMinutes", -1))
			var duration: String = (
				"—:—" if minutes < 0 else "%d:%02d" % [minutes / 60, minutes % 60]
			)
			records.append(
				{
					"status": "world",
					"description":
					(
						"第%d战\n%s\n%s"
						% [
							progress["worldStep"],
							content["story"]["world"]["nodes"][int(
								progress.get("worldLocation", progress["worldNode"])
							)]["name"],
							duration
						]
					)
				}
			)
	return records


func _accept_save_slot(slot: int) -> void:
	if _slot_operation == "save":
		var progress: Dictionary = _world_snapshot()
		var written: Dictionary = battle_store.write_slot(slot, progress)
		if not written["ok"]:
			push_warning(str(written))
			save_slots.show_error("存档无法写入，原记录已保留。")
			return
		world_progress = progress
		save_slots.refresh(_describe_save_slots())
	else:
		var result: Dictionary = battle_store.read_slot(slot)
		if not result["ok"]:
			push_warning(str(result))
			save_slots.show_error("存档无法读取，原记录已保留。")
			return
		_played_seconds = float(result["progress"].get("elapsedMinutes", -1)) * 60
		_adopt_content(result["content"])
		await _show_completed_progress(result["progress"])


func _save_and_title() -> void:
	if _save_battle():
		menu_layer.hide()
		_show_title()


func _change_music(kind: String) -> void:
	var stream: AudioStreamOggVorbis = load(content["entry"][kind])
	if player.stream == stream:
		return
	stream.loop = kind not in ["victoryMusic", "defeatMusic"]
	player.stream = stream
	if music_started and settings["music_enabled"]:
		player.play()


func _show_overview() -> void:
	map.show_overview()
	_set_menu_visible(false)


func _choose_trade_partner() -> void:
	var targets: Array = []
	for id: int in battle.trade_targets(selected_unit):
		targets.append(battle.unit(id))
	unit_panel.hide()
	menu_button.disabled = true
	map.set_action_field(battle.trade_field(selected_unit), targets, "trade")
	exchange_screen.choose_partner(targets)


func _present_player_action(result: Dictionary) -> void:
	if not result["ok"]:
		return
	busy = true
	menu_button.disabled = true
	map.selection_enabled = false
	choosing_destination = false
	unit_panel.hide()
	item_actions.hide()
	map.set_movement_field({})
	map.set_units(battle.snapshot()["units"])
	await _present_action_visuals(result)
	busy = false
	menu_button.disabled = false
	menu_button.show()
	map.selection_enabled = true
	if not battle.outcome.is_empty():
		await _finish_outcome()


func _present_action_visuals(result: Dictionary) -> void:
	if result.get("kind") == "combat":
		if not result.get("storyBefore", []).is_empty():
			var before_units: Array = battle.snapshot()["units"]
			for index: int in range(before_units.size()):
				for participant: Dictionary in result["participants"]:
					if before_units[index]["id"] == participant["id"]:
						before_units[index] = participant.duplicate(true)
			map.set_units(before_units)
			for sequence: String in result["storyBefore"]:
				await story_player.play(content["story"]["sequences"][sequence])
			map.set_units(battle.snapshot()["units"])
		_change_music("battleMusic")
		var played: Dictionary = await battle_view.play(result)
		_change_music("music")
		if not played["ok"]:
			push_error(played["error"])
			await story_player.show_notice("战斗演出无法播放，结算结果已保留。", "继续")
		await _present_retirements(result.get("retirements", []))
	elif result.get("kind") == "map_attack":
		var played: Dictionary = await map_attack_player.play(result, battle.snapshot()["units"])
		if not played["ok"]:
			push_error(played["error"])
			await story_player.show_notice("法术演出无法播放，结算结果已保留。", "继续")
	if await action_feedback.play(
		result,
		battle.snapshot()["units"],
		battle.event_completed("level_tutorial"),
		battle.phase == 0
	):
		battle.complete_event("level_tutorial")
	map.set_units(battle.snapshot()["units"])
	if not map_hud.actor.is_empty():
		var actor: Dictionary = battle.unit(int(map_hud.actor["id"]))
		map_hud.present(Vector2i(actor["x"], actor["y"]), actor)


func _present_retirements(retirements: Array) -> void:
	if retirements.is_empty():
		return
	var displayed: Array = battle.snapshot()["units"]
	for retirement: Dictionary in retirements:
		for actor: Dictionary in displayed:
			if actor["id"] == retirement["unitId"]:
				# Damage and death are committed. Only the map copy waits for the dialogue.
				actor["visible"] = true
				actor["flags"] &= ~1
	map.set_units(displayed)
	for retirement: Dictionary in retirements:
		for sequence: String in retirement["beforeRetirement"]:
			await story_player.play(content["story"]["sequences"][sequence])
		await story_player.play([{"kind": "focus", "unitId": retirement["unitId"]}])
		var played: Dictionary = await retirement_player.play(battle.unit(retirement["unitId"]))
		if not played["ok"]:
			push_error(played["error"])
			await story_player.show_notice("退场演出无法播放，结算结果已保留。", "继续")
		for sequence: String in retirement["afterRetirement"]:
			await story_player.play(content["story"]["sequences"][sequence])
	map.set_units(battle.snapshot()["units"])


func _end_turn() -> void:
	if busy:
		return
	var advanced: Dictionary = battle.end_phase()
	if not advanced["ok"]:
		menu_layer.set_notice("请先完成或取消当前行动。")
		return
	busy = true
	menu_button.disabled = true
	map.selection_enabled = false
	map.cancel_gesture()
	menu_layer.hide()
	unit_panel.hide()
	map.set_movement_field({})
	selected_unit = -1
	choosing_destination = false
	var tick_seconds: float = float(content["battleClips"]["tickMillis"]) / 1000
	while battle.phase != 0 and battle.outcome.is_empty():
		await _phase_banner("友军行动" if battle.phase == 1 else "敌军行动")
		while battle.automatic_actor() >= 0 and battle.outcome.is_empty():
			var id: int = battle.automatic_actor()
			var actor: Dictionary = battle.unit(id)
			map.selected = Vector2i(actor["x"], actor["y"])
			map.view.focus_cell(map.selected)
			map_hud.present(map.selected, actor)
			await get_tree().create_timer(2 * tick_seconds).timeout
			map.set_movement_field(
				battle.movement_field(id), "enemy" if battle.phase == 2 else "move"
			)
			await get_tree().create_timer(4 * tick_seconds).timeout
			var began: Dictionary = battle.begin_automatic_action(id)
			if not began["ok"]:
				await _automatic_error(began)
				return
			map.set_units(battle.snapshot()["units"])
			# The committed destination must not flash before the planned route and movement.
			map.presentation_positions[id] = Vector2(began["path"][0])
			map.selected = began["path"][-1]
			map.preview_route(began["path"])
			await get_tree().create_timer(4 * tick_seconds).timeout
			await map.play_move(id, began["path"])
			map.presentation_positions.erase(id)
			map.set_movement_field({})
			var plan: Dictionary = began["plan"]
			if plan.get("actionMode") == "map_attack":
				var preview: Dictionary = battle.map_attack_preview(
					id, plan["mapItem"], plan["mapPrimary"]
				)
				if not preview["ok"]:
					await _automatic_error(preview)
					return
				var loaded: Dictionary = map_attack_player.preload_effect(preview)
				if not loaded["ok"]:
					await _automatic_error(loaded)
					return
				var targets: Array = []
				for target: int in preview["targetIds"]:
					targets.append(battle.unit(target))
				map.set_action_field(preview["rangeCells"], targets, "attack")
				map.set_affected_cells(preview["affectedCells"])
				map.action_hint = "敌军施法" if battle.phase == 2 else "友军施法"
				await get_tree().create_timer(10 * tick_seconds).timeout
				map.set_movement_field({})
				var cast: Dictionary = battle.cast_map_attack(
					id, plan["mapItem"], plan["mapPrimary"]
				)
				if not cast["ok"]:
					await _automatic_error(cast)
					return
				await _present_action_visuals(cast)
				await get_tree().create_timer(6 * tick_seconds).timeout
				continue
			var result: Dictionary
			var target_id: int = int(plan["attackTarget"])
			if target_id < 0:
				target_id = int(plan["healTarget"])
			if target_id >= 0:
				var target: Dictionary = battle.unit(target_id)
				var healing: bool = int(plan["healTarget"]) >= 0
				map.set_action_field(
					(
						battle.healing_field(id, plan["healItem"])
						if healing
						else battle.attack_field(id)
					),
					[target],
					"heal" if healing else "attack"
				)
				map.action_hint = "友军治疗" if healing else "敌军攻击" if battle.phase == 2 else "友军攻击"
				map.selected = Vector2i(target["x"], target["y"])
				map.view.focus_cell(map.selected)
				await get_tree().create_timer(10 * tick_seconds).timeout
			map.set_movement_field({})
			if plan["attackTarget"] >= 0:
				var preloaded: Dictionary = battle_clips.preload_pair(
					battle.attack_preview(id, plan["attackTarget"])
				)
				if not preloaded["ok"]:
					await _automatic_error(preloaded)
					return
				result = battle.attack_unit(id, plan["attackTarget"])
			elif plan["healTarget"] >= 0:
				result = battle.heal_unit(id, plan["healTarget"], plan["healItem"])
			else:
				result = battle.wait_unit(id)
			if not result["ok"]:
				await _automatic_error(result)
				return
			await _present_action_visuals(result)
			if target_id >= 0:
				await get_tree().create_timer(6 * tick_seconds).timeout
		if not battle.outcome.is_empty():
			break
		advanced = battle.end_phase()
		if not advanced["ok"]:
			await _automatic_error(advanced)
			return
		await _present_phase_events(advanced["events"])
	if not battle.outcome.is_empty():
		await _finish_outcome()
		return
	await _phase_banner("第 %d 回合" % battle.round_number)
	busy = false
	menu_button.disabled = false
	menu_button.show()
	map.selection_enabled = true
	map.selected = Vector2i(-1, -1)
	map.set_units(battle.snapshot()["units"])
	var hero: Dictionary = battle.unit(map.focus_hero(false))
	map_hud.present(Vector2i(hero["x"], hero["y"]), hero)


func _present_phase_events(events: Array) -> void:
	for event: Dictionary in events:
		if event["kind"] != "reinforcements":
			continue
		if event.get("sequence", "").is_empty():
			map.set_units(battle.snapshot()["units"])
			continue
		var sequence: Array = content["story"]["sequences"][event["sequence"]].duplicate(true)
		var arrivals: Dictionary = {}
		for arrival: Dictionary in event["arrivals"]:
			map.presentation_hidden_ids.append(int(arrival["unit"]))
			arrivals[int(arrival["unit"])] = arrival
		for step: Dictionary in sequence:
			if step["kind"] != "parallelEntrances":
				continue
			var entrances: Array = []
			for entrance: Dictionary in step["units"]:
				var id: int = int(entrance["unitId"])
				if not arrivals.has(id):
					continue
				var destination: Vector2i = arrivals[id]["to"]
				var origin := Vector2i(entrance["from"][0], entrance["from"][1])
				var previous := Vector2i(entrance["to"][0], entrance["to"][1])
				origin += destination - previous
				entrance["from"] = [origin.x, origin.y]
				entrance["to"] = [destination.x, destination.y]
				entrances.append(entrance)
			step["units"] = entrances
		map.set_units(battle.snapshot()["units"])
		await story_player.play(sequence)
		map.clear_presentation()


func _phase_banner(text: String) -> void:
	feedback.text = text
	feedback.reset_size()
	feedback.position = (size - feedback.size) / 2.0
	feedback.show()
	await get_tree().create_timer(0.6).timeout
	feedback.hide()


func _automatic_error(result: Dictionary) -> void:
	push_error("Automatic action failed: " + str(result))
	await story_player.show_notice("行动无法继续，已保留上次存档。", "回到标题")
	_show_title()


func _show_completed_progress(progress: Dictionary, guidance: bool = false) -> void:
	busy = true
	_reset_tactical_selection()
	world_progress = progress.duplicate(true)
	save_slots.hide()
	world_inventory_screen.hide()
	title_screen.hide()
	menu_layer.hide()
	unit_panel.hide()
	map.hide()
	map_hud.hide()
	menu_button.hide()
	await story_player.show_world(progress, guidance)


func _world_action(kind: String) -> void:
	if (
		not story_player.world_active
		or not story_player.world_ready
		or not story_player.choices.visible
		or story_player.dialogue.visible
		or save_slots.visible
		or world_progress.is_empty()
	):
		return
	if kind in ["save", "load"]:
		_open_save_slots(kind)
	elif kind == "inventory":
		story_player.go_back()
		world_inventory_screen.present(world_progress)
	elif kind == "gold":
		var progress: Dictionary = world_progress.duplicate(true)
		var received: int = mini(WORLD_GOLD_BENEFIT, Battle.MAX_GOLD - int(progress["gold"]))
		if received == 0:
			await story_player.show_world_notice("资金已达到上限。")
			return
		progress["gold"] += received
		var saved: Dictionary = _commit_world_progress(progress)
		if not saved["ok"]:
			push_warning(str(saved))
			await story_player.show_world_notice("领取未完成，当前进度未改变，请重试。")
			return
		await story_player.show_world_notice("获得%d金币。现有资金：%d。" % [received, int(progress["gold"])])
	elif kind == "title":
		var saved: Dictionary = _commit_world_progress(world_progress)
		if not saved["ok"]:
			push_warning(str(saved))
			await story_player.show_world_notice("保存未完成，当前进度仍在，请重试。")
			return
		_show_title()


func _world_inventory_command(operation: String, details: Dictionary) -> void:
	if not world_inventory_screen.visible or not story_player.world_active:
		return
	var result: Dictionary = world_inventory.apply(world_progress, operation, details)
	if result["ok"]:
		var progress: Dictionary = result["progress"]
		if progress != world_progress:
			var saved: Dictionary = _commit_world_progress(progress)
			if not saved["ok"]:
				push_warning("World inventory save failed: " + str(saved))
				world_inventory_screen.complete(
					{"ok": false, "error": "SAVE_FAILED"}, world_progress
				)
				return
	world_inventory_screen.complete(result, world_progress)


func _commit_world_progress(candidate: Dictionary) -> Dictionary:
	var progress: Dictionary = candidate.duplicate(true)
	var minutes: int = _play_minutes()
	if minutes >= 0:
		progress["elapsedMinutes"] = minutes
	var saved: Dictionary = battle_store.write_progress(progress)
	if not saved["ok"]:
		return saved
	world_progress = progress
	return {"ok": true}


func _world_snapshot() -> Dictionary:
	var progress: Dictionary = world_progress.duplicate(true)
	var minutes: int = _play_minutes()
	if minutes >= 0:
		progress["elapsedMinutes"] = minutes
	return progress


func _world_node(node_id: int) -> void:
	if (
		_world_transitioning
		or world_progress.is_empty()
		or not story_player.world_ready
		or save_slots.visible
		or world_inventory_screen.visible
	):
		return
	var path: Array = content["story"]["world"]["routes"][int(world_progress["route"])]
	var step: int = int(world_progress.get("worldStep", 1))
	if path.slice(0, step).any(func(id: Variant) -> bool: return id == node_id):
		_world_transitioning = true
		var visited: Dictionary = world_progress.duplicate(true)
		visited["worldLocation"] = node_id
		var saved_location: Dictionary = _commit_world_progress(visited)
		if saved_location["ok"]:
			await story_player.travel_to(node_id, false)
		else:
			push_error(str(saved_location))
			await story_player.show_world_notice("地点无法保存，当前进度已保留。")
		_world_transitioning = false
		return
	if step >= path.size() or path[step] != node_id:
		await story_player.show_world_notice("请选择路线中亮起的下一目标。")
		return
	var next_id: String = "m%d" % node_id
	if not content["entry"].get("battles", {}).has(next_id):
		await story_player.show_world_notice("这一关卡内容尚在制作，当前进度已保留。")
		return
	var opened: Dictionary = Session.new().open(
		content["entry"]["chapterPath"], next_id, {"progress": world_progress}
	)
	if not opened["ok"]:
		push_error(str(opened))
		await story_player.show_world_notice("关卡数据无法加载，当前进度已保留。")
		return
	_world_transitioning = true
	if not await story_player.confirm_travel(node_id):
		_world_transitioning = false
		return
	await story_player.travel_to(node_id)
	_adopt_content(opened["content"], opened["battle"])
	busy = true
	title_screen.hide()
	map.set_units(battle.snapshot()["units"])
	map.prepare_opening(content["story"]["initialBattlePresentation"])
	map_hud.hide()
	menu_button.hide()
	await story_player.play(
		content["story"]["sequences"]["opening"], battle.command_configuration()
	)
	if not await _commit_opening_commander():
		_world_transitioning = false
		return
	battle.complete_event("opening")
	var saved: Dictionary = battle_store.write(battle, _play_minutes())
	while not saved["ok"]:
		push_error(str(saved))
		await story_player.show_notice("下一战进度无法保存，原记录已保留。请检查存储后重试。", "重试保存")
		saved = battle_store.write(battle, _play_minutes())
	world_progress = {}
	_world_transitioning = false
	resume_battle(battle)


func _finish_outcome() -> void:
	busy = true
	unit_panel.hide()
	menu_layer.hide()
	map.set_movement_field({})
	map.set_units(battle.snapshot()["units"])
	map_hud.hide()
	menu_button.hide()
	if battle.outcome["kind"] == "victory":
		await story_player.play(content["story"]["sequences"]["victory"])
		var routes: Array = content["story"]["routeChoices"]
		var route: int = (
			int(routes[0]["routeIndex"]) if routes.size() == 1 else story_player.selected_route
		)
		var completed: Dictionary = battle.complete_victory(route)
		if not completed["ok"]:
			push_error(completed["error"])
			await story_player.show_notice("关卡结算失败，原存档已保留。", "回到标题")
			_show_title()
			return
		var progress: Dictionary = completed["progress"].duplicate(true)
		var minutes: int = _play_minutes()
		if minutes >= 0:
			progress["elapsedMinutes"] = minutes
		var saved: Dictionary = battle_store.write_progress(progress)
		while not saved["ok"]:
			push_error(saved["error"])
			await story_player.show_notice("保存失败，原记录已保留。请检查可用存储后重试。", "重试保存")
			saved = battle_store.write_progress(progress)
		await _show_completed_progress(progress, true)
	else:
		await story_player.play(content["story"]["sequences"]["defeat"])
		_show_title()
