class_name SaveMigrations
extends RefCounted
## The production migration chain of the save format. Pure, static only.
##
## Key: the from-version (int). Value: Callable(data: Dictionary) -> Variant that upgrades the
## data by exactly one version and returns the new Dictionary, or null on failure. Every bump of
## the format version adds one step, which may be empty.


## The chain for the current format. Empty for version 1.
static func steps() -> Dictionary:
	return {}
