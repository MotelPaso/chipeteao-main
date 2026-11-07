class_name EnemySpawner
extends Node3D
## Genera enemigos con un temporizador, en un anillo alrededor de un raider y
## fuera de su vista. Con el reloj de la partida el intervalo se acorta y la
## cantidad por tick crece; la tabla de fases que elige phase_preset solo
## decide QUÉ aparece en cada bioma, y una tirada de élite puede ascender
## cualquier spawn. Todos los relojes son los de RunState (los mismos del HUD
## y de la puerta de etapa), así que rampa, hordas y jefes nunca se desfasan.
## Los enemigos son hijos de este nodo, pero el conteo de vivos sale del grupo
## "enemies" (un cadáver sigue siendo hijo durante su animación de muerte).
## Ayudantes que maneja desde su _physics_process: BossSchedule (horario de
## jefes), EnemyFreeze (tiempo detenido) y PowerUpDrops (drops de power-up).
## Contratos: grupo "enemy_spawner" y los métodos públicos que otros llaman
## por nombre (call_group/has_method); los exports los guarda cada arena.
## Orden del RNG: las tiradas (randf, randf_range, pick_random) siguen un
## orden fijo del que dependen los soaks con BONK_GAME_SEED; no las reordenes.

## Tabla de fases de esta arena. Las arenas guardan el NÚMERO del valor
## (AshDunes = 1, Gloomfen = 2): agrega biomas nuevos AL FINAL, nunca en medio.
enum PhasePreset { FOREST, DUNES, MARSH }

## Mezclas de spawn por tiempo. Cada entrada se activa en from_minute y sigue
## hasta que una posterior la reemplaza; los pesos son relativos dentro de la
## fase. Cada clave es un tipo que _scene_for() traduce a su escena exportada;
## una clave nueva necesita su rama ahí y su escena en cada arena.
const FOREST_PHASES: Array[Dictionary] = [
	{"from_minute": 0.0, "weights": {"grunt": 1.0}},
	{"from_minute": 2.0, "weights": {"grunt": 0.8, "skirmisher": 0.2}},
	{"from_minute": 5.0, "weights": {"grunt": 0.7, "skirmisher": 0.2, "tank": 0.1}},
	{"from_minute": 8.0, "weights": {"grunt": 0.55, "skirmisher": 0.25, "tank": 0.2}},
]

const DUNES_PHASES: Array[Dictionary] = [
	{"from_minute": 0.0, "weights": {"grunt": 0.7, "sunspitter": 0.3}},
	{"from_minute": 2.0, "weights": {"grunt": 0.55, "sunspitter": 0.3, "burrower": 0.15}},
	{"from_minute": 5.0,
			"weights": {"grunt": 0.45, "sunspitter": 0.25, "burrower": 0.15, "tank": 0.15}},
	{"from_minute": 8.0,
			"weights": {"grunt": 0.3, "sunspitter": 0.3, "burrower": 0.2, "tank": 0.2}},
]

## Ciénaga Lóbrega: mezcla de mapa veterano, con mucho enemigo a distancia
## desde el inicio y todos los tipos anteriores en juego desde el minuto 5.
const MARSH_PHASES: Array[Dictionary] = [
	{"from_minute": 0.0, "weights": {"grunt": 0.6, "skirmisher": 0.4}},
	{"from_minute": 2.0,
			"weights": {"grunt": 0.45, "skirmisher": 0.3, "burrower": 0.25}},
	{"from_minute": 5.0,
			"weights": {"grunt": 0.35, "skirmisher": 0.25, "burrower": 0.2, "tank": 0.2}},
	{"from_minute": 8.0,
			"weights": {"grunt": 0.25, "skirmisher": 0.3, "burrower": 0.25, "tank": 0.2}},
]

## Intentos de una muestra de anillo/banda para hallar una celda caminable;
## el último candidato se usa igual (un spawn nunca se pierde en silencio).
const RING_ATTEMPTS: int = 8
## Altura sobre el suelo hallado por el rayo, en metros: el enemigo se
## asienta en vez de nacer un frame dentro del suelo.
const SPAWN_GROUND_OFFSET: float = 0.05
## Altura de inicio del rayo de suelo sin Terrain, en metros: sobre toda
## plataforma y meseta, bajo el techo de los muros de máscara.
const GROUND_PROBE_HEIGHT: float = 12.0
## Con Terrain, el rayo parte esta altura sobre su punto más alto y termina
## esta otra bajo el más bajo, en metros (ver _ground_height).
const PROBE_HEADROOM: float = 30.0
const PROBE_UNDERSHOOT: float = 2.0
## Radianes que un hueco de ráfaga puede desviarse de su posición pareja en
## el anillo, para que el cerco se vea orgánico y no geométrico.
const BURST_ANGLE_JITTER: float = 0.35
## Techo duro de la probabilidad de élite, suba lo que suba la dificultad:
## pasado esto una élite deja de ser un evento.
const ELITE_CHANCE_CAP: float = 0.6
## Media placa usable, en metros, solo si la escena no tiene nodo en el grupo
## "arena_bounds" (las arenas lo tienen: es su scatter).
const FALLBACK_HALF_EXTENT: float = 78.0

@export_group("Escenas y fases")
## Tabla de fases de spawn de esta arena (ver PhasePreset).
@export var phase_preset: PhasePreset = PhasePreset.FOREST
## Escena del tipo "grunt"; cada tipo que usa la tabla de esta arena necesita
## la suya (se valida en _ready).
@export var grunt_scene: PackedScene
## Escena del tipo "skirmisher".
@export var skirmisher_scene: PackedScene
## Escena del tipo "tank".
@export var tank_scene: PackedScene
## Escena del tipo "sunspitter".
@export var sunspitter_scene: PackedScene
## Escena del tipo "burrower".
@export var burrower_scene: PackedScene

@export_group("Ritmo y dificultad")
## Multiplicador global de cantidad: escala los enemigos de cada tick del
## flujo Y el tamaño de cada horda. No toca el cupo (ver «Cupo de enemigos»).
@export var spawn_count_multiplier: float = 6.0
## Segundos entre ticks del flujo al empezar la partida.
@export var start_interval: float = 3.0
## Piso del intervalo entre ticks, en segundos (también de los factores de
## jefe, eclipse y pseudo-infinito; la party lo divide al final).
@export var min_interval: float = 0.35
## Segundos que pierde el intervalo por minuto de partida.
@export var interval_shrink_per_minute: float = 0.32
## Enemigos por tick al empezar, antes de spawn_count_multiplier.
@export var base_count_per_tick: int = 1
## Enemigos por tick que se suman por minuto (se trunca a entero; con 0.45
## los escalones caen en los minutos ~2.2 / 4.4 / 6.7).
@export var extra_count_per_minute: float = 0.45

@export_group("Cupo de enemigos")
## Máximo de enemigos vivos para el flujo normal: un tick crea a lo sumo
## max_active menos los vivos. Si subes spawn_count_multiplier, sube este y
## los dos márgenes de abajo en proporción, o el cupo recorta el aumento.
@export var max_active: int = 240
## Margen sobre max_active para hordas y tsunami (llegan hasta
## max_active + horde_overflow vivos).
@export var horde_overflow: int = 120
## Margen sobre max_active para packs de élite y lluvia de enemigos (hasta
## max_active + pressure_overflow vivos): sin él una arena saturada daría
## cero enemigos a un pack anunciado.
@export var pressure_overflow: int = 24

@export_group("Anillo de spawn")
## Radio mínimo del anillo de spawn alrededor del raider, en metros.
@export var min_radius: float = 18.0
## Radio máximo del anillo de spawn, en metros.
@export var max_radius: float = 25.0
## Metros que se restan al borde de la arena para que un spawn caiga sobre el suelo.
@export var arena_edge_margin: float = 2.0
## Distancia mínima de un spawn a cualquier raider en pie, en metros. Debe
## quedar BAJO surge_min_radius, o hordas y packs se anularían.
@export var min_player_clearance: float = 5.0

@export_group("Rampa tardía")
## Minuto de partida desde el que los spawns regulares escalan sin techo.
@export var late_ramp_start_minute: float = 6.0
## HP extra por minuto pasado el inicio de la rampa (fracción: 0.08 = +8%).
@export var late_hp_per_minute: float = 0.08
## Daño extra por minuto pasado el inicio de la rampa (fracción).
@export var late_damage_per_minute: float = 0.05
## XP extra por minuto pasado el inicio de la rampa (fracción).
@export var late_xp_per_minute: float = 0.065

@export_group("Hordas")
## Minutos de etapa en que llega una horda; tras la última se repite cada
## horde_repeat_minutes.
@export var horde_minutes: Array[float] = [3.0, 7.0, 10.0, 13.0]
## Minutos entre hordas después de la última de horde_minutes.
@export var horde_repeat_minutes: float = 3.0
## Enemigos de una horda en el minuto 0 (antes de multiplicadores).
@export var horde_base_size: int = 18
## Enemigos que suma la horda por minuto de partida.
@export var horde_size_per_minute: float = 2.0
## Oleadas en que llega cada horda, alrededor de un raider al azar.
@export var horde_waves: int = 4
## Segundos entre oleadas de una horda.
@export var horde_wave_gap: float = 1.6
## Aviso del HUD cuando se acerca una horda.
@export var horde_warning_text: String = "¡Se acerca una horda!"

@export_group("Oleadas de presión")
## Radio mínimo de la banda donde caen hordas y packs de élite alrededor de
## su centro, en metros.
@export var surge_min_radius: float = 7.0
## Radio máximo de esa banda, en metros.
@export var surge_max_radius: float = 10.0

@export_group("Co-op")
## HP extra de los spawns por cada jugador en pie además del primero
## (fracción). El daño NO se escala: cuatro cuerpos ya reparten los golpes.
@export var coop_hp_per_extra_player: float = 0.5
## Ritmo extra del flujo por cada jugador en pie además del primero
## (fracción; divide el intervalo).
@export var coop_rate_per_extra_player: float = 0.3
## Tamaño extra de horda por cada jugador en pie además del primero (fracción).
@export var coop_horde_per_extra_player: float = 0.3
## HP extra de los jefes por cada jugador de la party además del primero
## (fracción; cuenta la party del lobby, no solo los que están en pie).
@export var coop_boss_hp_per_extra_player: float = 0.5

@export_group("Élites")
## Minuto de partida en que empiezan a salir élites.
@export var elite_start_minute: float = 3.0
## Minuto en que la probabilidad de élite llega a elite_full_chance.
@export var elite_full_minute: float = 12.0
## Probabilidad de élite (0-1) en elite_start_minute; sube lineal hasta la
## de abajo. La dificultad la multiplica y ELITE_CHANCE_CAP le pone techo.
@export var elite_start_chance: float = 0.08
## Probabilidad de élite (0-1) desde elite_full_minute.
@export var elite_full_chance: float = 0.21

@export_group("Vueltas y pseudo-infinito")
## Multiplicador de HP por vuelta completa a la lista de mapas (spawns y jefes).
@export var lap_hp_mult: float = 1.5
## Multiplicador de daño por vuelta completa.
@export var lap_damage_mult: float = 1.3
## Multiplicador de XP por vuelta completa.
@export var lap_xp_mult: float = 1.3
## HP extra por minuto tras superar la etapa (fracción).
@export var endless_hp_per_minute: float = 0.15
## Daño extra por minuto tras superar la etapa (fracción).
@export var endless_damage_per_minute: float = 0.10
## Velocidad extra por minuto tras superar la etapa (fracción).
@export var endless_speed_per_minute: float = 0.04
## Techo del factor de velocidad: más rápida que esto, la horda no se puede
## esquivar.
@export var endless_speed_cap: float = 1.8
## Multiplicador del intervalo por minuto tras superar la etapa (compuesto,
## con piso en min_interval).
@export var endless_interval_per_minute: float = 0.85
## Multiplicador del tamaño de horda mientras corre la rampa pseudo-infinita.
@export var endless_horde_mult: float = 1.5

@export_group("Jefes")
## Escena del jefe de esta arena; sin escena no hay jefes y la puerta de
## etapa no espera ninguno.
@export var boss_scene: PackedScene
## Minuto de etapa en que llega el jefe del bioma.
@export var boss_spawn_minute: float = 5.0
## Minuto de etapa en que llega su revancha Ancestral (el jefe de etapa).
@export var elder_spawn_minute: float = 11.0
## Multiplicador de stats del Ancestral (y base de los jefes recurrentes).
@export var elder_stat_multiplier: float = 1.8
## Título del Ancestral en el HUD; cada arena pone el suyo (este vale solo
## para una arena que no lo ponga).
@export var elder_title: String = "Jefe Ancestral"
## Minutos entre jefes recurrentes tras el Ancestral (0 = ninguno).
@export var boss_repeat_minutes: float = 4.0
## Cuánto más fuerte es cada jefe recurrente que el anterior (multiplicador).
@export var boss_repeat_growth: float = 1.25
## Título del jefe recurrente: %s = elder_title, %d = su rango.
@export var boss_repeat_title_template: String = "%s Ascendente %d"
## Multiplicador del intervalo de los spawns regulares mientras vive un jefe.
@export var boss_alive_interval_multiplier: float = 1.3
## Multiplicador del intervalo durante el respiro tras matar un jefe.
@export var boss_relief_interval_multiplier: float = 2.0
## Segundos de respiro tras la muerte de un jefe.
@export var boss_relief_duration: float = 15.0
## Aviso del HUD cuando aparece un jefe; cada arena pone el suyo (este vale
## solo para una arena que no lo ponga).
@export var boss_warning_text: String = "Se acerca un jefe..."

@export_group("Eventos de cielo")
## Eclipse: cuántas veces más rápido llega el flujo (divide el intervalo).
@export var eclipse_rate_multiplier: float = 1.8
## Eclipse: multiplicador de HP de los spawns.
@export var eclipse_hp_multiplier: float = 1.25
## Luna de sangre: multiplicador de daño de los spawns.
@export var blood_moon_damage_multiplier: float = 1.4
## Luna de sangre: fracción (0-1) de spawns que llegan como berserker.
@export var blood_moon_berserker_chance: float = 0.5
## Eclipse: fracción (0-1) de spawns que llegan como sombra.
@export var eclipse_shade_chance: float = 0.4

@export_group("Power-ups")
## Probabilidad (0-1) de que UNA baja suelte un power-up, antes de la stat
## de drop del raider (en %). Diminuta a propósito: tiene que ser un evento.
@export var base_powerup_drop_chance: float = 0.004
## Multiplicador de esa probabilidad si la baja es un enemigo shiny.
@export var shiny_powerup_drop_scale: float = 5.0
## Escena del power-up que cae al suelo.
@export var powerup_pickup_scene: PackedScene = preload("res://scenes/systems/PowerUpPickup.tscn")

@export_group("Tiempo detenido")
## Aviso grande del HUD al empezar el tiempo detenido.
@export var time_stop_start_text: String = "¡TIEMPO DETENIDO!"
## Aviso del HUD cuando el tiempo vuelve a correr.
@export var time_stop_end_text: String = "El tiempo vuelve a correr."

@export_group("Frenesí de la ruleta")
## Aviso del HUD cuando la ruleta potencia a la horda.
@export var temp_buff_text: String = "¡La horda crece con una fuerza antinatural!"

var _spawn_timer: float = 0.0  # arranca vencido: la acción empieza de inmediato
## Estado de la horda.
var _hordes_fired: int = 0
var _horde_waves_left: int = 0
var _horde_wave_timer: float = 0.0
var _horde_wave_size: int = 0
## Evento de cielo (nodo Weather del WorldDirector): "" | "blood_moon" | "eclipse", y los
## segundos que le quedan.
var _sky_kind: String = ""
var _sky_left: float = 0.0
## Buff temporal de enemigos (frenesí de la ruleta): multiplicador y segundos.
var _temp_buff_multiplier: float = 1.0
var _temp_buff_left: float = 0.0
## Último minuto pseudo-infinito ya anunciado, para que el log salga una vez
## por minuto y no una vez por frame.
var _endless_minute_logged: int = -1
## Nodo de límites de arena (el scatter): también responde is_walkable()
## para la máscara irregular de la arena.
var _bounds: Node3D = null
## Media placa donde puede caer un spawn, en metros: el arena_half_extent del
## scatter menos arena_edge_margin, fijado en _ready.
var _arena_half_extent: float = FALLBACK_HALF_EXTENT
## Solo lo activa el gancho del harness (force_elite_spawns).
var _force_elite_spawns: bool = false
## Spawns descartados este minuto por falta de espacio, y el minuto que se
## está contando. Se imprime una vez por minuto mientras no sea cero, para
## que un soak vea si el chequeo se está comiendo la rampa.
var _clearance_skips: int = 0
var _clearance_report_minute: int = -1
var _bosses := BossSchedule.new(self)
var _freeze := EnemyFreeze.new(self)
var _drops := PowerUpDrops.new(self)


func _ready() -> void:
	# Los santuarios llegan al spawner por este grupo, nunca por ruta.
	add_to_group("enemy_spawner")
	_bounds = get_tree().get_first_node_in_group("arena_bounds") as Node3D
	if _bounds != null:
		_arena_half_extent = float(_bounds.get("arena_half_extent")) - arena_edge_margin
	_drops.read_boost_switch()
	_validate_phase_scenes()


func _physics_process(delta: float) -> void:
	_freeze.tick(delta)
	_bosses.tick_relief(delta)
	_temp_buff_left = maxf(_temp_buff_left - delta, 0.0)
	_sky_left = maxf(_sky_left - delta, 0.0)
	if _sky_left <= 0.0 and not _sky_kind.is_empty():
		_sky_kind = ""
	_tick_endless_log()
	_bosses.tick()
	_tick_hordes(delta)
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	# Arrastra el sobrante en vez de reiniciar: con el multiplicador de la
	# party el intervalo se acerca a un frame de física, y tirar el resto
	# haría la cadencia real más lenta que la tabulada. Con piso en cero, un
	# tirón de frames compra como mucho un tick de recuperación.
	_spawn_timer = maxf(_spawn_timer + current_interval(), 0.0)
	var budget := mini(current_count_per_tick(), max_active - _live_enemy_count())
	for i in budget:
		_spawn_one()


## --- Escalado por vuelta y pseudo-infinito ---------------------------------

## Escalado por VUELTA: cada vuelta completa a la lista de mapas multiplica
## los spawns nuevos y los jefes.
func lap_hp_factor() -> float:
	return pow(lap_hp_mult, float(RunState.lap))


func lap_damage_factor() -> float:
	return pow(lap_damage_mult, float(RunState.lap))


func lap_xp_factor() -> float:
	return pow(lap_xp_mult, float(RunState.lap))


## Superada la etapa, la party puede quedarse cuanto quiera y el mapa
## responde: por minuto de RunState.pseudo_infinite_time los spawns nuevos
## traen más HP, daño y velocidad, el intervalo se acorta y las hordas
## crecen. La velocidad tiene techo: un cuerpo más rápido que el raider no se
## puede esquivar.
func endless_minutes() -> float:
	return RunState.pseudo_infinite_time / 60.0 if RunState.stage_cleared else 0.0


func endless_hp_factor() -> float:
	return 1.0 + endless_hp_per_minute * endless_minutes()


func endless_damage_factor() -> float:
	return 1.0 + endless_damage_per_minute * endless_minutes()


func endless_speed_factor() -> float:
	return minf(1.0 + endless_speed_per_minute * endless_minutes(), endless_speed_cap)


func endless_interval_factor() -> float:
	return pow(endless_interval_per_minute, endless_minutes())


## Factores de la rampa tardía para un spawn que cae ahora (1.0 antes de la
## rampa).
func late_hp_factor() -> float:
	return 1.0 + late_hp_per_minute * maxf(_minutes() - late_ramp_start_minute, 0.0)


func late_damage_factor() -> float:
	return 1.0 + late_damage_per_minute * maxf(_minutes() - late_ramp_start_minute, 0.0)


func late_xp_factor() -> float:
	return 1.0 + late_xp_per_minute * maxf(_minutes() - late_ramp_start_minute, 0.0)


## --- Cadencia del flujo -----------------------------------------------------

func current_interval() -> float:
	var interval := maxf(start_interval - interval_shrink_per_minute * _minutes(), min_interval)
	interval *= _bosses.interval_factor()
	if _sky_kind == "eclipse":
		interval /= eclipse_rate_multiplier
	# El apretón pseudo-infinito se compone encima; la presión de la party
	# divide al final, para que una party más grande siga proporcionalmente
	# más rápida.
	interval = maxf(interval * endless_interval_factor(), min_interval)
	return interval / (1.0 + coop_rate_per_extra_player * _coop_extra_alive())


func current_count_per_tick() -> int:
	var base := base_count_per_tick + int(_minutes() * extra_count_per_minute)
	return maxi(roundi(float(base) * spawn_count_multiplier), 1)


## La party configurada en el lobby: para lo que se dimensiona toda la
## partida (HP de jefe), esté quien esté derribado ahora.
func coop_extra() -> float:
	return float(maxi(Coop.player_count - 1, 0))


## --- Tabla de fases ---------------------------------------------------------

## La tabla de fases que elige el preset de esta arena.
func active_phases() -> Array[Dictionary]:
	match phase_preset:
		PhasePreset.DUNES:
			return DUNES_PHASES
		PhasePreset.MARSH:
			return MARSH_PHASES
		_:
			return FOREST_PHASES


## Elección ponderada de la fase activa en el minuto actual de la partida.
func pick_spawn_scene() -> PackedScene:
	var minutes := _minutes()
	var phases := active_phases()
	var weights: Dictionary = phases[0]["weights"]
	for phase: Dictionary in phases:
		var from_minute: float = phase["from_minute"]
		if minutes >= from_minute:
			weights = phase["weights"]
	var total := 0.0
	for kind: String in weights:
		var weight: float = weights[kind]
		total += weight
	var roll := randf() * total
	for kind: String in weights:
		var weight: float = weights[kind]
		roll -= weight
		if roll <= 0.0:
			return _scene_for(kind)
	return grunt_scene


## --- Ganchos de grupo ("enemy_spawner") ----------------------------------

## Luna de sangre: los spawns pegan más fuerte y la mitad llega como
## berserker. Eclipse: flujo más rápido, spawns más duros y algunos llegan
## como sombra. "" lo apaga. Lo llama el WorldDirector.
func set_sky_event(kind: String, duration: float) -> void:
	_sky_kind = kind
	_sky_left = duration if not kind.is_empty() else 0.0


## Congela a la horda por `duration` segundos (lo llama PowerUps). Con
## `announce`, además muestra time_stop_start_text; la renovación que
## PowerUps empuja tras un cambio de etapa no lo anuncia.
func freeze_enemies(duration: float, announce: bool = false) -> void:
	_freeze.freeze(duration)
	if announce:
		get_tree().call_group("hud", "announce_major", time_stop_start_text)


func is_frozen() -> bool:
	return _freeze.is_frozen()


## Cuerpos congelados ahora mismo (el soak los muestrea).
func frozen_bodies() -> Array[Node3D]:
	return _freeze.frozen_bodies()


## True si esta muerte suelta un power-up (lo llama EnemyBase al morir).
func roll_powerup_drop(killer: Node, shiny: bool) -> bool:
	return _drops.roll(killer, shiny)


## Pone un power-up en el suelo (EnemyBase, la estrella del WorldDirector y
## el harness).
func spawn_powerup_pickup(at: Vector3, powerup_id: String) -> Node3D:
	return _drops.spawn(at, powerup_id)


## Gancho del harness: hace shiny TODOS los spawns. Solo pruebas (ArenaProbe
## con BONK_ELITE_BOOST=1): elite_chance() tiene techo ELITE_CHANCE_CAP a
## propósito y ningún export llega a 1.0. Nada del juego lo llama.
func force_elite_spawns(on: bool) -> void:
	_force_elite_spawns = on


## Buff temporal de enemigos (el frenesí de la ruleta): los spawns nuevos
## escalan HP y daño por `multiplier` durante `duration` segundos. Renueva
## como EnemyBase.apply_poison: gana el multiplicador más fuerte y el
## temporizador más largo.
func apply_temp_enemy_buff(multiplier: float, duration: float) -> void:
	var live := _temp_buff_multiplier if _temp_buff_left > 0.0 else 1.0
	_temp_buff_multiplier = maxf(live, maxf(multiplier, 1.0))
	_temp_buff_left = maxf(_temp_buff_left, duration)
	get_tree().call_group("boss_ui", "announce", temp_buff_text)


func temp_enemy_buff() -> float:
	return _temp_buff_multiplier if _temp_buff_left > 0.0 else 1.0


## Probabilidad de que un spawn nuevo salga élite: cero antes de
## elite_start_minute, luego una rampa lineal hasta elite_full_minute. La
## dificultad de la partida la multiplica: más élites es amenaza y
## recompensa a la vez.
func elite_chance() -> float:
	var minutes := _minutes()
	if minutes < elite_start_minute:
		return 0.0
	# Ambos extremos son exports por instancia: una arena que los iguale
	# dividiría por cero y envenenaría la rampa con NAN.
	var span := maxf(elite_full_minute - elite_start_minute, 0.001)
	var ramp := clampf((minutes - elite_start_minute) / span, 0.0, 1.0)
	# Los pactos demoníacos venden probabilidad de élite directa, encima de
	# la inclinación por dificultad.
	return minf(lerpf(elite_start_chance, elite_full_chance, ramp)
			* (1.0 + RunState.difficulty_bonus) + RunState.elite_chance_bonus,
			ELITE_CHANCE_CAP)


## Gancho de invocación: coloca una `scene` en cada una de `positions` y pasa
## cada cuerpo por el MISMO escalado que un spawn de anillo, más la tirada de
## élite, sin tope. Devuelve los cuerpos que llegaron. Hoy nadie lo llama
## (Rotking invoca a sus esbirros a mano).
func spawn_minions(scene: PackedScene, positions: Array[Vector3],
		force_elites: bool = false) -> Array[EnemyBase]:
	var spawned: Array[EnemyBase] = []
	if scene == null:
		return spawned
	for pos: Vector3 in positions:
		var minion := _make_enemy_at(pos, force_elites, scene)
		if minion != null:
			spawned.append(minion)
	return spawned


## Un enemigo en cada uno de `points`, a ras de suelo (lluvia de enemigos y
## tsunami del nodo Weather). Con presupuesto, como spawn_pressure_burst:
## max_active más horde_overflow si `horde`, o pressure_overflow si no.
## Devuelve cuántos cayeron, para que el llamador pueda dosificarse.
func spawn_at_points(points: Array[Vector3], horde: bool = true) -> int:
	var cap := max_active + (horde_overflow if horde else pressure_overflow)
	var budget := cap - _live_enemy_count()
	if budget <= 0:
		return 0
	var made := 0
	for point: Vector3 in points:
		if made >= budget:
			break
		var pos := point
		pos.y = _ground_height(pos) + SPAWN_GROUND_OFFSET
		if _make_enemy_at(pos) != null:
			made += 1
	return made


## Ráfaga de presión (hordas propias y jauría shiny del WorldDirector): `count`
## enemigos de la fase actual en la banda surge_min_radius-surge_max_radius
## alrededor de `center`, encima de la cadencia normal pero con presupuesto:
## max_active más horde_overflow si `horde`, o pressure_overflow si no. Con
## `force_elites` todos salen élite. Devuelve cuántos llegaron, para que el
## llamador no anuncie una recompensa que el tope se tragó.
func spawn_pressure_burst(center: Vector3, count: int, force_elites: bool = false,
		horde: bool = false) -> int:
	if Coop.alive_player_count(get_tree()) <= 0:
		return 0
	var cap := max_active + (horde_overflow if horde else pressure_overflow)
	var budget := mini(count, cap - _live_enemy_count())
	var spawned := 0
	for i in budget:
		# Huecos parejos en el anillo con desvío, para que rodee sin amontonar.
		var angle := TAU * float(i) / float(budget) \
				+ randf_range(-BURST_ANGLE_JITTER, BURST_ANGLE_JITTER)
		# Un hueco bloqueado gira dentro de la banda de OLEADA, nunca hacia el
		# anillo lejano: un punto junto a un muro debe seguir sintiéndose como
		# "aguanta aquí bajo presión".
		var pos := _band_position(center, surge_min_radius, surge_max_radius, angle)
		pos.y = _ground_height(pos) + SPAWN_GROUND_OFFSET
		if _make_enemy_at(pos, force_elites) != null:
			spawned += 1
	return spawned


## --- Ubicación (también la usa BossSchedule) --------------------------------

## Posición del anillo alrededor del jugador, a distancia de spawn y sobre
## el suelo.
func ring_position(player: Node3D) -> Vector3:
	var pos := _band_position(player.global_position, min_radius, max_radius, randf() * TAU)
	pos.y = _ground_height(pos) + SPAWN_GROUND_OFFSET
	return pos


## True si `pos` queda lo bastante lejos de todo raider en pie. Los cuerpos
## derribados no cuentan: tratarlos como zona prohibida abriría huecos
## muertos en el anillo.
func has_player_clearance(pos: Vector3) -> bool:
	var clearance_sq := min_player_clearance * min_player_clearance
	for node: Node in Coop.alive_players(get_tree()):
		var body := node as Node3D
		if body == null:
			continue
		var away := pos - body.global_position
		away.y = 0.0
		if away.length_squared() < clearance_sq:
			return false
	return true


## Cuenta un spawn descartado e informa el total una vez por minuto de juego.
func register_clearance_skip() -> void:
	_clearance_skips += 1
	var minute := floori(_minutes())
	if minute == _clearance_report_minute:
		return
	_clearance_report_minute = minute
	# Log de una línea (convención de RunManager) para los soaks headless.
	print("Spawn skipped: no clearance x%d" % _clearance_skips)


## --- Privados ---------------------------------------------------------------

## Todo tipo que la tabla de fases de esta arena puede sacar necesita su
## PackedScene, o esa tirada terminaría en nada a mitad de partida (un tipo
## mal escrito también cae aquí, porque _scene_for devuelve null).
func _validate_phase_scenes() -> void:
	var missing: Array[String] = []
	for phase: Dictionary in active_phases():
		var weights: Dictionary = phase["weights"]
		for kind: String in weights:
			if _scene_for(kind) == null and not missing.has(kind):
				missing.append(kind)
	if not missing.is_empty():
		push_error("EnemySpawner: no scene assigned for spawn kind(s) %s." % [missing])


## Una línea por minuto mientras corre la rampa pseudo-infinita, para que un
## soak pruebe que se movió.
func _tick_endless_log() -> void:
	if not RunState.stage_cleared:
		_endless_minute_logged = -1
		return
	var minute := floori(endless_minutes())
	if minute <= _endless_minute_logged:
		return
	_endless_minute_logged = minute
	print("Pseudo-infinite: minute %d hp x%.2f dmg x%.2f speed x%.2f" % [
			minute, endless_hp_factor(), endless_damage_factor(),
			endless_speed_factor()])


## Reloj de la partida en minutos. RunState es el dueño del reloj (timer del
## HUD, puerta de etapa); un segundo reloj aquí empezaría más tarde, porque
## la arena carga después de RunState.reset().
func _minutes() -> float:
	return RunState.run_time / 60.0


## Cuerpos vivos Y peligrosos. Los cadáveres siguen siendo hijos durante su
## animación de muerte y los jefes también son hijos, así que se cuenta el
## grupo "enemies", que un enemigo deja en el instante en que muere.
func _live_enemy_count() -> int:
	return get_tree().get_node_count_in_group(&"enemies")


## La party que sigue en pie. Un raider derribado sale del grupo "player"
## hasta que lo reanimen (ver coop.gd), así que la presión por tick (ritmo,
## HP de spawns nuevos, tamaño de horda) sigue a la pelea y no castiga al
## último en pie con la horda de cuatro.
func _coop_extra_alive() -> float:
	return float(maxi(Coop.alive_player_count(get_tree()) - 1, 0))


func _sky_hp_factor() -> float:
	return eclipse_hp_multiplier if _sky_kind == "eclipse" else 1.0


func _sky_damage_factor() -> float:
	return blood_moon_damage_multiplier if _sky_kind == "blood_moon" else 1.0


func _apply_sky_variant(enemy: EnemyBase) -> void:
	match _sky_kind:
		"blood_moon":
			if randf() < blood_moon_berserker_chance:
				enemy.apply_variant("berserker")
		"eclipse":
			if randf() < eclipse_shade_chance:
				enemy.apply_variant("shade")


func _next_horde_time() -> float:
	if _hordes_fired < horde_minutes.size():
		return horde_minutes[_hordes_fired] * 60.0
	var last := horde_minutes[horde_minutes.size() - 1] if not horde_minutes.is_empty() else 0.0
	return (last + horde_repeat_minutes * float(_hordes_fired - horde_minutes.size() + 1)) * 60.0


func _tick_hordes(delta: float) -> void:
	if _horde_waves_left > 0:
		_horde_wave_timer -= delta
		if _horde_wave_timer <= 0.0:
			# Primero el ancla: con toda la party derribada no hay a quién
			# rodear, y gastar la oleada igual achicaría una horda anunciada.
			# Se reintenta en el próximo tick.
			var anchor := Coop.random_player(get_tree())
			if anchor == null:
				return
			_horde_wave_timer = horde_wave_gap
			_horde_waves_left -= 1
			spawn_pressure_burst(anchor.global_position, _horde_wave_size, false, true)
		return
	if RunState.stage_time < _next_horde_time():
		return
	_hordes_fired += 1
	var size := int((float(horde_base_size) + horde_size_per_minute * _minutes())
			* (1.0 + RunState.difficulty_bonus)
			* (1.0 + coop_horde_per_extra_player * _coop_extra_alive())
			* (endless_horde_mult if RunState.stage_cleared else 1.0)
			* spawn_count_multiplier)
	_horde_wave_size = maxi(ceili(float(size) / float(maxi(horde_waves, 1))), 1)
	_horde_waves_left = horde_waves
	_horde_wave_timer = 0.0
	get_tree().call_group("boss_ui", "announce", horde_warning_text)
	# Se loguea lo que de verdad se pide: redondear hacia arriba el tamaño
	# de oleada puede pasar el `size` crudo hasta en horde_waves - 1, y este
	# log es la única vista de la horda que tienen los soaks.
	print("Horde: %d enemies in %d waves at %.1fs" % [
			_horde_wave_size * horde_waves, horde_waves, RunState.stage_time])


## La escena exportada de un tipo de la tabla de fases, o null si el tipo no
## existe (así _validate_phase_scenes avisa un tipo mal escrito).
func _scene_for(kind: String) -> PackedScene:
	match kind:
		"grunt":
			return grunt_scene
		"skirmisher":
			return skirmisher_scene
		"tank":
			return tank_scene
		"sunspitter":
			return sunspitter_scene
		"burrower":
			return burrower_scene
		_:
			return null


func _spawn_one() -> void:
	# Co-op: anillo alrededor de un jugador vivo AL AZAR, para repartir la
	# presión de la horda en una party separada.
	var player := Coop.random_player(get_tree())
	if player == null:
		return
	_make_enemy_at(ring_position(player))


## Un enemigo, colocado, escalado y con su tirada de élite. `scene_override`
## reemplaza la tirada de la tabla de fases. Devuelve null si no hay escena o
## su raíz no es EnemyBase, para que un llamador en bucle salte esa unidad
## sin perder el resto.
func _make_enemy_at(pos: Vector3, force_elite: bool = false,
		scene_override: PackedScene = null) -> EnemyBase:
	# LA puerta de todo spawn: anillo, hordas, oleadas, invocaciones y packs
	# pasan por aquí, así que la regla de espacio libre no se le puede olvidar
	# a un llamador nuevo. Los muestreadores de posición ya prefieren puntos
	# libres; esto es lo que pasa cuando no hay ninguno.
	if not has_player_clearance(pos):
		register_clearance_skip()
		return null
	var scene := scene_override if scene_override != null else pick_spawn_scene()
	if scene == null:
		return null
	var node := scene.instantiate()
	var enemy := node as EnemyBase
	if enemy == null:
		node.free()
		push_warning("EnemySpawner: spawn scene root does not extend EnemyBase.")
		return null
	add_child(enemy)
	enemy.global_position = pos
	_scale_fresh_spawn(enemy)
	if force_elite or _force_elite_spawns or randf() < elite_chance():
		enemy.make_elite()
	return enemy


## Todo el escalado de stats de un spawn regular en un solo lugar: vuelta x
## pseudo-infinito x rampa tardía x HP de co-op x dificultad de la partida
## (más duros Y más ricos: la parte de XP la paga RunState).
func _scale_fresh_spawn(enemy: EnemyBase) -> void:
	var difficulty := (1.0 + RunState.difficulty_bonus) * temp_enemy_buff()
	enemy.apply_tier_scaling(
			lap_hp_factor() * endless_hp_factor() * late_hp_factor() * difficulty
					* _sky_hp_factor()
					* (1.0 + coop_hp_per_extra_player * _coop_extra_alive()),
			lap_damage_factor() * endless_damage_factor() * late_damage_factor()
					* difficulty * _sky_damage_factor(),
			lap_xp_factor() * late_xp_factor())
	# La velocidad es el canal propio de la rampa pseudo-infinita:
	# apply_tier_scaling solo cubre HP, daño y pago.
	enemy.move_speed *= endless_speed_factor()
	_apply_sky_variant(enemy)


func _walkable(pos: Vector3) -> bool:
	if _bounds == null or not _bounds.has_method("is_walkable"):
		return true
	return bool(_bounds.call("is_walkable", Vector2(pos.x, pos.z)))


## Un punto caminable en la banda [min_r, max_r] alrededor de `center`, que
## empieza en `angle` y gira 1/RING_ATTEMPTS de vuelta por intento. Los
## candidatos fuera de la placa se REINTENTAN, no se recortan: recortar X y Z
## por separado juntaría todos los ángulos en la misma esquina junto a un
## borde. El último intento se usa aunque esté bloqueado (los trepadores
## salen), así que un spawn nunca se pierde en silencio.
func _band_position(center: Vector3, min_r: float, max_r: float, angle: float) -> Vector3:
	var pos := center
	for attempt in RING_ATTEMPTS:
		var heading := angle + TAU * float(attempt) / float(RING_ATTEMPTS)
		pos = center + Vector3(cos(heading), 0.0, sin(heading)) * randf_range(min_r, max_r)
		if absf(pos.x) > _arena_half_extent or absf(pos.z) > _arena_half_extent:
			continue
		# El espacio libre es parte de "¿sirve este punto?": girar por la
		# banda es justo como se resuelve un hueco bloqueado.
		if _walkable(pos) and has_player_clearance(pos):
			break
	pos.x = clampf(pos.x, -_arena_half_extent, _arena_half_extent)
	pos.z = clampf(pos.z, -_arena_half_extent, _arena_half_extent)
	return pos


## Baja el punto de spawn hasta la geometría del mundo (capa 1) que haya
## debajo — suelo, roca, plataforma — para que un enemigo nunca nazca dentro
## de un prop. Las copas de árbol no tienen colisión. Si el rayo no toca
## nada, usa la altura del Terrain (o 0 sin Terrain).
func _ground_height(pos: Vector3) -> float:
	# El rayo cubre todo el relieve: desde sobre la cima más alta hasta bajo
	# el fondo más hondo.
	var terrain := Terrain.find(get_tree())
	var top := GROUND_PROBE_HEIGHT
	var bottom := -1.0
	if terrain != null:
		top = terrain.max_height + PROBE_HEADROOM
		bottom = terrain.min_height - PROBE_UNDERSHOOT
	var ray := PhysicsRayQueryParameters3D.create(
			Vector3(pos.x, top, pos.z), Vector3(pos.x, bottom, pos.z), 1)
	# Los raiders comparten la capa 1 con el mundo, así que se excluye a TODA
	# la party: si no, un spawn sobre un compañero usaría su cabeza de suelo.
	var excluded: Array[RID] = []
	for node: Node in Coop.alive_players(get_tree()):
		var body := node as CollisionObject3D
		if body != null:
			excluded.append(body.get_rid())
	ray.exclude = excluded
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		# La altura del TERRAIN, no 0: cero es una altura real en un relieve,
		# y usarla metería cuerpos dentro o debajo de una colina.
		return terrain.height_at(pos.x, pos.z) if terrain != null else 0.0
	var hit_position: Vector3 = hit["position"]
	return hit_position.y
