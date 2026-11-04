extends RefCounted
## Counting helper for engine output (#91, ADR 0004).
##
## Runs an action once and returns what it logged, by kind and exact text, with a count per text.
## Every captured entry is removed from the running test's GdUnit4 error monitor, so the caller's
## assert on the returned counts is the only check, and it must be exact (each text as a key,
## the value its exact count). capture leaves script errors to GdUnit4; capture_all consumes
## them too, under "script_errors" (#92).
##
## Uses GdUnit4 6.2.2 internals, like GdUnitGodotErrorAssertImpl; the self-tests catch an upgrade.


## Usage: var seen: Dictionary = await EngineOutput.capture(func() -> void: ...)
## Returns {"errors": {text: count}, "warnings": {text: count}}. Script errors stay with GdUnit4.
static func capture(action: Callable) -> Dictionary:
	return await _capture(action, false)


## Like capture, and also consumes script errors. Returns
## {"errors": {text: count}, "warnings": {text: count}, "script_errors": {text: count}}.
static func capture_all(action: Callable) -> Dictionary:
	return await _capture(action, true)


static func _capture(action: Callable, include_script_errors: bool) -> Dictionary:
	var logger: GodotGdErrorMonitor.GdUnitLogger = GodotGdErrorMonitor.GdUnitLogger.new(true, true)
	await action.call()
	var errors: Dictionary = {}
	var warnings: Dictionary = {}
	var script_errors: Dictionary = {}
	var monitor: GodotGdErrorMonitor = (
		GdUnitThreadManager.get_current_context().get_execution_context().error_monitor
	)
	for entry: ErrorLogEntry in logger.entries():
		if entry._type == ErrorLogEntry.TYPE.PUSH_ERROR:
			errors[entry._message] = int(errors.get(entry._message, 0)) + 1
		elif entry._type == ErrorLogEntry.TYPE.PUSH_WARNING:
			warnings[entry._message] = int(warnings.get(entry._message, 0)) + 1
		elif include_script_errors and entry._type == ErrorLogEntry.TYPE.SCRIPT_ERROR:
			script_errors[entry._message] = int(script_errors.get(entry._message, 0)) + 1
		else:
			continue
		monitor.erase_log_entry(entry)
	OS.remove_logger(logger)
	var result: Dictionary = {"errors": errors, "warnings": warnings}
	if include_script_errors:
		result["script_errors"] = script_errors
	return result


## Like capture, and also returns what the action returned, under "result".
static func capture_result(action: Callable) -> Dictionary:
	var results: Array = []
	var seen: Dictionary = await capture(func() -> void: results.append(await action.call()))
	seen["result"] = results[0] if not results.is_empty() else null
	return seen
