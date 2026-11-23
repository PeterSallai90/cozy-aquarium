class_name FishNameText
extends RefCounted
## How a fish name reaches the screen (#36): the nickname, or the translated derived default name
## when the nickname is empty. Static helpers shared by the panel, the card and later the labels.
## The stored nickname is never changed; only the shown text is.

## Longest text shaped in a row or on the card; a longer name is cut and ends with an ellipsis.
const MAX_SHOWN_CHARS: int = 256

const _BREAKS: PackedStringArray = ["\r\n", "\n", "\r", " ", " "]


## The nickname, or the translation of the derived default-name key when the nickname is empty.
## `translator` is any Object, normally the Node that shows the name.
static func shown_name(fish: FishInstance, translator: Object) -> String:
	if not fish.nickname.is_empty():
		return fish.nickname
	var key: String = FishDefaultName.key_for(fish.uid)
	return translator.tr(key)


## The text on one line: every line break (CRLF counts once) becomes one space.
static func one_line(text: String) -> String:
	var result: String = text
	for separator: String in _BREAKS:
		result = result.replace(separator, " ")
	return result


## One line, and cut to MAX_SHOWN_CHARS with an ellipsis when longer. For labels and buttons;
## tooltips keep the full one-line text.
static func display(text: String) -> String:
	var line: String = one_line(text)
	if line.length() > MAX_SHOWN_CHARS:
		return line.substr(0, MAX_SHOWN_CHARS) + "…"
	return line
