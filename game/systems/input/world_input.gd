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
