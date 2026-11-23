class_name LuckyBlock
extends Interactable
## Bloque de la suerte: parece un cofre y no lo es. Gratis y siempre paga
## ALGO, pero no siempre bueno: puede dar gemas, puntos o un objeto, o
## traer un jefe, una horda o más dificultad. Los jefes
## sueltan dos al morir (BossBase).
##
## Los premios son una tabla con pesos y una rama por premio: uno nuevo es
## una fila más una rama, nunca un caso especial en otro sitio.

## La tabla, edita aquí. Los pesos son relativos.
const LUCKY_REWARDS: Array[Dictionary] = [
	{"id": "gem_rain", "weight": 1.0},
	{"id": "points", "weight": 1.0},
	{"id": "random_item", "weight": 1.0},
	{"id": "horde", "weight": 0.8},
	{"id": "boss", "weight": 0.5},
	{"id": "difficulty", "weight": 0.8},
]

@export_group("Bloque")
## Color del bloque: tiñe su material (Visual/Block), su luz (Visual/Glow) y las chispas al abrirlo.
@export var block_color: Color = Color(1.0, 0.85, 0.2)
## Velocidad del vaivén del bloque, en radianes por segundo.
@export var bob_speed: float = 2.0
## Altura del vaivén del bloque, en metros.
@export var bob_height: float = 0.06
## Giro del bloque, en radianes por segundo.
@export var spin_speed: float = 0.9
@export_group("Premios")
## Gemas de XP que suelta gem_rain.
@export var gem_count: int = 25
## XP de cada gema de gem_rain (una gema normal vale 1).
@export var gem_value: int = 2
## Distancia mínima a la que caen las gemas de gem_rain, en metros.
@export var gem_min_spread: float = 1.0
## Distancia máxima a la que caen las gemas de gem_rain, en metros.
@export var gem_spread: float = 6.0
## Puntos de partida que da el premio points.
@export var points_reward: int = 300
## Dificultad, en %, que suma el premio difficulty.
@export var difficulty_reward: float = 10.0
@export_group("Textos")
## Aviso del HUD de cada premio (por id); %s = nombre del objeto en random_item, %d = número en points y difficulty.
@export var reward_texts: Dictionary[String, String] = {
	"gem_rain": "¡Lluvia de gemas!",
	"points": "¡+%d pts!",
	"random_item": "Objeto: %s",
	"horde": "¡El bloque llama a una horda!",
	"boss": "¡El bloque despierta a un jefe!",
	"difficulty": "Dificultad +%d%%",
}

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


func _interact(player: Node) -> void:
	if _spent or not available:
		return
	_spent = true
	_emit_started()
	consume()
	var reward := _roll_reward()
	_pay(reward, player)
	print("Lucky block: %s" % reward)
	_finish()


## Una rama por premio. Si un premio no puede salir (sin spawner, o un jefe
## que pelea solo no deja entrar hordas ni jefes), paga gemas en su lugar.
func _pay(reward: String, player: Node) -> void:
	var spawner := get_tree().get_first_node_in_group(&"enemy_spawner") as EnemySpawner
	match reward:
		"gem_rain":
			_reward_gems()
		"points":
			if player.has_method("add_points"):
				player.call("add_points", points_reward)
			_say(reward, points_reward)
			return
		"random_item":
			_reward_item(player)
			return
		"horde":
			if spawner == null or not spawner.start_horde():
				_reward_gems()
				reward = "gem_rain"
		"boss":
			if spawner == null or not spawner.spawn_bonus_boss():
				_reward_gems()
				reward = "gem_rain"
		"difficulty":
			RunState.add_difficulty(difficulty_reward / 100.0, "lucky_block")
			_say(reward, roundi(difficulty_reward))
			return
	_say(reward)


## Pinta el material del bloque y su luz con block_color.
func _paint() -> void:
	var material := _block.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = block_color
		material.emission = block_color
	_glow.light_color = block_color


func _finish() -> void:
	Juice.sparkle(global_position + Vector3.UP * 1.0)
	_emit_completed()
	sink_away()


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


func _reward_gems() -> void:
	for i in gem_count:
		var gem := Pools.acquire_scene(Pools.XP_GEM_SCENE) as XpGem
		if gem == null:
			return
		gem.xp_value = gem_value
		var angle := randf() * TAU
		var distance := randf_range(gem_min_spread, gem_spread)
		gem.global_position = global_position \
				+ Vector3(cos(angle), 0.0, sin(angle)) * distance + Vector3.UP * 0.6


## Un objeto al azar, con la rareza sorteada por la suerte de quien abre.
func _reward_item(player: Node) -> void:
	var bag := ItemBag.find_in(player)
	var stats := PlayerStats.find_in(player)
	var luck := stats.luck if stats != null else 0.0
	var item_id := ItemCatalog.roll_id(String(UpgradePool.roll_rarity(luck).name))
	if bag == null or item_id.is_empty():
		_reward_gems()
		_say("gem_rain")
		return
	bag.add_item(item_id)
	_say("random_item", 0, String(ItemCatalog.by_id(item_id).get("display_name", item_id)))


## Aviso del HUD del premio, desde reward_texts.
func _say(reward: String, number: int = 0, name_text: String = "") -> void:
	var template := String(reward_texts.get(reward, ""))
	if template.is_empty():
		return
	var text := template
	if template.contains("%s"):
		text = template % name_text
	elif template.contains("%d"):
		text = template % number
	get_tree().call_group("hud", "announce", text)
