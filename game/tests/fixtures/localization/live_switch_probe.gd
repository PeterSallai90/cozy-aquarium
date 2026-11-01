extends Control
## Test-only probe for the live language switch. A Label with a key text (auto-translated) and a
## Label with text the code builds itself (the pattern every UI follows).

const APPLES: int = 3

var refresh_count: int = 0

@onready var title: Label = $Title
@onready var count: Label = $Count


func _ready() -> void:
	_refresh_texts()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_texts()


func _refresh_texts() -> void:
	refresh_count += 1
	count.text = tr_n("ui.fixture.apples", "ui.fixture.apples.plural", APPLES) % APPLES
