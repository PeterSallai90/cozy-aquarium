class_name ItemCatalogSource
extends RefCounted
## One shared ItemCatalog per session, loaded on the first get_catalog() call and never before
## (ADR 0012 rule 6, #30 AC 23). main.gd creates it and hands the same instance to the item browser
## and to placement. Loading the definitions also loads every item scene and thumbnail they
## reference, so the cost falls on the first need and not at game start.

var _catalog: ItemCatalog = null
var _load_count: int = 0


## A source that already holds `catalog`; it counts as no load. For tests and fixtures.
static func from_catalog(catalog: ItemCatalog) -> ItemCatalogSource:
	var source: ItemCatalogSource = ItemCatalogSource.new()
	source._catalog = catalog
	return source


## The shared catalog; the shipped item folders are loaded on the first call only.
func get_catalog() -> ItemCatalog:
	if _catalog == null:
		_catalog = ItemCatalog.load_dirs()
		_load_count += 1
	return _catalog


func is_loaded() -> bool:
	return _catalog != null


## How many times the shipped folders were loaded (0 or 1).
func get_load_count() -> int:
	return _load_count
