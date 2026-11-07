extends RefCounted
## Tells a Git LFS pointer file from the real binary (#21, criterion 23).
##
## A checkout without `git lfs pull` leaves a short text file where the binary should be. The
## engine would then report a generic import or load error, so every test that reads an LFS
## asset calls problem() first and fails with the readable text instead.

const GLB_MAGIC: PackedByteArray = [0x67, 0x6C, 0x54, 0x46]
const PNG_MAGIC: PackedByteArray = [0x89, 0x50, 0x4E, 0x47]
const POINTER_PREFIX := "version https://git-lfs.github.com/spec/v1"
const POINTER_MAX_BYTES := 1024


## Returns "" when the file is the real binary, else the reason it is not.
static func problem(path: String, magic: PackedByteArray) -> String:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return "missing: %s" % path
	if bytes.size() < POINTER_MAX_BYTES:
		var head: String = bytes.get_string_from_ascii()
		if head.begins_with(POINTER_PREFIX):
			return "LFS pointer, run git lfs pull: %s" % path
	if bytes.slice(0, magic.size()) != magic:
		return "not a %s file: %s" % [_kind(magic), path]
	return ""


static func _kind(magic: PackedByteArray) -> String:
	if magic == GLB_MAGIC:
		return "glb"
	if magic == PNG_MAGIC:
		return "png"
	return "binary"
