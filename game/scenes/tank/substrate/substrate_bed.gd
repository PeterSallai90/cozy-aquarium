class_name SubstrateBed
extends Node3D
## The substrate bed of one tank (ADR 0011 rules 6 and 10): the room adds it as
## Tank/SubstrateAnchor/Substrate and tells it which type and colour to show. It reads the model
## never and writes it never; it only draws.
##
## A type change assembles the bed on a worker thread (SubstrateAssemblyJob), instances it on the
## main thread into a hidden SubstrateBedView in steps of at most BUILD_BUDGET_USEC per frame and,
## once the view is complete, swaps it in within one frame: the new view becomes visible with the
## current tint, the old one is hidden and bed_swapped is emitted. The old complete bed stays
## visible until then; no half-built bed is ever shown. A new type change cancels the running job
## and drops the half-built view.
##
## Rules of show_type(): the type that is shown with nothing pending only changes the tint; the
## type that is pending changes nothing but the tint it will get; a type already built in this bed
## for the same tank swaps in within the same call (kept hidden since its build); assembled data in
## the session cache (SubstrateBedCache) is only instanced, without a job; anything else starts a
## job. While no bed is shown yet (a new tank, a new session) the core of the pending type is
## visible at once, so the lamp-lit cabinet never shows through an empty floor; the stones appear
## at the swap.
##
## finish_pending() does the rest of a pending change in the calling frame (wait for or run the
## assembly, instance everything, swap): headless tests and the measure script use it; the result
## equals the threaded path. Main thread only.

signal bed_swapped(substrate_id: StringName)

## Main-thread instancing per frame in microseconds; poll, instancing and swap together stay below
## the 4 ms of #28 AC 34.
const BUILD_BUDGET_USEC: int = 3000
const VIEW_PREFIX: String = "View_"
const PLACEHOLDER_NAME: String = "Pending"

var _cache: SubstrateBedCache = null
## The model colour: the tint of the shown view, or of the pending one while a change is pending.
var _tint: Color = Color.WHITE
## The tank of the views in _views.
var _tank_id: StringName = &""
## Complete views of _tank_id by substrate id: the shown one and the hidden ones kept for a swap.
var _views: Dictionary[StringName, SubstrateBedView] = {}
var _shown_id: StringName = &""
var _shown_view: SubstrateBedView = null
var _pending_id: StringName = &""
var _pending_look: SubstrateBedLook = null
var _pending_path: String = ""
var _pending_job: SubstrateAssemblyJob = null
## The view of the pending type being instanced; null while its data is still assembled.
var _pending_view: SubstrateBedView = null
## Core and floor skin of the pending type while nothing is shown and the data is assembled.
var _placeholder: SubstrateBedView = null
## Cancelled jobs whose task still runs; reaped in _process, waited for when leaving the tree.
var _cancelled: Array[SubstrateAssemblyJob] = []
var _assemblies: int = 0
## Main-thread microseconds of the bed since the last frame (show_type and set_tint included).
var _frame_usec: int = 0
var _last_frame_usec: int = 0
var _max_frame_usec: int = 0
var _last_lod_usec: int = 0


## The session cache shared by the beds of the room. Without it the bed keeps a cache of its own.
func setup(cache: SubstrateBedCache) -> void:
	_cache = cache


## The assembly input of a type in a tank. The depth comes from SubstrateSurface (the nominal
## surface of a flat bed); null when the tank, the definition or its bed look is missing.
static func make_input(
	tank: TankDefinition, definition: SubstrateDefinition
) -> SubstrateAssemblyInput:
	if tank == null or definition == null or definition.bed_look == null:
		return null
	return SubstrateAssemblyInput.create(
		tank.id,
		definition.id,
		tank.interior_size_m,
		SubstrateSurface.flat_depth(definition),
		definition.bed_look
	)


## Shows the type in the tank with the colour (see the rules in the class description).
func show_type(tank: TankDefinition, definition: SubstrateDefinition, colour: Color) -> void:
	var started: int = Time.get_ticks_usec()
	_show_type(tank, definition, colour)
	_count_outside_frame(started)


## Sets the colour: on the pending view (and its core) while a change is pending, else on the
## shown view, in the same frame. A view swapped in later gets it at the swap.
func set_tint(colour: Color) -> void:
	var started: int = Time.get_ticks_usec()
	_tint = colour
	if _pending_id != &"":
		_tint_pending()
	elif _shown_view != null:
		_shown_view.set_tint(colour)
	_count_outside_frame(started)


func get_tint() -> Color:
	return _tint


## Completes a pending change in this call: waits for or runs the assembly, instances the rest and
## swaps. Does nothing when nothing is pending.
func finish_pending() -> void:
	if _pending_id == &"":
		return
	if _pending_view == null:
		if _pending_job == null:
			return
		_pending_job.finish_now()
		_take_job_result()
		if _pending_view == null:
			return
	_pending_view.build_all()
	_swap(_pending_id, _pending_view)


## The type shown (empty while nothing is shown).
func get_shown_id() -> StringName:
	return _shown_id


## The type being built (empty when nothing is pending).
func get_pending_id() -> StringName:
	return _pending_id


func is_building() -> bool:
	return _pending_id != &""


func get_shown_view() -> SubstrateBedView:
	return _shown_view


## Assemblies started by this bed (a cancelled one counts; a cache hit or a colour change does not).
func get_assembly_count() -> int:
	return _assemblies


## Main-thread microseconds of poll, instancing and swap in the last frame (the LOD update apart).
func get_last_frame_main_usec() -> int:
	return _last_frame_usec


## The largest get_last_frame_main_usec() since reset_frame_stats().
func get_max_frame_main_usec() -> int:
	return _max_frame_usec


## Microseconds of the LOD update of the shown view in the last frame.
func get_last_lod_usec() -> int:
	return _last_lod_usec


func reset_frame_stats() -> void:
	_frame_usec = 0
	_last_frame_usec = 0
	_max_frame_usec = 0
	_last_lod_usec = 0


func _process(_delta: float) -> void:
	var started: int = Time.get_ticks_usec()
	_reap_cancelled()
	var lod_started: int = Time.get_ticks_usec()
	if _shown_view != null:
		_update_view_lod(_shown_view)
	_last_lod_usec = Time.get_ticks_usec() - lod_started
	_advance(started + _last_lod_usec)
	_frame_usec += Time.get_ticks_usec() - started - _last_lod_usec
	_last_frame_usec = _frame_usec
	_max_frame_usec = maxi(_max_frame_usec, _frame_usec)
	_frame_usec = 0


## Leaving the tree (the room drops the tank): cancel and wait, at most one chunk per job.
func _exit_tree() -> void:
	if _pending_job != null:
		_pending_job.wait_and_release()
		_pending_job = null
	for job: SubstrateAssemblyJob in _cancelled:
		job.wait_and_release()
	_cancelled.clear()
	if _pending_view == null:
		_pending_id = &""


# --- the rules of show_type ---


func _show_type(tank: TankDefinition, definition: SubstrateDefinition, colour: Color) -> void:
	if tank == null or definition == null or definition.bed_look == null:
		push_error("SubstrateBed: a tank, a substrate definition and its bed look are needed")
		return
	_tint = colour
	if tank.id != _tank_id:
		_change_tank(tank.id)
	var id: StringName = definition.id
	if id == _pending_id:
		_tint_pending()
		return
	_drop_pending()
	var built: SubstrateBedView = _views.get(id) as SubstrateBedView
	if built != null:
		if built == _shown_view:
			built.set_tint(_tint)
		else:
			_swap(id, built)
		return
	var input: SubstrateAssemblyInput = make_input(tank, definition)
	_pending_id = id
	_pending_look = definition.bed_look
	_pending_path = _pending_look.bake_path_for(tank.id)
	var data: SubstrateBedData = _get_cache().get_data(tank.id, id)
	if data != null:
		_begin_view(data)
		return
	_pending_job = SubstrateAssemblyJob.new(
		input, _pending_path, _get_cache().get_bake(_pending_path)
	)
	_pending_job.start()
	_assemblies += 1
	if _shown_view == null:
		_placeholder = _make_placeholder(input, definition.grain_scale)


## Another tank: the hidden views of the old one are freed; the shown one stays until the swap.
func _change_tank(tank_id: StringName) -> void:
	_drop_pending()
	for id: StringName in _views:
		if _views[id] != _shown_view:
			_free_view(_views[id])
	_views.clear()
	_tank_id = tank_id


## Cancels the pending change: the job goes to the reap list, the half-built view and the
## placeholder are freed.
func _drop_pending() -> void:
	if _pending_job != null:
		_pending_job.cancel()
		if not _pending_job.poll():
			_cancelled.append(_pending_job)
		_pending_job = null
	if _pending_view != null:
		_free_view(_pending_view)
		_pending_view = null
	if _placeholder != null:
		_free_view(_placeholder)
		_placeholder = null
	_pending_id = &""
	_pending_look = null
	_pending_path = ""


func _tint_pending() -> void:
	if _pending_view != null:
		_pending_view.set_tint(_tint)
	if _placeholder != null:
		_placeholder.set_tint(_tint)


# --- building ---


## One frame of the pending change: take the assembled data when the job is done, then instance
## within the budget and swap when the view is complete.
func _advance(started: int) -> void:
	if _pending_id == &"":
		return
	if _pending_view == null:
		if _pending_job == null or not _pending_job.poll():
			return
		_take_job_result()
		if _pending_view == null:
			return
	var budget: int = BUILD_BUDGET_USEC - (Time.get_ticks_usec() - started)
	if budget <= 0:
		return
	if _pending_view.build_step(budget):
		_swap(_pending_id, _pending_view)


## The job is done: keep its baked data and bed in the cache and start the view, or give up with
## one error (a placeholder core stays as the floor until the next type).
func _take_job_result() -> void:
	var job: SubstrateAssemblyJob = _pending_job
	_pending_job = null
	_get_cache().put_bake(_pending_path, job.get_bake())
	var data: SubstrateBedData = job.get_result()
	if data == null:
		push_error("SubstrateBed: the bed of %s could not be assembled" % _pending_id)
		_pending_id = &""
		_pending_look = null
		_pending_path = ""
		return
	_get_cache().put_data(data)
	_begin_view(data)


## Starts the view of the pending type. With nothing shown its core is visible at once and its
## stones stay hidden until the swap; otherwise the whole view stays hidden until then.
func _begin_view(data: SubstrateBedData) -> void:
	var view: SubstrateBedView = SubstrateBedView.new()
	view.name = VIEW_PREFIX + String(_pending_id)
	view.begin(data, _pending_look)
	view.set_tint(_tint)
	view.set_stones_visible(false)
	view.visible = _shown_view == null
	add_child(view)
	# the chunks are built at the LOD of the camera from the start
	_update_view_lod(view)
	_pending_view = view
	if _placeholder != null:
		_free_view(_placeholder)
		_placeholder = null


## Core, floor skin (and sand surface) of a type before its data is assembled: a view of a bed
## without stones whose core box is the one the assembler gives the input.
func _make_placeholder(input: SubstrateAssemblyInput, median_size_m: float) -> SubstrateBedView:
	var stub: SubstrateBedData = SubstrateBedData.new()
	stub.input = input
	stub.median_size_m = median_size_m
	var core: AABB = SubstrateAssembler.core_box(input)
	stub.core_size = core.size
	stub.core_centre = core.get_center()
	var view: SubstrateBedView = SubstrateBedView.new()
	view.name = PLACEHOLDER_NAME
	view.begin(stub, _pending_look)
	view.set_tint(_tint)
	add_child(view)
	return view


## Makes the view the shown one in this call: tinted, LOD of the camera, stones visible; the old
## view is hidden (kept when it belongs to this tank, freed otherwise); then bed_swapped.
func _swap(id: StringName, view: SubstrateBedView) -> void:
	var old: SubstrateBedView = _shown_view
	view.set_tint(_tint)
	_update_view_lod(view)
	view.set_stones_visible(true)
	view.visible = true
	if view == _pending_view:
		_pending_view = null
		_pending_id = &""
		_pending_look = null
		_pending_path = ""
	_views[id] = view
	_shown_view = view
	_shown_id = id
	if old != null and old != view:
		if _views.values().has(old):
			old.visible = false
		else:
			_free_view(old)
	bed_swapped.emit(id)


func _update_view_lod(view: SubstrateBedView) -> void:
	if not view.is_inside_tree():
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	view.update_lod(view.to_local(camera.global_position))


func _reap_cancelled() -> void:
	if _cancelled.is_empty():
		return
	var running: Array[SubstrateAssemblyJob] = []
	for job: SubstrateAssemblyJob in _cancelled:
		if not job.poll():
			running.append(job)
	_cancelled = running


func _free_view(view: SubstrateBedView) -> void:
	if view.get_parent() == self:
		remove_child(view)
	view.free()


## Adds main-thread work done outside _process (show_type, set_tint: a swap of a built type
## happens there) to the frame, so the maximum shows it at once.
func _count_outside_frame(started: int) -> void:
	_frame_usec += Time.get_ticks_usec() - started
	_max_frame_usec = maxi(_max_frame_usec, _frame_usec)


func _get_cache() -> SubstrateBedCache:
	if _cache == null:
		_cache = SubstrateBedCache.new()
	return _cache
