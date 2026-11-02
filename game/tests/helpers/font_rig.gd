extends RefCounted
## Shared access for the B08 font tests.
##
## Everything is loaded at run time (never preload), so a missing font, theme or script fails
## one test with a clear message instead of aborting the whole suite on a parse error.

const NUNITO_PATH := "res://assets/fonts/nunito/nunito_variable.ttf"
const NOTO_PATH := "res://assets/fonts/noto_sans/noto_sans_variable.ttf"
const THEME_PATH := "res://ui/theme/cozy_theme.tres"
const LAYERS_PATH := "res://ui/fonts/font_layers.gd"
const SAMPLES_PATH := "res://ui/dev/glyph_samples.gd"
const SCENE_PATH := "res://ui/dev/glyph_test.tscn"


static func missing_font(path: String) -> String:
	return "font file missing: %s (awaiting owner download permission)" % path


static func missing(path: String) -> String:
	return "required file missing: %s" % path


## Loads a resource, or returns null without an engine error when the file does not exist. The
## caller must still assert on null: GdUnit stops the rest of a suite at the first engine error,
## so a bare load() of a missing file would hide the other failing tests.
static func load_or_null(path: String) -> Resource:
	if not ResourceLoader.exists(path):
		return null
	return load(path)


static func theme() -> Theme:
	return load_or_null(THEME_PATH) as Theme


## The default font chain of the theme (layer 1); null while the theme is missing.
static func chain() -> Font:
	var loaded: Theme = theme()
	if loaded == null:
		return null
	return loaded.default_font


static func layers() -> GDScript:
	return load_or_null(LAYERS_PATH) as GDScript


static func samples_script() -> GDScript:
	return load_or_null(SAMPLES_PATH) as GDScript


## The ROWS constant of the sample table; empty while the script is missing.
static func rows() -> Array:
	var script: GDScript = samples_script()
	if script == null:
		return []
	var constants: Dictionary = script.get_script_constant_map()
	return constants.get("ROWS", []) as Array


static func supplying_layer(font_chain: Font, code_point: int) -> int:
	return layers().call("supplying_layer", font_chain, code_point) as int


static func glyph_sources(font_chain: Font, text: String) -> Array:
	return layers().call("glyph_sources", font_chain, text) as Array


static func summarize(sources: Array) -> String:
	return layers().call("summarize", sources) as String


static func layer_rids(font_chain: Font) -> Array:
	return layers().call("layer_rids", font_chain) as Array


## The weight axis value of a FontVariation, or -1.0 when it is not set. Accepts the key as
## the string "wght" or as the OpenType tag number.
static func weight_of(variation: FontVariation) -> float:
	var coordinates: Dictionary = variation.variation_opentype
	var tag: int = TextServerManager.get_primary_interface().name_to_tag("wght")
	for key: Variant in coordinates:
		if key is String and key == "wght" or key is int and key == tag:
			return float(coordinates[key])
	return -1.0
