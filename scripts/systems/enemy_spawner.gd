extends Node3D
## Genera enemigos con un temporizador, en un anillo alrededor de un raider y
## fuera de su vista. Con el reloj de la partida el intervalo se acorta y la
## cantidad por tick crece; la tabla de fases que elige phase_preset solo
## decide QUÉ aparece en cada bioma, y una tirada de élite puede ascender
## cualquier spawn. Todos los relojes son los de RunState (los mismos del HUD
## y de la puerta de etapa), así que rampa, hordas y jefes nunca se desfasan.
## Los enemigos son hijos de este nodo, pero el conteo de vivos sale del grupo
## "enemies" (un cadáver sigue siendo hijo durante su animación de muerte).
## También lleva el horario de jefes: el del bioma en boss_spawn_minute, su
## revancha Ancestral en elder_spawn_minute, spawns más lentos mientras vive
## un jefe y un respiro corto cuando muere.
## Orden del RNG: las tiradas (randf, randf_range) siguen un orden fijo del
## que dependen los soaks con BONK_GAME_SEED; no las reordenes.

## Tabla de fases de esta arena (ver las tablas de abajo).
enum PhasePreset { FOREST, DUNES, MARSH }

## Mezclas de spawn por tiempo. Cada entrada se activa en from_minute y sigue
## hasta que una posterior la reemplaza; los pesos son relativos dentro de la
## fase. Cada clave es un tipo que _scene_for() traduce a su escena exportada.
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

@export var phase_preset: PhasePreset = PhasePreset.FOREST
@export var grunt_scene: PackedScene
@export var skirmisher_scene: PackedScene
@export var tank_scene: PackedScene
@export var sunspitter_scene: PackedScene
@export var burrower_scene: PackedScene
@export var max_active: int = 240
@export_group("Power-ups")
## Probabilidad base (0-1) de que UNA baja suelte un power-up. Diminuta a
## propósito: un power-up tiene que sentirse como un evento. La escala la
## stat powerup_drop_chance del raider (en %) y otra vez un cuerpo shiny.
@export var base_powerup_drop_chance: float = 0.004
@export var shiny_powerup_drop_scale: float = 5.0
@export var powerup_pickup_scene: PackedScene = preload("res://scenes/systems/PowerUpPickup.tscn")
@export_group("Spawn Ring")
@export var min_radius: float = 18.0
@export var max_radius: float = 25.0
@export var spawn_count_multiplier: float = 6.0
## Media placa del suelo menos arena_edge_margin, en metros, para que un spawn
## junto al borde caiga sobre el suelo. Solo es respaldo: en _ready se deriva
## del arena_half_extent del nodo del grupo "arena_bounds" (el scatter).
@export var arena_half_extent: float = 78.0
@export var arena_edge_margin: float = 2.0
## Ningún spawn cae a menos de esta distancia de un raider en pie, en metros.
## Va por DEBAJO de la banda de oleada (surge_min_radius): una horda o una
## jauría shiny sobre un raider tiene que quedar incómodamente cerca, y
## subirlo por encima de surge_min_radius las anularía a ambas. Lo que evita
## es que un cuerpo aparezca encima de otro raider en co-op.
@export var min_player_clearance: float = 5.0
@export_group("Difficulty Ramp")
## Forma de la rampa: el intervalo entre ticks baja interval_shrink_per_minute
## segundos por minuto desde start_interval hasta min_interval, y la cantidad
## por tick sube extra_count_per_minute por minuto (antes de multiplicarse
## por spawn_count_multiplier). Los escalones de cantidad caen en los minutos
## ~2.2 / 4.4 / 6.7.
@export var start_interval: float = 3.0
@export var min_interval: float = 0.35
## Segundos que pierde el intervalo por minuto de partida.
@export var interval_shrink_per_minute: float = 0.32
@export var base_count_per_tick: int = 1
## Enemigos por tick que se suman por minuto (se trunca a entero).
@export var extra_count_per_minute: float = 0.45
@export_group("Late Ramp")
## Escalado sin techo de los spawns REGULARES (los jefes tienen su propia
## escalera): desde late_ramp_start_minute, cada minuto suma este % de HP,
## daño y XP a los spawns nuevos. Hacia el minuto 15 son ~+72% de HP y ~+45%
## de daño. Se acumula con vueltas y élites por apply_tier_scaling.
@export var late_ramp_start_minute: float = 6.0
@export var late_hp_per_minute: float = 0.08
@export var late_damage_per_minute: float = 0.05
## XP extra por minuto pasado el inicio de la rampa (fracción).
@export var late_xp_per_minute: float = 0.065
@export_group("Hordes")
## Minutos de etapa en que llega una horda; tras la última se repite cada
## horde_repeat_minutes. El tamaño escala con el minuto, la dificultad de la
## partida y la party, y llega en oleadas alrededor de un raider al azar.
@export var horde_minutes: Array[float] = [3.0, 7.0, 10.0, 13.0]
@export var horde_repeat_minutes: float = 3.0
@export var horde_base_size: int = 18
@export var horde_size_per_minute: float = 2.0
@export var horde_waves: int = 4
@export var horde_wave_gap: float = 1.6
## Cuántos enemigos puede pasar una horda por encima de max_active.
@export var horde_overflow: int = 120
@export var horde_warning_text: String = "¡Se acerca una horda!"
@export_group("Co-op Scaling")
## Presión extra por cada jugador después del primero: HP para que la
## potencia compartida no derrita la horda y ritmo para que todas las
## pantallas tengan acción. El daño NO se escala a propósito: cuatro cuerpos
## ya reparten los golpes.
@export var coop_hp_per_extra_player: float = 0.5
@export var coop_rate_per_extra_player: float = 0.3
@export var coop_boss_hp_per_extra_player: float = 0.5
@export_group("Elites")
@export var elite_start_minute: float = 3.0
@export var elite_full_minute: float = 12.0
## Probabilidad de élite (0-1) en elite_start_minute y en elite_full_minute,
## con rampa lineal entre ambos. Las élites son la principal fuente de
## curación antes del jefe (sueltan orbes) y los blancos de los packs.
@export var elite_start_chance: float = 0.08
@export var elite_full_chance: float = 0.21
@export_group("Laps and pseudo-infinite (iteration 50)")
## Multiplicador por vuelta completa a la lista de mapas, aplicado a los
## spawns nuevos y a los jefes: la dificultad sale de cuán lejos llegó la
## partida.
@export var lap_hp_mult: float = 1.5
@export var lap_damage_mult: float = 1.3
@export var lap_xp_mult: float = 1.3
## Rampa pseudo-infinita, por minuto pasada la puerta de etapa (fracción).
@export var endless_hp_per_minute: float = 0.15
@export var endless_damage_per_minute: float = 0.10
@export var endless_speed_per_minute: float = 0.04
## Techo del factor de velocidad: más rápido que esto la horda deja atrás al
## raider y el modo deja de ser jugable.
@export var endless_speed_cap: float = 1.8
## Multiplicador del intervalo por minuto (compuesto; nunca baja de
## min_interval, como cualquier otro factor del intervalo).
@export var endless_interval_per_minute: float = 0.85
## Multiplicador del tamaño de horda mientras corre la rampa.
@export var endless_horde_mult: float = 1.5

@export_group("Boss")
@export var boss_scene: PackedScene
## Minuto de etapa en que llega el jefe del bioma y minuto de su revancha
## Ancestral, más fuerte.
@export var boss_spawn_minute: float = 5.0
@export var elder_spawn_minute: float = 11.0
@export var elder_stat_multiplier: float = 1.8
@export var elder_title: String = "Rey Pútrido Ancestral"
## Tras el Ancestral, un jefe vuelve cada boss_repeat_minutes, cada uno
## boss_repeat_growth veces más fuerte que el anterior.
@export var boss_repeat_minutes: float = 4.0
@export var boss_repeat_growth: float = 1.25
## Cómo se arma el título del jefe recurrente con elder_title (%s) y su
## rango (%d). Exportado porque cada arena cambia elder_title.
@export var boss_repeat_title_template: String = "%s Ascendente %d"
## Mientras vive un jefe, el intervalo de los spawns regulares se multiplica
## por esto para que la pelea se lea...
@export var boss_alive_interval_multiplier: float = 1.3
## ...y la muerte de un jefe da un respiro: el intervalo se multiplica por
## esto durante boss_relief_duration segundos.
@export var boss_relief_interval_multiplier: float = 2.0
@export var boss_relief_duration: float = 15.0
@export var boss_warning_text: String = "Una presencia monstruosa se acerca..."
@export_group("Pressure Surge")
## Banda alrededor del punto pedido donde caen los enemigos de una oleada
## (spawn_pressure_burst: hordas, la jauría shiny del WorldDirector y el
## frenesí de la ruleta), en metros.
@export var surge_min_radius: float = 7.0
@export var surge_max_radius: float = 10.0
## Margen sobre max_active para oleadas y packs de élite: sin él, una arena
## saturada respondería a un pack anunciado con cero enemigos y la
## recompensa prometida nunca aparecería.
@export var pressure_overflow: int = 24
@export_group("Sky Events")
## Eclipse: el flujo llega tantas veces más rápido y sus spawns traen tanto
## más HP. Luna de sangre: los spawns pegan tanto más fuerte.
@export var eclipse_rate_multiplier: float = 1.8
@export var eclipse_hp_multiplier: float = 1.25
@export var blood_moon_damage_multiplier: float = 1.4
## Fracción (0-1) de spawns nuevos que llegan como variante del evento.
@export var blood_moon_berserker_chance: float = 0.5
@export var eclipse_shade_chance: float = 0.4

var _spawn_timer: float = 0.0  # arranca vencido: la acción empieza de inmediato
var _boss_spawned: bool = false
var _elder_spawned: bool = false
var _repeat_bosses_spawned: int = 0
## Estado de la horda.
var _hordes_fired: int = 0
var _horde_waves_left: int = 0
var _horde_wave_timer: float = 0.0
var _horde_wave_size: int = 0
## Evento de cielo (WorldDirector): "" | "blood_moon" | "eclipse", y los
## segundos que le quedan.
var _sky_kind: String = ""
var _sky_left: float = 0.0
var _bosses_alive: int = 0
var _relief_timer: float = 0.0

## Último minuto pseudo-infinito ya anunciado, para que el log salga una vez
## por minuto y no una vez por frame.
var _endless_minute_logged: int = -1


## Escalado por VUELTA: cada vuelta completa a la lista de mapas multiplica
## los spawns nuevos. Una vuelta es toda una partida de mapas, así que son
## pasos mucho mayores que la rampa por minuto.
func lap_hp_factor() -> float:
	return pow(lap_hp_mult, float(RunState.lap))


func lap_damage_factor() -> float:
	return pow(lap_damage_mult, float(RunState.lap))


func lap_xp_factor() -> float:
	return pow(lap_xp_mult, float(RunState.lap))


## --- Rampa pseudo-infinita ----------------------------------------------
## Superada la etapa, la party puede quedarse cuanto quiera y el mapa
## responde: por minuto de RunState.pseudo_infinite_time los spawns nuevos
## traen más HP, daño y velocidad, el intervalo se acorta y las hordas
## crecen. La velocidad tiene techo: un cuerpo más rápido que el raider no se
## puede esquivar, y eso no es dificultad sino un muro.
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


## Una línea por minuto mientras corre la rampa, para que un soak pruebe que
## se movió.
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


## Nodo de límites de arena (el scatter): también responde is_walkable()
## para la máscara irregular de la arena.
var _bounds: Node3D = null


func _ready() -> void:
	# Los santuarios llegan al spawner por este grupo, nunca por ruta.
	add_to_group("enemy_spawner")
	_bounds = get_tree().get_first_node_in_group("arena_bounds") as Node3D
	if _bounds != null:
		arena_half_extent = float(_bounds.get("arena_half_extent")) - arena_edge_margin
	if OS.get_environment(POWERUP_BOOST_ENV) == "1":
		_powerup_boost = POWERUP_BOOST_SCALE
		print("EnemySpawner: power-up drop boost x%.0f" % POWERUP_BOOST_SCALE)
	_validate_phase_scenes()


## Todo tipo que la tabla de fases de esta arena puede sacar necesita su
## PackedScene, o esa tirada termina en nada a mitad de partida. Se revisa
## en _ready, donde es barato.
func _validate_phase_scenes() -> void:
	var missing: Array[String] = []
	for phase: Dictionary in active_phases():
		var weights: Dictionary = phase["weights"]
		for kind: String in weights:
			if _scene_for(kind) == null and not missing.has(kind):
				missing.append(kind)
	if not missing.is_empty():
		push_error("EnemySpawner: no scene assigned for spawn kind(s) %s." % [missing])


## Solo lo activa el gancho del harness (force_elite_spawns).
var _force_elite_spawns: bool = false
## Spawns descartados este minuto por falta de espacio, y el minuto que se
## está contando. Se imprime una vez por minuto mientras no sea cero, para
## que un soak vea si el chequeo se está comiendo la rampa.
var _clearance_skips: int = 0
var _clearance_report_minute: int = -1


## True si `pos` queda lo bastante lejos de todo raider en pie. Los cuerpos
## derribados no cuentan: tratarlos como zona prohibida abriría huecos
## muertos en el anillo.
func _has_player_clearance(pos: Vector3) -> bool:
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
func _register_clearance_skip() -> void:
	_clearance_skips += 1
	var minute := floori(_minutes())
	if minute == _clearance_report_minute:
		return
	_clearance_report_minute = minute
	# Log de una línea (convención de RunManager) para los soaks headless.
	print("Spawn skipped: no clearance x%d" % _clearance_skips)


func _walkable(pos: Vector3) -> bool:
	if _bounds == null or not _bounds.has_method("is_walkable"):
		return true
	return bool(_bounds.call("is_walkable", Vector2(pos.x, pos.z)))


## Cuerpos vivos Y peligrosos. Los cadáveres siguen siendo hijos durante su
## animación de muerte y los jefes también son hijos, así que se cuenta el
## grupo "enemies", que un enemigo deja en el instante en que muere.
func _live_enemy_count() -> int:
	return get_tree().get_node_count_in_group(&"enemies")


## Reloj de la partida en minutos. RunState es el dueño del reloj (timer del
## HUD, puerta de etapa, horario de jefes); un segundo reloj aquí empezaría
## más tarde, porque la arena carga después de RunState.reset().
func _minutes() -> float:
	return RunState.run_time / 60.0


func _physics_process(delta: float) -> void:
	_tick_freeze(delta)
	_relief_timer = maxf(_relief_timer - delta, 0.0)
	_temp_buff_left = maxf(_temp_buff_left - delta, 0.0)
	_sky_left = maxf(_sky_left - delta, 0.0)
	if _sky_left <= 0.0 and not _sky_kind.is_empty():
		_sky_kind = ""
	_tick_endless_log()
	_tick_boss_schedule()
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


func current_interval() -> float:
	var interval := maxf(start_interval - interval_shrink_per_minute * _minutes(), min_interval)
	if _bosses_alive > 0:
		interval *= boss_alive_interval_multiplier
	elif _relief_timer > 0.0:
		interval *= boss_relief_interval_multiplier
	if _sky_kind == "eclipse":
		interval /= eclipse_rate_multiplier
	# El apretón pseudo-infinito se compone encima; la presión de la party
	# divide al final, para que una party más grande siga proporcionalmente
	# más rápida.
	interval = maxf(interval * endless_interval_factor(), min_interval)
	return interval / (1.0 + coop_rate_per_extra_player * _coop_extra_alive())


## La party configurada en el lobby: para lo que se dimensiona toda la
## partida (HP de jefe), esté quien esté derribado ahora.
func _coop_extra() -> float:
	return float(maxi(Coop.player_count - 1, 0))


## La party que sigue en pie. Un raider derribado sale del grupo "player"
## hasta que lo reanimen (ver coop.gd), así que la presión por tick (ritmo,
## HP de spawns nuevos, tamaño de horda) sigue a la pelea y no castiga al
## último en pie con la horda de cuatro.
func _coop_extra_alive() -> float:
	return float(maxi(Coop.alive_player_count(get_tree()) - 1, 0))


## Factores de la rampa tardía para un spawn que cae ahora (1.0 antes de la
## rampa).
func late_hp_factor() -> float:
	return 1.0 + late_hp_per_minute * maxf(_minutes() - late_ramp_start_minute, 0.0)


func late_damage_factor() -> float:
	return 1.0 + late_damage_per_minute * maxf(_minutes() - late_ramp_start_minute, 0.0)


func late_xp_factor() -> float:
	return 1.0 + late_xp_per_minute * maxf(_minutes() - late_ramp_start_minute, 0.0)


## --- Eventos de cielo (gancho de grupo del WorldDirector) ------------------

## Luna de sangre: los spawns pegan más fuerte y la mitad llega como
## berserker. Eclipse: flujo más rápido, spawns más duros y algunos llegan
## como sombra. "" lo apaga.
func set_sky_event(kind: String, duration: float) -> void:
	_sky_kind = kind
	_sky_left = duration if not kind.is_empty() else 0.0


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


## --- Hordas -----------------------------------------------------------------

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
			* (1.0 + RunState.difficulty_bonus) * (1.0 + 0.3 * _coop_extra_alive())
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


func current_count_per_tick() -> int:
	var base := base_count_per_tick + int(_minutes() * extra_count_per_minute)
	return maxi(roundi(float(base) * spawn_count_multiplier), 1)


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


## --- Tiempo detenido ----------------------------------------------------
## «Tiempo detenido» congela la horda y deja libre a la party. Lo lleva el
## spawner porque es el nodo que ya conoce a todos los enemigos: cuerpos,
## jefes y proyectiles en vuelo.
##
## Un cuerpo congelado queda en PROCESS_MODE_DISABLED con su velocidad
## guardada y puesta en cero: un CharacterBody3D deshabilitado conserva su
## velocidad, y restaurarla al descongelar evita que un enemigo en carga se
## teletransporte la distancia que "debía".
##
## También queda NO SÓLIDO (collision_layer 0) mientras dura: un cuerpo
## deshabilitado no se puede empujar, y ochenta estatuas alrededor de un
## raider lo dejarían soldado en el sitio. Las armas encuentran blancos por
## el GRUPO "enemies" y una prueba de distancia, nunca por capas de colisión
## (ver WeaponBase.enemies_in_disc), así que un congelado sigue recibiendo
## daño: atraviesas la horda y la sigues golpeando.
##
## Los proyectiles enemigos del pool llevan una BANDERA (EnemyBolt.frozen):
## NodePool guarda is_physics_processing() al liberar y lo restaura al
## adquirir, así que un proyectil congelado con set_physics_process(false)
## volvería inerte del pool para siempre.

## Congelado vivo: id de instancia -> cuerpo, para que un cuerpo liberado a
## mitad del congelado simplemente falte al descongelar.
var _frozen: Dictionary[int, Node3D] = {}
var _frozen_velocity: Dictionary[int, Vector3] = {}
## Capa de colisión de cada cuerpo congelado, restaurada al descongelar (un
## enemigo que quedara en 0 se podría atravesar para siempre).
var _frozen_layer: Dictionary[int, int] = {}
var _freeze_left: float = 0.0


## Gancho de grupo (PowerUps lo llama por "enemy_spawner"). Renueva a la
## más larga de las dos ventanas, como todo efecto temporizado de aquí.
func freeze_enemies(duration: float) -> void:
	_freeze_left = maxf(_freeze_left, duration)
	_freeze_new_bodies()


func is_frozen() -> bool:
	return _freeze_left > 0.0


## Cuerpos congelados ahora mismo (el soak los muestrea).
func frozen_bodies() -> Array[Node3D]:
	var bodies: Array[Node3D] = []
	for id: int in _frozen:
		var body := _frozen[id]
		if is_instance_valid(body):
			bodies.append(body)
	return bodies


func _tick_freeze(delta: float) -> void:
	if _freeze_left <= 0.0:
		return
	_freeze_left -= delta
	if _freeze_left > 0.0:
		# Lo que nace (o se invoca) durante el congelado también se congela:
		# una horda que sigue entrando no es tiempo detenido.
		_freeze_new_bodies()
		return
	_thaw_all()


func _freeze_new_bodies() -> void:
	# "burrowed" no es decorativo: un Duneburrower bajo tierra sale de
	# "enemies" a propósito, y sin este grupo sería el único cuerpo que
	# podría dañar a la party durante un congelado.
	for group: StringName in [&"enemies", &"boss", Duneburrower.BURROWED_GROUP]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body == null or not body.is_inside_tree():
				continue
			var id := body.get_instance_id()
			if _frozen.has(id):
				continue
			_frozen[id] = body
			var character := body as CharacterBody3D
			if character != null:
				_frozen_velocity[id] = character.velocity
				character.velocity = Vector3.ZERO
			var collider := body as CollisionObject3D
			if collider != null:
				_frozen_layer[id] = collider.collision_layer
				collider.collision_layer = 0
			body.process_mode = Node.PROCESS_MODE_DISABLED
	for node: Node in get_tree().get_nodes_in_group(&"enemy_projectiles"):
		node.set("frozen", true)


func _thaw_all() -> void:
	for id: int in _frozen:
		var body := _frozen[id]
		if not is_instance_valid(body):
			continue
		body.process_mode = Node.PROCESS_MODE_INHERIT
		var character := body as CharacterBody3D
		if character != null:
			character.velocity = _frozen_velocity.get(id, Vector3.ZERO)
		var collider := body as CollisionObject3D
		if collider != null and _frozen_layer.has(id):
			collider.collision_layer = _frozen_layer[id]
	_frozen.clear()
	_frozen_velocity.clear()
	_frozen_layer.clear()
	for node: Node in get_tree().get_nodes_in_group(&"enemy_projectiles"):
		node.set("frozen", false)
	get_tree().call_group("hud", "announce", "El tiempo vuelve a correr.")


## --- Drops de power-up ----------------------------------------------------

## True si esta muerte suelta un power-up. `killer` es el raider dueño de la
## tirada (el más cercano, como el pago de puntos), así que su «Fortuna
## menor» es la que mueve la probabilidad. BONK_POWERUP_BOOST multiplica todo
## para los soaks: con 0.4% de base harían falta miles de bajas.
func roll_powerup_drop(killer: Node, shiny: bool) -> bool:
	var chance := base_powerup_drop_chance * _powerup_boost
	var stats := PlayerStats.find_in(killer) if killer != null else null
	if stats != null:
		chance *= 1.0 + stats.powerup_drop_chance / 100.0
	if shiny:
		chance *= shiny_powerup_drop_scale
	return randf() < chance


## Suelta un pickup en `at`. LA puerta de los power-ups en el suelo: el
## avistamiento de la estrella también pasa por aquí, así que el padre de
## etapa y el grupo se escriben una sola vez.
func spawn_powerup_pickup(at: Vector3, powerup_id: String) -> Node3D:
	if powerup_id.is_empty() or powerup_pickup_scene == null:
		return null
	var pickup := powerup_pickup_scene.instantiate() as PowerUpPickup
	if pickup == null:
		return null
	pickup.setup(powerup_id)
	# De alcance de etapa, como todo lo que cae al mundo: el cambio de etapa
	# lo libera junto con el resto en vez de llevárselo.
	RunRoot.stage_parent(get_tree()).add_child(pickup)
	pickup.global_position = at
	print("Power-up dropped: %s" % powerup_id)
	return pickup


## Multiplicador leído una vez de BONK_POWERUP_BOOST (interruptor de prueba;
## 1.0 en una partida normal). Se lee en _ready y no por tirada: esto va en
## el camino de cada muerte.
var _powerup_boost: float = 1.0

const POWERUP_BOOST_ENV := "BONK_POWERUP_BOOST"
## Lo que vale BONK_POWERUP_BOOST=1: un soak de 360 s da un puñado de drops
## sin tapizar el mapa.
const POWERUP_BOOST_SCALE: float = 50.0


## Gancho del harness, por el grupo "enemy_spawner": hace shiny TODOS los
## spawns. Solo pruebas (ArenaProbe con BONK_ELITE_BOOST=1): elite_chance()
## tiene techo ELITE_CHANCE_CAP a propósito y ningún export llega a 1.0.
## Nada del juego lo llama.
func force_elite_spawns(on: bool) -> void:
	_force_elite_spawns = on


## Probabilidad de que un spawn nuevo salga élite: cero antes de
## elite_start_minute, luego una rampa lineal hasta elite_full_minute. La
## dificultad de la partida (altares demoníacos, Tomo del Peligro) la
## multiplica: más élites es amenaza y recompensa a la vez.
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


## Buff temporal de enemigos (el «frenesí» de la ruleta): los spawns nuevos
## escalan HP y daño por `multiplier` durante `duration` segundos. Gancho de
## grupo (enemy_spawner).
var _temp_buff_multiplier: float = 1.0
var _temp_buff_left: float = 0.0


func apply_temp_enemy_buff(multiplier: float, duration: float) -> void:
	# Renueva como EnemyBase.apply_poison: gana el multiplicador más fuerte y
	# el temporizador más largo, así una segunda tirada débil no desarma una
	# primera fuerte.
	var live := _temp_buff_multiplier if _temp_buff_left > 0.0 else 1.0
	_temp_buff_multiplier = maxf(live, maxf(multiplier, 1.0))
	_temp_buff_left = maxf(_temp_buff_left, duration)
	get_tree().call_group("boss_ui", "announce", "¡La horda crece con una fuerza antinatural!")


func temp_enemy_buff() -> float:
	return _temp_buff_multiplier if _temp_buff_left > 0.0 else 1.0


func _scene_for(kind: String) -> PackedScene:
	match kind:
		"skirmisher":
			return skirmisher_scene
		"tank":
			return tank_scene
		"sunspitter":
			return sunspitter_scene
		"burrower":
			return burrower_scene
		_:
			return grunt_scene


func _spawn_one() -> void:
	# Co-op: anillo alrededor de un jugador vivo AL AZAR, para repartir la
	# presión de la horda en una party separada.
	var player := Coop.random_player(get_tree())
	if player == null:
		return
	_make_enemy_at(_ring_position(player))


## Un enemigo, colocado, escalado y con su tirada de élite. `scene_override`
## reemplaza la tirada de la tabla de fases (las invocaciones traen su
## propio tipo). Devuelve null si no hay escena o su raíz no es EnemyBase,
## para que un llamador en bucle salte esa unidad sin perder el resto.
func _make_enemy_at(pos: Vector3, force_elite: bool = false,
		scene_override: PackedScene = null) -> EnemyBase:
	# LA puerta de todo spawn: anillo, hordas, oleadas, invocaciones y packs
	# del WorldDirector pasan por aquí, así que la regla de espacio libre no
	# se le puede olvidar a un llamador nuevo. Los muestreadores de posición
	# ya prefieren puntos libres; esto es lo que pasa cuando no hay ninguno.
	if not _has_player_clearance(pos):
		_register_clearance_skip()
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
	# apply_tier_scaling solo cubre HP, daño y pago, y un cuerpo que además
	# acelera es lo que hace que "quedarse demasiado" se sienta como error.
	enemy.move_speed *= endless_speed_factor()
	_apply_sky_variant(enemy)


## Gancho de invocación para quien llama cuerpos de SU propio tipo, por el
## grupo "enemy_spawner". Coloca una `scene` en cada una de `positions` y
## pasa cada cuerpo por el MISMO escalado que un spawn de anillo, más la
## tirada de élite. Devuelve los cuerpos que de verdad llegaron.
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


## Un enemigo en cada uno de `points`, a ras de suelo y por la misma puerta
## de espacio libre que todo lo demás (lluvia de enemigos y tsunami del
## WorldDirector). Síncrono y con presupuesto, como spawn_pressure_burst: una
## lluvia sin tope sería una horda con pasos extra. Devuelve cuántos cayeron,
## para que el llamador pueda dosificarse. No es spawn_minions: aquel no
## tiene tope a propósito, y el clima siempre debe tenerlo.
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


## Ráfaga de presión (hordas, jauría shiny, frenesí de la ruleta; por el
## grupo "enemy_spawner"): `count` enemigos de la fase actual en anillo
## alrededor de `center`, encima de la cadencia normal pero respetando
## max_active más el margen (pressure_overflow, u horde_overflow si `horde`).
## Aplica la tirada de élite normal; con `force_elites` (pack de élite del
## WorldDirector) todos salen élite. Devuelve cuántos llegaron, para que el
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
		# anillo lejano: un altar junto a un muro debe seguir sintiéndose como
		# "aguanta este punto bajo presión".
		var pos := _band_position(center, surge_min_radius, surge_max_radius, angle)
		pos.y = _ground_height(pos) + SPAWN_GROUND_OFFSET
		if _make_enemy_at(pos, force_elites) != null:
			spawned += 1
	return spawned


## Horario de jefes, sobre RunState.stage_time: cada arena trae su propio
## spawner, así que las banderas empiezan limpias por etapa y el reloj tiene
## que ser el de la etapa, no el de la partida. Cada entrada se dispara una
## vez por etapa.
func _tick_boss_schedule() -> void:
	if boss_scene == null:
		return
	# La bandera solo se marca si el jefe llegó de verdad: _spawn_boss aborta
	# con toda la party derribada (sin ancla de anillo), y un hueco marcado
	# como gastado perdería ese jefe para siempre.
	if not _boss_spawned and RunState.stage_time >= boss_spawn_minute * 60.0:
		_boss_spawned = _spawn_boss(1.0) != null
	if not _elder_spawned and RunState.stage_time >= elder_spawn_minute * 60.0:
		var elder := _spawn_boss(elder_stat_multiplier, elder_title)
		_elder_spawned = elder != null
		if elder != null:
			_watch_stage_boss(elder)
	# Después del Ancestral los jefes siguen volviendo, cada uno más fuerte.
	if _elder_spawned and boss_repeat_minutes > 0.0:
		var due := (elder_spawn_minute
				+ boss_repeat_minutes * float(_repeat_bosses_spawned + 1)) * 60.0
		if RunState.stage_time >= due:
			var rank := _repeat_bosses_spawned + 1
			if _spawn_boss(elder_stat_multiplier * pow(boss_repeat_growth, float(rank)),
					boss_repeat_title_template % [elder_title, rank]) != null:
				_repeat_bosses_spawned = rank


## El Ancestral es EL jefe de etapa: su muerte es la mitad de la puerta de
## etapa. Se ata a esa instancia y no al contador de jefes muertos, porque
## los jefes recurrentes posteriores no deben reabrir la puerta.
func _watch_stage_boss(boss: BossBase) -> void:
	var health := Health.find_in(boss)
	if health == null:
		RunState.stage_boss_dead = true
		return
	health.died.connect(_on_stage_boss_died, CONNECT_ONE_SHOT)


func _on_stage_boss_died() -> void:
	RunState.stage_boss_dead = true
	# Log de una línea (convención de RunManager) para los soaks headless.
	print("Stage boss slain: %s at %.1fs" % [elder_title, RunState.stage_time])


## El jefe que entró a la arena, o null si algo abortó, para que el llamador
## reintente el hueco en otro tick. Devuelve la instancia porque la muerte
## del Ancestral abre la puerta de etapa y el llamador conecta su Health.
func _spawn_boss(stat_multiplier: float, title_override: String = "") -> BossBase:
	var player := Coop.random_player(get_tree())
	if player == null:
		return null
	# Se ubica ANTES de que el jefe exista: el horario solo gasta un hueco si
	# el jefe llegó, así que un anillo sin punto libre reintenta en el
	# próximo tick en vez de anunciar un jefe que nunca vino.
	var at := _ring_position(player)
	if not _has_player_clearance(at):
		_register_clearance_skip()
		return null
	var node := boss_scene.instantiate()
	var boss := node as BossBase
	if boss == null:
		node.free()
		push_warning("EnemySpawner: boss scene root does not extend BossBase.")
		return null
	if not title_override.is_empty():
		# Antes de add_child: el jefe anuncia su título al HUD en _ready.
		boss.boss_title = title_override
	add_child(boss)
	boss.global_position = at
	# Todos los factores entran en UNA llamada a apply_tier, así
	# tier_body_scale se aplica una vez por jefe y un jefe base (todo 1.0)
	# queda exactamente base. Los tres canales son distintos a propósito:
	#   HP     — revancha x vuelta x dificultad x tamaño de party. Un jefe es
	#            una pelea larga, para la party que lo esperó.
	#   daño   — lo mismo SIN la party: cuatro cuerpos ya reparten golpes.
	#   pago   — revancha x vuelta: RunState.difficulty_xp_multiplier() ya
	#            paga la parte de dificultad al recoger las gemas.
	var payout_multiplier := stat_multiplier * lap_xp_factor()
	var damage_multiplier := stat_multiplier * lap_damage_factor() \
			* (1.0 + RunState.difficulty_bonus)
	var hp_multiplier := stat_multiplier * lap_hp_factor() \
			* (1.0 + RunState.difficulty_bonus) \
			* (1.0 + coop_boss_hp_per_extra_player * _coop_extra())
	# is_equal_approx y no "> 1.0": un factor puede quedar legítimamente bajo
	# 1.0 y no debe ignorarse.
	if not (is_equal_approx(hp_multiplier, 1.0) and is_equal_approx(damage_multiplier, 1.0)
			and is_equal_approx(payout_multiplier, 1.0)):
		boss.apply_tier(hp_multiplier, damage_multiplier, payout_multiplier)
	_bosses_alive += 1
	var health := Health.find_in(boss)
	if health != null:
		health.died.connect(_on_boss_died)
	get_tree().call_group("boss_ui", "announce", boss_warning_text)
	# Log de una línea (convención de RunManager) para que los soaks
	# confirmen que el horario de jefes se disparó.
	print("Boss spawned: %s at %.1fs" % [boss.boss_title, RunState.stage_time])
	return boss


func _on_boss_died() -> void:
	_bosses_alive = maxi(_bosses_alive - 1, 0)
	_relief_timer = boss_relief_duration
	# Contador meta para misiones de jefes; se guarda al final de la partida.
	SaveData.bump("bosses_killed")


## Posición del anillo alrededor del jugador, a distancia de spawn y sobre
## el suelo.
func _ring_position(player: Node3D) -> Vector3:
	var pos := _band_position(player.global_position, min_radius, max_radius, randf() * TAU)
	pos.y = _ground_height(pos) + SPAWN_GROUND_OFFSET
	return pos


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
		if absf(pos.x) > arena_half_extent or absf(pos.z) > arena_half_extent:
			continue
		# El espacio libre es parte de "¿sirve este punto?": girar por la
		# banda es justo como se resuelve un hueco bloqueado, y un raider
		# parado en la banda es un hueco bloqueado.
		if _walkable(pos) and _has_player_clearance(pos):
			break
	pos.x = clampf(pos.x, -arena_half_extent, arena_half_extent)
	pos.z = clampf(pos.z, -arena_half_extent, arena_half_extent)
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
