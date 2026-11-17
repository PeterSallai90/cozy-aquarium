class_name SubstrateChunkData
extends RefCounted
## One 5 cm column of an assembled substrate bed (data only, ADR 0011 rule 9). `buffers` holds one
## instance buffer per mesh variant (sand: one buffer), 16 floats per instance in tank-local
## metres: the 12 transform floats of the instancing layout (basis rows with the origin as the
## fourth column), then the custom data (lightness factor, hue shift in turns, saturation plus
## 4 x exposure, random 0..1).
##
## Draw order inside a buffer (the view draws a prefix of it, MultiMesh.visible_instance_count):
## 1. stones seen from above, 2. stones seen only through a pane, 3. stones kept behind the
## visible ones away from the glass, 4. stones kept behind at the glass. A camera on the inner
## side of every pane of the chunk cannot see the outer face of the stones at that glass: far
## away it draws 1, within the look's behind range 1 to 3. A camera beyond a pane of the chunk
## draws 1 and 2 far away and everything within the behind range (ADR 0011 rule 11: culling by
## the offline flags).

## Panes of a chunk (bits of `panes`), in the tank frame: front +z, back -z, left -x, right +x.
const PANE_FRONT: int = 1
const PANE_BACK: int = 2
const PANE_LEFT: int = 4
const PANE_RIGHT: int = 8
## Prefix ends per variant in `ends`: after part 1, after part 2, after part 3 of the draw order.
const ENDS: int = 3

## Column and row of the chunk on the floor grid (x from the left pane, z from the back pane).
var key: Vector2i = Vector2i.ZERO
## Tight bounds of the instances of the chunk, tank-local.
var aabb: AABB = AABB()
var buffers: Array[PackedFloat32Array] = []
## Instances per variant, the same order as `buffers`.
var counts: PackedInt32Array = PackedInt32Array()
## Per variant ENDS prefix ends of the draw order (empty: draw everything).
var ends: PackedInt32Array = PackedInt32Array()
## The panes whose stones (seen only through that glass) the chunk holds.
var panes: int = 0


func instance_count() -> int:
	var total: int = 0
	for count: int in counts:
		total += count
	return total


## The instances of variant `v` to draw: `near` (within the behind range of the look) keeps the
## stones kept behind the visible ones, `outside` (the camera beyond one of the chunk's panes)
## keeps the stones seen through that glass.
func drawn_count(v: int, near: bool, outside: bool) -> int:
	if v >= counts.size():
		return 0
	if ends.size() < (v + 1) * ENDS:
		return counts[v]
	if outside:
		return counts[v] if near else ends[v * ENDS + 1]
	return ends[v * ENDS + 2] if near else ends[v * ENDS]


## True when `camera_local` lies beyond the inner glass plane of one of the chunk's panes
## (`half` = half the inner floor size, x and z).
func is_outside(camera_local: Vector3, half: Vector2) -> bool:
	if panes == 0:
		return false
	return (
		((panes & PANE_FRONT) != 0 and camera_local.z > half.y)
		or ((panes & PANE_BACK) != 0 and camera_local.z < -half.y)
		or ((panes & PANE_LEFT) != 0 and camera_local.x < -half.x)
		or ((panes & PANE_RIGHT) != 0 and camera_local.x > half.x)
	)
