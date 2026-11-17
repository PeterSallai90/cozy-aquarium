class_name SubstrateBedLook
extends Resource
## The look of one substrate type (art values only, ADR 0011 rule 12): which baked data and grain
## meshes it uses, the materials, LOD distances, the sand real-grain range, the dark core and the
## tone spreads of Story Scope 9. One resource per type in res://assets/substrate/looks/, never
## changed at run time: a bed copies the materials and sets the tint on the copies.

const BAKE_DIR: String = "res://assets/substrate/bake/"
## Grain classes; the numbers equal SubstrateDefinition.GrainShape.
const CLASS_SAND: int = 0
const CLASS_ANGULAR: int = 1
const CLASS_ROUND: int = 2
const CLASS_PEBBLE: int = 3

@export_group("Data")
## 0 sand (ray-cast grains), 1 angular, 2 round, 3 pebble (instanced meshes).
@export var grain_class: int = CLASS_SAND
## File name of the baked tile data in BAKE_DIR (tile types).
@export var bake_file: String = ""
## File name of the baked data per tank id (whole-tank bakes: pebbles).
@export var bake_files_by_tank: Dictionary[StringName, String] = {}
## The grain meshes (nodes <class>_v<n>_lod<k>); null for sand.
@export var grain_glb: PackedScene = null

@export_group("Level of detail")
## Switch distances between LOD k and k + 1 in metres, camera to chunk bounds.
@export var lod_distances_m: PackedFloat32Array = PackedFloat32Array()
@export_range(0.0, 0.5) var lod_hysteresis: float = 0.05
@export var chunk_size_m: float = 0.05
## Beyond this distance a chunk leaves out the stones kept behind the visible ones (0 = never).
@export var behind_range_m: float = 0.0
## Sand: real top grains are drawn in full up to the begin and thin out to the end.
@export var sand_range_begin_m: float = 0.7
@export var sand_range_end_m: float = 1.0

@export_group("Materials")
@export var stone_material: ShaderMaterial = null
@export var grain_material: ShaderMaterial = null
@export var top_material: ShaderMaterial = null
@export var core_material: ShaderMaterial = null
## Sand: shader parameters of the grain material that differ for the grains of the top tiles.
@export var top_grain_parameters: Dictionary = {}

@export_group("Core")
## Distance of the core walls from the panes (at least 2 x the median drawn grain).
@export var core_inset_m: float = 0.01
## Distance of the core top below the fill depth (at least the median drawn grain).
@export var core_drop_m: float = 0.005
## Sand: distance of the procedural surface below the fill depth.
@export var sand_surface_drop_m: float = 0.0017

@export_group("Tone")
## Lightness spread around the swatch (0.08 = +-8 %).
@export var tone_lightness: float = 0.08
## Hue spread in degrees.
@export var tone_hue_deg: float = 3.0
## Saturation spread around the swatch.
@export var tone_saturation: float = 0.0
## Share of mixed-rock outliers (near-white, dark, rusty).
@export_range(0.0, 0.05) var tone_outlier_share: float = 0.0
## Share of lighter glint grains and their lightness factor.
@export_range(0.0, 0.05) var tone_glint_share: float = 0.0
@export var tone_glint_gain: float = 1.15
## Share of darker grains (0 for sand: its outliers are only lighter).
@export_range(0.0, 0.05) var tone_dark_share: float = 0.0

@export_group("Junction")
## Ring stones win: a top stone closer to a ring stone than this share of their sizes is dropped.
@export var junction_factor: float = 0.3
## How far the top layer reaches into the ring strip, in metres.
@export var junction_overlap_m: float = 0.0012


## Resource path of the baked data for a tank ("" when the look has none for it).
func bake_path_for(tank_id: StringName) -> String:
	if bake_files_by_tank.has(tank_id):
		return BAKE_DIR + bake_files_by_tank[tank_id]
	if bake_file.is_empty():
		return ""
	return BAKE_DIR + bake_file
