extends SceneTree

const Flow = preload("res://tests/test_m12_flow.gd")
const Matrix = preload("res://tests/test_m12_content.gd")
const Store = preload("res://persistence/battle_store.gd")
const Clips = preload("res://app/battle_clip_library.gd")
var _owned: String = ""
var _draws: int = 0


func _initialize() -> void:
	_owned = "user://m12_combat_%d" % Time.get_ticks_usec()
	if not _expect(DirAccess.make_dir_absolute(_owned) == OK, "Claim owned combat records"):
		return
	var opened: Dictionary = Flow.prepare_boundary(Matrix.CONTEXTS[0], 1, "ordinary")
	if not _expect(
		opened["ok"], "Prepare actual boss ordinary boundary: " + str(opened.get("error"))
	):
		return
	var battle: RefCounted = opened["battle"]
	var content: Dictionary = opened["content"]
	var library := Clips.new(content)
	var preview: Dictionary = battle.attack_preview(0, 89)
	if not _expect(
		preview["ok"] and library.preload_pair(preview)["ok"],
		"Real sword versus boss89 resolves ordinary clips"
	):
		return
	var first: Dictionary = battle.attack_unit(0, 89)
	if not _expect(
		(
			first["ok"]
			and first["storyBefore"] == ["boss_first_combat"]
			and first["retirements"].is_empty()
			and battle.event_completed("boss_first_combat")
			and (int(battle.unit(89)["flags"]) & 4) != 0
			and library.prepare(first)["ok"]
		),
		"Ordinary boss first combat schedules593 and native first flag once"
	):
		return
	var store := Store.new(content, _owned.path_join("first.json"))
	if not _expect(store.write(battle)["ok"], "Write actual post-first battle record"):
		return
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(store.path))
	_draws = 0
	var cold: Dictionary = store.decode(record, _roll)
	var read: Dictionary = store.read()
	if not _expect(
		(
			cold["ok"]
			and read["ok"]
			and _draws == 0
			and cold["battle"].snapshot() == battle.snapshot()
			and read["battle"].snapshot() == battle.snapshot()
		),
		"Actual first-combat JSON cold read preserves once flag with zero decode RNG"
	):
		return
	battle = cold["battle"]
	var state: Dictionary = battle.snapshot()
	Flow.duel_state(state, 89, true)
	if not _expect(
		battle.restore_snapshot(state)["ok"], "Prepare lethal boss boundary after cold first combat"
	):
		return
	var killed: Dictionary = battle.attack_unit(0, 89)
	var loot: Array = killed.get("rewards", {}).get("loot", [])
	if not _expect(
		(
			killed["ok"]
			and killed["storyBefore"].is_empty()
			and (
				killed["retirements"]
				== [
					{
						"unitId": 89,
						"beforeRetirement": ["boss_before_retirement"],
						"afterRetirement": []
					}
				]
			)
			and battle.event_completed("boss_death")
			and battle.unit(89)["hp"] == 0
			and not battle.unit(89)["visible"]
			and battle.outcome.is_empty()
			and loot.size() == 1
			and loot[0]["item"]["templateId"] == 57
			and loot[0]["item"]["durability"] == 4
			and library.prepare(killed)["ok"]
		),
		"Ordinary594 precedes89 retirement, drops actual57x4, and other visible enemies prevent victory"
	):
		return
	if not _expect(store.write(battle)["ok"], "Boss-only retirement remains stable and resumable"):
		return
	var after: Dictionary = store.read()
	if not _expect(
		after["ok"] and after["battle"].snapshot() == battle.snapshot(),
		"Cold boss-only record retains57 identity and completed593/594"
	):
		return
	_cleanup()
	print("PASS m12 ordinary593/594,real57 drop,boss-only not victory,cold records")
	quit(0)


func _roll(_limit: int) -> int:
	_draws += 1
	return 0


func _cleanup() -> void:
	if _owned.is_empty():
		return
	for name: String in DirAccess.get_files_at(_owned):
		DirAccess.remove_absolute(_owned.path_join(name))
	DirAccess.remove_absolute(_owned)
	_owned = ""


func _expect(condition: bool, message: String) -> bool:
	if not condition:
		push_error(message)
		_cleanup()
		quit(1)
	return condition
