extends Node
## Autoload "RunState": XP, nivel, bajas y tiempo de la partida actual, más
## los multiplicadores de la partida que modifican las mejoras y leen otros
## sistemas (acoplamiento suelto por este singleton en vez de referencias a
## nodos). Su process_mode por defecto es pausable, así run_time se congela
## mientras la UI de cartas pausa el árbol.

signal xp_changed(current_xp: int, xp_to_next: int)
signal leveled_up(new_level: int)
signal kills_changed(total_kills: int)
## Cambió la dificultad de la partida (Tomo del Peligro, altares demoníacos).
signal difficulty_changed(bonus: float)
## Una etapa nueva está activa: la arena está en el árbol y la party ya se
## ubicó. `stage_index` empieza en 0; todo lo que lee el jugador o un log de
## soak lo imprime como stage_index + 1.
signal stage_changed(stage_index: int, map_id: String)

var xp: int = 0
var level: int = 1
## Costo de la primera subida de nivel (reset() lo vuelve a sacar de la curva).
var xp_to_next: int = XP_BASE + XP_PER_LEVEL
var kills: int = 0
var run_time: float = 0.0
## --- Progresión de etapas ----------------------------------------------
## Una partida es una secuencia de ETAPAS, un mapa cada una, en el orden de
## MapCatalog, que vuelve al primer mapa con lap + 1. Todo lo de la party
## cruza; solo se reinician el mapa y su reloj.
## Índice desde 0 en MapCatalog.MAP_LIBRARY.
var stage_index: int = 0
## Vueltas completas a la lista de mapas. 0 en la primera pasada.
var lap: int = 0
## Segundos en la etapa ACTUAL. run_time sigue contando toda la partida;
## este es el que leen la puerta de etapa, el horario de jefes y las hordas,
## así una etapa se juega igual llegue cuando llegue.
var stage_time: float = 0.0
## True cuando murió el Ancestral de esta etapa (lo marca EnemySpawner).
var stage_boss_dead: bool = false
## True cuando se abrió la puerta de esta etapa (tiempo Y jefe): el portal de
## salida está afuera y corre la rampa pseudo-infinita.
var stage_cleared: bool = false
## Segundos desde que se superó esta etapa: el reloj pseudo-infinito.
var pseudo_infinite_time: float = 0.0
## Totales de la partida, que se suman al registro meta al final.
var stages_cleared_total: int = 0
var endless_seconds_total: float = 0.0
var laps_completed: int = 0
## Mapas visitados / superados en esta partida, en orden. El registro meta
## acredita runs_on_<mapa> por cada visitado y victories_<mapa> por cada
## superado, así las misiones por mapa funcionan en una partida de varios.
var visited_map_ids: Array[String] = []
var cleared_map_ids: Array[String] = []
## True mientras la partida está en curso; RunManager lo apaga al terminar
## (muerte o victoria) para que eventos tardíos del mismo frame, como una
## carta de nivel, se retiren.
var run_active: bool = true
## Multiplica el radio de imán de cada gema; lo suben las mejoras de alcance
## de recolección.
var pickup_radius_multiplier: float = 1.0
## Altares demoníacos completados en esta partida: los jefes sueltan un cofre
## extra por uso, y élites y hordas también lo leen.
var demonic_uses: int = 0
## Bono de dificultad de la partida, en fracción: 0.3 = +30%. Lo comparte
## toda la party. Los spawns nuevos escalan HP/daño por (1 + bono) y la XP
## por (1 + bono * DIFFICULTY_XP_SHARE). Las fuentes suman con
## add_difficulty (los tomos vuelven a publicar su total por jugador con
## set_difficulty_source, así el recálculo desde cero sigue exacto).
var difficulty_bonus: float = 0.0
## Aporte de dificultad por fuente (id de fuente -> fracción).
var _difficulty_sources: Dictionary[String, float] = {}
## Fracción del bono de dificultad que se vuelve XP extra en cada gema.
const DIFFICULTY_XP_SHARE: float = 0.75
## Pactos demoníacos: las perillas de la partida que escribe el COSTO de un
## pacto. Cada una es una fracción (0.1 = +10%) y tiene exactamente un
## consumidor, nombrado aquí para que ninguna quede como dato muerto:
##   elite_chance_bonus      -> EnemySpawner.elite_chance()
##   sky_duration_multiplier -> duración del evento de cielo (WorldDirector)
##   event_chance_bonus      -> probabilidad de evento de cielo (WorldDirector)
##   disaster_chance_bonus   -> tirada de desastre del WorldDirector (lo
##                              primero que se tira en un tick de evento).
var elite_chance_bonus: float = 0.0
var sky_duration_multiplier: float = 1.0
var event_chance_bonus: float = 0.0
var disaster_chance_bonus: float = 0.0
## Economía de cofres: precio base en puntos por rareza, y el multiplicador
## GLOBAL que cada cofre abierto aplica a todos los demás.
const CHEST_BASE_PRICES: Dictionary[String, int] = {
	"Common": 20, "Rare": 40, "Epic": 80, "Legendary": 160}
const CHEST_PRICE_GROWTH: float = 1.25
## Multiplicador de precio de cofres de la party, un paso de
## CHEST_PRICE_GROWTH por cofre abierto. Es el ÚNICO registro de cofres de la
## partida: el contador "chests_opened" de las misiones vive en SaveData (lo
## suma Interactable.consume).
var chest_price_multiplier: float = 1.0
## Economía de la ruleta: cada giro DUPLICA el precio de los siguientes en
## esta partida. Más empinado que el de cofres a propósito: un giro puede dar
## un objeto Legendario.
const ROULETTE_PRICE_GROWTH: float = 2.0
var roulette_price_multiplier: float = 1.0
## Lo que pide el vendedor de power-ups por su primera venta de la partida.
const POWERUP_VENDOR_BASE_PRICE: int = 100
## Lo que cobra a continuación el vendedor de power-ups, en puntos. Un precio
## ABSOLUTO de la partida y no un multiplicador: el puesto vende un power-up
## sacado sea cual sea, así que el número mismo es la escalera, y sube solo
## cuando hay una venta.
var powerup_vendor_price: int = POWERUP_VENDOR_BASE_PRICE
## Multiplicador de todo lo que la party COMPRA con puntos mientras cae la
## lluvia dorada (1.0 normal, 0.5 durante). Lo leen cofres, ruleta y
## manantial — y con ellos el vendedor de objetos, que pone precio con
## chest_price. El vendedor de power-ups y los precios de mascota quedan
## fuera a propósito: son la economía de largo plazo de la partida.
var price_discount: float = 1.0
## Variable de entorno que hace reproducible toda una partida (ver reset()).
## Solo pruebas; nada del juego la pone.
const GAME_SEED_ENV: String = "BONK_GAME_SEED"

## Curva de XP: costo del nivel al que se sube, en gemas (del 1 al 2 cuesta
## XP_BASE + XP_PER_LEVEL + el término cuadrático). Todo el ritmo de la
## partida va en estos tres números.
const XP_BASE: int = 5
const XP_PER_LEVEL: int = 3
## Término cuadrático: los primeros niveles casi no cambian (el 1 cuesta 8)
## y los tardíos pesan: el nivel 10 cuesta 50 y el 20 cuesta 125.
const XP_PER_LEVEL_SQUARED: float = 0.15


func _ready() -> void:
	reset()


func _physics_process(delta: float) -> void:
	# Solo una partida viva avanza el reloj: cuando RunManager la da por
	# terminada (o antes de empezar), nada que lea run_time — nota de
	# victoria, boons temporales, puntaje diario — debe verlo avanzar en los
	# frames en que algo despausa el árbol.
	if run_active:
		run_time += delta
		stage_time += delta
		if stage_cleared:
			pseudo_infinite_time += delta
			endless_seconds_total += delta


## Llamar al empezar una partida nueva.
func reset() -> void:
	xp = 0
	level = 1
	kills = 0
	run_time = 0.0
	run_active = true
	stage_index = 0
	lap = 0
	stages_cleared_total = 0
	endless_seconds_total = 0.0
	laps_completed = 0
	visited_map_ids = []
	cleared_map_ids = []
	begin_stage()
	pickup_radius_multiplier = 1.0
	demonic_uses = 0
	elite_chance_bonus = 0.0
	sky_duration_multiplier = 1.0
	event_chance_bonus = 0.0
	disaster_chance_bonus = 0.0
	difficulty_bonus = 0.0
	_difficulty_sources.clear()
	chest_price_multiplier = 1.0
	roulette_price_multiplier = 1.0
	powerup_vendor_price = POWERUP_VENDOR_BASE_PRICE
	price_discount = 1.0
	# Los contadores acreditados durante una partida viven en un buffer de
	# SaveData que solo el FIN de una partida pasa al registro guardado;
	# empezar (o abandonar) una partida tira lo pendiente, y eso cumple el
	# contrato de save_data "una partida abandonada no guarda nada". Se busca
	# por ruta: este autoload carga ANTES que SaveData, así que el primer
	# reset (al abrir la app) no puede nombrarlo.
	var ledger := get_node_or_null("/root/SaveData")
	if ledger != null:
		ledger.call("discard_run_counters")
	# Cacería diaria: todos sacan las mismas cartas, spawns y eventos en una
	# fecha dada; las partidas normales reordenan el flujo. Se busca por ruta:
	# este autoload carga ANTES que GameConfig, así que el primer reset (al
	# abrir la app, nunca diario) no puede nombrarlo.
	var config := get_node_or_null("/root/GameConfig")
	var game_seed := OS.get_environment(GAME_SEED_ENV)
	if config != null and bool(config.daily_mode) and int(config.daily_seed) != 0:
		seed(int(config.daily_seed))
	elif game_seed.is_valid_int():
		# Solo pruebas (BONK_GAME_SEED): el flujo de la partida — cartas,
		# spawns, scatter y por lo tanto el relieve — se vuelve reproducible,
		# para que una comparación entre dos corridas no mida ruido.
		seed(int(game_seed))
	else:
		randomize()
	xp_to_next = _xp_required(level)
	xp_changed.emit(xp, xp_to_next)
	kills_changed.emit(kills)
	difficulty_changed.emit(difficulty_bonus)


## Limpia los campos por etapa. Lo llaman reset() y RunRoot en cada cambio de
## etapa; los contadores de toda la partida de arriba NO van aquí, a propósito.
func begin_stage() -> void:
	stage_time = 0.0
	stage_boss_dead = false
	stage_cleared = false
	pseudo_infinite_time = 0.0


## Registra que se superó la etapa actual. Idempotente: la puerta se sondea,
## y si no acreditaría una etapa por frame.
func mark_stage_cleared(map_id: String) -> void:
	if stage_cleared:
		return
	stage_cleared = true
	stages_cleared_total += 1
	if not cleared_map_ids.has(map_id):
		cleared_map_ids.append(map_id)


func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	xp += amount
	# Bucle: una gema grande puede dar varios niveles; sale un leveled_up por
	# nivel para que la UI de cartas encole elecciones extra.
	while xp >= xp_to_next:
		xp -= xp_to_next
		level += 1
		xp_to_next = _xp_required(level)
		leveled_up.emit(level)
	xp_changed.emit(xp, xp_to_next)


func add_kill() -> void:
	kills += 1
	kills_changed.emit(kills)


## Fija el aporte de dificultad de una fuente (p. ej. "tomes_p0" para el total
## del Tomo del Peligro del jugador 0) y vuelve a sumar el bono de la
## partida. Las fuentes que recalculan desde cero (PlayerStats) llaman esto
## con su total completo.
func set_difficulty_source(source: String, fraction: float) -> void:
	if is_zero_approx(fraction):
		_difficulty_sources.erase(source)
	else:
		_difficulty_sources[source] = fraction
	_resum_difficulty()


## Suma un aporte permanente de una sola vez (usos de altar demoníaco).
func add_difficulty(fraction: float, source: String = "altars") -> void:
	if fraction <= 0.0:
		return
	_difficulty_sources[source] = float(_difficulty_sources.get(source, 0.0)) + fraction
	_resum_difficulty()


func _resum_difficulty() -> void:
	var total := 0.0
	for source: String in _difficulty_sources:
		total += _difficulty_sources[source]
	difficulty_bonus = maxf(total, 0.0)
	difficulty_changed.emit(difficulty_bonus)


## Precio actual de un cofre de la rareza dada, en puntos.
func chest_price(rarity_name: String) -> int:
	var base := int(CHEST_BASE_PRICES.get(rarity_name, CHEST_BASE_PRICES["Common"]))
	return ceili(float(base) * chest_price_multiplier * price_discount)


## Cada cofre abierto encarece todos los demás (multiplicador global).
func register_chest_opened() -> void:
	chest_price_multiplier *= CHEST_PRICE_GROWTH


## Precio actual de un giro de ruleta, en puntos: el precio base del
## santuario por el crecimiento de la partida.
func roulette_price(base_price: int) -> int:
	return ceili(float(base_price) * roulette_price_multiplier * price_discount)


## Cada giro hace que el siguiente cueste ROULETTE_PRICE_GROWTH veces más,
## para toda la party y el resto de la partida.
func register_roulette_spin() -> void:
	roulette_price_multiplier *= ROULETTE_PRICE_GROWTH


## Multiplicador de XP que da la dificultad de la partida en cada gema.
func difficulty_xp_multiplier() -> float:
	return 1.0 + difficulty_bonus * DIFFICULTY_XP_SHARE


func _xp_required(for_level: int) -> int:
	return XP_BASE + for_level * XP_PER_LEVEL \
			+ roundi(XP_PER_LEVEL_SQUARED * float(for_level * for_level))
