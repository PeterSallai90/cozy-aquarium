extends GdUnitTestSuite
## #157 criterion 11 (owner: technical-artist): the three item thumbnails and the decor atlas
## import settings. Each thumbnail exists, is a real 256 x 256, 8-bit RGBA PNG with transparent
## corners, and its committed .import keeps fix alpha border on, mipmaps generated and lossless
## compression. CI runs the import before the tests, so these files are what Godot reads.
##
## Group that makes this file pass: technical-artist (stage 1: thumbnails, atlas and their .import).
## The thumbnails come from tools/blender/render_item_thumbnail.py with --atlas
## game/assets/items/decor_palette_atlas.png (a local Blender run; CI only checks the result).
##
## Test decisions where the plan is silent:
## - Plan section 4 adds detect_3d/compress_to=0 to the thumbnails (so a later 3D use cannot
##   rewrite the compression mode); it is asserted here too, next to the three settings of AC 11.
## - "8-bit RGBA" is read from the raw IHDR: bit depth byte 8, colour type 6.

const LfsGuard := preload("res://tests/helpers/lfs_guard.gd")

const IDS: Array[String] = ["river_stone", "driftwood_branch", "clay_amphora"]
const THUMBNAIL_DIR := "res://assets/items/thumbnails/"
const ATLAS_PATH := "res://assets/items/decor_palette_atlas.png"
const SIZE := 256
const IHDR_WIDTH_AT := 16
const IHDR_HEIGHT_AT := 20
const IHDR_DEPTH_AT := 24
const IHDR_COLOUR_TYPE_AT := 25
const COLOUR_TYPE_RGBA := 6


func _path(id: String) -> String:
	return THUMBNAIL_DIR + id + ".png"


func _bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path)


func _config(path: String) -> ConfigFile:
	var config: ConfigFile = ConfigFile.new()
	var error: int = config.load(path + ".import")
	assert_int(error).override_failure_message("%s.import is missing" % path).is_equal(OK)
	return config if error == OK else null


func test_ac11_each_thumbnail_exists_and_is_a_real_png() -> void:
	for id: String in IDS:
		(
			assert_str(LfsGuard.problem(_path(id), LfsGuard.PNG_MAGIC))
			. override_failure_message(id)
			. is_empty()
		)


func test_ac11_each_thumbnail_is_256_by_256_pixels() -> void:
	for id: String in IDS:
		var bytes: PackedByteArray = _bytes(_path(id))
		if bytes.size() < 33:
			assert_bool(false).override_failure_message("%s.png is missing or short" % id).is_true()
			continue
		# PNG stores the IHDR numbers big-endian; decode_u32 reads little-endian, so swap.
		var width: int = _be32(bytes, IHDR_WIDTH_AT)
		var height: int = _be32(bytes, IHDR_HEIGHT_AT)
		assert_int(width).override_failure_message("%s width" % id).is_equal(SIZE)
		assert_int(height).override_failure_message("%s height" % id).is_equal(SIZE)


func _be32(bytes: PackedByteArray, at: int) -> int:
	return (
		(int(bytes[at]) << 24)
		| (int(bytes[at + 1]) << 16)
		| (int(bytes[at + 2]) << 8)
		| int(bytes[at + 3])
	)


func test_ac11_each_thumbnail_is_8_bit_rgba() -> void:
	for id: String in IDS:
		var bytes: PackedByteArray = _bytes(_path(id))
		if bytes.size() < 33:
			assert_bool(false).override_failure_message("%s.png is missing or short" % id).is_true()
			continue
		assert_int(bytes[IHDR_DEPTH_AT]).override_failure_message("%s bit depth" % id).is_equal(8)
		(
			assert_int(bytes[IHDR_COLOUR_TYPE_AT])
			. override_failure_message("%s colour type must be 6 (RGBA)" % id)
			. is_equal(COLOUR_TYPE_RGBA)
		)


func test_ac11_all_four_corner_pixels_of_each_thumbnail_are_transparent() -> void:
	for id: String in IDS:
		var image: Image = Image.new()
		var error: int = image.load_png_from_buffer(_bytes(_path(id)))
		assert_int(error).override_failure_message("%s.png does not decode" % id).is_equal(OK)
		if error != OK:
			continue
		var last: int = SIZE - 1
		for corner: Vector2i in [
			Vector2i(0, 0), Vector2i(last, 0), Vector2i(0, last), Vector2i(last, last)
		]:
			(
				assert_float(image.get_pixelv(corner).a)
				. override_failure_message("%s corner %s is not transparent" % [id, corner])
				. is_equal(0.0)
			)


func test_ac11_each_thumbnail_import_has_fix_alpha_border_mipmaps_and_lossless_compression(
) -> void:
	for id: String in IDS:
		var config: ConfigFile = _config(_path(id))
		if config == null:
			continue
		var params: Dictionary = {
			"process/fix_alpha_border": true,
			"mipmaps/generate": true,
			"compress/mode": 0,
			"detect_3d/compress_to": 0,
		}
		for key: String in params:
			(
				assert_that(config.get_value("params", key, "<missing>"))
				. override_failure_message("%s.png.import: %s" % [id, key])
				. is_equal(params[key])
			)


func test_ac11_the_decor_atlas_import_is_lossless_without_mipmaps_and_never_vram_compressed(
) -> void:
	var config: ConfigFile = _config(ATLAS_PATH)
	if config == null:
		return
	var params: Dictionary = {
		"compress/mode": 0,
		"mipmaps/generate": false,
		"detect_3d/compress_to": 0,
		"process/fix_alpha_border": true,
	}
	for key: String in params:
		(
			assert_that(config.get_value("params", key, "<missing>"))
			. override_failure_message("decor_palette_atlas.png.import: %s" % key)
			. is_equal(params[key])
		)
