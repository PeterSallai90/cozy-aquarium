extends RefCounted
## The append-only rule of colour_variants (#34 AC 4) as a pure comparison: every species of the
## snapshot must still exist and its snapshot list must be an exact prefix of the current list.
## Both arguments map a species id to an Array of hex colour strings; colours are compared as
## exact 8-bit values, so the letter case and the optional alpha pair of a hex string do not
## matter. Each failure names the species and the index.

const SNAPSHOT_PATH := "res://tests/data/colour_variants_frozen.json"


## The snapshot file as {species id: Array of hex strings}; empty when it is missing or broken.
static func load_snapshot(path: String = SNAPSHOT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## {species id: Array of "#rrggbb" strings} of a FishCatalog-like set of definitions.
static func hex_lists(definitions: Array) -> Dictionary:
	var result: Dictionary = {}
	for definition: Resource in definitions:
		var list: Array = []
		for colour: Color in definition.get("colour_variants"):
			list.append("#" + colour.to_html(false))
		result[str(definition.get("id"))] = list
	return result


static func failures(snapshot: Dictionary, current: Dictionary) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for species: Variant in snapshot:
		var id: String = str(species)
		if not current.has(id):
			result.append("species %s: removed from the catalog (snapshot index 0)" % id)
			continue
		var frozen: Array = snapshot[species]
		var now: Array = current[id]
		for index: int in frozen.size():
			if index >= now.size():
				result.append("species %s index %d: colour removed" % [id, index])
				break
			var wanted: Color = Color.html(str(frozen[index]))
			var found: Color = Color.html(str(now[index]))
			if wanted.to_rgba32() != found.to_rgba32():
				result.append(
					(
						"species %s index %d: colour changed or reordered, frozen %s, now %s"
						% [id, index, frozen[index], now[index]]
					)
				)
				break
	return result
