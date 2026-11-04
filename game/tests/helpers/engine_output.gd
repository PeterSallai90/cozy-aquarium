extends RefCounted
## Counting helper for engine output (#91, ADR 0004).
##
## Runs an action once and returns what it logged, by kind and exact text, with a count per text.
## Every captured entry is removed from the running test's GdUnit4 error monitor, so the caller's
## assert on the returned counts is the only check, and it must be exact (each text as a key,
## the value its exact count). Script errors are never consumed and stay with GdUnit4.
##
## Uses GdUnit4 6.2.2 internals, like GdUnitGodotErrorAssertImpl; the self-tests catch an upgrade.


## Usage: var seen: Dictionary = await EngineOutput.capture(func() -> void: ...)
## Returns {"errors": {text: count}, "warnings": {text: count}}.
static func capture(action: Callable) -> Dictionary:
	var logger: GodotGdErrorMonitor.GdUnitLogger = GodotGdErrorMonitor.GdUnitLogger.new(true, true)
	await action.call()
	var errors: Dictionary = {}
	var warnings: Dictionary = {}
	var monitor: GodotGdErrorMonitor = (
		GdUnitThreadManager.get_current_context().get_execution_context().error_monitor
	)
	for entry: ErrorLogEntry in logger.entries():
		if entry._type == ErrorLogEntry.TYPE.PUSH_ERROR:
			errors[entry._message] = int(errors.get(entry._message, 0)) + 1
		elif entry._type == ErrorLogEntry.TYPE.PUSH_WARNING:
			warnings[entry._message] = int(warnings.get(entry._message, 0)) + 1
		else:
			continue
		monitor.erase_log_entry(entry)
	OS.remove_logger(logger)
	return {"errors": errors, "warnings": warnings}


## Like capture, and also returns what the action returned, under "result".
static func capture_result(action: Callable) -> Dictionary:
	var results: Array = []
	var seen: Dictionary = await capture(func() -> void: results.append(await action.call()))
	seen["result"] = results[0] if not results.is_empty() else null
	return seen
