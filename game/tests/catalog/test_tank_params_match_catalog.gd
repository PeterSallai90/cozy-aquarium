extends GdUnitTestSuite
## #24 plan section 3 (drift guard, criteria 11 and 23): the Blender parameter files of the tanks
## mirror the catalog .tres, so the catalog, the JSON and the generated glb cannot drift apart.
## The Python generator tests need Blender and do not run in CI, so this guard is a GdUnit test.
## The files are read from the repository folder next to game/ (tools/blender/params).

const Api := preload("res://tests/helpers/late_api.gd")
const Table := preload("res://tests/helpers/tank_table.gd")

## Scalars are doubles and compare to 1e-9; the interior size is a Vector3 of 32-bit floats.
const EXACT := 1e-9
const VECTOR_PRECISION := 1e-6
const KEYS: Array[String] = [
	"interior_length_m",
	"interior_height_m",
	"interior_depth_m",
	"glass_thickness_m",
	"trim_size_m",
]


func _params_dir() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../tools/blender/params")


func _param_files() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(_params_dir())
	assert_object(dir).override_failure_message("cannot open %s" % _params_dir()).is_not_null()
	if dir == null:
		return result
	for file: String in dir.get_files():
		if file.begins_with("tank_") and file.ends_with(".json"):
			result.append(file)
	result.sort()
	return result


func _read(file: String) -> Dictionary:
	var text: String = FileAccess.get_file_as_string(_params_dir().path_join(file))
	var parsed: Variant = JSON.parse_string(text)
	(
		assert_bool(parsed is Dictionary)
		. override_failure_message("%s is not a JSON object" % file)
		. is_true()
	)
	return parsed if parsed is Dictionary else {}


func _expected(definition: Resource) -> Dictionary:
	var interior: Vector3 = Api.prop(definition, "interior_size_m", Vector3.ZERO)
	return {
		"interior_length_m": interior.x,
		"interior_height_m": interior.y,
		"interior_depth_m": interior.z,
		"glass_thickness_m": Api.prop(definition, "glass_thickness_m", Api.MISSING_NUMBER),
		"trim_size_m": Api.prop(definition, "trim_size_m", Api.MISSING_NUMBER),
	}


func test_ac23_there_is_one_parameter_file_per_catalog_tank_and_no_extra() -> void:
	var expected: Array[String] = []
	for id: StringName in Table.IDS:
		expected.append("%s.json" % id)
	assert_array(_param_files()).contains_exactly_in_any_order(expected)


func test_ac23_each_parameter_file_has_exactly_the_documented_keys() -> void:
	for file: String in _param_files():
		var keys: Array = _read(file).keys()
		keys.sort()
		var wanted: Array = KEYS.duplicate()
		wanted.sort()
		assert_array(keys).override_failure_message("%s keys" % file).is_equal(wanted)


func test_ac23_trim_width_and_height_keys_are_replaced_by_trim_size_m() -> void:
	for file: String in _param_files():
		var data: Dictionary = _read(file)
		assert_bool(data.has("trim_width_m")).override_failure_message(file).is_false()
		assert_bool(data.has("trim_height_m")).override_failure_message(file).is_false()


func test_ac23_every_key_equals_the_catalog_value() -> void:
	var catalog: RefCounted = Api.catalog_load_dir("res://catalog/tanks")
	for id: StringName in Table.IDS:
		var definition: Resource = Api.definition_of(catalog, id)
		assert_object(definition).override_failure_message("%s not in catalog" % id).is_not_null()
		if definition == null:
			continue
		var file: String = "%s.json" % id
		var data: Dictionary = _read(file)
		var wanted: Dictionary = _expected(definition)
		for key: String in KEYS:
			(
				assert_bool(data.has(key))
				. override_failure_message("%s lacks %s" % [file, key])
				. is_true()
			)
			if not data.has(key):
				continue
			(
				assert_float(float(data[key]))
				. override_failure_message(
					"%s: %s is %s, the catalog says %s" % [file, key, data[key], wanted[key]]
				)
				. is_equal_approx(
					float(wanted[key]), VECTOR_PRECISION if key.begins_with("interior") else EXACT
				)
			)
