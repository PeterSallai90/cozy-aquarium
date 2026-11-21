class_name FishSpecies
extends Resource
## One fish species in the catalog (data only). Mode 1 fields are shown or used by the cozy
## builder; Mode 2 fields are stored for the future simulation mode and never shown or used in
## Mode 1. Enum values are only ever appended, never renumbered; UNSET is 0 on purpose so a
## correctly filled field never equals the empty default (#34, ADR 0013).

enum Zone { UNSET = 0, TOP = 1, MIDDLE = 2, BOTTOM = 3 }
enum Temperament { UNSET = 0, PEACEFUL = 1, SEMI_AGGRESSIVE = 2, AGGRESSIVE = 3 }
enum Light { UNSET = 0, LOW = 1, MODERATE = 2, HIGH = 3 }

# --- Mode 1: identity and presentation ---
## Frozen once a save can contain it, for example "neon_tetra".
@export var id: StringName = &""
## Translation key "fish.<id>.name".
@export var name_key: String = ""
## Translation key "fish.<id>.description".
@export var description_key: String = ""
## Latin binomial. Data, never a translation key and never in a .po or .pot file.
@export var scientific_name: String = ""
## Wrapper scene with the species ShaderMaterial (ADR 0013).
@export var scene: PackedScene = null
## Append-only: a saved fish stores `variant` as an index into this list. Never remove, reorder or
## change an entry; the snapshot test (game/tests/data/colour_variants_frozen.json, checked by
## game/tests/catalog/test_fish_colour_variants_frozen.gd) fails otherwise.
@export var colour_variants: Array[Color] = []
## Standard length (snout to tail base) in centimetres; drives the scale of the model.
@export var adult_length_cm: float = 0.0
@export var preferred_zone: Zone = Zone.UNSET
@export var schooling: bool = false
## Relative, 1.0 = a medium mid-water fish.
@export var swim_speed: float = 0.0

# --- Mode 2: simulation (stored now, used later) ---
@export var temp_min_c: float = 0.0
@export var temp_max_c: float = 0.0
@export var ph_min: float = 0.0
@export var ph_max: float = 0.0
@export var min_group_size: int = 0
@export var min_tank_litres: int = 0
## Waste production, a relative design scale (1.0 = one adult bronze corydoras).
@export var bioload: float = 0.0
@export var temperament: Temperament = Temperament.UNSET
## "flakes", "pellets", "sinking_pellets", "live", "frozen", "algae", "vegetable".
@export var diet: Array[StringName] = []
@export var light_preference: Light = Light.UNSET
@export var needs_hiding_places: bool = false
## Symmetric: each side names the other. Mode 2 only, Mode 1 ignores it.
@export var incompatible_with: Array[StringName] = []
