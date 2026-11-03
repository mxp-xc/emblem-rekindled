extends RefCounted

const LOGIC_UNITS: int = 50
const GROWTH_ORDER: Array[String] = [
	"maxHp", "strength", "skill", "speed", "magic", "defense", "luck", "move"
]
var tick: int = 0
var finished: bool = false
var _remaining_units: int


static func sequence(
	result: Dictionary,
	actors: Array,
	interface: Dictionary,
	tutorial_seen: bool,
	player_phase: bool = true
) -> Array[Dictionary]:
	var queue: Array[Dictionary] = []
	var expiry: Array[Dictionary] = []
	if result.get("kind") == "repair":
		queue.append(
			{
				"kind": "message",
				"text":
				interface["items"][str(int(result["repairedItem"]["templateId"]))]["name"]["text"],
				"secondLine": "修复",
				"durationUnits": 1200,
				"unit": result["target"]
			}
		)
	elif result.get("effect") == "gold":
		queue.append(
			{
				"kind": "message",
				"text": "获得",
				"secondLine": "%d金" % int(result["creditedGold"]),
				"durationUnits": 1200,
				"unit": result["actor"]
			}
		)
	elif result.get("effect") == "attribute":
		var labels: Dictionary = {
			"strength": "力量",
			"skill": "技巧",
			"speed": "速度",
			"defense": "防御",
			"magic": "魔力",
			"luck": "幸运",
			"maxHp": "最大HP",
			"move": "移动"
		}
		queue.append(
			{
				"kind": "message",
				"text": interface["items"][str(int(result["templateId"]))]["name"]["text"] + "使用",
				"secondLine":
				"%s %d→%d" % [labels[result["stat"]], result["statBefore"], result["statAfter"]],
				"durationUnits": 1200,
				"unit": result["actor"],
				"noticeIcon": "item_10"
			}
		)
	for revival: Dictionary in result.get("revivals", []):
		var consumed: Dictionary = revival.get("expiredItem", {})
		if not consumed.is_empty():
			expiry.append(
				{
					"kind": "message",
					"text": interface["items"]["80"]["name"]["text"] + "消失",
					"durationUnits": 1200,
					"unit": revival["unit"],
					"noticeIcon": interface["items"]["80"]["icon"]
				}
			)
	var expired: Dictionary = result.get("expiredItem", {})
	if not expired.is_empty():
		expiry.append(
			{
				"kind": "message",
				"text": interface["items"][str(int(expired["templateId"]))]["name"]["text"] + "消失",
				"durationUnits": 1200,
				"unit": result["actor"],
				"noticeIcon": interface["items"][str(int(expired["templateId"]))]["icon"]
			}
		)
	var units: Dictionary = {}
	for actor: Dictionary in actors:
		units[int(actor["id"])] = actor
	for actor: Dictionary in result.get("participants", []):
		if actor["faction"] != 0:
			continue
		var inventory: Array = actor["inventory"].duplicate()
		inventory.reverse()
		for held: Dictionary in inventory:
			for broken: Dictionary in result.get("brokenItems", []):
				if (
					broken["unit"] == actor["id"]
					and broken["templateId"] == held["templateId"]
					and broken.get("item", held["id"]) == held["id"]
					and int(held["templateId"]) < 60
				):
					queue.append(
						{
							"kind": "message",
							"text":
							interface["items"][str(int(held["templateId"]))]["name"]["text"] + "消失",
							"durationUnits": 1200,
							"unit": actor["id"],
							"noticeIcon": interface["items"][str(int(held["templateId"]))]["icon"]
						}
					)
	var location: Dictionary = result.get("location", result)
	if (
		(result.get("kind") in ["open_chest", "visit"] or result.has("location"))
		and not location.get("claimed", false)
		and location.get("reason") == "WAREHOUSE_FULL"
	):
		queue.append(
			{"kind": "message", "text": "仓库已满", "durationUnits": 1200, "unit": location["actor"]}
		)
	if result.get("kind") in ["visit", "open_chest"] and result.get("claimed", false):
		var reward: Dictionary = result.get("reward", {})
		if reward.get("kind") == "empty":
			queue.append(
				{"kind": "message", "text": "(空)", "durationUnits": 1200, "unit": result["actor"]}
			)
		elif reward.get("kind") == "gold":
			queue.append(
				{
					"kind": "message",
					"text": "获得",
					"secondLine": "%d金" % int(reward["amount"]),
					"durationUnits": 1200,
					"unit": result["actor"]
				}
			)
	var rewards: Dictionary = location.get("rewards", {})
	for loot: Dictionary in rewards.get("loot", []):
		queue.append(
			{
				"kind": "message",
				"text": "获得",
				"templateId": loot["item"]["templateId"],
				"durationUnits": 1200,
				"unit": loot["unit"]
			}
		)
		if loot["destination"] == "warehouse":
			queue[-1]["warehouseNotice"] = "人物携带已满存入仓库"
	var primary_experience: Dictionary = rewards.get("experience", {})
	var awards: Array = []
	if not primary_experience.is_empty():
		awards = [primary_experience] + primary_experience.get("shared", [])
	elif result.has("promotion"):
		var actor: Dictionary = units[int(result["promotion"]["unit"])]
		awards = [
			{
				"unit": actor["id"],
				"level": actor["level"],
				"before": actor["experience"],
				"after": actor["experience"],
				"amount": 0,
				"growth": {},
				"promotion": result["promotion"]
			}
		]
	var rows: Array[Dictionary] = []
	for experience: Dictionary in awards:
		var unit: Dictionary = units[int(experience["unit"])]
		var level: int = int(experience.get("level", unit["level"]))
		var growth: Dictionary = {
			"unit": unit["id"],
			"name": unit["name"],
			"levelBefore": level - int(not experience["growth"].is_empty()),
			"levelAfter": level,
			"experienceBefore": experience["before"],
			"experienceAfter":
			experience.get("after", (int(experience["before"]) + int(experience["amount"])) % 100),
			"amount": experience["amount"],
			"before": [],
			"after": [],
			"increments": []
		}
		var promotion: Dictionary = experience.get("promotion", {})
		if not promotion.is_empty():
			growth["promotion"] = promotion.duplicate(true)
			growth["classBeforeName"] = interface["jobs"][str(int(promotion["classBefore"]))]["name"]["text"]
			growth["classAfterName"] = interface["jobs"][str(int(promotion["classAfter"]))]["name"]["text"]
			var equipment: Array[String] = []
			var equipment_icons: Array[Dictionary] = []
			var mask: int = int(promotion["equipMaskAfter"]) & ~int(promotion["equipMaskBefore"])
			var names: Array[String] = ["剑", "枪", "斧", "弓", "魔法", "杖"]
			for bit: int in range(6):
				if mask & (1 << bit):
					equipment.append(names[bit])
					var icon_id: String = interface["equipMaskIcons"][str(1 << bit)]
					var texture: String = interface["textures"][icon_id]["texture"]
					equipment_icons.append(
						{
							"id": icon_id,
							"texture": "res://" + texture.trim_prefix("res://"),
							"name": names[bit]
						}
					)
			growth["newEquipment"] = "、".join(equipment)
			growth["newEquipmentIcons"] = equipment_icons
		for stat: String in GROWTH_ORDER:
			var after: int = int(
				unit[stat] if stat in ["maxHp", "move"] else unit["attributes"][stat]
			)
			var increment: int = (
				int(experience["growth"].get(stat, 0))
				+ int(promotion.get("increments", {}).get(stat, 0))
			)
			growth["before"].append(after - increment)
			growth["after"].append(after)
			growth["increments"].append(increment)
		rows.append(growth)
	if not rows.is_empty():
		queue.append({"kind": "summary", "unit": rows[0]["unit"], "rows": rows})
	if not primary_experience.is_empty() and not tutorial_seen and player_phase:
		queue.append({"kind": "tutorial", "unit": primary_experience["unit"]})
	return queue + expiry


func _init(step: Dictionary) -> void:
	_remaining_units = int(step["durationUnits"])


func advance() -> void:
	if finished:
		return
	tick += 1
	if _remaining_units > 0:
		_remaining_units -= LOGIC_UNITS
	else:
		finished = true
