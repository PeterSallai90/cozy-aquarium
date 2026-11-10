# gdlint: disable=max-file-lines
extends SceneTree
## Measuring script for #129, the glass corner seam (owner: tester). Not a test suite: GdUnit does
## not pick it up. It needs the real renderer (no --headless). Relative --out paths are relative to
## the repository root. Same capture method as water_glint_measure.gd (#128): 1920x1080
## SubViewport with use_hdr_2d, a runtime Environment with glow off and the linear tonemapper,
## ripple frozen on a runtime copy of the surface material, Rec. 709 luminance, the first frame
## discarded while the volumetric fog settles.
##
##   godot_console --path game -s res://tests/measure/glass_seam_measure.gd -- \
##       --size=medium --pose=corner --tag=after --out=.claude/state/previews/129/
##
## Options (all after the lone "--"):
##   --size=small|medium|large        tank (default medium)
##   --pose=front|corner|corner_left  front = the room's default camera; corner = fov 40, keep
##                                    height, camera 49 mm inside the right inner wall, 100 mm in
##                                    front of the front glass, mid water height, 10.4 degrees yaw,
##                                    placed relative to the tank's own corner; corner_left = the
##                                    same mirrored in x and yaw (default front)
##   --variant=default|edge_zero|edge_max   glass_edge_opacity and glass_edge_brightness on a
##                                    runtime material copy: stored values, 0 and 0, 1 and 1
##   --tag=before|after               file name prefix. "before" only reports (exit 0); "after"
##                                    also compares with the before files and exits 1 on a failure
##   --out=<dir>                      output directory (default .claude/state/previews/129/)
##   --before=<dir>                   where the before_* files are read from (default: --out)
##   --shader=<file>                  use this shader text file for the glass instead of the stored
##                                    one, to try a candidate without editing the project
##
## Output per run: <tag>_<size>_<pose>[_<variant>].json (all numbers, one "checks" list with the
## limit and the result of each), .exr (default variant only), .png (tonemapped, as the player
## sees it) and PNG crops (x4) of the front corner and of the back corners seen through the water.
## A "checks" entry with "pass": null is information only (no limit, or no before file yet).
##
## Limits (the issue's acceptance criteria, owner decisions on #129):
##   AC1/AC2/AC8 dip <= 3% of the mean of the water side and the band side (12 px water side,
##     horizontal profile at 25/50/75% water height, mirrored so the water is always on the left)
##   AC3 core: the strongest 2 px running mean inside the band, minus 1 px at each edge, is at most
##     5% above the band mean
##   AC5 band width (half-step crossings) <= projected corner column + 1 px in every
##     pose (owner decision on #129: no fixed front or medium corner cap)
##   AC4a outside the 4 projected vertical corner columns (dilated 2 px): per pixel at most 0.0004
##     linear luminance change against before, at most 0.05% of the pixels above it. This also
##     covers "meniscus and underside unchanged" (AC9)
##   AC4b no new 1-2 px line (against before) that differs by more than 3% in luminance or in green
##     ratio G / ((R + B) / 2) from both sides (pixels 3-6 px away), on profiles across the floor
##     inner edges, the back corners (interior side), the water line and the glass top
##   AC4c the bottom-front green line is at most 0.25 px wider than before
##   AC7 render part: edge_zero gives a monotonic step water -> room (largest reverse excursion at
##     most 3% of the mean of both levels); edge_max renders finite pixels. A shader error shows in
##     the run log, not here: the caller greps the log for "SHADER ERROR"
##   AC9 no worse than before: face-on glass background change (glass on against glass hidden),
##     large strip contrast, interior mean within 5% and still the brightest. Noise allowance 0.0004
##     linear luminance (the AC4a bound; two identical frames differ by at most 0.00012), 0.005 in
##     contrast ratio. The #128 glint limits come from water_glint_measure.gd (see the issue).

const WIDTH := 1920
const HEIGHT := 1080
const ROOM_SCENE := "res://scenes/room/room_corner.tscn"
const SETTLE_FRAMES := 8
const LUMA := Vector3(0.2126, 0.7152, 0.0722)

const DIP_LIMIT := 0.03
const CORE_LIMIT := 0.05
const WATER_SIDE_PX := 12.0
const UNCHANGED_LIMIT := 0.0004
const UNCHANGED_SHARE_LIMIT := 0.0005
const MASK_DILATE_PX := 2.0
const LINE_LIMIT := 0.03
const LINE_MATCH_PX := 2.0
const LINE_REACH_PX := 14
const WIDTH_NOISE_PX := 0.25
const CONTRAST_NOISE := 0.005
const INTERIOR_TOLERANCE := 0.05
const EXCURSION_LIMIT := 0.03
const FRACTIONS: Array[float] = [0.25, 0.5, 0.75]
## Corner close-up pose, relative to the front-right inner corner of the tank (tank-local metres).
## Reconstructed from medium_front_corner_closeup.png (#23): the front inner corner lands at screen
## x 1110 and the back inner corner at x 870 on the medium tank; 5 mm reads as 35 px. Small and
## large use the same camera offsets relative to their own corner.
const CORNER_FOV_DEG := 40.0
const CORNER_TARGET_FRONT_X := 1110.0
const CORNER_TARGET_BACK_X := 870.0
const CORNER_BAND_PX := 35.0
const CORNER_REF_GLASS_M := 0.005
const CORNER_REF_DEPTH_M := 0.3

var _args: Dictionary = {}
var _size_name: String = "medium"
var _pose: String = "front"
var _variant: String = "default"
var _tag: String = "run"
var _out_dir: String = ""
var _before_dir: String = ""
var _viewport: SubViewport = null
var _room: Node3D = null
var _camera: Camera3D = null
var _environment: Environment = null
var _tank: Node3D = null
var _definition: TankDefinition = null
var _surface_material: ShaderMaterial = null
var _glass: MeshInstance3D = null
var _glass_material: ShaderMaterial = null
var _base_size: Vector3 = Vector3.ZERO
var _g: float = 0.0
var _hx: float = 0.0
var _hz: float = 0.0
var _front_transform: Transform3D = Transform3D.IDENTITY
var _checks: Array[Dictionary] = []


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--"):
			var parts: PackedStringArray = argument.substr(2).split("=", true, 1)
			_args[parts[0]] = parts[1] if parts.size() > 1 else "true"
	_size_name = str(_args.get("size", "medium"))
	_pose = str(_args.get("pose", "front"))
	_variant = str(_args.get("variant", "default"))
	_tag = str(_args.get("tag", "run"))
	_out_dir = _absolute(str(_args.get("out", ".claude/state/previews/129/")))
	_before_dir = _absolute(str(_args.get("before", _out_dir)))
	DirAccess.make_dir_recursive_absolute(_out_dir)
	_run()


func _absolute(path: String) -> String:
	if path.is_absolute_path():
		return path
	## Relative paths are relative to the repository root, the parent of the project folder.
	return ProjectSettings.globalize_path("res://").path_join("..").path_join(path).simplify_path()


func _name(suffix: String) -> String:
	var variant: String = "" if _variant == "default" else "_" + _variant
	return "%s_%s_%s%s%s" % [_tag, _size_name, _pose, variant, suffix]


func _run() -> void:
	if not _pose in ["front", "corner", "corner_left"]:
		push_error("unknown --pose=%s" % _pose)
		quit(2)
		return
	await _setup()
	_place_pose()
	_apply_variant()
	await _capture_hdr()
	var image: Image = await _capture_hdr()
	if image == null:
		quit(2)
		return
	var px: PackedFloat32Array = _rgba(image)
	var result: Dictionary = {"tag": _tag, "size": _size_name, "pose": _pose, "variant": _variant}
	result["resolution"] = [WIDTH, HEIGHT]
	result["pose_constants"] = _pose_constants()
	result["finite"] = _all_finite(px)
	_check("AC7", "all pixels finite", 1.0 if result["finite"] else 0.0, "== 1", result["finite"])
	var corners: Array[Dictionary] = []
	for entry: Dictionary in _corner_list():
		for fraction: float in FRACTIONS:
			var metrics: Dictionary = _corner_metrics(px, float(entry["sgn"]), fraction)
			metrics["label"] = entry["label"]
			metrics["fraction"] = fraction
			corners.append(metrics)
	result["corners"] = corners
	match _variant:
		"default":
			_gate_corners(corners)
			image.save_exr(_out_dir.path_join(_name(".exr")))
			await _default_checks(result, px)
		"edge_zero":
			_gate_monotonic(corners)
	var png: Image = await _save_png(_out_dir.path_join(_name(".png")))
	if _variant == "default":
		_save_crops(png)
	result["checks"] = _checks
	var failed: int = 0
	for entry: Dictionary in _checks:
		if entry["pass"] == false:
			failed += 1
	result["failed_checks"] = failed
	var file: FileAccess = FileAccess.open(_out_dir.path_join(_name(".json")), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	_print_summary(corners, failed)
	quit(1 if failed > 0 and _tag != "before" else 0)


# --- scene setup ---


func _setup() -> void:
	var catalog: TankCatalog = TankCatalog.load_dir()
	var tank_id: StringName = StringName("tank_%s_1" % _size_name)
	_definition = catalog.get_definition(tank_id)
	var model: AquariumModel = AquariumModel.new("2026-11-01T12:00:00Z")
	model.apply_set_tank_id(tank_id)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(WIDTH, HEIGHT)
	_viewport.use_hdr_2d = true
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_viewport.use_taa = false
	_viewport.use_debanding = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	_room = (load(ROOM_SCENE) as PackedScene).instantiate() as Node3D
	_room.call("setup", model, catalog)
	_viewport.add_child(_room)
	await _settle()
	_camera = _room.get_node("PlaceholderCamera") as Camera3D
	_tank = _room.get_node("Tank") as Node3D
	var surface: MeshInstance3D = _tank.get_node("WaterVolume/Surface") as MeshInstance3D
	_glass = _tank.get_node("Glass") as MeshInstance3D
	_environment = (_room.get_node("WorldEnvironment") as WorldEnvironment).environment
	_surface_material = (surface.material_override as ShaderMaterial).duplicate()
	surface.material_override = _surface_material
	_surface_material.set_shader_parameter("ripple_speed", 0.0)
	_glass_material = (_glass.get_surface_override_material(0) as ShaderMaterial).duplicate()
	_glass.set_surface_override_material(0, _glass_material)
	_base_size = _definition.get_water_volume_size_m()
	_g = _definition.glass_thickness_m
	_hx = _definition.interior_size_m.x / 2.0
	_hz = _definition.interior_size_m.z / 2.0
	_front_transform = _camera.transform


func _settle() -> void:
	for _i: int in SETTLE_FRAMES:
		await process_frame
	await RenderingServer.frame_post_draw


func _apply_variant() -> void:
	match _variant:
		"edge_zero":
			_set_edge(0.0)
		"edge_max":
			_set_edge(1.0)
		"default":
			pass
		_:
			push_error("unknown --variant=%s" % _variant)
			quit(2)
	if _args.has("shader"):
		## Try a candidate glass shader file without editing tank_glass.gdshader.
		var candidate: Shader = Shader.new()
		candidate.code = FileAccess.get_file_as_string(_absolute(str(_args["shader"])))
		_glass_material.shader = candidate


func _set_edge(value: float) -> void:
	_glass_material.set_shader_parameter("glass_edge_opacity", value)
	_glass_material.set_shader_parameter("glass_edge_brightness", value)


# --- capture ---


func _measure_mode(on: bool) -> void:
	_viewport.use_hdr_2d = on
	_environment.glow_enabled = not on
	_environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR if on else _stored_tonemap()
	_environment.tonemap_exposure = 1.0


func _stored_tonemap() -> Environment.ToneMapper:
	var stored: Environment = load("res://scenes/room/room_environment.tres") as Environment
	return stored.tonemap_mode if stored != null else Environment.TONE_MAPPER_AGX


func _capture_hdr() -> Image:
	_measure_mode(true)
	await _settle()
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = _viewport.get_texture().get_image()
	if not image.get_format() in [Image.FORMAT_RGBAH, Image.FORMAT_RGBH, Image.FORMAT_RGBAF]:
		push_error("capture is not HDR: image format %d" % image.get_format())
		return null
	return image


func _save_png(path: String) -> Image:
	_measure_mode(false)
	await _settle()
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = _viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	image.save_png(path)
	_measure_mode(true)
	return image


## RGBA floats of an image (row-major, 4 per pixel).
func _rgba(image: Image) -> PackedFloat32Array:
	var copy: Image = image.duplicate() as Image
	copy.convert(Image.FORMAT_RGBAF)
	return copy.get_data().to_float32_array()


func _lum(px: PackedFloat32Array, x: int, y: int) -> float:
	if x < 0 or y < 0 or x >= WIDTH or y >= HEIGHT:
		return 0.0
	var i: int = (y * WIDTH + x) * 4
	return px[i] * LUMA.x + px[i + 1] * LUMA.y + px[i + 2] * LUMA.z


func _green_ratio(px: PackedFloat32Array, x: int, y: int) -> float:
	if x < 0 or y < 0 or x >= WIDTH or y >= HEIGHT:
		return 0.0
	var i: int = (y * WIDTH + x) * 4
	return px[i + 1] / maxf((px[i] + px[i + 2]) / 2.0, 1e-6)


func _all_finite(px: PackedFloat32Array) -> bool:
	for i: int in range(0, px.size(), 4):
		if is_nan(px[i + 1]) or is_inf(px[i + 1]) or is_nan(px[i]) or is_inf(px[i]):
			return false
	return true


func _load_before() -> PackedFloat32Array:
	if _tag == "before":
		return PackedFloat32Array()
	var path: String = _before_dir.path_join("before_%s_%s.exr" % [_size_name, _pose])
	if not FileAccess.file_exists(path):
		return PackedFloat32Array()
	var image: Image = Image.load_from_file(path)
	return _rgba(image) if image != null else PackedFloat32Array()


func _load_before_json() -> Dictionary:
	var path: String = _before_dir.path_join("before_%s_%s.json" % [_size_name, _pose])
	if _tag == "before" or not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


# --- poses ---


func _pose_constants() -> Dictionary:
	return {
		"camera_position": _v3(_camera.global_position),
		"camera_rotation_deg": _v3(_camera.rotation_degrees),
		"fov": _camera.fov,
		"keep_aspect": _camera.keep_aspect,
		"corner_fov_deg": CORNER_FOV_DEG,
		"corner_target_front_x": CORNER_TARGET_FRONT_X,
		"corner_target_back_x": CORNER_TARGET_BACK_X,
		"corner_band_px": CORNER_BAND_PX,
		"corner_reference_glass_m": CORNER_REF_GLASS_M,
		"corner_reference_depth_m": CORNER_REF_DEPTH_M,
		"glass_thickness_m": _g,
		"interior_size_m": _v3(_definition.interior_size_m),
		"water_size_m": _v3(_base_size),
	}


func _v3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _place_pose() -> void:
	if _pose == "front":
		_camera.transform = _front_transform
		return
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.fov = CORNER_FOV_DEG
	var focal: float = (HEIGHT / 2.0) / tan(deg_to_rad(CORNER_FOV_DEG / 2.0))
	var ahead: float = focal * CORNER_REF_GLASS_M / CORNER_BAND_PX
	var depth_back: float = ahead + CORNER_REF_GLASS_M + CORNER_REF_DEPTH_M
	var want: float = atan((CORNER_TARGET_FRONT_X - WIDTH / 2.0) / focal)
	var want_back: float = atan((CORNER_TARGET_BACK_X - WIDTH / 2.0) / focal)
	var low: float = 0.0
	var high: float = 1.0
	for _i: int in 60:
		var side: float = (low + high) / 2.0
		if atan(side / (ahead + CORNER_REF_GLASS_M)) - atan(side / depth_back) > want - want_back:
			high = side
		else:
			low = side
	var inset: float = (low + high) / 2.0
	var yaw: float = atan(inset / (ahead + CORNER_REF_GLASS_M)) - want
	var sign_x: float = 1.0 if _pose == "corner" else -1.0
	var local: Vector3 = Vector3(sign_x * (_hx - inset), _base_size.y / 2.0, _hz + _g + ahead)
	_camera.global_position = _tank.global_transform * local
	_camera.global_rotation = Vector3(0.0, -sign_x * yaw, 0.0)
	_camera.force_update_transform()


func _proj(local: Vector3) -> Vector2:
	return _camera.unproject_position(_tank.global_transform * local)


func _corner_list() -> Array[Dictionary]:
	match _pose:
		"front":
			return [{"sgn": 1.0, "label": "R"}, {"sgn": -1.0, "label": "L"}]
		"corner":
			return [{"sgn": 1.0, "label": "R"}]
	return [{"sgn": -1.0, "label": "L"}]


# --- the corner profile (AC1, AC2, AC3, AC5, AC8) ---


## Luminance of pixel k of the mirrored row: with `flip` the row is read right to left, so the
## water is always at the lower k. Pixel k covers t in [k, k + 1).
func _pix(px: PackedFloat32Array, row: int, flip: bool, k: int) -> float:
	return _lum(px, -k - 1 if flip else k, row)


func _mean_t(px: PackedFloat32Array, row: int, flip: bool, low: float, high: float) -> float:
	var first: int = ceili(low - 0.5)
	var last: int = floori(high - 0.5)
	if last < first:
		return NAN
	var total: float = 0.0
	for k: int in range(first, last + 1):
		total += _pix(px, row, flip, k)
	return total / float(last - first + 1)


## Position of the first crossing of `level` going from the low side towards `toward`, scanning
## k upwards (step +1) or downwards (step -1) from `start`; NAN when it never crosses.
func _crossing(
	px: PackedFloat32Array, row: int, flip: bool, start: int, stop: int, level: float, up: bool
) -> float:
	var step: int = 1 if stop >= start else -1
	var k: int = start
	while k != stop + step:
		var value: float = _pix(px, row, flip, k)
		var reached: bool = value >= level if up else value <= level
		if reached:
			var before_value: float = _pix(px, row, flip, k - step)
			var span: float = value - before_value
			var share: float = (level - before_value) / span if absf(span) > 1e-9 else 0.0
			return (float(k - step) + 0.5) + share * float(step)
		k += step
	return NAN


func _corner_metrics(px: PackedFloat32Array, sgn: float, fraction: float) -> Dictionary:
	var y: float = _base_size.y * fraction
	var inner: Vector2 = _proj(Vector3(sgn * _hx, y, _hz))
	var toward: Vector2 = _proj(Vector3(sgn * (_hx - 0.05), y, _hz))
	var flip: bool = toward.x > inner.x
	var row: int = clampi(floori(inner.y), 0, HEIGHT - 1)
	var sample: float = -1.0 if flip else 1.0
	var t_inner: float = inner.x * sample
	var front_a: float = _proj(Vector3(sgn * _hx, y, _hz + _g)).x * sample
	var front_b: float = _proj(Vector3(sgn * (_hx + _g), y, _hz + _g)).x * sample
	var column_low: float = INF
	var column_high: float = -INF
	for dx: float in [0.0, _g]:
		for dz: float in [0.0, _g]:
			var t: float = _proj(Vector3(sgn * (_hx + dx), y, _hz + dz)).x * sample
			column_low = minf(column_low, t)
			column_high = maxf(column_high, t)
	var result: Dictionary = {
		"row": row,
		"flip": flip,
		"inner_corner_px": snappedf(t_inner, 0.01),
		"projected_column_px": snappedf(column_high - column_low, 0.01),
	}
	if inner.x < 30.0 or inner.x > WIDTH - 30.0 or column_high + 16.0 > WIDTH:
		result["skipped"] = "corner off screen"
		return result
	var edge_low: float = minf(t_inner, column_low)
	var band_low: float = minf(front_a, front_b)
	var band_high: float = maxf(front_a, front_b)
	var water: float = _mean_t(px, row, flip, edge_low - WATER_SIDE_PX, edge_low - 0.5)
	var band: float = _mean_t(px, row, flip, band_low + 1.0, band_high - 1.0)
	if is_nan(band):
		band = _pix(px, row, flip, floori((band_low + band_high) / 2.0))
	var room: float = _mean_t(px, row, flip, column_high + 3.0, column_high + 14.0)
	var trough: float = INF
	for k: int in range(floori(edge_low) - 2, ceili(band_low) + 2):
		trough = minf(trough, _pix(px, row, flip, k))
	var mean_sides: float = (water + band) / 2.0
	var dip: float = maxf(0.0, minf(water, band) - trough) / maxf(mean_sides, 1e-9)
	result.merge({"water": water, "band": band, "room": room, "trough": trough, "dip": dip}, true)
	## Band width: half-step crossings water -> band and band -> room.
	var distinct: bool = absf(band - water) > 0.03 * mean_sides
	var left: float = t_inner
	if distinct:
		var level_in: float = (water + band) / 2.0
		var found_in: float = _crossing(
			px,
			row,
			flip,
			floori(edge_low - WATER_SIDE_PX),
			floori(band_high),
			level_in,
			band > water
		)
		left = found_in if not is_nan(found_in) else t_inner
	var level_out: float = (band + room) / 2.0
	var right: float = _crossing(
		px, row, flip, floori(column_high + 14.0), floori(left), level_out, band > room
	)
	result["left_crossing_px"] = snappedf(left, 0.01)
	result["left_resolved"] = distinct
	result["right_crossing_px"] = snappedf(right, 0.01) if not is_nan(right) else null
	result["width_px"] = snappedf(right - left, 0.01) if not is_nan(right) else null
	## Core: strongest 2 px running mean inside the band, 1 px in from each crossing.
	var first: int = ceili(left + 1.0 - 0.5)
	var last: int = floori(right - 1.0 - 0.5) if not is_nan(right) else first
	var inside: Array[float] = []
	for k: int in range(first, last + 1):
		inside.append(_pix(px, row, flip, k))
	if inside.size() >= 3:
		var inside_mean: float = 0.0
		for value: float in inside:
			inside_mean += value
		inside_mean /= float(inside.size())
		var strongest: float = 0.0
		for i: int in range(inside.size() - 1):
			strongest = maxf(strongest, (inside[i] + inside[i + 1]) / 2.0)
		result["core"] = strongest / maxf(inside_mean, 1e-9) - 1.0
	result["profile_t0"] = floori(edge_low) - 16
	var values: Array[float] = []
	for k: int in range(floori(edge_low) - 16, ceili(column_high) + 17):
		values.append(snappedf(_pix(px, row, flip, k), 0.000001))
	result["profile_lum"] = values
	return result


func _gate_corners(corners: Array[Dictionary]) -> void:
	var ac: String = "AC1" if _pose == "front" else "AC2"
	for entry: Dictionary in corners:
		var tag: String = (
			"%s %s %d%%" % [_pose, entry["label"], int(float(entry["fraction"]) * 100)]
		)
		if entry.has("skipped"):
			_check(ac, "%s dip" % tag, null, "corner off screen", null)
			continue
		var dip: float = entry["dip"]
		_check(ac, "dip %s (AC8 on medium)" % tag, dip, "<= %s" % DIP_LIMIT, dip <= DIP_LIMIT)
		if entry.has("core"):
			var core: float = entry["core"]
			_check("AC3", "core %s" % tag, core, "<= %s" % CORE_LIMIT, core <= CORE_LIMIT)
		if entry["width_px"] == null:
			_check("AC5", "width %s" % tag, null, "no right crossing", null)
			continue
		var width: float = entry["width_px"]
		var column: float = float(entry["projected_column_px"]) + 1.0
		_check("AC5", "width %s" % tag, width, "<= %.2f" % column, width <= column)


func _gate_monotonic(corners: Array[Dictionary]) -> void:
	for entry: Dictionary in corners:
		if entry.has("skipped"):
			continue
		var tag: String = (
			"%s %s %d%%" % [_pose, entry["label"], int(float(entry["fraction"]) * 100)]
		)
		var lum: Array = entry["profile_lum"]
		var water: float = entry["water"]
		var room: float = entry["room"]
		var direction: float = 1.0 if room >= water else -1.0
		var worst: float = 0.0
		for i: int in lum.size():
			for j: int in range(i + 1, lum.size()):
				worst = maxf(worst, direction * (float(lum[i]) - float(lum[j])))
		var relative: float = worst / maxf((water + room) / 2.0, 1e-9)
		_check(
			"AC7",
			"edge 0: monotonic water -> room %s" % tag,
			relative,
			"<= %s" % EXCURSION_LIMIT,
			relative <= EXCURSION_LIMIT
		)


# --- checks that compare with before (AC4, AC9) ---


func _default_checks(result: Dictionary, px: PackedFloat32Array) -> void:
	var before: PackedFloat32Array = _load_before()
	var before_json: Dictionary = _load_before_json()
	var have_before: bool = not before.is_empty()
	result["before_available"] = have_before
	var specs: Array[Dictionary] = _line_specs()
	var after_lines: Dictionary = _detect_lines(px, specs)
	result["lines_after"] = after_lines
	var mask: PackedByteArray = _corner_mask()
	if have_before:
		var before_lines: Dictionary = _detect_lines(before, specs)
		result["lines_before"] = before_lines
		for name: String in after_lines:
			var fresh: Array[float] = _new_features(after_lines[name], before_lines.get(name, []))
			_check(
				"AC4b/AC8",
				"new line on %s" % name,
				fresh.size(),
				"== 0",
				fresh.is_empty(),
				str(fresh) if not fresh.is_empty() else ""
			)
		_gate_unchanged(result, px, before, mask)
	else:
		for name: String in after_lines:
			if not (after_lines[name] as Array).is_empty():
				_check("AC4b", "line on %s (no before)" % name, after_lines[name], "info", null)
	_bottom_line_checks(result, px, before)
	await _frame_checks(result, px, before, before_json)


func _gate_unchanged(
	result: Dictionary, px: PackedFloat32Array, before: PackedFloat32Array, mask: PackedByteArray
) -> void:
	var over: int = 0
	var counted: int = 0
	var worst: float = 0.0
	for y: int in HEIGHT:
		for x: int in WIDTH:
			if mask[y * WIDTH + x] != 0:
				continue
			counted += 1
			var change: float = absf(_lum(px, x, y) - _lum(before, x, y))
			worst = maxf(worst, change)
			if change > UNCHANGED_LIMIT:
				over += 1
	var share: float = float(over) / float(maxi(counted, 1))
	result["unchanged"] = {"max_change": worst, "over": over, "counted": counted, "share": share}
	_check(
		"AC4a/AC9",
		"pixels outside the corner columns changed by > %s" % UNCHANGED_LIMIT,
		share,
		"<= %s" % UNCHANGED_SHARE_LIMIT,
		share <= UNCHANGED_SHARE_LIMIT,
		"max change %.6f, %d px over" % [worst, over]
	)


## Mask of the 4 projected vertical corner columns, dilated by MASK_DILATE_PX.
func _corner_mask() -> PackedByteArray:
	var mask: PackedByteArray = PackedByteArray()
	mask.resize(WIDTH * HEIGHT)
	for sx: float in [1.0, -1.0]:
		for sz: float in [1.0, -1.0]:
			var points: PackedVector2Array = PackedVector2Array()
			for dx: float in [0.0, _g]:
				for dz: float in [0.0, _g]:
					for y: float in [-_g, _definition.interior_size_m.y]:
						points.append(_proj(Vector3(sx * (_hx + dx), y, sz * (_hz + dz))))
			var hull: PackedVector2Array = Geometry2D.convex_hull(points)
			var grown: Array[PackedVector2Array] = Geometry2D.offset_polygon(
				hull, MASK_DILATE_PX, Geometry2D.JOIN_MITER
			)
			if not grown.is_empty():
				_fill(mask, grown[0])
	return mask


func _fill(mask: PackedByteArray, polygon: PackedVector2Array) -> void:
	var low: float = INF
	var high: float = -INF
	for point: Vector2 in polygon:
		low = minf(low, point.y)
		high = maxf(high, point.y)
	for y: int in range(maxi(floori(low), 0), mini(ceili(high), HEIGHT - 1) + 1):
		var center: float = y + 0.5
		var x_low: float = INF
		var x_high: float = -INF
		for i: int in polygon.size():
			var a: Vector2 = polygon[i]
			var b: Vector2 = polygon[(i + 1) % polygon.size()]
			if (a.y <= center and b.y > center) or (b.y <= center and a.y > center):
				var x: float = a.x + (center - a.y) * (b.x - a.x) / (b.y - a.y)
				x_low = minf(x_low, x)
				x_high = maxf(x_high, x)
		if x_low > x_high:
			continue
		for x: int in range(maxi(ceili(x_low - 0.5), 0), mini(floori(x_high - 0.5), WIDTH - 1) + 1):
			mask[y * WIDTH + x] = 1


# --- line detector (AC4b, AC8) ---


## Profiles across the floor inner edges, the back corners (interior side only), the water line
## and the glass top. Each spec: name, axis ("x" runs along a row, "y" along a column), the fixed
## row or column, the first and last pixel, and the range in which a feature centre counts.
func _line_specs() -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	var height: float = _definition.interior_size_m.y
	for fraction: float in FRACTIONS:
		var x_at: float = -_hx + fraction * 2.0 * _hx
		var z_at: float = _hz - fraction * 2.0 * _hz
		var tag: String = "%d%%" % int(fraction * 100)
		_add_spec(specs, "floor front edge " + tag, "y", Vector3(x_at, 0.0, _hz), 0.0, 1.0, 14)
		_add_spec(
			specs, "water line " + tag, "y", Vector3(x_at, _base_size.y, _hz + _g), 0.0, 1.0, 14
		)
		_add_spec(specs, "glass top " + tag, "y", Vector3(x_at, height, _hz + _g), 0.0, 1.0, 14)
		for sgn: float in [1.0, -1.0]:
			var side: String = "R" if sgn > 0.0 else "L"
			_add_spec(
				specs,
				"floor side edge %s %s" % [side, tag],
				"x",
				Vector3(sgn * _hx, 0.0, z_at),
				sgn,
				0.0,
				14
			)
	for sgn: float in [1.0, -1.0]:
		var side: String = "R" if sgn > 0.0 else "L"
		var mid: Vector3 = Vector3(sgn * _hx, _base_size.y / 2.0, -_hz)
		_add_spec(specs, "back corner %s" % side, "x", mid, sgn, 0.0, 30)
	return specs


func _add_spec(
	specs: Array[Dictionary],
	label: String,
	axis: String,
	point: Vector3,
	sgn: float,
	_unused: float,
	reach: int
) -> void:
	var screen: Vector2 = _proj(point)
	var inside_point: Vector2 = _proj(point + Vector3(-sgn * 0.05, 0.0, 0.0))
	if screen.x < reach + 8 or screen.x > WIDTH - reach - 8:
		return
	if screen.y < reach + 8 or screen.y > HEIGHT - reach - 8:
		return
	var spec: Dictionary = {"name": label, "axis": axis, "reach": reach}
	if axis == "y":
		spec["fixed"] = roundi(screen.x)
		spec["first"] = roundi(screen.y) - reach
		spec["last"] = roundi(screen.y) + reach
		spec["min_center"] = -INF
		spec["max_center"] = INF
	else:
		spec["fixed"] = roundi(screen.y)
		spec["first"] = roundi(screen.x) - reach
		spec["last"] = roundi(screen.x) + reach
		## Only the interior side counts: the corner column and the side pane are outside.
		var interior_left: bool = inside_point.x < screen.x
		spec["min_center"] = -INF if interior_left else screen.x
		spec["max_center"] = screen.x if interior_left else INF
	specs.append(spec)


func _detect_lines(px: PackedFloat32Array, specs: Array[Dictionary]) -> Dictionary:
	var found: Dictionary = {}
	for spec: Dictionary in specs:
		var lum: Array[float] = []
		var green: Array[float] = []
		var first: int = spec["first"]
		for i: int in range(first, int(spec["last"]) + 1):
			var x: int = i if spec["axis"] == "x" else int(spec["fixed"])
			var y: int = int(spec["fixed"]) if spec["axis"] == "x" else i
			lum.append(_lum(px, x, y))
			green.append(_green_ratio(px, x, y))
		var centers: Array[float] = []
		for length: int in [1, 2]:
			for i: int in range(6, lum.size() - length - 5):
				var centre: float = float(first + i) + 0.5 * float(length)
				if centre < float(spec["min_center"]) or centre > float(spec["max_center"]):
					continue
				if _is_line(lum, i, length) or _is_line(green, i, length):
					centers.append(centre)
		found[spec["name"]] = centers
	return found


## True when the run at [i, i + length) differs from the mean of the pixels 3 to 6 px away on
## each side by more than LINE_LIMIT, in the same direction on both sides.
func _is_line(values: Array[float], i: int, length: int) -> bool:
	var run: float = 0.0
	for k: int in length:
		run += values[i + k]
	run /= float(length)
	var left: float = (values[i - 3] + values[i - 4] + values[i - 5] + values[i - 6]) / 4.0
	var right_start: int = i + length + 2
	var right: float = 0.0
	for k: int in 4:
		right += values[right_start + k]
	right /= 4.0
	var reference: float = maxf((left + right) / 2.0, 1e-9)
	var from_left: float = (run - left) / reference
	var from_right: float = (run - right) / reference
	return (
		(from_left > LINE_LIMIT and from_right > LINE_LIMIT)
		or (from_left < -LINE_LIMIT and from_right < -LINE_LIMIT)
	)


func _new_features(after_features: Array, before_features: Array) -> Array[float]:
	var fresh: Array[float] = []
	for centre: float in after_features:
		var known: bool = false
		for old: float in before_features:
			if absf(old - centre) <= LINE_MATCH_PX:
				known = true
				break
		if not known:
			fresh.append(centre)
	return fresh


# --- the bottom-front green line (AC4c) ---


func _bottom_line_checks(
	result: Dictionary, px: PackedFloat32Array, before: PackedFloat32Array
) -> void:
	if _pose != "front":
		return
	var widths: Dictionary = {}
	for fraction: float in FRACTIONS:
		var x_at: float = -_hx + fraction * 2.0 * _hx
		var top: Vector2 = _proj(Vector3(x_at, 0.0, _hz + _g))
		var bottom: Vector2 = _proj(Vector3(x_at, -_g, _hz + _g))
		var tag: String = "%d%%" % int(fraction * 100)
		var after_width: float = _line_width(px, roundi(top.x), top.y, bottom.y)
		var entry: Dictionary = {"after": after_width, "rows": [top.y, bottom.y]}
		if not before.is_empty():
			var before_width: float = _line_width(before, roundi(top.x), top.y, bottom.y)
			entry["before"] = before_width
			var ok: bool = after_width <= before_width + WIDTH_NOISE_PX
			_check(
				"AC4c",
				"bottom-front line width %s" % tag,
				after_width,
				"<= before %.2f + %s" % [before_width, WIDTH_NOISE_PX],
				ok
			)
		else:
			_check(
				"AC4c", "bottom-front line width %s (no before)" % tag, after_width, "info", null
			)
		widths[tag] = entry
	result["bottom_front_line"] = widths


## Half-step width of the line between rows `top` and `bottom` (screen y) on a column: the
## extreme sample against the mean of the two sides, crossings at half of each step.
func _line_width(px: PackedFloat32Array, col: int, top: float, bottom: float) -> float:
	var first: int = floori(top) - 12
	var last: int = ceili(bottom) + 12
	var values: Array[float] = []
	for y: int in range(first, last + 1):
		values.append(_lum(px, col, y))
	var above: float = 0.0
	var below: float = 0.0
	for k: int in 8:
		above += values[k]
		below += values[values.size() - 1 - k]
	above /= 8.0
	below /= 8.0
	var reference: float = (above + below) / 2.0
	var peak: float = reference
	for i: int in range(6, values.size() - 6):
		if absf(values[i] - reference) > absf(peak - reference):
			peak = values[i]
	var start: float = NAN
	var finish: float = NAN
	for i: int in range(1, values.size()):
		if absf(values[i] - above) >= absf(peak - above) / 2.0 and is_nan(start):
			start = float(i - 1) + _share(values[i - 1], values[i], (peak + above) / 2.0)
	for i: int in range(values.size() - 2, -1, -1):
		if absf(values[i] - below) >= absf(peak - below) / 2.0 and is_nan(finish):
			finish = float(i + 1) - _share(values[i + 1], values[i], (peak + below) / 2.0)
	return finish - start if not is_nan(start) and not is_nan(finish) else NAN


func _share(from_value: float, to_value: float, level: float) -> float:
	var span: float = to_value - from_value
	return clampf((level - from_value) / span, 0.0, 1.0) if absf(span) > 1e-9 else 0.0


# --- frame level checks (AC9) ---


func _frame_checks(
	result: Dictionary, px: PackedFloat32Array, before: PackedFloat32Array, before_json: Dictionary
) -> void:
	if _pose != "front":
		return
	var interior: Rect2i = _box_rect(
		AABB(Vector3(-_hx, 0.0, -_hz), _definition.interior_size_m), _tank.global_transform
	)
	var means: Dictionary = _frame_means(px, interior)
	result["frame"] = means
	var brightest: bool = means["interior_mean"] > means["rest_mean"]
	_check("AC9", "interior mean is the brightest part of the frame", brightest, "true", brightest)
	if not before.is_empty():
		var old: Dictionary = _frame_means(before, interior)
		var change: float = absf(means["interior_mean"] / old["interior_mean"] - 1.0)
		_check(
			"AC9",
			"interior mean against before",
			change,
			"<= %s" % INTERIOR_TOLERANCE,
			change <= INTERIOR_TOLERANCE
		)
	## Face-on glass background change: the central front pane area with and without the glass.
	var face: Rect2i = _face_rect()
	var with_glass: float = _rect_mean(px, face)
	_glass.visible = false
	var hidden_image: Image = await _capture_hdr()
	_glass.visible = true
	var without: float = _rect_mean(_rgba(hidden_image), face)
	var change_now: float = absf(with_glass - without)
	result["face_on_background"] = {"with_glass": with_glass, "without": without}
	var change_before: float = INF
	if before_json.has("face_on_background"):
		var stored: Dictionary = before_json["face_on_background"]
		change_before = absf(float(stored["with_glass"]) - float(stored["without"]))
	if is_inf(change_before):
		_check("AC9", "glass background change face-on (no before)", change_now, "info", null)
	else:
		_check(
			"AC9",
			"glass background change face-on",
			change_now,
			"<= before %.6f + %s" % [change_before, UNCHANGED_LIMIT],
			change_now <= change_before + UNCHANGED_LIMIT
		)
	if _size_name == "large":
		await _strip_check(result, before_json)


func _face_rect() -> Rect2i:
	var low: Vector2 = Vector2(INF, INF)
	var high: Vector2 = Vector2(-INF, -INF)
	for fx: float in [-0.5, 0.5]:
		for fy: float in [0.25, 0.75]:
			var screen: Vector2 = _proj(Vector3(fx * _hx, _base_size.y * fy, _hz + _g))
			low = low.min(screen)
			high = high.max(screen)
	return Rect2i(Vector2i(low.floor()), Vector2i((high - low).ceil())).intersection(
		Rect2i(0, 0, WIDTH, HEIGHT)
	)


func _box_rect(box: AABB, xform: Transform3D) -> Rect2i:
	var low: Vector2 = Vector2(INF, INF)
	var high: Vector2 = Vector2(-INF, -INF)
	for index: int in 8:
		var screen: Vector2 = _camera.unproject_position(xform * box.get_endpoint(index))
		low = low.min(screen)
		high = high.max(screen)
	var rect: Rect2i = Rect2i(Vector2i(low.floor()), Vector2i((high - low).ceil()))
	return rect.intersection(Rect2i(0, 0, WIDTH, HEIGHT))


func _rect_mean(px: PackedFloat32Array, rect: Rect2i) -> float:
	var total: float = 0.0
	var count: int = 0
	for y: int in range(rect.position.y, rect.end.y, 2):
		for x: int in range(rect.position.x, rect.end.x, 2):
			total += _lum(px, x, y)
			count += 1
	return total / float(maxi(count, 1))


func _frame_means(px: PackedFloat32Array, rect: Rect2i) -> Dictionary:
	var inside: float = 0.0
	var outside: float = 0.0
	var count_in: int = 0
	var count_out: int = 0
	for y: int in range(0, HEIGHT, 4):
		for x: int in range(0, WIDTH, 4):
			if rect.has_point(Vector2i(x, y)):
				inside += _lum(px, x, y)
				count_in += 1
			else:
				outside += _lum(px, x, y)
				count_out += 1
	return {
		"interior_mean": inside / float(maxi(count_in, 1)),
		"rest_mean": outside / float(maxi(count_out, 1)),
	}


## The #23 AC14 stand-in: a 3.5 x 0.5 cm strip, one half saturated red and one half saturated
## blue, unshaded, 3 mm in front of the back wall at the centre, at half water height. The
## contrast is max/min of the strip mean against the mean of the ring around it (plain ratio).
func _strip_check(result: Dictionary, before_json: Dictionary) -> void:
	var strip: Node3D = Node3D.new()
	_tank.add_child(strip)
	var centre: Vector3 = Vector3(0.0, _base_size.y / 2.0, -_hz + 0.003)
	var colours: Array[Color] = [Color(1.0, 0.03, 0.03), Color(0.03, 0.15, 1.0)]
	for i: int in 2:
		var piece: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(0.0175, 0.005, 0.001)
		piece.mesh = box
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = colours[i]
		piece.material_override = material
		piece.position = centre + Vector3(-0.00875 if i == 0 else 0.00875, 0.0, 0.0)
		strip.add_child(piece)
	var image: Image = await _capture_hdr()
	strip.queue_free()
	var px: PackedFloat32Array = _rgba(image)
	var low: Vector2 = _proj(centre + Vector3(-0.0175, 0.0025, 0.0))
	var high: Vector2 = _proj(centre + Vector3(0.0175, -0.0025, 0.0))
	var inner: Rect2i = Rect2i(
		Vector2i(low.x + 1, low.y + 1), Vector2i(high.x - low.x - 2, high.y - low.y - 2)
	)
	var ring_in: Rect2i = inner.grow(3)
	var ring_out: Rect2i = inner.grow(8)
	var strip_sum: float = 0.0
	var strip_n: int = 0
	var ring_sum: float = 0.0
	var ring_n: int = 0
	for y: int in range(ring_out.position.y, ring_out.end.y):
		for x: int in range(ring_out.position.x, ring_out.end.x):
			if inner.has_point(Vector2i(x, y)):
				strip_sum += _lum(px, x, y)
				strip_n += 1
			elif not ring_in.has_point(Vector2i(x, y)):
				ring_sum += _lum(px, x, y)
				ring_n += 1
	var strip_mean: float = strip_sum / float(maxi(strip_n, 1))
	var ring_mean: float = ring_sum / float(maxi(ring_n, 1))
	var contrast: float = maxf(strip_mean, ring_mean) / maxf(minf(strip_mean, ring_mean), 1e-9)
	result["strip"] = {
		"strip_mean": strip_mean,
		"ring_mean": ring_mean,
		"contrast": contrast,
		"rect": [inner.position.x, inner.position.y, inner.size.x, inner.size.y],
	}
	if before_json.has("strip"):
		var old: float = float((before_json["strip"] as Dictionary)["contrast"])
		_check(
			"AC9",
			"large strip contrast",
			contrast,
			">= before %.4f - %s" % [old, CONTRAST_NOISE],
			contrast >= old - CONTRAST_NOISE
		)
	else:
		_check("AC9", "large strip contrast (no before)", contrast, "info", null)


# --- crops for the owner check ---


func _save_crops(png: Image) -> void:
	var y: float = _base_size.y / 2.0
	for sgn: float in [1.0, -1.0]:
		var side: String = "R" if sgn > 0.0 else "L"
		_crop(png, _proj(Vector3(sgn * _hx, y, -_hz)), "crop_back_%s" % side)
		_crop(
			png, _proj(Vector3(sgn * (_hx + _g / 2.0), y, _hz + _g / 2.0)), "crop_front_%s" % side
		)


func _crop(png: Image, centre: Vector2, label: String) -> void:
	var rect: Rect2i = Rect2i(Vector2i(centre) - Vector2i(70, 100), Vector2i(140, 200))
	rect = rect.intersection(Rect2i(0, 0, WIDTH, HEIGHT))
	if rect.size.x < 40 or rect.size.y < 40:
		return
	var crop: Image = png.get_region(rect)
	crop.resize(rect.size.x * 4, rect.size.y * 4, Image.INTERPOLATE_NEAREST)
	crop.save_png(_out_dir.path_join(_name("_" + label + ".png")))


# --- reporting ---


func _check(
	criterion: String,
	label: String,
	value: Variant,
	limit: String,
	passed: Variant,
	note: String = ""
) -> void:
	(
		_checks
		. append(
			{
				"ac": criterion,
				"check": label,
				"value": value,
				"limit": limit,
				"pass": passed,
				"note": note,
			}
		)
	)


func _print_summary(corners: Array[Dictionary], failed: int) -> void:
	print("== glass seam %s %s %s %s ==" % [_tag, _size_name, _pose, _variant])
	for entry: Dictionary in corners:
		if entry.has("skipped"):
			print(
				(
					"  %s %d%%: %s"
					% [entry["label"], int(float(entry["fraction"]) * 100), entry["skipped"]]
				)
			)
			continue
		var core: String = "n/a"
		if entry.has("core"):
			core = "%.1f%%" % (float(entry["core"]) * 100.0)
		var head: String = "  %s %d%%: " % [entry["label"], int(float(entry["fraction"]) * 100)]
		var levels: String = (
			"water %.5f band %.5f room %.5f trough %.5f dip %.1f%% "
			% [entry["water"], entry["band"], entry["room"], entry["trough"], entry["dip"] * 100.0]
		)
		var shape: String = (
			"width %s core %s column %.1f px"
			% [str(entry["width_px"]), core, entry["projected_column_px"]]
		)
		print(head + levels + shape)
	for entry: Dictionary in _checks:
		if entry["pass"] == false:
			print(
				(
					"  FAIL %s %s: %s (limit %s) %s"
					% [entry["ac"], entry["check"], entry["value"], entry["limit"], entry["note"]]
				)
			)
	print("  checks: %d, failed: %d" % [_checks.size(), failed])
