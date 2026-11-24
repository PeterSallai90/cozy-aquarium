class_name FishSpecies
extends Resource
## One fish species in the catalog (data only). Mode 1 fields are shown or used by the cozy
## builder; Mode 2 fields are stored for the future simulation mode and never shown or used in
## Mode 1. Enum values are only ever appended, never renumbered; UNSET is 0 on purpose so a
## correctly filled field never equals the empty default (#34, ADR 0013).

enum Zone { UNSET = 0, TOP = 1, MIDDLE = 2, BOTTOM = 3 }
enum Temperament { UNSET = 0, PEACEFUL = 1, SEMI_AGGRESSIVE = 2, AGGRESSIVE = 3 }
enum Light { UNSET = 0, LOW = 1, MODERATE = 2, HIGH = 3 }
## How a species keeps together (#35, ADR 0015). Append-only. `schooling` is true exactly for
## TIGHT_SCHOOL and FORAGING_GROUP; UNSET is never valid on a catalog species.
enum GroupStyle { UNSET = 0, SOLITARY = 1, TIGHT_SCHOOL = 2, LOOSE_GROUP = 3, FORAGING_GROUP = 4 }

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

# --- Mode 1: behaviour (#35, ADR 0015); inputs of the steering model, never dropped or renamed ---
## All default to 0 or UNSET, so a forgotten value fails the catalog test.
@export var group_style: GroupStyle = GroupStyle.UNSET
## Share of the time a fish hovers (0 to 1, before its personality factor).
@export var idle_share: float = 0.0
## Seconds between two darts (before the boldness of the fish), and how long a dart lasts.
@export var dart_interval_min_s: float = 0.0
@export var dart_interval_max_s: float = 0.0
@export var dart_duration_min_s: float = 0.0
@export var dart_duration_max_s: float = 0.0
## Turn rate cap in degrees per second and pitch limit in degrees.
@export var turn_rate_max_deg_s: float = 0.0
@export var pitch_limit_deg: float = 0.0
## Mean nose-down body pitch while cruising or hovering, in degrees (0 is a legal value).
@export var nose_down_bias_deg: float = 0.0

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
