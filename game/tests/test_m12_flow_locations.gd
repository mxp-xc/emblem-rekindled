extends "res://tests/test_m12_flow_combat.gd"

const Battle = preload("res://gameplay/battle_state.gd")
const CELLS: Array[Vector2i] = [Vector2i(1, 1), Vector2i(8, 20), Vector2i(15, 20), Vector2i(22, 1)]
const GROUPS: Array = [[30, 66, 57, 58], [32, 65, 63, 64], [61, 62, 68, 33], [67, 31, 60, 59]]
const CHOICES: Array = [
	[[39, 30], [33, 70]], [[2, 70], [10, 30]], [[15, 70], [19, 30]], [[25, 70], [27, 30]]
]
var _last: bool = false


func _initialize() -> void:
	_owned = "user://m12_locations_%d" % Time.get_ticks_usec()
	if not _expect(
		DirAccess.make_dir_absolute(_owned) == OK, "Claim owned actual-location records"
	):
		return
	var opened: Dictionary = Flow.prepare_boundary(Matrix.CONTEXTS[1], 1)
	if not _expect(opened["ok"], "Open actual m12 location configuration"):
		return
	var content: Dictionary = opened["content"]
	var initial: Dictionary = opened["battle"].snapshot()
	if not _expect(
		content["map"]["locations"].size() == 4 and content["story"]["locationEvents"].size() == 4,
		"Actual m12 declares four source-order locations and four ambush groups"
	):
		return
	for index: int in range(4):
		var location: Dictionary = content["map"]["locations"][index]
		var configured: Dictionary = content["story"]["locationEvents"][index]
		var choices: Array = []
		for choice: Dictionary in location["weightedChoices"]:
			choices.append([int(choice["templateId"]), int(choice["weight"])])
		var group: Array[int] = []
		for identity: Variant in configured["unitIds"]:
			group.append(int(identity))
		if not _expect(
			(
				location["id"] == "chest_%d" % index
				and location["sourceIndex"] == index
				and Vector2i(location["position"][0], location["position"][1]) == CELLS[index]
				and choices == CHOICES[index]
				and configured["locationId"] == location["id"]
				and group == GROUPS[index]
			),
			(
				"Native chest%d retains source order, weighted table and its exact four-unit group"
				% index
			)
		):
			return
		for last: bool in [false, true]:
			_last = last
			var state: Dictionary = initial.duplicate(true)
			for actor: Dictionary in state["units"]:
				if actor["id"] == 0:
					actor["x"] = CELLS[index].x
					actor["y"] = CELLS[index].y
					actor["inventory"] = []
					actor["equippedInstanceId"] = ""
			var battle := Battle.new(content, _roll, false)
			_draws = 0
			if not _expect(
				battle.restore_snapshot(state)["ok"] and _draws == 0,
				"Actual location restore does not draw an unopened reward"
			):
				return
			var leader: Dictionary = battle.unit(GROUPS[index][0])
			var focus := Vector2i(leader["x"], leader["y"])
			if index == 0:
				var waited: Dictionary = battle.wait_unit(0)
				if not _expect(
					(
						waited["ok"]
						and not battle.event_completed("location:chest_0")
						and _draws == 0
						and battle.restore_snapshot(state)["ok"]
					),
					"Waiting on an m12 chest leaves it unopened and consumes no reward draw"
				):
					return
			var result: Dictionary = battle.open_chest(0)
			var arrivals: Array[int] = []
			for arrival: Dictionary in result.get("locationEvent", {}).get("arrivals", []):
				arrivals.append(int(arrival["unit"]))
			if not _expect(
				(
					result["ok"]
					and result["claimed"]
					and _draws == 1
					and (
						result["rewards"]["loot"][0]["item"]["templateId"]
						== CHOICES[index][1 if last else 0][0]
					)
					and arrivals == GROUPS[index]
					and result["locationEvent"]["focus"] == focus
					and (
						result["locationEvent"]["sequence"]
						== ("chest_ambush" if index == 1 else "")
					)
				),
				"Chest%d: one low/high draw, its own group, sampled leader focus" % index
			):
				return
			for other: int in range(4):
				for identity: int in GROUPS[other]:
					if not _expect(
						battle.unit(identity)["visible"] == (other == index),
						"Opening one actual chest leaves the other twelve hidden enemies untouched"
					):
						return
			var map: Dictionary = battle.map_state()["map"]
			if not _expect(
				(
					battle.event_completed("location:" + location["id"])
					and map["tiles"][CELLS[index].y][CELLS[index].x] == 88
					and map["terrain"][CELLS[index].y][CELLS[index].x] == 1
					and content["map"]["tiles"][CELLS[index].y][CELLS[index].x] == 79
				),
				"Actual chest projects native88/terrain1 in its own battle without mutating Content"
			):
				return
			if index == 1 and not last:
				var store := Store.new(content, _owned.path_join("chest1.json"))
				if not _expect(
					store.write(battle)["ok"], "Write actual chest1 reward and591/592 group state"
				):
					return
				var record: Dictionary = JSON.parse_string(
					FileAccess.get_file_as_string(store.path)
				)
				_draws = 0
				var decoded: Dictionary = store.decode(record, _roll)
				var read: Dictionary = store.read()
				if not _expect(
					(
						decoded["ok"]
						and read["ok"]
						and _draws == 0
						and decoded["battle"].snapshot() == battle.snapshot()
						and read["battle"].snapshot() == battle.snapshot()
						and not read["battle"].open_chest(0)["ok"]
					),
					"Actual chest cold JSON retains reward/ambushers/consumption and cannot reopen"
				):
					return
	_cleanup()
	print(
		"PASS actual m12 four chest tables,low/high rewards,four distinct groups,unique591/592,cold state"
	)
	quit(0)


func _roll(limit: int) -> int:
	_draws += 1
	return limit - 1 if _last else 0
