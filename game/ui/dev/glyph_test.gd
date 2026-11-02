extends Control
## Developer glyph test scene: one row per sample, plus a LineEdit for the manual IME check.
## It shows which font layer draws each glyph. Nothing here is translated and no font is set:
## the chain comes from the global theme, like every other control.

const FontLayers := preload("res://ui/fonts/font_layers.gd")
const GlyphSamples := preload("res://ui/dev/glyph_samples.gd")

@onready var _rows: VBoxContainer = $Scroll/Rows
@onready var _input: LineEdit = $Input
@onready var _input_source: Label = $InputSource


func _ready() -> void:
	for row: Dictionary in GlyphSamples.ROWS:
		_rows.add_child(_build_row(row))
	_input.text_changed.connect(_on_input_text_changed)
	_on_input_text_changed(_input.text)


func _build_row(row: Dictionary) -> HBoxContainer:
	var informational: bool = row["informational"] as bool
	var box: HBoxContainer = HBoxContainer.new()
	box.name = "Row_" + (row["id"] as String)
	box.set_meta("informational", informational)
	var script_label: Label = Label.new()
	script_label.text = row["script"] as String
	script_label.custom_minimum_size.x = 140.0
	var sample: Label = Label.new()
	sample.text = row["text"] as String
	sample.custom_minimum_size.x = 320.0
	var source: Label = Label.new()
	source.text = _describe(row["text"] as String, informational)
	box.add_child(script_label)
	box.add_child(sample)
	box.add_child(source)
	return box


func _describe(text: String, informational: bool) -> String:
	var summary: String = FontLayers.summarize(FontLayers.glyph_sources(_chain(), text))
	return ("informational: " if informational else "") + summary


func _chain() -> Font:
	return get_theme_font("font")


func _on_input_text_changed(new_text: String) -> void:
	_input_source.text = FontLayers.summarize(FontLayers.glyph_sources(_chain(), new_text))
