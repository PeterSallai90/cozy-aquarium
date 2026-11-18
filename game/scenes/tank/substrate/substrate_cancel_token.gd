class_name SubstrateCancelToken
extends RefCounted
## A cancel flag shared between the main thread and one assembly on a worker thread (ADR 0011
## rule 10). The assembler asks it at least once per chunk; a cancelled assembly returns null.

var _mutex: Mutex = Mutex.new()
var _cancelled: bool = false


func cancel() -> void:
	_mutex.lock()
	_cancelled = true
	_mutex.unlock()


func is_cancelled() -> bool:
	_mutex.lock()
	var value: bool = _cancelled
	_mutex.unlock()
	return value
