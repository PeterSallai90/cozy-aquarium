extends Node3D
## Dev-only preview of the substrate bed (#28): any tank x type x swatch x view, with an optional
## scale card (4 cm x 1 cm, 1 mm ticks). Not referenced by any game scene.
##
## It shows the real room with the tank of the job and puts its own SubstrateBedView under the
## SubstrateAnchor (synchronous assemble and build_all; a bed the room made is hidden). It writes
## nothing to the model: the tank is chosen with a ChangeTankCommand on a model of its own, and
## the depth of the bed comes from the baked data.
##
## Jobs: with user://substrate_preview.json (a list of {"tank", "type", "swatch", "view", "card",
## "out"}) every job is rendered at 1920 x 1080 and saved to "out" (PNG, absolute path), then the
## scene quits. Without the file one job comes from the command line (after "--":
## --tank=tank_large_1 --type=sand_fine --swatch=1 --view=default --card=none) and stays open.
## Views: "default" (the room's framing) and the close-ups of ADR 0011 rule 17. Cards: "none",
## "glass" (standing against the front pane) or "top" (lying on the bed).

const JOB_FILE: String = "user://substrate_preview.json"
const ROOM_SCENE: String = "res://scenes/room/room_corner.tscn"
const LOOK_PATH: String = "res://assets/substrate/looks/%s.tres"
const SHOT_SIZE: Vector2i = Vector2i(1920, 1080)
## Frames between staging a job and saving it (TAA and shadows settle).
const SETTLE_FRAMES: int = 48
const FOV_DEG: float = 50.0
const NEAR_M: float = 0.03
const CARD_SIZE_M: Vector2 = Vector2(0.04, 0.01)

var _jobs: Array[Dictionary] = []
var _batch: bool = false
var _room: Node3D = null
var _view: SubstrateBedView = null
var _camera: Camera3D = null


func _ready() -> void:
	_jobs = _read_jobs()
	if _batch:
		get_window().size = SHOT_SIZE
	_run()


func _process(_delta: float) -> void:
	if _view != null and _camera != null:
		_view.update_lod(_view.to_local(_camera.global_position))


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
		_stage(job)
		if not _batch:
			return
		for _frame: int in SETTLE_FRAMES:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var out: String = str(job.get("out", ""))
		if not out.is_empty():
			DirAccess.make_dir_recursive_absolute(out.get_base_dir())
			get_viewport().get_texture().get_image().save_png(out)
			print("substrate preview: saved %s" % out)
	get_tree().quit()


## Builds the room, the bed and the camera of one job.
func _stage(job: Dictionary) -> void:
	if _room != null:
		remove_child(_room)
		_room.queue_free()
		_view = null
		_camera = null
	var tank_id: StringName = StringName(str(job.get("tank", "tank_large_1")))
	var substrate_id: StringName = StringName(str(job.get("type", "sand_fine")))
	var tanks: TankCatalog = TankCatalog.load_dir()
	var tank: TankDefinition = tanks.get_definition(tank_id)
	var look: SubstrateBedLook = load(LOOK_PATH % substrate_id) as SubstrateBedLook
	if tank == null or look == null:
		push_error("substrate preview: unknown tank %s or type %s" % [tank_id, substrate_id])
		return
	var model: AquariumModel = AquariumModel.new()
	if model.get_tank_id() != tank_id:
		ChangeTankCommand.new(model, tanks, tank_id).do()
	_room = (load(ROOM_SCENE) as PackedScene).instantiate() as Node3D
	_room.call("setup", model, tanks)
	add_child(_room)
	var anchor: Node3D = _room.get_node_or_null("Tank/SubstrateAnchor") as Node3D
	if anchor == null:
		push_error("substrate preview: the room shows no tank with a SubstrateAnchor")
		return
	for child: Node in anchor.get_children():
		if child is Node3D:
			(child as Node3D).visible = false
	var bake: SubstrateBakeData = SubstrateBakeData.load_file(look.bake_path_for(tank_id))
	if bake == null:
		return
	var depth: float = bake.depth_m()
	var input: SubstrateAssemblyInput = SubstrateAssemblyInput.create(
		tank_id, substrate_id, tank.interior_size_m, depth, look
	)
	_view = SubstrateBedView.new()
	_view.name = "PreviewBed"
	anchor.add_child(_view)
	_view.begin(SubstrateAssembler.assemble(input, bake), look)
	_view.build_all()
	_view.set_tint(_swatch(substrate_id, int(str(job.get("swatch", "1")))))
	_camera = _room.get_node_or_null("BuildCamera") as Camera3D
	var view_name: String = str(job.get("view", "default"))
	var pose: Array[Vector3] = _pose(view_name, tank, depth)
	if _camera != null and not pose.is_empty():
		_camera.process_mode = Node.PROCESS_MODE_DISABLED
		_camera.keep_aspect = Camera3D.KEEP_WIDTH
		_camera.fov = FOV_DEG
		_camera.near = NEAR_M
		var forward: Vector3 = (pose[1] - pose[0]).normalized()
		var up: Vector3 = Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.999 else Vector3.BACK
		var local: Transform3D = Transform3D(Basis.looking_at(forward, up), pose[0])
		_camera.global_transform = anchor.global_transform * local
	_add_card(str(job.get("card", "none")), anchor, tank, depth)


## Swatch `number` (1 = the default) of a type; white when the catalog has none.
func _swatch(substrate_id: StringName, number: int) -> Color:
	var definition: SubstrateDefinition = SubstrateCatalog.load_dir().get_definition(substrate_id)
	if definition == null:
		return Color.WHITE
	var index: int = clampi(number - 1, 0, definition.colour_swatches.size() - 1)
	if definition.colour_swatches.is_empty():
		return definition.default_colour
	return definition.colour_swatches[index]


## Camera position and target of a close-up view in the tank frame (ADR 0011 rule 17); empty for
## "default" and unknown names (the room keeps its own framing).
func _pose(view_name: String, tank: TankDefinition, h: float) -> Array[Vector3]:
	var g: float = tank.glass_thickness_m
	var z_f: float = tank.interior_size_m.z / 2.0
	var o: float = z_f + g
	var half_x: float = tank.interior_size_m.x / 2.0
	var poses: Dictionary[String, Array] = {
		"glass_close_front": [Vector3(0.1, 0.8 * h, o + 0.12), Vector3(0.1, 0.42 * h, z_f)],
		"glass_close_back": [Vector3(-0.1, 0.8 * h, -o - 0.12), Vector3(-0.1, 0.42 * h, -z_f)],
		"glass_close_left":
		[Vector3(-half_x - g - 0.12, 0.8 * h, 0.0), Vector3(-half_x, 0.42 * h, 0.0)],
		"glass_close_right":
		[Vector3(half_x + g + 0.12, 0.8 * h, 0.0), Vector3(half_x, 0.42 * h, 0.0)],
		"glass_35": [Vector3(0.1, h + 0.045, o + 0.35), Vector3(0.1, 0.45 * h, z_f)],
		"top_35": [Vector3(0.1, h + 0.35, 0.02), Vector3(0.1, h, -0.03)],
		"top_12": [Vector3(0.1, h + 0.12, 0.12), Vector3(0.1, h, 0.04)],
		"corner":
		[Vector3(-half_x - 0.22, h + 0.1, o + 0.22), Vector3(-half_x + 0.06, 0.5 * h, z_f - 0.06)],
	}
	var pose: Array[Vector3] = []
	if poses.has(view_name):
		pose.assign(poses[view_name])
	return pose


## The scale card: a white 4 cm x 1 cm plate with a dark tick every millimetre (longer every
## 5 mm, full height every centimetre).
func _add_card(kind: String, anchor: Node3D, tank: TankDefinition, depth: float) -> void:
	if kind != "glass" and kind != "top":
		return
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_card_quad(tool, Vector2.ZERO, CARD_SIZE_M, 0.0, Color(0.95, 0.95, 0.92))
	for tick: int in range(0, 41):
		var height: float = 0.003
		if tick % 10 == 0:
			height = CARD_SIZE_M.y
		elif tick % 5 == 0:
			height = 0.005
		var x: float = clampf(tick * 0.001 - 0.0001, 0.0, CARD_SIZE_M.x - 0.0002)
		_card_quad(tool, Vector2(x, 0.0), Vector2(0.0002, height), 0.00002, Color(0.05, 0.05, 0.05))
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var card: MeshInstance3D = MeshInstance3D.new()
	card.name = "ScaleCard"
	card.mesh = tool.commit()
	card.material_override = material
	card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	anchor.add_child(card)
	if kind == "glass":
		# standing on the cabinet level against the outside of the front pane, facing the camera
		var z: float = tank.interior_size_m.z / 2.0 + tank.glass_thickness_m + 0.0005
		card.position = Vector3(0.11, 0.0, z)
	else:
		# lying on the bed, the ticks towards the camera
		card.rotation.x = -PI / 2.0
		card.position = Vector3(0.11, depth + 0.003, 0.0)


func _card_quad(
	tool: SurfaceTool, origin: Vector2, size: Vector2, lift: float, colour: Color
) -> void:
	var corners: Array[Vector3] = [
		Vector3(origin.x, origin.y, lift),
		Vector3(origin.x + size.x, origin.y, lift),
		Vector3(origin.x + size.x, origin.y + size.y, lift),
		Vector3(origin.x, origin.y + size.y, lift),
	]
	for index: int in [0, 2, 1, 0, 3, 2]:
		tool.set_color(colour)
		tool.add_vertex(corners[index])
