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

const SELECTION_MATERIAL: Material = preload("res://scenes/tank/items/item_selection_material.tres")

var _model: AquariumModel = null
var _source: ItemCatalogSource = null
var _tank: TankDefinition = null
var _substrate: SubstrateDefinition = null
var _nodes: Dictionary[String, Node3D] = {}
var _bounds: Dictionary[String, AABB] = {}
## Pending (hold) angles in degrees by uid; only the view shows them, the model keeps its angle.
var _pending: Dictionary[String, float] = {}
var _created: int = 0
var _selected_uid: String = ""
var _marked_uid: String = ""
var _feedback_visible: bool = true


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
	_apply_mark()


func _on_item_added(uid: String, _index: int) -> void:
	_create(_model.get_item(uid))


func _on_item_removed(uid: String, _index: int) -> void:
	_drop(uid)


func _on_item_changed(uid: String, _index: int) -> void:
	_pending.erase(uid)
	if _nodes.has(uid):
		_update(uid)
	else:
		_create(_model.get_item(uid))


func _on_model_reset() -> void:
	_rebuild()


func _rebuild() -> void:
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
	add_child(instance)
	_created += 1
	_place(item, instance)
	if item.uid == _marked_uid or item.uid == _selected_uid:
		_apply_mark()


func _drop(uid: String) -> void:
	var node: Node3D = _nodes.get(uid)
	_nodes.erase(uid)
	_bounds.erase(uid)
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


func _apply_mark() -> void:
	var wanted: String = _selected_uid if _feedback_visible else ""
	if wanted == _marked_uid and (wanted == "" or _nodes.has(wanted)):
		return
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
