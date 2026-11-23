class_name FishSwimSim
extends RefCounted
## The steering simulation of all fish of one tank (ADR 0015 rules 4 to 7): pure, no Node, no
## species or tuning literal. Time comes in through step(delta), randomness through the injected
## RandomNumberGenerator, every tuning value through FishSwimTuning and FishSwimParams.
##
## A fish moves along its travel direction (yaw, travel pitch) at a scalar speed, so it is
## head-first by construction. Speed, yaw rate and yaw acceleration are capped; the glass is
## respected by braking in time, the band by steering, and both are clamped exactly as a last
## resort. The states are idle (hover), cruise (wander with school forces), dart (a short burst)
## and override (seek a target, the seam for feeding). A fish outside its limits after a world
## change is guided back by the recovery ease (begin_recovery), which is also the seam for items
## placed over a fish (#168). step() splits a delta into equal substeps of at most max_substep_s,
## so any frame rate gives the same trajectory and a hitch never breaks a cap.

const _GROUPED_FROM: int = FishSpecies.GroupStyle.TIGHT_SCHOOL
## Positions are 32-bit vectors, so a speed read back from a displacement carries a rounding error
## of about 1e-5; the recovery plateau stays this far below its cap.
const _SPEED_MARGIN: float = 0.999
## Positions are 32-bit vectors with a rounding error of up to 3e-8 at tank size; the hard clamps
## stay this far inside their limits so a stored position never reads back outside them.
const _EDGE_EPSILON: float = 5.0e-8

var _tuning: FishSwimTuning = null
var _rng: RandomNumberGenerator = null
var _world: FishSwimWorld = null
var _fish: Array[FishSwimMember] = []
var _by_uid: Dictionary[String, FishSwimMember] = {}
var _paused: bool = false
## Seconds since the last neighbour search; INF forces a new search at the next substep.
var _neighbour_clock: float = 0.0
var _keys: Dictionary[StringName, int] = {}
var _scratch: FishSwimLimits.Vertical = FishSwimLimits.Vertical.new()
## The neighbour search results of the last search, by fish index.
var _nb: FishSwimNeighbours = FishSwimNeighbours.new()
# Constants of the current substep and of the tuning.
var _blend: float = 0.0
var _pitch_gain: float = 0.0
var _slow_from: float = 0.0
var _slow_inv: float = 0.0
var _slow_floor: float = 0.0


func _init(tuning: FishSwimTuning, rng: RandomNumberGenerator) -> void:
	_tuning = tuning
	_rng = rng
	_slow_from = deg_to_rad(tuning.turn_slow_from_deg)
	_slow_inv = 1.0 / (deg_to_rad(tuning.turn_slow_to_deg) - _slow_from)
	_slow_floor = tuning.turn_slow_floor


# --- public API ---


## Gives the simulation its tank. Every fish outside its new limits starts the recovery ease
## (unless it is already recovering).
func set_world(world: FishSwimWorld) -> void:
	_world = world
	_neighbour_clock = INF
	for fish: FishSwimMember in _fish:
		_refresh_geometry(fish)
		_refresh_pin(fish)
		if not fish.recovering and _must_recover(fish):
			begin_recovery(fish.uid)
		_refresh_override_goal(fish)


## Adds a fish at a start pose (speed 0, fresh timers). An existing fish of the uid is replaced.
func add_fish(uid: String, params: FishSwimParams, rest_pose: FishRestPose.Pose) -> void:
	remove_fish(uid)
	var fish: FishSwimMember = FishSwimMember.new()
	fish.uid = uid
	fish.params = params
	fish.position = rest_pose.position
	fish.yaw = rest_pose.yaw
	fish.anchor = Vector2(rest_pose.position.x, rest_pose.position.z)
	_register_key(params)
	_fish.append(fish)
	_by_uid[uid] = fish
	_neighbour_clock = INF
	_refresh_geometry(fish)
	_refresh_pin(fish)
	fish.dart_timer = _draw(params.dart_interval_min_s, params.dart_interval_max_s)
	if _rng.randf() < _idle_share(params):
		_start_idle(fish)
	else:
		_start_cruise(fish)
	fish.mode_left *= _rng.randf()
	_write_state(fish, Vector3.ZERO)


func remove_fish(uid: String) -> void:
	var fish: FishSwimMember = _by_uid.get(uid)
	if fish == null:
		return
	_by_uid.erase(uid)
	_fish.erase(fish)
	_neighbour_clock = INF


## Gives a fish new inputs (a species change) and keeps its position; a fish that is outside its
## new limits starts the recovery ease.
func replace_params(uid: String, params: FishSwimParams) -> void:
	var fish: FishSwimMember = _by_uid.get(uid)
	if fish == null:
		return
	fish.params = params
	_register_key(params)
	_neighbour_clock = INF
	_refresh_geometry(fish)
	_refresh_pin(fish)
	if not fish.recovering and _must_recover(fish):
		begin_recovery(uid)


func clear() -> void:
	_fish.clear()
	_by_uid.clear()
	_neighbour_clock = INF


func get_state(uid: String) -> FishSwimState:
	var fish: FishSwimMember = _by_uid.get(uid)
	return null if fish == null else fish.state


func get_uids() -> Array[String]:
	var result: Array[String] = []
	for fish: FishSwimMember in _fish:
		result.append(fish.uid)
	return result


## The delta the simulation uses for a frame of `delta` seconds (0 for a zero or negative delta).
func clamp_delta(delta: float) -> float:
	return clampf(delta, 0.0, _tuning.max_delta_s)


## While paused positions, headings, speeds and timers freeze; only recoveries advance.
func set_paused(paused: bool) -> void:
	_paused = paused
	for fish: FishSwimMember in _fish:
		fish.state.intends_to_move = _intends(fish)


func is_paused() -> bool:
	return _paused


## Makes a fish seek `target` (tank-local metres, clamped to its limits) until cleared.
func set_override(uid: String, target: Vector3) -> void:
	var fish: FishSwimMember = _by_uid.get(uid)
	if fish == null:
		return
	fish.has_override = true
	fish.override_raw = target
	fish.detour_left = 0.0
	_refresh_override_goal(fish)


func clear_override(uid: String) -> void:
	var fish: FishSwimMember = _by_uid.get(uid)
	if fish == null or not fish.has_override:
		return
	fish.has_override = false
	fish.detour_left = 0.0
	fish.low_time = 0.0
	if not _paused:
		_start_cruise(fish)
		fish.state.mode = fish.mode


## Guides a fish to the nearest valid point of its limits with the recovery ease (also the seam
## for an item placed over a fish): no velocity step, at most recovery_speed_factor x top speed.
func begin_recovery(uid: String) -> void:
	var fish: FishSwimMember = _by_uid.get(uid)
	if fish == null or _world == null:
		return
	var params: FishSwimParams = fish.params
	var goal: Vector3 = FishSwimLimits.nearest_valid(
		_world, params, fish.position, _tuning.wall_margin_m, _tuning.band_inset_m, _scratch
	)
	var length: float = fish.position.distance_to(goal)
	if length < 1.0e-5:
		return
	var ramp: float = _tuning.recovery_ramp_s
	var cap: float = _tuning.recovery_speed_factor * params.top_speed_m_s * _SPEED_MARGIN
	fish.recovering = true
	fish.rec_from = fish.position
	fish.rec_to = goal
	fish.rec_len = length
	fish.rec_dir = (goal - fish.position) / length
	var plan: Vector2 = FishSwimRecovery.plan(length, cap, ramp, _tuning.recovery_max_s)
	fish.rec_total = plan.x
	fish.rec_speed = plan.y
	fish.rec_time = 0.0
	fish.speed = 0.0
	fish.low_time = 0.0
	fish.state.recovering = true


## Advances every fish by `delta` seconds (zero or negative changes nothing; above max_delta_s it
## counts as max_delta_s) in equal substeps of at most max_substep_s.
func step(delta: float) -> void:
	if delta <= 0.0 or _world == null or _fish.is_empty():
		return
	var total: float = minf(delta, _tuning.max_delta_s)
	var substeps: int = maxi(ceili(total / _tuning.max_substep_s - 1.0e-6), 1)
	var size: float = total / substeps
	for _index: int in substeps:
		_substep(size)


# --- one substep ---


func _substep(h: float) -> void:
	_blend = 1.0 - exp(-h / _tuning.steer_smooth_s)
	_pitch_gain = h / _tuning.pitch_response_s
	if not _paused:
		_neighbour_clock += h
		if _neighbour_clock >= _tuning.neighbour_period_s:
			_neighbour_clock = 0.0
			_refresh_neighbours()
	for fish: FishSwimMember in _fish:
		if fish.recovering:
			_recover(fish, h)
		elif _paused:
			continue
		elif fish.vert.pinned:
			_update_pinned(fish, h)
		else:
			_update(fish, h)
	if not _paused:
		_resolve_contacts(h)


func _update(f: FishSwimMember, h: float) -> void:
	var p: FishSwimParams = f.params
	var t: FishSwimTuning = _tuning
	var pos: Vector3 = f.position
	var i: int = f.idx
	var half: Vector2 = f.soft
	_advance_modes(f, h)
	var mode: FishSwimState.Mode = f.mode
	if mode != FishSwimState.Mode.IDLE and f.speed < p.stuck_speed_m_s:
		f.low_time += h
		f.blocked_time += h
		if f.low_time >= t.stuck_time_s:
			_unstick(f)
			mode = f.mode
	else:
		f.low_time = 0.0
		f.blocked_time = maxf(f.blocked_time - 0.5 * h, 0.0)
	# The wanted direction (forces summed) and the wanted speed.
	var goal: Vector3 = pos
	var base_speed: float = 0.0
	var seek: bool = true
	var catching_up: bool = false
	var overriding: bool = mode == FishSwimState.Mode.OVERRIDE
	match mode:
		FishSwimState.Mode.OVERRIDE:
			goal = f.target if f.detour_left > 0.0 else f.override_goal
			if f.detour_left > 0.0:
				if f.speed >= p.stuck_speed_m_s:
					f.detour_left = maxf(f.detour_left - h, 0.0)
				if _flat_distance(pos, f.target) < p.body_length_m * 0.25:
					f.detour_left = 0.0
			base_speed = minf(p.catch_up_speed_m_s, pos.distance_to(goal) * t.arrive_gain_per_s)
		FishSwimState.Mode.DART:
			goal = pos + Vector3(sin(f.dart_yaw), 0.0, cos(f.dart_yaw))
			goal.y = clampf(pos.y, f.ahead_low, f.ahead_high)
			base_speed = p.dart_speed_m_s
		FishSwimState.Mode.CRUISE:
			goal = f.target
			base_speed = p.cruise_speed_m_s
			if p.group_style >= _GROUPED_FROM and _nb.near[i] >= 0:
				if _nb.near_sq[i] > p.catch_up_distance_m * p.catch_up_distance_m:
					goal = _nb.pos[_nb.near[i]]
					base_speed = p.catch_up_speed_m_s
					catching_up = true
		_:
			seek = false
			base_speed = p.idle_drift_m_s
	var want: Vector3 = Vector3.ZERO
	if seek:
		var off: Vector3 = goal - pos
		var flat: float = Vector2(off.x, off.z).length()
		var aim_y: float = goal.y if overriding else clampf(goal.y, f.ahead_low, f.ahead_high)
		if flat > p.body_length_m * 0.25:
			var slope: float = (aim_y - pos.y) / maxf(flat, p.body_length_m * 3.0)
			want = Vector3(off.x / flat, slope, off.z / flat) * t.wander_weight
		else:
			want.y = clampf((aim_y - pos.y) / (p.body_length_m * 0.5), -1.0, 1.0)
			if overriding and Vector2(pos.x, pos.z).length() > 1.0e-6:
				# Arrived at the override target: face open water.
				var inward: Vector2 = -Vector2(pos.x, pos.z).normalized() * t.arrival_turn_weight
				want.x = inward.x
				want.z = inward.y
		if mode == FishSwimState.Mode.CRUISE and not catching_up:
			want += _school_force(f, i, pos)
	var push: Vector3 = _nb.sep[i].limit_length(t.separation_force_cap) * t.separation_weight
	push += _nb.avd[i].limit_length(t.avoid_force_cap) * t.avoid_weight
	push.y *= t.social_vertical_scale
	if seek:
		want += push
	elif push.length_squared() > 0.0025:
		want = push
		base_speed = maxf(base_speed, minf(p.cruise_speed_m_s, push.length() * p.cruise_speed_m_s))
	# Glass ahead (within a turning radius): nothing may pull the fish into it, and it steers away.
	var avoid: float = p.avoid_m
	var weight: float = t.wall_avoid_weight
	var near_x: float = pos.x - half.x + avoid
	var near_z: float = pos.z - half.y + avoid
	if near_x > 0.0:
		want.x = minf(want.x, 0.0) - minf(near_x / avoid, 1.5) * weight
	elif pos.x + half.x - avoid < 0.0:
		want.x = maxf(want.x, 0.0) + minf((avoid - half.x - pos.x) / avoid, 1.5) * weight
	if near_z > 0.0:
		want.z = minf(want.z, 0.0) - minf(near_z / avoid, 1.5) * weight
	elif pos.z + half.y - avoid < 0.0:
		want.z = maxf(want.z, 0.0) + minf((avoid - half.y - pos.z) / avoid, 1.5) * weight
	if mode != f.smooth_mode or mode == FishSwimState.Mode.DART:
		f.smooth_mode = mode
		f.want = want
	else:
		f.want = f.want.lerp(want, _blend)
		want = f.want
	# Near the glass the part of the wish that points into it fades out: the fish slides along it.
	var zone: float = f.speed * f.speed * p.stop_zone_per_speed_sq + t.wall_margin_m
	if want.x > 0.0:
		want.x *= clampf((half.x - pos.x) / zone, 0.0, 1.0)
	elif want.x < 0.0:
		want.x *= clampf((half.x + pos.x) / zone, 0.0, 1.0)
	if want.z > 0.0:
		want.z *= clampf((half.y - pos.z) / zone, 0.0, 1.0)
	elif want.z < 0.0:
		want.z *= clampf((half.y + pos.z) / zone, 0.0, 1.0)
	# Heading.
	var flat_want: float = Vector2(want.x, want.z).length()
	var wanted_speed: float = base_speed
	var rate_wanted: float = 0.0
	if flat_want > 1.0e-6:
		var err: float = wrapf(atan2(want.x, want.z) - f.yaw, -PI, PI)
		wanted_speed *= maxf(
			clampf(1.0 - (absf(err) - _slow_from) * _slow_inv, 0.0, 1.0), _slow_floor
		)
		rate_wanted = clampf(err / t.yaw_response_s, -p.turn_rate_max, p.turn_rate_max)
	_apply_yaw_rate(f, p, rate_wanted, h)
	var pitch_want: float = clampf(atan2(want.y, flat_want), -p.pitch_limit, p.pitch_limit)
	var room_low: float = f.vert.hard_low if overriding else f.ahead_low
	var room_high: float = f.vert.hard_high if overriding else f.ahead_high
	var reach_y: float = maxf(f.speed * t.look_ahead_s, 2.0 * p.body_length_m)
	pitch_want = clampf(
		pitch_want,
		-atan2(maxf(pos.y - room_low, 0.0), reach_y),
		atan2(maxf(room_high - pos.y, 0.0), reach_y)
	)
	_steer_pitch(f, p, pitch_want, h)
	# The direction of travel, the braking limit, the speed.
	var cos_pitch: float = cos(f.travel_pitch)
	var dir_x: float = sin(f.yaw) * cos_pitch
	var dir_z: float = cos(f.yaw) * cos_pitch
	var glass: Vector3 = _glass_brake(pos, dir_x, dir_z, f.brake)
	var free: float = glass.x
	dir_x = glass.y
	dir_z = glass.z
	var wall_speed: float = sqrt(2.0 * p.accel_max * maxf(free, 0.0)) * t.brake_safety
	# A fish that has been held back for a while creeps on at an increasing share of its cruise
	# speed, so two fish that block each other (or a ring of them) never wait for ever.
	var give_way: float = clampf(
		(f.blocked_time - t.give_way_after_s) / t.give_way_ramp_s, 0.0, 1.0
	)
	var clear_speed: float = _nb.clear[i]
	if _nb.touching[i] == 0:
		clear_speed = maxf(clear_speed, give_way * t.give_way_fraction * p.cruise_speed_m_s)
	wanted_speed = minf(wanted_speed, minf(wall_speed, clear_speed))
	var accel_step: float = p.accel_max * h
	f.speed = maxf(f.speed + clampf(wanted_speed - f.speed, -accel_step, accel_step), 0.0)
	var biased: bool = mode == FishSwimState.Mode.IDLE or mode == FishSwimState.Mode.CRUISE
	f.bias = move_toward(f.bias, p.nose_down_bias if biased else 0.0, p.bias_step_per_s * h)
	_integrate(f, p, h, overriding, dir_x, dir_z)
	if mode == FishSwimState.Mode.CRUISE and not catching_up:
		if _flat_distance(f.position, f.target) < p.target_reach_m:
			_pick_target(f)


## A pinned fish hovers at the pinned height and drifts a little around its anchor.
func _update_pinned(f: FishSwimMember, h: float) -> void:
	var p: FishSwimParams = f.params
	var t: FishSwimTuning = _tuning
	f.mode = FishSwimState.Mode.IDLE
	f.low_time = 0.0
	f.drift_left -= h
	if f.drift_left <= 0.0:
		var angle: float = _rng.randf() * TAU
		var radius: float = t.pinned_drift_m * sqrt(_rng.randf())
		f.drift_goal = f.anchor + Vector2(cos(angle), sin(angle)) * radius
		f.drift_left = t.pinned_drift_period_s * (0.5 + _rng.randf())
	var off: Vector2 = f.drift_goal - Vector2(f.position.x, f.position.z)
	var gap: float = off.length()
	var wanted_speed: float = minf(p.idle_drift_m_s, gap * t.arrive_gain_per_s)
	var rate_wanted: float = 0.0
	if gap > t.pinned_drift_m * 0.1:
		var err: float = wrapf(atan2(off.x, off.y) - f.yaw, -PI, PI)
		wanted_speed *= maxf(
			clampf(1.0 - (absf(err) - _slow_from) * _slow_inv, 0.0, 1.0), _slow_floor
		)
		rate_wanted = clampf(err / t.yaw_response_s, -p.turn_rate_max, p.turn_rate_max)
	else:
		wanted_speed = 0.0
	_apply_yaw_rate(f, p, rate_wanted, h)
	_steer_pitch(f, p, 0.0, h)
	var accel_step: float = p.accel_max * h
	f.speed = maxf(f.speed + clampf(wanted_speed - f.speed, -accel_step, accel_step), 0.0)
	f.bias = move_toward(f.bias, p.nose_down_bias, p.bias_step_per_s * h)
	var cos_pitch: float = cos(f.travel_pitch)
	_integrate(f, p, h, false, sin(f.yaw) * cos_pitch, cos(f.yaw) * cos_pitch)


# --- modes ---


func _advance_modes(f: FishSwimMember, h: float) -> void:
	var p: FishSwimParams = f.params
	f.since_dart += h
	if f.has_override:
		if f.mode != FishSwimState.Mode.OVERRIDE:
			f.mode = FishSwimState.Mode.OVERRIDE
			f.low_time = 0.0
		return
	if f.mode == FishSwimState.Mode.OVERRIDE:
		_start_cruise(f)
	f.dart_timer -= h
	if f.mode == FishSwimState.Mode.DART:
		f.dart_left -= h
		if f.dart_left <= 0.0:
			f.mode = f.resume_mode
			if f.mode == FishSwimState.Mode.CRUISE and f.mode_left <= 0.0:
				_start_idle(f)
		return
	f.mode_left -= h
	if f.mode_left <= 0.0:
		if f.mode == FishSwimState.Mode.CRUISE:
			_start_idle(f)
		else:
			_start_cruise(f)
	elif f.mode == FishSwimState.Mode.IDLE and p.group_style >= _GROUPED_FROM:
		var far: float = _tuning.catch_up_distance_bl * p.body_length_m
		if f.idx >= 0 and f.idx < _nb.near.size() and _nb.near[f.idx] >= 0:
			if _nb.near_sq[f.idx] > far * far:
				_start_cruise(f)
	if f.dart_timer <= 0.0 and f.since_dart >= _tuning.min_dart_gap_s:
		_try_dart(f)


func _start_idle(f: FishSwimMember) -> void:
	f.mode = FishSwimState.Mode.IDLE
	f.mode_left = _draw(_tuning.idle_episode_min_s, _tuning.idle_episode_max_s)


func _start_cruise(f: FishSwimMember) -> void:
	var share: float = _idle_share(f.params)
	var mean_idle: float = (_tuning.idle_episode_min_s + _tuning.idle_episode_max_s) / 2.0
	var mean_cruise: float = mean_idle * (1.0 - share) / share
	f.mode = FishSwimState.Mode.CRUISE
	f.mode_left = mean_cruise * _draw(0.5, 1.5)
	_pick_target(f)


## Starts a dart in the first direction that has room for it, or tries again soon.
func _try_dart(f: FishSwimMember) -> void:
	var half: Vector2 = f.soft
	var p: FishSwimParams = f.params
	var t: FishSwimTuning = _tuning
	if f.vert.pinned or f.mode == FishSwimState.Mode.DART:
		return
	if f.speed > p.dart_speed_m_s:
		# Still faster than a dart may be (catching up): wait until the speed has come down.
		f.dart_timer = t.dart_retry_s
		return
	var duration: float = _draw(p.dart_duration_min_s, p.dart_duration_max_s)
	var need: float = (
		p.dart_speed_m_s * duration + p.dart_speed_m_s * p.dart_speed_m_s / (2.0 * p.accel_max)
	)
	var side: float = 1.0 if _rng.randf() < 0.5 else -1.0
	var step_angle: float = deg_to_rad(t.dart_angle_step_deg)
	var chosen: float = INF
	for k: int in range(0, t.dart_angle_steps + 1):
		for direction: float in [side, -side]:
			var yaw: float = f.yaw + direction * k * step_angle
			if _free_along(f.position, sin(yaw), cos(yaw), half) >= need:
				chosen = yaw
				break
		if chosen != INF:
			break
	if chosen == INF:
		f.dart_timer = t.dart_retry_s
		return
	f.resume_mode = f.mode
	f.mode = FishSwimState.Mode.DART
	f.dart_yaw = chosen
	f.dart_left = duration
	f.since_dart = 0.0
	f.low_time = 0.0
	f.dart_timer = _draw(p.dart_interval_min_s, p.dart_interval_max_s)
	f.state.darts_started += 1


## The stuck rule: a fish that intends to move but stays slow picks a new target.
func _unstick(f: FishSwimMember) -> void:
	var half: Vector2 = f.soft
	f.low_time = 0.0
	if f.mode == FishSwimState.Mode.OVERRIDE:
		var hop: float = _tuning.detour_radius_bl * f.params.body_length_m
		var goal: Vector3 = f.override_goal
		var shift_x: float = sin(f.yaw) * hop
		var shift_z: float = cos(f.yaw) * hop
		# A hop never points out of the water: it turns around at the glass.
		if absf(goal.x + shift_x) > half.x:
			shift_x = -shift_x
		if absf(goal.z + shift_z) > half.y:
			shift_z = -shift_z
		f.target = goal + Vector3(shift_x, 0.0, shift_z)
		f.detour_left = _tuning.detour_s
	elif f.mode == FishSwimState.Mode.DART:
		f.mode = f.resume_mode
		_pick_target(f)
	else:
		_pick_target(f)


## A new wander target: the target of a school-mate in view when the fish follows, else a random
## point of the band at a random place.
func _pick_target(f: FishSwimMember) -> void:
	if _world == null:
		return
	var p: FishSwimParams = f.params
	var soft: Vector2 = f.soft
	var mate: FishSwimMember = _mate_of(f)
	if (
		mate != null
		and p.group_style >= _GROUPED_FROM
		and _nb.count[f.idx] > 0
		and _rng.randf() < _tuning.follow_target_chance
		and mate.mode == FishSwimState.Mode.CRUISE
	):
		var jitter: float = maxf(p.spacing_m, p.body_length_m)
		var offset: Vector3 = Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0))
		var shifted: Vector3 = mate.target + offset * jitter
		f.target = _inside_goal(f, shifted.x, shifted.z, soft, shifted.y, false)
		return
	f.target = _random_goal(f, soft)


func _random_goal(f: FishSwimMember, soft: Vector2) -> Vector3:
	var p: FishSwimParams = f.params
	var best: Vector3 = f.position
	var best_gap: float = -1.0
	var wanted_gap: float = 3.0 * p.body_length_m
	var span_x: float = maxf(soft.x - p.avoid_m, 0.0)
	var span_z: float = maxf(soft.y - p.avoid_m, 0.0)
	for _attempt: int in 3:
		var x: float = _rng.randf_range(-span_x, span_x)
		var z: float = _rng.randf_range(-span_z, span_z)
		var candidate: Vector3 = _inside_goal(f, x, z, soft, 0.0, true)
		var gap: float = _flat_distance(candidate, f.position)
		if gap > best_gap:
			best = candidate
			best_gap = gap
		if gap >= wanted_gap:
			break
	return best


## A goal at (x, z) kept inside the soft box with a height in the band: the preferred height with
## a random variation, or `height` when `vary` is false.
func _inside_goal(
	f: FishSwimMember, x: float, z: float, soft: Vector2, height: float, vary: bool
) -> Vector3:
	var p: FishSwimParams = f.params
	var gx: float = clampf(x, -soft.x, soft.x)
	var gz: float = clampf(z, -soft.y, soft.y)
	FishSwimLimits.vertical(_world, p, gx, gz, _scratch)
	var low: float = _scratch.min_y
	var high: float = _scratch.max_y
	if high - low > 2.0 * _tuning.band_inset_m:
		low += _tuning.band_inset_m
		high -= _tuning.band_inset_m
	var y: float = height
	if vary:
		var band: float = _scratch.max_y - _scratch.min_y
		y = (
			_scratch.preferred(p.depth_fraction)
			+ band * _tuning.wander_height_jitter * _rng.randf_range(-1.0, 1.0)
		)
	return Vector3(gx, clampf(y, low, high), gz)


# --- steering helpers ---


## The school forces of a cruising fish: spacing, cohesion and alignment (by group style).
func _school_force(f: FishSwimMember, i: int, pos: Vector3) -> Vector3:
	var p: FishSwimParams = f.params
	var t: FishSwimTuning = _tuning
	if p.group_style < _GROUPED_FROM:
		return Vector3.ZERO
	var force: Vector3 = _nb.spc[i].limit_length(t.spacing_force_cap) * t.spacing_weight
	var mates: int = _nb.count[i]
	if mates > 0:
		var off: Vector3 = _nb.coh[i] / mates - pos
		var gap: float = off.length()
		var inner: float = p.spacing_m * 0.5
		var pull: float = clampf((gap - inner) / maxf(p.view_radius_m - inner, 1.0e-6), 0.0, 1.0)
		# Cohesion fades while a school-mate is closer than the spacing, so a school never packs.
		var lonely: float = clampf(
			(sqrt(_nb.near_sq[i]) - p.body_length_m) / maxf(p.spacing_m - p.body_length_m, 1.0e-6),
			0.0,
			1.0
		)
		if gap > 1.0e-6:
			force += off / gap * (p.cohesion * t.cohesion_weight * pull * lonely)
		force += _nb.ali[i] / mates * (p.alignment * t.alignment_weight)
	force.y *= t.social_vertical_scale
	return force


## Turns the yaw rate toward the wanted one: limited by the yaw acceleration and the turn cap, and
## a turn does not reverse within min_flip_gap_s of the last reversal (at most 2 sign flips per
## second).
func _apply_yaw_rate(f: FishSwimMember, p: FishSwimParams, wanted: float, h: float) -> void:
	var t: FishSwimTuning = _tuning
	f.flip_clock += h
	if wanted != 0.0 and f.last_sign != 0 and (wanted > 0.0) != (f.last_sign > 0):
		if f.flip_clock < t.min_flip_gap_s:
			wanted = 0.0
	var limit: float = p.yaw_accel_max * h
	var rate: float = f.yaw_rate + clampf(wanted - f.yaw_rate, -limit, limit)
	f.yaw_rate = clampf(rate, -p.turn_rate_max, p.turn_rate_max)
	# wrapf snaps a value within 1e-5 of PI to -PI, a jump the heading-rate cap must not see.
	f.yaw += f.yaw_rate * h
	if f.yaw > PI:
		f.yaw -= TAU
	elif f.yaw < -PI:
		f.yaw += TAU
	if absf(f.yaw_rate) > t.yaw_deadband_fraction * p.turn_rate_max:
		var now_sign: int = 1 if f.yaw_rate > 0.0 else -1
		if now_sign != f.last_sign:
			if f.last_sign != 0:
				f.flip_clock = 0.0
			f.last_sign = now_sign


## Moves the travel pitch toward the wanted one, limited by the pitch rate and the pitch limit.
func _steer_pitch(f: FishSwimMember, p: FishSwimParams, wanted: float, h: float) -> void:
	var cap: float = p.pitch_rate_max * h
	var change: float = clampf((wanted - f.travel_pitch) * _pitch_gain, -cap, cap)
	f.travel_pitch = clampf(f.travel_pitch + change, -p.pitch_limit, p.pitch_limit)


## The glass ahead of a fish: x is the distance to travel before it must stop (INF when nothing is
## ahead), y and z the horizontal direction of travel. A fish flush with the glass whose heading
## points only slightly into it glides along the glass: that part of its motion is dropped instead
## of the fish being held still by the sign of a rounding error.
func _glass_brake(from: Vector3, dx: float, dz: float, limit: Vector2) -> Vector3:
	var slack: float = _tuning.brake_slack_m
	var glide: float = _tuning.glass_glide_sin
	var best: float = INF
	if dx > 1.0e-6:
		var gap_x: float = limit.x - from.x
		if gap_x <= 0.0 and dx <= glide:
			dx = 0.0
		else:
			best = (gap_x + slack) / dx
	elif dx < -1.0e-6:
		var gap_x: float = limit.x + from.x
		if gap_x <= 0.0 and dx >= -glide:
			dx = 0.0
		else:
			best = (gap_x + slack) / -dx
	if dz > 1.0e-6:
		var gap_z: float = limit.y - from.z
		if gap_z <= 0.0 and dz <= glide:
			dz = 0.0
		else:
			best = minf(best, (gap_z + slack) / dz)
	elif dz < -1.0e-6:
		var gap_z: float = limit.y + from.z
		if gap_z <= 0.0 and dz >= -glide:
			dz = 0.0
		else:
			best = minf(best, (gap_z + slack) / -dz)
	return Vector3(best, dx, dz)


## The distance along a horizontal direction to the glass limits (`half` is the soft box).
func _free_along(from: Vector3, dx: float, dz: float, half: Vector2) -> float:
	var slack: float = _tuning.brake_slack_m
	var best: float = INF
	if dx > 1.0e-6:
		best = (half.x - from.x + slack) / dx
	elif dx < -1.0e-6:
		best = (-half.x - from.x - slack) / dx
	if dz > 1.0e-6:
		best = minf(best, (half.y - from.z + slack) / dz)
	elif dz < -1.0e-6:
		best = minf(best, (-half.y - from.z - slack) / dz)
	return best


## The glass limits (hard) and the glass limits shrunk by the wall margin (soft) of a fish.
func _refresh_geometry(f: FishSwimMember) -> void:
	if _world == null:
		return
	var radius: float = f.params.extents.horizontal_radius_m
	var margin: float = _tuning.wall_margin_m
	var hard_x: float = FishSwimLimits.half_extent(_world.interior_size_m.x, radius)
	var hard_z: float = FishSwimLimits.half_extent(_world.interior_size_m.z, radius)
	f.hard = Vector2(maxf(hard_x - _EDGE_EPSILON, 0.0), maxf(hard_z - _EDGE_EPSILON, 0.0))
	f.soft = Vector2(maxf(hard_x - margin, 0.0), maxf(hard_z - margin, 0.0))
	var stop: float = _tuning.brake_margin_m
	f.brake = Vector2(maxf(hard_x - stop, 0.0), maxf(hard_z - stop, 0.0))


# --- movement ---


## Moves the fish one step along (dir_x, travel pitch, dir_z), clamps it to the hard limits (and the
## band, unless ignored), stores it and writes the state; the velocity is the displacement.
func _integrate(
	f: FishSwimMember, p: FishSwimParams, h: float, ignore_band: bool, dir_x: float, dir_z: float
) -> void:
	var distance: float = f.speed * h
	var next: Vector3 = _clamp_position(
		f,
		p,
		f.position + Vector3(dir_x * distance, sin(f.travel_pitch) * distance, dir_z * distance),
		ignore_band
	)
	var velocity: Vector3 = (next - f.position) / h
	f.step_from = f.position
	f.position = next
	_write_state(f, velocity)


## A position kept inside the hard limits and (unless ignored) the band margin. A fish that is
## already outside the band may not go further out.
func _clamp_position(
	f: FishSwimMember, p: FishSwimParams, next: Vector3, ignore_band: bool
) -> Vector3:
	next.x = clampf(next.x, -f.hard.x, f.hard.x)
	next.z = clampf(next.z, -f.hard.y, f.hard.y)
	var v: FishSwimLimits.Vertical = f.vert
	FishSwimLimits.vertical(_world, p, next.x, next.z, v)
	if v.pinned:
		next.y = v.hard_low
		return next
	var low: float = v.hard_low + _EDGE_EPSILON
	var high: float = v.hard_high - _EDGE_EPSILON
	if not ignore_band:
		var margin: float = _tuning.band_margin_m - _EDGE_EPSILON
		low = maxf(low, minf(maxf(low, v.min_y - margin), f.position.y))
		high = minf(high, maxf(minf(high, v.max_y + margin), f.position.y))
	next.y = clampf(next.y, low, high)
	return next


## Pushes apart the pairs that are closer than the sum of their half lengths (the personal space
## no fish may enter): the steering avoids them, this is the last resort and the way out of a
## jam. A pinned fish never moves, a push is limited to a share of the fish's own motion plus a
## slow drift, so it stays a nudge and never a jump.
func _resolve_contacts(h: float) -> void:
	var t: FishSwimTuning = _tuning
	for fish: FishSwimMember in _fish:
		fish.nudged = 0.0
	for k: int in _nb.contact_a.size():
		var a: FishSwimMember = _fish[_nb.contact_a[k]]
		var b: FishSwimMember = _fish[_nb.contact_b[k]]
		if a.recovering or b.recovering:
			continue
		var off: Vector3 = a.position - b.position
		var wanted: float = (
			(a.params.half_length_m + b.params.half_length_m) * t.contact_distance_factor
		)
		var d2: float = off.length_squared()
		if d2 >= wanted * wanted:
			continue
		var d: float = sqrt(d2)
		var away: Vector3 = off / d if d > 1.0e-9 else Vector3.RIGHT
		var share_a: float = 0.0 if a.vert.pinned else 0.5
		var share_b: float = 0.0 if b.vert.pinned else 0.5
		if share_a == 0.0 and share_b == 0.0:
			continue
		var scale: float = 1.0 / (share_a + share_b)
		var need: float = wanted - d
		_nudge(a, away * minf(need * share_a * scale, _contact_room(a, h)), h)
		_nudge(b, -away * minf(need * share_b * scale, _contact_room(b, h)), h)


## How far a contact may push a fish in one step. A fish that is nearly still may drift up to
## contact_still_fraction of its top speed in total (below the speed from which heading and motion
## must agree); a moving fish gets a share of its own motion (so heading and motion stay within the
## head-first angle). Never beyond the fastest speed a fish may have (the personality range), and
## all pushes of one step together stay within the room.
func _contact_room(f: FishSwimMember, h: float) -> float:
	var t: FishSwimTuning = _tuning
	var top: float = f.params.top_speed_m_s
	var room: float = maxf(
		t.contact_still_fraction * top - f.speed, t.contact_follow_fraction * f.speed
	)
	var fastest: float = FishPersonality.FACTOR_MIN + FishPersonality.FACTOR_SPAN
	return maxf(minf(room, maxf(fastest * top * 0.99 - f.speed, 0.0)) * h - f.nudged, 0.0)


## Moves a fish by a contact push (not part of its swimming velocity), keeps it inside its limits
## and lets its tail beat for the extra motion.
func _nudge(f: FishSwimMember, by: Vector3, h: float) -> void:
	if by.length_squared() <= 0.0:
		return
	var next: Vector3 = _clamp_position(
		f, f.params, f.position + by, f.mode == FishSwimState.Mode.OVERRIDE
	)
	f.nudged += by.length()
	f.position = next
	f.state.position = next
	var moved: float = next.distance_to(f.step_from) / h
	f.state.shader_speed = clampf(moved / f.params.top_speed_m_s, 0.0, 1.0)


func _write_state(f: FishSwimMember, velocity: Vector3) -> void:
	var p: FishSwimParams = f.params
	var s: FishSwimState = f.state
	s.position = f.position
	s.velocity = velocity
	s.speed = f.speed
	s.yaw = f.yaw
	s.yaw_rate = f.yaw_rate
	s.travel_pitch = f.travel_pitch
	s.pitch = clampf(f.travel_pitch - f.bias, -p.pitch_limit, p.pitch_limit)
	s.shader_speed = clampf(velocity.length() / p.top_speed_m_s, 0.0, 1.0)
	s.mode = f.mode
	s.recovering = f.recovering
	s.pinned = f.vert.pinned
	s.intends_to_move = (
		not _paused and not f.recovering and not f.vert.pinned and f.mode != FishSwimState.Mode.IDLE
	)
	s.low_speed_time = f.low_time


func _intends(f: FishSwimMember) -> bool:
	return (
		not _paused and not f.recovering and not f.vert.pinned and f.mode != FishSwimState.Mode.IDLE
	)


# --- recovery ease ---


func _recover(f: FishSwimMember, h: float) -> void:
	var p: FishSwimParams = f.params
	f.rec_time = minf(f.rec_time + h, f.rec_total)
	var next: Vector3 = (
		f.rec_from
		+ (
			f.rec_dir
			* FishSwimRecovery.distance(
				f.rec_len, f.rec_total, f.rec_speed, _tuning.recovery_ramp_s, f.rec_time
			)
		)
	)
	var velocity: Vector3 = (next - f.position) / h
	var flat: float = Vector2(f.rec_dir.x, f.rec_dir.z).length()
	var rate_wanted: float = 0.0
	if flat > 1.0e-3:
		var err: float = wrapf(atan2(f.rec_dir.x, f.rec_dir.z) - f.yaw, -PI, PI)
		rate_wanted = clampf(err / _tuning.yaw_response_s, -p.turn_rate_max, p.turn_rate_max)
	_apply_yaw_rate(f, p, rate_wanted, h)
	_steer_pitch(f, p, atan2(f.rec_dir.y, flat), h)
	f.bias = move_toward(f.bias, 0.0, p.bias_step_per_s * h)
	f.step_from = f.position
	f.position = next
	f.speed = velocity.length()
	if f.rec_time >= f.rec_total:
		f.position = f.rec_to
		f.recovering = false
		f.speed = 0.0
		FishSwimLimits.vertical(_world, p, f.position.x, f.position.z, f.vert)
		if _is_outside(f):
			begin_recovery(f.uid)
		elif not f.has_override and f.mode != FishSwimState.Mode.DART:
			_start_cruise(f)
	_write_state(f, velocity)


# --- neighbours ---


func _refresh_neighbours() -> void:
	_nb.rebuild(_fish, _keys, _tuning)
	for fish: FishSwimMember in _fish:
		_refresh_ahead(fish, fish.params)


## The band a fish looks at: the tighter of the band here and the band look_ahead_s ahead.
func _refresh_ahead(f: FishSwimMember, p: FishSwimParams) -> void:
	var inset: float = _tuning.band_inset_m
	var reach: float = f.speed * _tuning.look_ahead_s
	var x: float = f.position.x + sin(f.yaw) * reach
	var z: float = f.position.z + cos(f.yaw) * reach
	var radius: float = p.extents.horizontal_radius_m
	var limit_x: float = FishSwimLimits.half_extent(_world.interior_size_m.x, radius)
	var limit_z: float = FishSwimLimits.half_extent(_world.interior_size_m.z, radius)
	FishSwimLimits.vertical(
		_world, p, clampf(x, -limit_x, limit_x), clampf(z, -limit_z, limit_z), _scratch
	)
	var low: float = maxf(f.vert.min_y, _scratch.min_y)
	var high: float = minf(f.vert.max_y, _scratch.max_y)
	if high < low:
		high = low
	if high - low > 2.0 * inset:
		low += inset
		high -= inset
	f.ahead_low = low
	f.ahead_high = high


func _mate_of(f: FishSwimMember) -> FishSwimMember:
	var i: int = f.idx
	if i < 0 or i >= _nb.near.size() or i >= _fish.size() or _fish[i] != f:
		return null
	var mate: int = _nb.near[i]
	if mate < 0 or mate >= _fish.size():
		return null
	return _fish[mate]


# --- small helpers ---


func _register_key(params: FishSwimParams) -> void:
	if not _keys.has(params.species_key):
		_keys[params.species_key] = _keys.size()


func _refresh_pin(f: FishSwimMember) -> void:
	if _world == null:
		return
	FishSwimLimits.vertical(_world, f.params, f.position.x, f.position.z, f.vert)
	if f.vert.pinned and not f.was_pinned:
		f.anchor = Vector2(f.position.x, f.position.z)
	f.was_pinned = f.vert.pinned
	f.ahead_low = f.vert.min_y
	f.ahead_high = f.vert.max_y


func _refresh_override_goal(f: FishSwimMember) -> void:
	if not f.has_override or _world == null:
		return
	var p: FishSwimParams = f.params
	var soft: Vector2 = f.soft
	var x: float = clampf(f.override_raw.x, -soft.x, soft.x)
	var z: float = clampf(f.override_raw.z, -soft.y, soft.y)
	FishSwimLimits.vertical(_world, p, x, z, _scratch)
	var low: float = _scratch.hard_low
	var high: float = _scratch.hard_high
	if high - low > 2.0 * _tuning.band_inset_m:
		low += _tuning.band_inset_m
		high -= _tuning.band_inset_m
	f.override_goal = Vector3(x, clampf(f.override_raw.y, low, high), z)


func _is_outside(f: FishSwimMember) -> bool:
	return FishSwimLimits.is_outside(
		_world, f.params, f.position, _tuning.band_margin_m, _tuning.recovery_tolerance_m, _scratch
	)


## True when the fish is outside its limits, or so close to the glass ahead that it cannot stop in
## time within its acceleration cap (a tank change under a swimming fish).
func _must_recover(f: FishSwimMember) -> bool:
	if _is_outside(f):
		return true
	var p: FishSwimParams = f.params
	var cp: float = cos(f.travel_pitch)
	var free: float = _free_along(f.position, sin(f.yaw) * cp, cos(f.yaw) * cp, f.brake)
	return f.speed * f.speed > 2.0 * p.accel_max * maxf(free, 0.0)


func _idle_share(p: FishSwimParams) -> float:
	return clampf(p.idle_share, 0.02, 0.95)


func _draw(low: float, high: float) -> float:
	return _rng.randf_range(low, high)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
