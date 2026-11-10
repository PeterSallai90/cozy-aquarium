extends GdUnitTestSuite
## #128 criterion 7, headless part (owner: tester): the water glint fix stays a parameter tuning
## of the water surface material. These are regression guards: they pass on develop before the fix
## on purpose, because a tuning issue has no honest failing-first test without hard-coding target
## values, which would remove the tuning freedom. The size, strength and shimmer criteria 1 to 5
## are measured in the real renderer by tests/measure/water_glint_measure.gd (headless Godot
## cannot render). The guards pin what must not change (values of develop at 4f8c55e) and that
## the glint is not removed.

const SURFACE_SHADER := "res://shaders/water_surface.gdshader"
const SURFACE_MATERIAL := "res://assets/tank/materials/water_surface.tres"
const GLASS_MATERIAL := "res://assets/tank/materials/tank_glass.tres"
const TINT_MATERIAL := "res://assets/tank/materials/water_depth_tint.tres"
const LAMP_SCENES: Dictionary = {
	"small": "res://scenes/room/lamp_small_1.tscn",
	"medium": "res://scenes/room/lamp_medium_1.tscn",
	"large": "res://scenes/room/lamp_large_1.tscn",
}
const KEY_ENERGY: Dictionary = {"small": 2.4, "medium": 3.0, "large": 4.4}
const KEY_SIZE: Dictionary = {"small": 0.03, "medium": 0.03, "large": 0.05}
const EPSILON := 0.00001

## Parameters of water_surface.tres that the fix must leave alone.
const SURFACE_UNCHANGED: Dictionary = {
	"surface_color": Color(0.78, 0.92, 0.94, 1),
	"surface_opacity": 0.06,
	"surface_reflection_color": Color(0.62, 0.66, 0.78, 1),
	"surface_reflection_strength": 0.35,
	"underside_color": Color(0.7, 0.86, 0.9, 1),
	"underside_opacity": 0.22,
	"underside_brightness": 0.12,
	"ripple_strength": 0.2,
	"ripple_cells_per_m": 45.0,
	"ripple_speed": 0.06,
	"meniscus_strength": 0.3,
	"meniscus_width_m": 0.003,
	"meniscus_color": Color(0.88, 0.96, 0.97, 1),
}
const GLASS_UNCHANGED: Dictionary = {
	"glass_opacity": 0.025,
	"glass_edge_tint": Color(0.42, 0.7, 0.56, 1),
	"glass_edge_opacity": 0.6,
	"glass_edge_brightness": 0.12,
	"glass_reflection_color": Color(0.7, 0.66, 0.8, 1),
	"glass_reflection_strength": 0.22,
	"glass_reflection_power": 5.0,
	"glass_roughness": 0.3,
	"glass_specular": 0.1,
}
const TINT_UNCHANGED: Dictionary = {
	"depth_tint_color": Color(0.55, 0.8, 0.85, 1),
	"depth_tint_strength": 0.25,
	"depth_tint_reference_m": 0.35,
}


func _material(path: String) -> ShaderMaterial:
	var exists: bool = ResourceLoader.exists(path)
	assert_bool(exists).override_failure_message("material missing: %s" % path).is_true()
	if not exists:
		return null
	var material: ShaderMaterial = load(path) as ShaderMaterial
	(
		assert_object(material)
		. override_failure_message("not a ShaderMaterial: %s" % path)
		. is_not_null()
	)
	return material


func _range_of(entry: Dictionary) -> PackedFloat64Array:
	if int(entry["hint"]) != PROPERTY_HINT_RANGE:
		return PackedFloat64Array()
	var parts: PackedStringArray = String(entry["hint_string"]).split(",")
	if parts.size() < 2:
		return PackedFloat64Array()
	return PackedFloat64Array([float(parts[0]), float(parts[1])])


func _uniform(shader: Shader, uniform_name: String) -> Dictionary:
	for entry: Dictionary in shader.get_shader_uniform_list():
		if entry["name"] == uniform_name:
			return entry
	return {}


func _same(actual: Variant, expected: Variant) -> bool:
	if expected is Color:
		var a: Color = actual as Color
		var e: Color = expected as Color
		return (
			absf(a.r - e.r) < EPSILON
			and absf(a.g - e.g) < EPSILON
			and absf(a.b - e.b) < EPSILON
			and absf(a.a - e.a) < EPSILON
		)
	return absf(float(actual) - float(expected)) < EPSILON


func _check_unchanged(path: String, expected: Dictionary) -> void:
	var material: ShaderMaterial = _material(path)
	if material == null:
		return
	for key: String in expected:
		var actual: Variant = material.get_shader_parameter(key)
		(
			assert_bool(actual != null and _same(actual, expected[key]))
			. override_failure_message(
				"%s: %s must stay %s, is %s" % [path, key, expected[key], actual]
			)
			. is_true()
		)


func test_ac7_every_ranged_surface_parameter_is_stored_inside_its_range() -> void:
	var material: ShaderMaterial = _material(SURFACE_MATERIAL)
	if material == null:
		return
	var shader: Shader = load(SURFACE_SHADER) as Shader
	assert_object(shader).override_failure_message("shader missing").is_not_null()
	if shader == null:
		return
	var checked: int = 0
	for entry: Dictionary in shader.get_shader_uniform_list():
		var range_limits: PackedFloat64Array = _range_of(entry)
		if range_limits.is_empty():
			continue
		var uniform_name: String = String(entry["name"])
		var value: Variant = material.get_shader_parameter(uniform_name)
		(
			assert_bool(value != null)
			. override_failure_message("%s is not stored in the material" % uniform_name)
			. is_true()
		)
		if value == null:
			continue
		var number: float = float(value)
		(
			assert_bool(number >= range_limits[0] - EPSILON and number <= range_limits[1] + EPSILON)
			. override_failure_message(
				(
					"%s = %s is outside [%s, %s]"
					% [uniform_name, number, range_limits[0], range_limits[1]]
				)
			)
			. is_true()
		)
		checked += 1
	assert_int(checked).override_failure_message("no ranged uniform found").is_greater(0)


func test_ac7_glint_parameters_stay_exposed_with_a_range_and_are_stored() -> void:
	var material: ShaderMaterial = _material(SURFACE_MATERIAL)
	var shader: Shader = load(SURFACE_SHADER) as Shader
	if material == null or shader == null:
		return
	for uniform_name: String in ["surface_roughness", "surface_specular"]:
		var entry: Dictionary = _uniform(shader, uniform_name)
		(
			assert_bool(not entry.is_empty() and not _range_of(entry).is_empty())
			. override_failure_message(
				"%s must stay an exposed uniform with hint_range" % uniform_name
			)
			. is_true()
		)
		(
			assert_bool(material.get_shader_parameter(uniform_name) != null)
			. override_failure_message("%s must be stored in the material" % uniform_name)
			. is_true()
		)


func test_ac3_the_glint_is_not_removed_specular_stays_above_zero() -> void:
	var material: ShaderMaterial = _material(SURFACE_MATERIAL)
	if material == null:
		return
	var specular: Variant = material.get_shader_parameter("surface_specular")
	assert_bool(specular != null and float(specular) > 0.0).is_true()
	var roughness: Variant = material.get_shader_parameter("surface_roughness")
	assert_bool(roughness != null and float(roughness) > 0.0).is_true()


func test_ac6_ripple_meniscus_and_reflection_parameters_stay_unchanged() -> void:
	_check_unchanged(SURFACE_MATERIAL, SURFACE_UNCHANGED)


func test_ac7_glass_parameters_stay_unchanged() -> void:
	_check_unchanged(GLASS_MATERIAL, GLASS_UNCHANGED)


func test_ac7_depth_tint_parameters_stay_unchanged() -> void:
	_check_unchanged(TINT_MATERIAL, TINT_UNCHANGED)


func test_ac7_surface_render_priority_stays_minus_one() -> void:
	var material: ShaderMaterial = _material(SURFACE_MATERIAL)
	if material == null:
		return
	assert_int(material.render_priority).is_equal(-1)


func test_ac7_lamp_key_and_bounce_lights_stay_unchanged() -> void:
	for tank_size: String in LAMP_SCENES:
		var path: String = LAMP_SCENES[tank_size]
		var scene: PackedScene = load(path) as PackedScene
		assert_object(scene).override_failure_message("lamp scene missing: %s" % path).is_not_null()
		if scene == null:
			continue
		var lamp: Node = scene.instantiate()
		auto_free(lamp)
		var key: SpotLight3D = lamp.get_node_or_null("KeyLight") as SpotLight3D
		var bounce: OmniLight3D = lamp.get_node_or_null("BounceLight") as OmniLight3D
		assert_object(key).override_failure_message("%s: no KeyLight" % tank_size).is_not_null()
		(
			assert_object(bounce)
			. override_failure_message("%s: no BounceLight" % tank_size)
			. is_not_null()
		)
		if key == null or bounce == null:
			continue
		assert_float(key.light_energy).is_equal_approx(KEY_ENERGY[tank_size], EPSILON)
		assert_float(key.light_size).is_equal_approx(KEY_SIZE[tank_size], EPSILON)
		assert_float(key.light_specular).is_equal_approx(0.5, EPSILON)
		assert_float(bounce.light_specular).is_equal_approx(0.0, EPSILON)
