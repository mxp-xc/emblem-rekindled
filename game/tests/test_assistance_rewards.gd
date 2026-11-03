extends SceneTree


func _initialize() -> void:
	var content: Dictionary = load("res://app/chapter_content.gd").new().load_chapter(
		"res://content/chapter_1/chapter.json"
	)
	for spawn: Dictionary in content["spawns"]:
		if spawn["id"] == 0:
			spawn["position"] = [8, 21]
		elif spawn["id"] == 59:
			spawn["position"] = [9, 21]
	for options: Array in [[false, false], [true, false], [false, true], [true, true]]:
		var sharing: bool = options[0]
		var full_growth: bool = options[1]
		var battle: RefCounted = load("res://gameplay/battle_state.gd").new(
			content, func(_limit: int) -> int: return 0
		)
		battle.share_experience = sharing
		battle.full_growth = full_growth
		var state: Dictionary = battle.snapshot()
		var before: Dictionary = {}
		for actor: Dictionary in state["units"]:
			if actor["faction"] == 0:
				actor["experience"] = 99
			if actor["id"] == 2:
				actor["level"] = 10
			if actor["id"] == 9:
				actor["level"] = 20
			if actor["id"] == 1:
				actor["hp"] = 0
				actor["visible"] = false
				actor["flags"] |= 65
			if actor["id"] == 0:
				actor["attributes"]["luck"] = int(content["rules"]["statCaps"]["luck"])
			before[int(actor["id"])] = actor.duplicate(true)
		if not battle.restore_snapshot(state)["ok"]:
			fail("Controlled reward fixture must restore")
			return
		var result: Dictionary = battle.attack_unit(0, 59)
		if not result["ok"] or result["rewards"]["experience"].is_empty():
			fail("Actual combat command must earn experience")
			return
		var experience: Dictionary = result["rewards"]["experience"]
		var combat: RefCounted = load("res://gameplay/combat_rules.gd").new(
			content["rules"], content["map"]["terrain"]
		)
		var hit: bool = result["strikes"].any(
			func(strike: Dictionary) -> bool:
				return strike["hit"] and before[int(strike["attacker"])]["faction"] != 2
		)
		var killed: bool = battle.unit(59)["hp"] <= 0
		var expected_recipients: Array[int] = [0]
		for previous: Dictionary in before.values():
			var id: int = previous["id"]
			var current: Dictionary = battle.unit(id)
			var eligible: bool = (
				sharing
				and previous["faction"] == 0
				and previous["formal"]
				and previous["visible"]
				and previous["hp"] > 0
				and previous["level"] < 20
				and previous["classGroup"] not in [7, 8, 9]
			)
			if id == 0 or eligible:
				if id != 0:
					expected_recipients.append(id)
				var amount: int = combat.experience_gain(
					previous, before[59], killed, hit, false, before[0]
				)
				if (
					current["experience"] != (99 + amount) % 100
					or current["level"] != previous["level"] + 1
				):
					fail("Each eligible blue unit must receive the calculated XP exactly once")
					return
				var rates: Dictionary = content["rules"]["growthRates"][int(
					previous["growthTemplateId"]
				)]
				for stat: String in battle.STAT_ORDER:
					var old_value: int = (
						previous[stat]
						if stat in ["maxHp", "move"]
						else previous["attributes"][stat]
					)
					var value: int = (
						current[stat] if stat in ["maxHp", "move"] else current["attributes"][stat]
					)
					var increment: int = 1 if full_growth or int(rates[stat]) > 0 else 0
					if (
						value
						!= mini(old_value + increment, int(content["rules"]["statCaps"][stat]))
					):
						fail(
							(
								"Full growth must raise every attribute within its original cap: "
								+ stat
							)
						)
						return
			elif (
				current["experience"] != previous["experience"]
				or current["level"] != previous["level"]
			):
				fail("Disabled sharing, green/enemy units and maximum-level units must retain XP")
				return
		var queue: Array = load("res://features/battle/reward_timeline.gd").sequence(
			result, battle.snapshot()["units"], content["interface"], false
		)
		var displayed: Array[int] = []
		var tutorials: int = 0
		for step: Dictionary in queue:
			if step["kind"] == "summary":
				for row: Dictionary in step["rows"]:
					displayed.append(int(row["unit"]))
			elif step["kind"] == "tutorial":
				tutorials += 1
		if displayed != expected_recipients or tutorials != 1:
			fail("Shared XP and growth must be presented once per recipient with only one tutorial")
			return
		var settled: Dictionary = battle.snapshot()
		if battle.attack_unit(0, 59)["ok"] or battle.snapshot() != settled:
			fail("Repeated combat must not distribute a second shared reward")
			return
	print(
		(
			"PASS assistance rewards: combat, individualized XP, faction/level bounds, "
			+ "growth and presentation"
		)
	)
	quit(0)


func fail(message: String) -> void:
	push_error(message)
	quit(1)
