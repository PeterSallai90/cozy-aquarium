# gdlint: disable=max-public-methods
extends RefCounted
## One running placement scene for the #31 tests: the room with its Placement child in its own
## SubViewport, driven by synthetic input pushed through the viewport (ADR 0008) and by fixed
## frame times (the placement system processing is switched off; step() drives it).
## Built by placement_rig.gd. The placement system and its views are reached by node name and by
## method name because they do not exist before the implementation.
##
## Contract used by the #31 tests (technical plan on the issue, section 1):
## - RoomCorner has a child "Placement" (PlacementSystem) with the children "PlacedItems"
##   (PlacedItemsView) and "Ghost" (ItemGhost). Its transform is the tank-local frame.
## - Placement: step(delta_s), get_selected_uid() -> String ("" without selection),
##   get_picked_id() -> StringName, get_ghost_rotation() -> float, is_dragging(), is_holding().
## - PlacedItemsView: get_hit_entries(), get_drawn_count(), get_created_count(),
##   get_node_for(uid) -> Node3D, show_pending_rotation(uid, deg), clear_pending(uid),
##   set_selected(uid), set_feedback_visible(bool).
## - #33: PlacedItemsView.is_refusal_cue_active(), get_refusal_cue_count(), get_mark_strength();
##   the cue runs on Placement.step(delta_s) (step_cue is called there).
## - The ghost is shown when "Ghost" is visible in the tree.
## Test decisions: the stub below plays the item browser (it answers
## EventBus.item_pick_clear_requested with item_pick_cleared when it holds a pick); item and
## ground positions are compared at POSITION_TOLERANCE_M.

const Api := preload("res://tests/helpers/placement_api.gd")

const FRAME_S: float = 1.0 / 60.0
const OUTSIDE := Vector2(4.0, 4.0)
const POSITION_TOLERANCE_M: float = 0.0005
const ANGLE_TOLERANCE_DEG: float = 0.01
const MISSING_TEXT := "<missing>"

var viewport: Viewport = null
var room: Node3D = null
var placement: Node = null
var view: Node = null
var ghost: Node3D = null
var camera: Camera3D = null
var model: AquariumModel = null
var history: CommandHistory = null
var source: RefCounted = null
var items: ItemCatalog = null
## How many item_pick_clear_requested the stub saw.
var clear_requests: int = 0
## "selected:<uid>" and "cleared" in the order of the EventBus selection signals.
var selection_timeline: Array[String] = []

var _stub_pick: StringName = &""
var _pointer: Vector2 = OUTSIDE
var _mask: int = 0
var _substrates: SubstrateCatalog = SubstrateCatalog.load_dir()


## Listens to the EventBus. With `stub` the session also plays the item browser: it answers
## item_pick_clear_requested itself (the main scene tests use the real browser instead).
func connect_bus(stub: bool = true) -> void:
	EventBus.item_picked.connect(_on_picked)
	EventBus.item_pick_cleared.connect(_on_cleared)
	if stub and EventBus.has_signal("item_pick_clear_requested"):
		EventBus.connect("item_pick_clear_requested", _on_clear_requested)
	if EventBus.has_signal("item_selected"):
		EventBus.connect("item_selected", _on_selected)
	if EventBus.has_signal("item_selection_cleared"):
		EventBus.connect("item_selection_cleared", _on_selection_cleared)


func disconnect_bus() -> void:
	if EventBus.item_picked.is_connected(_on_picked):
		EventBus.item_picked.disconnect(_on_picked)
	if EventBus.item_pick_cleared.is_connected(_on_cleared):
		EventBus.item_pick_cleared.disconnect(_on_cleared)
	_drop("item_pick_clear_requested", _on_clear_requested)
	_drop("item_selected", _on_selected)
	_drop("item_selection_cleared", _on_selection_cleared)


func _drop(signal_name: String, callback: Callable) -> void:
	if EventBus.has_signal(signal_name) and EventBus.is_connected(signal_name, callback):
		EventBus.disconnect(signal_name, callback)


func _on_picked(catalog_id: StringName) -> void:
	_stub_pick = catalog_id


func _on_cleared() -> void:
	_stub_pick = &""


func _on_clear_requested() -> void:
	clear_requests += 1
	if _stub_pick != &"":
		_stub_pick = &""
		EventBus.item_pick_cleared.emit()


func _on_selected(uid: String) -> void:
	selection_timeline.append("selected:%s" % uid)


func _on_selection_cleared() -> void:
	selection_timeline.append("cleared")


# --- reading ---


func depth() -> float:
	var definition: SubstrateDefinition = _substrates.get_definition(model.get_substrate_id())
	if definition == null:
		definition = _substrates.get_default()
	return SubstrateSurface.flat_depth(definition)


func picked_id() -> String:
	return str(Api.call_on(placement, "get_picked_id", [], MISSING_TEXT))


func selected_uid() -> String:
	return str(Api.call_on(placement, "get_selected_uid", [], MISSING_TEXT))


func ghost_rotation() -> float:
	return float(Api.call_on(placement, "get_ghost_rotation", [], Api.MISSING_NUMBER))


func dragging() -> bool:
	return Api.call_on(placement, "is_dragging", [], null) == true


func holding() -> bool:
	return Api.call_on(placement, "is_holding", [], null) == true


func ghost_shown() -> bool:
	return ghost != null and ghost.is_visible_in_tree()


func drawn_count() -> int:
	return int(Api.call_on(view, "get_drawn_count", [], -1))


func created_count() -> int:
	return int(Api.call_on(view, "get_created_count", [], -1))


## The refusal cue of the drawn items (#33): PlacedItemsView.is_refusal_cue_active(),
## get_refusal_cue_count() (plays since setup, -1 while missing) and get_mark_strength() (the
## fresnel_strength on the marked meshes now; base without a cue, 0.0 with nothing marked).
func cue_active() -> bool:
	return Api.call_on(view, "is_refusal_cue_active", [], null) == true


func cue_count() -> int:
	return int(Api.call_on(view, "get_refusal_cue_count", [], -1))


func mark_strength() -> float:
	return float(Api.call_on(view, "get_mark_strength", [], Api.MISSING_NUMBER))


## #33 cue getters of the view (addendum 1 and 2): get_cue_uid() (the uid the cue plays on, "" with
## none), get_cue_colour() (glow_colour), get_cue_fresnel_power(), get_cue_lift() (glow_lift) and
## get_cue_strength() (the strength on the cued meshes; base outside a cue).
func cue_uid() -> String:
	return str(Api.call_on(view, "get_cue_uid", [], MISSING_TEXT))


func cue_colour() -> Color:
	var result: Variant = Api.call_on(view, "get_cue_colour", [], null)
	return result if result is Color else Color(1.0, 0.0, 1.0, 0.0)


func cue_power() -> float:
	return float(Api.call_on(view, "get_cue_fresnel_power", [], Api.MISSING_NUMBER))


func cue_lift() -> Vector3:
	var result: Variant = Api.call_on(view, "get_cue_lift", [], null)
	return result if result is Vector3 else Vector3(NAN, NAN, NAN)


func cue_strength() -> float:
	return float(Api.call_on(view, "get_cue_strength", [], Api.MISSING_NUMBER))


func node_for(uid: String) -> Node3D:
	return Api.call_on(view, "get_node_for", [uid], null) as Node3D


## The model-style position of a node: x and z tank-local, y above the substrate surface.
func local_position(node: Node3D) -> Vector3:
	var point: Vector3 = placement.to_local(node.global_position)
	return Vector3(point.x, point.y - depth(), point.z)


## The heading of a node in degrees (0 faces +Z, +90 faces +X), 0 up to below 360.
func yaw_of(node: Node3D) -> float:
	var axis: Vector3 = placement.global_transform.basis.inverse() * node.global_transform.basis.z
	return fposmod(rad_to_deg(atan2(axis.x, axis.z)), 360.0)


## The drawn heading of an item.
func drawn_yaw(uid: String) -> float:
	var node: Node3D = node_for(uid)
	return yaw_of(node) if node != null else Api.MISSING_NUMBER


## The point of the nominal substrate plane under a screen position, tank-local with y 0 (the
## model position of an item put there). NaN components when the ray misses the plane. An
## independent computation: it does not call the production helper.
func ground_local(screen: Vector2) -> Vector3:
	var origin: Vector3 = camera.project_ray_origin(screen)
	var direction: Vector3 = camera.project_ray_normal(screen)
	var plane: Plane = Plane(Vector3.UP, placement.global_position.y + depth())
	var hit: Variant = plane.intersects_ray(origin, direction)
	if hit == null:
		return Vector3(NAN, NAN, NAN)
	var local: Vector3 = placement.to_local(hit as Vector3)
	return Vector3(local.x, 0.0, local.z)


## The screen position of a point of the substrate plane (item origin), `above` metres above it.
func screen_of(x: float, z: float, above: float = 0.0) -> Vector2:
	return camera.unproject_position(placement.to_global(Vector3(x, depth() + above, z)))


## The centre of the visual meshes of a drawn node, in the world.
func center_of(node: Node3D) -> Vector3:
	var box: AABB = AABB()
	var first: bool = true
	for found: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = found as MeshInstance3D
		var part: AABB = mesh.global_transform * mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box.get_center()


## The screen position of the middle of a drawn item (a point that hits its bounds).
func screen_of_item(uid: String) -> Vector2:
	var node: Node3D = node_for(uid)
	if node == null:
		return OUTSIDE
	return camera.unproject_position(center_of(node))


# --- driving ---


func frame() -> void:
	await viewport.get_tree().process_frame


func step(seconds: float) -> void:
	if seconds <= 0.0:
		Api.call_on(placement, "step", [0.0], null)
		return
	var left: float = seconds
	while left > 0.0:
		var dt: float = minf(FRAME_S, left)
		Api.call_on(placement, "step", [dt], null)
		left -= dt


func pick(catalog_id: StringName) -> void:
	EventBus.item_picked.emit(catalog_id)
	step(0.0)


func unpick() -> void:
	EventBus.item_pick_cleared.emit()
	step(0.0)


func move(at: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.relative = at - _pointer
	event.screen_relative = event.relative
	event.button_mask = _mask
	_pointer = at
	viewport.push_input(event)
	step(0.0)


func press(at: Vector2) -> void:
	_button(at, true)


func release(at: Vector2) -> void:
	_button(at, false)


func click(at: Vector2) -> void:
	press(at)
	release(at)


func _button(at: Vector2, pressed: bool) -> void:
	_pointer = at
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	event.global_position = at
	_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.button_mask = _mask
	viewport.push_input(event)
	step(0.0)


func key(keycode: Key, pressed: bool, modifiers: int = 0) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	if keycode == KEY_COMMA:
		event.unicode = 44
	elif keycode == KEY_PERIOD:
		event.unicode = 46
	event.ctrl_pressed = (modifiers & KEY_MASK_CTRL) != 0
	event.shift_pressed = (modifiers & KEY_MASK_SHIFT) != 0
	event.alt_pressed = (modifiers & KEY_MASK_ALT) != 0
	event.meta_pressed = (modifiers & KEY_MASK_META) != 0
	viewport.push_input(event)
	step(0.0)


func tap(keycode: Key, modifiers: int = 0) -> void:
	key(keycode, true, modifiers)
	key(keycode, false, modifiers)


## The Shift key itself going down or up (the placement system reads Shift from these events).
func shift(down: bool) -> void:
	key(KEY_SHIFT, down, KEY_MASK_SHIFT if down else 0)


func esc() -> void:
	tap(KEY_ESCAPE)


func focus_out() -> void:
	placement.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	step(0.0)


# --- fake controls in the viewport ---


## A fake modal dialog or photo-mode root: a Control of the group world_input_blockers, hidden
## until set_blocked(blocker, true).
func make_blocker() -> Control:
	var blocker: Control = Control.new()
	blocker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blocker.visible = false
	blocker.add_to_group(&"world_input_blockers")
	viewport.add_child(blocker)
	return blocker


func set_blocked(blocker: Control, on: bool) -> void:
	blocker.visible = on
	step(0.0)


## A Control that stops the mouse over `rect`, like a HUD panel.
func make_panel(rect: Rect2) -> Control:
	var panel: Control = Control.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	viewport.add_child(panel)
	panel.position = rect.position
	panel.size = rect.size
	return panel


func make_text_field() -> LineEdit:
	var field: LineEdit = LineEdit.new()
	viewport.add_child(field)
	field.position = Vector2(900.0, 20.0)
	field.size = Vector2(120.0, 30.0)
	return field


func make_button() -> Button:
	var button: Button = Button.new()
	viewport.add_child(button)
	button.position = Vector2(900.0, 80.0)
	button.size = Vector2(120.0, 30.0)
	return button
