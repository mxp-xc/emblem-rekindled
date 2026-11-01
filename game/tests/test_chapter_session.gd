extends SceneTree

const Session = preload("res://app/chapter_session.gd")
const Store = preload("res://persistence/battle_store.gd")
const CHAPTER: String = "res://content/chapter_1/chapter.json"
var _draws: int = 0


func _initialize() -> void:
	var session := Session.new()
	var first: Dictionary = session.open(CHAPTER, "", {"new": true}, _roll)
	if not _expect(first["ok"], "New game must open the chapter's configured first battle"):
		return
	var original: Dictionary = first["battle"].snapshot()
	if not _expect(_draws > 0, "New game must draw initial results through the supplied source"):
		return
	_draws = 0
	var restored: Dictionary = session.open(CHAPTER, "m0", {"snapshot": original}, _roll)
	if not _expect(
		restored["ok"] and _draws == 0 and restored["battle"].snapshot() == original,
		"Snapshot opening must restore all existing results without initial random draws"
	):
		return
	var first_battle: RefCounted = first["battle"]
	first_battle.win_with_assistance()
	var progress: Dictionary = first_battle.complete_victory(0)["progress"]
	progress["party"].reverse()
	var preserved: Dictionary = progress.duplicate(true)
	var second: Dictionary = session.open(CHAPTER, "m1", {"progress": progress}, _roll)
	if not _expect(second["ok"] and progress == preserved, "World entry must preserve its input"):
		return
	if not _expect(
		(
			second["battle"].unit(0)["x"] == 1
			and second["battle"].unit(0)["y"] == 15
			and second["battle"].unit(9)["x"] == 0
			and second["battle"].unit(9)["y"] == 15
		),
		"Recruit order, rather than the party array order, must determine m1's deployment slots"
	):
		return
	var saved: Dictionary = Store.new(first["content"]).encode(second["battle"])
	if not _expect(saved["ok"], "The chapter store must encode the actual second-battle identity"):
		return
	_draws = 0
	var reopened: Dictionary = Store.new(first["content"]).decode(saved["record"], _roll)
	if not _expect(
		(
			reopened["ok"]
			and _draws == 0
			and reopened["battle"].snapshot() == second["battle"].snapshot()
		),
		"Continue decoding must bind the actual roster and avoid initializing a replacement battle"
	):
		return
	var completed: Dictionary = session.completed_content(CHAPTER, progress)
	if not _expect(
		(
			completed["ok"]
			and completed["content"]["entry"]["battleId"] == "m0"
			and completed["content"]["story"]["battleNumber"] == 1
			and second["content"]["story"]["battleNumber"] == 2
		),
		"A completed world record and its next battle must use different world-step contexts"
	):
		return
	var malformed: Dictionary = progress.duplicate(true)
	malformed["gold"] = -1
	var before: Dictionary = malformed.duplicate(true)
	if not _expect(
		not session.open(CHAPTER, "m1", {"progress": malformed})["ok"] and malformed == before,
		"Invalid inherited business state must fail without publishing or mutating its source"
	):
		return
	for source: Dictionary in [{}, {"new": true, "progress": progress}, {"new": false}]:
		if not _expect(
			not session.open(CHAPTER, "", source)["ok"], "Opening sources are exclusive"
		):
			return
	print(
		"PASS chapter session: new/world/snapshot entry, roster order, zero-draw restore and isolation"
	)
	quit(0)


func _roll(_limit: int) -> int:
	_draws += 1
	return 0


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		quit(1)
	return condition
