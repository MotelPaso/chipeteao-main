class_name Vendor
extends Interactable
## Un vendedor de objetos repartido por el mapa desde el inicio de la etapa
## (StageFixtures). Su estante (item_offers objetos, cada uno con su rareza
## tirada con la suerte de quien lo abre primero) se sortea UNA vez y se
## queda. Cada objeto vale el precio ACTUAL del cofre por el factor de su
## rareza (item_price_factors) y por RunState.vendor_price_multiplier: abrir
## cofres encarece los puestos, y cada compra encarece todos los puestos del
## mapa (no los cofres). Se va cuando vende todo.
##
## El puesto es dueño de la ECONOMÍA: qué hay en el estante y a qué precio
## (roll_offers), qué se cobra y qué se entrega (buy), el registro y la regla de
## una sola venta. VendorUi (VendorPanel.tscn) solo dibuja las ofertas y le
## devuelve la elegida.
##
## Se queda hasta vender todo: un vendedor que se fuera por tiempo sería una
## caminata larga que el grupo puede perder por llegar tarde.

## Tipos de puesto, edita aquí. Campos de fila: id (identificador, también
## `kind`), display_name y prompt (texto del jugador), color (baliza, figura,
## toldo, luz, acento del panel y marcador). Un tipo nuevo es una fila aquí,
## una rama en roll_offers() y otra en buy(), nunca un caso especial por id en
## otro lado. Hoy solo hay vendedor de objetos.
const VENDOR_LIBRARY: Array[Dictionary] = [
	{
		"id": "items", "display_name": "Vendedor de objetos",
		"prompt": "[E] Ver la mercancía",
		"color": Color(1.0, 0.82, 0.35),
	},
]

## Ids de fila de VENDOR_LIBRARY con rama propia en roll_offers() y buy().
const KIND_ITEMS: String = "items"

## El menú que abre el puesto (VendorUi). Se carga al abrirlo: vendor_ui.gd usa
## Vendor y un preload aquí cerraría un ciclo de carga.
const VENDOR_PANEL_PATH: String = "res://scenes/ui/modal/VendorPanel.tscn"

## Qué puesto es (id de fila de VENDOR_LIBRARY); lo fija el WorldDirector antes
## de que entre al árbol.
@export var kind: String = "items"

@export_group("Precios")
## Precio de cada objeto como múltiplo del precio actual del cofre, según su rareza (clave: id de rareza en inglés). Elegir el objeto cuesta más que la sorpresa del cofre.
@export var item_price_factors: Dictionary[String, float] = {
	"Common": 1.2, "Rare": 2.5, "Epic": 5.0, "Legendary": 9.0,
}

@export_group("Estante")
## Objetos que ofrece el vendedor, cada uno con su rareza sorteada.
@export var item_offers: int = 4
## Re-tiradas cuando un objeto cae en un hueco que ya lo tiene: el mismo nombre
## dos veces con dos precios parece un bug. Es acotado porque una rareza puede
## tener menos objetos que huecos el estante (Legendario tiene dos).
@export var item_rerolls: int = 4

@export_group("Espera")
## Segundos que el puesto ignora `interact` tras cerrarse un menú sin venta. El
## soak vuelve a interactuar cada 0.75 s mientras se queda cerca, y sin esto el
## panel se reabriría apenas se cierra, para siempre.
@export var retry_cooldown: float = 20.0

@export_group("Toldo")
## Metros que sube y baja el toldo mientras el puesto atiende.
@export var sign_bob_height: float = 0.04
## Velocidad del vaivén del toldo, en radianes por segundo.
@export var sign_bob_speed: float = 1.6

@export_group("Textos")
## Línea que se muestra EN LUGAR de la del puesto mientras corre la espera; %d
## son los segundos que faltan. Sin el prefijo "[E] " de los demás prompts: el
## token promete un botón que hace algo, y durante la espera no hay nada que
## presionar, así que se lee como un estado.
@export var cooldown_prompt_template: String = "Atiende de nuevo en %d s"
## Prompt para una fila que no trae uno (un `kind` mal escrito).
@export var default_prompt: String = "[E] Comerciar"
## Aviso del HUD cuando el puesto se va tras vender todo.
@export var leave_announcement: String = "El vendedor recoge el puesto."

@onready var _figure: MeshInstance3D = $Figure
@onready var _sign: MeshInstance3D = $Sign
@onready var _light: OmniLight3D = $Light

## El estante, sorteado al abrirlo la primera vez; cada oferta vendida lleva "sold".
var _shelf: Array[Dictionary] = []
var _rolled: bool = false
## True cuando ya no queda nada que vender.
var _sold: bool = false
var _cooldown_left: float = 0.0
var _ui: VendorUi = null
var _time: float = 0.0
## Altura de reposo del toldo (la de Vendor.tscn); el vaivén oscila alrededor.
var _sign_rest_y: float = 0.0


func _ready() -> void:
	super()
	# NO en el grupo "altars": el WorldDirector cuenta ese grupo para su tope de
	# altares, y un puesto parado ahí dejaría a la partida sin altares.
	add_to_group(&"vendors")
	set_prompt(_row_prompt())
	_sign_rest_y = _sign.position.y
	_apply_tint()


func _physics_process(delta: float) -> void:
	_time += delta
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(_cooldown_left - delta, 0.0)
		_refresh_cooldown_prompt()
	if available:
		_sign.position.y = _sign_rest_y + sin(_time * sign_bob_speed) * sign_bob_height


## La fila de VENDOR_LIBRARY de este puesto (la primera si `kind` es
## desconocido, así un export mal escrito igual dibuja algo en vez de romperse).
func row() -> Dictionary:
	for entry: Dictionary in VENDOR_LIBRARY:
		if String(entry.id) == kind:
			return entry
	push_warning("Vendor: unknown kind '%s'" % kind)
	return VENDOR_LIBRARY[0]


## El estante del puesto, sorteado UNA vez (con la suerte de quien lo abre
## primero) y guardado: el panel se redibuja tras cada clic y cada compra, y
## un estante rearmado ahí cambiaría la mercancía bajo el cursor. Cada oferta
## es una fila lista para mostrar Y el argumento que consume buy(): kind,
## price, title, tag, lines, color, item_id y, si ya se vendió, sold.
func roll_offers(player: Node) -> Array[Dictionary]:
	if not _rolled:
		_rolled = true
		match kind:
			KIND_ITEMS:
				_shelf = _item_offers(player)
			_:
				push_warning("VendorUi: unknown vendor kind '%s'" % kind)
	refresh_prices()
	return _shelf


## Recalcula el precio de lo que queda con el precio actual del cofre: otra
## compra (aquí, en otro puesto o un cofre) o la lluvia dorada lo cambian.
func refresh_prices() -> void:
	for offer: Dictionary in _shelf:
		if not bool(offer.get("sold", false)):
			offer["price"] = item_price(String(offer.get("rarity", "Common")))


## Lo que cuesta ahora un objeto de `rarity_name` en este puesto.
func item_price(rarity_name: String) -> int:
	var factor := float(item_price_factors.get(rarity_name, item_price_factors.get("Common", 1.0)))
	return ceili(float(RunState.chest_price()) * factor * RunState.vendor_price_multiplier)


## LA compra. Cobra, entrega, registra, encarece lo que queda y, si ya no
## queda nada, cierra el puesto. Devuelve false si la oferta ya se vendió o
## si el raider no puede pagar, y eso es lo que deja al panel seguir abierto y
## decirlo.
func buy(offer: Dictionary, player: Node) -> bool:
	if _sold or bool(offer.get("sold", false)):
		return false
	var price := int(offer.get("price", 0))
	if not player.has_method("spend_points") or not bool(player.call("spend_points", price)):
		return false
	offer["sold"] = true
	# Registro de una línea (convención de RunManager), impreso ANTES de la
	# entrega para que el soak lea causa y después efecto: esta línea, y luego lo
	# lo que la entrega anuncie.
	print("Vendor sold: %s %s %d" % [kind, _payload_id(offer), price])
	# Línea aparte, nunca un campo de la de arriba: "Vendor sold:" es la interfaz
	# de verificación de tres soaks y su forma está congelada. QUÉ raider pagó
	# solo importa en co-op, y solo un soak co-op puede probar que la entrega cae
	# en el comprador y no en la ranura 0.
	var buyer: Variant = player.get("player_index")
	print("Vendor buyer: p%d" % (int(buyer) if buyer != null else -1))
	match String(offer.get("kind", "")):
		KIND_ITEMS:
			var bag := ItemBag.find_in(player)
			if bag != null:
				bag.add_item(String(offer.get("item_id", "")))
			# Encarece todos los puestos, no los cofres.
			RunState.register_vendor_sale()
	refresh_prices()
	var left := 0
	for other: Dictionary in _shelf:
		if not bool(other.get("sold", false)):
			left += 1
	if left == 0:
		_sold = true
		consume()
		_emit_completed()
		_leave()
	return true


## True si el puesto ya vendió todo (el panel lo usa para cerrarse).
func sold_out() -> bool:
	return _sold


## El color propio del puesto en el mapa, para distinguir los tres UNA VEZ
## encontrados. El marcador se oculta tras la niebla como todo POI, así que
## nunca revela qué vendedor llegó antes de que alguien camine hasta allá.
func map_marker_color() -> Color:
	return row().get("color", Color.WHITE)


## Pinta la figura, el toldo y la luz con el color de la fila del puesto: lo
## único que insinúa el tipo antes de leer el prompt. Los materiales de la
## figura y el toldo son locales a cada puesto (resource_local_to_scene), así
## dos puestos de distinto tipo no se pintan entre sí.
func _apply_tint() -> void:
	var tint: Color = row().get("color", Color.WHITE)
	for mesh: MeshInstance3D in [_figure, _sign]:
		var material := mesh.material_override as StandardMaterial3D
		material.albedo_color = tint
		material.emission = tint
	_light.light_color = tint


## La línea propia del puesto, de su fila de VENDOR_LIBRARY.
func _row_prompt() -> String:
	return String(row().get("prompt", default_prompt))


## Cuenta la espera en el prompt y devuelve la línea propia del puesto apenas
## termina: un puesto que ofrece la mercancía mientras rechaza cada clic miente
## (el cofre y la ruleta también cambian su línea cuando dicen que no). No
## depende del rango a propósito: la espera puede terminar sin nadie mirando y la
## línea igual tiene que volver.
func _refresh_cooldown_prompt() -> void:
	var line: String = _row_prompt() if _cooldown_left <= 0.0 \
			else cooldown_prompt_template % ceili(_cooldown_left)
	# Solo ante un cambio real: set_prompt reescribe el Label3D (que rearma su
	# malla de texto), y esta línea cambia una vez por segundo, no por frame.
	if line == prompt_text:
		return
	set_prompt(line)


func _interact(player: Node) -> void:
	if _sold or not available or _cooldown_left > 0.0:
		return
	if _ui != null and is_instance_valid(_ui):
		return
	# Nunca abre un menú que pausa el árbol SOBRE otro: el panel de este puesto
	# suelta la pausa al cerrarse, y esa pausa podría ser del selector de cartas.
	# El soak cuelga toda la partida de un nodo que procesa siempre, así que
	# Interactable._unhandled_input sigue disparando en pausa y el probe presiona
	# interact cada 0.75 s mientras se queda cerca.
	if BlockingUi.any_open(get_tree()):
		return
	var offers := roll_offers(player)
	var ui := (load(VENDOR_PANEL_PATH) as PackedScene).instantiate() as VendorUi
	ui.setup(self, player, offers)
	# Cuelga de la etapa como todo lo que aparece, así un cambio de etapa se
	# lleva el panel junto con el puesto en vez de dejar un árbol pausado.
	RunRoot.stage_parent(get_tree()).add_child(ui)
	_ui = ui
	ui.tree_exited.connect(_on_menu_closed)


## El menú se fue. Si queda mercancía el puesto sigue, pero se calla un rato:
## si no, el interact repetido del soak lo reabriría en el frame siguiente.
func _on_menu_closed() -> void:
	_ui = null
	if not _sold:
		_cooldown_left = retry_cooldown
		# Se dice de inmediato, no en el próximo tick de física: el raider está
		# parado en el anillo justo cuando el panel se cierra, leyéndolo.
		_refresh_cooldown_prompt()


## Objetos, cada uno con su propia tirada de rareza inclinada por la suerte del
## comprador; su precio lo pone refresh_prices().
func _item_offers(player: Node) -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	var luck := _buyer_luck(player)
	var taken := PackedStringArray()
	for _slot in item_offers:
		var rarity := UpgradePool.roll_rarity(luck, 0)
		var rarity_name := String(rarity.name)
		var item_id := _roll_unused_item(rarity_name, taken)
		if item_id.is_empty():
			continue
		taken.append(item_id)
		var item := ItemCatalog.by_id(item_id)
		offers.append({
			"kind": KIND_ITEMS,
			"item_id": item_id,
			"rarity": rarity_name,
			"price": item_price(rarity_name),
			"title": String(item.display_name),
			"tag": UpgradePool.rarity_display(rarity_name),
			"lines": PackedStringArray([String(item.get("description", ""))]),
			"color": ItemCatalog.rarity_color(rarity_name),
		})
	return offers


## Un objeto de `rarity_name` que todavía no está en el estante. Los reintentos
## son acotados (item_rerolls), y un hueco vacío es peor que uno repetido.
func _roll_unused_item(rarity_name: String, taken: PackedStringArray) -> String:
	var item_id := ItemCatalog.roll_id(rarity_name)
	var tries := 0
	while tries < item_rerolls and taken.has(item_id):
		item_id = ItemCatalog.roll_id(rarity_name)
		tries += 1
	return item_id


static func _buyer_luck(player: Node) -> float:
	var stats := PlayerStats.find_in(player)
	return stats.luck if stats != null else 0.0


## Lo que la oferta entregó de verdad, para el registro.
static func _payload_id(offer: Dictionary) -> String:
	for key: String in ["item_id"]:
		var value: Variant = offer.get(key)
		if value != null and not String(value).is_empty():
			return String(value)
	return "?"


func _leave() -> void:
	get_tree().call_group("hud", "announce", leave_announcement)
	# Se encoge sin bajar: sink_duration en Vendor.tscn; sink_end_scale es el de interactable.gd.
	sink_away()
