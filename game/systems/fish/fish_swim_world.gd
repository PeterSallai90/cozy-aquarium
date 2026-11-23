class_name FishSwimWorld
extends RefCounted
## The tank as the steering model sees it (ADR 0015 rule 4): plain numbers and one Callable, no
## Node. All lengths are metres in the tank frame (x and z centred, y up from the floor).

## Interior size (x, y, z) of the water box.
var interior_size_m: Vector3 = Vector3.ZERO
var water_line_m: float = 0.0
## (x, z) -> height of the bed in metres, called on every query so an uneven bed plugs in.
var surface_at: Callable = Callable()
## Grain allowance of the substrate (FishZones, ADR 0013 rule 7).
var grain_allowance_m: float = 0.0
