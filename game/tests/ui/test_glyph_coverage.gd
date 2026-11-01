extends GdUnitTestSuite
## Glyph coverage through the font API, driven by the theme chain and the shared sample table.
## It never names a font family. Hungarian must come from layer 1 alone, Cyrillic and Greek from
## a bundled layer. CJK and emoji rows are informational: printed, never asserted.

const FontRig := preload("res://tests/helpers/font_rig.gd")

const NO_FONT_CODE_POINT := 0x10FFFD
const HUNGARIAN_ACCENTS := "áéíóöúüÁÉÍÓÖÚÜ"
const DOUBLE_ACUTE := "őűŐŰ"
const REQUIRED_IDS: Array[String] = [
	"hungarian",
	"hungarian_upper",
	"russian",
	"greek",
	"mixed",
	"chinese_sc",
	"chinese_tc",
	"japanese",
	"korean",
	"mixed_cjk",
	"emoji",
]
const ROW_KEYS: Array[String] = ["id", "script", "text", "informational", "layer1_only"]


func _chain() -> Font:
	var chain: Font = FontRig.chain()
	assert_object(chain).override_failure_message(FontRig.missing(FontRig.THEME_PATH)).is_not_null()
	return chain


## The chain and the layer helper, or null (with a failed assertion) when either is missing.
func _chain_with_helper() -> Font:
	var chain: Font = _chain()
	(
		assert_object(FontRig.layers())
		. override_failure_message(FontRig.missing(FontRig.LAYERS_PATH))
		. is_not_null()
	)
	if FontRig.layers() == null:
		return null
	return chain


func _rows() -> Array:
	var rows: Array = FontRig.rows()
	(
		assert_array(rows)
		. override_failure_message("sample table missing or empty: " + FontRig.SAMPLES_PATH)
		. is_not_empty()
	)
	return rows


func _nunito() -> FontFile:
	var chain: FontVariation = _chain() as FontVariation
	if chain == null:
		return null
	var nunito: FontFile = chain.base_font as FontFile
	(
		assert_object(nunito)
		. override_failure_message(FontRig.missing_font(FontRig.NUNITO_PATH))
		. is_not_null()
	)
	return nunito


func _row(id: String) -> Dictionary:
	for row: Dictionary in _rows():
		if row.get("id", "") == id:
			return row
	fail("sample row missing: " + id)
	return {}


func _lacking(font: FontFile, text: String) -> PackedStringArray:
	var missing: PackedStringArray = PackedStringArray()
	for index: int in text.length():
		var code_point: int = text.unicode_at(index)
		if not font.has_char(code_point):
			missing.append("U+%04X" % code_point)
	return missing


func test_nunito_alone_covers_all_of_latin_extended_a() -> void:
	var nunito: FontFile = _nunito()
	if nunito == null:
		return
	var missing: PackedStringArray = PackedStringArray()
	for code_point: int in range(0x0100, 0x0180):
		if not nunito.has_char(code_point):
			missing.append("U+%04X" % code_point)
	(
		assert_array(Array(missing))
		. override_failure_message(
			(
				(
					"Nunito lacks %s. Post these code points on issue #19 and tell the orchestrator:"
					+ " the story is blocked (needs:decision), no fallback patch."
				)
				% ", ".join(missing)
			)
		)
		. is_empty()
	)


func test_nunito_alone_has_the_hungarian_double_acute_letters() -> void:
	var nunito: FontFile = _nunito()
	if nunito == null:
		return
	(
		assert_array(Array(_lacking(nunito, DOUBLE_ACUTE)))
		. override_failure_message("Nunito lacks one of the Hungarian letters ő ű Ő Ű")
		. is_empty()
	)


func test_nunito_alone_has_the_other_hungarian_accented_letters() -> void:
	var nunito: FontFile = _nunito()
	if nunito == null:
		return
	(
		assert_array(Array(_lacking(nunito, HUNGARIAN_ACCENTS)))
		. override_failure_message("Nunito lacks one of the Hungarian letters " + HUNGARIAN_ACCENTS)
		. is_empty()
	)


func test_the_layer_helper_lists_the_three_layers_in_order() -> void:
	var chain: Font = _chain_with_helper()
	if chain == null:
		return
	var rids: Array = FontRig.layer_rids(chain)
	assert_int(rids.size()).is_equal(3)
	if rids.size() == 3:
		assert_bool(rids[0] == chain.get_rids()[0]).is_true()


func test_the_sample_table_has_every_row_with_unique_ids_and_all_keys() -> void:
	var seen: Array[String] = []
	for row: Dictionary in _rows():
		for key: String in ROW_KEYS:
			(
				assert_bool(row.has(key))
				. override_failure_message("row %s lacks key %s" % [row.get("id", "?"), key])
				. is_true()
			)
		var id: String = row.get("id", "") as String
		assert_bool(seen.has(id)).override_failure_message("duplicate row id " + id).is_false()
		seen.append(id)
	for id: String in REQUIRED_IDS:
		assert_bool(seen.has(id)).override_failure_message("sample row missing: " + id).is_true()


func test_the_table_flags_cjk_and_emoji_informational_and_the_rest_asserted() -> void:
	var informational: Array[String] = [
		"chinese_sc", "chinese_tc", "japanese", "korean", "mixed_cjk", "emoji"
	]
	var asserted: Array[String] = ["hungarian", "hungarian_upper", "russian", "greek", "mixed"]
	for id: String in informational:
		(
			assert_bool(_row(id).get("informational", false))
			. override_failure_message("row %s must be informational" % id)
			. is_true()
		)
	for id: String in asserted:
		(
			assert_bool(_row(id).get("informational", true))
			. override_failure_message("row %s must not be informational" % id)
			. is_false()
		)
	for id: String in ["hungarian", "hungarian_upper"]:
		(
			assert_bool(_row(id).get("layer1_only", false))
			. override_failure_message("row %s must be layer1_only" % id)
			. is_true()
		)


func test_every_character_of_a_bundled_row_comes_from_a_bundled_layer() -> void:
	var chain: Font = _chain_with_helper()
	if chain == null:
		return
	for row: Dictionary in _rows():
		if row.get("informational", false):
			continue
		var text: String = row.get("text", "") as String
		var layers: PackedStringArray = PackedStringArray()
		for index: int in text.length():
			var code_point: int = text.unicode_at(index)
			var layer: int = FontRig.supplying_layer(chain, code_point)
			layers.append(str(layer))
			(
				assert_bool(layer == 1 or layer == 2)
				. override_failure_message(
					(
						"row %s: U+%04X comes from layer %d, expected 1 or 2"
						% [row["id"], code_point, layer]
					)
				)
				. is_true()
			)
			if row.get("layer1_only", false):
				(
					assert_int(layer)
					. override_failure_message(
						"row %s: U+%04X must come from Nunito (layer 1)" % [row["id"], code_point]
					)
					. is_equal(1)
				)
		print("glyph row %s: layers %s" % [row["id"], ",".join(layers)])


func test_informational_rows_are_recorded_and_never_asserted() -> void:
	var chain: Font = _chain_with_helper()
	if chain == null:
		return
	var count: int = 0
	for row: Dictionary in _rows():
		if not row.get("informational", false):
			continue
		count += 1
		var text: String = row.get("text", "") as String
		var layers: PackedStringArray = PackedStringArray()
		for index: int in text.length():
			layers.append(str(FontRig.supplying_layer(chain, text.unicode_at(index))))
		var summary: String = FontRig.summarize(FontRig.glyph_sources(chain, text))
		print(
			"glyph row %s (informational): %s | layers %s" % [row["id"], summary, ",".join(layers)]
		)
		(
			assert_float(chain.get_string_size(text).x)
			. override_failure_message("row %s has no width" % row["id"])
			. is_greater(0.0)
		)
	assert_int(count).override_failure_message("no informational rows in the table").is_greater(0)


func test_a_character_in_no_font_does_not_crash_or_hang() -> void:
	var chain: Font = _chain_with_helper()
	if chain == null:
		return
	assert_int(FontRig.supplying_layer(chain, NO_FONT_CODE_POINT)).is_equal(0)
	var text: String = "A" + char(NO_FONT_CODE_POINT) + "鱼"
	var label: Label = auto_free(Label.new()) as Label
	label.text = text
	add_child(label)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(label.get_minimum_size().x).is_greater(0.0)
	var sources: Array = FontRig.glyph_sources(chain, text)
	assert_array(sources).is_not_empty()
	print("no-font string: " + FontRig.summarize(sources))


func test_the_layer_of_ascii_is_nunito() -> void:
	var chain: Font = _chain_with_helper()
	if chain == null:
		return
	assert_int(FontRig.supplying_layer(chain, 0x41)).is_equal(1)


func test_greek_comes_from_a_bundled_layer_and_not_from_the_system() -> void:
	var chain: Font = _chain_with_helper()
	if chain == null:
		return
	var layer: int = FontRig.supplying_layer(chain, 0x0393)
	(
		assert_bool(layer == 1 or layer == 2)
		. override_failure_message("Greek Gamma comes from layer %d" % layer)
		. is_true()
	)


func test_a_mixed_string_has_width_and_each_glyph_comes_from_the_expected_layer() -> void:
	var chain: Font = _chain_with_helper()
	if chain == null:
		return
	var text: String = _row("mixed").get("text", "") as String
	assert_str(text).is_not_empty()
	assert_float(chain.get_string_size(text).x).is_greater(0.0)
	var sources: Array = FontRig.glyph_sources(chain, text)
	assert_array(sources).is_not_empty()
	for glyph: Dictionary in sources:
		var start: int = glyph["start"] as int
		var layer: int = glyph["layer"] as int
		var expected: int = FontRig.supplying_layer(chain, text.unicode_at(start))
		(
			assert_bool(layer == 1 or layer == 2)
			. override_failure_message(
				(
					"glyph at %d (U+%04X) drawn by layer %d (%s)"
					% [start, text.unicode_at(start), layer, glyph["source"]]
				)
			)
			. is_true()
		)
		(
			assert_int(layer)
			. override_failure_message(
				(
					"glyph at %d drawn by layer %d, but layer %d has the character"
					% [start, layer, expected]
				)
			)
			. is_equal(expected)
		)
		assert_str(glyph["source"] as String).is_equal(str(layer))
		if text.unicode_at(start) < 0x80:
			(
				assert_int(layer)
				. override_failure_message("Latin glyph at %d is not Nunito" % start)
				. is_equal(1)
			)


func test_a_mixed_string_uses_both_bundled_layers() -> void:
	var chain: Font = _chain_with_helper()
	if chain == null:
		return
	var sources: Array = FontRig.glyph_sources(chain, "Neon Γειά")
	var layers: Array[int] = []
	for glyph: Dictionary in sources:
		if not layers.has(glyph["layer"] as int):
			layers.append(glyph["layer"] as int)
	layers.sort()
	assert_array(layers).is_equal([1, 2])
	var summary: String = FontRig.summarize(sources)
	assert_bool(summary.contains("1") and summary.contains("2")).is_true()


func test_glyph_sources_of_an_empty_string_is_empty() -> void:
	var chain: Font = _chain_with_helper()
	if chain == null:
		return
	assert_array(FontRig.glyph_sources(chain, "")).is_empty()


func test_summarize_names_a_missing_glyph() -> void:
	if _chain_with_helper() == null:
		return
	var sources: Array[Dictionary] = [{"start": 0, "end": 1, "layer": 0, "source": "missing"}]
	assert_str(FontRig.summarize(sources)).contains("missing")
