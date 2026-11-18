# gdlint: disable=max-file-lines
extends SceneTree
## Measuring script for #28, the real 3D substrate bed (owner: tester; the technical-artist runs it
## after the art work and the tester repeats it after the developer). Not a test suite: GdUnit does
## not pick it up, and it needs the real renderer and a GPU (no --headless). It measures AC 34 and
## AC 41 of technical plan v3 (section 7 and the F = 3 amendment) in the main scene, 1920 x 1080
## requested, vsync off, TAA (the project default). The window cannot always reach the requested
## size (a title bar on a 1080-line screen leaves 1920 x 1061): the drawable size the frames were
## rendered at is recorded in the output ("resolution"), the requested one in
## "requested_resolution"; --borderless asks for a borderless window at the screen corner.
## Relative --out paths are relative to the repository root.
##
##   godot_console --path game -s res://tests/measure/substrate_budget_measure.gd -- \
##       --mode=gpu --type=all --out=.claude/state/previews/28/
##
## Options (all after the lone "--"):
##   --mode=gpu|hitch|orbit|colour  what to measure (default gpu)
##   --tank=<id>               gpu and colour mode: the tank (default tank_large_1); orbit mode:
##                             one tank or all (default all)
##   --type=<id>|all           substrate type(s) (default all; colour mode always sand_black)
##   --views=<a,b,...>         gpu mode: only these views (default: the default camera and the
##                             eight close-ups of tests/helpers/substrate_views.gd)
##   --cases=<type@view,...>   gpu mode: exactly these type and view pairs (replaces --type and
##                             --views; for the extra AC 34 cases of the other tanks)
##   --load=scaled|none        gpu mode: the stand-in D18 load of plan 1.2 (default scaled: the
##                             plan's 60 fish and 100 decor in the large tank, the same density per
##                             floor area in a smaller tank) or none
##   --out=<dir>               output directory (default .claude/state/previews/28/)
##   --tag=<text>              suffix of the output file name
##   --borderless              borderless window at the screen corner
##   --warmup=<n>              gpu mode warm-up frames per view (default 600)
##   --block=<n>               gpu mode frames per block (default 300)
##   --pairs=<n>               gpu mode alternating pairs of blocks (default 4)
##
## gpu: per type and view, warm up, then alternate blocks with the bed visible and hidden
##   (SubstrateBed.visible); added = median(visible) - median(hidden) of the measured GPU render
##   time of the root viewport; the pairs must agree within 0.02 ms or the block set is repeated
##   (at most twice). Checks: added <= 1.5 ms; added x F <= 1.5 ms with F = 3 (the RTX 3060 tier
##   estimate, owner decision), i.e. added <= 0.5 ms on this card; primitives (visible minus
##   hidden) <= 0.6 M at the default camera and <= 1.0 M at a close-up; the headless estimate is
##   not more than 10 percent below the reported primitives. Reported: render-server CPU, draw
##   calls, MultiMesh nodes, memory of the view. The extra AC 34 cases of the other tanks (BA
##   decision, issue #28 comment 6957276105) run with --tank and --views.
## hitch: a new session (caches empty), large tank, ten type changes (the five types twice) and
##   three tank changes; per change the longest frame, the time to bed_swapped and the main-thread
##   microseconds of the bed. A tank change replaces the tank and its bed: the script re-binds both
##   right after the action and resets the new bed's frame stats, carrying the microseconds its
##   show_type spent inside the action into the frame of the action. Checks: median of the longest
##   frames <= 33 ms; every change within 2 s and a type already built in the tank within one frame
##   (33 ms); main-thread assembly and instancing <= 4,000 us per frame; LOD update <= 500 us.
## orbit: per tank and type, the bed is built, then the camera moves linearly (position and target)
##   through the default camera, the eight close-ups and back to the default camera, then along an
##   arc around the default pivot (yaw -60 to +60 degrees, elevation 5 to 35 degrees, radius 45 to
##   100 percent of the default distance); every leg once with 60 and once with 15 frames.
##   get_last_lod_usec() is read every frame. Reported: max, p99, p95, median and the frames above
##   500 us. Check: max <= 500 us.
## colour: sand_black at its default swatch under the warm lamp, at the default camera and at the
##   35 cm view from above, without the stand-in load; the mean colour of the pixels the bed adds
##   (a second render with the bed hidden gives the mask, saved as a PNG; pixel counts reported):
##   chroma (max - min) / max <= 0.20 and the maximum channel <= 0.25. The mean is computed at the
##   mask thresholds 2/255 and 0.03 (sum of the channel differences); the two must agree within
##   0.01 per channel, else the mask holds pixels that are not the bed (code-reviewer decision,
##   issue #28 comment 6957252973).
##
## Output: substrate_<mode>[_<tank>][_<tag>].json (GPU name, driver, every number, a "checks" list
## with the limit and the result of each) and PNGs in colour mode. The exit code is 1 when a check
## fails.

const Views := preload("res://tests/helpers/substrate_views.gd")
const Api := preload("res://tests/helpers/substrate_bed_api.gd")
const Table := preload("res://tests/helpers/tank_table.gd")

const WIDTH := 1920
const HEIGHT := 1080
const MAIN_SCENE := "res://scenes/main.tscn"
const LARGE: StringName = &"tank_large_1"
const TANKS: Array[StringName] = [&"tank_small_1", &"tank_medium_1", &"tank_large_1"]
const TYPES: Array[StringName] = [
	&"sand_fine", &"gravel_natural", &"pebbles_river", &"sand_black", &"gravel_coloured"
]
const SETTLE_FRAMES := 20
const FACTOR := 3.0
const LIMIT_ADDED_MS := 1.5
const PAIR_AGREEMENT_MS := 0.02
const MAX_REPEATS := 2
const LIMIT_DEFAULT_PRIMITIVES := 600000.0
const LIMIT_CLOSE_UP_PRIMITIVES := 1000000.0
const ESTIMATE_SHORTFALL := 0.10
const LIMIT_FRAME_MS := 33.0
const LIMIT_SWAP_MS := 2000.0
const LIMIT_MAIN_USEC := 4000
const LIMIT_LOD_USEC := 500
const LIMIT_CHROMA := 0.20
const LIMIT_MAX_CHANNEL := 0.25
const MASK_EPSILON := 2.0 / 255.0
const MASK_EPSILON_HIGH := 0.03
const MASK_AGREEMENT := 0.01
## Orbit mode: frames per leg (slow and fast pass) and the arc waypoints (yaw and elevation in
## degrees, radius as a share of the default distance), starting and ending at the default camera.
const ORBIT_FRAMES: Array[int] = [60, 15]
const ORBIT_ARC: Array[Vector3] = [
	Vector3(0.0, 5.0, 1.0),
	Vector3(-60.0, 5.0, 1.0),
	Vector3(-60.0, 35.0, 0.45),
	Vector3(0.0, 35.0, 0.45),
	Vector3(60.0, 35.0, 0.45),
	Vector3(60.0, 5.0, 1.0),
	Vector3(0.0, 5.0, 1.0),
]
## Stand-in D18 load (technical plan 1.2), for the large tank.
const FISH_COUNT := 60
const FISH_LENGTH_M := 0.05
const DECOR_COUNT := 100
const LOAD_SEED := 28
const FISH_PATH := "res://assets/fish/proof_fish.glb"

var _args: Dictionary = {}
var _out_dir: String = ""
var _main: Node = null
var _room: Node3D = null
var _model: AquariumModel = null
var _camera: Camera3D = null
var _tank: Node3D = null
var _bed: Node3D = null
var _tank_id: StringName = LARGE
var _rid: RID = RID()
var _substrates: SubstrateCatalog = null
var _checks: Array[Dictionary] = []
var _result: Dictionary = {}


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--"):
			var parts: PackedStringArray = argument.substr(2).split("=", true, 1)
			_args[parts[0]] = parts[1] if parts.size() > 1 else "true"
	_out_dir = _absolute(str(_args.get("out", ".claude/state/previews/28/")))
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run()


func _absolute(path: String) -> String:
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://").path_join("..").path_join(path).simplify_path()


func _run() -> void:
	var mode: String = str(_args.get("mode", "gpu"))
	if not mode in ["gpu", "hitch", "orbit", "colour"]:
		push_error("unknown --mode=%s" % mode)
		quit(2)
		return
	var wanted_tank: String = str(_args.get("tank", "all" if mode == "orbit" else String(LARGE)))
	if mode in ["gpu", "colour"] and not TANKS.has(StringName(wanted_tank)):
		push_error("unknown --tank=%s" % wanted_tank)
		quit(2)
		return
	if mode in ["gpu", "colour"]:
		_tank_id = StringName(wanted_tank)
	_result = {
		"mode": mode,
		"tank": wanted_tank if mode == "orbit" else String(_tank_id),
		"gpu": RenderingServer.get_video_adapter_name(),
		"vendor": RenderingServer.get_video_adapter_vendor(),
		"driver": RenderingServer.get_video_adapter_api_version(),
		"godot": Engine.get_version_info().get("string", ""),
		"os": OS.get_name(),
		"requested_resolution": [WIDTH, HEIGHT],
		"factor": FACTOR,
	}
	await _setup(mode)
	match mode:
		"gpu":
			await _measure_gpu()
		"hitch":
			await _measure_hitch()
		"orbit":
			await _measure_orbit(wanted_tank)
		"colour":
			await _measure_colour()
	var failed: int = 0
	for entry: Dictionary in _checks:
		if entry["pass"] == false:
			failed += 1
	_result["checks"] = _checks
	_result["failed_checks"] = failed
	var path: String = _out_dir.path_join("substrate_%s.json" % _file_stem(mode))
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(_result, "\t"))
	file.close()
	print(
		(
			"[#28 measure] %s: %d checks, %d failed, written to %s"
			% [mode, _checks.size(), failed, path]
		)
	)
	quit(1 if failed > 0 else 0)


func _file_stem(mode: String) -> String:
	var stem: String = mode
	if mode in ["gpu", "colour"] and _tank_id != LARGE:
		stem += "_" + String(_tank_id)
	var tag: String = str(_args.get("tag", ""))
	if not tag.is_empty():
		stem += "_" + tag
	return stem


func _check(label: String, value: float, limit_text: String, passed: bool) -> void:
	_checks.append({"check": label, "value": value, "limit": limit_text, "pass": passed})
	print(
		"[#28 measure] %s %s: %.4f (%s)" % ["ok  " if passed else "FAIL", label, value, limit_text]
	)


# --- scene setup ---


func _setup(mode: String) -> void:
	if _args.has("borderless"):
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		DisplayServer.window_set_position(DisplayServer.screen_get_position())
	root.size = Vector2i(WIDTH, HEIGHT)
	DisplayServer.window_set_size(Vector2i(WIDTH, HEIGHT))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_rid = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_rid, true)
	_result["taa"] = root.use_taa
	_substrates = SubstrateCatalog.load_dir()
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(_main)
	await _settle()
	_model = _main.call("get_model") as AquariumModel
	_room = _find_room(_main)
	if _room == null or _model == null:
		push_error("the main scene has no model or no room")
		quit(2)
		return
	_model.apply_set_tank_id(_tank_id)
	await _settle()
	_bind_nodes()
	_result["load"] = {"fish": 0, "decor": 0, "kind": "none"}
	if mode == "gpu" and str(_args.get("load", "scaled")) != "none":
		_add_stand_in_load()
	_camera.process_mode = Node.PROCESS_MODE_DISABLED
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.fov = Views.FOV_DEG
	_camera.near = Views.NEAR_M
	await _settle()
	_record_resolution()


## The size the frames are actually drawn at (the window may stay below the requested size).
func _record_resolution() -> void:
	var drawn: Vector2i = root.get_texture().get_size()
	_result["resolution"] = [drawn.x, drawn.y]
	_result["window_size"] = [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y]
	_result["screen_size"] = [DisplayServer.screen_get_size().x, DisplayServer.screen_get_size().y]
	print(
		(
			"[#28 measure] drawn at %d x %d (requested %d x %d, window %s, screen %s)"
			% [drawn.x, drawn.y, WIDTH, HEIGHT, _result["window_size"], _result["screen_size"]]
		)
	)


func _find_room(node: Node) -> Node3D:
	var script: Script = node.get_script() as Script
	if script != null and script.get_global_name() == &"RoomCorner":
		return node as Node3D
	for child: Node in node.get_children():
		var found: Node3D = _find_room(child)
		if found != null:
			return found
	return null


func _bind_nodes() -> void:
	_camera = _room.get_node("BuildCamera") as Camera3D
	_rebind()


## The shown tank and its bed; the room replaces both on a tank change.
func _rebind() -> void:
	_tank = _room.get_node("Tank") as Node3D
	_bed = _tank.get_node_or_null("SubstrateAnchor/Substrate") as Node3D
	if _bed == null:
		push_error("Tank/SubstrateAnchor/Substrate is missing")
		quit(2)


func _settle() -> void:
	for _i: int in SETTLE_FRAMES:
		await process_frame
	await RenderingServer.frame_post_draw


## 60 static proof fish and 100 static sphere stand-ins in the large tank (technical plan 1.2); in
## a smaller tank the same number per floor area, the fish below its water line. The positions in
## the large tank are those of the plan's load.
func _add_stand_in_load() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = LOAD_SEED
	var interior: Vector3 = Table.interior(_tank_id)
	var large: Vector3 = Table.interior(LARGE)
	var share: float = minf(1.0, (interior.x * interior.z) / (large.x * large.z))
	var fish_count: int = roundi(float(FISH_COUNT) * share)
	var decor_count: int = roundi(float(DECOR_COUNT) * share)
	var fish_top: float = minf(0.45, Table.water_line(_tank_id) - 0.03)
	_result["load"] = {"fish": fish_count, "decor": decor_count, "kind": "scaled"}
	var fish_scene: PackedScene = load(FISH_PATH) as PackedScene
	var load_root: Node3D = Node3D.new()
	load_root.name = "StandInLoad"
	_tank.add_child(load_root)
	for _i: int in fish_count:
		var fish: Node3D = fish_scene.instantiate() as Node3D
		fish.scale = Vector3.ONE * FISH_LENGTH_M
		fish.position = Vector3(
			rng.randf_range(-(interior.x / 2.0 - 0.06), interior.x / 2.0 - 0.06),
			rng.randf_range(0.12, fish_top),
			rng.randf_range(-(interior.z / 2.0 - 0.05), interior.z / 2.0 - 0.05)
		)
		fish.rotation.y = rng.randf_range(0.0, TAU)
		load_root.add_child(fish)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.55, 0.5, 0.45)
	var surface: float = float(Api.fill_depth(_model.get_substrate_id()))
	for _i: int in decor_count:
		var diameter: float = rng.randf_range(0.03, 0.08)
		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = diameter / 2.0
		sphere.height = diameter
		sphere.radial_segments = 32
		sphere.rings = 24
		sphere.material = material
		var instance: MeshInstance3D = MeshInstance3D.new()
		instance.mesh = sphere
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		instance.position = Vector3(
			rng.randf_range(-(interior.x / 2.0 - 0.06), interior.x / 2.0 - 0.06),
			surface + diameter / 2.0,
			rng.randf_range(-(interior.z / 2.0 - 0.05), interior.z / 2.0 - 0.05)
		)
		load_root.add_child(instance)


## Shows the type with its default colour and completes the swap.
func _show_type(id: StringName) -> void:
	var definition: SubstrateDefinition = _substrates.get_definition(id)
	_model.apply_set_substrate(id, definition.default_colour)
	_bed.call("finish_pending")
	await _settle()


func _place_view(view_name: String, id: StringName) -> void:
	_place_pose(Views.pose_of(view_name, _tank_id, Api.fill_depth(id)))


func _place_pose(pose: Dictionary) -> void:
	_camera.global_transform = _tank.global_transform * Views.transform_of(pose)


# --- statistics ---


func _median(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted: PackedFloat32Array = values.duplicate()
	sorted.sort()
	# Intended integer division.
	@warning_ignore("integer_division")
	return sorted[sorted.size() / 2]


## The nearest-rank percentile (share 0..1) of the values.
func _percentile(values: PackedFloat32Array, share: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted: PackedFloat32Array = values.duplicate()
	sorted.sort()
	var rank: int = clampi(ceili(share * float(sorted.size())) - 1, 0, sorted.size() - 1)
	return sorted[rank]


func _info(kind: int) -> float:
	return float(
		RenderingServer.viewport_get_render_info(
			_rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, kind
		)
	)


## Runs `count` frames; adds the measured GPU time (ms) and render-server CPU time (ms) of each.
func _frames(count: int, gpu: PackedFloat32Array, cpu: PackedFloat32Array) -> void:
	for _i: int in count:
		await process_frame
		await RenderingServer.frame_post_draw
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(_rid))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(_rid))


# --- gpu ---


func _measure_gpu() -> void:
	var warmup: int = int(_args.get("warmup", 600))
	var block: int = int(_args.get("block", 300))
	var pairs: int = int(_args.get("pairs", 4))
	var rows: Array[Dictionary] = []
	var plan: Array[Dictionary] = _gpu_plan()
	for step: Dictionary in plan:
		var id: StringName = step["type"]
		await _show_type(id)
		var view_names: Array[String] = step["views"]
		for view_name: String in view_names:
			_place_view(view_name, id)
			for _i: int in warmup:
				await process_frame
			var row: Dictionary = await _measure_view(id, view_name, block, pairs)
			rows.append(row)
	_result["views"] = rows
	var worst: Dictionary = {}
	for row: Dictionary in rows:
		if worst.is_empty() or float(row["added_ms"]) > float(worst["added_ms"]):
			worst = row
	_result["worst"] = worst


## The types to show in order, each with its views: --cases when given, else every selected type
## with every selected view.
func _gpu_plan() -> Array[Dictionary]:
	var plan: Array[Dictionary] = []
	var cases: String = str(_args.get("cases", ""))
	if cases.is_empty():
		for id: StringName in _selected_types():
			plan.append({"type": id, "views": _selected_views()})
		return plan
	for entry: String in cases.split(","):
		var parts: PackedStringArray = entry.strip_edges().split("@")
		var id: StringName = StringName(parts[0])
		var step: Dictionary = {}
		for existing: Dictionary in plan:
			if existing["type"] == id:
				step = existing
		if step.is_empty():
			var no_views: Array[String] = []
			step = {"type": id, "views": no_views}
			plan.append(step)
		(step["views"] as Array[String]).append(
			parts[1] if parts.size() > 1 else Views.DEFAULT_VIEW
		)
	return plan


func _selected_types() -> Array[StringName]:
	var wanted: String = str(_args.get("type", "all"))
	if wanted == "all":
		return TYPES
	var one: Array[StringName] = [StringName(wanted)]
	return one


func _selected_views() -> Array[String]:
	var wanted: String = str(_args.get("views", ""))
	if wanted.is_empty():
		return Views.all_names()
	var names: Array[String] = []
	for entry: String in wanted.split(","):
		names.append(entry.strip_edges())
	return names


func _measure_view(id: StringName, view_name: String, block: int, pairs: int) -> Dictionary:
	var visible_gpu: PackedFloat32Array = PackedFloat32Array()
	var hidden_gpu: PackedFloat32Array = PackedFloat32Array()
	var visible_cpu: PackedFloat32Array = PackedFloat32Array()
	var hidden_cpu: PackedFloat32Array = PackedFloat32Array()
	var deltas: PackedFloat32Array = PackedFloat32Array()
	var stable: bool = false
	for attempt: int in MAX_REPEATS + 1:
		deltas = PackedFloat32Array()
		for _pair: int in pairs:
			var on_gpu: PackedFloat32Array = PackedFloat32Array()
			var off_gpu: PackedFloat32Array = PackedFloat32Array()
			_bed.visible = true
			await _frames(block, on_gpu, visible_cpu)
			_bed.visible = false
			await _frames(block, off_gpu, hidden_cpu)
			deltas.append(_median(on_gpu) - _median(off_gpu))
			visible_gpu.append_array(on_gpu)
			hidden_gpu.append_array(off_gpu)
		var spread: float = _median_spread(deltas)
		stable = spread <= PAIR_AGREEMENT_MS
		if stable or attempt == MAX_REPEATS:
			break
	_bed.visible = true
	await process_frame
	await RenderingServer.frame_post_draw
	var with_bed: float = _info(RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	var draws_with: float = _info(RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	_bed.visible = false
	await process_frame
	await RenderingServer.frame_post_draw
	var without_bed: float = _info(RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	var draws_without: float = _info(RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	_bed.visible = true
	var added: float = _median(visible_gpu) - _median(hidden_gpu)
	var primitives: float = with_bed - without_bed
	var view: Node3D = _bed.call("get_shown_view") as Node3D
	var estimate: int = int(view.call("get_drawn_triangle_estimate", _camera))
	var row: Dictionary = {
		"tank": String(_tank_id),
		"type": String(id),
		"view": view_name,
		"added_ms": added,
		"estimate_x_factor_ms": added * FACTOR,
		"gpu_visible_ms": _median(visible_gpu),
		"gpu_hidden_ms": _median(hidden_gpu),
		"pair_deltas_ms": Array(deltas),
		"stable": stable,
		"cpu_added_ms": _median(visible_cpu) - _median(hidden_cpu),
		"primitives": primitives,
		"estimate_triangles": estimate,
		"draw_calls_added": draws_with - draws_without,
		"multimesh_nodes": int(view.call("get_multimesh_node_count")),
		"unique_stones": int(view.call("get_unique_stone_count")),
		"memory_bytes": int(view.call("get_memory_bytes")),
	}
	var label: String = "%s %s %s" % [_tank_id, id, view_name]
	_check("%s added GPU ms" % label, added, "<= %.2f" % LIMIT_ADDED_MS, added <= LIMIT_ADDED_MS)
	_check(
		"%s added x %d ms (mid-range estimate)" % [label, int(FACTOR)],
		added * FACTOR,
		"<= %.2f" % LIMIT_ADDED_MS,
		added * FACTOR <= LIMIT_ADDED_MS
	)
	var limit: float = (
		LIMIT_DEFAULT_PRIMITIVES if view_name == Views.DEFAULT_VIEW else LIMIT_CLOSE_UP_PRIMITIVES
	)
	_check("%s primitives" % label, primitives, "<= %d" % int(limit), primitives <= limit)
	_check(
		"%s estimate against primitives" % label,
		float(estimate),
		">= %d" % int(primitives * (1.0 - ESTIMATE_SHORTFALL)),
		float(estimate) >= primitives * (1.0 - ESTIMATE_SHORTFALL)
	)
	_check("%s pairs agree" % label, _median_spread(deltas), "<= 0.02 ms", stable)
	return row


## The spread (max - min) of the per-pair added times.
func _median_spread(deltas: PackedFloat32Array) -> float:
	if deltas.is_empty():
		return 0.0
	var low: float = deltas[0]
	var high: float = deltas[0]
	for value: float in deltas:
		low = minf(low, value)
		high = maxf(high, value)
	return high - low


# --- hitch ---


func _measure_hitch() -> void:
	var changes: Array[Dictionary] = []
	var longest_frames: PackedFloat32Array = PackedFloat32Array()
	for round_index: int in 2:
		for id: StringName in TYPES:
			var cached: bool = round_index == 1
			var change: Dictionary = await _timed_change(
				func() -> void:
					_model.apply_set_substrate(id, _substrates.get_definition(id).default_colour),
				id
			)
			change["kind"] = "type"
			change["type"] = String(id)
			change["cached"] = cached
			changes.append(change)
			var label: String = "type %s%s" % [id, " (cached)" if cached else ""]
			if not cached:
				longest_frames.append(float(change["longest_frame_ms"]))
			else:
				_check(
					"%s swapped within one frame" % label,
					float(change["swap_ms"]),
					"<= %.0f ms" % LIMIT_FRAME_MS,
					float(change["swap_ms"]) <= LIMIT_FRAME_MS
				)
			_check_change(label, change)
	for tank_id: StringName in TANKS:
		var change: Dictionary = await _timed_change(
			func() -> void: _model.apply_set_tank_id(tank_id), _model.get_substrate_id()
		)
		change["kind"] = "tank"
		change["tank"] = String(tank_id)
		changes.append(change)
		_check_change("tank %s" % tank_id, change)
	_result["changes"] = changes
	_check(
		"median of the longest frames over the type changes",
		_median(longest_frames),
		"<= %.0f ms" % LIMIT_FRAME_MS,
		_median(longest_frames) <= LIMIT_FRAME_MS
	)


func _check_change(label: String, change: Dictionary) -> void:
	_check(
		"%s swap time" % label,
		float(change["swap_ms"]),
		"<= %.0f ms" % LIMIT_SWAP_MS,
		float(change["swap_ms"]) <= LIMIT_SWAP_MS
	)
	_check(
		"%s main-thread us per frame" % label,
		float(change["max_main_usec"]),
		"<= %d" % LIMIT_MAIN_USEC,
		int(change["max_main_usec"]) <= LIMIT_MAIN_USEC
	)
	_check(
		"%s LOD update us" % label,
		float(change["max_lod_usec"]),
		"<= %d" % LIMIT_LOD_USEC,
		int(change["max_lod_usec"]) <= LIMIT_LOD_USEC
	)


## Runs `action`, then frames until the bed shows `wanted_id` (bed_swapped, or shown and not
## building); at least the frame of the action is measured. Returns the time to the swap, the
## longest frame in between and the main-thread microseconds of the bed. A tank change replaces the
## tank and its bed inside the action: both are re-bound at once, and the new bed's frame stats
## are reset after the microseconds of its show_type (spent inside the action) are read; those are
## added to the first frame, so the maximum keeps them.
func _timed_change(action: Callable, wanted_id: StringName) -> Dictionary:
	_rebind()
	_bed.call("reset_frame_stats")
	var swapped: Array[bool] = [false]
	var handler: Callable = func(_swapped_id: StringName) -> void: swapped[0] = true
	var old_tank: Node3D = _tank
	var started: int = Time.get_ticks_usec()
	action.call()
	var carried_usec: int = 0
	var replaced: bool = _room.get_node_or_null("Tank") != old_tank
	if replaced:
		_rebind()
		carried_usec = int(_bed.call("get_max_frame_main_usec"))
		_bed.call("reset_frame_stats")
	_bed.connect(&"bed_swapped", handler)
	var swap_usec: int = -1
	if _already_shown(wanted_id):
		swap_usec = Time.get_ticks_usec() - started
	var longest: float = 0.0
	var max_lod: int = 0
	var first_frame_usec: int = -1
	var last: int = started
	while Time.get_ticks_usec() - started < 10000000:
		await process_frame
		var now: int = Time.get_ticks_usec()
		longest = maxf(longest, float(now - last) / 1000.0)
		last = now
		max_lod = maxi(max_lod, int(_bed.call("get_last_lod_usec")))
		if first_frame_usec < 0:
			first_frame_usec = int(_bed.call("get_last_frame_main_usec"))
		if swap_usec < 0 and (swapped[0] or _already_shown(wanted_id)):
			swap_usec = now - started
		if swap_usec >= 0:
			break
	if swap_usec < 0:
		swap_usec = Time.get_ticks_usec() - started
	var main_usec: int = maxi(
		int(_bed.call("get_max_frame_main_usec")), carried_usec + maxi(0, first_frame_usec)
	)
	_bed.disconnect(&"bed_swapped", handler)
	await _settle()
	return {
		"swap_ms": float(swap_usec) / 1000.0,
		"longest_frame_ms": longest,
		"max_main_usec": main_usec,
		"show_type_usec_in_action": carried_usec,
		"tank_replaced": replaced,
		"max_lod_usec": max_lod,
	}


func _already_shown(wanted_id: StringName) -> bool:
	return _bed.call("get_shown_id") == wanted_id and not bool(_bed.call("is_building"))


# --- orbit ---


func _measure_orbit(wanted_tank: String) -> void:
	var tanks: Array[StringName] = TANKS
	if wanted_tank != "all":
		tanks = [StringName(wanted_tank)]
	var rows: Array[Dictionary] = []
	var everything: PackedFloat32Array = PackedFloat32Array()
	for tank_id: StringName in tanks:
		await _switch_tank(tank_id)
		for id: StringName in _selected_types():
			await _show_type(id)
			_place_pose(Views.default_view(_tank_id))
			await _settle()
			for frames_per_leg: int in ORBIT_FRAMES:
				var samples: PackedFloat32Array = await _orbit_pass(id, frames_per_leg)
				everything.append_array(samples)
				var row: Dictionary = _lod_stats(samples)
				row["tank"] = String(tank_id)
				row["type"] = String(id)
				row["frames_per_leg"] = frames_per_leg
				rows.append(row)
				_check(
					"orbit %s %s %d frames per leg max LOD us" % [tank_id, id, frames_per_leg],
					float(row["max_usec"]),
					"<= %d" % LIMIT_LOD_USEC,
					float(row["max_usec"]) <= float(LIMIT_LOD_USEC)
				)
	_result["orbit"] = rows
	var overall: Dictionary = _lod_stats(everything)
	_result["orbit_overall"] = overall
	print(
		(
			"[#28 measure] orbit overall: %d frames, max %d us, p99 %d, p95 %d, median %d, %d > %d us"
			% [
				int(overall["frames"]),
				int(overall["max_usec"]),
				int(overall["p99_usec"]),
				int(overall["p95_usec"]),
				int(overall["median_usec"]),
				int(overall["frames_over_limit"]),
				LIMIT_LOD_USEC
			]
		)
	)


func _switch_tank(tank_id: StringName) -> void:
	_tank_id = tank_id
	if _model.get_tank_id() != tank_id:
		_model.apply_set_tank_id(tank_id)
	_rebind()
	_bed.call("finish_pending")
	await _settle()


## One pass of the path with `frames_per_leg` frames per leg: linear legs through the default
## camera, the eight close-ups and back, then the arc legs. Returns the LOD microseconds of every
## frame (read after the frame that used the pose).
func _orbit_pass(id: StringName, frames_per_leg: int) -> PackedFloat32Array:
	var samples: PackedFloat32Array = PackedFloat32Array()
	var stops: Array[Dictionary] = []
	for view_name: String in Views.all_names():
		stops.append(Views.pose_of(view_name, _tank_id, Api.fill_depth(id)))
	stops.append(Views.default_view(_tank_id))
	for leg: int in stops.size() - 1:
		var from: Dictionary = stops[leg]
		var to: Dictionary = stops[leg + 1]
		for frame: int in range(1, frames_per_leg + 1):
			var t: float = float(frame) / float(frames_per_leg)
			_place_pose(
				{
					"position": (from["position"] as Vector3).lerp(to["position"], t),
					"target": (from["target"] as Vector3).lerp(to["target"], t),
				}
			)
			await process_frame
			samples.append(float(_bed.call("get_last_lod_usec")))
	var default_pose: Dictionary = Views.default_view(_tank_id)
	var pivot: Vector3 = default_pose["target"]
	var distance: float = ((default_pose["position"] as Vector3) - pivot).length()
	for leg: int in ORBIT_ARC.size() - 1:
		for frame: int in range(1, frames_per_leg + 1):
			var t: float = float(frame) / float(frames_per_leg)
			var arc: Vector3 = ORBIT_ARC[leg].lerp(ORBIT_ARC[leg + 1], t)
			_place_pose(_arc_pose(pivot, distance, arc))
			await process_frame
			samples.append(float(_bed.call("get_last_lod_usec")))
	return samples


## A camera on the sphere around the pivot: arc = (yaw, elevation in degrees, radius share).
func _arc_pose(pivot: Vector3, distance: float, arc: Vector3) -> Dictionary:
	var yaw: float = deg_to_rad(arc.x)
	var elevation: float = deg_to_rad(arc.y)
	var direction: Vector3 = Vector3(
		sin(yaw) * cos(elevation), sin(elevation), cos(yaw) * cos(elevation)
	)
	return {"position": pivot + direction * distance * arc.z, "target": pivot}


func _lod_stats(samples: PackedFloat32Array) -> Dictionary:
	var over: int = 0
	var high: float = 0.0
	for value: float in samples:
		high = maxf(high, value)
		if value > float(LIMIT_LOD_USEC):
			over += 1
	return {
		"frames": samples.size(),
		"max_usec": high,
		"p99_usec": _percentile(samples, 0.99),
		"p95_usec": _percentile(samples, 0.95),
		"median_usec": _median(samples),
		"frames_over_limit": over,
	}


# --- colour ---


func _measure_colour() -> void:
	await _show_type(&"sand_black")
	var rows: Array[Dictionary] = []
	for view_name: String in [Views.DEFAULT_VIEW, "top_35"]:
		_place_view(view_name, &"sand_black")
		_bed.visible = true
		await _settle()
		var with_bed: Image = root.get_texture().get_image()
		_bed.visible = false
		await _settle()
		var without_bed: Image = root.get_texture().get_image()
		_bed.visible = true
		with_bed.save_png(_out_dir.path_join("sand_black_%s_bed.png" % view_name))
		without_bed.save_png(_out_dir.path_join("sand_black_%s_no_bed.png" % view_name))
		var masks: Dictionary = _masked_means(with_bed, without_bed)
		var mask_path: String = _out_dir.path_join("sand_black_%s_mask.png" % view_name)
		(masks["mask"] as Image).save_png(mask_path)
		var low_mean: Color = masks["mean_low"]
		var high_mean: Color = masks["mean_high"]
		var high: float = maxf(low_mean.r, maxf(low_mean.g, low_mean.b))
		var low: float = minf(low_mean.r, minf(low_mean.g, low_mean.b))
		var chroma: float = (high - low) / high if high > 0.0 else 0.0
		var difference: float = maxf(
			absf(low_mean.r - high_mean.r),
			maxf(absf(low_mean.g - high_mean.g), absf(low_mean.b - high_mean.b))
		)
		(
			rows
			. append(
				{
					"view": view_name,
					"mean": [low_mean.r, low_mean.g, low_mean.b],
					"chroma": chroma,
					"max": high,
					"mask_threshold": MASK_EPSILON,
					"mask_pixels": int(masks["count_low"]),
					"mean_at_0_03": [high_mean.r, high_mean.g, high_mean.b],
					"chroma_at_0_03": _chroma(high_mean),
					"mask_pixels_at_0_03": int(masks["count_high"]),
					"threshold_difference": difference,
					"mask_png": mask_path,
				}
			)
		)
		print(
			(
				"[#28 measure] sand_black %s: mask %d px at 2/255 mean %s, %d px at 0.03 mean %s"
				% [
					view_name,
					int(masks["count_low"]),
					low_mean,
					int(masks["count_high"]),
					high_mean
				]
			)
		)
		_check(
			"sand_black %s mask thresholds 2/255 and 0.03 agree per channel" % view_name,
			difference,
			"<= %.2f" % MASK_AGREEMENT,
			difference <= MASK_AGREEMENT
		)
		_check(
			"sand_black %s chroma" % view_name,
			chroma,
			"<= %.2f" % LIMIT_CHROMA,
			chroma <= LIMIT_CHROMA
		)
		_check(
			"sand_black %s max channel" % view_name,
			high,
			"<= %.2f" % LIMIT_MAX_CHANNEL,
			high <= LIMIT_MAX_CHANNEL
		)
	_result["colour"] = rows


func _chroma(colour: Color) -> float:
	var high: float = maxf(colour.r, maxf(colour.g, colour.b))
	var low: float = minf(colour.r, minf(colour.g, colour.b))
	return (high - low) / high if high > 0.0 else 0.0


## The mean colour (sRGB, as the screenshot shows it) of the pixels where the two images differ by
## more than 2/255 and by more than 0.03 (sum of the channel differences), the pixel counts, and
## the 2/255 mask as a white-on-black image.
func _masked_means(with_bed: Image, without_bed: Image) -> Dictionary:
	var width: int = with_bed.get_width()
	var height: int = with_bed.get_height()
	var mask: Image = Image.create_empty(width, height, false, Image.FORMAT_L8)
	var total_low: Color = Color(0, 0, 0, 0)
	var total_high: Color = Color(0, 0, 0, 0)
	var count_low: int = 0
	var count_high: int = 0
	for y: int in height:
		for x: int in width:
			var a: Color = with_bed.get_pixel(x, y)
			var b: Color = without_bed.get_pixel(x, y)
			var change: float = absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			if change > MASK_EPSILON:
				total_low += a
				count_low += 1
				mask.set_pixel(x, y, Color.WHITE)
				if change > MASK_EPSILON_HIGH:
					total_high += a
					count_high += 1
	return {
		"mask": mask,
		"count_low": count_low,
		"count_high": count_high,
		"mean_low": _mean(total_low, count_low),
		"mean_high": _mean(total_high, count_high),
	}


func _mean(total: Color, count: int) -> Color:
	if count == 0:
		return Color(0, 0, 0, 1)
	return Color(total.r / count, total.g / count, total.b / count, 1.0)
