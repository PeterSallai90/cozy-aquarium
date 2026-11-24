extends RefCounted
## The long simulation runs of the #35 tests, each (species, step) simulated exactly once per suite
## and cached in a static, so the zone, feel and smoothness tests of one species all read the
## metrics of the same run (plan section 5, "Suite time"). One run is 20 fish of one species with
## seeded uids in the large tank (100 x 40 cm), the shipped tuning, the steering random source
## seeded 777, 10 simulated minutes at a fixed step, the first 30 s discarded as settling for the
## feel metrics (BA decision Q7). The smoothness checker and the zone checker see every step,
## settling included.
##
## Measures (Q7): mean cruise speed = the average 3D speed of the origin over the steps in the
## cruise state, as a fraction of the species top speed; idle share = idle steps / all steps; dart
## rate = darts started / fish-seconds; dart duration = time in the dart state. Test helper only.

const Api := preload("res://tests/helpers/fish_swim_api.gd")
const Rig := preload("res://tests/helpers/fish_swim_rig.gd")

const COUNT: int = 20
const SETTLE_S: float = 30.0
const TOTAL_S: float = 600.0
## The angelfish runs (owner decision on #35 and the BA seed rule): ANGEL_RUNS runs of ANGEL_FISH
## fish, pooled into one set of per-fish values. Run i uses uid seed 12345 + i and steering seed
## 777 + i. Fallback if 5 fish cannot reach the mean cruise: 5 runs of 4 fish.
const ANGEL_RUNS: int = 4
const ANGEL_FISH: int = 5
const PER_FISH: Array[String] = [
	"cruise_fraction",
	"cruise_pitch",
	"idle_share",
	"dart_interval",
	"dart_duration",
	"mean_height",
	"depth_fraction",
	"darts",
]

static var _cache: Dictionary = {}


## The metrics of the run of `id` at `step` seconds; {"ok": false} while a class is missing.
## Angelfish are pooled over ANGEL_RUNS runs; the other species are one run of COUNT fish.
static func feel(id: StringName, step: float) -> Dictionary:
	return _pool(parts(id, step))


## The cached runs behind feel(): one for tetras and corydoras, ANGEL_RUNS for angelfish. Checks of
## per-run objects (smooth, limits) go through every part.
static func parts(id: StringName, step: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var tag: String = "%s@%d" % [id, roundi(1.0 / step)]
	if id != &"angelfish":
		result.append(custom(tag, id, Rig.crowd(id, COUNT), step))
		return result
	for run: int in ANGEL_RUNS:
		var entries: Array = Rig.crowd(id, ANGEL_FISH, Rig.UID_SEED + run)
		result.append(custom("%s#%d" % [tag, run], id, entries, step, Rig.SIM_SEED + run))
	return result


static func _pool(runs: Array[Dictionary]) -> Dictionary:
	for run: Dictionary in runs:
		if not run.get("ok", false):
			return {"ok": false}
	if runs.size() == 1:
		return runs[0]
	var pooled: Dictionary = runs[0].duplicate()
	pooled["count"] = 0
	pooled["min_gap"] = INF
	pooled["darts_match"] = true
	pooled["parts"] = runs
	for key: String in PER_FISH:
		if key == "darts":
			pooled[key] = PackedInt32Array()
		else:
			pooled[key] = PackedFloat64Array()
	for run: Dictionary in runs:
		pooled["count"] = int(pooled["count"]) + int(run["count"])
		pooled["min_gap"] = minf(float(pooled["min_gap"]), float(run["min_gap"]))
		pooled["darts_match"] = bool(pooled["darts_match"]) and bool(run["darts_match"])
		for key: String in PER_FISH:
			if key == "darts":
				var darts: PackedInt32Array = pooled[key]
				darts.append_array(run[key] as PackedInt32Array)
				pooled[key] = darts
			else:
				var values: PackedFloat64Array = pooled[key]
				values.append_array(run[key] as PackedFloat64Array)
				pooled[key] = values
	return pooled


## The same run for any entries (see FishSwimRig.entry), cached under `key`: the extreme
## personalities use one fish with a hand-made personality.
static func custom(
	key: String, id: StringName, entries: Array, step: float, sim_seed: int = Rig.SIM_SEED
) -> Dictionary:
	if not _cache.has(key):
		_cache[key] = _run(id, entries, step, sim_seed)
	return _cache[key]


static func _run(id: StringName, entries: Array, step: float, sim_seed: int) -> Dictionary:
	var started: int = Time.get_ticks_msec()
	var setup: Rig.Setup = Rig.open(Rig.LARGE, entries, Callable(), null, sim_seed)
	if setup == null:
		return {"ok": false}
	var count: int = setup.members.size()
	var obs: Rig.Observer = Rig.Observer.new(setup)
	var smooth: Rig.Smooth = Rig.Smooth.new(setup.members)
	var limits: Rig.Limits = Rig.Limits.new(setup)
	var idle_mode: int = Api.mode_id("IDLE")
	var cruise_mode: int = Api.mode_id("CRUISE")
	var dart_mode: int = Api.mode_id("DART")
	var cruise_sum: PackedFloat64Array = PackedFloat64Array()
	var pitch_sum: PackedFloat64Array = PackedFloat64Array()
	var height_sum: PackedFloat64Array = PackedFloat64Array()
	var duration_sum: PackedFloat64Array = PackedFloat64Array()
	var last_start: PackedFloat64Array = PackedFloat64Array()
	var cruise_steps: PackedInt32Array = PackedInt32Array()
	var idle_steps: PackedInt32Array = PackedInt32Array()
	var all_steps: PackedInt32Array = PackedInt32Array()
	var darts_after: PackedInt32Array = PackedInt32Array()
	var darts_done: PackedInt32Array = PackedInt32Array()
	var starts_total: PackedInt32Array = PackedInt32Array()
	var dart_run: PackedInt32Array = PackedInt32Array()
	var prev_mode: PackedInt32Array = PackedInt32Array()
	cruise_sum.resize(count)
	pitch_sum.resize(count)
	height_sum.resize(count)
	duration_sum.resize(count)
	cruise_steps.resize(count)
	idle_steps.resize(count)
	all_steps.resize(count)
	darts_after.resize(count)
	darts_done.resize(count)
	starts_total.resize(count)
	dart_run.resize(count)
	prev_mode.resize(count)
	last_start.resize(count)
	last_start.fill(-INF)
	prev_mode.fill(-1)
	var min_gap: float = INF
	var total_steps: int = roundi(TOTAL_S / step)
	var settle_steps: int = roundi(SETTLE_S / step)
	for index: int in total_steps:
		setup.sim.call("step", step)
		var time: float = (index + 1) * step
		obs.read()
		smooth.check(obs, time, step)
		limits.check(obs, time)
		for fish: int in count:
			var mode: int = obs.mode[fish]
			if mode == dart_mode:
				if prev_mode[fish] != dart_mode:
					starts_total[fish] += 1
					min_gap = minf(min_gap, time - last_start[fish])
					last_start[fish] = time
					dart_run[fish] = 0
					if index >= settle_steps:
						darts_after[fish] += 1
				dart_run[fish] += 1
			elif prev_mode[fish] == dart_mode and last_start[fish] >= SETTLE_S:
				duration_sum[fish] += dart_run[fish] * step
				darts_done[fish] += 1
			prev_mode[fish] = mode
			if index < settle_steps:
				continue
			all_steps[fish] += 1
			height_sum[fish] += obs.position[fish].y
			if mode == idle_mode:
				idle_steps[fish] += 1
			elif mode == cruise_mode:
				cruise_steps[fish] += 1
				cruise_sum[fish] += obs.speed[fish]
				pitch_sum[fish] += obs.pitch[fish]
	var span: float = TOTAL_S - SETTLE_S
	var cruise_fraction: PackedFloat64Array = PackedFloat64Array()
	var cruise_pitch: PackedFloat64Array = PackedFloat64Array()
	var idle_share: PackedFloat64Array = PackedFloat64Array()
	var dart_interval: PackedFloat64Array = PackedFloat64Array()
	var dart_duration: PackedFloat64Array = PackedFloat64Array()
	var mean_height: PackedFloat64Array = PackedFloat64Array()
	var depth_fraction: PackedFloat64Array = PackedFloat64Array()
	var darts_match: bool = true
	for fish: int in count:
		var member: Rig.Member = setup.members[fish]
		var cruising: int = cruise_steps[fish]
		cruise_fraction.append(0.0 if cruising == 0 else cruise_sum[fish] / cruising / member.top)
		cruise_pitch.append(0.0 if cruising == 0 else pitch_sum[fish] / cruising)
		idle_share.append(float(idle_steps[fish]) / maxf(float(all_steps[fish]), 1.0))
		dart_interval.append(INF if darts_after[fish] == 0 else span / darts_after[fish])
		dart_duration.append(
			0.0 if darts_done[fish] == 0 else duration_sum[fish] / darts_done[fish]
		)
		mean_height.append(height_sum[fish] / maxf(float(all_steps[fish]), 1.0))
		depth_fraction.append(float(member.personality.get("depth_preference")))
		if obs.darts[fish] != starts_total[fish]:
			darts_match = false
	var result: Dictionary = {
		"ok": true,
		"id": id,
		"step": step,
		"seconds": span,
		"count": count,
		"setup": setup,
		"smooth": smooth,
		"limits": limits,
		"min_gap": min_gap,
		"cruise_fraction": cruise_fraction,
		"idle_share": idle_share,
		"darts": darts_after,
		"dart_interval": dart_interval,
		"dart_duration": dart_duration,
		"mean_height": mean_height,
		"depth_fraction": depth_fraction,
		"cruise_pitch": cruise_pitch,
		"darts_match": darts_match,
	}
	for key: String in PER_FISH:
		var size: int = (result[key] as Variant).size()
		if size != count:
			push_error("FishSwimRuns %s: %s has %d entries for %d fish" % [id, key, size, count])
			result["ok"] = false
	result["wall_ms"] = Time.get_ticks_msec() - started
	print("FishSwimRuns %s at 1/%d s: %d ms" % [id, roundi(1.0 / step), result["wall_ms"]])
	return result
