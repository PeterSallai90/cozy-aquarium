class_name FishDefaultName
extends RefCounted
## The derived default name of a fish (ADR 0014): a translation key chosen from the uid alone with
## FishHash and the salt `fish.name.default`. Pure and static; it returns a key and never calls
## tr(), the UI does that. The list of keys, its order, COUNT and the formula are frozen with the
## golden test (freeze rule: see test_fish_default_name_golden.gd).

const COUNT: int = 30
const KEY_PREFIX: String = "fish.default_name."


## The 1-based list index for a hash unit in [0, 1): min(floor(unit * COUNT), COUNT - 1) + 1.
static func index_for_unit(unit: float) -> int:
	return clampi(floori(unit * COUNT), 0, COUNT - 1) + 1


static func key_at(index: int) -> String:
	return KEY_PREFIX + "%02d" % index


static func key_for(uid: String) -> String:
	return key_at(index_for_unit(FishHash.unit(uid, FishHash.SALT_DEFAULT_NAME)))


## fish.default_name.01 to fish.default_name.30 in order.
static func all_keys() -> PackedStringArray:
	var keys: PackedStringArray = PackedStringArray()
	for index: int in range(1, COUNT + 1):
		keys.append(key_at(index))
	return keys
