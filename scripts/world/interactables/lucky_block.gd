class_name LuckyBlock
extends Interactable
## Bloque de la suerte: parece un cofre y no lo es. Gratis, raro, y siempre
## paga ALGO. No hay precio ni rareza: el premio entero es la sorpresa, por
## eso todos los premios son buenos y cambian de tipo, no de tamaño.
##
## Los premios son una tabla con pesos y una rama por premio: uno nuevo es
## una fila más una rama, nunca un caso especial en otro sitio.

## La tabla. Los pesos son relativos; el pozo es el más raro porque es el
## único que le hace una pregunta al jugador.
const LUCKY_REWARDS: Array[Dictionary] = [
	{"id": "enemy_explosion", "weight": 1.0},
	{"id": "gem_rain", "weight": 1.0},
	{"id": "points", "weight": 1.0},
	{"id": "free_chest", "weight": 1.0},
	{"id": "powerup", "weight": 1.0},
	{"id": "well", "weight": 0.7},
]

## Objetos que ofrece el pozo, más la carta de "quedarse con todo". DOS, no
## tres: la UI de cartas tiene tres huecos y descarta el sobrante sin avisar,
## y el que caería sería justo la opción de rechazar.
const WELL_OFFERS: int = 2

@export_group("Bloque")
## Color del bloque: tiñe su material (Visual/Block), su luz (Visual/Glow) y las chispas de la explosión.
@export var block_color: Color = Color(1.0, 0.85, 0.2)
## Velocidad del vaivén del bloque, en radianes por segundo.
@export var bob_speed: float = 2.0
## Altura del vaivén del bloque, en metros.
@export var bob_height: float = 0.06
## Giro del bloque, en radianes por segundo.
@export var spin_speed: float = 0.9
@export_group("Premios")
## Alcance de enemy_explosion, en metros.
@export var explosion_radius: float = 12.0
## Fracción de la vida máxima (0-1) que pierde un jefe en enemy_explosion, en vez de morir.
@export var boss_hp_fraction: float = 0.15
## Gemas de XP que suelta gem_rain.
@export var gem_count: int = 25
## Distancia máxima a la que caen las gemas de gem_rain, en metros.
@export var gem_spread: float = 6.0
## Puntos de partida que da el premio points.
@export var points_reward: int = 80
## Dónde cae el cofre de free_chest respecto del bloque, en metros.
@export var free_chest_offset: Vector3 = Vector3(1.6, 0.0, 0.0)
## Probabilidad (0-1) de que el pozo pague un power-up en vez del objeto mejor.
@export_range(0.0, 1.0) var well_powerup_chance: float = 0.3
@export_group("Textos del pozo")
## Título de la elección del pozo.
@export var well_title: String = "El pozo pide una ofrenda"
## Descripción de cada carta de objeto que se puede entregar.
@export var well_give_line: String = "Lo cambias por algo mejor"
## Título de la carta de rechazo.
@export var well_keep_title: String = "Nada"
## Descripción de la carta de rechazo.
@export var well_keep_line: String = "Te quedas con todo"

## Cola del harness (ArenaProbe, BONK_LUCKY_REWARD): ids de premio que pagan
## los próximos bloques en vez de tirar. ESTÁTICA porque la tirada es
## estática y la cola tiene que sobrevivir entre bloques. La última entrada
## se repite. Vacía en una partida real: solo el harness la escribe.
static var _forced_rewards: Array[String] = []

var _spent: bool = false
var _time: float = 0.0
## Altura de reposo del bloque, la de la escena.
var _block_rest_y: float = 0.0

## El material del bloque es local a la escena: cada bloque tiene el suyo.
@onready var _block: MeshInstance3D = $Visual/Block
@onready var _glow: OmniLight3D = $Visual/Glow


func _ready() -> void:
	super()
	add_to_group(&"lucky_blocks")
	_block_rest_y = _block.position.y
	_paint()


func _physics_process(delta: float) -> void:
	_time += delta
	if available:
		_block.position.y = _block_rest_y + sin(_time * bob_speed) * bob_height
		_block.rotate_y(delta * spin_speed)


func _interact(player: Node) -> void:
	if _spent or not available:
		return
	_spent = true
	_emit_started()
	consume()
	var reward := _roll_reward()
	match reward:
		"enemy_explosion":
			_reward_explosion()
		"gem_rain":
			_reward_gems()
		"points":
			_reward_points(player)
		"free_chest":
			_reward_chest()
		"powerup":
			_reward_powerup(player)
		"well":
			# El ÚNICO premio que pregunta. Imprime su propia línea al
			# resolverse, y siempre se resuelve (también sin objetos).
			_reward_well(player)
			_finish()
			return
	print("Lucky block: %s" % reward)
	_finish()


func _finish() -> void:
	Juice.sparkle(global_position + Vector3.UP * 1.0)
	_emit_completed()
	sink_away()


## Encola los ids que pagan los próximos bloques (solo el harness). Un id
## desconocido es push_error y se descarta: un soak que cree probar el pozo
## mientras la tabla tira puntos daría verde sobre una rama que no corrió.
static func force_rewards(ids: Array[String]) -> void:
	var known: Dictionary[String, bool] = {}
	for row: Dictionary in LUCKY_REWARDS:
		known[String(row.id)] = true
	_forced_rewards.clear()
	for id: String in ids:
		if known.has(id):
			_forced_rewards.append(id)
		else:
			push_error("LuckyBlock: unknown forced reward '%s'" % id)


static func _roll_reward() -> String:
	# La cola del harness, si hay: se consume de adelante hacia atrás y la
	# última entrada se queda.
	if not _forced_rewards.is_empty():
		var forced := _forced_rewards[0]
		if _forced_rewards.size() > 1:
			_forced_rewards.remove_at(0)
		return forced
	var total := 0.0
	for row: Dictionary in LUCKY_REWARDS:
		total += float(row.weight)
	var roll := randf() * total
	for row: Dictionary in LUCKY_REWARDS:
		roll -= float(row.weight)
		if roll <= 0.0:
			return String(row.id)
	return String(LUCKY_REWARDS[0].id)


## Muere todo lo cercano. Los jefes no: matarlos de golpe convertiría un
## bloque gratis en la respuesta a su pelea.
func _reward_explosion() -> void:
	var radius_sq := explosion_radius * explosion_radius
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var body := node as Node3D
		if body == null or not body.is_inside_tree():
			continue
		if body.global_position.distance_squared_to(global_position) > radius_sq:
			continue
		var health := Health.find_in(body)
		if health == null or health.is_dead:
			continue
		Juice.burst(body.global_position + Vector3.UP * 0.6, block_color, 10)
		if body.is_in_group("boss"):
			health.take_damage(health.max_hp * boss_hp_fraction)
		else:
			health.take_damage(health.current_hp + health.armor)
	Juice.shake(0.3)


func _reward_gems() -> void:
	for i in gem_count:
		var gem := Pools.acquire_scene(Pools.XP_GEM_SCENE) as XpGem
		if gem == null:
			return
		var angle := randf() * TAU
		var distance := randf_range(1.0, gem_spread)
		gem.global_position = global_position \
				+ Vector3(cos(angle), 0.0, sin(angle)) * distance + Vector3.UP * 0.6


func _reward_points(player: Node) -> void:
	if player.has_method("add_points"):
		player.call("add_points", points_reward)


## Un cofre gratis junto al bloque.
func _reward_chest() -> void:
	Chest.spawn_free(get_tree(), global_position + free_chest_offset)


func _reward_powerup(player: Node) -> void:
	var powerups := PowerUps.find_in(player)
	if powerups != null:
		# Nunca la estrella: esa se encuentra rondando el mapa.
		powerups.apply(PowerUpCatalog.roll_id(true))


## El pozo: das un objeto y recibes uno mejor. Sin nada que dar paga un
## power-up directo en vez de abrir un menú con una sola carta muerta
## (open_choice no hace nada con una lista vacía y el bloque se leería roto).
func _reward_well(player: Node) -> void:
	var bag := ItemBag.find_in(player)
	var carried: Array[String] = bag.carried_ids() if bag != null else []
	if carried.is_empty():
		_reward_powerup(player)
		print("Lucky block: well (sin objetos -> power-up)")
		return
	carried.shuffle()
	var options: Array[Dictionary] = []
	for i in mini(WELL_OFFERS, carried.size()):
		var row := ItemCatalog.by_id(carried[i])
		options.append({
			"title": String(row.get("display_name", carried[i])),
			"description": well_give_line,
			"color": ItemCatalog.rarity_color(String(row.get("rarity", "Common"))),
			"item_id": carried[i],
		})
	# El rechazo siempre está, así que con un solo objeto hay elección real.
	options.append({
		"title": well_keep_title,
		"description": well_keep_line,
		"color": UiTheme.TEXT_DIM,
		"item_id": "",
	})
	get_tree().call_group("upgrade_ui", "open_choice", well_title, options,
			player, _on_well_pick.bind(player), "lucky_well")


func _on_well_pick(option: Dictionary, player: Node) -> void:
	var given := String(option.get("item_id", ""))
	if given.is_empty():
		print("Lucky block: well (nada)")
		return
	var bag := ItemBag.find_in(player)
	if bag == null or not bag.remove_item(given):
		print("Lucky block: well (nada)")
		return
	if randf() < well_powerup_chance:
		_reward_powerup(player)
		print("Lucky block: well (%s -> power-up)" % given)
		return
	var paid := _next_rarity_item(String(ItemCatalog.by_id(given).get("rarity", "Common")))
	if paid.is_empty():
		_reward_powerup(player)
		print("Lucky block: well (%s -> power-up)" % given)
		return
	bag.add_item(paid)
	print("Lucky block: well (%s -> %s)" % [given, paid])


## Un objeto de la rareza siguiente a `rarity_name`; Legendario no tiene
## siguiente, así que se cambia por otro Legendario.
static func _next_rarity_item(rarity_name: String) -> String:
	var index := UpgradePool.rarity_index(rarity_name)
	var better := mini(index + 1, UpgradePool.RARITIES.size() - 1)
	return ItemCatalog.roll_id(String(UpgradePool.RARITIES[better].name))


## Pinta el material del bloque y su luz con block_color.
func _paint() -> void:
	var material := _block.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = block_color
		material.emission = block_color
	_glow.light_color = block_color
