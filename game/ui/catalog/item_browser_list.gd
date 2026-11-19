class_name ItemBrowserList
extends RefCounted
## The pure list logic of the item browser (#30): which categories are shown and which items match
## a category and a search. No Node and no translation here: the panel passes in the translated
## names. The catalog order is kept as it is; nothing is sorted again.

## "All" is represented by ItemDefinition.Category.UNSET (no catalog item has it).
const ALL: ItemDefinition.Category = ItemDefinition.Category.UNSET
const CATEGORY_ORDER: Array[ItemDefinition.Category] = [
	ItemDefinition.Category.ROCK,
	ItemDefinition.Category.WOOD,
	ItemDefinition.Category.ORNAMENT,
	ItemDefinition.Category.PLANT,
]


## The query as it is compared: no leading or trailing spaces, lower case. Accents stay.
static func normalise_query(text: String) -> String:
	return text.strip_edges().to_lower()


## True when the display name contains the query. The query is already normalised; an empty query
## matches everything.
static func matches(display_name: String, query: String) -> bool:
	if query.is_empty():
		return true
	return display_name.to_lower().contains(query)


## ALL first, then every category of CATEGORY_ORDER that has at least one item.
static func visible_categories(catalog: ItemCatalog) -> Array[ItemDefinition.Category]:
	var result: Array[ItemDefinition.Category] = [ALL]
	for category: ItemDefinition.Category in CATEGORY_ORDER:
		if not catalog.get_ids_in_category(category).is_empty():
			result.append(category)
	return result


## The ids of the category (ALL: every item) whose name matches the query, in catalog order. A
## name missing from `names` counts as the id's name key, like the card text does.
static func filter(
	catalog: ItemCatalog,
	names: Dictionary[StringName, String],
	category: ItemDefinition.Category,
	query: String
) -> Array[StringName]:
	var wanted: String = normalise_query(query)
	var source: Array[StringName] = (
		catalog.get_ids() if category == ALL else catalog.get_ids_in_category(category)
	)
	var result: Array[StringName] = []
	for id: StringName in source:
		var shown: String = names.get(id, catalog.get_definition(id).name_key)
		if matches(shown, wanted):
			result.append(id)
	return result
