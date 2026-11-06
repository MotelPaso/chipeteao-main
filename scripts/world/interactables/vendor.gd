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
## El puesto es dueño de la ECONOMÍA: qué hay en el estante y a qué precio
## (roll_offers), qué se cobra y qué se entrega (buy), el registro y la regla de
## una sola venta. VendorUi (VendorPanel.tscn) solo dibuja las ofertas y le
## devuelve la elegida.
##
## Se queda hasta vender algo: un vendedor que se fuera por tiempo sería una
## caminata larga que el grupo puede perder por llegar tarde.

## Tipos de puesto, edita aquí. Campos de fila: id (identificador, también
## `kind`), display_name y prompt (texto del jugador), color (baliza, figura,
## toldo, luz, acento del panel y marcador). Un cuarto tipo es una fila aquí,
## una rama en roll_offers() y otra en buy(), nunca un caso especial por id en
## otro lado.
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

## Ids de fila de VENDOR_LIBRARY con rama propia en roll_offers() y buy().
const KIND_ANIMALS: String = "animals"
const KIND_POWERUPS: String = "powerups"
const KIND_ITEMS: String = "items"

## El menú que abre el puesto (VendorUi).
const VENDOR_PANEL_SCENE := preload("res://scenes/ui/modal/VendorPanel.tscn")

## Qué puesto es (id de fila de VENDOR_LIBRARY); lo fija el WorldDirector antes
## de que entre al árbol.
@export var kind: String = "items"

@export_group("Precios")
## Precio fijo de cualquier mascota en el traficante, en puntos. A propósito no
## es un precio de cofre: una mascota es un espacio, no una rareza, y ponerle
## precio por rareza daría a entender que una es la buena.
@export var pet_price: int = 120
## Multiplicador del precio del power-up tras cada venta, para toda la partida.
## El precio inicial es RunState.POWERUP_VENDOR_BASE_PRICE.
@export var powerup_price_growth: float = 1.5

@export_group("Estante")
## Mascotas que ofrece el traficante (una elección entre varias).
@export var pet_offers: int = 3
## Objetos que ofrece el vendedor de objetos, cada uno con su rareza sorteada.
## El de power-ups siempre ofrece uno solo: su precio es el de la partida y
## ofrecer más sería el mismo precio repetido.
@export var item_offers: int = 4
## Re-tiradas cuando un objeto cae en un hueco que ya lo tiene: el mismo nombre
## dos veces con dos precios parece un bug. Es acotado porque una rareza puede
## tener menos objetos que huecos el estante (Legendario tiene dos).
@export var item_rerolls: int = 4

@export_group("Espera y salida")
## Segundos que el puesto ignora `interact` tras cerrarse un menú sin venta. El
## soak vuelve a interactuar cada 0.75 s mientras se queda cerca, y sin esto el
## panel se reabriría apenas se cierra, para siempre.
@export var retry_cooldown: float = 20.0
## Segundos que tarda el puesto en encogerse y desaparecer tras la venta.
@export var sink_time: float = 0.6
## Escala final del puesto al encogerse (0-1).
@export var sink_scale: float = 0.05

@export_group("Textos")
## Línea que se muestra EN LUGAR de la del puesto mientras corre la espera; %d
## son los segundos que faltan. Sin el prefijo "[E] " de los demás prompts: el
## token promete un botón que hace algo, y durante la espera no hay nada que
## presionar, así que se lee como un estado.
@export var cooldown_prompt_template: String = "Atiende de nuevo en %d s"
## Prompt para una fila que no trae uno (un `kind` mal escrito).
@export var default_prompt: String = "[E] Comerciar"
## Etiqueta de duración en la carta del power-up; %d son los segundos.
@export var duration_tag_template: String = "%d s"
## Aviso del HUD cuando el puesto se va tras la venta.
@export var leave_announcement: String = "El vendedor recoge el puesto."

var _sold: bool = false
var _cooldown_left: float = 0.0
var _ui: VendorUi = null
var _time: float = 0.0
var _sign: MeshInstance3D = null


func _init() -> void:
	marker_kind = &"vendor"
	prompt_height = 3.0


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


## El estante para `player`, sorteado UNA vez al abrir el menú: el panel se
## redibuja tras cada clic y cada cambio de puntos, y un estante rearmado ahí
## cambiaría la mercancía bajo el cursor. Cada oferta es una fila lista para
## mostrar Y el argumento que consume buy(): kind, price, title, tag, lines,
## color y la carga (pet_id / powerup_id / item_id).
func roll_offers(player: Node) -> Array[Dictionary]:
	match kind:
		KIND_ANIMALS:
			return _animal_offers(player)
		KIND_POWERUPS:
			return _powerup_offers()
		KIND_ITEMS:
			return _item_offers(player)
	push_warning("VendorUi: unknown vendor kind '%s'" % kind)
	return []


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
	var ui := VENDOR_PANEL_SCENE.instantiate() as VendorUi
	ui.setup(self, player, offers)
	# Cuelga de la etapa como todo lo que aparece, así un cambio de etapa se
	# lleva el panel junto con el puesto en vez de dejar un árbol pausado.
	RunRoot.stage_parent(get_tree()).add_child(ui)
	_ui = ui
	ui.tree_exited.connect(_on_menu_closed)


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
		KIND_ANIMALS:
			if player.has_method("set_pet"):
				player.call("set_pet", String(offer.get("pet_id", "")))
		KIND_POWERUPS:
			var powerups := PowerUps.find_in(player)
			if powerups != null:
				powerups.apply(String(offer.get("powerup_id", "")))
			# Para toda la partida, y solo con una VENTA: un estante que alguien
			# miró y dejó no debe encarecer el siguiente.
			RunState.powerup_vendor_price = roundi(
					float(RunState.powerup_vendor_price) * powerup_price_growth)
		KIND_ITEMS:
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


## Mascotas que el comprador no lleva: venderle la que ya tiene le cobraría por
## cambiarla por sí misma.
func _animal_offers(player: Node) -> Array[Dictionary]:
	var current: Variant = player.get("pet_id")
	var held := String(current) if current != null else ""
	var rows: Array[Dictionary] = []
	for pet: Dictionary in PetCatalog.PET_LIBRARY:
		if String(pet.id) != held:
			rows.append(pet)
	rows.shuffle()
	var offers: Array[Dictionary] = []
	for i in mini(pet_offers, rows.size()):
		var pet: Dictionary = rows[i]
		offers.append({
			"kind": KIND_ANIMALS,
			"pet_id": String(pet.id),
			"price": pet_price,
			"title": String(pet.display_name),
			# El arma y la stat son lo único que cambia entre mascotas, así que
			# ambas van en cada carta: un cambio que no se puede deshacer nunca
			# debe ser una apuesta.
			"tag": PetCatalog.weapon_display_name(pet),
			"lines": PackedStringArray([String(pet.get("stat_label", ""))]),
			"color": pet.get("color", UiTheme.TEXT_BRIGHT),
		})
	return offers


## Un power-up, nunca la estrella: esa se encuentra recorriendo el mapa, y por
## eso PowerUpCatalog.roll_id la excluye también para toda otra fuente.
func _powerup_offers() -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	var powerup_id := PowerUpCatalog.roll_id(true)
	if powerup_id.is_empty():
		return offers
	var powerup := PowerUpCatalog.by_id(powerup_id)
	offers.append({
		"kind": KIND_POWERUPS,
		"powerup_id": powerup_id,
		# Se lee aquí y no se guarda: el precio sube con cada power-up comprado
		# en cualquier puesto de la partida, así que la carta cotiza lo que dejó
		# el último comprador.
		"price": RunState.powerup_vendor_price,
		"title": String(powerup.display_name),
		# La duración del catálogo, antes de que la stat de duración del
		# comprador la estire: el puesto vende la fila, no el equipo del raider.
		"tag": duration_tag_template % int(powerup.get("duration", 0.0)),
		"lines": PackedStringArray([String(powerup.get("description", ""))]),
		"color": powerup.get("color", UiTheme.TEXT_BRIGHT),
	})
	return offers


## Objetos, cada uno con su propia tirada de rareza inclinada por la suerte del
## comprador. Un objeto de un estante y uno de un cofre son la misma compra, así
## que una sola curva les pone precio a ambos, inflación de cofres incluida.
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
			"price": RunState.chest_price(rarity_name),
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
	for key: String in ["pet_id", "powerup_id", "item_id"]:
		var value: Variant = offer.get(key)
		if value != null and not String(value).is_empty():
			return String(value)
	return "?"


func _leave() -> void:
	get_tree().call_group("hud", "announce", leave_announcement)
	set_physics_process(false)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * sink_scale, sink_time) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
