class_name SubstrateLayer
extends MeshInstance3D
## The visible substrate floor of a tank (#28): a flat plane the size of the inner floor at the
## SubstrateAnchor, top face just below tank-local y = 0 (visual only, never moves the logical
## floor). It uses the shared material res://assets/tank/materials/substrate.tres, which is never
## changed at run time; the look of the active type is set per instance here. The layer knows no
## catalog and no model: the room passes the values in.

const TINT_PARAMETER: StringName = &"substrate_tint"
const GRAIN_SCALE_PARAMETER: StringName = &"grain_scale"
const GRAIN_SHAPE_PARAMETER: StringName = &"grain_shape"
const GRAIN_CONTRAST_PARAMETER: StringName = &"grain_contrast"


## Sets the four instance shader parameters at once: the colour, the apparent grain size in
## metres, the grain shape (0 SPECKLE, 1 ANGULAR, 2 ROUND, as SubstrateDefinition.GrainShape) and
## the grain contrast (0..1). Takes effect in the same frame.
func apply_look(tint: Color, grain_scale: float, grain_shape: int, grain_contrast: float) -> void:
	set_instance_shader_parameter(TINT_PARAMETER, tint)
	set_instance_shader_parameter(GRAIN_SCALE_PARAMETER, grain_scale)
	set_instance_shader_parameter(GRAIN_SHAPE_PARAMETER, grain_shape)
	set_instance_shader_parameter(GRAIN_CONTRAST_PARAMETER, grain_contrast)
