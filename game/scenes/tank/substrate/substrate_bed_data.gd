class_name SubstrateBedData
extends RefCounted
## One assembled substrate bed (data only): the output of SubstrateAssembler.assemble and the
## input of SubstrateBedView (ADR 0011 rule 9). Everything is in tank-local metres (x and z
## centred on the inner floor, floor at y = 0, front glass at +z). Never saved.

const FLOATS: int = 16
const PLACEMENT_FLOATS: int = 5

## The input the bed was assembled from.
var input: SubstrateAssemblyInput = null
var chunks: Array[SubstrateChunkData] = []
## Shared instance buffers of the top tiles (sand only), in the frame of a tile: x and z relative
## to the centre of the cell, y tank-local. A cell draws one or more of them.
var top_tiles: Array[PackedFloat32Array] = []
## Per top tile placement 5 floats: x and z of the cell centre, quarter turns, mirror, tile index.
## Every tile-based type lists every cell of its top lattice here with its fill. A negative tile
## index (-1 - fill) means the stones of the cell are in the chunk buffers (stone types). A sand
## cell at a pane is listed once per tile part it draws, the part with the middle of the cell
## last.
var top_placements: PackedFloat32Array = PackedFloat32Array()
## Edge of a top lattice cell in metres (0 when the type has no tiles).
var top_pitch_m: float = 0.0
## Lowest and highest point of the top tile grains (tank-local y), for the cell bounds.
var top_y_range: Vector2 = Vector2.ZERO
## The dark core box behind and under the shell.
var core_size: Vector3 = Vector3.ZERO
var core_centre: Vector3 = Vector3.ZERO
## Median drawn grain size of the baked data in metres (the unit of the shading depths).
var median_size_m: float = 0.0


## Unique instance buffer entries: every chunk instance and every shared tile grain once.
func unique_stone_count() -> int:
	var total: int = 0
	for chunk: SubstrateChunkData in chunks:
		for buffer: PackedFloat32Array in chunk.buffers:
			# buffer.size() / FLOATS: float count to record count; chunk buffers hold
			# whole records, so there is no remainder.
			@warning_ignore("integer_division")
			total += buffer.size() / FLOATS
	for tile: PackedFloat32Array in top_tiles:
		# tile.size() / FLOATS: float count to record count; top tiles hold whole
		# records, so there is no remainder.
		@warning_ignore("integer_division")
		total += tile.size() / FLOATS
	return total


## Bytes of the instance buffers and placements held in memory.
func byte_size() -> int:
	var total: int = top_placements.size() * 4
	for chunk: SubstrateChunkData in chunks:
		for buffer: PackedFloat32Array in chunk.buffers:
			total += buffer.size() * 4
	for tile: PackedFloat32Array in top_tiles:
		total += tile.size() * 4
	return total


## The instances of top tile `index` (0 when the index names no shared tile).
func tile_instance_count(index: int) -> int:
	if index < 0 or index >= top_tiles.size():
		return 0
	# top tile size / FLOATS: float count to record count; top tiles hold whole
	# records, so there is no remainder.
	@warning_ignore("integer_division")
	return top_tiles[index].size() / FLOATS
