class_name SettingKey
extends RefCounted
## A typed settings key: section, key, value type, default and an optional numeric range.
## Pure: no Node and no file access.

var section: String
var key: String
var value_type: Variant.Type
var default_value: Variant
var has_range: bool = false
var min_value: float = NAN
var max_value: float = NAN


## The range is present when both min_value and max_value are numbers.
func _init(
	p_section: String,
	p_key: String,
	p_value_type: Variant.Type,
	p_default: Variant,
	p_min: float = NAN,
	p_max: float = NAN
) -> void:
	section = p_section
	key = p_key
	value_type = p_value_type
	default_value = p_default
	min_value = p_min
	max_value = p_max
	has_range = not is_nan(p_min) and not is_nan(p_max)


## The value a stored or given raw value stands for: the default for a wrong type, NaN or
## infinity; a number is clamped into the range.
func coerce(raw: Variant) -> Variant:
	if not accepts(raw):
		return default_value
	var raw_type: int = typeof(raw)
	if value_type == TYPE_FLOAT:
		var as_float: float = float(raw)
		if raw_type == TYPE_FLOAT and (is_nan(as_float) or is_inf(as_float)):
			return default_value
		if has_range:
			return clampf(as_float, min_value, max_value)
		return as_float
	if value_type == TYPE_INT and has_range:
		return clampi(int(raw), int(min_value), int(max_value))
	return raw


## True when the value has the key's type (an int is accepted for a float key).
func accepts(value: Variant) -> bool:
	var raw_type: int = typeof(value)
	if value_type == TYPE_FLOAT:
		return raw_type == TYPE_FLOAT or raw_type == TYPE_INT
	return raw_type == value_type


func id() -> String:
	return section + "/" + key
