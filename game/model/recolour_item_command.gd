class_name RecolourItemCommand
extends Command
## Sets or clears the colour of one placed item (#32): has_colour true with a colour, or false for
## the original colour. Refuses a missing uid and a request equal to the current state (compared
## by to_rgba32()), with the model untouched and no signal. The item keeps everything else. Undo
## puts the old instance back, so the old colour state is restored exactly.

var _model: AquariumModel = null
var _uid: String = ""
var _has_colour: bool = false
var _colour: Color = Color.WHITE

var _before: PlacedItem = null
var _after: PlacedItem = null


func _init(model: AquariumModel, uid: String, has_colour: bool, colour: Color) -> void:
	_model = model
	_uid = uid
	_has_colour = has_colour
	_colour = colour


func do() -> bool:
	var current: PlacedItem = _model.get_item(_uid)
	if current == null:
		return false
	if current.has_colour == _has_colour:
		if not _has_colour or current.colour.to_rgba32() == _colour.to_rgba32():
			return false
	var candidate: PlacedItem = current.copy()
	candidate.has_colour = _has_colour
	candidate.colour = _colour if _has_colour else Color.WHITE
	if not _model.apply_replace_item(candidate):
		return false
	_before = current
	_after = candidate
	return true


func undo() -> bool:
	return _model.apply_replace_item(_before)
