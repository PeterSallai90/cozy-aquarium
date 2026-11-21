class_name FishExtents
extends RefCounted
## How far a scaled fish model reaches from its origin, in metres (ADR 0013). Derived from the
## model vertices, never a catalog field.

## The largest horizontal distance sqrt(x^2 + z^2) of any vertex; independent of the facing.
var horizontal_radius_m: float = 0.0
## The reach below the origin (positive), fins included.
var below_m: float = 0.0
## The reach above the origin (positive), fins included.
var above_m: float = 0.0


static func create(radius_m: float, below: float, above: float) -> FishExtents:
	var result: FishExtents = FishExtents.new()
	result.horizontal_radius_m = radius_m
	result.below_m = below
	result.above_m = above
	return result
