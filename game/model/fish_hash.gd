class_name FishHash
extends RefCounted
## The deterministic hash behind the derived fish values (ADR 0013 rule 6): FNV-1a, 32 bit, over
## the UTF-8 bytes of salt + ":" + uid, divided by 2^32. Pure and static. Every use has its own
## salt; the swim phase is not frozen. The `fish.trait.` family belongs to the personality of #35
## (FishPersonality, ADR 0015 rule 1, frozen); the `fish.name.` family is reserved for names
## (ADR 0014).

const SALT_REST_X: String = "fish.rest.x"
const SALT_REST_Z: String = "fish.rest.z"
const SALT_REST_Y: String = "fish.rest.y"
const SALT_REST_YAW: String = "fish.rest.yaw"
const SALT_SWIM_PHASE: String = "fish.swim.phase"
const SALT_DEFAULT_NAME: String = "fish.name.default"
const SALT_TRAIT_SPEED: String = "fish.trait.speed"
const SALT_TRAIT_BOLDNESS: String = "fish.trait.boldness"
const SALT_TRAIT_SOCIABILITY: String = "fish.trait.sociability"
const SALT_TRAIT_IDLE_SHARE: String = "fish.trait.idle_share"
const SALT_TRAIT_DEPTH_PREFERENCE: String = "fish.trait.depth_preference"

const _FNV_OFFSET: int = 2166136261
const _FNV_PRIME: int = 16777619
const _MASK_32: int = 0xFFFFFFFF
const _RANGE_32: float = 4294967296.0


## A repeatable number in [0, 1) for the uid under the salt.
static func unit(uid: String, salt: String) -> float:
	var value: int = _FNV_OFFSET
	for byte: int in (salt + ":" + uid).to_utf8_buffer():
		value = ((value ^ byte) * _FNV_PRIME) & _MASK_32
	return float(value) / _RANGE_32
