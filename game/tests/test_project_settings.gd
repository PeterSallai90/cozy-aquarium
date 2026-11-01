extends GdUnitTestSuite


func test_rendering_method_is_forward_plus() -> void:
	var method: String = ProjectSettings.get_setting("rendering/renderer/rendering_method", "")
	assert_str(method).is_equal("forward_plus")
