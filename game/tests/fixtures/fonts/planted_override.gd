extends Label
## Planted offences for the font override scan test. It lives under tests/, so the real scan
## never reads it.


func _ready() -> void:
	add_theme_font_override("font", FontVariation.new())
	var file: FontFile = FontFile.new()
	file.load_dynamic_font("res://planted.ttf")
	var bitmap: FontFile = FontFile.new()
	bitmap.load_bitmap_font("res://planted.fnt")
	var system: SystemFont = SystemFont.new()
	add_theme_font_override("font", system)
