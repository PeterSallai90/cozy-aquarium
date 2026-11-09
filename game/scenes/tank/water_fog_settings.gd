class_name WaterFogSettings
extends Resource
## The one place for every fog value that changes the look or costs performance (ADR 0007).
## Values in room_environment.tres and the preview FogMaterial are editor mirrors of the defaults
## here. A quality level (#81) changes these values and calls apply().

## Emitted by apply(); the room and the current TankWater re-apply their parts from this resource.
signal applied

const DENSITY_MAX: float = 0.1
const LENGTH_MIN_M: float = 1.0
const LENGTH_MAX_M: float = 64.0
const DETAIL_SPREAD_MIN: float = 0.5
const DETAIL_SPREAD_MAX: float = 6.0
const VOLUME_MIN: int = 16
const VOLUME_MAX: int = 512

@export var volumetric_fog_enabled: bool = true
@export var density: float = 0.02
@export var albedo: Color = Color(0.70, 0.90, 0.95)
@export var volumetric_fog_length: float = 8.0
@export var volumetric_fog_detail_spread: float = 2.0
@export var volume_size: int = 64
@export var volume_depth: int = 64
@export var use_filter: bool = true


## Clamps the values (one warning when anything was out of range) and announces the result.
func apply() -> void:
	var clamped: PackedStringArray = PackedStringArray()
	var new_density: float = clampf(density, 0.0, DENSITY_MAX)
	if not is_equal_approx(new_density, density):
		clamped.append("density")
	density = new_density
	var new_length: float = clampf(volumetric_fog_length, LENGTH_MIN_M, LENGTH_MAX_M)
	if not is_equal_approx(new_length, volumetric_fog_length):
		clamped.append("volumetric_fog_length")
	volumetric_fog_length = new_length
	var new_spread: float = clampf(
		volumetric_fog_detail_spread, DETAIL_SPREAD_MIN, DETAIL_SPREAD_MAX
	)
	if not is_equal_approx(new_spread, volumetric_fog_detail_spread):
		clamped.append("volumetric_fog_detail_spread")
	volumetric_fog_detail_spread = new_spread
	var new_size: int = clampi(volume_size, VOLUME_MIN, VOLUME_MAX)
	if new_size != volume_size:
		clamped.append("volume_size")
	volume_size = new_size
	var new_depth: int = clampi(volume_depth, VOLUME_MIN, VOLUME_MAX)
	if new_depth != volume_depth:
		clamped.append("volume_depth")
	volume_depth = new_depth
	if not clamped.is_empty():
		push_warning("WaterFogSettings: clamped out-of-range values: %s" % ", ".join(clamped))
	applied.emit()


## Fog on or off, length and detail spread. The global density stays 0: the haze comes only from
## the bounded FogVolume.
func apply_to_environment(environment: Environment) -> void:
	if environment == null:
		return
	environment.volumetric_fog_enabled = volumetric_fog_enabled
	environment.volumetric_fog_density = 0.0
	environment.volumetric_fog_length = volumetric_fog_length
	environment.volumetric_fog_detail_spread = volumetric_fog_detail_spread


## The froxel volume size and the temporal filter; process-wide, with no getter.
func apply_to_rendering_server() -> void:
	RenderingServer.environment_set_volumetric_fog_volume_size(volume_size, volume_depth)
	RenderingServer.environment_set_volumetric_fog_filter_active(use_filter)


## Density and albedo of the FogVolume material; the volume is hidden when fog is off.
func apply_to_fog(fog: FogVolume) -> void:
	if fog == null:
		return
	var material: FogMaterial = fog.material as FogMaterial
	if material != null:
		material.density = density
		material.albedo = albedo
	fog.visible = volumetric_fog_enabled
