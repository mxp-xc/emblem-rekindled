extends RefCounted


static func step_buttons(rows: Array[Button], direction: int) -> void:
	if rows.is_empty():
		return
	var focused: Control = rows[0].get_viewport().gui_get_focus_owner()
	var index: int = rows.find(focused)
	rows[posmod(index + direction, rows.size()) if index >= 0 else 0].grab_focus()
