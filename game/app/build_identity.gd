extends RefCounted

const PATH := "res://content/build_info.json"


static func current() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {"buildId": "development"}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not value is Dictionary or not value.get("buildId") is String:
		push_error("Invalid build identity")
		return {}
	return value


static func publish() -> void:
	var identity := current()
	print("EMBLEM_BUILD " + JSON.stringify(identity))
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var bridge := Engine.get_singleton("JavaScriptBridge")
		bridge.eval(
			(
				"document.getElementById('canvas').dataset.emblemBuildId = "
				+ JSON.stringify(identity.get("buildId", "invalid"))
			),
			true
		)
