extends CanvasLayer
## Card picker: on RunState.leveled_up it pauses the tree, frees the
## mouse, and offers 3 rolled upgrades from UpgradePool. Runs with
## process_mode ALWAYS so its buttons work while everything else is
## paused. Shrines and chests reach it through the "upgrade_ui" group via
## open_bonus_pick() for free picks (optionally luck-boosted or
## rarity-floored). Level-ups or bonus picks arriving while already open
## are queued — pending levels first, then bonus picks — and served as
## consecutive rerolls before unpausing.
##
## Look (iteration 29): radial dim fades in, the 3 cards deal in with a
## staggered overshoot, rarity reads as border + outer glow + a top
## ribbon (Legendary adds a slow shimmer), hovering lifts a card, and the
## chosen card punches up while the losers fall away (0.16s) before the
## next queued pick or the close. All motion runs on this ALWAYS layer
## and ignores time scale, so the paused tree and hit-stop never stall
## it; the pause/queue/is_blocking contract is unchanged.

## Seconds between pausing the tree and revealing the cards: a beat for
## the level-up pulse to read under the freeze-frame. Keep under ~0.25.
const REVEAL_DELAY := 0.2

## Chosen-card punch / losers-fall beat before serving the next pick.
const PICK_ANIM_TIME := 0.16

@onready var _dim: ColorRect = %Dim
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
## True during the 0.16s pick animation: swallows further card clicks so
## a double-click can never apply two upgrades from one offer.
var _picking: bool = false
var _deal_tween: Tween = null
var _pick_tween: Tween = null
## Legendary shimmer loops, killed on every reroll.
var _shine_tweens: Array[Tween] = []


func _ready() -> void:
	visible = false
	add_to_group("upgrade_ui")
	add_to_group("ui_blocking")
	RunState.leveled_up.connect(_on_leveled_up)
	UiTheme.style_title(_level_label, 34, Color(0.96, 0.93, 0.82), 4, 8)
	for i in _cards.size():
		_cards[i].pressed.connect(_on_card_pressed.bind(i))
		UiTheme.attach_motion(_cards[i], 1.05, 0.97)


## PauseMenu contract ("ui_blocking"): true while this layer owns the tree
## pause — including the pre-reveal window where nothing is visible yet.
func is_blocking() -> bool:
	return visible or _opening


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
		# Chained pick (card just pressed): already on screen — deal the
		# fresh offer in with a quick half-strength re-deal.
		_deal(true)
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
	_deal(false)


## Deal-in motion: dim fades up and each visible card slides in from a
## smaller scale with a 0.06s stagger and a back-ease overshoot (~0.35s
## total; quick = the in-place swap between chained picks). Idempotent:
## restarting kills the previous deal first.
func _deal(quick: bool) -> void:
	if _deal_tween != null and _deal_tween.is_valid():
		_deal_tween.kill()
	_deal_tween = create_tween().set_parallel()
	_deal_tween.set_ignore_time_scale(true)
	if not quick:
		_dim.modulate.a = 0.0
		_deal_tween.tween_property(_dim, "modulate:a", 1.0, 0.15)
		_level_label.pivot_offset = _level_label.size * 0.5
		_level_label.scale = Vector2(0.9, 0.9)
		_deal_tween.tween_property(_level_label, "scale", Vector2.ONE, 0.22) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_dim.modulate.a = 1.0
	var start_scale := 0.92 if quick else 0.8
	var duration := 0.14 if quick else 0.22
	for i in _cards.size():
		var card := _cards[i]
		if not card.visible:
			continue
		card.pivot_offset = card.size * 0.5
		card.scale = Vector2.ONE * start_scale
		card.modulate = Color(1.0, 1.0, 1.0, 0.0)
		var delay := (0.03 if quick else 0.06) * i
		_deal_tween.tween_property(card, "modulate:a", 1.0, duration * 0.7) \
				.set_delay(delay)
		_deal_tween.tween_property(card, "scale", Vector2.ONE, duration) \
				.set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _roll() -> void:
	for tween: Tween in _shine_tweens:
		if tween.is_valid():
			tween.kill()
	_shine_tweens.clear()
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
	var rarity_color := rarity.color as Color
	var rarity_label: Label = card.get_node("CardBox/RarityLabel")
	rarity_label.text = String(rarity.name).to_upper()
	# Top ribbon: rarity-colored pill with dark text, spaced like a stamp.
	rarity_label.add_theme_font_override("font", UiTheme.spaced_font(3))
	UiTheme.style_badge(rarity_label, Color(0.07, 0.075, 0.1),
			rarity_color, rarity_color.lightened(0.2))
	rarity_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var title_label := card.get_node("CardBox/TitleLabel") as Label
	title_label.text = item.title
	title_label.add_theme_color_override("font_color", UiTheme.TEXT_BRIGHT)
	var desc_label := card.get_node("CardBox/DescLabel") as Label
	desc_label.text = item.description
	desc_label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_style_card(card, rarity_color)
	if String(rarity.name) == "Legendary":
		# Slow shine: the whole card breathes brighter (the shadow glow in
		# the stylebox rides along).
		var shine := create_tween().set_loops()
		shine.set_ignore_time_scale(true)
		shine.tween_property(card, "self_modulate", Color(1.25, 1.18, 1.0), 0.7) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		shine.tween_property(card, "self_modulate", Color.WHITE, 0.7) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_shine_tweens.append(shine)
	else:
		card.self_modulate = Color.WHITE


func _style_card(card: Button, border_color: Color) -> void:
	var fills: Dictionary[String, Color] = {
		"normal": UiTheme.CARD_BG,
		"hover": UiTheme.CARD_BG_HOVER,
		"pressed": UiTheme.CARD_BG_PRESSED,
		"focus": UiTheme.CARD_BG_HOVER,
	}
	for state: String in fills:
		var style := UiTheme.flat(fills[state], UiTheme.RADIUS)
		style.border_color = border_color if state != "hover" \
				else border_color.lightened(0.2)
		style.set_border_width_all(3)
		UiTheme.add_glow(style, border_color, 10,
				0.5 if state == "hover" else 0.3)
		card.add_theme_stylebox_override(state, style)


func _on_card_pressed(index: int) -> void:
	if index >= _offer.size() or _picking:
		return
	_picking = true
	Sfx.play(&"card_pick")
	# Apply immediately (original contract) — only the visual beat waits.
	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		UpgradePool.apply(_offer[index], player)
	_animate_pick(index)


## Chosen card punches up, the losers drop and fade; after the short beat
## the queue continues exactly as before (levels first, then bonus picks).
func _animate_pick(index: int) -> void:
	if _pick_tween != null and _pick_tween.is_valid():
		_pick_tween.kill()
	_pick_tween = create_tween().set_parallel()
	_pick_tween.set_ignore_time_scale(true)
	for i in _cards.size():
		var card := _cards[i]
		if not card.visible:
			continue
		card.pivot_offset = card.size * 0.5
		if i == index:
			_pick_tween.tween_property(card, "scale", Vector2(1.12, 1.12),
					PICK_ANIM_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		else:
			_pick_tween.tween_property(card, "scale", Vector2(0.9, 0.9), PICK_ANIM_TIME)
			_pick_tween.tween_property(card, "modulate:a", 0.2, PICK_ANIM_TIME)
	_pick_tween.chain().tween_callback(_after_pick)


func _after_pick() -> void:
	_picking = false
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
	# Leave no stale motion for the next open (deal re-seeds everything).
	for card: Button in _cards:
		card.scale = Vector2.ONE
		card.modulate = Color.WHITE
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
