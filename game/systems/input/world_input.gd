class_name WorldInput
extends RefCounted
## World input routing helper (ADR 0008): modal UI joins BLOCKER_GROUP; while any member is
## visible, world systems ignore new presses and end running gestures.

const BLOCKER_GROUP: StringName = &"world_input_blockers"


static func is_blocked(tree: SceneTree) -> bool:
	for node: Node in tree.get_nodes_in_group(BLOCKER_GROUP):
		var item: CanvasItem = node as CanvasItem
		if item != null and item.is_visible_in_tree():
			return true
	return false


## True while the GUI focus is in a text field: its owner wants the keys, the wheel and the mouse.
static func is_text_focused(viewport: Viewport) -> bool:
	var owner: Control = viewport.gui_get_focus_owner()
	return owner is LineEdit or owner is TextEdit


## True when a visible Control that stops the mouse covers the position. The engine marks the
## wheel as handled only for controls that use it, so the world checks this itself.
static func is_over_stop_control(root: Node, position: Vector2) -> bool:
	for child: Node in root.get_children():
		if child is Window or child is SubViewport:
			continue
		var item: CanvasItem = child as CanvasItem
		if item != null and not item.visible:
			continue
		var layer: CanvasLayer = child as CanvasLayer
		if layer != null and not layer.visible:
			continue
		var control: Control = child as Control
		if (
			control != null
			and control.mouse_filter == Control.MOUSE_FILTER_STOP
			and control.get_global_rect().has_point(position)
		):
			return true
		if is_over_stop_control(child, position):
			return true
	return false
