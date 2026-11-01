class_name LocalFormat
extends RefCounted
## Date, time and number text for the player's language. Pure and stateless: it reads the language,
## the UTC offset and the clock through three Callables on every call and caches nothing. UI gets
## it from Localization.local_format() (null before the autoload is ready).
##
## Caller conventions:
## - Length and temperature pass 0 decimals when the value rounded to one decimal is whole
##   (12 cm, 24 C) and 1 otherwise (3.5 cm, 24.5 C). Tank volume passes 0.
## - Unit text is a tr() key with a placeholder and a space before the unit; the owning UI issue
##   names the key.
## - A label rebuilds its text on NOTIFICATION_TRANSLATION_CHANGED or EventBus.language_changed.
##
## Daylight saving: the offset is the system's current one. When it is a whole EU standard offset
## (UTC+0, +1, +2, after taking out the current summer hour) the EU rule (last Sunday of March to
## last Sunday of October, 01:00 UTC) is applied per timestamp. Accepted limits: Moscow and Turkey
## in summer show winter timestamps 1 h early; the Azores are never corrected; Iceland's summer
## timestamps show 1 h late; non-EU zones and non-whole-hour zones get no correction; a zone at
## UTC+2 without DST may be shifted in summer.
##
## The placeholder text (datetime.unknown, number.unknown) follows the TranslationServer locale,
## while the format follows the injected language.

const MIN_OFFSET_MINUTES: int = -720
const MAX_OFFSET_MINUTES: int = 840
const MAX_UNIX: int = 253402300799
const MAX_DECIMALS: int = 6
const EU_STANDARD_OFFSETS: Array[int] = [0, 60, 120]
const _DATE_PATTERNS: Dictionary[String, String] = {
	"en": "%04d-%02d-%02d", "hu": "%04d. %02d. %02d."
}
const _DECIMAL_SEPARATORS: Dictionary[String, String] = {"en": ".", "hu": ","}

var _language_source: Callable
var _offset_source: Callable
var _clock_source: Callable


func _init(language: Callable, offset_minutes: Callable, utc_now: Callable) -> void:
	_language_source = language
	_offset_source = offset_minutes
	_clock_source = utc_now


func format_date(timestamp: Variant) -> String:
	return _format(timestamp, true, false)


func format_time(timestamp: Variant) -> String:
	return _format(timestamp, false, true)


func format_datetime(timestamp: Variant) -> String:
	return _format(timestamp, true, true)


func format_number(value: float, decimals: int) -> String:
	var text: String = decimal_text(value, decimals, decimal_separator(_language()))
	if text.is_empty():
		push_warning("LocalFormat: number is not finite: %s" % [value])
		return tr("number.unknown")
	return text


func _format(timestamp: Variant, with_date: bool, with_time: bool) -> String:
	var language: String = _language()
	var offset: int = _offset()
	var now: int = _now()
	var unix: int = parse_timestamp(timestamp)
	if unix < 0:
		push_warning("LocalFormat: timestamp rejected: %s" % [timestamp])
		return tr("datetime.unknown")
	var local: int = unix + offset_at(unix, offset, now) * 60
	var sec: int = posmod(local, 86400)
	var civil: Vector3i = civil_from_days((local - sec) / 86400)
	var parts: PackedStringArray = PackedStringArray()
	if with_date:
		parts.append(date_text(civil.x, civil.y, civil.z, language))
	if with_time:
		parts.append(time_text(sec / 3600, (sec % 3600) / 60))
	return " ".join(parts)


func _language() -> String:
	if not _language_source.is_valid():
		return LanguagePolicy.DEFAULT_LANGUAGE
	var value: Variant = _language_source.call()
	if LanguagePolicy.is_supported(value):
		return value
	return LanguagePolicy.DEFAULT_LANGUAGE


func _offset() -> int:
	var value: Variant = null
	if _offset_source.is_valid():
		value = _offset_source.call()
	if typeof(value) != TYPE_INT:
		push_warning("LocalFormat: offset is not an int: %s" % [value])
		return 0
	var clamped: int = clampi(value, MIN_OFFSET_MINUTES, MAX_OFFSET_MINUTES)
	if clamped != value:
		push_warning("LocalFormat: offset clamped: %d" % value)
	return clamped


func _now() -> int:
	var value: Variant = 0
	if _clock_source.is_valid():
		value = _clock_source.call()
	if typeof(value) == TYPE_FLOAT and not is_nan(value) and not is_inf(value):
		value = floori(clampf(value, 0.0, float(MAX_UNIX)))
	if typeof(value) != TYPE_INT:
		push_warning("LocalFormat: clock is not a number: %s" % [value])
		return 0
	var clamped: int = clampi(value, 0, MAX_UNIX)
	if clamped != value:
		push_warning("LocalFormat: clock clamped: %d" % value)
	return clamped


static func parse_timestamp(value: Variant) -> int:
	match typeof(value):
		TYPE_STRING:
			return _parse_string(value)
		TYPE_INT:
			return value if value >= 0 and value <= MAX_UNIX else -1
		TYPE_FLOAT:
			if is_nan(value) or is_inf(value) or value < 0.0 or value > float(MAX_UNIX):
				return -1
			return int(value)
	return -1


static func _parse_string(text: String) -> int:
	if text.length() != 20:
		return -1
	for index: int in [4, 7]:
		if text.unicode_at(index) != 45:
			return -1
	if text.unicode_at(10) != 84 or text.unicode_at(19) != 90:
		return -1
	if text.unicode_at(13) != 58 or text.unicode_at(16) != 58:
		return -1
	for index: int in range(20):
		if [4, 7, 10, 13, 16, 19].has(index):
			continue
		var code: int = text.unicode_at(index)
		if code < 48 or code > 57:
			return -1
	var y: int = text.substr(0, 4).to_int()
	var m: int = text.substr(5, 2).to_int()
	var d: int = text.substr(8, 2).to_int()
	var h: int = text.substr(11, 2).to_int()
	var mi: int = text.substr(14, 2).to_int()
	var s: int = text.substr(17, 2).to_int()
	if y < 1970 or m < 1 or m > 12 or d < 1 or d > _days_in_month(y, m):
		return -1
	if h > 23 or mi > 59 or s > 59:
		return -1
	return days_from_civil(y, m, d) * 86400 + h * 3600 + mi * 60 + s


static func _days_in_month(y: int, m: int) -> int:
	if m == 2:
		return 29 if (y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)) else 28
	return 30 if [4, 6, 9, 11].has(m) else 31


static func days_from_civil(year: int, month: int, day: int) -> int:
	var y: int = year - (1 if month <= 2 else 0)
	var era: int = y / 400
	var yoe: int = y - era * 400
	var doy: int = (153 * (month - 3 if month > 2 else month + 9) + 2) / 5 + day - 1
	var doe: int = yoe * 365 + yoe / 4 - yoe / 100 + doy
	return era * 146097 + doe - 719468


static func civil_from_days(days: int) -> Vector3i:
	var z: int = days + 719468
	var era: int = z / 146097
	var doe: int = z - era * 146097
	var yoe: int = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
	var doy: int = doe - (365 * yoe + yoe / 4 - yoe / 100)
	var mp: int = (5 * doy + 2) / 153
	var d: int = doy - (153 * mp + 2) / 5 + 1
	var m: int = mp + 3 if mp < 10 else mp - 9
	return Vector3i(yoe + era * 400 + (1 if m <= 2 else 0), m, d)


static func last_sunday(year: int, month: int) -> int:
	return 31 - posmod(days_from_civil(year, month, 31) + 4, 7)


static func is_eu_dst(unix: int) -> bool:
	var y: int = civil_from_days((unix - posmod(unix, 86400)) / 86400).x
	var start: int = days_from_civil(y, 3, last_sunday(y, 3)) * 86400 + 3600
	var end: int = days_from_civil(y, 10, last_sunday(y, 10)) * 86400 + 3600
	return start <= unix and unix < end


static func standard_offset(current_minutes: int, now_unix: int) -> int:
	return current_minutes - 60 if is_eu_dst(now_unix) else current_minutes


static func offset_at(unix: int, current_minutes: int, now_unix: int) -> int:
	var std: int = standard_offset(current_minutes, now_unix)
	if EU_STANDARD_OFFSETS.has(std):
		return std + (60 if is_eu_dst(unix) else 0)
	return current_minutes


static func date_text(year: int, month: int, day: int, language: String) -> String:
	return _DATE_PATTERNS.get(language, _DATE_PATTERNS["en"]) % [year, month, day]


static func time_text(hour: int, minute: int) -> String:
	return "%02d:%02d" % [hour, minute]


static func decimal_separator(language: String) -> String:
	return _DECIMAL_SEPARATORS.get(language, ".")


static func decimal_text(value: float, decimals: int, separator: String) -> String:
	if is_nan(value) or is_inf(value):
		return ""
	var d: int = clampi(decimals, 0, MAX_DECIMALS)
	if d != decimals:
		push_warning("LocalFormat: decimals clamped: %d" % decimals)
	var text: String = DecimalDouble.to_text(absf(value))
	if text.is_empty():
		text = String.num_scientific(absf(value))
	var mantissa: String = text.get_slice("e", 0)
	var e10: int = text.get_slice("e", 1).to_int() if "e" in text else 0
	var int_digits: String = mantissa.get_slice(".", 0)
	var frac_digits: String = mantissa.get_slice(".", 1) if "." in mantissa else ""
	var digits: String = int_digits + frac_digits
	var point: int = int_digits.length() + e10
	if point < 0:
		digits = "0".repeat(-point) + digits
		point = 0
	while digits.length() < point + d + 1:
		digits += "0"
	var kept: String = digits.substr(0, point + d)
	if digits.unicode_at(point + d) >= 53:
		var chars: PackedStringArray = PackedStringArray(kept.split(""))
		var i: int = chars.size() - 1
		var carry: bool = true
		while i >= 0 and carry:
			if chars[i] == "9":
				chars[i] = "0"
			else:
				chars[i] = str(chars[i].to_int() + 1)
				carry = false
			i -= 1
		kept = "".join(chars)
		if carry:
			kept = "1" + kept
	var int_part: String = kept.substr(0, kept.length() - d).lstrip("0")
	if int_part.is_empty():
		int_part = "0"
	var result: String = int_part
	if d > 0:
		result += separator + kept.substr(kept.length() - d)
	var nonzero: bool = false
	for ch: String in kept:
		if ch != "0":
			nonzero = true
	if value < 0.0 and nonzero:
		result = "-" + result
	return result


static func system_offset_minutes() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0))
