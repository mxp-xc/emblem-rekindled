extends RefCounted

const MAX_EXPANDED_BYTES := 64 * 1024 * 1024


static func read(path: String) -> Variant:
	var text: String
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return null
		text = file.get_as_text()
	elif FileAccess.file_exists(path + ".gz"):
		var file := FileAccess.open(path + ".gz", FileAccess.READ)
		if file == null:
			return null
		var compressed := file.get_buffer(file.get_length())
		if compressed.size() < 2 or compressed[0] != 0x1f or compressed[1] != 0x8b:
			return null
		var bytes := compressed.decompress_dynamic(MAX_EXPANDED_BYTES, FileAccess.COMPRESSION_GZIP)
		if bytes.is_empty():
			return null
		text = bytes.get_string_from_utf8()
	else:
		return null
	return JSON.parse_string(text)
