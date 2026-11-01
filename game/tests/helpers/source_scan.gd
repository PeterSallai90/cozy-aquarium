extends RefCounted
## Shared code for the static source scans.


static func list_scripts(root: String, excluded: PackedStringArray) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	_walk(root, excluded, result)
	return result


static func strip_comments(source: String) -> String:
	var lines: PackedStringArray = source.split("\n")
	var kept: PackedStringArray = PackedStringArray()
	for line: String in lines:
		var hash_index: int = line.find("#")
		kept.append(line if hash_index < 0 else line.substr(0, hash_index))
	return "\n".join(kept)


static func find_matches(source: String, patterns: Array[RegEx]) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for pattern: RegEx in patterns:
		for hit: RegExMatch in pattern.search_all(source):
			result.append(hit.get_string())
	return result


static func compile(expressions: PackedStringArray) -> Array[RegEx]:
	var result: Array[RegEx] = []
	for expression: String in expressions:
		var regex: RegEx = RegEx.new()
		var error: int = regex.compile(expression)
		assert(error == OK, "bad regex %s" % expression)
		result.append(regex)
	return result


static func read(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


static func _walk(dir_path: String, excluded: PackedStringArray, result: PackedStringArray) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		var sub_path: String = dir_path.path_join(sub) + "/"
		if not _is_excluded(sub_path, excluded):
			_walk(sub_path.trim_suffix("/"), excluded, result)
	for file_name: String in dir.get_files():
		var file_path: String = dir_path.path_join(file_name)
		if file_name.ends_with(".gd") and not _is_excluded(file_path, excluded):
			result.append(file_path)


static func _is_excluded(path: String, excluded: PackedStringArray) -> bool:
	for prefix: String in excluded:
		if path.begins_with(prefix):
			return true
	return false
