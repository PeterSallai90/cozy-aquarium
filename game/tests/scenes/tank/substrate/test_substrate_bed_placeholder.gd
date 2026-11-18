extends GdUnitTestSuite
## #28 criteria 28 and 32 (developer's own checks of SubstrateBed): while nothing is shown and the
## data of the first type is still assembled, the bed shows a stone-less view of that type (core,
## floor skin, for sand the procedural surface) so the lamp-lit cabinet never shows through an
## empty floor. Its core box must be exactly the box the assembler gives the same input, so the
## swap to the real view moves nothing; this suite guards that SubstrateBed builds the placeholder
## core from SubstrateAssembler.core_box.

const EngineOutput := preload("res://tests/helpers/engine_output.gd")
const Fixture := preload("res://tests/helpers/substrate_bed_fixture.gd")
const Rig := preload("res://tests/helpers/room_rig.gd")
const Scene := preload("res://tests/helpers/substrate_scene_rig.gd")
const Sub := preload("res://tests/helpers/substrate_api.gd")
const Table := preload("res://tests/helpers/tank_table.gd")

var _substrates: SubstrateCatalog = null


func before_test() -> void:
	_substrates = SubstrateCatalog.load_dir()


func _bed() -> SubstrateBed:
	var bed: SubstrateBed = SubstrateBed.new()
	bed.setup(SubstrateBedCache.new())
	add_child(bed)
	auto_free(bed)
	return bed


func _box_of(view: Node3D, part: String) -> AABB:
	return Scene.aabb_in_view(view.get_node(part) as MeshInstance3D, view)


func test_ac28_the_placeholder_core_is_the_core_of_the_assembled_bed_for_every_tank_and_type(
) -> void:
	for tank_id: StringName in Table.IDS:
		var tank: TankDefinition = Rig.definition_of(tank_id) as TankDefinition
		for id: StringName in Sub.IDS:
			var label: String = "%s in %s" % [id, tank_id]
			var bed: SubstrateBed = _bed()
			bed.show_type(tank, _substrates.get_definition(id), Color.WHITE)
			var views: Array[Node3D] = Scene.views_of(bed)
			assert_int(views.size()).override_failure_message(label).is_equal(1)
			if views.size() != 1:
				continue
			var placeholder: Node3D = views[0]
			(
				assert_bool(Scene.stones_visible(placeholder))
				. override_failure_message(label)
				. is_false()
			)
			var data: SubstrateBedData = Fixture.bed_of(tank_id, id) as SubstrateBedData
			var wanted: AABB = AABB(data.core_centre - data.core_size / 2.0, data.core_size)
			var core: AABB = _box_of(placeholder, "Core")
			(
				assert_bool(core.position.is_equal_approx(wanted.position))
				. override_failure_message("%s: core at %s, want %s" % [label, core, wanted])
				. is_true()
			)
			(
				assert_bool(core.size.is_equal_approx(wanted.size))
				. override_failure_message("%s: core size %s, want %s" % [label, core, wanted])
				. is_true()
			)
			var skin: AABB = _box_of(placeholder, "CoreFloor")
			bed.finish_pending()
			# the real view replaced the placeholder: the same core and skin, nothing moved
			var shown: Node3D = bed.get_shown_view()
			assert_bool(_box_of(shown, "Core").is_equal_approx(core)).is_true()
			assert_bool(_box_of(shown, "CoreFloor").is_equal_approx(skin)).is_true()
			assert_bool(is_instance_valid(placeholder)).override_failure_message(label).is_false()
			assert_int(Scene.views_of(bed).size()).override_failure_message(label).is_equal(1)


func test_ac28_the_placeholder_has_the_tint_and_the_sand_surface_of_its_type() -> void:
	var colour: Color = Color8(0x12, 0x34, 0x56)
	var bed: SubstrateBed = _bed()
	bed.show_type(Rig.definition_of(Table.SMALL), _substrates.get_definition(Sub.SAND), colour)
	var placeholder: Node3D = Scene.views_of(bed)[0]
	assert_object(placeholder.get_node_or_null("SandSurface")).is_not_null()
	assert_str(Scene.tint_mismatch(placeholder, colour)).is_empty()
	bed.set_tint(Color.RED)
	assert_str(Scene.tint_mismatch(placeholder, Color.RED)).is_empty()


func test_ac32_no_placeholder_while_a_bed_is_shown() -> void:
	var tank: TankDefinition = Rig.definition_of(Table.SMALL) as TankDefinition
	var bed: SubstrateBed = _bed()
	bed.show_type(tank, _substrates.get_definition(Sub.PEBBLES), Color.WHITE)
	bed.finish_pending()
	var shown: SubstrateBedView = bed.get_shown_view()
	bed.show_type(tank, _substrates.get_definition(Sub.GRAVEL), Color.WHITE)
	# only the shown pebbles: the gravel view starts hidden when its data arrives
	var views: Array[Node3D] = Scene.views_of(bed)
	assert_int(views.size()).is_equal(1)
	assert_bool(is_same(views[0], shown)).is_true()
	assert_bool(shown.is_visible_in_tree()).is_true()
	bed.finish_pending()
	assert_that(bed.get_shown_id()).is_equal(Sub.GRAVEL)
	(
		assert_bool(shown.is_visible_in_tree())
		. override_failure_message("pebbles still shown")
		. is_false()
	)


func test_ac32_a_failed_assembly_logs_one_error_and_shows_nothing_new() -> void:
	var tank: TankDefinition = Rig.definition_of(Table.SMALL) as TankDefinition
	var broken: SubstrateDefinition = (
		_substrates.get_definition(Sub.GRAVEL).duplicate() as SubstrateDefinition
	)
	# baked for 4 cm: the assembler refuses another depth
	broken.fill_depth_m = 0.05
	var bed: SubstrateBed = _bed()
	var seen: Dictionary = await EngineOutput.capture(
		func() -> void:
			bed.show_type(tank, broken, Color.WHITE)
			bed.finish_pending()
	)
	assert_dict(seen["errors"]).is_equal(
		{"SubstrateBed: the bed of gravel_natural could not be assembled": 1}
	)
	assert_that(bed.get_shown_id()).is_equal(&"")
	assert_bool(bed.is_building()).is_false()
