class_name WaterCausticSettings
extends Resource
## The one place for every caustic value that changes the look (ADR 0007 Amendment 1). The values
## reach the shader only as instance parameters set by TankCaustics. Intensity 0 is the off state;
## there is no enabled flag. A quality level (#81) may change these values and call apply().

## Emitted once by apply(); the displayed TankCaustics re-reads the values from this resource.
signal applied

const CAUSTIC_INTENSITY_MIN: float = 0.0
const CAUSTIC_INTENSITY_MAX: float = 2.0
const CAUSTIC_SPEED_MIN: float = 0.05
const CAUSTIC_SPEED_MAX: float = 0.5
const CAUSTIC_SCALE_MIN: float = 10.0
const CAUSTIC_SCALE_MAX: float = 60.0
const DEFAULT_INTENSITY: float = 0.4
const DEFAULT_SPEED: float = 0.25
const DEFAULT_SCALE: float = 25.0
const ROLLOVER_SETTING: String = "rendering/limits/time/time_rollover_secs"
const DEFAULT_ROLLOVER_SECS: float = 3600.0

@export_range(0.0, 2.0) var caustic_intensity: float = DEFAULT_INTENSITY
@export_range(0.05, 0.5) var caustic_speed: float = DEFAULT_SPEED
@export_range(10.0, 60.0) var caustic_scale: float = DEFAULT_SCALE


## Clamps the values (a non-finite value goes to its default, the speed is rounded to a whole
## number of cycles per TIME rollover), warns once when anything was out of range, then announces.
func apply() -> void:
	var changed: PackedStringArray = PackedStringArray()
	var new_intensity: float = _fixed(
		caustic_intensity, CAUSTIC_INTENSITY_MIN, CAUSTIC_INTENSITY_MAX, DEFAULT_INTENSITY
	)
	if not is_equal_approx(new_intensity, caustic_intensity):
		changed.append("caustic_intensity")
	caustic_intensity = new_intensity
	var new_speed: float = _fixed(
		caustic_speed, CAUSTIC_SPEED_MIN, CAUSTIC_SPEED_MAX, DEFAULT_SPEED
	)
	if not is_equal_approx(new_speed, caustic_speed):
		changed.append("caustic_speed")
	caustic_speed = _round_to_rollover(new_speed)
	var new_scale: float = _fixed(
		caustic_scale, CAUSTIC_SCALE_MIN, CAUSTIC_SCALE_MAX, DEFAULT_SCALE
	)
	if not is_equal_approx(new_scale, caustic_scale):
		changed.append("caustic_scale")
	caustic_scale = new_scale
	if not changed.is_empty():
		push_warning("WaterCausticSettings: clamped out-of-range values: %s" % ", ".join(changed))
	applied.emit()


func _fixed(value: float, low: float, high: float, default_value: float) -> float:
	if not is_finite(value):
		return default_value
	return clampf(value, low, high)


## A whole number of cycles per TIME rollover keeps the animation loop seamless at the wrap.
func _round_to_rollover(speed: float) -> float:
	var rollover: float = float(
		ProjectSettings.get_setting(ROLLOVER_SETTING, DEFAULT_ROLLOVER_SECS)
	)
	if not is_finite(rollover) or rollover <= 0.0:
		return speed
	var cycles: float = roundf(speed * rollover)
	return clampf(cycles / rollover, CAUSTIC_SPEED_MIN, CAUSTIC_SPEED_MAX)
