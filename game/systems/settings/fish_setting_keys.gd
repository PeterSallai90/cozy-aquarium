class_name FishSettingKeys
extends RefCounted
## The typed settings keys of the fish area (#164, ADR 0003 rule 1: declared by the feature).


## [fish] show_names: whether the fish name labels are shown above the fish. Off by default.
static func show_names() -> SettingKey:
	return SettingKey.new("fish", "show_names", TYPE_BOOL, false)
