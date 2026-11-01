extends RefCounted
## Which layer of a font chain supplies a character or a glyph.
##
## Static functions only, no state. It never creates a font: it works on any Font chain. Layer 1
## is the chain itself, then one layer per entry of chain.fallbacks. A character that only the
## operating system supplies is not a layer, so it counts as MISSING for supplying_layer().

const MISSING := 0


## RIDs of the layers in order: index 0 is layer 1, then the first RID of each fallback.
static func layer_rids(chain: Font) -> Array[RID]:
	var result: Array[RID] = []
	var own: Array[RID] = chain.get_rids()
	if not own.is_empty():
		result.append(own[0])
	for fallback: Font in chain.fallbacks:
		var rids: Array[RID] = fallback.get_rids()
		if not rids.is_empty():
			result.append(rids[0])
	return result


## The 1-based layer that has code_point (first one wins), or MISSING when none has it.
static func supplying_layer(chain: Font, code_point: int) -> int:
	var server: TextServer = TextServerManager.get_primary_interface()
	var rids: Array[RID] = layer_rids(chain)
	for index: int in rids.size():
		if server.font_has_char(rids[index], code_point):
			return index + 1
	return MISSING


## One Dictionary per shaped glyph: {"start", "end", "layer", "source"}. layer is 1..n or
## MISSING. source is "1".."n", "os:<face name>" or "missing".
static func glyph_sources(chain: Font, text: String, font_size: int = 16) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var server: TextServer = TextServerManager.get_primary_interface()
	var layers: Array[RID] = layer_rids(chain)
	var shaped: RID = server.create_shaped_text()
	server.shaped_text_add_string(shaped, text, chain.get_rids(), font_size)
	for glyph: Dictionary in server.shaped_text_get_glyphs(shaped):
		var font_rid: RID = glyph.get("font_rid", RID()) as RID
		var layer: int = MISSING
		var source: String = "missing"
		if font_rid.is_valid():
			var index: int = layers.find(font_rid)
			if index >= 0:
				layer = index + 1
				source = str(layer)
			else:
				source = "os:" + server.font_get_name(font_rid)
		(
			result
			. append(
				{
					"start": glyph.get("start", 0) as int,
					"end": glyph.get("end", 0) as int,
					"layer": layer,
					"source": source,
				}
			)
		)
	server.free_rid(shaped)
	return result


## Short summary of the distinct sources in order, for example "1", "1,2" or "os:Malgun Gothic".
static func summarize(sources: Array[Dictionary]) -> String:
	var seen: PackedStringArray = PackedStringArray()
	for entry: Dictionary in sources:
		var source: String = entry.get("source", "missing") as String
		if not seen.has(source):
			seen.append(source)
	return ", ".join(seen)
