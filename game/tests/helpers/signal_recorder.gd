extends RefCounted
## Records the script signals of one or more objects into one ordered timeline.

var events: Array = []


func watch(source: Object) -> void:
	var script: Script = source.get_script() as Script
	for info: Dictionary in script.get_script_signal_list():
		var signal_name: StringName = info["name"]
		var error: int = source.connect(signal_name, _on_signal.bind(source, signal_name))
		assert(error == OK, "cannot watch signal %s" % signal_name)


func names() -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for event: Array in events:
		result.append(event[0])
	return result


func clear() -> void:
	events.clear()


func count() -> int:
	return events.size()


func args_of(index: int) -> Array:
	return events[index][1]


func _on_signal(...args: Array) -> void:
	# The bound arguments are appended after the signal arguments: [..., source, name].
	var signal_name: Variant = args.pop_back()
	args.pop_back()
	events.append([str(signal_name), args])
