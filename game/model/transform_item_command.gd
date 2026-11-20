class_name TransformItemCommand
extends Command
## Moves and/or turns one placed item: the drop of a drag (position and rotation) and the release
## of a rotate hold (rotation only). The item keeps its uid, catalog id, scale and colour. Refuses
## a missing uid and anything PlacementRules does not allow, with the model untouched and no
## signal. Undo puts the old instance back, so the start transform is restored exactly.

var _model: AquariumModel = null
var _uid: String = ""
var _position: Vector3 = Vector3.ZERO
var _rotation_y: float = 0.0
var _rules: PlacementRules = null

var _before: PlacedItem = null
var _after: PlacedItem = null


func _init(
	model: AquariumModel, uid: String, position: Vector3, rotation_y: float, rules: PlacementRules
) -> void:
	_model = model
	_uid = uid
	_position = position
	_rotation_y = rotation_y
	_rules = rules


func do() -> bool:
	var current: PlacedItem = _model.get_item(_uid)
	if current == null:
		return false
	var candidate: PlacedItem = current.copy()
	candidate.position = _position
	candidate.rotation_y = _rotation_y
	if _rules == null or not _rules.allows(_model, candidate, current):
		return false
	if not _model.apply_replace_item(candidate):
		return false
	_before = current
	_after = candidate
	return true


func undo() -> bool:
	return _model.apply_replace_item(_before)
