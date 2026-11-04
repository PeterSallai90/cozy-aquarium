extends RefCounted
## Load-every-script helper (#92, ADR 0004). Pure: it does not capture engine output.

const SourceScan := preload("res://tests/helpers/source_scan.gd")
const SELF_PATH := "res://tests/helpers/script_analysis.gd"
const RUNNING_TEST := "res://tests/test_script_analysis.gd"
const EXCLUDED: PackedStringArray = ["res://addons/", "res://.godot/"]


## Every script path outside the addons, sorted.
static func project_scripts() -> PackedStringArray:
	var paths: PackedStringArray = SourceScan.list_scripts("res://", EXCLUDED)
	paths.sort()
	return paths


## Paths that do not load as an instantiable script. CACHE_MODE_IGNORE forces a fresh analysis,
## because a cached script is not analysed again. This file and the census test are skipped:
## reloading a script that is running breaks the call or crashes the engine, and both were already
## analysed when they loaded.
static func failing_scripts(paths: PackedStringArray) -> PackedStringArray:
	var failing: PackedStringArray = PackedStringArray()
	for path: String in paths:
		if path == SELF_PATH or path == RUNNING_TEST:
			continue
		var script: GDScript = (
			ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
		)
		if script == null or not script.can_instantiate():
			failing.append(path)
	return failing
