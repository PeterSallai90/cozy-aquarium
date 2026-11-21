class_name ItemDefinition
extends Resource
## One placeable item in the catalog: a rock, a piece of wood, an ornament or a live plant (data
## only). Mode 1 fields are shown or used by the cozy builder; Mode 2 fields are stored for the
## future simulation mode and never shown or used in Mode 1. Enum values are only ever appended,
## never renumbered; UNSET is 0 on purpose so a correctly filled field never equals the empty
## default. Every value carries an explicit number because a .tres stores enums as integers.

## The browser category of the item. Folder names do not matter, only this field.
enum Category { UNSET = 0, ROCK = 1, WOOD = 2, ORNAMENT = 3, PLANT = 4 }

## What the item is made of (Mode 2). Named ItemMaterial so it does not shadow the Material class.
enum ItemMaterial {
	UNSET = 0, STONE = 1, WOOD = 2, CERAMIC = 3, RESIN = 4, SHELL = 5, LIVE_PLANT = 6
}

## Effect of the item on a water value (Mode 2).
enum WaterEffect {
	UNSET = 0,
	INERT = 1,
	RAISES_SLIGHTLY = 2,
	RAISES = 3,
	LOWERS_SLIGHTLY = 4,
	LOWERS = 5,
}

## How much light a plant needs (Mode 2).
enum LightNeed { UNSET = 0, LOW = 1, MODERATE = 2, HIGH = 3 }

## The growth habit of a plant (Mode 2).
enum GrowthForm {
	UNSET = 0,
	STEM = 1,
	ROSETTE = 2,
	CARPET = 3,
	RHIZOME = 4,
	MOSS = 5,
	FLOATING = 6,
	BALL = 7,
}

## How a plant holds its place (Mode 2). LOOSE lies free on the substrate.
enum Anchoring { UNSET = 0, ROOTED = 1, EPIPHYTE = 2, FLOATING = 3, LOOSE = 4 }

# --- Mode 1 ---
@export var id: StringName = &""
@export var name_key: String = ""
@export var description_key: String = ""
@export var category: Category = Category.UNSET
## The placed instance. Its own scale is the drawn size (1 unit = 1 m).
@export var scene: PackedScene = null
@export var thumbnail: Texture2D = null
@export var sort_order: int = 0
@export var colourable: bool = false
## The swatches of a colourable item: alternatives to its original colour, which is never
## listed. Empty when the item is not colourable; otherwise 1 to 8 colours, each an exact 8-bit
## #RRGGBB colour, no duplicates (checked by the shipped-catalog test, not by the loader).
@export var colour_swatches: Array[Color] = []

# --- Mode 2, every item (stored, never shown or used in Mode 1) ---
@export var material: ItemMaterial = ItemMaterial.UNSET
@export var aquarium_safe: bool = true
@export var weight_kg: float = 0.0
@export var volume_displacement_l: float = 0.0
## Real size in cm: x width, y height, z depth. Shared: Mode 1 placement validity also reads it
## (#33, ADR 0012 Amendment 2); keep the real size, never tune it for placement.
@export var footprint_cm: Vector3 = Vector3.ZERO
@export var ph_effect: WaterEffect = WaterEffect.UNSET
@export var hardness_effect: WaterEffect = WaterEffect.UNSET
@export var tannin_release: float = 0.0
@export var hiding_places: int = 0
@export var hiding_quality: float = 0.0
@export var shade_cover: float = 0.0
@export var edge_smoothness: float = 0.0
@export var flow_obstruction: float = 0.0
@export var waste_trapping: float = 0.0
@export var cleaning_difficulty: float = 0.0
@export var algae_surface: float = 0.0
@export var breaks_down: bool = false

# --- Mode 2, live plants only (stored, never shown or used in Mode 1) ---
@export var growth_form: GrowthForm = GrowthForm.UNSET
@export var anchoring: Anchoring = Anchoring.UNSET
@export var light_need: LightNeed = LightNeed.UNSET
@export var growth_cm_per_week: float = 0.0
@export var max_height_cm: float = 0.0
@export var temp_min_c: float = 0.0
@export var temp_max_c: float = 0.0
@export var ph_min: float = 0.0
@export var ph_max: float = 0.0
@export var nutrient_uptake: float = 0.0
@export var oxygen_output: float = 0.0
@export var co2_need: float = 0.0
@export var substrate_rooting_need: float = 0.0
@export var nibble_vulnerability: float = 0.0
@export var provides_cover: bool = false
