extends RefCounted

const CastRing = preload("res://features/battle/native_cast_ring.gd")
const CriticalParticles = preload("res://features/battle/native_critical_particles.gd")
const SIN_30: Array[int] = [0, 514, 889, 1024, 882, 501, 0, -526, -896, -1024, -874, -488]

# Original physical and magic effect programs.
var layers: Array[Dictionary] = []
var _sprites: Array[Dictionary] = []
var _effects: Dictionary
var _attacker: Dictionary
var _defender: Dictionary
var _hit: bool
var _next_id: int = 0
var _wind_spawned: bool = false
var _projectile: Dictionary
var _distance: int = 0
var _magic: bool = false
var _cast_spawned: bool = false
var _orbit_center: Vector2i
var _orbit_radius: int = 0
var _critical: bool = false
var _random: RefCounted
var _critical_intro_spawned: bool = false
var _critical_light_sprite: Dictionary = {}
var _wind_sprites: Array[Dictionary] = []


static func supports(action: Dictionary, outcome: String) -> bool:
	return (
		(
			(
				int(action.get("effectKind", -1)) in [0, 1]
				and (
					int(action.get("R", -1)) in [0, 2, 4, 5, 6, 8]
					or (int(action.get("R", -1)) == 7 and not action.get("thrown", false))
				)
			)
			or int(action.get("effectKind", -1)) in [3, 4, 5, 6, 7, 8, 11, 12]
		)
		and (
			outcome in ["hit", "miss"]
			or (
				outcome == "critical"
				and (
					int(action.get("effectKind", -1)) in [3, 4, 5, 6, 7, 8, 11, 12]
					or (
						int(action.get("effectKind", -1)) in [0, 1]
						and (
							(action.get("thrown", false) and int(action.get("R", -1)) in [0, 2, 4])
							or (
								not action.get("thrown", false)
								and int(action.get("R", -1)) in [0, 2, 4, 5, 6, 7, 8]
							)
						)
					)
				)
			)
		)
	)


func _init(
	action: Dictionary,
	defender: Dictionary,
	outcome: String,
	effects: Dictionary,
	projectile: Dictionary = {},
	random: RefCounted = null
) -> void:
	assert(supports(action, outcome))
	_effects = effects
	_attacker = action
	_magic = int(action["effectKind"]) in [3, 4, 5, 6, 7, 8, 11, 12]
	_defender = defender
	_hit = outcome != "miss"
	_critical = outcome == "critical"
	_random = random
	assert(not _critical or _random != null)
	assert(int(action["effectKind"]) not in [5, 6, 11] or _random != null)
	_projectile = projectile
	assert(not action["thrown"] or not projectile.is_empty())
	var from_edge: int = int(action["o"]) + int(action["frames"][3][0])
	var to_edge: int = int(defender["o"]) + int(defender["at"]) - int(defender["frames"][0][0]) + 5
	if int(action["I"]) == 1:
		from_edge = int(action["o"]) + int(action["at"]) - int(action["frames"][3][0])
		to_edge = int(defender["o"]) + int(defender["frames"][0][0]) - 5
	_distance = to_edge - from_edge


func has_live_effects() -> bool:
	return not _sprites.is_empty()


func advance(clock: RefCounted) -> void:
	for index: int in range(_sprites.size() - 1, -1, -1):
		var sprite: Dictionary = _sprites[index]
		if sprite.has("beam"):
			sprite["beam"]["elapsed"] += 50
			if int(sprite["beam"]["elapsed"]) >= int(sprite["beam"]["duration"]):
				_sprites.remove_at(index)
			continue
		if sprite.has("particles"):
			sprite["particles"].advance()
			if not sprite["particles"].alive:
				_sprites.remove_at(index)
			continue
		sprite["position"] += sprite["velocity"]
		sprite["elapsed"] += 50
		if sprite["elapsed"] >= sprite["period"]:
			sprite["elapsed"] = 0
			sprite["frame"] += 1
			if sprite["frame"] >= sprite["definition"]["frames"].size():
				sprite["frame"] = 0
				if sprite["cycles"] > 0:
					sprite["cycles"] -= 1
				if sprite["cycles"] == 0:
					_sprites.remove_at(index)
	if not _magic and clock.source_state == 2 and not _wind_spawned and int(_attacker["R"]) == 8:
		_wind_spawned = true
		var wind_cast: Dictionary = _effects["wind_cast"]
		_spawn(
			wind_cast,
			Vector2i(
				int(_attacker["q"]) - (int(wind_cast["virtualWidth"]) >> 1),
				int(_attacker["p"]) - int(wind_cast["virtualHeight"])
			),
			true,
			3
		)
	if _magic and clock.source_state == 2 and not _cast_spawned:
		_cast_spawned = true
		if int(_attacker["R"]) == 10:
			var q: int = int(_attacker["q"])
			var r: int = int(_attacker["r"])
			for center: Vector2i in [
				Vector2i(q - 8, r - 50), Vector2i(q - 28, r - 40), Vector2i(q + 12, r - 40)
			]:
				_spawn({"frames": CastRing.frames()}, center, true, 1)
		elif not _critical:
			_spawn(
				{"frames": CastRing.frames()},
				Vector2i(
					int(_attacker["q"]), int(_attacker["p"]) - int(_attacker["frames"][2][1]) - 12
				),
				true,
				1
			)
		var cast: Dictionary = _effects["wind_cast"]
		if int(_attacker["R"]) == 10 or int(_attacker["effectKind"]) == 6:
			_spawn(
				cast,
				Vector2i(
					int(_attacker["q"]) - (int(cast["virtualWidth"]) >> 1),
					int(_attacker["p"]) - int(cast["virtualHeight"])
				),
				true,
				3
			)
		if int(_attacker["effectKind"]) == 5:
			_spawn(
				cast,
				Vector2i(
					int(_defender["q"]) - (int(cast["virtualWidth"]) >> 1),
					int(_attacker["p"]) - int(cast["virtualHeight"])
				),
				true,
				3
			)
	var intro_time: bool = (
		clock.source_state == 7
		or (clock.source_state == 2 and (_magic or int(_attacker["R"]) != 4 or _attacker["thrown"]))
		or (
			clock.source_state == 3
			and clock.source_step == 0
			and int(_attacker["R"]) == 4
			and not _magic
			and not _attacker["thrown"]
		)
	)
	if _critical and intro_time and not _critical_intro_spawned:
		_critical_intro_spawned = true
		if int(_attacker["R"]) != 10:
			var intro: Dictionary = _effects["bomb"]
			_spawn(
				intro,
				Vector2i(
					int(_attacker["q"]) - (int(intro["virtualWidth"]) >> 1),
					(
						int(_attacker["p"])
						- int(_attacker["frames"][1][1])
						- int(intro["virtualHeight"])
					)
				),
				true,
				1
			)
		if clock.source_state == 7 and int(_attacker["R"]) != 7:
			var charge: Dictionary = _effects["power"]
			_spawn(
				charge,
				Vector2i(
					int(_attacker["q"]) - (int(charge["virtualWidth"]) >> 1),
					int(_attacker["p"]) - int(charge["virtualHeight"])
				),
				true,
				3
			)
	if (
		_critical
		and not _magic
		and not _attacker["thrown"]
		and int(_attacker["R"]) in [2, 6]
		and clock.source_state == 8
		and clock.source_step == 0
	):
		var charge_smoke: Dictionary = _effects["smoke"]
		_spawn(
			charge_smoke,
			Vector2i(
				int(_attacker["q"]) - (int(charge_smoke["virtualWidth"]) >> 1),
				int(_attacker["p"]) - int(charge_smoke["virtualHeight"])
			),
			false,
			1,
			200,
			Vector2i(0, -1)
		)
	if _critical and not _magic and not _attacker["thrown"] and clock.critical_preimpact:
		if int(_attacker["R"]) == 4:
			var smoke: Dictionary = _effects["smoke"]
			_spawn(
				smoke,
				Vector2i(
					int(_attacker["q"]) - (int(smoke["virtualWidth"]) >> 1),
					int(_attacker["p"]) - int(smoke["virtualHeight"])
				),
				false,
				1,
				200,
				Vector2i(0, -1)
			)
		var bomb: Dictionary = _effects["bomb"]
		_spawn(
			bomb,
			Vector2i(
				int(_defender["q"]) - (int(bomb["virtualWidth"]) >> 1),
				int(_defender["r"]) - (int(bomb["virtualHeight"]) >> 1)
			),
			false,
			1
		)
		if int(_attacker["R"]) == 0:
			var power: Dictionary = _effects["power"]
			_spawn(
				power,
				Vector2i(
					int(_defender["q"]) - (int(power["virtualWidth"]) >> 1),
					int(_attacker["p"]) - int(power["virtualHeight"])
				),
				true,
				3
			)
	if (
		_critical
		and not _magic
		and not _attacker["thrown"]
		and int(_attacker["R"]) == 4
		and clock.source_state == 3
		and clock.source_step == 16
	):
		var power: Dictionary = _effects["power"]
		_spawn(
			power,
			Vector2i(
				int(_defender["q"]) - (int(power["virtualWidth"]) >> 1),
				int(_attacker["p"]) - int(power["virtualHeight"])
			),
			true,
			3
		)
	if (
		_critical
		and not _magic
		and not _attacker["thrown"]
		and int(_attacker["R"]) == 0
		and clock.source_state == 3
		and clock.source_step == 14
	):
		var side: int = int(_attacker["I"])
		var strike: Dictionary = _effects["strike_right" if side == 1 else "strike_left"]
		var strike_x: int = (
			clock.position.x
			+ (10 if side == 1 else int(_attacker["frames"][3][0]) - 10)
			- (int(strike["virtualWidth"]) if side == 1 else 0)
		)
		var strike_y: int = (
			int(_attacker["p"]) - int(_attacker["u"]) - (int(strike["virtualHeight"]) >> 1)
		)
		for index: int in range(3):
			var x: int = strike_x + (0 if index == 0 else (10 if side == 1 else -10))
			var y: int = (
				strike_y
				+ (
					0
					if index == 0
					else (
						-(int(strike["virtualHeight"]) >> 1)
						if index == 1
						else int(strike["virtualHeight"]) >> 1
					)
				)
			)
			_spawn(
				{"frames": [strike]},
				Vector2i(x, y),
				true,
				1,
				150,
				Vector2i(0, 0 if index == 0 else (2 if index == 1 else -2))
			)
	if (
		_critical
		and not _magic
		and not _attacker["thrown"]
		and int(_attacker["R"]) in [5, 8]
		and clock.source_state == 3
		and clock.source_step == 0
	):
		var power: Dictionary = _effects["power"]
		_spawn(
			power,
			Vector2i(
				int(_attacker["q"]) - (int(power["virtualWidth"]) >> 1),
				int(_attacker["p"]) - int(power["virtualHeight"])
			),
			true,
			3
		)
		var side: int = int(_attacker["I"])
		var strike: Dictionary = _effects["strike_right" if side == 1 else "strike_left"]
		var strike_x: int = int(_attacker["q"]) - (int(strike["virtualWidth"]) if side == 1 else 0)
		var strike_y: int = (
			(
				int(_attacker["p"]) - int(_attacker["u"])
				if int(_attacker["R"]) == 5
				else int(_defender["r"])
			)
			- (int(strike["virtualHeight"]) >> 1)
		)
		for index: int in range(3):
			var x: int = strike_x + (0 if index == 0 else (10 if side == 1 else -10))
			var y: int = (
				strike_y
				+ (
					0
					if index == 0
					else (
						-(int(strike["virtualHeight"]) >> 1)
						if index == 1
						else int(strike["virtualHeight"]) >> 1
					)
				)
			)
			_spawn(
				{"frames": [strike]},
				Vector2i(x, y),
				true,
				1,
				300,
				Vector2i(_distance, 0 if index == 0 else (2 if index == 1 else -2))
			)
	if (
		_magic
		and int(_attacker["effectKind"]) in [3, 4, 5, 6, 7, 8]
		and clock.source_state == 3
		and clock.source_step == 1
	):
		var kind: int = int(_attacker["effectKind"])
		var magic: Dictionary = _effects[
			"fire" if kind in [3, 4] else ("wind" if kind in [5, 6] else "light")
		]
		_orbit_center = Vector2i(
			int(_defender["q"]) - (int(magic["virtualWidth"]) >> 1),
			int(_defender["p"]) - int(magic["virtualHeight"])
		)
		if kind in [5, 6]:
			var x: int = (
				_orbit_center.x
				if kind == 5
				else (
					int(_attacker["q"])
					- (int(magic["virtualWidth"]) if int(_attacker["I"]) == 1 else 0)
				)
			)
			for index: int in range(
				(3 if _critical else 2) if kind == 5 else (6 if _critical else 3)
			):
				if index == 3:
					x += (int(magic["virtualWidth"]) >> 1) * (1 if int(_attacker["I"]) == 1 else -1)
				_spawn(
					magic,
					Vector2i(x, _orbit_center.y - (index % 3) * (int(magic["virtualHeight"]) - 1)),
					true,
					-1
				)
				_sprites[-1]["wind_age"] = 0
				_wind_sprites.append(_sprites[-1])
		elif kind in [4, 8]:
			_orbit_center.y -= 5
			_orbit_radius = maxi(20, (int(_defender["frames"][0][0]) >> 1) - 5)
			for index: int in range(3):
				var angle: int = (index * 120 + (210 if kind == 4 and not _critical else 0)) % 360
				_spawn(magic, _orbit_position(angle), true, 3)
				_sprites[-1]["orbit_angle"] = angle
		elif kind == 3 and _critical:
			var spread: int = (int(_defender["frames"][0][0]) >> 1) - 5
			for x: int in [_orbit_center.x, _orbit_center.x + spread, _orbit_center.x - spread]:
				_spawn(
					magic,
					Vector2i(x - _distance, _orbit_center.y),
					true,
					-1,
					100,
					Vector2i(int(float(_distance) / 4.0), 0)
				)
				_sprites[-1]["critical_fire"] = x
		elif kind == 7 and _critical:
			_spawn(
				magic,
				Vector2i(_orbit_center.x - _distance, _orbit_center.y),
				true,
				-1,
				100,
				Vector2i(int(float(_distance) / 4.0), 0)
			)
			_sprites[-1]["critical_light"] = true
			_critical_light_sprite = _sprites[-1]
		else:
			_spawn(magic, _orbit_center, true, 3)
	if _magic and clock.source_state == 3 and clock.source_step > 1:
		var smoke_positions: Array[Vector2i] = []
		if not _wind_sprites.is_empty():
			var kind: int = int(_attacker["effectKind"])
			var delay: int = 1 if kind == 5 else 2
			var spread: int = mini(int(_defender["frames"][0][0]) >> 1, 15)
			var x: int = _orbit_center.x + _random.native_range(-spread, spread)
			for index: int in range(_wind_sprites.size()):
				var wind: Dictionary = _wind_sprites[index]
				if index == 3:
					x = _orbit_center.x + _random.native_range(-spread, spread)
				wind["wind_age"] += 1
				var offset: int = 0 if index in [0, 3] else _random.native_range(-5, 5)
				if int(wind["wind_age"]) > delay:
					if _critical and kind == 6 and int(wind["wind_age"]) > delay + 18:
						continue
					if _critical and kind == 6 and int(wind["wind_age"]) == delay + 18:
						wind["velocity"].x = 8 if index >= 3 else -8
						if index == 0:
							var side: int = int(_attacker["I"])
							var strike: Dictionary = _effects[
								"strike_right" if side == 1 else "strike_left"
							]
							var strike_position := Vector2i(
								int(_defender["q"]) - (int(strike["virtualWidth"]) >> 1),
								(
									int(_defender["p"])
									- int(_effects["wind"]["virtualHeight"])
									- (int(_effects["wind"]["virtualHeight"]) >> 1)
								)
							)
							for velocity: int in [0, 6, -6]:
								_spawn(
									{"frames": [strike]},
									strike_position,
									true,
									2,
									100,
									Vector2i(0, velocity)
								)
					wind["position"].x = x + offset
				else:
					if kind == 6:
						wind["position"].x += int(float(_distance) / 2.0)
						if index == 0:
							smoke_positions.append(
								(
									wind["position"]
									+ Vector2i(
										0,
										(
											int(_effects["wind"]["virtualHeight"])
											- int(_effects["smoke"]["virtualHeight"])
										)
									)
								)
							)
					if int(wind["wind_age"]) == delay:
						wind["cycles"] = 6 if _critical else 3
		if not _critical_light_sprite.is_empty():
			var sprite: Dictionary = _critical_light_sprite
			if clock.source_step == 2:
				sprite["cycles"] = 4
			elif clock.source_step == 5:
				sprite["cycles"] = 2
				sprite["velocity"] = Vector2i.ZERO
			var half_width: int = int(_defender["frames"][0][0]) >> 1
			var x: int = _orbit_center.x + _random.native_range(-half_width, half_width)
			sprite["position"].x = x
			if clock.source_step % 2 == 0:
				smoke_positions.append(
					Vector2i(x, int(_defender["p"]) - int(_effects["smoke"]["virtualHeight"]))
				)
		for sprite: Dictionary in _sprites:
			if sprite.has("critical_fire") and clock.source_step == 5:
				sprite["position"].x = int(sprite["critical_fire"])
				sprite["velocity"] = Vector2i.ZERO
				sprite["cycles"] = 2
			if sprite.has("orbit_angle"):
				if _critical and clock.source_step == 2:
					sprite["cycles"] = 6
				sprite["position"] = _orbit_position(int(sprite["orbit_angle"]))
				if int(_attacker["effectKind"]) == 8 or _critical:
					sprite["orbit_angle"] = (int(sprite["orbit_angle"]) + 30) % 360
					if int(_attacker["effectKind"]) == 8 and clock.source_step % 6 == 0:
						smoke_positions.append(
							(
								sprite["position"]
								+ Vector2i(
									0,
									(
										int(sprite["definition"]["virtualHeight"])
										- int(_effects["smoke"]["virtualHeight"])
									)
								)
							)
						)
		if _critical and int(_attacker["effectKind"]) == 4 and clock.source_step == 22:
			_sprites.append(
				{
					"beam": {"elapsed": 0, "duration": 500},
					"position": Vector2i(int(_defender["q"]), int(_attacker["p"])),
					"foreground": true,
					"instance": -1
				}
			)
		for at: Vector2i in smoke_positions:
			_spawn(
				_effects["smoke"], at, int(_attacker["effectKind"]) == 7, 1, 200, Vector2i(0, -1)
			)
	if _magic and clock.source_state == 3:
		var kind: int = int(_attacker["effectKind"])
		if kind == 11 and clock.source_step <= 10:
			var x: int = int(_defender["q"]) + _random.native_range(-20, 20)
			var y: int = int(_defender["r"]) + _random.native_range(-15, 15)
			_spawn({"frames": CastRing.frames()}, Vector2i(x, y - 12), true, 1, 50)
		elif kind == 12 and clock.source_step in [5, 7, 10]:
			var distance: int = int(_defender["q"]) - int(_attacker["q"])
			var x: int = int(_attacker["q"]) + int(float(distance) / 2.0)
			if clock.source_step == 7:
				x += int(float(distance) / 4.0)
			elif clock.source_step == 10:
				x += int(float(distance) / 4.0) * 2
			var power: Dictionary = _effects["power"]
			_spawn(
				power,
				Vector2i(
					x - (int(power["virtualWidth"]) >> 1),
					int(_attacker["p"]) - int(power["virtualHeight"])
				),
				true,
				3
			)
			_sprites.append(
				{
					"beam": {"elapsed": 0, "duration": 200},
					"position": Vector2i(x, int(_attacker["p"])),
					"foreground": true,
					"instance": -1
				}
			)
		elif kind == 12 and _hit and clock.source_step == 14:
			var bomb: Dictionary = _effects["bomb"]
			_spawn(
				bomb,
				Vector2i(
					int(_defender["q"]) - (int(bomb["virtualWidth"]) >> 1),
					int(_defender["r"]) - (int(bomb["virtualHeight"]) >> 1)
				),
				true,
				1
			)
	if _magic and _hit and clock.settled and int(_attacker["effectKind"]) not in [11, 12]:
		var kind: int = int(_attacker["effectKind"])
		if kind in [3, 4, 5, 6]:
			var magic_bomb: Dictionary = _effects["bomb"]
			if kind in [3, 4]:
				_spawn(
					magic_bomb,
					Vector2i(
						int(_defender["q"]) - (int(magic_bomb["virtualWidth"]) >> 1),
						int(_defender["r"]) - (int(magic_bomb["virtualHeight"]) >> 1)
					),
					true,
					1
				)
		var magic_smoke: Dictionary = _effects["smoke"]
		_spawn(
			magic_smoke,
			Vector2i(
				(
					int(_defender["q"])
					- ((int(magic_smoke["virtualWidth"]) >> 1) if kind in [5, 6] else 0)
				),
				int(_defender["p"]) - int(magic_smoke["virtualHeight"])
			),
			kind not in [5, 6],
			1,
			200,
			Vector2i(0, -1)
		)
		if kind in [5, 6]:
			var wind_bomb: Dictionary = _effects["bomb"]
			_spawn(
				wind_bomb,
				Vector2i(
					int(_defender["q"]) - (int(wind_bomb["virtualWidth"]) >> 1),
					int(_defender["r"]) - (int(wind_bomb["virtualHeight"]) >> 1)
				),
				false,
				1
			)
	if (
		not _magic
		and not _critical
		and clock.source_state == 3
		and clock.source_step == 0
		and int(_attacker["R"]) == 0
		and not _attacker["thrown"]
	):
		var smoke: Dictionary = _effects["smoke"]
		_spawn(
			smoke,
			Vector2i(
				int(_attacker["q"]) - (int(smoke["virtualWidth"]) >> 1),
				int(_attacker["p"]) - int(smoke["virtualHeight"])
			),
			false,
			1,
			200,
			Vector2i(0, -1)
		)
	if _attacker["thrown"] and clock.source_state == 3:
		if clock.source_step == 0:
			var projectile_x: int = (
				int(_defender["q"])
				+ (38 - int(_projectile["virtualWidth"]) if int(_attacker["I"]) == 1 else -38)
			)
			var projectile_y: int = int(_defender["r"]) - 35
			if _attacker["lance"]:
				projectile_x = (
					int(_defender["q"])
					+ (30 - int(_projectile["virtualWidth"]) if int(_attacker["I"]) == 1 else -30)
				)
				projectile_y = int(_defender["r"]) - (int(_projectile["virtualHeight"]) >> 1)
			_spawn(
				{"frames": [_projectile]},
				Vector2i(projectile_x, projectile_y),
				false,
				6 if _attacker["lance"] else 1,
				50
			)
		elif clock.source_step == 5 and not _attacker["lance"]:
			_spawn(
				{"frames": [_projectile]},
				Vector2i(
					int(_defender["q"]) - (int(_projectile["virtualWidth"]) >> 1),
					int(_defender["r"]) - 12
				),
				false,
				1,
				50
			)
	if (
		not _magic
		and clock.source_state == 3
		and (
			(clock.source_step == 0 and int(_attacker["R"]) == 5 and not _critical)
			or (clock.source_step == 1 and _attacker["thrown"] and _hit)
		)
	):
		var side: int = int(_attacker["I"])
		var strike: Dictionary = _effects["strike_right" if side == 1 else "strike_left"]
		var strike_x: int = int(_attacker["q"]) + (_distance if _attacker["thrown"] else 0)
		var strike_y: int = (
			(
				int(_defender["p"]) - int(_attacker["u"])
				if int(_attacker["u"]) != 0
				else int(_defender["r"])
			)
			if _attacker["thrown"]
			else int(_attacker["p"]) - int(_attacker["u"])
		)
		_spawn(
			{"frames": [strike]},
			Vector2i(
				strike_x - (int(strike["virtualWidth"]) if side == 1 else 0),
				strike_y - (int(strike["virtualHeight"]) >> 1)
			),
			true,
			1,
			100 if _attacker["thrown"] else 300,
			Vector2i(0 if _attacker["thrown"] else _distance, 0)
		)
	if (
		not _magic
		and _hit
		and int(_attacker["R"]) == 7
		and clock.source_state == 3
		and clock.source_step == 0
	):
		var power: Dictionary = _effects["power"]
		_spawn(
			power,
			Vector2i(
				int(_defender["q"]) - (int(power["virtualWidth"]) >> 1),
				int(_attacker["p"]) - int(power["virtualHeight"])
			),
			true,
			3
		)
	if not _magic and _hit and clock.impact_started:
		var bomb: Dictionary = _effects["bomb"]
		var target_y: int = (
			int(_defender["p"]) - int(_attacker["u"])
			if int(_attacker["u"]) != 0
			else int(_defender["r"])
		)
		_spawn(
			bomb,
			Vector2i(
				int(_defender["q"]) - (int(bomb["virtualWidth"]) >> 1),
				target_y - (int(bomb["virtualHeight"]) >> 1)
			),
			false,
			1
		)
		if int(_attacker["R"]) in [2, 6] and not _attacker["thrown"]:
			var power: Dictionary = _effects["power"]
			_spawn(
				power,
				Vector2i(
					int(_defender["q"]) - (int(power["virtualWidth"]) >> 1),
					int(_defender["p"]) - int(power["virtualHeight"])
				),
				true,
				3
			)
		if _critical:
			_sprites.append(
				{
					"particles": CriticalParticles.new(_random),
					"position": Vector2i(int(_defender["q"]), int(_defender["r"])),
					"foreground": true,
					"instance": -1
				}
			)
	layers.clear()
	for foreground: bool in [false, true]:
		for sprite: Dictionary in _sprites:
			if sprite["foreground"] != foreground:
				continue
			if sprite.has("beam"):
				if sprite["instance"] < 0:
					sprite["instance"] = _next_id
					_next_id += 1
				layers.append(
					{
						"beam": sprite["beam"],
						"position": sprite["position"],
						"instance": sprite["instance"],
						"foreground": foreground
					}
				)
				continue
			if sprite.has("particles"):
				if sprite["instance"] < 0:
					sprite["instance"] = _next_id
					_next_id += 1
				layers.append(
					{
						"particles": sprite["particles"],
						"position": sprite["position"],
						"instance": sprite["instance"],
						"foreground": foreground
					}
				)
				continue
			var frame: Dictionary = sprite["definition"]["frames"][sprite["frame"]]
			var draw_at: Vector2i = (
				sprite["position"] + Vector2i(int(frame["offsetX"]), int(frame["offsetY"]))
			)
			if (
				frame.get("empty", false)
				or draw_at.x >= 240
				or draw_at.y >= 320
				or draw_at.x + int(frame["width"]) <= 0
				or draw_at.y + int(frame["height"]) <= 0
			):
				continue
			if sprite["instance"] < 0:
				sprite["instance"] = _next_id
				_next_id += 1
			layers.append(
				{
					"texture": frame["texture"],
					"position": draw_at,
					"instance": sprite["instance"],
					"foreground": foreground
				}
			)


func _spawn(
	definition: Dictionary,
	position: Vector2i,
	foreground: bool,
	cycles: int,
	period: int = 100,
	velocity: Vector2i = Vector2i.ZERO
) -> void:
	_sprites.append(
		{
			"definition": definition,
			"position": position,
			"velocity": velocity,
			"foreground": foreground,
			"instance": -1,
			"frame": 0,
			"elapsed": 0,
			"period": period,
			"cycles": cycles
		}
	)


func _orbit_position(angle: int) -> Vector2i:
	var index: int = angle / 30
	var x: int = (_orbit_radius * SIN_30[(index + 3) % 12]) >> 10
	var y: int = int(float(_orbit_radius * SIN_30[index]) / 3.0) >> 10
	return _orbit_center + Vector2i(x, y)
