extends GdUnitTestSuite
## #34 AC 8, 31 and 37 (owner: technical-artist, stage 1): the species mask textures
## game/assets/fish/<id>_mask.png, 256 x 256 px RGBA8, linear data, sampled with UV0. R and G are
## the pattern regions, B holds the eye as hard bands (0 none, 85 pupil, 170 iris ring, 255 dot,
## tolerance 20), A marks the tintable body (0 or 255, tolerance 20; never on an eye texel, never
## on a texel a fin triangle samples). Every species has a pupil band and a dot band (at least one
## 3 x 3 block); only the angelfish has an iris band, every texel of the 2 texel ring around its
## pupil and dot is iris. The import file keeps all four channels as authored (no premultiplied
## alpha, no colour bleed into A = 0 texels): mip level 0 of the imported texture equals the PNG.
## The edge cases are synthetic images fed to the same checker: a dot below 3 x 3, an iris band on
## the neon tetra or the corydoras, an empty alpha region, an alpha texel inside the eye band and a
## premultiplied-alpha import all fail.

const Api := preload("res://tests/helpers/fish_api.gd")
const Checks := preload("res://tests/helpers/fish_species_checks.gd")

const SIZE := 256


## A valid synthetic mask: eye at (100..119, 100..119) with a pupil, the dot in the middle,
## optionally an iris ring around; a body region elsewhere; R and G regions for the neon.
func _synthetic(with_iris: bool, dot_side: int = 3, body: bool = true) -> Image:
	var image: Image = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color8(0, 0, 0, 0))
	if body:
		for y: int in range(10, 60):
			for x: int in range(10, 200):
				image.set_pixel(x, y, Color8(255, 255, 0, 255))
	for y: int in range(10, 20):
		for x: int in range(200, 210):
			image.set_pixel(x, y, Color8(0, 255, 0, 0))
	if with_iris:
		for y: int in range(96, 124):
			for x: int in range(96, 124):
				image.set_pixel(x, y, Color8(0, 0, 170, 0))
	for y: int in range(100, 120):
		for x: int in range(100, 120):
			image.set_pixel(x, y, Color8(0, 0, 85, 0))
	for y: int in dot_side:
		for x: int in dot_side:
			image.set_pixel(105 + x, 105 + y, Color8(0, 0, 255, 0))
	return image


func _failures(id: StringName, image: Image) -> PackedStringArray:
	return Checks.mask_failures(image, id)


# --- the committed masks ---


func test_ac08_ac31_ac37_every_committed_mask_passes_the_mask_rules() -> void:
	for id: StringName in Api.IDS:
		var image: Image = Checks.load_mask(id)
		assert_object(image).override_failure_message("%s: mask is missing" % id).is_not_null()
		if image == null:
			continue
		var failures: PackedStringArray = _failures(id, image)
		(
			assert_str("\n".join(failures))
			. override_failure_message("%s: %s" % [id, "; ".join(failures)])
			. is_empty()
		)


func test_ac08_the_masks_are_at_most_256_by_256_and_exactly_256_rgba() -> void:
	for id: StringName in Api.IDS:
		var image: Image = Checks.load_mask(id)
		assert_object(image).override_failure_message("%s: mask is missing" % id).is_not_null()
		if image == null:
			continue
		assert_int(image.get_width()).is_equal(SIZE)
		assert_int(image.get_height()).is_equal(SIZE)
		assert_int(image.get_format()).is_equal(Image.FORMAT_RGBA8)


func test_ac37_no_texel_a_fin_triangle_samples_has_a_body_alpha() -> void:
	for id: StringName in Api.IDS:
		var model: Checks.FishModel = Checks.open(id)
		var image: Image = Checks.load_mask(id)
		(
			assert_str(model.problem)
			. override_failure_message("%s: %s" % [id, model.problem])
			. is_empty()
		)
		assert_object(image).override_failure_message("%s: mask is missing" % id).is_not_null()
		if model.problem.is_empty() and image != null:
			var failures: PackedStringArray = Checks.fin_alpha_failures(model, image)
			assert_str("; ".join(failures)).override_failure_message(id).is_empty()
		model.release()


func test_ac31_the_dot_and_the_pupil_are_on_both_sides_of_the_head_in_uv0() -> void:
	for id: StringName in Api.IDS:
		var model: Checks.FishModel = Checks.open(id)
		var image: Image = Checks.load_mask(id)
		(
			assert_str(model.problem)
			. override_failure_message("%s: %s" % [id, model.problem])
			. is_empty()
		)
		assert_object(image).override_failure_message("%s: mask is missing" % id).is_not_null()
		if model.problem.is_empty() and image != null:
			var left: int = 0
			var right: int = 0
			var samples: Dictionary = Checks.surface_samples(model, model.body)
			var points: PackedVector3Array = samples["points"]
			var uvs: PackedVector2Array = samples["uvs"]
			for index: int in points.size():
				if Checks.band_at(image, uvs[index]) >= 1:
					if points[index].x > 0.0:
						right += 1
					else:
						left += 1
			(
				assert_bool(left > 0 and right > 0)
				. override_failure_message("%s: eye samples left %d right %d" % [id, left, right])
				. is_true()
			)
		model.release()


# --- import settings ---


func test_ac37_the_import_files_keep_the_channels_as_authored() -> void:
	for id: StringName in Api.IDS:
		var config: ConfigFile = ConfigFile.new()
		var path: String = Checks.mask_path(id) + ".import"
		var loaded: bool = config.load(path) == OK
		assert_bool(loaded).override_failure_message("missing: %s" % path).is_true()
		if not loaded:
			continue
		var failures: PackedStringArray = Checks.mask_import_failures(config)
		(
			assert_str("; ".join(failures))
			. override_failure_message("%s: %s" % [id, failures])
			. is_empty()
		)


func test_ac37_mip_level_0_of_the_imported_texture_equals_the_png_texel_for_texel() -> void:
	for id: StringName in Api.IDS:
		var source: Image = Checks.load_mask(id)
		var texture: Texture2D = null
		if ResourceLoader.exists(Checks.mask_path(id)):
			texture = load(Checks.mask_path(id)) as Texture2D
		assert_object(source).override_failure_message("%s: mask is missing" % id).is_not_null()
		(
			assert_object(texture)
			. override_failure_message("%s: mask did not import" % id)
			. is_not_null()
		)
		if source == null or texture == null:
			continue
		var imported: Image = texture.get_image()
		imported.decompress()
		imported.convert(Image.FORMAT_RGBA8)
		var differing: int = 0
		for y: int in SIZE:
			for x: int in SIZE:
				if source.get_pixel(x, y) != imported.get_pixel(x, y):
					differing += 1
		(
			assert_int(differing)
			. override_failure_message("%s: %d texels differ after the import" % [id, differing])
			. is_equal(0)
		)


func test_ac37_the_mask_is_imported_as_linear_data_with_mipmaps() -> void:
	for id: StringName in Api.IDS:
		var texture: Texture2D = null
		if ResourceLoader.exists(Checks.mask_path(id)):
			texture = load(Checks.mask_path(id)) as Texture2D
		(
			assert_object(texture)
			. override_failure_message("%s: mask did not import" % id)
			. is_not_null()
		)
		if texture != null:
			var image: Image = texture.get_image()
			(
				assert_bool(image.has_mipmaps())
				. override_failure_message(
					"%s: no mipmaps (R and G are read with the mipmapped sampler)" % id
				)
				. is_true()
			)


# --- edge cases on synthetic images ---


func test_ac31_edge_the_synthetic_baseline_passes_for_each_species_kind() -> void:
	assert_str("; ".join(_failures(&"neon_tetra", _synthetic(false)))).is_empty()
	assert_str("; ".join(_failures(&"bronze_corydoras", _synthetic(false)))).is_empty()
	var ring: Image = _synthetic(true)
	# The ring texels around the pupil are band 2, so the iris rule holds for the angelfish.
	assert_str("; ".join(_failures(&"angelfish", ring))).is_empty()


func test_ac31_edge_a_dot_below_3_by_3_texels_fails() -> void:
	var failures: PackedStringArray = _failures(&"neon_tetra", _synthetic(false, 2))
	assert_str("; ".join(failures)).contains("3 x 3")


func test_ac31_edge_an_iris_band_on_the_neon_tetra_or_the_corydoras_fails() -> void:
	assert_int(_failures(&"neon_tetra", _synthetic(true)).size()).is_greater(0)
	assert_int(_failures(&"bronze_corydoras", _synthetic(true)).size()).is_greater(0)


func test_ac31_edge_the_angelfish_without_an_iris_ring_fails() -> void:
	assert_str("; ".join(_failures(&"angelfish", _synthetic(false)))).contains("iris")


func test_ac31_edge_an_iris_ring_narrower_than_2_texels_fails() -> void:
	var image: Image = _synthetic(true)
	# Paint a band-0 notch into the ring one texel from the pupil.
	for y: int in range(96, 124):
		image.set_pixel(99, y, Color8(0, 0, 0, 0))
	assert_int(_failures(&"angelfish", image).size()).is_greater(0)


func test_ac31_edge_a_blue_level_outside_the_tolerance_fails() -> void:
	var image: Image = _synthetic(false)
	image.set_pixel(30, 100, Color8(0, 0, 128, 0))
	assert_str("; ".join(_failures(&"neon_tetra", image))).contains("tolerance").is_not_empty()


func test_ac37_edge_an_empty_alpha_region_fails() -> void:
	var failures: PackedStringArray = _failures(&"neon_tetra", _synthetic(false, 3, false))
	assert_str("; ".join(failures)).contains("empty")


func test_ac37_edge_an_alpha_texel_inside_the_eye_band_fails() -> void:
	var image: Image = _synthetic(false)
	image.set_pixel(110, 110, Color8(0, 0, 85, 255))
	assert_str("; ".join(_failures(&"neon_tetra", image))).contains("eye")


func test_ac37_edge_a_premultiplied_alpha_import_fails() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("params", "compress/mode", 0)
	config.set_value("params", "mipmaps/generate", true)
	config.set_value("params", "process/fix_alpha_border", false)
	config.set_value("params", "process/premult_alpha", true)
	config.set_value("params", "detect_3d/compress_to", 0)
	config.set_value("params", "process/size_limit", 0)
	config.set_value("params", "process/channel_remap/red", 0)
	config.set_value("params", "process/channel_remap/green", 1)
	config.set_value("params", "process/channel_remap/blue", 2)
	config.set_value("params", "process/channel_remap/alpha", 3)
	var failures: PackedStringArray = Checks.mask_import_failures(config)
	assert_int(failures.size()).is_equal(1)
	assert_str(failures[0]).contains("premult_alpha")
	config.set_value("params", "process/premult_alpha", false)
	config.set_value("params", "process/fix_alpha_border", true)
	assert_str("; ".join(Checks.mask_import_failures(config))).contains("fix_alpha_border")
