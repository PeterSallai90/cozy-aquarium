class_name SubstrateAssemblyInput
extends RefCounted
## Everything SubstrateAssembler.assemble needs besides the baked data, as plain values (ADR 0011
## rules 9 and 10): created on the main thread, read on a worker thread. The colour is not here:
## a swatch change never re-assembles.

var tank_id: StringName = &""
var substrate_id: StringName = &""
var interior_size_m: Vector3 = Vector3.ZERO
## The depth of the bed in metres; other scripts read it through depth().
var fill_depth_m: float = 0.0
var grain_class: int = 0
var chunk_size_m: float = 0.05
var core_inset_m: float = 0.0
var core_drop_m: float = 0.0
var tone_lightness: float = 0.0
var tone_hue_deg: float = 0.0
var tone_saturation: float = 0.0
var tone_outlier_share: float = 0.0
var tone_glint_share: float = 0.0
var tone_glint_gain: float = 1.0
var tone_dark_share: float = 0.0
var junction_factor: float = 0.3
var junction_overlap_m: float = 0.0
var packing_version: int = 0
# Public bake input name; it shadows the built-in seed() on purpose.
@warning_ignore("shadowed_global_identifier") var seed: int = 0


## Copies the values of the look; the seed comes from SubstrateAssembler.seed_for.
static func create(
	wanted_tank_id: StringName,
	wanted_substrate_id: StringName,
	interior: Vector3,
	depth_m: float,
	look: SubstrateBedLook
) -> SubstrateAssemblyInput:
	var input: SubstrateAssemblyInput = SubstrateAssemblyInput.new()
	input.tank_id = wanted_tank_id
	input.substrate_id = wanted_substrate_id
	input.interior_size_m = interior
	input.fill_depth_m = depth_m
	input.grain_class = look.grain_class
	input.chunk_size_m = look.chunk_size_m
	input.core_inset_m = look.core_inset_m
	input.core_drop_m = look.core_drop_m
	input.tone_lightness = look.tone_lightness
	input.tone_hue_deg = look.tone_hue_deg
	input.tone_saturation = look.tone_saturation
	input.tone_outlier_share = look.tone_outlier_share
	input.tone_glint_share = look.tone_glint_share
	input.tone_glint_gain = look.tone_glint_gain
	input.tone_dark_share = look.tone_dark_share
	input.junction_factor = look.junction_factor
	input.junction_overlap_m = look.junction_overlap_m
	input.packing_version = SubstrateAssembler.PACKING_VERSION
	input.seed = SubstrateAssembler.seed_for(wanted_tank_id, wanted_substrate_id)
	return input


## The depth of the bed in metres (the nominal surface height of a flat bed).
func depth() -> float:
	return fill_depth_m
