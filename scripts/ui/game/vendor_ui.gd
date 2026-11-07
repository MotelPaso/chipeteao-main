class_name VendorUi
extends ModalPanel
## Tienda del vendedor (VendorPanel.tscn), abierta por un Vendor con el estante
## ya sorteado (Vendor.roll_offers). Dibuja las ofertas como cartas y le devuelve
## UNA compra al puesto, que es dueño de la economía: cobra, registra y cierra el
## puesto tras la venta. La pausa, el cierre y el juego sin pantalla los maneja
## ModalPanel; sin pantalla compra la primera carta que alcance.

@export_group("Cartas")
## Tamaño de cada carta del estante, en píxeles.
@export var card_size: Vector2 = Vector2(196.0, 196.0)
## Tamaño de letra del nombre en la carta.
@export var card_title_font_size: int = 16
## Tamaño de letra de la etiqueta y de las líneas de la carta.
@export var card_text_font_size: int = 12
## Tamaño de letra del precio en la carta.
@export var card_price_font_size: int = 14
## Cuánto se aclara el color de la carta en su etiqueta (0-1).
@export var tag_lighten: float = 0.25
## Opacidad del borde de la etiqueta (0-1).
@export var tag_border_alpha: float = 0.4
## Opacidad del borde del precio (0-1).
@export var price_border_alpha: float = 0.55

@export_group("Venta")
## Segundos entre la línea de agradecimiento y el cierre del panel.
@export var sold_close_delay: float = 1.1
## Escala del golpe de la línea de agradecimiento.
@export var sold_pop_scale: float = 1.3
## Segundos del golpe de la línea de agradecimiento.
@export var sold_pop_time: float = 0.3

@export_group("Textos")
## Línea bajo el estante mientras no hay compra.
@export var hint_line: String = "Elige lo que te llevas."
## Línea cuando el raider no alcanza a pagar la carta que eligió.
@export var broke_line: String = "No te alcanzan los puntos."
## Línea tras la venta; %s es el nombre de lo comprado.
@export var sold_template: String = "¡Trato hecho! %s"
## Precio en cada carta; %d son los puntos.
@export var price_template: String = "%d pts"
## Línea en lugar del estante cuando no hay nada que vender.
@export var empty_shelf_line: String = "El vendedor no tiene nada para ti."
## Indicación del botón de aceptar.
@export var buy_hint_text: String = "Comprar"

@onready var _shelf: HBoxContainer = %Shelf
@onready var _empty_label: Label = %EmptyLabel

var _vendor: Vendor = null
## Las ofertas del puesto; el panel solo las lee.
var _offers: Array[Dictionary] = []
var _cards: Array[Button] = []
var _price_labels: Array[Label] = []
## Una venta por puesto: se marca cuando el vendedor acepta, y todas las cartas
## quedan inactivas.
var _sold: bool = false


## DEBE llamarse antes de add_child(): el puesto, el raider que compra y el
## estante que el puesto ya sorteó para él.
func setup(vendor: Vendor, player: Node, offers: Array[Dictionary]) -> void:
	_vendor = vendor
	_offers = offers
	_bind(vendor, player)


func _build() -> void:
	var row := _vendor.row()
	var accent: Color = row.get("color", UiTheme.ACCENT_AMBER)
	_style_frame(String(row.display_name).to_upper(), accent)
	if _offers.is_empty():
		# Nada que vender (todas las mascotas ya acompañan al raider, catálogo
		# vacío): se dice, en vez de dibujar una fila vacía y dejar al raider
		# preguntándose qué se rompió.
		_shelf.visible = false
		_empty_label.text = empty_shelf_line
		_empty_label.visible = true
	for i in _offers.size():
		_shelf.add_child(_build_card(_offers[i], i))
	_result.text = hint_line if not _offers.is_empty() else ""
	_refresh_points()
	_focus_first_offer()


func _play_headless() -> void:
	var index := _first_affordable()
	if index >= 0:
		_on_buy(index)


func _accept_hint() -> String:
	return buy_hint_text


func _log_tag() -> String:
	return "VendorUi"


## La carta ES el botón de compra (la misma superficie de "elige una de estas"
## que usan las demás pantallas), así que inalcanzable y vendida se ven como el
## estado deshabilitado normal en vez de una carta que parece viva y se traga el
## clic.
func _build_card(offer: Dictionary, index: int) -> Button:
	var tint: Color = offer.color
	var card := Button.new()
	card.custom_minimum_size = card_size
	UiTheme.style_card(card, tint)
	card.pressed.connect(_on_buy.bind(index))
	# Al volver desde Salir se cae en la carta que el jugador dejó, no en la que
	# quede más cerca del centro del botón.
	card.focus_entered.connect(func() -> void:
		_close_button.focus_neighbor_top = _close_button.get_path_to(card))
	var box := CardFactory.card_box(card)
	var title := CardFactory.label(String(offer.title), card_title_font_size,
			UiTheme.TEXT_BRIGHT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	var tag := String(offer.tag)
	if not tag.is_empty():
		var tag_color := tint.lightened(tag_lighten)
		var badge := CardFactory.label(tag, card_text_font_size, tag_color)
		UiTheme.style_badge(badge, tag_color, UiTheme.PANEL_BG, Color(tint, tag_border_alpha))
		box.add_child(_centered(badge))
	for line: String in offer.lines as PackedStringArray:
		var body := CardFactory.label(line, card_text_font_size, UiTheme.TEXT_DIM)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(body)
	# El precio va pegado al borde inferior de cada carta, diga lo que diga el
	# cuerpo de arriba.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)
	var price := CardFactory.label(price_template % int(offer.price), card_price_font_size,
			UiTheme.TEXT_BRIGHT)
	UiTheme.style_badge(price, UiTheme.TEXT_BRIGHT, UiTheme.CARD_BG_PRESSED,
			Color(tint, price_border_alpha))
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


## Con el árbol pausado y el mouse libre, quien juega con control o teclado
## igual tiene que poder contestar este panel: siempre hay algo enfocable.
func _focus_first_offer() -> void:
	for card: Button in _cards:
		if not card.disabled:
			card.grab_focus()
			return
	_close_button.grab_focus()


## Una carta que el raider no puede pagar queda en gris: un botón que parece
## presionable y se traga el clic en silencio es peor que uno muerto.
func _refresh_points() -> void:
	var purse := _show_points()
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
		_result.text = broke_line
		_result.add_theme_color_override("font_color", UiTheme.ACCENT_RED)
		Sfx.play(&"dodge")
		_refresh_points()
		return
	_finish_sale(offer)


## Una venta por puesto (la regla del vendedor; esta es su cara): todas las
## cartas quedan inactivas, el panel agradece y devuelve el árbol un momento
## después.
func _finish_sale(offer: Dictionary) -> void:
	_sold = true
	_result.text = sold_template % String(offer.title)
	_result.add_theme_color_override("font_color", UiTheme.TEXT_BRIGHT)
	UiTheme.pop(_result, sold_pop_scale, sold_pop_time)
	Sfx.play(&"card_pick")
	_refresh_points()
	_close_button.grab_focus()
	await get_tree().create_timer(sold_close_delay, true, false, true).timeout
	if is_inside_tree():
		_close()


func _first_affordable() -> int:
	# Se llega después de una espera, así que el raider contra el que cotiza
	# pudo liberarse entretanto: a un comprador muerto nada le alcanza.
	if not is_instance_valid(_player):
		return -1
	var purse := int(_player.get("points"))
	for i in _offers.size():
		if purse >= int(_offers[i].price):
			return i
	return -1
