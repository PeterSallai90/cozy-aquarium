extends SceneTree
## Measuring script for #128 (owner: tester). Not a test suite: GdUnit does not pick it up.
## It needs the real renderer (no --headless). Relative --out paths are relative to the repository
## root. Run it like this:
##
##   godot_console --path game -s res://tests/measure/water_glint_measure.gd -- \
##       --size=large --view=top --tag=before --out=.claude/state/previews/128/
##
## Options (all after the lone "--"):
##   --size=small|medium|large   tank to show (default medium)
##   --view=top|front|orbit|shimmer
##       top      glint metrics (AC1, AC2, AC3) from the top pose, ripple frozen
##       front    interior and frame luminance (AC5, AC17) from the room's default camera
##       lamp     the lamp bar seen from below (its bright side), for the AC2 lamp peak
##       orbit    AC4: top pose down to 30 degrees pitch and back over 10 s, live ripple
##       shimmer  AC4 baseline: top pose held for 10 s, live ripple (calm-ripple variation)
##   --tag=<text>                 file name prefix, "before" or "after" (default "run")
##   --out=<dir>                  output directory (default .claude/state/previews/128/)
##   --exposure=<float>           linear tonemap exposure used for the capture (default 1.0);
##                                luminance is divided by it again
##   --stride=<int>               pixel step of the glint analysis (default 1; 2 for orbit)
##
## Added-light protocol (owner decision on #128, 2026-11-10): AC1 (region width, area), AC2 (peak
## against the lamp peak) and AC4 (variation) are measured on the light the water surface ADDS:
## luminance(normal frame) minus luminance(same pose with the Surface mesh hidden), clamped at 0 per
## pixel. The lamp-lit sand seen through the water is therefore not counted as glint. AC3 stays on
## the normal frame: glint = normal-frame luminance at the added-light peak pixel, divided by the
## median of the normal frame on the ring at 1.5 to 2x the radius of the added-light 20% region.
## Top: both frames use the frozen ripple, so TIME is identical. Orbit and shimmer: per sample the
## camera is placed once and two frames are rendered at that pose, normal (live ripple) and
## surface hidden. The hidden frame contains no water surface, so it has no TIME dependence; only
## the pose has to match. The "normal" block of the top JSON keeps the old normal-frame-only numbers
## (peak, regions, area, ring contrast around the normal-frame peak) for comparison with the
## earlier baseline. Orbit/shimmer JSON and CSV now hold the added-light numbers. No new CLI
## options; the top view also writes <tag>_<size>_top_surface_hidden.exr and runs the
## lamp-from-below measurement (<tag>_<size>_top_lamp.*), so glint_peak_over_lamp_strip_peak (AC2)
## is in its JSON.
##
## Measurement basis (BA decision on #128): 1920x1080, Forward+, room corner, no fish. Luminance is
## linear HDR before tonemapping and glow: a SubViewport with use_hdr_2d, a runtime copy of the
## room Environment with glow off and the linear tonemapper. Rec. 709 weights. Ripple TIME is
## frozen by ripple_speed 0 on a runtime copy of the surface material (top and front); orbit and
## shimmer keep the stored ripple_speed. Per run it writes <tag>_<size>_<view>.json, an .exr
## (HDR, bar hidden for top, bar visible for front) and tonemapped .png screenshots.
##
## The top pose is not recorded anywhere from #23 (the previews are the only record), so it is
## fixed here as constants read from those previews: steep (75 degrees), front edge of the water
## about 70% of the screen width, pivot at the centre of the water surface.

const WIDTH := 1920
const HEIGHT := 1080
const ROOM_SCENE := "res://scenes/room/room_corner.tscn"
const GlbChecks := preload("res://tests/helpers/glb_mesh_checks.gd")

const TOP_PITCH_DEG := 75.0
const ORBIT_LOW_PITCH_DEG := 30.0
const TOP_WIDTH_SHARE := 0.70
const ORBIT_SECONDS := 10.0
const SETTLE_FRAMES := 6
const MENISCUS_INSET_PX := 6.0
const MIN_RING_RADIUS_PX := 2.0
const REGION_LEVEL := 0.5
const AREA_LEVEL := 0.2
const AVERAGE_STRIDE := 4
const LAMP_DIFFERENCE := 0.002
const LUMA := Vector3(0.2126, 0.7152, 0.0722)

var _args: Dictionary = {}
var _size_name: String = "medium"
var _exposure: float = 1.0
var _channels: int = 4
var _viewport: SubViewport = null
var _room: Node3D = null
var _camera: Camera3D = null
var _environment: Environment = null
var _original_tonemap: int = 0
var _original_glow: bool = true
var _tank: Node3D = null
var _definition: TankDefinition = null
var _surface: MeshInstance3D = null
var _surface_material: ShaderMaterial = null
var _lamp_bar: MeshInstance3D = null
var _pivot: Vector3 = Vector3.ZERO
var _top_distance: float = 0.0
var _front_transform: Transform3D = Transform3D.IDENTITY


func _initialize() -> void:
	_args = _parse_args(OS.get_cmdline_user_args())
	_run()


func _parse_args(raw: PackedStringArray) -> Dictionary:
	var parsed: Dictionary = {}
	for argument: String in raw:
		if not argument.begins_with("--"):
			continue
		var parts: PackedStringArray = argument.substr(2).split("=", true, 1)
		parsed[parts[0]] = parts[1] if parts.size() > 1 else "true"
	return parsed


func _run() -> void:
	_size_name = str(_args.get("size", "medium"))
	var view: String = str(_args.get("view", "top"))
	var tag: String = str(_args.get("tag", "run"))
	var out_dir: String = str(_args.get("out", ".claude/state/previews/128/"))
	_exposure = float(_args.get("exposure", "1.0"))
	var stride: int = int(_args.get("stride", "2" if view in ["orbit", "shimmer"] else "1"))
	if not out_dir.is_absolute_path():
		## Relative paths are relative to the repository root, the parent of the project folder.
		out_dir = ProjectSettings.globalize_path("res://").path_join("..").path_join(out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	await _setup()
	var base: String = out_dir.path_join("%s_%s_%s" % [tag, _size_name, view])
	var result: Dictionary = {}
	match view:
		"top":
			result = await _measure_top(base, stride)
		"front":
			result = await _measure_front(base)
		"lamp":
			result = await _measure_lamp(base)
		"orbit":
			result = await _measure_live(base, stride, true)
		"shimmer":
			result = await _measure_live(base, stride, false)
		_:
			push_error("unknown --view=%s" % view)
			quit(2)
			return
	result["tag"] = tag
	result["size"] = _size_name
	result["view"] = view
	result["exposure"] = _exposure
	result["resolution"] = [WIDTH, HEIGHT]
	var file: FileAccess = FileAccess.open(base + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print(JSON.stringify(result, "\t"))
	quit(0 if bool(result.get("ok", false)) else 1)


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
	var scene: PackedScene = load(ROOM_SCENE) as PackedScene
	_room = scene.instantiate() as Node3D
	_room.call("setup", model, catalog)
	_viewport.add_child(_room)
	await _settle()
	_camera = _room.get_node("PlaceholderCamera") as Camera3D
	_tank = _room.get_node("Tank") as Node3D
	_surface = _tank.get_node("WaterVolume/Surface") as MeshInstance3D
	_lamp_bar = GlbChecks.find_mesh(_room.get_node("Lamp"), "lamp")
	var holder: WorldEnvironment = _room.get_node("WorldEnvironment") as WorldEnvironment
	_environment = holder.environment
	_original_tonemap = _environment.tonemap_mode
	_original_glow = _environment.glow_enabled
	_surface_material = (_surface.material_override as ShaderMaterial).duplicate()
	_surface.material_override = _surface_material
	_pivot = _tank.global_position + Vector3(0.0, _definition.water_line_height_m, 0.0)
	_front_transform = _camera.transform
	_top_distance = _fit_top_distance()


func _settle() -> void:
	for _i: int in SETTLE_FRAMES:
		await process_frame
	await RenderingServer.frame_post_draw


func _freeze_ripple(frozen: bool) -> void:
	_surface_material.set_shader_parameter("ripple_speed", 0.0 if frozen else _stored_speed())


func _stored_speed() -> float:
	var stored: ShaderMaterial = load("res://assets/tank/materials/water_surface.tres")
	return float(stored.get_shader_parameter("ripple_speed"))


# --- poses ---


## The #23 top pose: camera above the water centre at the given pitch, distance chosen so the
## front edge of the water is TOP_WIDTH_SHARE of the screen width at TOP_PITCH_DEG.
func _fit_top_distance() -> float:
	var low: float = 0.3
	var high: float = 8.0
	for _i: int in 40:
		var middle: float = (low + high) / 2.0
		_place_camera(TOP_PITCH_DEG, middle)
		if _front_edge_px() > TOP_WIDTH_SHARE * WIDTH:
			low = middle
		else:
			high = middle
	return (low + high) / 2.0


func _place_camera(pitch_deg: float, distance: float) -> void:
	var pitch: float = deg_to_rad(pitch_deg)
	_camera.position = _pivot + distance * Vector3(0.0, sin(pitch), cos(pitch))
	_camera.rotation = Vector3(-pitch, 0.0, 0.0)
	_camera.force_update_transform()


func _water_corners() -> PackedVector3Array:
	var size: Vector3 = _definition.get_water_volume_size_m()
	var corners: PackedVector3Array = PackedVector3Array()
	for point: Vector2 in [Vector2(-1, 1), Vector2(1, 1), Vector2(1, -1), Vector2(-1, -1)]:
		var local: Vector3 = Vector3(point.x * size.x / 2.0, size.y, point.y * size.z / 2.0)
		corners.append(_tank.global_transform * local)
	return corners


func _project(point: Vector3) -> Vector2:
	return _camera.unproject_position(point)


func _front_edge_px() -> float:
	var corners: PackedVector3Array = _water_corners()
	return _project(corners[0]).distance_to(_project(corners[1]))


func _box_rect(box: AABB, xform: Transform3D) -> Rect2i:
	var low: Vector2 = Vector2(INF, INF)
	var high: Vector2 = Vector2(-INF, -INF)
	for index: int in 8:
		var screen: Vector2 = _project(xform * box.get_endpoint(index))
		low = low.min(screen)
		high = high.max(screen)
	var rect: Rect2i = Rect2i(Vector2i(low.floor()), Vector2i((high - low).ceil()))
	return rect.intersection(Rect2i(0, 0, WIDTH, HEIGHT))


func _interior_rect() -> Rect2i:
	var interior: Vector3 = _definition.interior_size_m
	var box: AABB = AABB(Vector3(-interior.x / 2.0, 0.0, -interior.z / 2.0), interior)
	return _box_rect(box, _tank.global_transform)


func _lamp_rect() -> Rect2i:
	if _lamp_bar == null or _lamp_bar.mesh == null:
		return Rect2i()
	return _box_rect(_lamp_bar.mesh.get_aabb(), _lamp_bar.global_transform)


# --- capture ---


## Renders one frame; the result is a copy of the viewport image.
func _capture() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = _viewport.get_texture().get_image()
	_channels = 4 if image.get_format() in [Image.FORMAT_RGBAH, Image.FORMAT_RGBAF] else 3
	return image


func _measure_mode(on: bool) -> void:
	_viewport.use_hdr_2d = on
	_environment.glow_enabled = false if on else _original_glow
	_environment.tonemap_mode = (
		Environment.TONE_MAPPER_LINEAR if on else _original_tonemap as Environment.ToneMapper
	)
	_environment.tonemap_exposure = _exposure if on else 1.0


func _capture_hdr() -> Image:
	_measure_mode(true)
	await _settle()
	var image: Image = await _capture()
	var format: Image.Format = image.get_format()
	if not format in [Image.FORMAT_RGBAH, Image.FORMAT_RGBH, Image.FORMAT_RGBAF, Image.FORMAT_RGBF]:
		push_error("capture is not HDR: image format %d" % format)
		return null
	return image


func _save_tonemapped(path: String) -> void:
	_measure_mode(false)
	await _settle()
	var image: Image = await _capture()
	image.convert(Image.FORMAT_RGBA8)
	image.save_png(path)
	_measure_mode(true)


func _set_bar_visible(shown: bool) -> void:
	if _lamp_bar != null:
		_lamp_bar.visible = shown


# --- luminance access ---


func _lum_at(data: PackedByteArray, half: bool, x: int, y: int) -> float:
	var step: int = 2 if half else 4
	var offset: int = (y * WIDTH + x) * _channels * step
	var red: float
	var green: float
	var blue: float
	if half:
		red = data.decode_half(offset)
		green = data.decode_half(offset + step)
		blue = data.decode_half(offset + 2 * step)
	else:
		red = data.decode_float(offset)
		green = data.decode_float(offset + step)
		blue = data.decode_float(offset + 2 * step)
	return (red * LUMA.x + green * LUMA.y + blue * LUMA.z) / _exposure


func _is_half(image: Image) -> bool:
	return image.get_format() in [Image.FORMAT_RGBAH, Image.FORMAT_RGBH]


func _rect_peak(image: Image, rect: Rect2i, other: Image) -> float:
	## Highest luminance in the rect among pixels that differ from the `other` image (the lamp bar
	## itself, not what is seen behind it); the whole rect when `other` is null.
	var data: PackedByteArray = image.get_data()
	var other_data: PackedByteArray = PackedByteArray() if other == null else other.get_data()
	var half: bool = _is_half(image)
	var peak: float = 0.0
	for y: int in range(rect.position.y, rect.end.y):
		for x: int in range(rect.position.x, rect.end.x):
			var value: float = _lum_at(data, half, x, y)
			if other != null and absf(value - _lum_at(other_data, half, x, y)) < LAMP_DIFFERENCE:
				continue
			peak = maxf(peak, value)
	return peak


## Mean luminance inside `rect` and outside it, on a coarse grid.
func _averages(image: Image, rect: Rect2i) -> Dictionary:
	var data: PackedByteArray = image.get_data()
	var half: bool = _is_half(image)
	var sum_in: float = 0.0
	var sum_out: float = 0.0
	var count_in: int = 0
	var count_out: int = 0
	for y: int in range(0, HEIGHT, AVERAGE_STRIDE):
		for x: int in range(0, WIDTH, AVERAGE_STRIDE):
			var value: float = _lum_at(data, half, x, y)
			if rect.has_point(Vector2i(x, y)):
				sum_in += value
				count_in += 1
			else:
				sum_out += value
				count_out += 1
	return {
		"interior_mean": sum_in / maxf(count_in, 1.0),
		"rest_mean": sum_out / maxf(count_out, 1.0),
		"interior_rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
	}


# --- glint metrics ---


## Scanline mask of the water surface quad, inset from the tank edge.
func _water_mask() -> Dictionary:
	var corners: PackedVector3Array = _water_corners()
	var polygon: PackedVector2Array = PackedVector2Array()
	for corner: Vector3 in corners:
		polygon.append(_project(corner))
	var meniscus_px: float = (
		_front_edge_px() / _definition.interior_size_m.x * 0.003 + MENISCUS_INSET_PX
	)
	var top: float = INF
	var bottom: float = -INF
	for point: Vector2 in polygon:
		top = minf(top, point.y)
		bottom = maxf(bottom, point.y)
	var first: int = maxi(int(ceilf(top + meniscus_px)), 0)
	var last: int = mini(int(floorf(bottom - meniscus_px)), HEIGHT - 1)
	var left: PackedInt32Array = PackedInt32Array()
	var right: PackedInt32Array = PackedInt32Array()
	for y: int in range(first, last + 1):
		var low_x: float = INF
		var high_x: float = -INF
		for index: int in 4:
			var a: Vector2 = polygon[index]
			var b: Vector2 = polygon[(index + 1) % 4]
			var scan: float = y + 0.5
			if (a.y <= scan) != (b.y <= scan):
				var crossing: float = a.x + (scan - a.y) / (b.y - a.y) * (b.x - a.x)
				low_x = minf(low_x, crossing)
				high_x = maxf(high_x, crossing)
		left.append(clampi(int(ceilf(low_x + meniscus_px)), 0, WIDTH - 1))
		right.append(clampi(int(floorf(high_x - meniscus_px)), 0, WIDTH - 1))
	return {"first": first, "left": left, "right": right, "polygon": polygon}


## Luminance on a grid of every `stride` pixels, -1 outside the water mask.
## With `subtract` set, each value is max(image - subtract, 0): the light the surface adds.
func _water_grid(image: Image, mask: Dictionary, stride: int, subtract: Image = null) -> Dictionary:
	var data: PackedByteArray = image.get_data()
	var other_data: PackedByteArray = PackedByteArray() if subtract == null else subtract.get_data()
	var half: bool = _is_half(image)
	var grid_w: int = (WIDTH + stride - 1) / stride
	var grid_h: int = (HEIGHT + stride - 1) / stride
	var grid: PackedFloat32Array = PackedFloat32Array()
	grid.resize(grid_w * grid_h)
	grid.fill(-1.0)
	var first: int = mask["first"]
	var left: PackedInt32Array = mask["left"]
	var right: PackedInt32Array = mask["right"]
	var cells: int = 0
	var peak: float = 0.0
	var peak_cell: Vector2i = Vector2i.ZERO
	for row: int in left.size():
		var y: int = first + row
		if y % stride != 0:
			continue
		for x: int in range(left[row], right[row] + 1):
			if x % stride != 0:
				continue
			var value: float = _lum_at(data, half, x, y)
			if subtract != null:
				value = maxf(value - _lum_at(other_data, half, x, y), 0.0)
			grid[(y / stride) * grid_w + x / stride] = value
			cells += 1
			if value > peak:
				peak = value
				peak_cell = Vector2i(x / stride, y / stride)
	return {
		"grid": grid, "w": grid_w, "h": grid_h, "cells": cells, "peak": peak, "peak_cell": peak_cell
	}


## Connected components (4-neighbour) of cells with value >= level. Each entry: area in cells,
## bounding box in cells and whether it holds the peak cell.
func _components(info: Dictionary, level: float) -> Array[Dictionary]:
	var grid: PackedFloat32Array = info["grid"]
	var grid_w: int = info["w"]
	var grid_h: int = info["h"]
	var peak_cell: Vector2i = info["peak_cell"]
	var seen: PackedByteArray = PackedByteArray()
	seen.resize(grid.size())
	var found: Array[Dictionary] = []
	for start: int in grid.size():
		if seen[start] != 0 or grid[start] < level:
			continue
		var stack: PackedInt32Array = PackedInt32Array([start])
		seen[start] = 1
		var area: int = 0
		var low: Vector2i = Vector2i(grid_w, grid_h)
		var high: Vector2i = Vector2i(-1, -1)
		var has_peak: bool = false
		while not stack.is_empty():
			var cell: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			var cx: int = cell % grid_w
			var cy: int = cell / grid_w
			area += 1
			low = Vector2i(mini(low.x, cx), mini(low.y, cy))
			high = Vector2i(maxi(high.x, cx), maxi(high.y, cy))
			has_peak = has_peak or Vector2i(cx, cy) == peak_cell
			for offset: Vector2i in [
				Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
			]:
				var nx: int = cx + offset.x
				var ny: int = cy + offset.y
				if nx < 0 or ny < 0 or nx >= grid_w or ny >= grid_h:
					continue
				var next: int = ny * grid_w + nx
				if seen[next] == 0 and grid[next] >= level:
					seen[next] = 1
					stack.append(next)
		found.append({"area": area, "low": low, "high": high, "has_peak": has_peak})
	return found


## Without `hidden` every metric is taken on `image` (the old normal-frame definition). With
## `hidden` (the same pose, surface hidden) peak, regions and area use the added light, and the
## ring contrast (AC3) uses `image` around the added-light peak.
func _glint_metrics(image: Image, stride: int, hidden: Image = null) -> Dictionary:
	var mask: Dictionary = _water_mask()
	var info: Dictionary = _water_grid(image, mask, stride, hidden)
	var normal_info: Dictionary = info if hidden == null else _water_grid(image, mask, stride)
	var tank_px: float = _front_edge_px()
	var peak: float = info["peak"]
	var cells: int = info["cells"]
	var cell_px_area: float = float(stride * stride)
	var water_px: float = cells * cell_px_area
	var result: Dictionary = {
		"water_mask_px": water_px,
		"tank_width_px": tank_px,
		"glint_peak": peak,
		"stride": stride,
	}
	if peak <= 0.0 or cells == 0:
		result["regions_50"] = []
		result["max_region_px"] = 0.0
		result["max_region_share_of_tank"] = 0.0
		result["area_20_share_of_water"] = 0.0
		result["ring_median"] = -1.0
		result["contrast"] = -1.0
		return result
	var regions: Array[Dictionary] = []
	var widest: float = 0.0
	for component: Dictionary in _components(info, peak * REGION_LEVEL):
		var low: Vector2i = component["low"]
		var high: Vector2i = component["high"]
		var width_px: float = float(high.x - low.x + 1) * stride
		var height_px: float = float(high.y - low.y + 1) * stride
		widest = maxf(widest, maxf(width_px, height_px))
		(
			regions
			. append(
				{
					"width_px": width_px,
					"height_px": height_px,
					"area_px": float(component["area"]) * cell_px_area,
					"share_of_tank": maxf(width_px, height_px) / tank_px,
				}
			)
		)
	var area_cells: int = 0
	var peak_area_cells: int = 0
	for component: Dictionary in _components(info, peak * AREA_LEVEL):
		area_cells += int(component["area"])
		if bool(component["has_peak"]):
			peak_area_cells = int(component["area"])
	var radius_20: float = maxf(sqrt(peak_area_cells * cell_px_area / PI), MIN_RING_RADIUS_PX)
	var ring: Dictionary = _ring(normal_info, info["peak_cell"], radius_20, stride)
	result["regions_50"] = regions
	result["region_count_50"] = regions.size()
	result["max_region_px"] = widest
	result["max_region_share_of_tank"] = widest / tank_px
	result["area_20_px"] = area_cells * cell_px_area
	result["area_20_share_of_water"] = area_cells * cell_px_area / water_px
	result["radius_20_px"] = radius_20
	result["ring_median"] = ring["median"]
	result["ring_cells"] = ring["count"]
	var peak_cell: Vector2i = info["peak_cell"]
	var normal_grid: PackedFloat32Array = normal_info["grid"]
	var normal_at_peak: float = normal_grid[peak_cell.y * int(info["w"]) + peak_cell.x]
	result["normal_at_peak"] = normal_at_peak
	result["contrast"] = normal_at_peak / ring["median"] if ring["median"] > 0.0 else -1.0
	result["peak_xy"] = [peak_cell.x * stride, peak_cell.y * stride]
	result["water_median"] = _median_of_grid(normal_info)
	return result


func _ring(info: Dictionary, peak_cell: Vector2i, radius: float, stride: int) -> Dictionary:
	var grid: PackedFloat32Array = info["grid"]
	var grid_w: int = info["w"]
	var grid_h: int = info["h"]
	var inner: float = 1.5 * radius / stride
	var outer: float = 2.0 * radius / stride
	var values: PackedFloat32Array = PackedFloat32Array()
	var span: int = int(ceilf(outer))
	for cy: int in range(maxi(peak_cell.y - span, 0), mini(peak_cell.y + span + 1, grid_h)):
		for cx: int in range(maxi(peak_cell.x - span, 0), mini(peak_cell.x + span + 1, grid_w)):
			var distance: float = Vector2(cx - peak_cell.x, cy - peak_cell.y).length()
			var value: float = grid[cy * grid_w + cx]
			if value >= 0.0 and distance >= inner and distance <= outer:
				values.append(value)
	if values.is_empty():
		return {"median": 0.0, "count": 0}
	values.sort()
	return {"median": values[values.size() / 2], "count": values.size()}


func _median_of_grid(info: Dictionary) -> float:
	var grid: PackedFloat32Array = info["grid"]
	var values: PackedFloat32Array = PackedFloat32Array()
	for value: float in grid:
		if value >= 0.0:
			values.append(value)
	if values.is_empty():
		return 0.0
	values.sort()
	return values[values.size() / 2]


# --- views ---


func _measure_top(base: String, stride: int) -> Dictionary:
	_freeze_ripple(true)
	_place_camera(TOP_PITCH_DEG, _top_distance)
	_set_bar_visible(false)
	var hidden_image: Image = await _capture_hdr()
	if hidden_image == null:
		return {"ok": false, "problem": "no HDR capture"}
	hidden_image.save_exr(base + "_bar_hidden.exr")
	_surface.visible = false
	var no_surface: Image = await _capture_hdr()
	_surface.visible = true
	if no_surface == null:
		return {"ok": false, "problem": "no HDR capture"}
	no_surface.save_exr(base + "_surface_hidden.exr")
	var result: Dictionary = {"ok": true}
	result["glint"] = _glint_metrics(hidden_image, stride, no_surface)
	result["normal"] = _glint_metrics(hidden_image, stride)
	await _save_tonemapped(base + "_bar_hidden.png")
	_set_bar_visible(true)
	var visible_image: Image = await _capture_hdr()
	visible_image.save_exr(base + "_bar_visible.exr")
	await _save_tonemapped(base + ".png")
	var lamp_rect: Rect2i = _lamp_rect()
	var lamp_peak: float = _rect_peak(visible_image, lamp_rect, hidden_image)
	var frame: Dictionary = _averages(visible_image, _interior_rect())
	result["lamp_rect"] = [
		lamp_rect.position.x, lamp_rect.position.y, lamp_rect.size.x, lamp_rect.size.y
	]
	result["lamp_peak"] = lamp_peak
	result["glint_peak_over_lamp_peak"] = (
		float(result["glint"]["glint_peak"]) / lamp_peak if lamp_peak > 0.0 else -1.0
	)
	result["frame"] = frame
	result["interior_brightest"] = frame["interior_mean"] > frame["rest_mean"]
	result["hdr_unclamped"] = maxf(lamp_peak, float(result["glint"]["glint_peak"])) > 1.0
	result["pose"] = {
		"pitch_deg": TOP_PITCH_DEG, "distance_m": _top_distance, "share": TOP_WIDTH_SHARE
	}
	result["environment"] = _environment_notes()
	## AC2 lamp peak: the emissive strip seen from below (BA decision), measured in the same run.
	var below: Dictionary = await _measure_lamp(base + "_lamp")
	var strip_peak: float = float(below.get("lamp_peak_from_below", 0.0))
	result["lamp_peak_from_below"] = strip_peak
	result["glint_peak_over_lamp_strip_peak"] = (
		float(result["glint"]["glint_peak"]) / strip_peak if strip_peak > 0.0 else -1.0
	)
	result["max_glint_peak_for_ac2"] = strip_peak * 0.25
	return result


func _measure_front(base: String) -> Dictionary:
	_camera.transform = _front_transform
	_freeze_ripple(true)
	_set_bar_visible(true)
	var image: Image = await _capture_hdr()
	if image == null:
		return {"ok": false, "problem": "no HDR capture"}
	image.save_exr(base + ".exr")
	await _save_tonemapped(base + ".png")
	var result: Dictionary = {"ok": true}
	var frame: Dictionary = _averages(image, _interior_rect())
	result["frame"] = frame
	result["interior_brightest"] = frame["interior_mean"] > frame["rest_mean"]
	result["frame_mean_all"] = (
		(
			frame["interior_mean"] * _interior_rect().get_area()
			+ frame["rest_mean"] * (WIDTH * HEIGHT - _interior_rect().get_area())
		)
		/ (WIDTH * HEIGHT)
	)
	var lamp_rect: Rect2i = _lamp_rect()
	result["lamp_rect"] = [
		lamp_rect.position.x, lamp_rect.position.y, lamp_rect.size.x, lamp_rect.size.y
	]
	result["lamp_peak_in_rect"] = _rect_peak(image, lamp_rect, null)
	result["hdr_unclamped"] = result["lamp_peak_in_rect"] > 1.0
	return result


## The bar seen from below and in front, ripple frozen: its brightest side. The peak is taken over
## the pixels that change when the bar is hidden.
func _measure_lamp(base: String) -> Dictionary:
	_freeze_ripple(true)
	var center: Vector3 = _lamp_bar.global_transform * _lamp_bar.mesh.get_aabb().get_center()
	_camera.position = center + Vector3(0.0, -0.25, 0.9)
	_camera.look_at(center)
	_camera.force_update_transform()
	_set_bar_visible(false)
	var hidden_image: Image = await _capture_hdr()
	_set_bar_visible(true)
	var visible_image: Image = await _capture_hdr()
	if hidden_image == null or visible_image == null:
		return {"ok": false, "problem": "no HDR capture"}
	visible_image.save_exr(base + ".exr")
	await _save_tonemapped(base + ".png")
	var lamp_rect: Rect2i = _lamp_rect()
	var peak: float = _rect_peak(visible_image, lamp_rect, hidden_image)
	return {
		"ok": true,
		"lamp_rect":
		[lamp_rect.position.x, lamp_rect.position.y, lamp_rect.size.x, lamp_rect.size.y],
		"lamp_peak_from_below": peak,
		"hdr_unclamped": peak > 1.0
	}


## AC4: live ripple for ORBIT_SECONDS; the camera orbits when `orbit` is true, else it holds the
## top pose (the calm-ripple baseline). One CSV row per captured frame.
func _measure_live(base: String, stride: int, orbit: bool) -> Dictionary:
	_freeze_ripple(false)
	_set_bar_visible(false)
	_measure_mode(true)
	await _settle()
	var rows: Array[Dictionary] = []
	var csv: FileAccess = FileAccess.open(base + ".csv", FileAccess.WRITE)
	csv.store_line("t_s,pitch_deg,peak,max_region_px,max_region_share,area20_share,contrast")
	var start: int = Time.get_ticks_msec()
	var elapsed: float = 0.0
	while elapsed <= ORBIT_SECONDS:
		var phase: float = (1.0 - cos(TAU * elapsed / ORBIT_SECONDS)) / 2.0 if orbit else 0.0
		var pitch: float = lerpf(TOP_PITCH_DEG, ORBIT_LOW_PITCH_DEG, phase)
		_place_camera(pitch, _top_distance)
		var image: Image = await _capture()
		_surface.visible = false
		var no_surface: Image = await _capture()
		_surface.visible = true
		var metrics: Dictionary = _glint_metrics(image, stride, no_surface)
		metrics["t_s"] = elapsed
		metrics["pitch_deg"] = pitch
		rows.append(metrics)
		(
			csv
			. store_line(
				(
					"%.3f,%.2f,%.5f,%.1f,%.5f,%.6f,%.3f"
					% [
						elapsed,
						pitch,
						metrics["glint_peak"],
						metrics["max_region_px"],
						metrics["max_region_share_of_tank"],
						metrics["area_20_share_of_water"],
						metrics["contrast"],
					]
				)
			)
		)
		elapsed = (Time.get_ticks_msec() - start) / 1000.0
	csv.close()
	return _live_summary(rows, orbit)


func _live_summary(rows: Array[Dictionary], orbit: bool) -> Dictionary:
	var peaks: PackedFloat64Array = PackedFloat64Array()
	var max_share: float = 0.0
	var max_area: float = 0.0
	var min_contrast: float = INF
	for row: Dictionary in rows:
		peaks.append(row["glint_peak"])
		max_share = maxf(max_share, row["max_region_share_of_tank"])
		max_area = maxf(max_area, row["area_20_share_of_water"])
		min_contrast = minf(min_contrast, row["contrast"])
	var mean: float = 0.0
	for value: float in peaks:
		mean += value
	mean /= maxf(peaks.size(), 1.0)
	var variance: float = 0.0
	var largest_step: float = 0.0
	var peak_max: float = 0.0
	var peak_min: float = INF
	for index: int in peaks.size():
		peak_max = maxf(peak_max, peaks[index])
		peak_min = minf(peak_min, peaks[index])
		variance += (peaks[index] - mean) * (peaks[index] - mean)
		if index > 0:
			largest_step = maxf(largest_step, absf(peaks[index] - peaks[index - 1]))
	var deviation: float = sqrt(variance / maxf(peaks.size(), 1.0))
	return {
		"ok": not rows.is_empty(),
		"mode": "orbit" if orbit else "shimmer",
		"frames": rows.size(),
		"peak_mean": mean,
		"peak_std": deviation,
		"peak_cv": deviation / mean if mean > 0.0 else -1.0,
		"largest_step_abs": largest_step,
		"largest_step_rel_of_mean": largest_step / mean if mean > 0.0 else -1.0,
		"peak_max": peak_max,
		"peak_min": peak_min if peak_min < INF else 0.0,
		"max_region_share_of_tank": max_share,
		"max_area_20_share_of_water": max_area,
		"min_contrast": min_contrast if min_contrast < INF else -1.0,
	}


func _environment_notes() -> Dictionary:
	var stock: Environment = Environment.new()
	return {
		"glow_threshold_default": stock.glow_hdr_threshold,
		"glow_intensity_default": stock.glow_intensity,
		"glow_strength_default": stock.glow_strength,
		"glow_bloom_default": stock.glow_bloom,
		"glow_hdr_scale_default": stock.glow_hdr_luminance_cap,
		"stored_glow_enabled": _original_glow,
		"stored_tonemap_mode": _original_tonemap,
	}
