class_name SubstrateAssemblyJob
extends RefCounted
## One assembly of a substrate bed on a worker thread (ADR 0011 rule 10, technical plan v3 1.8).
##
## The worker runs only SubstrateBakeData.load_file (when no baked data was given) and the pure
## SubstrateAssembler.assemble on the plain input; it writes nothing but the job's own two result
## fields, which the main thread reads only after it reaped the task. The main thread polls with
## poll() (is_task_completed first, then wait_for_task_completion, so it never blocks); it blocks
## only in finish_now() and wait_and_release(). A cancelled job has no result, whatever the worker
## got done before it noticed the token (checked at least once per chunk).
##
## Created, started, polled and released on the main thread only.

var _input: SubstrateAssemblyInput = null
var _bake_path: String = ""
var _bake: SubstrateBakeData = null
var _token: SubstrateCancelToken = SubstrateCancelToken.new()
var _task_id: int = -1
## True once there is no work left: the task was reaped, the assembly ran here, or the job was
## cancelled before it started.
var _done: bool = false
var _result: SubstrateBedData = null
## Written by the worker, read by the main thread after the task was reaped.
var _worker_bake: SubstrateBakeData = null
var _worker_result: SubstrateBedData = null


## `bake` may be null: the worker then reads `bake_path` itself (FileAccess only).
func _init(
	input: SubstrateAssemblyInput, bake_path: String, bake: SubstrateBakeData = null
) -> void:
	_input = input
	_bake_path = bake_path
	_bake = bake


## A job released while its task still runs (no owner waited) cancels it and waits, so the worker
## never runs on a freed object.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _task_id >= 0 and not _done:
		_token.cancel()
		WorkerThreadPool.wait_for_task_completion(_task_id)


## Hands the assembly to the worker thread pool. Does nothing when the job runs, ran or was
## cancelled.
func start() -> void:
	if _done or _task_id >= 0:
		return
	if _token.is_cancelled():
		_done = true
		return
	_task_id = WorkerThreadPool.add_task(_work, false, "SubstrateAssemblyJob")


## True when the job has no work left (finished, or cancelled and its task reaped); never blocks.
## A cancelled job that never started counts as finished.
func poll() -> bool:
	if _done:
		return true
	if _task_id < 0:
		if _token.is_cancelled():
			_done = true
		return _done
	if not WorkerThreadPool.is_task_completed(_task_id):
		return false
	_reap()
	return true


## Asks the worker to stop; it notices the token within one chunk.
func cancel() -> void:
	_token.cancel()


func is_cancelled() -> bool:
	return _token.is_cancelled()


## The assembled bed now: waits for the running task (only as long as it still needs), or
## assembles on the calling thread when the job has not started. Null when the job was cancelled
## or the assembly failed.
func finish_now() -> SubstrateBedData:
	if _done:
		return _result
	if _task_id >= 0:
		_reap()
		return _result
	_done = true
	if _token.is_cancelled():
		return null
	_work()
	_take_worker_output()
	return _result


## The assembled bed once the job is done; null before, after a cancel or a failure.
func get_result() -> SubstrateBedData:
	return _result


## The baked data the job used (given or read by the worker); null until it is known.
func get_bake() -> SubstrateBakeData:
	return _bake


## For leaving the tree: cancels, waits at most one chunk for a running task and drops the result.
func wait_and_release() -> void:
	_token.cancel()
	if _task_id >= 0 and not _done:
		WorkerThreadPool.wait_for_task_completion(_task_id)
		_take_worker_output()
	_done = true
	_result = null


## Worker thread (or the caller of finish_now): reads the baked data if needed and assembles.
func _work() -> void:
	var bake: SubstrateBakeData = _bake
	if bake == null and not _token.is_cancelled():
		bake = SubstrateBakeData.load_file(_bake_path)
	var result: SubstrateBedData = null
	if bake != null:
		result = SubstrateAssembler.assemble(_input, bake, _token)
	_worker_bake = bake
	_worker_result = result


func _reap() -> void:
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_take_worker_output()
	_done = true


func _take_worker_output() -> void:
	if _bake == null:
		_bake = _worker_bake
	_result = null if _token.is_cancelled() else _worker_result
	_worker_bake = null
	_worker_result = null
