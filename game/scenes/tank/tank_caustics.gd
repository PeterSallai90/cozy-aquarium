class_name TankCaustics
extends MeshInstance3D
## The lamp caustics inside the water of a tank (ADR 0007 Amendment 1). A depth-reading box the
## size of the water volume; the shader does the work. This node keeps values only: the lamp is
## copied into the WaterVolume frame and never referenced. Hidden when the intensity is 0, there
## is no lamp or the water is not built. No per-frame work.

var _size_m: Vector3 = Vector3.ZERO
var _has_lamp: bool = false
var _settings: WaterCausticSettings = null


## Sizes the box, clears the lamp and follows the settings. Called by TankWater.build().
func configure(size_m: Vector3, settings: WaterCausticSettings) -> void:
	_disconnect_settings()
	_size_m = size_m
	_has_lamp = false
	var box: BoxMesh = BoxMesh.new()
	box.size = size_m
	mesh = box
	transform = Transform3D.IDENTITY
	set_instance_shader_parameter(&"water_size_m", size_m)
	_settings = settings
	if _settings != null:
		_settings.applied.connect(refresh)
	refresh()


## Hides the node and forgets size, lamp and settings. Called by TankWater on an invalid build.
func clear() -> void:
	_disconnect_settings()
	_size_m = Vector3.ZERO
	_has_lamp = false
	refresh()


## Copies the lamp into the WaterVolume frame. Null, or a light outside the tree, clears the lamp.
func set_key_light(light: SpotLight3D) -> void:
	_has_lamp = false
	if light != null:
		var parent: Node3D = get_parent() as Node3D
		if parent == null or not is_inside_tree() or not parent.is_inside_tree():
			push_warning("TankCaustics: lamp ignored, the tank is not in the scene tree")
		elif not light.is_inside_tree():
			push_warning("TankCaustics: lamp ignored, the light is not in the scene tree")
		else:
			_copy_lamp(parent, light)
	refresh()


func has_lamp() -> bool:
	return _has_lamp


## The intensity the shader gets: 0 while the node is hidden.
func get_effective_intensity() -> float:
	return _settings.caustic_intensity if visible and _settings != null else 0.0


## Shows or hides the node and writes the settings values to the instance parameters.
func refresh() -> void:
	var on: bool = (
		_size_m != Vector3.ZERO
		and _has_lamp
		and _settings != null
		and _settings.caustic_intensity > 0.0
	)
	visible = on
	if _settings == null:
		set_instance_shader_parameter(&"caustic_intensity", 0.0)
		return
	set_instance_shader_parameter(&"caustic_intensity", _settings.caustic_intensity if on else 0.0)
	set_instance_shader_parameter(&"caustic_speed", _settings.caustic_speed)
	set_instance_shader_parameter(&"caustic_scale", _settings.caustic_scale)


func _copy_lamp(parent: Node3D, light: SpotLight3D) -> void:
	var inverse: Transform3D = parent.global_transform.affine_inverse()
	var direction: Vector3 = (
		(parent.global_basis.inverse() * light.global_basis * Vector3.FORWARD).normalized()
	)
	set_instance_shader_parameter(&"lamp_position_m", inverse * light.global_position)
	set_instance_shader_parameter(&"lamp_direction", direction)
	set_instance_shader_parameter(&"lamp_spot_angle_deg", light.spot_angle)
	set_instance_shader_parameter(&"lamp_spot_range_m", light.spot_range)
	_has_lamp = true


func _disconnect_settings() -> void:
	if _settings != null and _settings.applied.is_connected(refresh):
		_settings.applied.disconnect(refresh)
	_settings = null


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_disconnect_settings()
