extends SceneTree


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var scene: Control = load("res://app/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var story: Control = scene.story_player
	var progress: Dictionary = {
		"chapterCompleted": true,
		"chapterResult":
		{
			"party": [{"id": 0, "level": 12, "power": 123}],
			"gold": 6000,
			"totalPower": 123,
			"chapterStats": {"rounds": null, "playerRetirements": null, "allyRetirements": null}
		}
	}
	var before: Dictionary = progress.duplicate(true)
	story.present_chapter_result(progress, false)
	await process_frame
	if story.dialogue.full_text != "Lv 12\n战斗力 123":
		fail("Chapter records must show the saved personal level and power")
		return
	story.advance()
	await process_frame
	if story.dialogue.full_text != "总资金 6000\n指挥能力 未记录\n总战斗力 123\n总回合 未记录":
		fail("Legacy chapter records must disclose unknown history rather than invent zero")
		return
	story.go_back()
	await process_frame
	if story.dialogue.full_text != "无法评定（旧记录缺少累计数据）":
		fail("Unknown legacy history must not receive a fabricated rating")
		return
	story.go_back()
	await process_frame
	if story.visible or progress != before:
		fail("Finishing the read-only record must leave its source snapshot untouched")
		return
	progress["chapterResult"]["totalPower"] = 4001
	progress["chapterResult"]["party"][0]["power"] = 4001
	story.present_chapter_result(progress, false)
	await process_frame
	story.advance()
	await process_frame
	story.advance()
	await process_frame
	if story.dialogue.full_text != "SSS":
		fail("Power above 4000 must still determine SSS with unknown legacy counters")
		return
	story.advance()
	await process_frame
	scene.queue_free()
	await process_frame
	print("PASS chapter record UI: saved party, summary, legacy unknown, SSS, Back, read-only")
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
