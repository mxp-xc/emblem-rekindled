extends RefCounted


# Execute actual phase commands while replacing automatic actions with waits.
static func advance(battle: RefCounted) -> Dictionary:
	var events: Array = []
	for phase: int in range(3):
		while battle.automatic_actor() >= 0:
			var waited: Dictionary = battle.wait_unit(battle.automatic_actor())
			if not waited["ok"]:
				return waited
		var result: Dictionary = battle.end_phase()
		if not result["ok"]:
			return result
		events.append_array(result["events"])
		if battle.phase == 0:
			return {"ok": true, "events": events}
	return {"ok": false, "error": "PHASE_DID_NOT_RETURN"}
