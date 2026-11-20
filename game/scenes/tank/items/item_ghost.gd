class_name ItemGhost
extends Node3D
## The see-through preview of the picked or dragged item (#31, ADR 0012 rule 8): one instance of the
## item's own scene with the ghost material as material_override and no shadow. It is re-instanced
## only when the item changes, has no collision or pick shape and is never part of the model or of
## the drawn items. Its only child is that instance.

const GHOST_MATERIAL: Material = preload("res://scenes/tank/items/item_ghost_material.tres")

var _item_id: StringName = &""
var _instance: Node3D = null


## Makes the ghost the item `id` built from `scene`. The same id keeps the instance. A missing
## scene empties the ghost and returns false.
func show_item(id: StringName, scene: PackedScene) -> bool:
	if _instance != null and id == _item_id:
		return true
	clear_item()
	if scene == null:
		return false
	var instance: Node3D = scene.instantiate() as Node3D
	if instance == null:
		return false
	for geometry: GeometryInstance3D in PlacedItemsView.geometry_of(instance):
		geometry.material_override = GHOST_MATERIAL
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	_instance = instance
	_item_id = id
	return true


func clear_item() -> void:
	if _instance != null:
		remove_child(_instance)
		_instance.queue_free()
	_instance = null
	_item_id = &""


func has_item() -> bool:
	return _instance != null


## Puts the ghost at a tank-local position with a heading in degrees and a uniform scale.
func place(local_position: Vector3, rotation_deg: float, scale_value: float) -> void:
	position = local_position
	rotation = Vector3(0.0, deg_to_rad(rotation_deg), 0.0)
	scale = Vector3.ONE * scale_value
