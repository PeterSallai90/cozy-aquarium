extends RefCounted
## A LocalFormat with injected inputs that a test can change between two calls. The three
## Callables read the members of this object, because a lambda captures a local by value.

## 2026-01-15T00:00:00Z, 2026-07-01T00:00:00Z and 2026-11-01T00:00:00Z as Unix seconds.
const CLOCK_JANUARY: int = 1768435200
const CLOCK_JULY: int = 1782864000
const CLOCK_NOVEMBER: int = 1793491200

var language: Variant = "en"
var offset: Variant = 60
var now: Variant = CLOCK_NOVEMBER
var format: LocalFormat


func _init(
	language_value: Variant = "en", offset_value: Variant = 60, now_value: Variant = CLOCK_NOVEMBER
) -> void:
	language = language_value
	offset = offset_value
	now = now_value
	format = LocalFormat.new(
		func() -> Variant: return language,
		func() -> Variant: return offset,
		func() -> Variant: return now
	)
