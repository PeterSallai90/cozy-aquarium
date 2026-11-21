extends GdUnitTestSuite
## #34 AC 36 (owner: developer): the dev route game/scenes/dev/fish_preview/fish_preview.tscn.
## Loaded headless it builds without errors or warnings, shows at least one fish of each species
## through FishView, and is not referenced from the main menu or any player-facing scene (a scan of
## the game files outside the scene's own folder and the tests finds no reference to it).

const Api := preload("res://tests/helpers/fish_api.gd")
const SourceScan := preload("res://tests/helpers/source_scan.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const SCENE := "res://scenes/dev/fish_preview/fish_preview.tscn"
const NEEDLE := "fish_preview"
const EXCLUDED: PackedStringArray = [
	"res://scenes/dev/fish_preview/",
	"res://tests/",
	"res://addons/",
	"res://reports/",
	"res://.godot/",
]


func _fish_views(root: Node) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for node: Node in root.find_children("*", "Node3D", true, false):
		var script: Script = node.get_script() as Script
		if script != null and script.resource_path == Api.VIEW_PATH:
			found.append(node as Node3D)
	return found


func _open() -> Dictionary:
	var holder: Array = []
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void:
			var packed: PackedScene = load(SCENE) as PackedScene
			var root: Node = packed.instantiate()
			add_child(root)
			auto_free(root)
			holder.append(root)
			await get_tree().process_frame
			await get_tree().process_frame
	)
	return {"root": holder[0] if not holder.is_empty() else null, "seen": seen}


func test_ac36_the_scene_exists() -> void:
	(
		assert_bool(ResourceLoader.exists(SCENE))
		. override_failure_message("%s is missing" % SCENE)
		. is_true()
	)


func test_ac36_the_scene_builds_without_errors_or_warnings() -> void:
	if not ResourceLoader.exists(SCENE):
		assert_bool(false).override_failure_message("%s is missing" % SCENE).is_true()
		return
	var opened: Dictionary = await _open()
	var seen: Dictionary = opened["seen"]
	assert_dict(seen["errors"]).override_failure_message("errors: %s" % [seen["errors"]]).is_empty()
	(
		assert_dict(seen["warnings"])
		. override_failure_message("warnings: %s" % [seen["warnings"]])
		. is_empty()
	)


func test_ac36_the_scene_shows_at_least_one_fish_of_each_species_through_fish_view() -> void:
	if not ResourceLoader.exists(SCENE):
		assert_bool(false).override_failure_message("%s is missing" % SCENE).is_true()
		return
	var opened: Dictionary = await _open()
	var root: Node = opened["root"]
	assert_object(root).is_not_null()
	if root == null:
		return
	var views: Array[Node3D] = _fish_views(root)
	assert_int(views.size()).override_failure_message("no FishView in the preview").is_greater(0)
	if views.is_empty():
		return
	var shown: Dictionary = {}
	for node: Node in views[0].get_children():
		shown[node.get_child(0).scene_file_path] = true
	for id: StringName in Api.IDS:
		var scene: PackedScene = Api.field(id, "scene", null) as PackedScene
		var wanted: String = (
			"res://assets/fish/scenes/%s.tscn" % id if scene == null else scene.resource_path
		)
		(
			assert_bool(shown.has(wanted))
			. override_failure_message("no %s in the preview" % id)
			. is_true()
		)


func test_ac36_no_player_facing_file_references_the_preview() -> void:
	var files: PackedStringArray = SourceScan.list_files(
		"res://", EXCLUDED, [".gd", ".tscn", ".tres", ".godot"]
	)
	assert_int(files.size()).is_greater(10)
	var hits: PackedStringArray = PackedStringArray()
	for path: String in files:
		if FileAccess.get_file_as_string(path).contains(NEEDLE):
			hits.append(path)
	(
		assert_str("\n".join(hits))
		. override_failure_message("referenced from: %s" % ", ".join(hits))
		. is_empty()
	)
	assert_bool(FileAccess.get_file_as_string("res://project.godot").contains(NEEDLE)).is_false()
