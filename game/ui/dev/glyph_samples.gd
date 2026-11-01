extends RefCounted
## Sample table shared by the glyph test scene and the glyph tests (data only).
##
## Keys: id (unique, used in node names), script (developer label, never translated), text,
## informational (recorded, never asserted), layer1_only (must come from layer 1 alone).

const ROWS: Array[Dictionary] = [
	{
		"id": "hungarian",
		"script": "Hungarian",
		"text": "Árvíztűrő tükörfúrógép",
		"informational": false,
		"layer1_only": true,
	},
	{
		"id": "hungarian_upper",
		"script": "Hungarian",
		"text": "ÁRVÍZTŰRŐ TÜKÖRFÚRÓGÉP",
		"informational": false,
		"layer1_only": true,
	},
	{
		"id": "russian",
		"script": "Cyrillic",
		"text": "Привет, аквариум",
		"informational": false,
		"layer1_only": false,
	},
	{
		"id": "greek",
		"script": "Greek",
		"text": "Γειά σου, ενυδρείο",
		"informational": false,
		"layer1_only": false,
	},
	{
		"id": "mixed",
		"script": "Mixed",
		"text": "Neon tetra Привет Γειά",
		"informational": false,
		"layer1_only": false,
	},
	{
		"id": "chinese_sc",
		"script": "Chinese SC",
		"text": "鱼缸",
		"informational": true,
		"layer1_only": false,
	},
	{
		"id": "chinese_tc",
		"script": "Chinese TC",
		"text": "魚缸",
		"informational": true,
		"layer1_only": false,
	},
	{
		"id": "japanese",
		"script": "Japanese",
		"text": "水槽 ひらがな カタカナ",
		"informational": true,
		"layer1_only": false,
	},
	{
		"id": "korean",
		"script": "Korean",
		"text": "어항",
		"informational": true,
		"layer1_only": false,
	},
	{
		"id": "mixed_cjk",
		"script": "Mixed + CJK",
		"text": "Neon Привет Γειά 鱼缸",
		"informational": true,
		"layer1_only": false,
	},
	{
		"id": "emoji",
		"script": "Emoji",
		"text": "🐟🐠🌿",
		"informational": true,
		"layer1_only": false,
	},
]
