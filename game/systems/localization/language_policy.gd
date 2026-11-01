class_name LanguagePolicy
extends RefCounted
## Pure language rules: which languages exist and which one a first start picks.
## No Node, no file access, no OS calls; the OS locale is always passed in.

const DEFAULT_LANGUAGE: String = "en"
# The order is the order the settings screen lists the languages in.
const SUPPORTED_LANGUAGES: Array[String] = ["en", "hu"]
# Constants on purpose, not translated: each language is named in its own language.
const DISPLAY_NAMES: Dictionary[String, String] = {"en": "English", "hu": "Magyar"}


## A fresh copy of the supported language codes.
static func supported_languages() -> PackedStringArray:
	return PackedStringArray(SUPPORTED_LANGUAGES)


## True only for the exact (case-sensitive) String "en" or "hu".
static func is_supported(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and SUPPORTED_LANGUAGES.has(value)


## The language name in its own language, or "" for an unsupported code.
static func display_name(code: String) -> String:
	return DISPLAY_NAMES.get(code, "")


## First-start rule: Hungarian when the language part of the OS locale (before the first "_" or
## "-", case-insensitive) is "hu", otherwise English.
static func detect(os_locale: String) -> String:
	var lang: String = os_locale.strip_edges().to_lower().replace("-", "_").get_slice("_", 0)
	return "hu" if lang == "hu" else "en"


## The stored value when it is supported, otherwise the first-start rule.
static func resolve(stored: Variant, os_locale: String) -> String:
	if is_supported(stored):
		return stored
	return detect(os_locale)
