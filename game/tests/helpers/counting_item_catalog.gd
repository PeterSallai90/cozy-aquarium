extends ItemCatalog
## An ItemCatalog that counts get_definition() calls and answers from `inner` (#33 AC 17). Wrap it
## with ItemCatalogSource.from_catalog(). Test helper, never shipped.

var lookups: int = 0
var inner: ItemCatalog = null


func get_definition(id: StringName) -> ItemDefinition:
	lookups += 1
	return inner.get_definition(id) if inner != null else null
