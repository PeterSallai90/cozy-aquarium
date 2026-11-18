extends GdUnitTestSuite
## #28 criterion 32, the assembly job (owner: developer: SubstrateAssemblyJob runs the pure
## assembler on WorkerThreadPool; the assembler itself is the technical-artist's). The main thread
## polls the job and only then reaps the task; a cancelled job returns null and builds nothing more;
## finish_now() waits for the running task, or assembles on the calling thread when the job has not
## started, and gives the same data as the threaded path (technical plan v3, 1.8). Headless tests
## use finish_now() and bounded polling; no test waits on frames for the bed.

const Api := preload("res://tests/helpers/substrate_bed_api.gd")
const Fixture := preload("res://tests/helpers/substrate_bed_fixture.gd")
const Sub := preload("res://tests/helpers/substrate_api.gd")
const Table := preload("res://tests/helpers/tank_table.gd")
const EngineOutput := preload("res://tests/helpers/engine_output.gd")

const POLL_LIMIT_MSEC := 60000
const CANCEL_REACTION_MSEC := 500


func _have_pipeline(tank_id: StringName, id: StringName) -> bool:
	var missing: String = Api.missing_script([Api.JOB_PATH])
	assert_str(missing).is_empty()
	var why: String = Fixture.problem(tank_id, id)
	assert_str(why).override_failure_message("%s in %s: %s" % [id, tank_id, why]).is_empty()
	return missing.is_empty() and why.is_empty()


func _job(tank_id: StringName, id: StringName, preloaded_bake: bool = false) -> RefCounted:
	var look: Resource = Api.look_of(id)
	var script: GDScript = load(Api.JOB_PATH) as GDScript
	var input: RefCounted = Api.create_input(tank_id, id, look)
	var bake: RefCounted = Fixture.bake_of(tank_id, id) if preloaded_bake else null
	return script.new(input, Api.bake_path(look, tank_id), bake) as RefCounted


## Polls until the job reports finished or cancelled; false after the limit.
func _poll_until_done(job: RefCounted, limit_msec: int = POLL_LIMIT_MSEC) -> bool:
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < limit_msec:
		if bool(job.call("poll")):
			return true
		OS.delay_msec(2)
	return false


func test_ac32_a_job_runs_on_a_worker_and_delivers_the_same_bed_as_a_plain_assembly() -> void:
	for id: StringName in [Sub.PEBBLES, Sub.COLOURED, Sub.SAND]:
		if not _have_pipeline(Table.SMALL, id):
			return
		var job: RefCounted = _job(Table.SMALL, id)
		job.call("start")
		(
			assert_bool(_poll_until_done(job))
			. override_failure_message("%s: the job never finished" % id)
			. is_true()
		)
		(
			assert_bool(Api.beds_equal(Fixture.bed_of(Table.SMALL, id), job.call("get_result")))
			. override_failure_message("%s: the job result differs from the plain assembly" % id)
			. is_true()
		)
		assert_object(job.call("get_bake")).is_not_null()
		assert_bool(bool(job.call("is_cancelled"))).is_false()


func test_ac32_finish_now_gives_the_same_bed_when_the_job_was_started_and_when_it_was_not() -> void:
	if not _have_pipeline(Table.SMALL, Sub.COLOURED):
		return
	var started: RefCounted = _job(Table.SMALL, Sub.COLOURED)
	started.call("start")
	var from_running: RefCounted = started.call("finish_now")
	var not_started: RefCounted = _job(Table.SMALL, Sub.COLOURED)
	var from_idle: RefCounted = not_started.call("finish_now")
	var wanted: RefCounted = Fixture.bed_of(Table.SMALL, Sub.COLOURED)
	(
		assert_bool(Api.beds_equal(wanted, from_running))
		. override_failure_message("running job")
		. is_true()
	)
	assert_bool(Api.beds_equal(wanted, from_idle)).override_failure_message("idle job").is_true()
	assert_bool(Api.beds_equal(wanted, started.call("get_result"))).is_true()


func test_ac32_a_job_given_the_baked_data_keeps_that_object() -> void:
	if not _have_pipeline(Table.SMALL, Sub.PEBBLES):
		return
	var job: RefCounted = _job(Table.SMALL, Sub.PEBBLES, true)
	job.call("finish_now")
	assert_bool(is_same(job.call("get_bake"), Fixture.bake_of(Table.SMALL, Sub.PEBBLES))).is_true()


func test_ac32_a_job_cancelled_before_the_start_returns_null() -> void:
	if not _have_pipeline(Table.SMALL, Sub.GRAVEL):
		return
	var job: RefCounted = _job(Table.SMALL, Sub.GRAVEL)
	job.call("cancel")
	assert_bool(bool(job.call("is_cancelled"))).is_true()
	job.call("start")
	assert_bool(_poll_until_done(job)).is_true()
	assert_object(job.call("get_result")).is_null()


func test_ac32_a_job_cancelled_while_running_finishes_quickly_with_no_result() -> void:
	if not _have_pipeline(Table.LARGE, Sub.GRAVEL):
		return
	var job: RefCounted = _job(Table.LARGE, Sub.GRAVEL)
	job.call("start")
	job.call("cancel")
	var cancelled_at: int = Time.get_ticks_msec()
	(
		assert_bool(_poll_until_done(job))
		. override_failure_message("the cancelled job never finished")
		. is_true()
	)
	var reaction: int = Time.get_ticks_msec() - cancelled_at
	(
		assert_int(reaction)
		. override_failure_message(
			"the cancelled job needed %d ms to stop (checked at least once per chunk)" % reaction
		)
		. is_less(CANCEL_REACTION_MSEC)
	)
	(
		assert_object(job.call("get_result"))
		. override_failure_message("a cancelled job has a result")
		. is_null()
	)
	assert_bool(bool(job.call("is_cancelled"))).is_true()


func test_ac32_finish_now_after_a_cancel_returns_null() -> void:
	if not _have_pipeline(Table.SMALL, Sub.GRAVEL):
		return
	var running: RefCounted = _job(Table.SMALL, Sub.GRAVEL)
	running.call("start")
	running.call("cancel")
	assert_object(running.call("finish_now")).is_null()
	var idle: RefCounted = _job(Table.SMALL, Sub.GRAVEL)
	idle.call("cancel")
	assert_object(idle.call("finish_now")).is_null()


func test_ac32_a_job_with_a_missing_bake_file_finishes_without_a_result() -> void:
	if not _have_pipeline(Table.SMALL, Sub.PEBBLES):
		return
	var script: GDScript = load(Api.JOB_PATH) as GDScript
	var input: RefCounted = Api.create_input(Table.SMALL, Sub.PEBBLES, Api.look_of(Sub.PEBBLES))
	var results: Array[RefCounted] = []
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void:
			var job: RefCounted = script.new(
				input, "res://assets/substrate/bake/not_there.bin", null
			)
			results.append(job.call("finish_now"))
	)
	assert_object(results[0]).is_null()
	assert_dict(seen["errors"]).is_not_empty()


func test_ac32_releasing_a_cancelled_running_job_waits_at_most_one_chunk() -> void:
	if not _have_pipeline(Table.LARGE, Sub.GRAVEL):
		return
	var job: RefCounted = _job(Table.LARGE, Sub.GRAVEL)
	job.call("start")
	job.call("cancel")
	var started: int = Time.get_ticks_msec()
	job.call("wait_and_release")
	(
		assert_int(Time.get_ticks_msec() - started)
		. override_failure_message("wait_and_release of a cancelled job took long")
		. is_less(CANCEL_REACTION_MSEC)
	)
	assert_object(job.call("get_result")).is_null()
