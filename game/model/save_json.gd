class_name SaveJson
extends RefCounted
## Strict JSON reader and writer for the save file. Pure, no I/O.
##
## Why not Godot's JSON class: its number parser is not correctly rounded, so a double read back
## from a file can differ from the one written. This reader converts every number token with
## DecimalDouble.parse(), and this writer writes floats with DecimalDouble.to_text().
##
## Reader: strict RFC 8259. Whitespace is space, tab, LF and CR. Exactly one value and nothing
## after it. No trailing commas, comments, NaN, Infinity, leading zeros or "+" sign. A duplicate
## key keeps the last value. Every number is returned as a float. A raw control character in a
## string, an unknown escape, a lone surrogate and \u0000 (a Godot String cannot hold NUL) are
## errors. Nesting deeper than MAX_DEPTH is an error.
##
## Writer: same layout as JSON.stringify(data, "  "). Strings escape the quote and the backslash,
## U+0008, U+0009, U+000A, U+000C and U+000D as \b \t \n \f \r, and every other code point from
## U+0000 to U+001F as \u00XX with uppercase hex. Nothing else is escaped, so the text never has
## a raw byte below 0x20 except the line feeds of the layout.

## A v1 file needs 4 levels. A future format must stay within this limit, so that a newer file
## still parses far enough to be reported as a newer version.
const MAX_DEPTH: int = 64

const _INDENT: String = "  "
const _NUMBER_PATTERN: String = "\\G-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?"
const _SPECIAL_PATTERN: String = '[\\x{00}-\\x{1F}"\\\\]'
const _HEX4_PATTERN: String = "\\G[0-9A-Fa-f]{4}"
const _SPACE_PATTERN: String = "\\G[ \\t\\r\\n]+"
const _SHORT_ESCAPES: Dictionary = {
	8: "\\b",
	9: "\\t",
	10: "\\n",
	12: "\\f",
	13: "\\r",
	34: '\\"',
	92: "\\\\",
}

static var _escape_regex: RegEx = RegEx.create_from_string(_SPECIAL_PATTERN)

## The parsed value after a successful parse(), else null.
var data: Variant = null
## Empty after a success. Developers only, never shown to the player.
var error_message: String = ""

var _text: String = ""
var _at: int = 0
var _length: int = 0
var _number_regex: RegEx = RegEx.create_from_string(_NUMBER_PATTERN)
var _special_regex: RegEx = RegEx.create_from_string(_SPECIAL_PATTERN)
var _hex4_regex: RegEx = RegEx.create_from_string(_HEX4_PATTERN)
var _space_regex: RegEx = RegEx.create_from_string(_SPACE_PATTERN)


## Parses the text. Returns OK, or ERR_PARSE_ERROR with error_message set. The instance can be
## used again after a failure.
func parse(text: String) -> Error:
	_text = text
	_at = 0
	_length = text.length()
	error_message = ""
	data = null
	var value: Variant = _read_value(1)
	if error_message.is_empty():
		_skip_space()
		if _at < _length:
			_fail("unexpected text after the value")
	if not error_message.is_empty():
		data = null
		_text = ""
		return ERR_PARSE_ERROR
	data = value
	_text = ""
	return OK


## Writes a value as JSON text without a trailing newline. Supports Dictionary (insertion order,
## String or StringName keys), Array, String, StringName, int, float, bool and null. Returns ""
## when the value cannot be written: an unsupported type, a non-finite float, or a float whose
## text would not read back to the same bits.
static func stringify(value: Variant) -> String:
	var parts: PackedStringArray = PackedStringArray()
	if not _write(value, 0, parts):
		return ""
	return "".join(parts)


# --- Reader ---------------------------------------------------------------------------------


func _fail(why: String) -> void:
	if not error_message.is_empty():
		return
	var line: int = _text.substr(0, mini(_at, _length)).count("\n") + 1
	error_message = "%s (offset %d, line %d)" % [why, _at, line]


func _skip_space() -> void:
	if _at >= _length:
		return
	var code: int = _text.unicode_at(_at)
	if code != 32 and code != 10 and code != 13 and code != 9:
		return
	var found: RegExMatch = _space_regex.search(_text, _at)
	if found != null:
		_at = found.get_end()


func _peek() -> int:
	if _at >= _length:
		return -1
	return _text.unicode_at(_at)


func _read_value(depth: int) -> Variant:
	_skip_space()
	var code: int = _peek()
	if code == -1:
		_fail("unexpected end of text")
		return null
	if code == 123 or code == 91:
		return _read_container(code, depth)
	if code == 34:
		return _read_string()
	if code == 45 or (code >= 48 and code <= 57):
		return _read_number()
	return _read_literal()


func _read_container(code: int, depth: int) -> Variant:
	if depth > MAX_DEPTH:
		_fail("nesting deeper than %d" % MAX_DEPTH)
		return null
	if code == 123:
		return _read_object(depth)
	return _read_array(depth)


func _read_literal() -> Variant:
	if _take_literal("true"):
		return true
	if _take_literal("false"):
		return false
	if _take_literal("null"):
		return null
	_fail("unexpected character")
	return null


func _take_literal(literal: String) -> bool:
	if _text.substr(_at, literal.length()) != literal:
		return false
	_at += literal.length()
	return true


func _read_number() -> Variant:
	var found: RegExMatch = _number_regex.search(_text, _at)
	if found == null:
		_fail("malformed number")
		return null
	_at = found.get_end()
	return DecimalDouble.parse(found.get_string())


func _read_object(depth: int) -> Variant:
	var result: Dictionary = {}
	_at += 1
	_skip_space()
	if _peek() == 125:
		_at += 1
		return result
	while error_message.is_empty():
		if not _read_member(depth, result):
			return null
		_skip_space()
		var next: int = _peek()
		if next == 44:
			_at += 1
		elif next == 125:
			_at += 1
			return result
		else:
			_fail("expected ',' or '}'")
	return null


## Reads "key": value into the dictionary. False on error.
func _read_member(depth: int, into: Dictionary) -> bool:
	_skip_space()
	if _peek() != 34:
		_fail("expected a string key")
		return false
	var key: String = _read_string()
	if not error_message.is_empty():
		return false
	_skip_space()
	if _peek() != 58:
		_fail("expected ':' after a key")
		return false
	_at += 1
	var value: Variant = _read_value(depth + 1)
	if not error_message.is_empty():
		return false
	into[key] = value
	return true


func _read_array(depth: int) -> Variant:
	var result: Array = []
	_at += 1
	_skip_space()
	if _peek() == 93:
		_at += 1
		return result
	while error_message.is_empty():
		var value: Variant = _read_value(depth + 1)
		if not error_message.is_empty():
			return null
		result.append(value)
		_skip_space()
		var next: int = _peek()
		if next == 44:
			_at += 1
		elif next == 93:
			_at += 1
			return result
		else:
			_fail("expected ',' or ']'")
	return null


## Reads a string whose opening quote is at _at. Returns "" and sets the error on failure.
func _read_string() -> String:
	_at += 1
	var parts: PackedStringArray = PackedStringArray()
	while true:
		var found: RegExMatch = _special_regex.search(_text, _at)
		if found == null:
			_at = _length
			_fail("unterminated string")
			return ""
		var stop: int = found.get_start()
		parts.append(_text.substr(_at, stop - _at))
		_at = stop
		var code: int = _text.unicode_at(stop)
		if code == 34:
			_at += 1
			return "".join(parts)
		if code != 92:
			_fail("raw control character in a string")
			return ""
		_at += 1
		if not _read_escape(parts):
			return ""
	return ""


## Reads the part after a backslash and appends the character. False on error.
func _read_escape(parts: PackedStringArray) -> bool:
	var code: int = _peek()
	_at += 1
	match code:
		34:
			parts.append('"')
		92:
			parts.append("\\")
		47:
			parts.append("/")
		98:
			parts.append(char(8))
		102:
			parts.append(char(12))
		110:
			parts.append("\n")
		114:
			parts.append("\r")
		116:
			parts.append("\t")
		117:
			var point: int = _read_unicode_escape()
			if point < 0:
				return false
			parts.append(char(point))
		_:
			_fail("invalid escape")
			return false
	return true


## Reads the four hex digits after \u, and a following \uXXXX when the first is a high
## surrogate. Returns the code point, or -1 after setting the error.
func _read_unicode_escape() -> int:
	var point: int = _read_hex4()
	if point < 0:
		return -1
	if point == 0:
		_fail("\\u0000 is not allowed")
		return -1
	if point >= 0xDC00 and point <= 0xDFFF:
		_fail("lone low surrogate")
		return -1
	if point >= 0xD800 and point <= 0xDBFF:
		return _read_low_surrogate(point)
	return point


## Combines a high surrogate with the \uXXXX that must follow it. -1 after setting the error.
func _read_low_surrogate(high: int) -> int:
	if _text.substr(_at, 2) != "\\u":
		_fail("lone high surrogate")
		return -1
	_at += 2
	var low: int = _read_hex4()
	if low < 0:
		return -1
	if low < 0xDC00 or low > 0xDFFF:
		_fail("high surrogate without a low surrogate")
		return -1
	return 0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00)


func _read_hex4() -> int:
	var found: RegExMatch = _hex4_regex.search(_text, _at)
	if found == null:
		_fail("malformed \\u escape")
		return -1
	_at += 4
	return found.get_string().hex_to_int()


# --- Writer ---------------------------------------------------------------------------------


static func _write(value: Variant, depth: int, parts: PackedStringArray) -> bool:
	match typeof(value):
		TYPE_NIL:
			parts.append("null")
		TYPE_BOOL:
			parts.append("true" if value else "false")
		TYPE_INT:
			parts.append(str(value))
		TYPE_FLOAT:
			var text: String = DecimalDouble.to_text(value)
			if text.is_empty():
				return false
			parts.append(text)
		TYPE_STRING, TYPE_STRING_NAME:
			parts.append(_quote(String(value)))
		TYPE_ARRAY:
			return _write_array(value, depth, parts)
		TYPE_DICTIONARY:
			return _write_dictionary(value, depth, parts)
		_:
			return false
	return true


static func _write_array(list: Array, depth: int, parts: PackedStringArray) -> bool:
	if list.is_empty():
		parts.append("[]")
		return true
	var inner: String = _INDENT.repeat(depth + 1)
	parts.append("[\n")
	for index: int in list.size():
		if index > 0:
			parts.append(",\n")
		parts.append(inner)
		if not _write(list[index], depth + 1, parts):
			return false
	parts.append("\n" + _INDENT.repeat(depth) + "]")
	return true


static func _write_dictionary(map: Dictionary, depth: int, parts: PackedStringArray) -> bool:
	if map.is_empty():
		parts.append("{}")
		return true
	var inner: String = _INDENT.repeat(depth + 1)
	parts.append("{\n")
	var first: bool = true
	for key: Variant in map:
		var key_type: int = typeof(key)
		if key_type != TYPE_STRING and key_type != TYPE_STRING_NAME:
			return false
		if not first:
			parts.append(",\n")
		first = false
		parts.append(inner)
		parts.append(_quote(String(key)))
		parts.append(": ")
		if not _write(map[key], depth + 1, parts):
			return false
	parts.append("\n" + _INDENT.repeat(depth) + "}")
	return true


static func _quote(text: String) -> String:
	var specials: Array[RegExMatch] = _escape_regex.search_all(text)
	if specials.is_empty():
		return '"' + text + '"'
	var parts: PackedStringArray = PackedStringArray(['"'])
	var from: int = 0
	for found: RegExMatch in specials:
		var at: int = found.get_start()
		parts.append(text.substr(from, at - from))
		var code: int = text.unicode_at(at)
		if _SHORT_ESCAPES.has(code):
			parts.append(_SHORT_ESCAPES[code])
		else:
			parts.append("\\u%04X" % code)
		from = at + 1
	parts.append(text.substr(from))
	parts.append('"')
	return "".join(parts)
