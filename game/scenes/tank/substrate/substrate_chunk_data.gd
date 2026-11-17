class_name SubstrateChunkData
extends RefCounted
## One 5 cm column of an assembled substrate bed (data only, ADR 0011 rule 9). `buffers` holds one
## instance buffer per mesh variant (sand: one buffer), 16 floats per instance in tank-local
## metres: the 12 transform floats of the instancing layout (basis rows with the origin as the
## fourth column), then the custom data (lightness factor, hue shift in turns, saturation plus
## 4 x exposure, random 0..1).

## Column and row of the chunk on the floor grid (x from the left pane, z from the back pane).
var key: Vector2i = Vector2i.ZERO
## Tight bounds of the instances of the chunk, tank-local.
var aabb: AABB = AABB()
var buffers: Array[PackedFloat32Array] = []
## Instances per variant, the same order as `buffers`.
var counts: PackedInt32Array = PackedInt32Array()
## Per variant the instances that are seen from above or through a pane. They come first in the
## buffer; the rest are the stones kept behind them, which are only drawn near the camera.
var seen_counts: PackedInt32Array = PackedInt32Array()


func instance_count() -> int:
	var total: int = 0
	for count: int in counts:
		total += count
	return total


## The instances of variant `v` drawn at a distance: all of them near the camera, without the
## stones kept behind the visible ones beyond `behind_range_m` (0 = always all).
func drawn_count(v: int, distance: float, behind_range_m: float) -> int:
	if behind_range_m > 0.0 and distance > behind_range_m and v < seen_counts.size():
		return seen_counts[v]
	return counts[v]
