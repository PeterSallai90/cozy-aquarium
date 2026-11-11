extends GdUnitTestSuite
## #26 (owner: developer): WorldInput.is_over_stop_control respects the visibility of a
## CanvasLayer and ignores Controls inside other windows and viewports.

const POINT := Vector2(50.0, 50.0)


func _root() -> Node:
	var root: Node = Node.new()
	add_child(root)
	auto_free(root)
	return root


func _stop_control(parent: Node) -> Control:
	var control: Control = Control.new()
	control.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(control)
	control.position = Vector2.ZERO
	control.size = Vector2(200.0, 200.0)
	return control


func test_a_stop_control_under_a_visible_canvas_layer_counts() -> void:
	var root: Node = _root()
	var layer: CanvasLayer = CanvasLayer.new()
	root.add_child(layer)
	_stop_control(layer)
	assert_bool(WorldInput.is_over_stop_control(root, POINT)).is_true()


func test_a_stop_control_under_a_hidden_canvas_layer_does_not_count() -> void:
	var root: Node = _root()
	var layer: CanvasLayer = CanvasLayer.new()
	layer.visible = false
	root.add_child(layer)
	_stop_control(layer)
	assert_bool(WorldInput.is_over_stop_control(root, POINT)).is_false()


func test_a_stop_control_inside_a_sub_viewport_does_not_count() -> void:
	var root: Node = _root()
	var viewport: SubViewport = SubViewport.new()
	root.add_child(viewport)
	_stop_control(viewport)
	assert_bool(WorldInput.is_over_stop_control(root, POINT)).is_false()


func test_a_pass_control_does_not_count() -> void:
	var root: Node = _root()
	var control: Control = _stop_control(root)
	control.mouse_filter = Control.MOUSE_FILTER_PASS
	assert_bool(WorldInput.is_over_stop_control(root, POINT)).is_false()
