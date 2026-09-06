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
## it; the pause/queue/is_blocking contract is unchanged. Every deal ends
## by focusing the first card and wiring left/right neighbours, so the
## pick is playable on pad or keyboard alone — with the tree paused and
## Esc blocked, a picker nobody can answer freezes the whole run.

## Seconds between pausing the tree and revealing the cards: a beat for
## the level-up pulse to read under the freeze-frame. Keep under ~0.25.
const REVEAL_DELAY := 0.2

## Chosen-card punch / losers-fall beat before serving the next pick.
const PICK_ANIM_TIME := 0.16

## Co-op title suffix. One template (not "title += ..."), so translating
## the separator or putting the raider first is a one-line change.
const RECIPIENT_TITLE_TEMPLATE := "%s  ·  Jugador %d"

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
## Co-op: the raider this pick belongs to. XP and level are party-wide, so
## picks rotate round-robin through the standing players — everyone grows.
## Solo: always the single player.
var _recipient: Node = null
var _recipient_rotation: int = 0
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
## `recipient` names the raider the prize belongs to — pass it whenever
## somebody PAID for the pick (greed shrine takes HP, chests take points),
## or the round-robin can hand their prize to a teammate. Omitting it
## keeps the old rotation, so existing 3-argument call_group callers are
## unaffected. Queues behind whatever pick is already open; same-frame
## level-ups and bonus picks therefore never eat each other.
func open_bonus_pick(title: String, luck_bonus: float = 0.0, min_rarity: String = "",
		recipient: Node = null) -> void:
	if not RunState.run_active:
		return
	var request := {"title": title, "luck_bonus": luck_bonus,
			"min_rarity": min_rarity, "recipient": recipient}
	if visible or _opening:
		_pending_bonus.append(request)
		return
	if not _open_bonus_pick(request):
		_pending_bonus.append(request)


func _on_leveled_up(new_level: int) -> void:
	# Run-end wins over a level-up landing the same frame: once the run is
	# over, the run-end screen (layer 20) owns the pause and the mouse.
	if not RunState.run_active:
		return
	if visible or _opening:
		_pending_levels += 1
		return
	if not _open_level_pick(new_level):
		_pending_levels += 1


## Each returns false when the pick could not be opened (nobody standing
## to receive it), so the caller re-queues it instead of losing it.
func _open_level_pick(new_level: int) -> bool:
	_luck_bonus = 0.0
	_min_rarity = ""
	return _open("Nivel %d — elige una mejora" % new_level)


func _open_bonus_pick(request: Dictionary) -> bool:
	_luck_bonus = float(request.luck_bonus)
	_min_rarity = String(request.min_rarity)
	return _open(String(request.title), request.get("recipient", null) as Node)


func _open(title: String, requested_recipient: Node = null) -> bool:
	# A prize somebody paid for goes to the payer; everything else rotates.
	var recipient := requested_recipient if is_instance_valid(requested_recipient) \
			else _pick_recipient()
	if recipient == null:
		# Whole party down (co-op) — the offer is rolled from a BODY's
		# weapons, so there is nothing to roll against. Resolved BEFORE
		# the pause: an empty picker over a paused tree is a wedge.
		return false
	get_tree().paused = true
	_recipient = recipient
	if Coop.is_coop():
		title = RECIPIENT_TITLE_TEMPLATE % [title, int(_recipient.get("player_index")) + 1]
	_level_label.text = title
	_roll()
	if visible:
		# Chained pick (card just pressed): already on screen — deal the
		# fresh offer in with a quick half-strength re-deal.
		_deal(true)
		return true
	# Pause lands immediately (no combat can race the reveal window); the
	# cards show after a short beat so the level-up pulse reads first. The
	# timer processes while paused and ignores hit-stop time scaling.
	_opening = true
	var timer := get_tree().create_timer(REVEAL_DELAY, true, false, true)
	timer.timeout.connect(_reveal, CONNECT_ONE_SHOT)
	return true


func _reveal() -> void:
	_opening = false
	# The run can end during the 0.2 s reveal window (a gem levels you up
	# at the top of the tick, an enemy kills you before it ends): the
	# run-end screen owns the pause and the mouse from then on, so this
	# pick must fold silently instead of drawing under it.
	if not RunState.run_active:
		_cancel_pick()
		return
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
	_focus_first_card()


## Keyboard/pad access: without an explicit focus nothing here answers
## ui_left/ui_right/ui_accept, and since the tree is paused and Esc is
## blocked by the "ui_blocking" contract, a pad-only player is stuck until
## they find a mouse. Focus is re-grabbed on every deal (a chained pick
## replaces the offer under the cursor).
func _focus_first_card() -> void:
	var visible_cards: Array[Button] = []
	for card: Button in _cards:
		if card.visible:
			visible_cards.append(card)
	if visible_cards.is_empty():
		return
	# Wrap-around left/right neighbours, so the row navigates as a ring.
	for i in visible_cards.size():
		var previous := visible_cards[(i - 1 + visible_cards.size()) % visible_cards.size()]
		var next := visible_cards[(i + 1) % visible_cards.size()]
		visible_cards[i].focus_neighbor_left = previous.get_path()
		visible_cards[i].focus_neighbor_right = next.get_path()
	visible_cards[0].grab_focus()


func _roll() -> void:
	_kill_shines()
	# The pool needs the recipient to offer only THEIR owned-weapon
	# upgrades and new-weapon cards (re-derived on every reroll).
	var player := _resolve_recipient()
	_offer = UpgradePool.roll_offer(player, _cards.size(), _luck_bonus, _min_rarity)
	for i in _cards.size():
		_cards[i].visible = i < _offer.size()
		if i < _offer.size():
			_populate_card(_cards[i], _offer[i])


func _populate_card(card: Button, item: Dictionary) -> void:
	var rarity: Dictionary = item.rarity
	var rarity_color := rarity.color as Color
	var rarity_label: Label = card.get_node("CardBox/RarityLabel")
	# rarity.name is an ID (chest prices, item rows, min_rarity floors all
	# key off it): translated only here, on the way to the screen.
	rarity_label.text = UpgradePool.rarity_display(String(rarity.name)).to_upper()
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
	UiTheme.style_card(card, rarity_color)
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


func _on_card_pressed(index: int) -> void:
	if index >= _offer.size() or _picking:
		return
	_picking = true
	Sfx.play(&"card_pick")
	# Apply immediately (original contract) — only the visual beat waits.
	# Same recipient the offer was rolled for (weapon upgrades must land on
	# the body that owns the weapon): _resolve_recipient caches its answer,
	# so the roll and the click can never resolve to different raiders.
	var player := _resolve_recipient()
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
		# BaseButton emits button_up before pressed, so attach_motion's
		# hover tween is still writing `scale` when the punch starts. Kill
		# it or the two fight over the property and the payoff stutters.
		UiTheme.kill_meta_tween(card, &"ui_motion_tween")
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
	# A queued pick that cannot open right now (nobody standing) goes back
	# in the queue and the picker closes instead of sitting on a stale
	# offer over a paused tree.
	if _pending_levels > 0:
		_pending_levels -= 1
		if _open_level_pick(RunState.level):
			return
		_pending_levels += 1
	if not _pending_bonus.is_empty():
		var request: Dictionary = _pending_bonus.pop_front()
		if _open_bonus_pick(request):
			return
		_pending_bonus.push_front(request)
	_close()


## Round-robin over the party BY SLOT, not by position in the alive list:
## the rotation counter names a slot (0..player_count-1) and the pick goes
## to that raider if they are standing, else to the next standing slot.
## Rotating over the alive array instead would re-map every turn whenever
## someone falls or revives (the modulus changes), and a raider could draw
## twice as many cards as another across a run with heavy downs.
func _pick_recipient() -> Node:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	if not Coop.is_coop():
		return players[0]
	for i in Coop.player_count:
		var slot := (_recipient_rotation + i) % Coop.player_count
		for node: Node in players:
			if int(node.get("player_index")) != slot:
				continue
			# Next pick starts looking one slot past this one, so a downed
			# raider cedes the turn without shifting anybody else's order.
			_recipient_rotation = slot + 1
			return node
	return null


## The raider this pick belongs to, resolved once and reused: _roll() and
## _on_card_pressed() must never answer differently (the offer is built
## from one body's weapons and has to land on that same body). Falls back
## to the LOWEST STANDING SLOT — not get_first_node_in_group, whose order
## shuffles every time someone goes down and is revived.
func _resolve_recipient() -> Node:
	if _recipient != null and is_instance_valid(_recipient) and _recipient.is_inside_tree():
		return _recipient
	var best: Node = null
	var best_slot := Coop.MAX_PLAYERS
	for node: Node in get_tree().get_nodes_in_group("player"):
		var slot := int(node.get("player_index"))
		if slot < best_slot:
			best_slot = slot
			best = node
	_recipient = best
	return best


## Kills the looping Legendary shimmers. They set_loops() and ignore time
## scale on an ALWAYS layer, so one left running keeps writing
## self_modulate on a hidden Button for the rest of the run.
func _kill_shines() -> void:
	for tween: Tween in _shine_tweens:
		if tween.is_valid():
			tween.kill()
	_shine_tweens.clear()


## Folds the picker away without touching the pause or the mouse: for the
## case where the run ended under it and another layer already owns both.
func _cancel_pick() -> void:
	_opening = false
	_picking = false
	_pending_levels = 0
	_pending_bonus.clear()
	_kill_shines()
	visible = false


func _close() -> void:
	visible = false
	_kill_shines()
	# Leave no stale motion for the next open (deal re-seeds everything).
	for card: Button in _cards:
		card.scale = Vector2.ONE
		card.modulate = Color.WHITE
		card.self_modulate = Color.WHITE
	# Only ever release the pause THIS layer took (the pause_menu.gd
	# contract). If the run ended under the picker, or another blocking
	# layer is up, unpausing here would resume the world behind the
	# run-end screen and steal the mouse back from its buttons.
	if not RunState.run_active or _other_blocking_ui_open():
		return
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## Any OTHER member of "ui_blocking" holding the pause right now?
func _other_blocking_ui_open() -> bool:
	for node: Node in get_tree().get_nodes_in_group("ui_blocking"):
		if node == self or not node.has_method(&"is_blocking"):
			continue
		if node.call(&"is_blocking") == true:
			return true
	return false
