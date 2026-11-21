extends Node3D
## Dev-only preview of the decor item tint (#32): the first colourable catalog item in its original
## look and in every swatch of its catalog definition, in the real room and the lighting of any
## tank. Not referenced by any game scene. It sets the `item_tint` instance shader parameter on the
## drawn item geometry directly (the value PlacedItemsView sets: the swatch rgb with alpha 1, alpha
## 0 for the original look), so it does not depend on the recolour command or the item view. Item
## ids come from the catalog, never from this file; items enter the preview model through
## PlaceItemCommand.
##
## Jobs: with user://item_tint_preview.json (a list of {"tank", "set", "view", "out"}) every job is
## rendered at 1920 x 1080 and saved to "out" (PNG, absolute path), then the scene quits. Without
## the file one job comes from the command line (after "--": --tank=tank_small_1 --set=a
## --view=front) and stays open.
## Sets: "a" (original, swatches 1 to 3), "b" (swatches 4 to 6, original), "plain" (every catalog
## item untinted: the #157 look must not change). Views: "front" (through the front glass, the row
## fills the width), "close" (the first two items from above the rim) and "room" (the room's own
## default framing).
## Check jobs render in a SubViewport of their own (no TAA, the SubViewport default, so two renders
## of the same scene are pixel-identical):
## - "calibrate" ({"set": "calibrate", "out"}) draws, unshaded, each swatch twice: as a
##   StandardMaterial3D albedo (Godot's sRGB to linear conversion) and through decor_item.gdshader
##   with the tint set as a Color instance parameter. It prints the largest 8-bit difference of the
##   two rows (0: the 3D colour equals the swatch colour, so the shader must not convert the tint
##   itself) and sets item_tint on a quad whose overlay (the selection material) does not declare
##   it, which must log nothing.
## - "parity" ({"set": "parity", "shader": "old" or "new", "out"}) draws every catalog item under
##   one directional light through an orthographic camera, with the old material
##   (palette_atlas.gdshader and the decor parameters) or the shipped decor material with item_tint
##   alpha 0. A "new" job after an "old" job prints how many pixels differ (0: the untinted look is
##   exactly the #157 look).
##
## Selection mark and refusal cue jobs (#33 AC 15 d):
## - "mark" on a room job: "selection" puts the selection material on every item as
##   material_overlay (the selected look), "cue" puts a copy of it with the uniforms of "cue"
##   ({"strength", "power", "colour" [r, g, b] sRGB, "lift" [r, g, b] linear}), the frame of the
##   refusal cue at one step. "glow_shader" (absolute path of a .gdshader file) replaces the shader
##   of that overlay, for the look before a shader change.
## - Set "fixtures": the colourable item once per entry of "tints" (a list of sRGB [r, g, b]).
##   Five fit every tank: on a tank too narrow for the usual row spacing the row closes up (see
##   ROW_REACH_M), so only the small tank frames differ from the medium and large ones.
## - "proof" ({"set": "proof", "items", "tank", "view", "before", "after", "out_before", "out"})
##   renders the room three times in the same frame, each in a SubViewport of its own (no TAA, the
##   same shader TIME, so the three differ only in the overlay): unmarked, marked with the shader
##   at "before" and marked with the shader at "after" (a path; empty for the shipped shader). It
##   prints the rim pixels (unmarked vs before) and the largest 8-bit channel difference of before
##   vs after (the default selection look must not change).

const JOB_FILE: String = "user://item_tint_preview.json"
const ROOM_SCENE: String = "res://scenes/room/room_corner.tscn"
const DECOR_SHADER: String = "res://shaders/decor_item.gdshader"
const OLD_SHADER: String = "res://shaders/palette_atlas.gdshader"
const DECOR_MATERIAL: String = "res://assets/items/materials/decor_palette.tres"
const SELECTION_MATERIAL: String = "res://scenes/tank/items/item_selection_material.tres"
## Uniforms of the selection glow that a cue job sets.
const STRENGTH_PARAM: StringName = &"fresnel_strength"
const POWER_PARAM: StringName = &"fresnel_power"
const COLOUR_PARAM: StringName = &"glow_colour"
const LIFT_PARAM: StringName = &"glow_lift"
const TINT_PARAM: StringName = &"item_tint"
const SHOT_SIZE: Vector2i = Vector2i(1920, 1080)
## Frames between staging a job and saving it (TAA and shadows settle).
const SETTLE_FRAMES: int = 48
const FOV_DEG: float = 50.0
const NEAR_M: float = 0.03
## Centre distance of the items in a row, metres (the amphora is 9 cm wide).
const SPACING_M: float = 0.1
## Rows of the tinted sets (a, b): centre distance in x and the zigzag in z, metres. Four amphoras
## turned by TURN_DEG must fit the small tank (0.40 x 0.25 m) under the footprint rule (#33).
const ROW_SPACING_M: float = 0.09
const ROW_ZIGZAG_M: float = 0.04
## Half the x extent of an amphora turned by TURN_DEG (9 x 8 cm footprint: 5.8 cm) plus a margin,
## metres: a row centre stays this far inside the interior wall, and on a narrow tank the row
## spacing shrinks below ROW_SPACING_M to keep it so (five fixtures on the small tank: 7 cm).
const ROW_REACH_M: float = 0.06
## Turn of every item, degrees, so the amphora handles read in the front view.
const TURN_DEG: float = 25.0
## "plain" set: tank-local spots by catalog order (category, then id), so a long piece of wood
## lies behind the others instead of through them; more items continue the row.
const PLAIN_SPOTS: Array[Vector3] = [
	Vector3(-0.13, 0.0, 0.05), Vector3(0.05, 0.0, -0.03), Vector3(0.04, 0.0, 0.06)
]
## Parity job: the view is 0.6 m wide; items sit this far apart from the left.
const PARITY_WIDTH_M: float = 0.6
const PARITY_STEP_M: float = 0.19

var _jobs: Array[Dictionary] = []
var _batch: bool = false
var _stage_root: Node = null
## The SubViewport of a check job; null for a room job (the window is captured).
var _check_viewport: SubViewport = null
## The last image of an "old" parity job.
var _parity_reference: Image = null
## The SubViewports of a proof job: unmarked, before, after; empty for any other job.
var _proof_viewports: Array[SubViewport] = []


func _ready() -> void:
	_jobs = _read_jobs()
	if _batch:
		get_window().size = SHOT_SIZE
	_run()


func _read_jobs() -> Array[Dictionary]:
	var jobs: Array[Dictionary] = []
	if FileAccess.file_exists(JOB_FILE):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(JOB_FILE))
		if parsed is Array:
			for entry: Variant in parsed:
				if entry is Dictionary:
					jobs.append(entry)
		_batch = not jobs.is_empty()
	if jobs.is_empty():
		var job: Dictionary = {}
		for argument: String in OS.get_cmdline_user_args():
			if argument.begins_with("--") and argument.contains("="):
				var parts: PackedStringArray = argument.substr(2).split("=", true, 1)
				job[parts[0]] = parts[1]
		jobs.append(job)
	return jobs


func _run() -> void:
	for job: Dictionary in _jobs:
		var set_id: String = str(job.get("set", "a"))
		var old: bool = str(job.get("shader", "new")) == "old"
		if set_id == "calibrate":
			_stage_calibration()
		elif set_id == "parity":
			_stage_parity(old)
		elif set_id == "proof":
			_stage_proof(job)
		else:
			_stage(job)
		if not _batch:
			return
		for _frame: int in SETTLE_FRAMES:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		if set_id == "proof":
			_report_proof(job)
			continue
		var image: Image = null
		if _check_viewport != null:
			image = _check_viewport.get_texture().get_image()
		else:
			image = get_viewport().get_texture().get_image()
		if set_id == "calibrate":
			_report_calibration(image)
		elif set_id == "parity":
			_report_parity(image, old)
		var out: String = str(job.get("out", ""))
		if not out.is_empty():
			DirAccess.make_dir_recursive_absolute(out.get_base_dir())
			image.save_png(out)
			print("item tint preview: saved %s" % out)
	get_tree().quit()


func _clear_stage() -> void:
	if _stage_root != null:
		remove_child(_stage_root)
		_stage_root.queue_free()
		_stage_root = null
	_check_viewport = null
	_proof_viewports.clear()


## Every catalog item, by category and then id.
func _ordered(catalog: ItemCatalog) -> Array[ItemDefinition]:
	var list: Array[ItemDefinition] = []
	for id: StringName in catalog.get_ids():
		list.append(catalog.get_definition(id))
	list.sort_custom(
		func(a: ItemDefinition, b: ItemDefinition) -> bool:
			if a.category != b.category:
				return a.category < b.category
			return String(a.id) < String(b.id)
	)
	return list


## The first colourable catalog item that has swatches; null when there is none.
func _colourable(catalog: ItemCatalog) -> ItemDefinition:
	for definition: ItemDefinition in _ordered(catalog):
		if definition.colourable and not definition.colour_swatches.is_empty():
			return definition
	return null


## Builds the room with the items of one job, tints and marks them and places the camera.
func _stage(job: Dictionary) -> void:
	_clear_stage()
	_stage_root = _build_room(job, self)


## The room of a job as a child of `parent`; null when the tank or the item is unknown.
func _build_room(job: Dictionary, parent: Node) -> Node3D:
	var tank_id: StringName = StringName(str(job.get("tank", "tank_small_1")))
	var tanks: TankCatalog = TankCatalog.load_dir()
	var tank: TankDefinition = tanks.get_definition(tank_id)
	var source: ItemCatalogSource = ItemCatalogSource.new()
	var subject: ItemDefinition = _colourable(source.get_catalog())
	if tank == null or subject == null:
		push_error("item tint preview: unknown tank %s or no colourable item" % tank_id)
		return null
	var model: AquariumModel = AquariumModel.new()
	if model.get_tank_id() != tank_id:
		ChangeTankCommand.new(model, tanks, tank_id).do()
	var rules: PlacementRules = PlacementRules.new(tanks, source, SubstrateCatalog.load_dir())
	var entries: Array[Dictionary] = _entries(
		str(job.get("set", "a")),
		source.get_catalog(),
		job.get("tints", []) as Array,
		tank.interior_size_m.x
	)
	for index: int in entries.size():
		var item: PlacedItem = PlacedItem.new()
		item.uid = "%08x" % (0x7a000000 + index)
		item.catalog_id = entries[index]["id"]
		var row_x: float = (index - (entries.size() - 1) / 2.0) * SPACING_M
		item.position = entries[index].get("at", Vector3(row_x, 0.0, 0.0))
		item.rotation_y = TURN_DEG
		item.has_colour = entries[index]["tinted"]
		item.colour = entries[index]["colour"]
		if not PlaceItemCommand.new(model, item, rules).do():
			push_error(
				"item tint preview: %s does not fit at %s" % [item.catalog_id, item.position]
			)
	var room: Node3D = (load(ROOM_SCENE) as PackedScene).instantiate() as Node3D
	room.call("setup", model, tanks, null, null, null, null, source)
	parent.add_child(room)
	var view: PlacedItemsView = _find_view(room)
	if view == null:
		push_error("item tint preview: the room has no PlacedItemsView")
		return room
	var overlay: Material = _overlay(job)
	var centres: Array[Vector3] = []
	for item: PlacedItem in model.get_items():
		var node: Node3D = view.get_node_for(item.uid)
		if node == null:
			continue
		centres.append(node.position)
		var tint: Color = Color(0.0, 0.0, 0.0, 0.0)
		if item.has_colour:
			tint = Color(item.colour.r, item.colour.g, item.colour.b, 1.0)
		for geometry: GeometryInstance3D in PlacedItemsView.geometry_of(node):
			geometry.set_instance_shader_parameter(TINT_PARAM, tint)
			if overlay != null:
				geometry.material_overlay = overlay
	_aim(room, view, str(job.get("view", "front")), centres)
	return room


## The overlay of a job's "mark" (see the header); null for no mark.
func _overlay(job: Dictionary) -> Material:
	var mark: String = str(job.get("mark", ""))
	if mark != "selection" and mark != "cue":
		return null
	var material: ShaderMaterial = load(SELECTION_MATERIAL) as ShaderMaterial
	var shader_path: String = str(job.get("glow_shader", ""))
	if mark == "selection" and shader_path.is_empty():
		return material
	material = material.duplicate() as ShaderMaterial
	if not shader_path.is_empty():
		var shader: Shader = Shader.new()
		shader.code = FileAccess.get_file_as_string(shader_path)
		material.shader = shader
	if mark == "cue":
		var cue: Dictionary = job.get("cue", {}) as Dictionary
		material.set_shader_parameter(STRENGTH_PARAM, float(cue.get("strength", 0.7)))
		material.set_shader_parameter(POWER_PARAM, float(cue.get("power", 1.6)))
		var colour: Array = cue.get("colour", [1.0, 0.86, 0.62]) as Array
		material.set_shader_parameter(
			COLOUR_PARAM, Color(float(colour[0]), float(colour[1]), float(colour[2]), 1.0)
		)
		var lift: Array = cue.get("lift", [0.0, 0.0, 0.0]) as Array
		material.set_shader_parameter(
			LIFT_PARAM, Vector3(float(lift[0]), float(lift[1]), float(lift[2]))
		)
	return material


## Three rooms of the same job in SubViewports of their own (see the header).
func _stage_proof(job: Dictionary) -> void:
	_clear_stage()
	var holder: Node = Node.new()
	holder.name = "Proof"
	add_child(holder)
	_stage_root = holder
	var variants: Array[Dictionary] = [
		{"mark": ""},
		{"mark": "selection", "glow_shader": str(job.get("before", ""))},
		{"mark": "selection", "glow_shader": str(job.get("after", ""))},
	]
	for variant: Dictionary in variants:
		var port: SubViewport = SubViewport.new()
		port.size = SHOT_SIZE
		port.own_world_3d = true
		port.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		holder.add_child(port)
		_proof_viewports.append(port)
		var room_job: Dictionary = job.duplicate()
		room_job["set"] = str(job.get("items", "plain"))
		room_job.merge(variant, true)
		_build_room(room_job, port)


func _report_proof(job: Dictionary) -> void:
	var images: Array[Image] = []
	for port: SubViewport in _proof_viewports:
		var image: Image = port.get_texture().get_image()
		image.convert(Image.FORMAT_RGB8)
		images.append(image)
	var rim: Vector2i = _byte_difference(images[0], images[1])
	var change: Vector2i = _byte_difference(images[1], images[2])
	print(
		(
			"selection proof %s: %d rim pixels; before vs after: %d pixels differ, largest %d/255"
			% [str(job.get("out", "")).get_file(), rim.x, change.x, change.y]
		)
	)
	_save(images[1], str(job.get("out_before", "")))
	_save(images[2], str(job.get("out", "")))


func _save(image: Image, out: String) -> void:
	if out.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	image.save_png(out)
	print("item tint preview: saved %s" % out)


## Pixels that differ and the largest 8-bit channel difference of two RGB8 images.
func _byte_difference(a: Image, b: Image) -> Vector2i:
	var first: PackedByteArray = a.get_data()
	var second: PackedByteArray = b.get_data()
	if first.size() != second.size():
		return Vector2i(-1, -1)
	var pixels: int = 0
	var largest: int = 0
	for index: int in range(0, first.size(), 3):
		var worst: int = 0
		for channel: int in 3:
			worst = maxi(worst, absi(first[index + channel] - second[index + channel]))
		if worst > 0:
			pixels += 1
			largest = maxi(largest, worst)
	return Vector2i(pixels, largest)


## The items of a set: {"id", "tinted", "colour"} in row order, left to right; "at" (tank-local,
## metres) replaces the row position where the items would overlap. `interior_width_m` closes up
## the row of a narrow tank (see ROW_REACH_M); the default leaves ROW_SPACING_M as it is.
func _entries(
	set_id: String, catalog: ItemCatalog, tints: Array, interior_width_m: float = INF
) -> Array[Dictionary]:
	var subject: ItemDefinition = _colourable(catalog)
	var swatches: Array[Color] = subject.colour_swatches
	var original: Dictionary = {"id": subject.id, "tinted": false, "colour": Color.WHITE}
	var list: Array[Dictionary] = []
	match set_id:
		"plain":
			var ordered: Array[ItemDefinition] = _ordered(catalog)
			for index: int in ordered.size():
				var entry: Dictionary = {
					"id": ordered[index].id, "tinted": false, "colour": Color.WHITE
				}
				if index < PLAIN_SPOTS.size():
					entry["at"] = PLAIN_SPOTS[index]
				list.append(entry)
		"fixtures":
			for tint: Variant in tints:
				var rgb: Array = tint as Array
				var colour: Color = Color(float(rgb[0]), float(rgb[1]), float(rgb[2]))
				list.append({"id": subject.id, "tinted": true, "colour": colour})
		"b":
			for index: int in range(3, mini(6, swatches.size())):
				list.append({"id": subject.id, "tinted": true, "colour": swatches[index]})
			list.append(original)
		_:
			list.append(original)
			for index: int in range(0, mini(3, swatches.size())):
				list.append({"id": subject.id, "tinted": true, "colour": swatches[index]})
	if set_id != "plain":
		var spacing: float = ROW_SPACING_M
		if list.size() > 1:
			var reach: float = interior_width_m / 2.0 - ROW_REACH_M
			spacing = minf(spacing, 2.0 * reach / (list.size() - 1))
		for index: int in list.size():
			var row_x: float = (index - (list.size() - 1) / 2.0) * spacing
			var zigzag: float = ROW_ZIGZAG_M if index % 2 == 0 else -ROW_ZIGZAG_M
			list[index]["at"] = Vector3(row_x, 0.0, zigzag)
	return list


func _find_view(root: Node) -> PlacedItemsView:
	for child: Node in root.find_children("*", "Node3D", true, false):
		if child is PlacedItemsView:
			return child as PlacedItemsView
	return null


## Places the build camera; "room" keeps the room's own framing.
func _aim(room: Node3D, view: PlacedItemsView, view_name: String, centres: Array[Vector3]) -> void:
	var camera: Camera3D = room.get_node_or_null("BuildCamera") as Camera3D
	if camera == null or centres.is_empty() or view_name == "room":
		return
	var low: Vector3 = centres[0]
	var high: Vector3 = centres[0]
	for centre: Vector3 in centres:
		low = low.min(centre)
		high = high.max(centre)
	var middle: Vector3 = (low + high) / 2.0
	var eye: Vector3
	var target: Vector3
	if view_name == "close":
		# the first two items from above the rim, so the glaze, the rim and the dark inside show
		var pair: Vector3 = (centres[0] + centres[mini(1, centres.size() - 1)]) / 2.0
		target = pair + Vector3(0.0, 0.08, 0.0)
		eye = pair + Vector3(0.0, 0.3, 0.3)
	else:
		var half_width: float = (high.x - low.x) / 2.0 + 0.07
		var distance: float = half_width / tan(deg_to_rad(FOV_DEG / 2.0))
		target = middle + Vector3(0.0, 0.065, 0.0)
		eye = middle + Vector3(0.0, 0.1, distance)
	camera.process_mode = Node.PROCESS_MODE_DISABLED
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.fov = FOV_DEG
	camera.near = NEAR_M
	var forward: Vector3 = (target - eye).normalized()
	var local: Transform3D = Transform3D(Basis.looking_at(forward, Vector3.UP), eye)
	camera.global_transform = view.global_transform * local


## A SubViewport with a world of its own: black background, linear tonemapping, one directional
## light without shadows and an orthographic camera `width_m` wide. Returns the root to fill.
func _check_stage(width_m: float) -> Node3D:
	_clear_stage()
	var port: SubViewport = SubViewport.new()
	port.name = "CheckViewport"
	port.size = SHOT_SIZE
	port.own_world_3d = true
	port.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(port)
	_stage_root = port
	_check_viewport = port
	var root: Node3D = Node3D.new()
	root.name = "CheckStage"
	port.add_child(root)
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color.BLACK
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = environment
	root.add_child(world)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-40.0), deg_to_rad(30.0), 0.0)
	sun.shadow_enabled = false
	root.add_child(sun)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = width_m
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	camera.position = Vector3(0.0, 0.0, 2.0)
	camera.current = true
	root.add_child(camera)
	return root


## The untinted look against #157 (see the header): every item uses the old material when `old`,
## else the shipped decor material with item_tint alpha 0 set explicitly.
func _stage_parity(old: bool) -> void:
	var root: Node3D = _check_stage(PARITY_WIDTH_M)
	var material: ShaderMaterial = null
	if old:
		material = (load(DECOR_MATERIAL) as ShaderMaterial).duplicate() as ShaderMaterial
		material.shader = load(OLD_SHADER) as Shader
	var ordered: Array[ItemDefinition] = _ordered(ItemCatalogSource.new().get_catalog())
	for index: int in ordered.size():
		if ordered[index].scene == null:
			continue
		var node: Node3D = ordered[index].scene.instantiate() as Node3D
		var x: float = -PARITY_WIDTH_M / 2.0 + 0.11 + index * PARITY_STEP_M
		node.position = Vector3(x, -0.05, 0.0)
		node.rotation = Vector3(0.0, deg_to_rad(TURN_DEG), 0.0)
		root.add_child(node)
		for geometry: GeometryInstance3D in PlacedItemsView.geometry_of(node):
			if old:
				geometry.material_override = material
			else:
				geometry.set_instance_shader_parameter(TINT_PARAM, Color(0.0, 0.0, 0.0, 0.0))


func _report_parity(image: Image, old: bool) -> void:
	if old:
		_parity_reference = image
		return
	if _parity_reference == null or _parity_reference.get_size() != image.get_size():
		print("item tint parity: no old render of the same size to compare with")
		return
	var differing: int = 0
	var drawn: int = 0
	for y: int in image.get_height():
		for x: int in image.get_width():
			var reference: Color = _parity_reference.get_pixel(x, y)
			if reference.get_luminance() > 0.0:
				drawn += 1
			if reference.to_rgba32() != image.get_pixel(x, y).to_rgba32():
				differing += 1
	print("item tint parity: %d drawn pixels, %d differ from the old shader" % [drawn, differing])


## Two rows of unshaded quads per swatch (see the header) and the overlay case below them.
func _stage_calibration() -> void:
	var root: Node3D = _check_stage(9.0)
	var code: String = (load(DECOR_SHADER) as Shader).code
	var unshaded: Shader = Shader.new()
	unshaded.code = code.replace("render_mode cull_back;", "render_mode cull_back, unshaded;")
	var swatches: Array[Color] = _calibration_colours()
	for index: int in swatches.size():
		var x: float = _calibration_x(index, swatches.size())
		var plain: StandardMaterial3D = StandardMaterial3D.new()
		plain.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		plain.albedo_color = swatches[index]
		_quad(root, Vector3(x, 1.5, 0.0), plain, swatches[index])
		_quad(root, Vector3(x, 0.0, 0.0), _shader_material(unshaded), swatches[index])
	# the selection overlay does not declare item_tint: setting it must log nothing
	var marked: MeshInstance3D = _quad(
		root, Vector3(0.0, -1.5, 0.0), _shader_material(unshaded), swatches[0]
	)
	marked.material_overlay = load(SELECTION_MATERIAL) as Material
	marked.set_instance_shader_parameter(TINT_PARAM, Color(swatches[0], 1.0))


## The swatches of the colourable item, then the atlas terracotta of the original look.
func _calibration_colours() -> Array[Color]:
	var list: Array[Color] = []
	var subject: ItemDefinition = _colourable(ItemCatalogSource.new().get_catalog())
	if subject != null:
		list.assign(subject.colour_swatches)
	list.append(Color8(176, 112, 79))
	return list


func _calibration_x(index: int, count: int) -> float:
	return (index - (count - 1) / 2.0) * 1.2


func _shader_material(shader: Shader) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("vertex_shade", 1.0)
	return material


func _quad(root: Node3D, at: Vector3, material: Material, colour: Color) -> MeshInstance3D:
	var quad: MeshInstance3D = MeshInstance3D.new()
	var mesh: QuadMesh = QuadMesh.new()
	mesh.size = Vector2(1.0, 1.0)
	quad.mesh = mesh
	quad.material_override = material
	quad.position = at
	root.add_child(quad)
	quad.set_instance_shader_parameter(TINT_PARAM, Color(colour.r, colour.g, colour.b, 1.0))
	return quad


func _report_calibration(image: Image) -> void:
	var camera: Camera3D = _check_viewport.get_camera_3d()
	var swatches: Array[Color] = _calibration_colours()
	var worst: float = 0.0
	for index: int in swatches.size():
		var x: float = _calibration_x(index, swatches.size())
		var reference: Color = _pixel(image, camera, Vector3(x, 1.5, 0.0))
		var drawn: Color = _pixel(image, camera, Vector3(x, 0.0, 0.0))
		worst = maxf(worst, _difference(reference, drawn))
		print(
			(
				"item tint calibration: #%s albedo #%s shader #%s"
				% [swatches[index].to_html(false), reference.to_html(false), drawn.to_html(false)]
			)
		)
	print("item tint calibration: worst 8-bit difference %d" % roundi(worst * 255.0))


func _pixel(image: Image, camera: Camera3D, at: Vector3) -> Color:
	var point: Vector2 = camera.unproject_position(at)
	return image.get_pixel(int(point.x), int(point.y))


func _difference(a: Color, b: Color) -> float:
	return maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
