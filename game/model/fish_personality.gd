class_name FishPersonality
extends RefCounted
## The derived personality of a fish (ADR 0015 rule 1): five traits that are a pure function of
## the uid, never saved. The species id does not enter the hash; the species only supplies the base
## values the unitless traits are applied to. FROZEN once released (STATE open until the owner
## approves or the v0.1 tag): the five salts, their order and the three formula constants below.
##
## With u = FishHash.unit(uid, salt): speed, boldness, sociability and idle share are factors
## FACTOR_MIN + FACTOR_SPAN * u (range [0.80, 1.20)); depth preference is the fraction
## (2u - 1) * DEPTH_SPAN of the band height (range [-0.20, 0.20)).

## The salts in the frozen trait order: speed, boldness, sociability, idle share, depth preference.
const SALTS: Array[String] = [
	FishHash.SALT_TRAIT_SPEED,
	FishHash.SALT_TRAIT_BOLDNESS,
	FishHash.SALT_TRAIT_SOCIABILITY,
	FishHash.SALT_TRAIT_IDLE_SHARE,
	FishHash.SALT_TRAIT_DEPTH_PREFERENCE,
]
const FACTOR_MIN: float = 0.80
const FACTOR_SPAN: float = 0.40
const DEPTH_SPAN: float = 0.20

## Factor on the species cruise and top speed.
var speed: float = 1.0
## Factor on how often a fish darts (divides the dart interval) and how fast the dart is.
var boldness: float = 1.0
## Factor on the pull to its group.
var sociability: float = 1.0
## Factor on the species idle share.
var idle_share: float = 1.0
## Offset of the preferred height from the band centre, as a fraction of the band height.
var depth_preference: float = 0.0


static func derive(uid: String) -> FishPersonality:
	var result: FishPersonality = FishPersonality.new()
	result.speed = _factor(uid, SALTS[0])
	result.boldness = _factor(uid, SALTS[1])
	result.sociability = _factor(uid, SALTS[2])
	result.idle_share = _factor(uid, SALTS[3])
	result.depth_preference = (2.0 * FishHash.unit(uid, SALTS[4]) - 1.0) * DEPTH_SPAN
	return result


## The five traits in the frozen order.
func to_array() -> PackedFloat64Array:
	return PackedFloat64Array([speed, boldness, sociability, idle_share, depth_preference])


static func _factor(uid: String, salt: String) -> float:
	return FACTOR_MIN + FACTOR_SPAN * FishHash.unit(uid, salt)
