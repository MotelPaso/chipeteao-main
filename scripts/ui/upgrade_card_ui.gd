extends CanvasLayer
## Card picker: on RunState.leveled_up it pauses the tree, frees the
## mouse, and offers 3 rolled upgrades from UpgradePool. Runs with
## process_mode ALWAYS so its buttons work while everything else is
## paused. Shrines and chests reach it through the "upgrade_ui" group via
## open_bonus_pick() for free picks (optionally luck-boosted or
## rarity-floored). Level-ups or bonus picks arriving while already open
## are queued — pending levels first, then bonus picks — and served as
## consecutive rerolls before unpausing.

## Seconds between pausing the tree and revealing the cards: a beat for
## the level-up pulse to read under the freeze-frame. Keep under ~0.25.
const REVEAL_DELAY := 0.2

@onready var _level_label: Label = %LevelLabel
@onready var _cards: Array[Button] = [%Card1 as Button, %Card2 as Button, %Card3 as Button]

var _offer: Array[Dictionary] = []
## True from the pause until the delayed reveal: requests landing in that
## window must queue exactly as if the picker were already visible.
var _opening: bool = false
var _pending_levels: int = 0
## Queued open_bonus_pick requests ({title, luck_bonus, min_rarity}).
var _pending_bonus: Array[Dictionary] = []
## Roll context for the pick currently on screen (zeroed for level picks).
var _luck_bonus: float = 0.0
var _min_rarity: String = ""


func _ready() -> void:
	visible = false
	add_to_group("upgrade_ui")
	RunState.leveled_up.connect(_on_leveled_up)
	for i in _cards.size():
		_cards[i].pressed.connect(_on_card_pressed.bind(i))


## Public (shrines/chests via the "upgrade_ui" group): a free card pick
## outside the level-up flow. luck_bonus is temporary rarity-tilt luck for
## this roll only; min_rarity (e.g. "Rare") floors every rolled rarity.
## Queues behind whatever pick is already open; same-frame level-ups and
## bonus picks therefore never eat each other.
func open_bonus_pick(title: String, luck_bonus: float = 0.0, min_rarity: String = "") -> void:
	if not RunState.run_active:
		return
	var request := {"title": title, "luck_bonus": luck_bonus, "min_rarity": min_rarity}
	if visible or _opening:
		_pending_bonus.append(request)
		return
	_open_bonus_pick(request)


func _on_leveled_up(new_level: int) -> void:
	# Run-end wins over a level-up landing the same frame: once the run is
	# over, the run-end screen (layer 20) owns the pause and the mouse.
	if not RunState.run_active:
		return
	if visible or _opening:
		_pending_levels += 1
		return
	_open_level_pick(new_level)


func _open_level_pick(new_level: int) -> void:
	_luck_bonus = 0.0
	_min_rarity = ""
	_open("Level %d — choose an upgrade" % new_level)


func _open_bonus_pick(request: Dictionary) -> void:
	_luck_bonus = float(request.luck_bonus)
	_min_rarity = String(request.min_rarity)
	_open(String(request.title))


func _open(title: String) -> void:
	get_tree().paused = true
	_level_label.text = title
	_roll()
	if visible:
		# Chained pick (card just pressed): already on screen, swap in place.
		return
	# Pause lands immediately (no combat can race the reveal window); the
	# cards show after a short beat so the level-up pulse reads first. The
	# timer processes while paused and ignores hit-stop time scaling.
	_opening = true
	var timer := get_tree().create_timer(REVEAL_DELAY, true, false, true)
	timer.timeout.connect(_reveal, CONNECT_ONE_SHOT)


func _reveal() -> void:
	_opening = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	visible = true


func _roll() -> void:
	# The pool needs the player to offer only owned-weapon upgrades and
	# unowned new-weapon cards (re-derived on every reroll).
	var player := get_tree().get_first_node_in_group("player")
	_offer = UpgradePool.roll_offer(player, _cards.size(), _luck_bonus, _min_rarity)
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
		_open_level_pick(RunState.level)
		return
	if not _pending_bonus.is_empty():
		var request: Dictionary = _pending_bonus.pop_front()
		_open_bonus_pick(request)
		return
	_close()


func _close() -> void:
	visible = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
