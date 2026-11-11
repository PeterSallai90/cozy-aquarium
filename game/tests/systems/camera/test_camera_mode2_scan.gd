extends GdUnitTestSuite
## #26 (owner: developer): the camera code and the room that feeds it never read the Mode 2
## fields of the tank definition (light_slots, has_lid, heater_slots, filter_slots; Q17), and the
## helper scripts of the technical plan exist. Comments are stripped before the scan.

const Scan := preload("res://tests/helpers/source_scan.gd")

const CAMERA_DIR := "res://systems/camera/"
const ROOM_SCRIPT := "res://scenes/room/room_corner.gd"
const FORBIDDEN: PackedStringArray = ["light_slots", "has_lid", "heater_slots", "filter_slots"]
const HELPERS: PackedStringArray = [
	"res://systems/camera/camera_moves.gd",
	"res://systems/camera/camera_collision.gd",
	"res://systems/camera/camera_solids.gd",
]


func _scripts() -> PackedStringArray:
	var found: PackedStringArray = Scan.list_scripts(CAMERA_DIR, PackedStringArray())
	found.append(ROOM_SCRIPT)
	return found


func test_the_camera_helper_scripts_of_the_plan_exist() -> void:
	for path: String in HELPERS:
		(
			assert_bool(ResourceLoader.exists(path))
			. override_failure_message("%s is missing" % path)
			. is_true()
		)


func test_the_camera_code_does_not_read_mode_2_fields() -> void:
	var scripts: PackedStringArray = _scripts()
	assert_int(scripts.size()).is_greater_equal(5)
	for path: String in scripts:
		var source: String = Scan.strip_comments(Scan.read(path))
		assert_bool(source.is_empty()).is_false()
		for word: String in FORBIDDEN:
			(
				assert_bool(source.contains(word))
				. override_failure_message("%s reads %s" % [path, word])
				. is_false()
			)


func test_the_camera_settings_carry_no_mode_2_fields() -> void:
	var source: String = Scan.read("res://systems/camera/camera_settings.gd")
	for word: String in FORBIDDEN:
		assert_bool(source.contains(word)).is_false()
	assert_bool(source.contains("zoom_step_factor")).is_true()
