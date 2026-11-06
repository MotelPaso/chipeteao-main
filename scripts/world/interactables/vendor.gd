class_name Vendor
extends Interactable
## Un puesto que aparece a mitad de partida y se va tras UNA venta.
##
## Tres tipos, una tabla: el traficante de animales vende una elección de tres
## mascotas, el vendedor de power-ups vende un power-up sorteado a un precio que
## sube en toda la partida, y el vendedor de objetos vende cuatro objetos a
## precio de cofre. El WorldDirector sortea el tipo en secreto y solo anuncia
## que llega un vendedor: caminar hasta él para descubrir cuál es es la gracia,
## y una baliza que nombrara el tipo respondería la pregunta desde el otro lado
## del mapa.
##
## El puesto es dueño de la ECONOMÍA (qué se cobra, qué se entrega, el registro y
## la regla de una sola venta); VendorUi es dueño del momento (qué hay en el
## estante, qué dice una carta y qué pasa entre el clic y la despedida).
##
## Se queda hasta vender algo: un vendedor que se fuera por tiempo sería una
## caminata larga que el grupo puede perder por llegar tarde.

## Campos de fila: id (identificador, también `kind`), display_name y prompt
## (texto del jugador), color (baliza, acento del panel y marcador). Un cuarto
## tipo es una fila aquí más una rama en VendorUi._build_offers y otra en
## buy(), nunca un caso especial por id en otro lado.
const VENDOR_LIBRARY: Array[Dictionary] = [
	{
		"id": "animals", "display_name": "Traficante de animales",
		"prompt": "[E] Ver los animales",
		"color": Color(0.55, 0.9, 0.6),
	},
	{
		"id": "powerups", "display_name": "Vendedor de power-ups",
		"prompt": "[E] Ver el power-up",
		"color": Color(0.5, 0.8, 1.0),
	},
	{
		"id": "items", "display_name": "Vendedor de objetos",
		"prompt": "[E] Ver la mercancía",
		"color": Color(1.0, 0.82, 0.35),
	},
]

## Qué puesto es (id de fila de VENDOR_LIBRARY); lo fija el WorldDirector antes
## de que entre al árbol.
@export var kind: String = "items"
## Precio fijo de cualquier mascota en el traficante, en puntos. A propósito no
## es un precio de cofre: una mascota es un espacio, no una rareza, y ponerle
## precio por rareza daría a entender que una es la buena.
@export var pet_price: int = 120
## Segundos que el puesto ignora `interact` tras cerrarse un menú sin venta. El
## soak vuelve a interactuar cada 0.75 s mientras se queda cerca, y sin esto el
## panel se reabriría apenas se cierra, para siempre.
@export var retry_cooldown: float = 20.0
## Segundos que tarda el puesto en encogerse y desaparecer tras la venta.
@export var sink_time: float = 0.6

const VENDOR_UI_SCRIPT := preload("res://scripts/ui/game/vendor_ui.gd")

## Línea que se muestra EN LUGAR de la del puesto mientras corre la espera. Sin
## el prefijo "[E] " de los demás prompts: el token promete un botón que hace
## algo, y durante la espera no hay nada que presionar, así que se lee como un
## estado (como el cofre que cita un precio que no puedes pagar en vez de
## ofrecer abrirse).
const COOLDOWN_PROMPT_TEMPLATE: String = "Atiende de nuevo en %d s"
## Prompt para una fila que no tiene uno (un `kind` mal escrito).
const DEFAULT_PROMPT: String = "[E] Comerciar"

## El precio del power-up se multiplica por esto con cada compra, en toda la
## partida.
const POWERUP_PRICE_GROWTH: float = 1.5

var _sold: bool = false
var _cooldown_left: float = 0.0
var _ui: CanvasLayer = null
var _time: float = 0.0
var _sign: MeshInstance3D = null


func _init() -> void:
	marker_kind = &"vendor"
	prompt_height = 3.0
	meta_stat_id = ""
	collision_layer = 0
	collision_mask = 1


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 2.4
	cylinder.height = 3.5
	shape.shape = cylinder
	shape.position.y = 1.75
	add_child(shape)
	super()
	# NO en el grupo "altars": el WorldDirector cuenta ese grupo para su tope de
	# altares, y un puesto parado ahí dejaría a la partida sin altares.
	add_to_group(&"vendors")
	set_prompt(_row_prompt())
	_build_visual()


## La fila de VENDOR_LIBRARY de este puesto (la primera si `kind` es
## desconocido, así un export mal escrito igual dibuja algo en vez de romperse).
func row() -> Dictionary:
	for entry: Dictionary in VENDOR_LIBRARY:
		if String(entry.id) == kind:
			return entry
	push_warning("Vendor: unknown kind '%s'" % kind)
	return VENDOR_LIBRARY[0]


func _build_visual() -> void:
	var tint: Color = row().get("color", Color.WHITE)
	var stall := MeshInstance3D.new()
	var counter := BoxMesh.new()
	counter.size = Vector3(2.2, 1.0, 0.8)
	stall.mesh = counter
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.35, 0.26, 0.18)
	stall.material_override = wood
	stall.position.y = 0.5
	add_child(stall)
	# La figura detrás del mostrador: una cápsula del color del puesto, lo único
	# que insinúa el tipo antes del prompt.
	var figure := MeshInstance3D.new()
	var body := CapsuleMesh.new()
	body.radius = 0.35
	body.height = 1.5
	# Teselado explícito (el motor usa 64 lados por defecto); 8 anillos por defecto.
	body.radial_segments = 16
	body.rings = 8
	figure.mesh = body
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = tint
	cloth.emission_enabled = true
	cloth.emission = tint
	cloth.emission_energy_multiplier = 0.5
	figure.material_override = cloth
	figure.position = Vector3(0.0, 1.15, -0.7)
	add_child(figure)
	_sign = MeshInstance3D.new()
	var awning := BoxMesh.new()
	awning.size = Vector3(2.4, 0.12, 1.2)
	_sign.mesh = awning
	var awning_material := StandardMaterial3D.new()
	awning_material.albedo_color = tint
	awning_material.emission_enabled = true
	awning_material.emission = tint
	awning_material.emission_energy_multiplier = 1.1
	_sign.material_override = awning_material
	_sign.position.y = 2.2
	add_child(_sign)
	var light := OmniLight3D.new()
	light.light_color = tint
	light.light_energy = 1.5
	light.omni_range = 7.0
	light.position.y = 2.0
	add_child(light)


func _physics_process(delta: float) -> void:
	_time += delta
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(_cooldown_left - delta, 0.0)
		_refresh_cooldown_prompt()
	if _sign != null and available:
		_sign.position.y = 2.2 + sin(_time * 1.6) * 0.04


## La línea propia del puesto, de su fila de VENDOR_LIBRARY.
func _row_prompt() -> String:
	return String(row().get("prompt", DEFAULT_PROMPT))


## Cuenta la espera en el prompt y devuelve la línea propia del puesto apenas
## termina: un puesto que ofrece la mercancía mientras rechaza cada clic miente
## (el cofre y la ruleta también cambian su línea cuando dicen que no). No
## depende del rango a propósito: la espera puede terminar sin nadie mirando y la
## línea igual tiene que volver.
func _refresh_cooldown_prompt() -> void:
	var line: String = _row_prompt() if _cooldown_left <= 0.0 \
			else COOLDOWN_PROMPT_TEMPLATE % ceili(_cooldown_left)
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
	if _blocking_ui_open():
		return
	var ui := VENDOR_UI_SCRIPT.new() as CanvasLayer
	ui.call("setup", self, player)
	# Cuelga de la etapa como todo lo que aparece, así un cambio de etapa se
	# lleva el panel junto con el puesto en vez de dejar un árbol pausado.
	RunRoot.stage_parent(get_tree()).add_child(ui)
	_ui = ui
	ui.tree_exited.connect(_on_menu_closed)


## ¿Hay alguna capa "ui_blocking" arriba ahora? Mismo contrato (y misma forma)
## que pause_menu.gd: un miembro sin is_blocking() CUENTA como bloqueante; si
## alguien olvida el contrato, falla del lado SEGURO.
func _blocking_ui_open() -> bool:
	for node: Node in get_tree().get_nodes_in_group("ui_blocking"):
		if not node.has_method(&"is_blocking"):
			push_warning("ui_blocking member without is_blocking(): %s" % node.name)
			return true
		var blocking: Variant = node.call(&"is_blocking")
		if blocking == true:
			return true
	return false


## El menú se fue. Si no hubo compra el puesto sigue, pero se calla un rato: si
## no, el interact repetido del soak lo reabriría en el frame siguiente.
func _on_menu_closed() -> void:
	_ui = null
	if not _sold:
		_cooldown_left = retry_cooldown
		# Se dice de inmediato, no en el próximo tick de física: el raider está
		# parado en el anillo justo cuando el panel se cierra, leyéndolo.
		_refresh_cooldown_prompt()


## LA compra. Cobra, entrega, registra y cierra el puesto. Devuelve false SOLO
## si el raider no puede pagar, y eso es lo que deja al panel seguir abierto y
## decirlo.
func buy(offer: Dictionary, player: Node) -> bool:
	if _sold:
		return false
	var price := int(offer.get("price", 0))
	if not player.has_method("spend_points") or not bool(player.call("spend_points", price)):
		return false
	_sold = true
	# Registro de una línea (convención de RunManager), impreso ANTES de la
	# entrega para que el soak lea causa y después efecto: esta línea, y luego lo
	# que la entrega anuncie ("Pet joined:", "Power-up picked:").
	print("Vendor sold: %s %s %d" % [kind, _payload_id(offer), price])
	# Línea aparte, nunca un campo de la de arriba: "Vendor sold:" es la interfaz
	# de verificación de tres soaks y su forma está congelada. QUÉ raider pagó
	# solo importa en co-op, y solo un soak co-op puede probar que la entrega cae
	# en el comprador y no en la ranura 0.
	var buyer: Variant = player.get("player_index")
	print("Vendor buyer: p%d" % (int(buyer) if buyer != null else -1))
	match String(offer.get("kind", "")):
		"animals":
			if player.has_method("set_pet"):
				player.call("set_pet", String(offer.get("pet_id", "")))
		"powerups":
			var powerups := PowerUps.find_in(player)
			if powerups != null:
				powerups.apply(String(offer.get("powerup_id", "")))
			# Para toda la partida, y solo con una VENTA: un estante que alguien
			# miró y dejó no debe encarecer el siguiente.
			RunState.powerup_vendor_price = roundi(
					float(RunState.powerup_vendor_price) * POWERUP_PRICE_GROWTH)
		"items":
			var bag := ItemBag.find_in(player)
			if bag != null:
				bag.add_item(String(offer.get("item_id", "")))
			# El estante de objetos ES stock de cofre a precio de cofre, así que
			# suma al mismo contador de inflación: si no, un vendedor sería una
			# forma de comprar legendarios manteniendo baratos los cofres.
			RunState.register_chest_opened()
	consume()
	_emit_completed()
	_leave()
	return true


## El color propio del puesto en el mapa, para distinguir los tres UNA VEZ
## encontrados. El marcador se oculta tras la niebla como todo POI, así que
## nunca revela qué vendedor llegó antes de que alguien camine hasta allá.
func map_marker_color() -> Color:
	return row().get("color", Color.WHITE)


## Lo que la oferta entregó de verdad, para el registro.
static func _payload_id(offer: Dictionary) -> String:
	for key: String in ["pet_id", "powerup_id", "item_id"]:
		var value: Variant = offer.get(key)
		if value != null and not String(value).is_empty():
			return String(value)
	return "?"


func _leave() -> void:
	get_tree().call_group("hud", "announce", "El vendedor recoge el puesto.")
	set_physics_process(false)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.05, sink_time) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
