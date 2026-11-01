extends RefCounted
## A LocalFormat with injected inputs that a test can change between two calls. The three
## Callables read a shared state Dictionary, because a lambda captures a local by value.

## 2026-01-15T00:00:00Z, 2026-07-01T00:00:00Z and 2026-11-01T00:00:00Z as Unix seconds.
const CLOCK_JANUARY: int = 1768435200
const CLOCK_JULY: int = 1782864000
const CLOCK_NOVEMBER: int = 1793491200

var language: Variant:
	get:
		return _state["language"]
	set(value):
		_state["language"] = value
var offset: Variant:
	get:
		return _state["offset"]
	set(value):
		_state["offset"] = value
var now: Variant:
	get:
		return _state["now"]
	set(value):
		_state["now"] = value
var format: LocalFormat

## The Callables capture only this Dictionary, never the rig, so there is no reference cycle.
var _state: Dictionary = {}


func _init(
	language_value: Variant = "en", offset_value: Variant = 60, now_value: Variant = CLOCK_NOVEMBER
) -> void:
	var state: Dictionary = _state
	language = language_value
	offset = offset_value
	now = now_value
	format = LocalFormat.new(
		func() -> Variant: return state["language"],
		func() -> Variant: return state["offset"],
		func() -> Variant: return state["now"]
	)
