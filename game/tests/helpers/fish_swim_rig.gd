extends RefCounted
## Builds a FishSwimSim with fish for the #35 steering tests (plan section 5, "Shared rig"): the
## large (100 x 40 cm) or small (40 x 25 cm) tank from the catalog, a flat sand bed or a custom
## surface Callable, uids from a RandomNumberGenerator seeded 12345 (never sequential), the steering
## random source seeded 777 and the shipped tuning. Everything is late-bound (FishSwimApi) so a
## missing class gives a readable failure and no parse error. Test helper only.
##
## The expected caps are computed here from the catalog species and the BA constants (k = 3,
## acceleration 0.3 s, yaw acceleration 0.25 s), never read from FishSwimParams, so the tests do
## not depend on the names of the developer's private fields.

const Api := preload("res://tests/helpers/fish_swim_api.gd")
const FishApi := preload("res://tests/helpers/fish_api.gd")
const ViewRig := preload("res://tests/helpers/fish_view_rig.gd")

const STEP: float = 1.0 / 60.0
const UID_SEED: int = 12345
const SIM_SEED: int = 777
const LARGE: StringName = &"tank_large_1"
const SMALL: StringName = &"tank_small_1"
const SAND: StringName = &"sand_fine"
const BAND_TOLERANCE_M: float = 0.01
## The pinned test fish: a copy of the angelfish at 18 cm (the real angelfish is not pinned in any
## shipped tank; the column of the small tank, 22 cm, cannot hold an angelfish above 14.8 cm).
const PINNED_ID: StringName = &"pinned_angelfish"
const PINNED_ADULT_CM: float = 18.0
const EPS: float = 1e-9
const MAX_SAMPLES: int = 12
## The recovery speed cap in top speeds, the speed factor range and the Q5 caps (BA decisions).
const RECOVERY_FACTOR: float = 6.0
const SPEED_FACTOR_MAX: float = 1.2
const ACCEL_TIME_S: float = 0.3
const YAW_ACCEL_TIME_S: float = 0.25
const FLIP_WINDOW_S: float = 1.0
const FLIP_MAX: int = 2
const FLIP_DEADBAND: float = 0.05
const PITCH_MARGIN_DEG: float = 0.5
const HEAD_FIRST_MAX_DEG: float = 30.0
const HEAD_FIRST_MIN_SPEED: float = 0.10


## One fish of a setup with the values the checks need.
class Member:
	extends RefCounted
	var uid: String = ""
	var species_id: StringName = &""
	var species: Resource = null
	var extents: Object = null
	var personality: Object = null
	var params: Object = null
	var length_m: float = 0.0
	var top: float = 0.0
	var turn_cap: float = 0.0
	var pitch_cap: float = 0.0
	var zone: int = 0
	var speed_factor: float = 1.0


## A simulation with its fish and the world it was built for.
class Setup:
	extends RefCounted
	var sim: Object = null
	var world: Object = null
	var interior: Vector3 = Vector3.ZERO
	var water_line: float = 0.0
	var surface: Callable = Callable()
	var allowance: float = 0.0
	var members: Array[Member] = []
	var index_of: Dictionary[String, int] = {}

	func uids() -> Array[String]:
		var result: Array[String] = []
		for member: Member in members:
			result.append(member.uid)
		return result


## The values of every fish of a setup after one step, read once and kept in packed arrays.
class Observer:
	extends RefCounted
	var count: int = 0
	var position: PackedVector3Array = PackedVector3Array()
	var velocity: PackedVector3Array = PackedVector3Array()
	var speed: PackedFloat64Array = PackedFloat64Array()
	var yaw: PackedFloat64Array = PackedFloat64Array()
	var yaw_rate: PackedFloat64Array = PackedFloat64Array()
	var pitch: PackedFloat64Array = PackedFloat64Array()
	var travel_pitch: PackedFloat64Array = PackedFloat64Array()
	var shader_speed: PackedFloat64Array = PackedFloat64Array()
	var mode: PackedInt32Array = PackedInt32Array()
	var darts: PackedInt32Array = PackedInt32Array()
	var recovering: PackedByteArray = PackedByteArray()
	var pinned: PackedByteArray = PackedByteArray()
	var intends: PackedByteArray = PackedByteArray()
	var _setup: Setup = null

	func _init(setup: Setup) -> void:
		_setup = setup
		count = setup.members.size()
		position.resize(count)
		velocity.resize(count)
		speed.resize(count)
		yaw.resize(count)
		yaw_rate.resize(count)
		pitch.resize(count)
		travel_pitch.resize(count)
		shader_speed.resize(count)
		mode.resize(count)
		darts.resize(count)
		recovering.resize(count)
		pinned.resize(count)
		intends.resize(count)

	func read() -> void:
		for index: int in count:
			var state: Object = _setup.sim.call("get_state", _setup.members[index].uid) as Object
			position[index] = state.get("position")
			velocity[index] = state.get("velocity")
			speed[index] = state.get("speed")
			yaw[index] = state.get("yaw")
			yaw_rate[index] = state.get("yaw_rate")
			pitch[index] = state.get("pitch")
			travel_pitch[index] = state.get("travel_pitch")
			shader_speed[index] = state.get("shader_speed")
			mode[index] = state.get("mode")
			darts[index] = state.get("darts_started")
			recovering[index] = 1 if state.get("recovering") else 0
			pinned[index] = 1 if state.get("pinned") else 0
			intends[index] = 1 if state.get("intends_to_move") else 0


## The smoothness checker of the plan (Q5), applied in every steering test: acceleration, speed and
## head-first checks skip the steps of the recovery ease (DoR note 2); the turn cap, the pitch
## limit, the yaw acceleration, the heading-rate sign flips and the "no teleport" bound never skip.
class Smooth:
	extends RefCounted
	var violations: Dictionary[String, int] = {}
	var samples: PackedStringArray = PackedStringArray()
	var steps: int = 0
	var max_speed_ratio: float = 0.0
	var max_move_ratio: float = 0.0
	var _members: Array[Member] = []
	var _has_prev: bool = false
	var _prev_pos: PackedVector3Array = PackedVector3Array()
	var _prev_speed: PackedFloat64Array = PackedFloat64Array()
	var _prev_yaw: PackedFloat64Array = PackedFloat64Array()
	var _prev_rate: PackedFloat64Array = PackedFloat64Array()
	var _prev_rec: PackedByteArray = PackedByteArray()
	var _flips: Array[PackedFloat64Array] = []
	var _last_sign: PackedInt32Array = PackedInt32Array()

	func _init(members: Array[Member]) -> void:
		_members = members
		_last_sign.resize(members.size())
		for _index: int in members.size():
			_flips.append(PackedFloat64Array())

	func total() -> int:
		var sum: int = 0
		for key: String in violations:
			sum += violations[key]
		return sum

	func report() -> String:
		return "%s %s" % [violations, samples]

	func _flag(kind: String, member: Member, time: float, detail: String) -> void:
		violations[kind] = violations.get(kind, 0) + 1
		if samples.size() < MAX_SAMPLES:
			samples.append("%s %s t=%.3f %s" % [kind, member.uid, time, detail])

	## Checks the observer values of one step of `delta` seconds ending at `time`.
	func check(obs: Observer, time: float, delta: float) -> void:
		steps += 1
		for index: int in _members.size():
			_check_fish(obs, index, time, delta)
		_prev_pos = obs.position.duplicate()
		_prev_speed = obs.speed.duplicate()
		_prev_yaw = obs.yaw.duplicate()
		_prev_rate = obs.yaw_rate.duplicate()
		_prev_rec = obs.recovering.duplicate()
		_has_prev = true

	func _check_fish(obs: Observer, index: int, time: float, delta: float) -> void:
		var member: Member = _members[index]
		var speed: float = obs.speed[index]
		var rate: float = obs.yaw_rate[index]
		var recovering: bool = obs.recovering[index] == 1
		max_speed_ratio = maxf(max_speed_ratio, speed / member.top)
		if not recovering and speed > member.top * SPEED_FACTOR_MAX + EPS:
			_flag("speed_cap", member, time, "speed %.4f top %.4f" % [speed, member.top])
		if obs.mode[index] == Api.mode_id("DART") and not recovering:
			if speed > member.top * member.speed_factor + 1e-7:
				_flag("dart_cap", member, time, "speed %.4f" % speed)
		if absf(rate) > member.turn_cap + 1e-7:
			_flag("turn_cap", member, time, "rate %.3f cap %.3f" % [rate, member.turn_cap])
		var limit: float = member.pitch_cap + deg_to_rad(PITCH_MARGIN_DEG)
		if absf(obs.pitch[index]) > limit or absf(obs.travel_pitch[index]) > limit:
			_flag("pitch", member, time, "pitch %.2f deg" % rad_to_deg(obs.pitch[index]))
		if not recovering and speed > member.top * HEAD_FIRST_MIN_SPEED:
			_check_head_first(obs, index, member, time)
		if _has_prev:
			var exempt: bool = recovering or _prev_rec[index] == 1
			_check_change(obs, index, member, time, delta, exempt)
			var moved: float = obs.position[index].distance_to(_prev_pos[index])
			var allowed: float = member.top * (RECOVERY_FACTOR if exempt else SPEED_FACTOR_MAX)
			max_move_ratio = maxf(max_move_ratio, moved / maxf(member.top * delta, EPS))
			if moved > allowed * delta * (1.0 + 1e-6) + 1e-7:
				_flag("jump", member, time, "moved %.5f in %.4f s" % [moved, delta])
		_count_flips(index, member, rate, time)

	func _check_head_first(obs: Observer, index: int, member: Member, time: float) -> void:
		var velocity: Vector3 = obs.velocity[index]
		if velocity.length() < EPS:
			return
		var yaw: float = obs.yaw[index]
		var pitch: float = obs.pitch[index]
		var heading: Vector3 = Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
		var angle: float = rad_to_deg(acos(clampf(heading.dot(velocity.normalized()), -1.0, 1.0)))
		if angle > HEAD_FIRST_MAX_DEG:
			_flag("head_first", member, time, "angle %.1f deg" % angle)

	func _check_change(
		obs: Observer, index: int, member: Member, time: float, delta: float, exempt: bool
	) -> void:
		if not exempt:
			var change: float = absf(obs.speed[index] - _prev_speed[index])
			if change > member.top / ACCEL_TIME_S * delta + 1e-9:
				_flag("accel", member, time, "change %.5f step %.4f" % [change, delta])
		var accel: float = absf(obs.yaw_rate[index] - _prev_rate[index])
		if accel > member.turn_cap / YAW_ACCEL_TIME_S * delta + 1e-7:
			_flag("yaw_accel", member, time, "change %.4f" % accel)
		var turned: float = absf(wrapf(obs.yaw[index] - _prev_yaw[index], -PI, PI))
		if turned > member.turn_cap * delta * (1.0 + 1e-6) + 1e-7:
			_flag("heading_rate", member, time, "turned %.4f rad" % turned)

	func _count_flips(index: int, member: Member, rate: float, time: float) -> void:
		if absf(rate) <= member.turn_cap * FLIP_DEADBAND:
			return
		var sign_now: int = 1 if rate > 0.0 else -1
		var last: int = _last_sign[index]
		_last_sign[index] = sign_now
		if last == 0 or last == sign_now:
			return
		var times: PackedFloat64Array = _flips[index]
		times.append(time)
		while times.size() > 0 and times[0] < time - FLIP_WINDOW_S:
			times.remove_at(0)
		_flips[index] = times
		if times.size() > FLIP_MAX:
			_flag("flips", member, time, "%d sign flips within 1 s" % times.size())


## The zone and hard limit checker (plan section 5, zones): the origin stays in the FishZones band
## of its species at its current x/z with an overshoot of at most 1 cm at the band edges (never
## below the bottom limit of a bottom fish), and inside the hard limits without any tolerance.
class Limits:
	extends RefCounted
	var violations: Dictionary[String, int] = {}
	var samples: PackedStringArray = PackedStringArray()
	var _members: Array[Member] = []
	var _setup: Setup = null
	var _zones: GDScript = null

	func _init(setup: Setup) -> void:
		_setup = setup
		_members = setup.members
		_zones = Api.script_of(FishApi.ZONES_PATH)

	func total() -> int:
		var sum: int = 0
		for key: String in violations:
			sum += violations[key]
		return sum

	func report() -> String:
		return "%s %s" % [violations, samples]

	func _flag(kind: String, member: Member, time: float, detail: String) -> void:
		violations[kind] = violations.get(kind, 0) + 1
		if samples.size() < MAX_SAMPLES:
			samples.append("%s %s t=%.3f %s" % [kind, member.uid, time, detail])

	func check(obs: Observer, time: float, with_band: bool = true) -> void:
		for index: int in _members.size():
			_check_fish(obs, index, time, with_band)

	func _check_fish(obs: Observer, index: int, time: float, with_band: bool) -> void:
		var member: Member = _members[index]
		var at: Vector3 = obs.position[index]
		var radius: float = float(member.extents.get("horizontal_radius_m"))
		var half_x: float = _setup.interior.x / 2.0 - radius
		var half_z: float = _setup.interior.z / 2.0 - radius
		if half_x < 0.0:
			half_x = _setup.interior.x / 2.0
		if half_z < 0.0:
			half_z = _setup.interior.z / 2.0
		if absf(at.x) > half_x + EPS or absf(at.z) > half_z + EPS:
			_flag("glass", member, time, "at %s" % at)
		var span: Object = (
			_zones.call(
				"origin_range",
				member.zone,
				_setup.surface,
				at.x,
				at.z,
				_setup.water_line,
				_setup.allowance,
				member.extents
			)
			as Object
		)
		var low: float = span.get("min_y")
		var high: float = span.get("max_y")
		var is_pinned: bool = span.get("pinned")
		if is_pinned:
			if absf(at.y - low) > BAND_TOLERANCE_M:
				_flag("pinned_height", member, time, "y %.4f pinned %.4f" % [at.y, low])
			return
		var below: float = float(member.extents.get("below_m"))
		var above: float = float(member.extents.get("above_m"))
		var floor_y: float = (
			low
			if member.zone == FishApi.ZONE_BOTTOM
			else (float(_setup.surface.call(at.x, at.z)) + below)
		)
		if at.y < floor_y - EPS or at.y > _setup.water_line - above + EPS:
			_flag("hard", member, time, "y %.5f floor %.5f" % [at.y, floor_y])
		if not with_band:
			return
		var low_edge: float = low if member.zone == FishApi.ZONE_BOTTOM else low - BAND_TOLERANCE_M
		if at.y < low_edge - EPS or at.y > high + BAND_TOLERANCE_M + EPS:
			_flag("band", member, time, "y %.4f band %.4f to %.4f" % [at.y, low, high])


## Watches every pair of fish for the personal space of the BA decisions: the time in which two
## origins are closer than the sum of their half-lengths (adult_length_cm / 2 each). A pair with a
## pinned fish is never counted (a pinned fish never moves away, only the others yield).
class Pairs:
	extends RefCounted
	var close: PackedFloat64Array = PackedFloat64Array()
	var _first: PackedInt32Array = PackedInt32Array()
	var _second: PackedInt32Array = PackedInt32Array()
	var _limit: PackedFloat64Array = PackedFloat64Array()
	var _uids: PackedStringArray = PackedStringArray()

	func _init(setup: Setup, cross_species_only: bool = false) -> void:
		for first: int in setup.members.size():
			for second: int in range(first + 1, setup.members.size()):
				var one: Member = setup.members[first]
				var two: Member = setup.members[second]
				if cross_species_only and one.species_id == two.species_id:
					continue
				_first.append(first)
				_second.append(second)
				_limit.append((one.length_m + two.length_m) / 2.0)
				_uids.append("%s/%s" % [one.uid, two.uid])
		close.resize(_first.size())

	func observe(obs: Observer, delta: float) -> void:
		for index: int in _first.size():
			var one: int = _first[index]
			var two: int = _second[index]
			if obs.pinned[one] == 1 or obs.pinned[two] == 1:
				continue
			if obs.position[one].distance_to(obs.position[two]) < _limit[index]:
				close[index] += delta

	func worst() -> float:
		var most: float = 0.0
		for seconds: float in close:
			most = maxf(most, seconds)
		return most

	func report() -> String:
		var parts: PackedStringArray = PackedStringArray()
		for index: int in close.size():
			if close[index] > 0.5 and parts.size() < 6:
				parts.append("%s %.2f s" % [_uids[index], close[index]])
		return ", ".join(parts)


## A numeric species field, 0 while the field does not exist yet.
static func _field(species: Resource, field: String) -> float:
	var value: Variant = species.get(field)
	return 0.0 if value == null else float(value)


## The species resource of the pinned test fish (see PINNED_ID); null while FishSpecies is missing.
static func pinned_species() -> Resource:
	return FishApi.variant_of(FishApi.ANGEL, {"id": PINNED_ID, "adult_length_cm": PINNED_ADULT_CM})


## The entry of the pinned test fish, measured with the angelfish model.
static func pinned_entry(uid: String) -> Dictionary:
	return entry(PINNED_ID, uid, pinned_species(), null, FishApi.ANGEL)


static func tank_of(tank_id: StringName) -> TankDefinition:
	return TankCatalog.load_dir().get_definition(tank_id)


## `count` uids of 8 hex characters from a RandomNumberGenerator seeded with `seed_value`.
static func uids(count: int, seed_value: int = UID_SEED, skip: int = 0) -> Array[String]:
	var random: RandomNumberGenerator = RandomNumberGenerator.new()
	random.seed = seed_value
	var result: Array[String] = []
	var seen: Dictionary[String, bool] = {}
	var drawn: int = 0
	while result.size() < count:
		var text: String = "%08x" % random.randi()
		drawn += 1
		if seen.has(text) or drawn <= skip:
			continue
		seen[text] = true
		result.append(text)
	return result


## An entry for open(): the species id, the uid and optional overrides: a species resource (a
## copy with changed fields), a start pose object, the id of the model to measure (when the species
## is a copy with another id) and a FishPersonality object (extreme personalities).
static func entry(
	id: StringName,
	uid: String,
	species: Resource = null,
	pose: Object = null,
	model: StringName = &"",
	personality: Object = null
) -> Dictionary:
	return {
		"id": id,
		"uid": uid,
		"species": species,
		"pose": pose,
		"model": model if model != &"" else id,
		"personality": personality,
	}


## `count` entries of one species with seeded uids.
static func crowd(id: StringName, count: int, seed_value: int = UID_SEED) -> Array:
	var result: Array = []
	for uid: String in uids(count, seed_value):
		result.append(entry(id, uid))
	return result


## The mixed crowd of the BA decisions: tetras, then angelfish, then corydoras, uids drawn in turn
## from one seeded generator so no two fish share one.
static func mixed(tetras: int, angels: int, corys: int, seed_value: int = UID_SEED) -> Array:
	var all: Array[String] = uids(tetras + angels + corys, seed_value)
	var result: Array = []
	var index: int = 0
	for pair: Array in [[FishApi.NEON, tetras], [FishApi.ANGEL, angels], [FishApi.CORY, corys]]:
		for _count: int in int(pair[1]):
			result.append(entry(pair[0], all[index]))
			index += 1
	return result


## The flat sand surface of a tank as a Callable.
static func flat_surface(tank_id: StringName) -> Callable:
	var tank: TankDefinition = tank_of(tank_id)
	var sand: SubstrateDefinition = SubstrateCatalog.load_dir().get_definition(SAND)
	return FishApi.surface_source(sand, PackedFloat32Array(), Vector2i.ZERO, tank.interior_size_m)


static func sand_allowance() -> float:
	var sand: SubstrateDefinition = SubstrateCatalog.load_dir().get_definition(SAND)
	return FishApi.top_allowance(sand)


## A world object of a tank with a surface Callable (flat sand when empty).
static func world_of(tank_id: StringName, surface: Callable = Callable()) -> Object:
	var tank: TankDefinition = tank_of(tank_id)
	var used: Callable = surface if surface.is_valid() else flat_surface(tank_id)
	return Api.make_world(tank.interior_size_m, tank.water_line_height_m, used, sand_allowance())


## The Member of one fish: species, extents, personality, params and the expected caps.
static func member_of(
	id: StringName,
	uid: String,
	species: Resource = null,
	model: StringName = &"",
	personality: Object = null
) -> Member:
	var member: Member = Member.new()
	member.uid = uid
	member.species_id = id
	member.species = species if species != null else FishApi.species(id)
	if member.species == null:
		return null
	var adult: float = float(member.species.get("adult_length_cm"))
	member.length_m = adult / 100.0
	member.extents = ViewRig.extents_of(model if model != &"" else id, adult)
	member.personality = personality if personality != null else Api.personality(uid)
	member.params = Api.make_params(member.species, member.personality, member.extents)
	member.top = float(member.species.get("swim_speed")) * Api.TOP_SPEED_K * member.length_m
	member.turn_cap = deg_to_rad(_field(member.species, "turn_rate_max_deg_s"))
	member.pitch_cap = deg_to_rad(_field(member.species, "pitch_limit_deg"))
	member.zone = int(member.species.get("preferred_zone"))
	member.speed_factor = float(member.personality.get("speed")) if member.personality else 1.0
	return member


## The pose object FishRestPose gives a member in the setup (a Pose).
static func rest_pose(setup: Setup, member: Member) -> Object:
	var script: GDScript = Api.script_of(Api.POSE_PATH)
	return (
		script.call(
			"compute",
			member.uid,
			member.zone,
			member.extents,
			setup.interior,
			setup.water_line,
			setup.surface,
			setup.allowance
		)
		as Object
	)


## Builds the simulation of a catalog tank with the entries (see entry()). Returns null while a
## class is missing, so the caller asserts and returns.
static func open(
	tank_id: StringName,
	entries: Array,
	surface: Callable = Callable(),
	with_tuning: Resource = null
) -> Setup:
	var tank: TankDefinition = tank_of(tank_id)
	var used: Callable = surface if surface.is_valid() else flat_surface(tank_id)
	return open_box(tank.interior_size_m, tank.water_line_height_m, entries, used, with_tuning)


## The same for any box: interior size, water line and a surface Callable (x, z) -> metres.
static func open_box(
	interior: Vector3,
	water_line: float,
	entries: Array,
	surface: Callable,
	with_tuning: Resource = null
) -> Setup:
	var setup: Setup = Setup.new()
	setup.interior = interior
	setup.water_line = water_line
	setup.surface = surface
	setup.allowance = sand_allowance()
	setup.world = Api.make_world(interior, water_line, surface, setup.allowance)
	setup.sim = Api.make_sim(SIM_SEED, with_tuning)
	if setup.world == null or setup.sim == null or FishApi.shipped() == null:
		return null
	setup.sim.call("set_world", setup.world)
	for spec: Dictionary in entries:
		if add(setup, spec) == null:
			return null
	return setup


## Adds one fish to the simulation at its rest pose (or the pose of the entry) and returns it.
static func add(setup: Setup, spec: Dictionary) -> Member:
	var member: Member = member_of(
		spec["id"],
		spec["uid"],
		spec.get("species"),
		spec.get("model", &""),
		spec.get("personality")
	)
	if member == null or member.params == null:
		return null
	var pose: Object = spec.get("pose") as Object
	if pose == null:
		pose = rest_pose(setup, member)
	setup.sim.call("add_fish", member.uid, member.params, pose)
	setup.index_of[member.uid] = setup.members.size()
	setup.members.append(member)
	return member


## Gives the running simulation a new world (any box) through set_world and updates the setup.
static func change_world(
	setup: Setup, interior: Vector3, water_line: float, surface: Callable
) -> void:
	setup.interior = interior
	setup.water_line = water_line
	setup.surface = surface
	setup.world = Api.make_world(interior, water_line, surface, setup.allowance)
	setup.sim.call("set_world", setup.world)


## change_world for a catalog tank (flat sand when `surface` is empty).
static func change_tank(setup: Setup, tank_id: StringName, surface: Callable = Callable()) -> void:
	var tank: TankDefinition = tank_of(tank_id)
	var used: Callable = surface if surface.is_valid() else flat_surface(tank_id)
	change_world(setup, tank.interior_size_m, tank.water_line_height_m, used)


## Removes one fish from the simulation and from the setup.
static func remove(setup: Setup, uid: String) -> void:
	setup.sim.call("remove_fish", uid)
	setup.members.remove_at(setup.index_of[uid])
	setup.index_of.clear()
	for index: int in setup.members.size():
		setup.index_of[setup.members[index].uid] = index


static func state_of(setup: Setup, uid: String) -> Object:
	return setup.sim.call("get_state", uid) as Object


## Steps the simulation `seconds` in steps of `delta`, returning the number of steps.
static func run(setup: Setup, seconds: float, delta: float = STEP) -> int:
	var steps: int = roundi(seconds / delta)
	for _step: int in steps:
		setup.sim.call("step", delta)
	return steps


## The mean over every fish of the distance to its nearest other fish of the same species id, in
## metres, and the same in body lengths (adult_length_cm / 100) of that fish.
static func nearest_same_species(setup: Setup, obs: Observer) -> PackedFloat64Array:
	var result: PackedFloat64Array = PackedFloat64Array()
	result.resize(setup.members.size())
	for index: int in setup.members.size():
		var best: float = INF
		for other: int in setup.members.size():
			if other == index or setup.members[other].species_id != setup.members[index].species_id:
				continue
			best = minf(best, obs.position[index].distance_to(obs.position[other]))
		result[index] = best
	return result


static func mean(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var sum: float = 0.0
	for value: float in values:
		sum += value
	return sum / values.size()


## True when a fish stands inside the tank volume of a setup (origin only, any tolerance zero).
static func inside_tank(setup: Setup, at: Vector3) -> bool:
	return (
		absf(at.x) <= setup.interior.x / 2.0
		and absf(at.z) <= setup.interior.z / 2.0
		and at.y > 0.0
		and at.y < setup.water_line
	)
