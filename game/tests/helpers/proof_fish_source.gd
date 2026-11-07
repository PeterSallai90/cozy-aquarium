extends RefCounted
## Where the proof fish under test comes from (#21, criterion 10).
##
## Default: the committed res://assets/fish/proof_fish.glb, loaded through the importer, with its
## .import file. When the environment variable PROOF_FISH_GLB holds an absolute path, that
## temporary .glb is loaded at run time with GLTFDocument instead, the atlas is read from
## proof_palette_atlas.png next to it, and there is no import config (import_config is null).
## After open(), "problem" is "" when everything loaded; otherwise it names the cause.

const LfsGuard := preload("res://tests/helpers/lfs_guard.gd")

const ENV_NAME := "PROOF_FISH_GLB"
const COMMITTED_GLB := "res://assets/fish/proof_fish.glb"
const COMMITTED_ATLAS := "res://assets/fish/proof_palette_atlas.png"
const ATLAS_FILE := "proof_palette_atlas.png"

var problem: String = ""
var atlas_problem: String = ""
var glb_path: String = COMMITTED_GLB
var atlas_path: String = COMMITTED_ATLAS
var root: Node3D = null
var mesh: Mesh = null
var atlas: Image = null
var import_config: ConfigFile = null


func open() -> void:
	var override: String = OS.get_environment(ENV_NAME)
	if override.is_empty():
		_open_committed()
	else:
		_open_temporary(override)
	_open_atlas()
	if problem.is_empty():
		mesh = _first_mesh(root)


func release() -> void:
	if root != null and is_instance_valid(root):
		root.free()
	root = null
	mesh = null
	atlas = null


func is_temporary() -> bool:
	return not OS.get_environment(ENV_NAME).is_empty()


func _open_committed() -> void:
	glb_path = COMMITTED_GLB
	atlas_path = COMMITTED_ATLAS
	problem = LfsGuard.problem(glb_path, LfsGuard.GLB_MAGIC)
	if not problem.is_empty():
		return
	var scene: PackedScene = load(glb_path) as PackedScene
	if scene == null:
		problem = "import failed: %s did not load as a PackedScene" % glb_path
		return
	root = scene.instantiate() as Node3D
	if root == null:
		problem = "import failed: root of %s is not a Node3D" % glb_path
		return
	var config: ConfigFile = ConfigFile.new()
	if config.load(glb_path + ".import") != OK:
		problem = "missing: %s.import" % glb_path
		return
	import_config = config


func _open_temporary(path: String) -> void:
	glb_path = path
	atlas_path = path.get_base_dir().path_join(ATLAS_FILE)
	problem = LfsGuard.problem(path, LfsGuard.GLB_MAGIC)
	if not problem.is_empty():
		return
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	if document.append_from_file(path, state) != OK:
		problem = "import failed: GLTFDocument could not read %s" % path
		return
	root = document.generate_scene(state) as Node3D
	if root == null:
		problem = "import failed: root of %s is not a Node3D" % path


func _open_atlas() -> void:
	atlas_problem = LfsGuard.problem(atlas_path, LfsGuard.PNG_MAGIC)
	if not atlas_problem.is_empty():
		return
	var image: Image = Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(atlas_path)) != OK:
		atlas_problem = "png decode failed: %s" % atlas_path
		return
	image.convert(Image.FORMAT_RGBA8)
	atlas = image


func _first_mesh(node: Node) -> Mesh:
	for instance: MeshInstance3D in mesh_instances(node):
		return instance.mesh
	return null


static func mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		found.append_array(mesh_instances(child))
	return found
