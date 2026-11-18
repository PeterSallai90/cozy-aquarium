class_name SubstrateDefinition
extends Resource
## One substrate type in the catalog (data only). Mode 1 fields are shown or used by the cozy
## builder; Mode 2 fields are stored for the future simulation mode and never shown or used in
## Mode 1. Enum values are only ever appended, never renumbered; UNSET is 0 on purpose so a
## correctly filled field never equals the empty default.

## The grain class of the bed (ADR 0011): SAND is drawn as ray-cast grains, the others name the
## stone mesh class (angular chips, round stones, pebbles). The numbers equal
## SubstrateBedLook.CLASS_* and are only ever appended.
enum GrainShape { SAND = 0, ANGULAR = 1, ROUND = 2, PEBBLE = 3 }

## Effect of the substrate on a water value (Mode 2).
enum WaterEffect { UNSET = 0, INERT = 1, RAISES_SLIGHTLY = 2, RAISES = 3 }

# --- Mode 1 ---
@export var id: StringName = &""
@export var name_key: String = ""
@export var description_key: String = ""
## Position in the chooser, 1 first.
@export var sort_order: int = 0
@export var default_colour: Color = Color(0.0, 0.0, 0.0, 0.0)
## The colours the player can pick, the default first. Exact 8-bit values.
@export var colour_swatches: Array[Color] = []
## Median drawn grain size in metres (drawn, not the real grain size of the Mode 2 fields).
@export var grain_scale: float = 0.0
@export var grain_shape: GrainShape = GrainShape.SAND
## Grain-to-grain tone variation, 0..1.
@export_range(0.0, 1.0) var grain_contrast: float = 0.0
## Fixed depth of the bed in metres (ADR 0011 rule 3). Mode 1 code outside the catalog reads it
## only through SubstrateSurface; layer_depth_default_cm holds the same value times 100.
@export var fill_depth_m: float = 0.0
## The art values of the bed: baked data, grain meshes, materials, LOD, tone spreads.
@export var bed_look: SubstrateBedLook = null

# --- Mode 2 (stored, never shown or used in Mode 1) ---
@export var ph_effect: WaterEffect = WaterEffect.UNSET
@export var hardness_effect: WaterEffect = WaterEffect.UNSET
@export var bulk_density_kg_per_l: float = 0.0
@export var layer_depth_min_cm: float = 0.0
@export var layer_depth_max_cm: float = 0.0
@export var layer_depth_default_cm: float = 0.0
@export var grain_size_min_mm: float = 0.0
@export var grain_size_max_mm: float = 0.0
@export var rooting_suitability: float = 0.0
@export var nutrient_retention: float = 0.0
@export var burrowing_suitability: float = 0.0
## 1 = no sharp edges.
@export var edge_smoothness: float = 0.0
@export var waste_trapping: float = 0.0
@export var cleaning_difficulty: float = 0.0
