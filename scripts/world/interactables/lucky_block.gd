class_name LuckyBlock
extends Interactable
## Bloque de la suerte: parece un cofre y no lo es. Gratis, raro, y siempre
## paga ALGO. No hay precio ni rareza: el premio entero es la sorpresa, por
## eso todos los premios son buenos y cambian de tipo, no de tamaño.
##
## Los premios son una tabla con pesos y una rama por premio: uno nuevo es
## una fila más una rama, nunca un caso especial en otro sitio.

@export var block_color: Color = Color(1.0, 0.85, 0.2)
## Alcance de enemy_explosion en metros, y fracción de la vida máxima que pierde un jefe en vez de morir.
@export var explosion_radius: float = 12.0
@export var boss_hp_fraction: float = 0.15
@export var gem_count: int = 25
@export var gem_spread: float = 6.0
@export var points_reward: int = 80

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

const CHEST_SCENE: PackedScene = preload("res://scenes/world/chests/Chest.tscn")
## Probabilidad (0-1) de que el pozo pague un power-up en vez del objeto mejor.
const WELL_POWERUP_CHANCE: float = 0.3
## Objetos que ofrece el pozo, más la carta de "quedarse con todo". DOS, no
## tres: la UI de cartas tiene tres huecos y descarta el sobrante sin avisar,
## y el que caería sería justo la opción de rechazar.
const WELL_OFFERS: int = 2
const WELL_TITLE: String = "El pozo pide una ofrenda"
const WELL_NOTHING: String = "Nada"
const WELL_NOTHING_LINE: String = "Te quedas con todo"
const WELL_GIVE_LINE: String = "Lo cambias por algo mejor"

## Cola del harness (ArenaProbe, BONK_LUCKY_REWARD): ids de premio que pagan
## los próximos bloques en vez de tirar. ESTÁTICA porque la tirada es
## estática y la cola tiene que sobrevivir entre bloques. La última entrada
## se repite. Vacía en una partida real: solo el harness la escribe.
static var _forced_rewards: Array[String] = []

var _spent: bool = false
var _time: float = 0.0
var _body: MeshInstance3D = null


func _init() -> void:
	prompt_text = "[E] Abrir bloque de la suerte"
	marker_kind = &"lucky_block"
	prompt_height = 2.4
	# Sin contador: no es un cofre y las misiones de cofres no lo cuentan.
	meta_stat_id = ""
	collision_layer = 0
	collision_mask = 1


func _ready() -> void:
	# El anillo de detección va ANTES de super(), que conecta body_entered.
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 1.9
	cylinder.height = 2.6
	shape.shape = cylinder
	shape.position.y = 1.3
	add_child(shape)
	super()
	add_to_group(&"lucky_blocks")
	_build_visual()


func _build_visual() -> void:
	_body = MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = Vector3(0.9, 0.9, 0.9)
	_body.mesh = cube
	# Material propio de cada bloque.
	var gold := StandardMaterial3D.new()
	gold.albedo_color = block_color
	gold.metallic = 0.55
	gold.roughness = 0.35
	gold.emission_enabled = true
	gold.emission = block_color
	gold.emission_energy_multiplier = 0.7
	_body.material_override = gold
	_body.position.y = 0.65
	add_child(_body)
	var mark := Label3D.new()
	mark.text = "?"
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.no_depth_test = true
	mark.font_size = 64
	mark.outline_size = 14
	mark.modulate = Color(0.25, 0.18, 0.05)
	mark.position.y = 0.65
	add_child(mark)
	var light := OmniLight3D.new()
	light.light_color = block_color
	light.light_energy = 1.6
	light.omni_range = 6.0
	light.position.y = 1.0
	add_child(light)


func _physics_process(delta: float) -> void:
	_time += delta
	if _body != null and available:
		_body.position.y = 0.65 + sin(_time * 2.0) * 0.06
		_body.rotate_y(delta * 0.9)


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
	var chest := CHEST_SCENE.instantiate() as Chest
	if chest == null:
		return
	chest.free_open = true
	var parent := RunRoot.stage_parent(get_tree())
	if parent == null:
		return
	parent.add_child(chest)
	chest.global_position = global_position + Vector3(1.6, 0.0, 0.0)


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
			"description": WELL_GIVE_LINE,
			"color": ItemCatalog.rarity_color(String(row.get("rarity", "Common"))),
			"item_id": carried[i],
		})
	# El rechazo siempre está, así que con un solo objeto hay elección real.
	options.append({
		"title": WELL_NOTHING,
		"description": WELL_NOTHING_LINE,
		"color": UiTheme.TEXT_DIM,
		"item_id": "",
	})
	get_tree().call_group("upgrade_ui", "open_choice", WELL_TITLE, options,
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
	if randf() < WELL_POWERUP_CHANCE:
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

