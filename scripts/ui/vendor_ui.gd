extends CanvasLayer
## Vendor menu (iteration 54), built in code by a Vendor: pauses the tree
## (ui_blocking contract, the roulette's layer), lays the stall's goods out
## as cards, and hands ONE purchase back to the vendor. The vendor owns the
## economy — it charges, it logs, and it decides that a stall closes after
## a sale; this layer owns the moment: what is on the shelf, what a card
## says, and what happens between the press and the goodbye.
##
## What the shelf holds comes from the vendor's `kind`, one branch each:
##   "animals"  — three companions the buyer is not already following, at
##                the vendor's flat pet_price.
##   "powerups" — one rolled power-up, never the star, at the run-wide
##                RunState.powerup_vendor_price.
##   "items"    — four items, each at its own luck-rolled rarity and priced
##                like a chest of that rarity, inflation included.
## Every offer is a display-ready row AND the argument vendor.buy()
## consumes: kind, price, title, tag, lines, color, plus the payload
## (pet_id / powerup_id / item_id).
##
## The offers are rolled ONCE, in _ready: the panel redraws after every
## press and after every purse change, and a shelf rebuilt in the redraw
## would swap the goods out from under the raider's cursor.
##
## Pause safety: this layer holds the whole tree paused, so it must never
## be able to outlive its owner. It closes itself if the raider that opened
## it — or the stall itself, on a stage teardown — goes away, exposes
## dismiss() for anything that needs to shut it down programmatically
## (group "blocking_ui_closable"), and on a headless display it plays
## itself: a soak has nobody to press a card, and a stall waiting forever
## freezes the whole run.

## Vendor kinds (VENDOR_LIBRARY row ids). Identifiers, never shown.
const KIND_ANIMALS: String = "animals"
const KIND_POWERUPS: String = "powerups"
const KIND_ITEMS: String = "items"

## How many cards each kind puts out. Animals and items are a CHOICE (pick
## one of several); the power-up is a single take-it-or-leave-it card,
## because its price is the run-wide one that grows with every power-up
## anybody buys — offering three would just be the same price three times.
const PET_OFFERS: int = 3
const ITEM_OFFERS: int = 4
## Re-rolls allowed when an item lands on a slot that already holds it: the
## same name twice at two prices reads as a bug. Bounded, because a tier can
## hold fewer items than the shelf has slots (Legendary has two).
const ITEM_REROLLS: int = 4

const DIM_COLOR: Color = Color(0.03, 0.03, 0.05, 0.75)
const CARD_SIZE: Vector2 = Vector2(196.0, 196.0)
const CLOSE_BUTTON_SIZE: Vector2 = Vector2(140.0, 46.0)

## Headless self-play: buy the first affordable card, then leave.
const HEADLESS_BUY_DELAY: float = 0.4
const HEADLESS_LEAVE_DELAY: float = 3.0
## Beat between the thank-you line and the panel closing itself.
const SOLD_CLOSE_DELAY: float = 1.1

## Every player-visible string of the stall, in one block (docs/GLOSARIO.md).
const POINTS_TEMPLATE: String = "Tienes %d pts"
const PRICE_TEMPLATE: String = "%d pts"
const DURATION_TEMPLATE: String = "%d s"
const HINT_LINE: String = "Elige lo que te llevas."
const BROKE_LINE: String = "No te alcanzan los puntos."
const SOLD_TEMPLATE: String = "¡Trato hecho! %s"
const EMPTY_SHELF_LINE: String = "El vendedor no tiene nada para ti."

var _vendor: Vendor = null
var _player: Node = null
## Rolled once in _ready; the drawing code only ever reads them.
var _offers: Array[Dictionary] = []
var _cards: Array[Button] = []
var _price_labels: Array[Label] = []
var _points_label: Label = null
var _result_label: Label = null
var _close_button: Button = null
## One sale per stall: set the moment the vendor accepts, and every card
## goes dead with it.
var _sold: bool = false


## MUST be called before add_child(): _ready rolls the shelf from the
## vendor's kind and the raider's luck, and prices it against their points.
func setup(vendor: Vendor, player: Node) -> void:
	_vendor = vendor
	_player = player


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Nothing to watch — and no pause of ours to release — until the panel
	# is actually up.
	set_process(false)
	if not is_instance_valid(_vendor) or not is_instance_valid(_player):
		push_error("VendorUi: setup() must run before add_child()")
		queue_free()
		return
	add_to_group("ui_blocking")
	add_to_group("blocking_ui_closable")
	_offers = _build_offers()
	_build()
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	set_process(true)
	if DisplayServer.get_name() == "headless":
		_auto_play()


func is_blocking() -> bool:
	return true


## Programmatic close (soak harnesses, teardown). Nothing here is worth
## waiting for: the sale, if there was one, already happened.
func dismiss() -> void:
	_close()


## The tree is paused, so nothing else can notice that the raider who
## walked up to the stall is gone (co-op wipe, scene teardown) — or that
## the stall itself went with the stage. Nobody would be left to press
## Salir, and the pause would outlive the run.
func _process(_delta: float) -> void:
	if is_queued_for_deletion():
		return
	if not is_instance_valid(_player) or not is_instance_valid(_vendor):
		_close()


# --- shelf -----------------------------------------------------------------

## One branch per vendor kind, and nothing per id: a fourth kind is a row
## in VENDOR_LIBRARY, a branch here and a branch in Vendor.buy().
func _build_offers() -> Array[Dictionary]:
	match _vendor.kind:
		KIND_ANIMALS:
			return _animal_offers()
		KIND_POWERUPS:
			return _powerup_offers()
		KIND_ITEMS:
			return _item_offers()
	push_warning("VendorUi: unknown vendor kind '%s'" % _vendor.kind)
	return []


## Three companions the buyer is not already following. Selling the pet
## somebody already has would charge them 120 points to swap it for itself.
func _animal_offers() -> Array[Dictionary]:
	var current: Variant = _player.get("pet_id")
	var held := String(current) if current != null else ""
	var rows: Array[Dictionary] = []
	for row: Dictionary in PetCatalog.PET_LIBRARY:
		if String(row.id) != held:
			rows.append(row)
	rows.shuffle()
	var offers: Array[Dictionary] = []
	for i in mini(PET_OFFERS, rows.size()):
		var row: Dictionary = rows[i]
		offers.append({
			"kind": KIND_ANIMALS,
			"pet_id": String(row.id),
			"price": _vendor.pet_price,
			"title": String(row.display_name),
			# Weapon and stat are the only things that differ between
			# companions, so both go on every card: a swap the player
			# cannot undo must never be a guess.
			"tag": PetCatalog.weapon_display_name(row),
			"lines": PackedStringArray([String(row.get("stat_label", ""))]),
			"color": row.get("color", UiTheme.TEXT_BRIGHT),
		})
	return offers


## One power-up, never the star: that one is found roaming the map, which
## is why PowerUpCatalog.roll_id excludes it for every other source too.
func _powerup_offers() -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	var powerup_id := PowerUpCatalog.roll_id(true)
	if powerup_id.is_empty():
		return offers
	var row := PowerUpCatalog.by_id(powerup_id)
	offers.append({
		"kind": KIND_POWERUPS,
		"powerup_id": powerup_id,
		# Read here and not cached: the price grows with every power-up
		# bought anywhere this run, so the card quotes what the last buyer
		# left behind.
		"price": RunState.powerup_vendor_price,
		"title": String(row.display_name),
		# The catalog duration, before the buyer's own duration stat
		# stretches it — the stall sells the row, not the raider's build.
		"tag": DURATION_TEMPLATE % int(row.get("duration", 0.0)),
		"lines": PackedStringArray([String(row.get("description", ""))]),
		"color": row.get("color", UiTheme.TEXT_BRIGHT),
	})
	return offers


## Four items, each on its own luck-tilted rarity roll. An item bought off
## a shelf and an item bought out of a lockbox are the same purchase, so
## one curve prices both — chest inflation included.
func _item_offers() -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	var luck := _buyer_luck()
	var taken := PackedStringArray()
	for _slot in ITEM_OFFERS:
		var rarity := UpgradePool.roll_rarity(luck, 0)
		var rarity_name := String(rarity.name)
		var item_id := _roll_unused_item(rarity_name, taken)
		if item_id.is_empty():
			continue
		taken.append(item_id)
		var row := ItemCatalog.by_id(item_id)
		offers.append({
			"kind": KIND_ITEMS,
			"item_id": item_id,
			"rarity": rarity_name,
			"price": RunState.chest_price(rarity_name),
			"title": String(row.display_name),
			"tag": UpgradePool.rarity_display(rarity_name),
			"lines": PackedStringArray([String(row.get("description", ""))]),
			"color": ItemCatalog.rarity_color(rarity_name),
		})
	return offers


## An item of `rarity_name` that is not on the shelf yet. The retries are
## bounded because a tier can hold fewer items than the shelf has slots
## (Legendary holds two), and a slot left empty is worse than a repeat.
static func _roll_unused_item(rarity_name: String, taken: PackedStringArray) -> String:
	var item_id := ItemCatalog.roll_id(rarity_name)
	var tries := 0
	while tries < ITEM_REROLLS and taken.has(item_id):
		item_id = ItemCatalog.roll_id(rarity_name)
		tries += 1
	return item_id


func _buyer_luck() -> float:
	var stats := PlayerStats.find_in(_player)
	return stats.luck if stats != null else 0.0


# --- panel -----------------------------------------------------------------

func _build() -> void:
	var row := _vendor.row()
	var accent: Color = row.get("color", UiTheme.ACCENT_AMBER)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = DIM_COLOR
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
			UiTheme.panel(UiTheme.PANEL_BG, accent, 32.0, 22.0))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	_build_header(box, String(row.display_name), accent)
	_build_cards(box)
	_build_result(box)
	_build_buttons(box)
	_refresh_points()
	_focus_first_offer()


func _build_header(box: VBoxContainer, title_text: String, accent: Color) -> void:
	var title := Label.new()
	title.text = title_text.to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_title(title, 34, accent, 6, 8)
	box.add_child(title)
	_points_label = Label.new()
	_points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_points_label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	box.add_child(_points_label)


func _build_cards(box: VBoxContainer) -> void:
	if _offers.is_empty():
		# Nothing to sell (every companion already followed, an empty
		# roster): say so, instead of drawing an empty row and letting the
		# raider wonder what broke.
		var empty := Label.new()
		empty.text = EMPTY_SHELF_LINE
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		box.add_child(empty)
		return
	var shelf := HBoxContainer.new()
	shelf.alignment = BoxContainer.ALIGNMENT_CENTER
	shelf.add_theme_constant_override("separation", 14)
	box.add_child(shelf)
	for i in _offers.size():
		shelf.add_child(_build_card(_offers[i], i))


## The card IS the buy button (the one "pick one of these" surface every
## other screen uses), so unaffordable and sold-out both read as the plain
## disabled state instead of a live-looking card that swallows the press.
func _build_card(offer: Dictionary, index: int) -> Button:
	var tint: Color = offer.color
	var card := Button.new()
	card.custom_minimum_size = CARD_SIZE
	UiTheme.style_card(card, tint)
	card.pressed.connect(_on_buy.bind(index))
	var box := CardFactory.card_box(card)
	var title := CardFactory.label(String(offer.title), 16, UiTheme.TEXT_BRIGHT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	var tag := String(offer.tag)
	if not tag.is_empty():
		var badge := CardFactory.label(tag, 12, tint.lightened(0.25))
		UiTheme.style_badge(badge, tint.lightened(0.25), UiTheme.PANEL_BG,
				Color(tint, 0.4))
		box.add_child(_centered(badge))
	for line: String in offer.lines as PackedStringArray:
		var body := CardFactory.label(line, 12, UiTheme.TEXT_DIM)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(body)
	# The price sits on the bottom edge of every card, however much or
	# little the body above it has to say.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)
	var price := CardFactory.label(PRICE_TEMPLATE % int(offer.price), 14,
			UiTheme.TEXT_BRIGHT)
	UiTheme.style_badge(price, UiTheme.TEXT_BRIGHT, UiTheme.CARD_BG_PRESSED,
			Color(tint, 0.55))
	box.add_child(_centered(price))
	_cards.append(card)
	_price_labels.append(price)
	return card


## Badges hug their text instead of stretching across the card. The wrapper
## is click-through: containers default to MOUSE_FILTER_STOP and would eat
## the press meant for the card underneath.
static func _centered(control: Control) -> CenterContainer:
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(control)
	return center


func _build_result(box: VBoxContainer) -> void:
	_result_label = Label.new()
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.custom_minimum_size = Vector2(0.0, 30.0)
	_result_label.add_theme_font_size_override("font_size", 20)
	_result_label.add_theme_color_override("font_color", UiTheme.TEXT_BRIGHT)
	_result_label.text = HINT_LINE if not _offers.is_empty() else ""
	box.add_child(_result_label)


func _build_buttons(box: VBoxContainer) -> void:
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)
	_close_button = Button.new()
	_close_button.text = "Salir"
	_close_button.custom_minimum_size = CLOSE_BUTTON_SIZE
	UiTheme.style_button(_close_button)
	_close_button.pressed.connect(_close)
	buttons.add_child(_close_button)


## With the tree paused and the mouse free, a pad or keyboard player still
## has to be able to answer this panel: something focusable, always.
func _focus_first_offer() -> void:
	for card: Button in _cards:
		if not card.disabled:
			card.grab_focus()
			return
	_close_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


# --- buying ----------------------------------------------------------------

## A card the raider cannot pay for stays greyed out: a button that looks
## pressable and silently swallows the press is worse than a dead one.
func _refresh_points() -> void:
	var purse := int(_player.get("points"))
	_points_label.text = POINTS_TEMPLATE % purse
	for i in _cards.size():
		var affordable := purse >= int(_offers[i].price)
		_cards[i].disabled = _sold or not affordable
		_price_labels[i].add_theme_color_override("font_color",
				UiTheme.TEXT_BRIGHT if affordable else UiTheme.ACCENT_RED)


func _on_buy(index: int) -> void:
	# The stall can be gone by the time a queued press is handled (a stage
	# teardown lands on the same frame): _process closes for that, but the
	# press must not reach a freed vendor on its way out.
	if _sold or not is_instance_valid(_vendor) or index >= _offers.size():
		return
	var offer := _offers[index]
	if not _vendor.buy(offer, _player):
		# The vendor owns the purse check, so a refusal only ever means one
		# thing. The stall stays open: there may be a cheaper card.
		_result_label.text = BROKE_LINE
		_result_label.add_theme_color_override("font_color", UiTheme.ACCENT_RED)
		Sfx.play(&"dodge")
		_refresh_points()
		return
	_finish_sale(offer)


## One sale per stall (the vendor's rule; this is its face): every card goes
## dead, the panel says thanks, and it hands the tree back a beat later.
func _finish_sale(offer: Dictionary) -> void:
	_sold = true
	_result_label.text = SOLD_TEMPLATE % String(offer.title)
	_result_label.add_theme_color_override("font_color", UiTheme.TEXT_BRIGHT)
	UiTheme.pop(_result_label, 1.3, 0.3)
	Sfx.play(&"card_pick")
	_refresh_points()
	_close_button.grab_focus()
	await get_tree().create_timer(SOLD_CLOSE_DELAY, true, false, true).timeout
	if is_inside_tree():
		_close()


## Soaks (and any other headless run) have no hands: take the first thing
## the purse covers and leave, so the paused tree is always handed back —
## including the run where nothing on the shelf is affordable.
func _auto_play() -> void:
	await get_tree().create_timer(HEADLESS_BUY_DELAY, true, false, true).timeout
	if not is_inside_tree():
		return
	var index := _first_affordable()
	if index >= 0:
		_on_buy(index)
	await get_tree().create_timer(HEADLESS_LEAVE_DELAY, true, false, true).timeout
	if is_inside_tree():
		_close()


func _first_affordable() -> int:
	var purse := int(_player.get("points"))
	for i in _offers.size():
		if purse >= int(_offers[i].price):
			return i
	return -1


## Guarded because two paths can reach it on a headless run — the sale's own
## goodbye and the leave backstop — and the tree pause must be released
## exactly once, by whichever gets here first.
func _close() -> void:
	if is_queued_for_deletion():
		return
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	queue_free()
