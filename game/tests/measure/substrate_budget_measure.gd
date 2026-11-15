# gdlint: disable=max-file-lines
extends SceneTree
## Measuring script for #28, the real 3D substrate bed (owner: tester; the technical-artist runs it
## after the art work and the tester repeats it after the developer). Not a test suite: GdUnit does
## not pick it up, and it needs the real renderer and a GPU (no --headless). It measures AC 34 and
## AC 41 of technical plan v3 (section 7 and the F = 3 amendment) in the main scene, large tank,
## 1920 x 1080, vsync off, TAA (the project default), with the stand-in D18 load of plan 1.2.
## Relative --out paths are relative to the repository root.
##
##   godot_console --path game -s res://tests/measure/substrate_budget_measure.gd -- \
##       --mode=gpu --type=all --out=.claude/state/previews/28/
##
## Options (all after the lone "--"):
##   --mode=gpu|hitch|colour   what to measure (default gpu)
##   --type=<id>|all           substrate type(s) (default all; colour mode always sand_black)
##   --views=<a,b,...>         gpu mode: only these views (default: the default camera and the
##                             eight close-ups of tests/helpers/substrate_views.gd)
##   --out=<dir>               output directory (default .claude/state/previews/28/)
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
##   calls, MultiMesh nodes, memory of the view.
## hitch: a new session (caches empty), ten type changes (the five types twice) and three tank
##   changes; per change the longest frame, the time to bed_swapped and the main-thread
##   microseconds of the bed. Checks: median of the longest frames <= 33 ms; every change within
##   2 s and a type already built in the tank within one frame (33 ms); main-thread assembly and
##   instancing <= 4,000 us per frame; LOD update <= 500 us.
## colour: sand_black at its default swatch under the warm lamp, at the default camera and at the
##   35 cm view from above; the mean colour of the pixels the bed adds (a second render with the
##   bed hidden gives the mask): chroma (max - min) / max <= 0.20 and the maximum channel <= 0.25.
##
## Output: substrate_<mode>.json (GPU name, driver, every number, a "checks" list with the limit and
## the result of each) and PNGs in colour mode. The exit code is 1 when a check fails.

const Views := preload("res://tests/helpers/substrate_views.gd")
const Api := preload("res://tests/helpers/substrate_bed_api.gd")
const Table := preload("res://tests/helpers/tank_table.gd")

const WIDTH := 1920
const HEIGHT := 1080
const MAIN_SCENE := "res://scenes/main.tscn"
const LARGE: StringName = &"tank_large_1"
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
## Stand-in D18 load (technical plan 1.2).
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
	if not mode in ["gpu", "hitch", "colour"]:
		push_error("unknown --mode=%s" % mode)
		quit(2)
		return
	_result = {
		"mode": mode,
		"gpu": RenderingServer.get_video_adapter_name(),
		"vendor": RenderingServer.get_video_adapter_vendor(),
		"driver": RenderingServer.get_video_adapter_api_version(),
		"godot": Engine.get_version_info().get("string", ""),
		"os": OS.get_name(),
		"resolution": [WIDTH, HEIGHT],
		"factor": FACTOR,
	}
	await _setup(mode)
	match mode:
		"gpu":
			await _measure_gpu()
		"hitch":
			await _measure_hitch()
		"colour":
			await _measure_colour()
	var failed: int = 0
	for entry: Dictionary in _checks:
		if entry["pass"] == false:
			failed += 1
	_result["checks"] = _checks
	_result["failed_checks"] = failed
	var path: String = _out_dir.path_join("substrate_%s.json" % mode)
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


func _check(label: String, value: float, limit_text: String, passed: bool) -> void:
	_checks.append({"check": label, "value": value, "limit": limit_text, "pass": passed})
	print(
		"[#28 measure] %s %s: %.4f (%s)" % ["ok  " if passed else "FAIL", label, value, limit_text]
	)


# --- scene setup ---


func _setup(mode: String) -> void:
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
	_model.apply_set_tank_id(LARGE)
	await _settle()
	_bind_nodes()
	if mode != "hitch":
		_add_stand_in_load()
	_camera.process_mode = Node.PROCESS_MODE_DISABLED
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.fov = Views.FOV_DEG
	_camera.near = Views.NEAR_M


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
	_tank = _room.get_node("Tank") as Node3D
	_bed = _tank.get_node_or_null("SubstrateAnchor/Substrate") as Node3D
	if _bed == null:
		push_error("Tank/SubstrateAnchor/Substrate is missing")
		quit(2)


func _settle() -> void:
	for _i: int in SETTLE_FRAMES:
		await process_frame
	await RenderingServer.frame_post_draw


## 60 static proof fish and 100 static sphere stand-ins in the large tank (technical plan 1.2).
func _add_stand_in_load() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = LOAD_SEED
	var interior: Vector3 = Table.interior(LARGE)
	var fish_scene: PackedScene = load(FISH_PATH) as PackedScene
	var load_root: Node3D = Node3D.new()
	load_root.name = "StandInLoad"
	_tank.add_child(load_root)
	for _i: int in FISH_COUNT:
		var fish: Node3D = fish_scene.instantiate() as Node3D
		fish.scale = Vector3.ONE * FISH_LENGTH_M
		fish.position = Vector3(
			rng.randf_range(-(interior.x / 2.0 - 0.06), interior.x / 2.0 - 0.06),
			rng.randf_range(0.12, 0.45),
			rng.randf_range(-(interior.z / 2.0 - 0.05), interior.z / 2.0 - 0.05)
		)
		fish.rotation.y = rng.randf_range(0.0, TAU)
		load_root.add_child(fish)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.55, 0.5, 0.45)
	var surface: float = float(Api.fill_depth(_model.get_substrate_id()))
	for _i: int in DECOR_COUNT:
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
	var pose: Dictionary = Views.pose_of(view_name, LARGE, Api.fill_depth(id))
	_camera.global_transform = _tank.global_transform * Views.transform_of(pose)


# --- statistics ---


func _median(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted: PackedFloat32Array = values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


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
	var ids: Array[StringName] = _selected_types()
	var view_names: Array[String] = _selected_views()
	var rows: Array[Dictionary] = []
	for id: StringName in ids:
		await _show_type(id)
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
	var label: String = "%s %s" % [id, view_name]
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
	for tank_id: StringName in [&"tank_small_1", &"tank_medium_1", LARGE]:
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


## Runs `action`, then frames until the bed shows `wanted_id` again (bed_swapped); returns the time
## to the swap, the longest frame in between and the main-thread microseconds of the bed.
func _timed_change(action: Callable, wanted_id: StringName) -> Dictionary:
	_bed = _tank.get_node_or_null("SubstrateAnchor/Substrate") as Node3D
	_bed.call("reset_frame_stats")
	var swapped: Array[bool] = [false]
	var handler: Callable = func(_swapped_id: StringName) -> void: swapped[0] = true
	var started: int = Time.get_ticks_usec()
	action.call()
	_bed = _tank.get_node_or_null("SubstrateAnchor/Substrate") as Node3D
	_bed.connect(&"bed_swapped", handler)
	var longest: float = 0.0
	var max_lod: int = 0
	var last: int = started
	while (
		not swapped[0]
		and not _already_shown(wanted_id)
		and Time.get_ticks_usec() - started < 10000000
	):
		await process_frame
		var now: int = Time.get_ticks_usec()
		longest = maxf(longest, float(now - last) / 1000.0)
		last = now
		max_lod = maxi(max_lod, int(_bed.call("get_last_lod_usec")))
	var swap_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
	var main_usec: int = int(_bed.call("get_max_frame_main_usec"))
	_bed.disconnect(&"bed_swapped", handler)
	await _settle()
	return {
		"swap_ms": swap_ms,
		"longest_frame_ms": longest,
		"max_main_usec": main_usec,
		"max_lod_usec": max_lod,
	}


func _already_shown(wanted_id: StringName) -> bool:
	return _bed.call("get_shown_id") == wanted_id and not bool(_bed.call("is_building"))


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
		var mean: Color = _mean_of_difference(with_bed, without_bed)
		var high: float = maxf(mean.r, maxf(mean.g, mean.b))
		var low: float = minf(mean.r, minf(mean.g, mean.b))
		var chroma: float = (high - low) / high if high > 0.0 else 0.0
		rows.append(
			{"view": view_name, "mean": [mean.r, mean.g, mean.b], "chroma": chroma, "max": high}
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


## The mean colour (sRGB, as the screenshot shows it) of the pixels where the two images differ.
func _mean_of_difference(with_bed: Image, without_bed: Image) -> Color:
	var total: Color = Color(0, 0, 0, 0)
	var count: int = 0
	for y: int in with_bed.get_height():
		for x: int in with_bed.get_width():
			var a: Color = with_bed.get_pixel(x, y)
			var b: Color = without_bed.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > MASK_EPSILON:
				total += a
				count += 1
	if count == 0:
		return Color(0, 0, 0, 1)
	return Color(total.r / count, total.g / count, total.b / count, 1.0)
