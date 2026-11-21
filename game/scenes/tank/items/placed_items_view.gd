# gdlint: disable=max-public-methods
class_name PlacedItemsView
extends Node3D
## The drawn items of the model (#31, ADR 0012 rule 2): one node per placed item uid, instanced from
## ItemDefinition.scene, at the model transform in the tank-local frame of the parent Placement.
## It reads the model and never writes it. item_added creates exactly one node, item_removed frees
## exactly one, item_changed updates the existing node in place and model_reset rebuilds all in one
## pass. set_tank and set_substrate only move nodes. An unknown catalog_id or a definition without
## a scene draws nothing and logs nothing. The ghost, the drag preview and the selection mark are
## never in the registry: the mark is the selection material as material_overlay on the meshes of
## the selected node, so it follows every transform change of that node.
##
## The colour of a colourable item is a per-instance shader parameter (#32, ADR 0012 Amendment 1
## rule 11): every geometry instance of the node gets item_tint, alpha 1 for a stored colour of a
## colourable definition and alpha 0 (the original look) otherwise. Meshes and materials stay
## shared; it is set on create and on item_changed only, never for a pending rotation.
##
## The refusal cue (#33 AC 13, 15, ADR 0012 Amendment 2 rule 16): play_refusal_cue() plays one
## pulse (RefusalCue) on any drawn item. While it runs the item carries one runtime copy of the
## selection material as overlay; step_cue() sets its glow_colour, fresnel_strength, fresnel_power
## and glow_lift. The shared material is never written: it goes back on the marked item, and an
## item that is not marked loses its overlay, when the cue ends or is cancelled.

const TINT_PARAM: StringName = &"item_tint"
const SELECTION_MATERIAL: Material = preload("res://scenes/tank/items/item_selection_material.tres")
const STRENGTH_PARAM: StringName = &"fresnel_strength"
const COLOUR_PARAM: StringName = &"glow_colour"
const POWER_PARAM: StringName = &"fresnel_power"
const LIFT_PARAM: StringName = &"glow_lift"

var _model: AquariumModel = null
var _source: ItemCatalogSource = null
var _tank: TankDefinition = null
var _substrate: SubstrateDefinition = null
var _nodes: Dictionary[String, Node3D] = {}
var _bounds: Dictionary[String, AABB] = {}
## Whether the definition of each drawn item is colourable, cached at creation.
var _colourable: Dictionary[String, bool] = {}
## Pending (hold) angles in degrees by uid; only the view shows them, the model keeps its angle.
var _pending: Dictionary[String, float] = {}
var _created: int = 0
var _selected_uid: String = ""
var _marked_uid: String = ""
var _feedback_visible: bool = true
var _cue: RefusalCue = RefusalCue.new()
var _cue_material: ShaderMaterial = null
var _cue_uid: String = ""
var _cue_plays: int = 0


## Connects to the model. The catalog is asked for only when an item has to be drawn.
func setup(model: AquariumModel, source: ItemCatalogSource) -> void:
	_model = model
	_source = source
	_model.item_added.connect(_on_item_added)
	_model.item_removed.connect(_on_item_removed)
	_model.item_changed.connect(_on_item_changed)
	_model.model_reset.connect(_on_model_reset)
	_rebuild()


## The tank the items stand in; null hides every item (no tank is shown).
func set_tank(definition: TankDefinition) -> void:
	_cancel_cue()
	_tank = definition
	visible = definition != null
	_reposition_all()


## The substrate definition the bed shows; items stand on its nominal surface.
func set_substrate(definition: SubstrateDefinition) -> void:
	_substrate = definition
	_reposition_all()


## One entry per drawn item in model order: {"uid", "transform", "aabb"} in tank-local space.
func get_hit_entries() -> Array:
	var entries: Array = []
	if _model == null:
		return entries
	for item: PlacedItem in _model.get_items():
		var node: Node3D = _nodes.get(item.uid)
		if node == null:
			continue
		entries.append({"uid": item.uid, "transform": node.transform, "aabb": _bounds[item.uid]})
	return entries


func get_drawn_count() -> int:
	return _nodes.size()


## How many drawn nodes were ever created (the 100-item guard counts with it).
func get_created_count() -> int:
	return _created


func get_node_for(uid: String) -> Node3D:
	return _nodes.get(uid)


## Shows `deg` as the angle of the drawn item without touching the model (rotate hold preview).
func show_pending_rotation(uid: String, deg: float) -> void:
	_pending[uid] = deg
	_update(uid)


## Back to the model angle.
func clear_pending(uid: String) -> void:
	if _pending.erase(uid):
		_update(uid)


## Puts the selection mark on the item, or removes it with an empty uid.
func set_selected(uid: String) -> void:
	_selected_uid = uid
	_apply_mark()


## Hides or shows the selection mark (the world is blocked, for example in photo mode).
func set_feedback_visible(shown: bool) -> void:
	_feedback_visible = shown
	if not shown:
		_cancel_cue()
	_apply_mark()


## Plays the refusal cue on any drawn item while the feedback is shown (the marked item keeps its
## mark under the cue; another item gets the runtime copy as its overlay). A cue that runs, on this
## or another item, is ended first and restarted, never stacked.
func play_refusal_cue(uid: String) -> void:
	if uid == "" or not _feedback_visible:
		return
	var node: Node3D = _nodes.get(uid)
	if node == null:
		return
	_cancel_cue()
	if _cue_material == null:
		_cue_material = (SELECTION_MATERIAL as ShaderMaterial).duplicate() as ShaderMaterial
	_cue.start()
	_cue_plays += 1
	_cue_uid = uid
	_write_cue()
	_set_overlay(node, _cue_material)


## Advances the cue by one frame and writes its uniforms to the runtime copy.
func step_cue(delta_s: float) -> void:
	if not _cue.is_active():
		return
	_cue.step(delta_s)
	if _cue.is_active():
		_write_cue()
	else:
		_cancel_cue()


func is_refusal_cue_active() -> bool:
	return _cue.is_active()


## How many cues were played since setup.
func get_refusal_cue_count() -> int:
	return _cue_plays


## The uid the cue plays on; empty without a cue.
func get_cue_uid() -> String:
	return _cue_uid if _cue.is_active() else ""


## The fresnel strength on the marked meshes now: the base without a cue (and for a cue on another
## item), 0.0 with nothing marked.
func get_mark_strength() -> float:
	if _marked_uid == "":
		return 0.0
	if _cue.is_active() and _cue_uid == _marked_uid:
		return _cue.get_strength(_base_strength())
	return _base_strength()


## The fresnel strength on the cued meshes; the base outside a cue.
func get_cue_strength() -> float:
	return _cue.get_strength(_base_strength())


## The glow_colour of the cue now; the base colour outside a cue.
func get_cue_colour() -> Color:
	var base: Color = _base_colour()
	return RefusalCue.colour_at(_cue.get_elapsed_s(), base) if _cue.is_active() else base


func get_cue_fresnel_power() -> float:
	var base: float = _base_power()
	return RefusalCue.power_at(_cue.get_elapsed_s(), base) if _cue.is_active() else base


## The glow_lift of the cue now; zero outside a cue.
func get_cue_lift() -> Vector3:
	return RefusalCue.lift_at(_cue.get_elapsed_s()) if _cue.is_active() else Vector3.ZERO


func _write_cue() -> void:
	_cue_material.set_shader_parameter(STRENGTH_PARAM, get_cue_strength())
	_cue_material.set_shader_parameter(COLOUR_PARAM, get_cue_colour())
	_cue_material.set_shader_parameter(POWER_PARAM, get_cue_fresnel_power())
	_cue_material.set_shader_parameter(LIFT_PARAM, get_cue_lift())


func _base_strength() -> float:
	return float((SELECTION_MATERIAL as ShaderMaterial).get_shader_parameter(STRENGTH_PARAM))


func _base_colour() -> Color:
	return (SELECTION_MATERIAL as ShaderMaterial).get_shader_parameter(COLOUR_PARAM)


func _base_power() -> float:
	return float((SELECTION_MATERIAL as ShaderMaterial).get_shader_parameter(POWER_PARAM))


## Ends a running cue: the shared selection material goes back on the marked item, and an item
## that is not marked loses its overlay.
func _cancel_cue() -> void:
	_cue.cancel()
	if _cue_uid == "":
		return
	var node: Node3D = _nodes.get(_cue_uid)
	if node != null:
		_set_overlay(node, SELECTION_MATERIAL if _cue_uid == _marked_uid else null)
	_cue_uid = ""


func _on_item_added(uid: String, _index: int) -> void:
	_create(_model.get_item(uid))


func _on_item_removed(uid: String, _index: int) -> void:
	_drop(uid)


func _on_item_changed(uid: String, _index: int) -> void:
	_pending.erase(uid)
	if _nodes.has(uid):
		_update(uid)
		_apply_tint(_model.get_item(uid), _nodes[uid])
	else:
		_create(_model.get_item(uid))


func _on_model_reset() -> void:
	_rebuild()


func _rebuild() -> void:
	_cancel_cue()
	for uid: String in _nodes.keys():
		_drop(uid)
	_pending.clear()
	for item: PlacedItem in _model.get_items():
		_create(item)


func _create(item: PlacedItem) -> void:
	if item == null or _source == null or _nodes.has(item.uid):
		return
	var definition: ItemDefinition = _source.get_catalog().get_definition(item.catalog_id)
	if definition == null or definition.scene == null:
		return
	var instance: Node3D = definition.scene.instantiate() as Node3D
	if instance == null:
		return
	instance.name = item.uid
	_bounds[item.uid] = _visual_bounds(instance)
	_nodes[item.uid] = instance
	_colourable[item.uid] = definition.colourable
	add_child(instance)
	_created += 1
	_place(item, instance)
	_apply_tint(item, instance)
	if item.uid == _marked_uid or item.uid == _selected_uid:
		_apply_mark()


func _drop(uid: String) -> void:
	if uid == _cue_uid:
		_cancel_cue()
	var node: Node3D = _nodes.get(uid)
	_nodes.erase(uid)
	_bounds.erase(uid)
	_colourable.erase(uid)
	_pending.erase(uid)
	if uid == _marked_uid:
		_marked_uid = ""
	if node != null:
		remove_child(node)
		node.queue_free()


func _update(uid: String) -> void:
	var node: Node3D = _nodes.get(uid)
	var item: PlacedItem = _model.get_item(uid)
	if node != null and item != null:
		_place(item, node)


func _reposition_all() -> void:
	if _model == null:
		return
	for uid: String in _nodes:
		_update(uid)


func _place(item: PlacedItem, node: Node3D) -> void:
	var deg: float = _pending.get(item.uid, item.rotation_y)
	node.position = Vector3(item.position.x, _height_of(item), item.position.z)
	node.rotation = Vector3(0.0, deg_to_rad(deg), 0.0)
	node.scale = Vector3.ONE * item.scale


## The tank-local height of the item: the substrate surface plus its position.y (H1).
func _height_of(item: PlacedItem) -> float:
	if _substrate == null or _tank == null:
		return item.position.y
	return SubstrateSurface.absolute_y(
		_substrate,
		_model.get_heightmap(),
		_model.get_heightmap_size(),
		_tank.interior_size_m,
		item.position
	)


func _apply_tint(item: PlacedItem, node: Node3D) -> void:
	if item == null or node == null:
		return
	var tint: Color = Color(0.0, 0.0, 0.0, 0.0)
	if _colourable.get(item.uid, false) and item.has_colour:
		tint = Color(item.colour.r, item.colour.g, item.colour.b, 1.0)
	for instance: GeometryInstance3D in geometry_of(node):
		instance.set_instance_shader_parameter(TINT_PARAM, tint)


func _apply_mark() -> void:
	var wanted: String = _selected_uid if _feedback_visible else ""
	if wanted == _marked_uid and (wanted == "" or _nodes.has(wanted)):
		return
	_cancel_cue()
	var old: Node3D = _nodes.get(_marked_uid)
	if old != null:
		_set_overlay(old, null)
	_marked_uid = ""
	var node: Node3D = _nodes.get(wanted)
	if node != null:
		_set_overlay(node, SELECTION_MATERIAL)
		_marked_uid = wanted


static func _set_overlay(root: Node3D, material: Material) -> void:
	for instance: GeometryInstance3D in geometry_of(root):
		instance.material_overlay = material


## Every GeometryInstance3D of a drawn or ghost node, the root included.
static func geometry_of(root: Node) -> Array[GeometryInstance3D]:
	var found: Array[GeometryInstance3D] = []
	var own: GeometryInstance3D = root as GeometryInstance3D
	if own != null:
		found.append(own)
	for child: Node in root.find_children("*", "GeometryInstance3D", true, false):
		found.append(child as GeometryInstance3D)
	return found


## The union of the visual mesh bounds in the frame of `root`, computed once at creation.
static func _visual_bounds(root: Node3D) -> AABB:
	var box: AABB = AABB()
	var first: bool = true
	var meshes: Array[Node] = root.find_children("*", "MeshInstance3D", true, false)
	var own: MeshInstance3D = root as MeshInstance3D
	if own != null:
		meshes.append(own)
	for found: Node in meshes:
		var mesh: MeshInstance3D = found as MeshInstance3D
		if mesh.mesh == null:
			continue
		var frame: Transform3D = Transform3D.IDENTITY
		var walker: Node3D = mesh
		while walker != null and walker != root:
			frame = walker.transform * frame
			walker = walker.get_parent() as Node3D
		var part: AABB = frame * mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box
