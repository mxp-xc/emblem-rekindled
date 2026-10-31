extends RefCounted

var path: String


func _init(settings_path: String = "user://settings.json") -> void:
	path = settings_path


func read() -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": true, "missing": true, "settings": {"volume": 0.45, "music_enabled": false}}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("无法打开设置: " + error_string(FileAccess.get_open_error()))
	var json := JSON.new()
	var parse_error: Error = json.parse(file.get_as_text())
	if (
		parse_error != OK
		or not json.data is Dictionary
		or json.data.get("version") != 1
		or not _valid(json.data)
	):
		return _failure("设置文件损坏或版本不受支持")
	return {
		"ok": true,
		"missing": false,
		"settings":
		{"volume": float(json.data["volume"]), "music_enabled": json.data["music_enabled"]}
	}


func write(settings: Dictionary) -> Dictionary:
	if not _valid(settings):
		return _failure("设置值无效")
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _failure("无法写入临时设置: " + error_string(FileAccess.get_open_error()))
	file.store_string(
		JSON.stringify(
			{"version": 1, "volume": settings["volume"], "music_enabled": settings["music_enabled"]}
		)
	)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temporary)
		return _failure("设置写入失败: " + error_string(write_error))
	var replace_error: Error = DirAccess.rename_absolute(temporary, path)
	if replace_error != OK:
		DirAccess.remove_absolute(temporary)
		return _failure("无法替换设置，原记录保留: " + error_string(replace_error))
	return {"ok": true}


func _valid(settings: Dictionary) -> bool:
	var volume: Variant = settings.get("volume")
	return (
		(volume is float or volume is int)
		and is_finite(float(volume))
		and volume >= 0.0
		and volume <= 1.0
		and settings.get("music_enabled") is bool
	)


func _failure(message: String) -> Dictionary:
	return {"ok": false, "missing": false, "error": message}
