class_name PowerUpDrops
extends RefCounted
## Power-ups que sueltan las bajas: la tirada y LA puerta que los pone en el
## suelo. Lo maneja EnemySpawner, que lo expone con roll_powerup_drop y
## spawn_powerup_pickup (los llaman EnemyBase y el WorldDirector por el grupo
## "enemy_spawner"). Las probabilidades y la escena son exports del spawner
## (grupo «Power-ups»).

## Interruptor de prueba: con BONK_POWERUP_BOOST=1 la probabilidad de drop se
## multiplica por BOOST_SCALE, para que un soak de 360 s vea un puñado de
## drops sin tapizar el mapa. Nada del juego lo pone.
const BOOST_ENV := "BONK_POWERUP_BOOST"
const BOOST_SCALE: float = 50.0

var _spawner: EnemySpawner = null
## Multiplicador leído una vez de BOOST_ENV (1.0 en una partida normal). Se
## lee en el _ready del spawner y no por tirada: esto va en el camino de
## cada muerte.
var _boost: float = 1.0


func _init(spawner: EnemySpawner) -> void:
	_spawner = spawner


## Lee el interruptor de prueba. Lo llama EnemySpawner._ready.
func read_boost_switch() -> void:
	if OS.get_environment(BOOST_ENV) == "1":
		_boost = BOOST_SCALE
		print("EnemySpawner: power-up drop boost x%.0f" % BOOST_SCALE)


## True si esta muerte suelta un power-up. `killer` es el raider dueño de la
## tirada (el más cercano, como el pago de puntos), así que su «Fortuna
## menor» es la que mueve la probabilidad; un cuerpo shiny la multiplica.
## Orden del RNG: un randf por muerte que llega aquí.
func roll(killer: Node, shiny: bool) -> bool:
	var chance := _spawner.base_powerup_drop_chance * _boost
	var stats := PlayerStats.find_in(killer) if killer != null else null
	if stats != null:
		chance *= 1.0 + stats.powerup_drop_chance / 100.0
	if shiny:
		chance *= _spawner.shiny_powerup_drop_scale
	return randf() < chance


## Suelta un pickup en `at`. LA puerta de los power-ups en el suelo: el
## avistamiento de la estrella también pasa por aquí, así que el padre de
## etapa y el grupo se escriben una sola vez.
func spawn(at: Vector3, powerup_id: String) -> Node3D:
	var scene := _spawner.powerup_pickup_scene
	if powerup_id.is_empty() or scene == null:
		return null
	var pickup := scene.instantiate() as PowerUpPickup
	if pickup == null:
		return null
	pickup.setup(powerup_id)
	# De alcance de etapa, como todo lo que cae al mundo: el cambio de etapa
	# lo libera junto con el resto en vez de llevárselo.
	RunRoot.stage_parent(_spawner.get_tree()).add_child(pickup)
	pickup.global_position = at
	print("Power-up dropped: %s" % powerup_id)
	return pickup
