extends GdUnitArgumentMatcher
## Matches a push_error or push_warning message by substring. An empty needle matches nothing.
##
## GdUnit4 6.2.2 compares push_error messages exactly. The architect's plan fixes only a stable
## substring per message, so this matcher is passed to is_push_error(). GdUnit accepts a matcher
## only when its string form is "any_string()", which is why _to_string returns that text.

var _needle: String = ""


func _init(needle: String) -> void:
	_needle = needle


func is_match(value: Variant) -> bool:
	return not _needle.is_empty() and str(value).contains(_needle)


func _to_string() -> String:
	return "any_string()"
