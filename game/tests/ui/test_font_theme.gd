extends GdUnitTestSuite
## The global theme: one default font chain Nunito, Noto Sans, SystemFont, inherited by every
## control, and unchanged by a language switch.

const FontRig := preload("res://tests/helpers/font_rig.gd")
const SaveFixtures := preload("res://tests/helpers/save_fixtures.gd")

var _dir: String = ""
var _saved_locale: String = ""


func before_test() -> void:
	_dir = SaveFixtures.make_dir("font_theme")
	_saved_locale = TranslationServer.get_locale()


func after_test() -> void:
	TranslationServer.set_locale(_saved_locale)
	SaveFixtures.remove_dir(_dir)
	SaveFixtures.remove_root_if_empty()


func _theme() -> Theme:
	var theme: Theme = FontRig.theme()
	assert_object(theme).override_failure_message(FontRig.missing(FontRig.THEME_PATH)).is_not_null()
	return theme


func _chain() -> FontVariation:
	var theme: Theme = _theme()
	if theme == null:
		return null
	var chain: FontVariation = theme.default_font as FontVariation
	(
		assert_object(chain)
		. override_failure_message("theme default_font must be a FontVariation (layer 1)")
		. is_not_null()
	)
	return chain


func _fallback_count(chain: FontVariation) -> int:
	return 0 if chain == null else chain.fallbacks.size()


func test_default_font_is_a_variation_over_nunito_at_weight_400() -> void:
	var chain: FontVariation = _chain()
	if chain == null:
		return
	(
		assert_object(chain.base_font)
		. override_failure_message("layer 1 has no base font")
		. is_not_null()
	)
	if chain.base_font == null:
		return
	assert_str(chain.base_font.resource_path).is_equal(FontRig.NUNITO_PATH)
	assert_float(FontRig.weight_of(chain)).is_equal(400.0)


func test_the_chain_has_exactly_two_fallbacks() -> void:
	var chain: FontVariation = _chain()
	if chain == null:
		return
	assert_int(chain.fallbacks.size()).is_equal(2)
	(
		assert_int(chain.get_rids().size())
		. override_failure_message("the chain must resolve to 3 layers")
		. is_equal(3)
	)


func test_layer_two_is_a_variation_over_noto_sans_at_weight_400() -> void:
	var chain: FontVariation = _chain()
	assert_int(_fallback_count(chain)).is_greater_equal(1)
	if _fallback_count(chain) < 1:
		return
	var noto: FontVariation = chain.fallbacks[0] as FontVariation
	(
		assert_object(noto)
		. override_failure_message("fallbacks[0] must be a FontVariation")
		. is_not_null()
	)
	if noto == null or noto.base_font == null:
		return
	assert_str(noto.base_font.resource_path).is_equal(FontRig.NOTO_PATH)
	assert_float(FontRig.weight_of(noto)).is_equal(400.0)


func test_layer_three_is_a_system_font_with_the_generic_sans_serif_name() -> void:
	var chain: FontVariation = _chain()
	assert_int(_fallback_count(chain)).is_greater_equal(2)
	if _fallback_count(chain) < 2:
		return
	var last: Font = chain.fallbacks[chain.fallbacks.size() - 1]
	(
		assert_bool(last is SystemFont)
		. override_failure_message("the last layer must be a SystemFont")
		. is_true()
	)
	if last is SystemFont:
		assert_array(Array((last as SystemFont).font_names)).contains(["sans-serif"])


func test_the_theme_holds_no_other_font() -> void:
	var theme: Theme = _theme()
	if theme == null:
		return
	assert_array(Array(theme.get_font_type_list())).is_empty()


func test_the_project_setting_points_to_the_theme() -> void:
	var path: String = ProjectSettings.get_setting("gui/theme/custom", "") as String
	assert_str(path).is_equal(FontRig.THEME_PATH)
	var theme: Theme = _theme()
	if theme != null:
		assert_object(ThemeDB.get_project_theme()).is_same(theme)


func _inherits_the_default_font(control: Control) -> void:
	var theme: Theme = _theme()
	if theme == null:
		control.free()
		return
	add_child(auto_free(control))
	(
		assert_object(control.get_theme_font("font"))
		. override_failure_message(
			"%s does not resolve to the theme default font" % control.get_class()
		)
		. is_same(theme.default_font)
	)


func test_a_label_resolves_to_the_default_font() -> void:
	_inherits_the_default_font(Label.new())


func test_a_button_resolves_to_the_default_font() -> void:
	_inherits_the_default_font(Button.new())


func test_a_line_edit_resolves_to_the_default_font() -> void:
	_inherits_the_default_font(LineEdit.new())


func test_a_text_edit_resolves_to_the_default_font() -> void:
	_inherits_the_default_font(TextEdit.new())


func test_a_language_switch_leaves_the_font_unchanged_without_a_restart() -> void:
	var theme: Theme = _theme()
	if theme == null:
		return
	var label: Label = auto_free(Label.new()) as Label
	add_child(label)
	var before: Font = label.get_theme_font("font")
	assert_object(before).is_same(theme.default_font)
	var service: LanguageService = LanguageService.new(
		SettingsStore.new(_dir.path_join("settings.cfg"))
	)
	service.start("en_US")
	assert_int(service.set_language("hu")).is_equal(OK)
	await get_tree().process_frame
	assert_object(label.get_theme_font("font")).is_same(before)
	assert_object(ThemeDB.get_project_theme().default_font).is_same(before)
	assert_int(service.set_language("en")).is_equal(OK)
	await get_tree().process_frame
	assert_object(label.get_theme_font("font")).is_same(before)
	assert_object(ThemeDB.get_project_theme().default_font).is_same(before)
