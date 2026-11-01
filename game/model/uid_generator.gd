class_name UidGenerator
extends RefCounted
## Generates 8 lowercase hex uids that are unused in a given model.

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## A seed of -1 randomises; any other value gives a deterministic sequence.
func _init(seed_value: int = -1) -> void:
	if seed_value == -1:
		_rng.randomize()
	else:
		_rng.seed = seed_value


## Returns a uid not used by any item or fish of the model. The model may be null.
func generate(model: AquariumModel) -> String:
	while true:
		var uid: String = "%08x" % _rng.randi()
		if model == null or not model.has_uid(uid):
			return uid
	return ""
