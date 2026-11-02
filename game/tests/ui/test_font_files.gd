extends GdUnitTestSuite
## The bundled font files: they load, they are not empty, they ship their license and they are
## imported as compressed dynamic fonts.

const FontRig := preload("res://tests/helpers/font_rig.gd")

const FONTS: Array[String] = [FontRig.NUNITO_PATH, FontRig.NOTO_PATH]


func _font(path: String) -> FontFile:
	var font: FontFile = FontRig.load_or_null(path) as FontFile
	assert_object(font).override_failure_message(FontRig.missing_font(path)).is_not_null()
	return font


func _import_config(path: String) -> ConfigFile:
	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load(path + ".import")
	(
		assert_int(error)
		. override_failure_message(
			"import file missing or unreadable: %s.import (%s)" % [path, error_string(error)]
		)
		. is_equal(OK)
	)
	return config


func test_each_font_loads_as_a_font_file_with_a_name() -> void:
	for path: String in FONTS:
		var font: FontFile = _font(path)
		if font != null:
			(
				assert_str(font.get_font_name())
				. override_failure_message("font has no name: " + path)
				. is_not_empty()
			)


func test_each_font_has_the_letter_a() -> void:
	for path: String in FONTS:
		var font: FontFile = _font(path)
		if font != null:
			(
				assert_bool(font.has_char(0x41))
				. override_failure_message("font lacks U+0041: " + path)
				. is_true()
			)


func test_each_font_holds_data() -> void:
	for path: String in FONTS:
		var font: FontFile = _font(path)
		if font != null:
			(
				assert_int(font.data.size())
				. override_failure_message("font data is empty: " + path)
				. is_greater(0)
			)


func test_each_font_folder_has_the_ofl_license_text() -> void:
	for path: String in FONTS:
		var license: String = path.get_base_dir().path_join("OFL.txt")
		(
			assert_bool(FileAccess.file_exists(license))
			. override_failure_message(FontRig.missing(license))
			. is_true()
		)
		var text: String = (
			FileAccess.get_file_as_string(license) if FileAccess.file_exists(license) else ""
		)
		(
			assert_str(text)
			. override_failure_message("license text is empty: " + license)
			. is_not_empty()
		)


func test_each_font_is_imported_with_compression_on() -> void:
	for path: String in FONTS:
		var config: ConfigFile = _import_config(path)
		var value: Variant = config.get_value("params", "compress", null)
		(
			assert_bool(value == true)
			. override_failure_message("[params] compress must be true in %s.import" % path)
			. is_true()
		)


func test_each_font_is_imported_as_a_dynamic_font_not_msdf() -> void:
	for path: String in FONTS:
		var config: ConfigFile = _import_config(path)
		var value: Variant = config.get_value("params", "multichannel_signed_distance_field", null)
		(
			assert_bool(value == false)
			. override_failure_message(
				"[params] multichannel_signed_distance_field must be false in %s.import" % path
			)
			. is_true()
		)
