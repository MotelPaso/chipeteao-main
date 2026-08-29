extends CanvasLayer
## Level-up card picker: on RunState.leveled_up it pauses the tree, frees
## the mouse, and offers 3 rolled upgrades from UpgradePool. Runs with
## process_mode ALWAYS so its buttons work while everything else is
## paused. Level-ups arriving while already open are queued and served as
## consecutive rerolls before unpausing.

@onready var _level_label: Label = %LevelLabel
@onready var _cards: Array[Button] = [%Card1 as Button, %Card2 as Button, %Card3 as Button]

var _offer: Array[Dictionary] = []
var _pending_levels: int = 0


func _ready() -> void:
	visible = false
	RunState.leveled_up.connect(_on_leveled_up)
	for i in _cards.size():
		_cards[i].pressed.connect(_on_card_pressed.bind(i))


func _on_leveled_up(new_level: int) -> void:
	# Run-end wins over a level-up landing the same frame: once the run is
	# over, the run-end screen (layer 20) owns the pause and the mouse.
	if not RunState.run_active:
		return
	if visible:
		_pending_levels += 1
		return
	_open(new_level)


func _open(new_level: int) -> void:
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_level_label.text = "Level %d — choose an upgrade" % new_level
	_roll()
	visible = true


func _roll() -> void:
	_offer = UpgradePool.roll_offer(_cards.size())
	for i in _cards.size():
		_cards[i].visible = i < _offer.size()
		if i < _offer.size():
			_populate_card(_cards[i], _offer[i])


func _populate_card(card: Button, item: Dictionary) -> void:
	var rarity: Dictionary = item.rarity
	var rarity_label: Label = card.get_node("CardBox/RarityLabel")
	rarity_label.text = String(rarity.name).to_upper()
	rarity_label.add_theme_color_override("font_color", rarity.color)
	(card.get_node("CardBox/TitleLabel") as Label).text = item.title
	(card.get_node("CardBox/DescLabel") as Label).text = item.description
	_style_card(card, rarity.color)


func _style_card(card: Button, border_color: Color) -> void:
	var fills := {
		"normal": Color(0.13, 0.14, 0.18, 0.97),
		"hover": Color(0.18, 0.2, 0.26, 0.97),
		"pressed": Color(0.1, 0.11, 0.14, 0.97),
		"focus": Color(0.18, 0.2, 0.26, 0.97),
	}
	for state: String in fills:
		var style := StyleBoxFlat.new()
		style.bg_color = fills[state]
		style.border_color = border_color
		style.set_border_width_all(3)
		style.set_corner_radius_all(10)
		card.add_theme_stylebox_override(state, style)


func _on_card_pressed(index: int) -> void:
	if index >= _offer.size():
		return
	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		UpgradePool.apply(_offer[index], player)
	if _pending_levels > 0:
		_pending_levels -= 1
		_level_label.text = "Level %d — choose an upgrade" % RunState.level
		_roll()
		return
	_close()


func _close() -> void:
	visible = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
