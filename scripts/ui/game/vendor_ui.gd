extends CanvasLayer
## Menú del vendedor, creado por un Vendor: pausa el árbol (contrato
## "ui_blocking", la misma capa que la ruleta), muestra la mercancía como cartas
## y le devuelve UNA compra al vendedor. El vendedor es dueño de la economía
## (cobra, registra y cierra el puesto tras una venta); esta capa es dueña del
## momento: qué hay en el estante, qué dice cada carta y qué pasa entre el clic y
## la despedida.
##
## Lo que hay en el estante depende del `kind` del vendedor, una rama por tipo:
##   "animals"  — tres mascotas que el comprador no lleva, al pet_price fijo del
##                vendedor.
##   "powerups" — un power-up sorteado, nunca la estrella, al precio de toda la
##                partida RunState.powerup_vendor_price.
##   "items"    — cuatro objetos, cada uno con su rareza sorteada con suerte y
##                con precio de cofre de esa rareza, inflación incluida.
## Cada oferta es una fila lista para mostrar Y el argumento que consume
## vendor.buy(): kind, price, title, tag, lines, color y la carga (pet_id /
## powerup_id / item_id).
##
## Las ofertas se sortean UNA vez, en _ready: el panel se redibuja tras cada
## clic y cada cambio de puntos, y un estante rearmado en el redibujo cambiaría
## la mercancía bajo el cursor del raider.
##
## Pausa segura: esta capa tiene todo el árbol pausado, así que nunca puede
## sobrevivir a su dueño. Se cierra sola si el raider que la abrió, o el puesto
## (al desmontar la etapa), desaparece; expone dismiss() para cerrarla desde
## código (grupo "blocking_ui_closable"); y sin pantalla (headless) juega sola,
## porque un soak no tiene quien presione una carta y un puesto esperando para
## siempre congela la partida. La pausa también se suelta desde _exit_tree, así
## que un panel liberado en vez de cerrado devuelve el árbol igual; y, como el
## selector de cartas, nunca suelta una pausa que tomó otra capa bloqueante.

## Tipos de vendedor (ids de fila de VENDOR_LIBRARY). Identificadores, nunca se
## muestran.
const KIND_ANIMALS: String = "animals"
const KIND_POWERUPS: String = "powerups"
const KIND_ITEMS: String = "items"

## Cuántas cartas pone cada tipo. Animales y objetos son una ELECCIÓN (elige
## una de varias); el power-up es una sola carta, porque su precio es el de la
## partida y sube con cada power-up que alguien compra: ofrecer tres sería el
## mismo precio tres veces.
const PET_OFFERS: int = 3
const ITEM_OFFERS: int = 4
## Re-tiradas permitidas cuando un objeto cae en un hueco que ya lo tiene: el
## mismo nombre dos veces con dos precios parece un bug. Es acotado porque una
## rareza puede tener menos objetos que huecos el estante (Legendario tiene dos).
const ITEM_REROLLS: int = 4

const DIM_COLOR: Color = Color(0.03, 0.03, 0.05, 0.75)
const CARD_SIZE: Vector2 = Vector2(196.0, 196.0)
const CLOSE_BUTTON_SIZE: Vector2 = Vector2(140.0, 46.0)

## Juego sin pantalla: compra la primera carta que alcance y se va (segundos).
const HEADLESS_BUY_DELAY: float = 0.4
const HEADLESS_LEAVE_DELAY: float = 3.0
## Segundos entre la línea de agradecimiento y el cierre del panel.
const SOLD_CLOSE_DELAY: float = 1.1

## Todos los textos que ve el jugador en el puesto, en un bloque
## (docs/GLOSARIO.md).
const POINTS_TEMPLATE: String = "Tienes %d pts"
const PRICE_TEMPLATE: String = "%d pts"
const DURATION_TEMPLATE: String = "%d s"
const HINT_LINE: String = "Elige lo que te llevas."
const BROKE_LINE: String = "No te alcanzan los puntos."
const SOLD_TEMPLATE: String = "¡Trato hecho! %s"
const EMPTY_SHELF_LINE: String = "El vendedor no tiene nada para ti."

var _vendor: Vendor = null
var _player: Node = null
## Se sortean una vez en _ready; el dibujo solo las lee.
var _offers: Array[Dictionary] = []
var _cards: Array[Button] = []
var _price_labels: Array[Label] = []
var _points_label: Label = null
var _result_label: Label = null
var _close_button: Button = null
## Una venta por puesto: se marca cuando el vendedor acepta, y todas las cartas
## quedan inactivas.
var _sold: bool = false
## true solo entre el _ready que pausó el árbol y la liberación que lo devuelve
## (la regla de _pause_owned de pause_menu.gd). El cierre y el respaldo de
## _exit_tree pasan por aquí, así que la pausa se suelta una sola vez y un panel
## que nunca llegó a pausar no suelta nada.
var _pause_held: bool = false


## DEBE llamarse antes de add_child(): _ready sortea el estante según el tipo
## del vendedor y la suerte del raider, y le pone precio contra sus puntos.
func setup(vendor: Vendor, player: Node) -> void:
	_vendor = vendor
	_player = player


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Nada que vigilar (ni pausa propia que soltar) hasta que el panel está
	# arriba.
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
	_pause_held = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	set_process(true)
	if DisplayServer.get_name() == "headless":
		_auto_play()


## Contrato de PauseMenu/UpgradeCardUi ("ui_blocking"): true mientras esta capa
## es dueña de la pausa. Es false apenas queda en cola para borrarse: el nodo
## sigue en el grupo hasta que la cola de borrado se vacía al final del frame, y
## un puesto que se va y contesta "sí" hace que el selector de cartas (o un
## cambio de etapa) se salte su propia quita de pausa en ese frame.
func is_blocking() -> bool:
	return not is_queued_for_deletion()


## Cierre desde código (harness de soak, desmontaje). Nada aquí vale la espera:
## la venta, si hubo, ya ocurrió.
func dismiss() -> void:
	_close()


## Con el árbol pausado nada más puede notar que el raider que se acercó al
## puesto ya no está (caída de todo el grupo en co-op, desmontaje de la escena),
## o que el puesto se fue con la etapa. No quedaría nadie para presionar Salir y
## la pausa duraría más que la partida.
func _process(_delta: float) -> void:
	if is_queued_for_deletion():
		return
	if not is_instance_valid(_player) or not is_instance_valid(_vendor):
		_close()


# --- estante -----------------------------------------------------------------

## Una rama por tipo de vendedor y nada por id: un cuarto tipo es una fila en
## VENDOR_LIBRARY, una rama aquí y otra en Vendor.buy().
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


## Tres mascotas que el comprador no lleva: venderle la que ya tiene le cobraría
## por cambiarla por sí misma.
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
			# El arma y la stat son lo único que cambia entre mascotas, así que
			# ambas van en cada carta: un cambio que no se puede deshacer nunca
			# debe ser una apuesta.
			"tag": PetCatalog.weapon_display_name(row),
			"lines": PackedStringArray([String(row.get("stat_label", ""))]),
			"color": row.get("color", UiTheme.TEXT_BRIGHT),
		})
	return offers


## Un power-up, nunca la estrella: esa se encuentra recorriendo el mapa, y por
## eso PowerUpCatalog.roll_id la excluye también para toda otra fuente.
func _powerup_offers() -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	var powerup_id := PowerUpCatalog.roll_id(true)
	if powerup_id.is_empty():
		return offers
	var row := PowerUpCatalog.by_id(powerup_id)
	offers.append({
		"kind": KIND_POWERUPS,
		"powerup_id": powerup_id,
		# Se lee aquí y no se guarda: el precio sube con cada power-up comprado
		# en cualquier puesto de la partida, así que la carta cotiza lo que dejó
		# el último comprador.
		"price": RunState.powerup_vendor_price,
		"title": String(row.display_name),
		# La duración del catálogo, antes de que la stat de duración del
		# comprador la estire: el puesto vende la fila, no el equipo del raider.
		"tag": DURATION_TEMPLATE % int(row.get("duration", 0.0)),
		"lines": PackedStringArray([String(row.get("description", ""))]),
		"color": row.get("color", UiTheme.TEXT_BRIGHT),
	})
	return offers


## Cuatro objetos, cada uno con su propia tirada de rareza inclinada por la
## suerte. Un objeto de un estante y uno de un cofre son la misma compra, así
## que una sola curva les pone precio a ambos, inflación de cofres incluida.
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


## Un objeto de `rarity_name` que todavía no está en el estante. Los reintentos
## son acotados porque una rareza puede tener menos objetos que huecos el
## estante (Legendario tiene dos), y un hueco vacío es peor que uno repetido.
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


# --- panel -------------------------------------------------------------------

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
		# Nada que vender (todas las mascotas ya acompañan al raider, catálogo
		# vacío): se dice, en vez de dibujar una fila vacía y dejar al raider
		# preguntándose qué se rompió.
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


## La carta ES el botón de compra (la misma superficie de "elige una de estas"
## que usan las demás pantallas), así que inalcanzable y vendida se ven como el
## estado deshabilitado normal en vez de una carta que parece viva y se traga el
## clic.
func _build_card(offer: Dictionary, index: int) -> Button:
	var tint: Color = offer.color
	var card := Button.new()
	card.custom_minimum_size = CARD_SIZE
	UiTheme.style_card(card, tint)
	card.pressed.connect(_on_buy.bind(index))
	# Al volver desde Salir se cae en la carta que el jugador dejó, no en la que
	# quede más cerca del centro del botón.
	card.focus_entered.connect(func() -> void:
		if _close_button != null:
			_close_button.focus_neighbor_top = _close_button.get_path_to(card))
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
	# El precio va pegado al borde inferior de cada carta, diga lo que diga el
	# cuerpo de arriba.
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


## Las insignias abrazan su texto en vez de estirarse a lo ancho de la carta. El
## envoltorio deja pasar el clic: los contenedores usan MOUSE_FILTER_STOP por
## defecto y se comerían el clic de la carta de abajo.
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
	# Indicaciones de botón bajo los botones; siguen al último dispositivo usado.
	box.add_child(InputHints.build([["ui_accept", "Comprar"], ["ui_cancel", "Salir"]]))


## Con el árbol pausado y el mouse libre, quien juega con control o teclado
## igual tiene que poder contestar este panel: siempre hay algo enfocable.
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


# --- compra ------------------------------------------------------------------

## Una carta que el raider no puede pagar queda en gris: un botón que parece
## presionable y se traga el clic en silencio es peor que uno muerto.
func _refresh_points() -> void:
	var purse := int(_player.get("points"))
	_points_label.text = POINTS_TEMPLATE % purse
	for i in _cards.size():
		var affordable := purse >= int(_offers[i].price)
		_cards[i].disabled = _sold or not affordable
		_price_labels[i].add_theme_color_override("font_color",
				UiTheme.TEXT_BRIGHT if affordable else UiTheme.ACCENT_RED)


func _on_buy(index: int) -> void:
	# El puesto (o el comprador) puede haberse ido cuando se procesa un clic en
	# cola (un desmontaje de etapa en el mismo frame, una caída en co-op que
	# libera al raider): _process cierra por eso, pero la entrada se procesa
	# ANTES que _process en el frame, así que el clic no debe llegar a un
	# vendedor o un raider liberados.
	if _sold or not is_instance_valid(_vendor) or not is_instance_valid(_player) \
			or index >= _offers.size():
		return
	var offer := _offers[index]
	if not _vendor.buy(offer, _player):
		# El vendedor es dueño de la comprobación de puntos, así que un rechazo
		# solo significa una cosa. El puesto sigue abierto: puede haber una carta
		# más barata.
		_result_label.text = BROKE_LINE
		_result_label.add_theme_color_override("font_color", UiTheme.ACCENT_RED)
		Sfx.play(&"dodge")
		_refresh_points()
		return
	_finish_sale(offer)


## Una venta por puesto (la regla del vendedor; esta es su cara): todas las
## cartas quedan inactivas, el panel agradece y devuelve el árbol un momento
## después.
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


## Los soaks (y toda corrida sin pantalla) no tienen manos: compra lo primero
## que alcance y se va, así el árbol pausado siempre se devuelve, también cuando
## nada del estante alcanza.
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
	# Se llega después del await de _auto_play, así que el raider contra el que
	# cotiza pudo liberarse entretanto: a un comprador muerto nada le alcanza.
	if not is_instance_valid(_player):
		return -1
	var purse := int(_player.get("points"))
	for i in _offers.size():
		if purse >= int(_offers[i].price):
			return i
	return -1


## Protegido porque en una corrida sin pantalla dos caminos pueden llegar aquí
## (la despedida de la venta y el respaldo de salida) y la pausa debe soltarse
## una sola vez, por el primero que llegue.
func _close() -> void:
	if is_queued_for_deletion():
		return
	_release_pause()
	queue_free()


## Devuelve el árbol como máximo una vez, y solo si la pausa es NUESTRA (regla
## de upgrade_card_ui.gd). Una compra puede poner otra capa "ui_blocking" en
## pantalla, y la partida puede terminar debajo de este panel, en cuyo caso la
## pantalla de fin es dueña de la pausa y del mouse: quitar la pausa en
## cualquiera de los dos casos reanudaría el mundo detrás del modal de otro y le
## quitaría el mouse a sus botones.
func _release_pause() -> void:
	if not _pause_held:
		return
	_pause_held = false
	if not RunState.run_active or _other_blocking_ui_open():
		return
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## ¿Algún OTRO miembro de "ui_blocking" tiene la pausa ahora?
func _other_blocking_ui_open() -> bool:
	for node: Node in get_tree().get_nodes_in_group("ui_blocking"):
		if node == self or not node.has_method(&"is_blocking"):
			continue
		if node.call(&"is_blocking") == true:
			return true
	return false


## _close() es el único camino que quita la pausa, así que un panel LIBERADO en
## vez de cerrado (free() desde un harness, el padre de la etapa que se va con
## un cambio de etapa) dejaría un árbol pausado sin nada en pantalla que lo
## suelte.
func _exit_tree() -> void:
	_release_pause()
