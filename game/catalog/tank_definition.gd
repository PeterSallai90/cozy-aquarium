class_name TankDefinition
extends Resource
## One tank in the catalog (data only). Mode 1 fields are shown or used by the cozy builder;
## Mode 2 fields are stored for the future simulation mode and never shown or used in Mode 1.

# --- Mode 1 ---
@export var id: StringName = &""
@export var name_key: String = ""
@export var description_key: String = ""
@export var scene: PackedScene = null
## Interior size in metres: x length, y height, z depth.
@export var interior_size_m: Vector3 = Vector3.ZERO
## Nominal capacity shown to the player (Mode 1 info and Mode 2 base).
@export var volume_litres: int = 0
@export var glass_thickness_m: float = 0.0
@export var water_line_height_m: float = 0.0

# --- Mode 2 (stored, never shown or used in Mode 1) ---
@export var empty_weight_kg: float = 0.0
@export var heat_loss_factor: float = 1.0
@export var evaporation_l_per_day: float = 0.0
@export var heater_slots: int = 0
@export var filter_slots: int = 0
@export var light_slots: int = 0
@export var recommended_heater_watts: int = 0
@export var recommended_filter_lph: int = 0
@export var has_lid: bool = false


## Outer size of the glass box (the trim is not counted).
func get_exterior_size_m() -> Vector3:
	return Vector3(
		interior_size_m.x + 2.0 * glass_thickness_m,
		interior_size_m.y + glass_thickness_m,
		interior_size_m.z + 2.0 * glass_thickness_m
	)


## Size of the water body: length, water line height, depth.
func get_water_volume_size_m() -> Vector3:
	return Vector3(interior_size_m.x, water_line_height_m, interior_size_m.z)
