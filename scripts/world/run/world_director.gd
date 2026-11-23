extends Node
## Director del mundo: mantiene viva la arena durante toda la partida.
## Vive en RunSystems.tscn (un solo nodo por partida) y Arena._ready le
## avisa de cada etapa por el grupo "world_director". En cada etapa:
##
## 1. Reparto (on_stage_started, antes de que el scatter ponga sus props):
##    cada interactuable de suelo del grupo "scatter_keepout" (altares, el
##    cofre de suelo, los secretos) se mueve a un punto al azar, para que
##    el mapa no se pueda memorizar. Lo que está sobre una plataforma
##    conserva su altura. Después el hijo StageFixtures pone los objetos
##    de inicio (portales, ruletas, cofres extra, manantiales, vendedores...).
##
## 2. Ritmo por minuto: en cada pulso (cada beat_seconds) salen
##    - un clima asegurado al azar: luna, lluvia o desastre (el hijo Weather,
##      con su WEATHER_CATALOG; si ya hay de los tres, se corta uno);
##    - la tirada independiente de otro clima extra (Weather.roll_extra);
##    - y en horde_and_weather_minutes (2, 4, 6, 8), además, una horda.
##    EVENT_LIBRARY (jauría shiny, estrella) queda guardada y no sale sola.
##
## 3. El portal de salida al superar la etapa, y las balizas de luz.
## Todo punto pasa por la máscara caminable de la arena y una sonda de
## suelo: lo anunciado siempre se puede alcanzar y pisar.
## Modo de proceso pausable: los eventos se congelan con la pausa y las cartas.

const EXIT_PORTAL_SCENE := preload("res://scenes/world/director/ExitPortal.tscn")
const BEACON_SCENE := preload("res://scenes/world/director/Beacon.tscn")
const Beacon := preload("res://scripts/world/run/director/beacon.gd")

## Eventos del mundo guardados para más adelante: hoy no salen solos (peso
## 0 y el pulso por minuto ya no los sortea). Edita aquí el peso, el aviso y
## la baliza de cada uno. Campos:
##   id:           identificador; event_weight_overrides lo usa como clave.
##   weight:       peso relativo del sorteo.
##   method:       se llama con call(row); catalog_lint.gd revisa que exista.
##   announce:     aviso en el HUD (texto del jugador); obligatorio.
##   beacon_color: color de la baliza sobre el evento; sin él no hay baliza.
##   beacon_time:  segundos que arde la baliza; sin él o INF = hasta que el
##                 POI se usa (o hasta el cambio de etapa si no hay POI).
##   cap_group/cap: van juntos: con `cap` o más nodos en el grupo
##                 `cap_group`, el evento pesa 0 y sale otro.
##   log:          línea de log al aparecer, para los soaks (no traducir).
const EVENT_LIBRARY: Array[Dictionary] = [
	{
		"id": "elite_pack", "weight": 0.0, "method": &"_event_elite_pack",
		"announce": "¡Una jauría shiny te huele el rastro!",
	},
	{
		# La estrella solo aparece con este evento: no cae de enemigos ni se
		# vende. La baliza marca dónde se vio, no dónde está: se mueve.
		"id": "star_sighting", "weight": 0.0, "method": &"_event_star",
		"announce": "Algo brillante cruza el campo...",
		"beacon_color": Color(1.0, 0.9, 0.35), "beacon_time": 12.0,
	},
]



## Una baliza viva: el nodo del pilar, el POI que señala y los segundos
## que le quedan. Se apaga junto con su POI: un pilar de 22 m sobre un
## altar ya usado llama a cruzar el mapa por nada.
class TimedBeacon:
	var node: Node3D
	## POI que señala; null si no hay nada que vigilar (la estrella se mueve).
	var poi: Node = null
	var time_left: float = 0.0
	## Solo el cofre de suministros se hunde al apagarse la luz: se puede
	## perder a propósito. Los demás POI se quedan; solo se apaga la luz.
	var sink_poi: bool = false

	func _init(p_node: Node3D, p_poi: Node, p_time_left: float,
			p_sink_poi: bool = false) -> void:
		node = p_node
		poi = p_poi
		time_left = p_time_left
		sink_poi = p_sink_poi

	## Verdadero mientras el POI siga valiendo el viaje: existe y, si tiene
	## `available`, sigue en true.
	func poi_worth_showing() -> bool:
		if poi == null:
			return true
		if not is_instance_valid(poi) or poi.is_queued_for_deletion():
			return false
		var available: Variant = poi.get("available")
		return not (available is bool) or bool(available)


@export_group("Reparto de POI")
## Mueve los POI de suelo a puntos al azar en cada etapa.
@export var shuffle_layout: bool = true
## Distancia mínima (metros) de un POI movido al punto de aparición.
@export var min_distance_from_spawn: float = 16.0
## Distancia mínima (metros) entre dos POI.
@export var min_distance_between: float = 18.0
## Distancia mínima (metros) a los puntos fijos: plataformas y rocas.
@export var min_distance_from_keepouts: float = 12.0
## Margen (metros) con el borde de la arena para todo lo que pone el director: POI, eventos, clima (lluvia, tsunami, meteoritos) y el portal de salida.
@export var bounds_margin: float = 14.0
## Puntos que se prueban para cada altar, ruleta y cofre al empezar la etapa; se queda con el más lejano a lo ya puesto (más = reparto más parejo, carga un poco más lenta).
@export var spread_tries: int = 32
## Cuánto más se separan dos POI del MISMO tipo que dos distintos: la distancia entre iguales cuenta x esto (0.4 = los iguales quedan ~2.5 veces más lejos).
@export_range(0.05, 1.0) var same_kind_spread: float = 0.4

@export_group("Ritmo por minuto")
## Si hay un pulso por minuto (clima asegurado, clima extra, una fila de EVENT_LIBRARY y, en sus minutos, horda). Apagado: no sale nada de eso.
@export var beat_enabled: bool = true
## Segundos entre pulsos (el primero sale a estos segundos de empezar la etapa).
@export var beat_seconds: float = 60.0
## Minutos de la etapa en que el pulso trae además una horda (en los demás no hay horda).
@export var horde_and_weather_minutes: Array[int] = [2, 4, 6, 8]

@export_group("Eventos")
## Activa los eventos del mundo y el clima.
@export var events_enabled: bool = true
## Distancia mínima (metros) de un evento a un jugador vivo al azar.
@export var event_min_distance: float = 25.0
## Distancia máxima (metros) de un evento a un jugador vivo al azar.
@export var event_max_distance: float = 45.0
## Enemigos shiny de la jauría de élite.
@export var elite_pack_size: int = 3
## Pesos que reemplazan los de EVENT_LIBRARY, por id de evento; 0 quita el
## evento. Vale para todas las arenas: el director es uno por partida.
@export var event_weight_overrides: Dictionary[String, float] = {}

@export_group("Portal de salida")
## Distancia mínima (metros) del portal de salida al jugador más cercano.
@export var exit_portal_min_distance: float = 40.0
## Aviso en el HUD cuando se abre el portal de salida.
@export var exit_portal_announce: String = "Se abrió el portal de salida — crúzalo cuando quieras"

## El clima activo, o vacío: {id, group, time_left}. Vive en el nodo
## Weather; scripts/ui/game/hud/weather_badge.gd y el probe
## lo leen aquí con get("active_weather").
var active_weather: Dictionary:
	get:
		return _weather.active_weather if _weather != null else {}
## Todos los climas vivos a la vez (luna, lluvia y desastre pueden coincidir);
## el chip del HUD los lee con get("active_weathers").
var active_weathers: Array[Dictionary]:
	get:
		var none: Array[Dictionary] = []
		return _weather.active_weathers if _weather != null else none

## Reparto de la etapa actual: arena, máscara, puntos ocupados y
## muestreos. Uno nuevo por etapa; entre etapas, uno vacío.
var _layout: StageLayout = null
## Un portal de salida por etapa.
var _exit_portal_spawned: bool = false
## Segundos hasta el próximo pulso por minuto, y pulsos ya dados en la etapa.
var _beat_timer: float = 0.0
var _beats_fired: int = 0
## Balizas vivas (portal de salida, estrella...).
var _beacons: Array[TimedBeacon] = []

## El clima (RunSystems.tscn > WorldDirector > Weather).
@onready var _weather: WeatherDirector = $Weather
## Los objetos de inicio (RunSystems.tscn > WorldDirector > StageFixtures).
@onready var _fixtures: StageFixtures = $StageFixtures

func _ready() -> void:
	_set_layout(_new_layout(null))
	add_to_group("world_director")


func _physics_process(delta: float) -> void:
	if not RunState.run_active:
		# La partida acaba de terminar (derrota o extracción) y la pantalla
		# final deja la arena viva y en pausa: el clima se detiene aquí, o el
		# HUD quedaría desplazado y el descuento dorado seguiría activo.
		_weather.stop_weather()
		return
	_tick_exit_portal()
	_tick_beacons(delta)
	if not events_enabled:
		return
	_weather.tick(delta)
	_tick_beat(delta)


## Pulso por minuto: horda o clima al azar; el primero nunca es horda.
func _tick_beat(delta: float) -> void:
	# Con un jefe en pie el reloj de la partida se detiene, y el pulso también.
	if not beat_enabled or RunState.boss_fight_active:
		return
	_beat_timer -= delta
	if _beat_timer > 0.0:
		return
	_beat_timer = beat_seconds
	_beats_fired += 1
	print("Beat %d at %.1fs" % [_beats_fired, RunState.stage_time])
	# El HUD junta los avisos de este pulso y los muestra en una sola lista.
	var tree := get_tree()
	tree.call_group("hud", "begin_event_batch")
	tree.call_group("hud", "event_batch_kind", "weather")
	# Clima asegurado: si los tres canales están ocupados, se corta uno y
	# empieza otro.
	if _weather.start_random().is_empty():
		_weather.start_sky_event(WeatherCatalog.roll_any())
	# Aparte, la tirada independiente de otro clima en un canal libre.
	_weather.roll_extra()
	if horde_and_weather_minutes.has(_beats_fired):
		tree.call_group("hud", "event_batch_kind", "horde")
		_start_horde()
	tree.call_group("hud", "end_event_batch")


func _start_horde() -> bool:
	var spawner := get_tree().get_first_node_in_group(&"enemy_spawner") as EnemySpawner
	return spawner != null and spawner.start_horde()


## Inicio de etapa: Arena._ready lo llama por el grupo "world_director".
## El director dura toda la partida, así que aquí olvida todo lo que
## guardaba de la arena anterior.
## Orden dentro de la etapa: el _enter_tree del scatter ya construyó la
## máscara; esto toma la arena, mueve los POI de suelo y pone los objetos
## de inicio; después Arena llama a scatter.place_props(), cuyas zonas
## vedadas ven así las posiciones nuevas.
func on_stage_started(arena: Node3D) -> void:
	set_physics_process(true)
	_set_layout(_new_layout(arena))
	# El clima olvida las luces de la arena anterior y vuelve a buscarlas.
	_weather.begin_stage(_layout)
	_beacons.clear()
	_beat_timer = beat_seconds
	_beats_fired = 0
	# La niebla y el mapa son por etapa. Se reinician aquí y no con la
	# señal stage_changed: la etapa 0 también pasa por aquí.
	var fog := FogOfWar.find(get_tree())
	if fog != null:
		fog.reset_for_stage(arena)
	get_tree().call_group("hud", "on_stage_started", arena)
	_exit_portal_spawned = false
	if shuffle_layout:
		_layout.shuffle_ground_interactables()
	# Objetos de inicio (nodo StageFixtures), después de mover los POI: su
	# orden interno es parte del sorteo.
	_fixtures.place(_layout)


## Fin de etapa: RunRoot lo llama antes de liberar la arena. Para el
## clima, devuelve el cielo y libera las balizas.
func on_stage_ended() -> void:
	# Deja de procesar durante el cambio: este nodo sobrevive a la arena y
	# un evento disparado ahora caería en un mapa a punto de liberarse.
	set_physics_process(false)
	# Primero el stop() del clima y el cielo de vuelta: una lluvia dorada
	# sin cerrar dejaría el x2 de puntos y el descuento vivos después de la
	# arena, y un tween sobre el sol liberado sería un error.
	_weather.end_stage()
	# Libera los NODOS de las balizas, no solo la lista: el barrido de etapa
	# corre antes de liberar la arena y exige beacons=0.
	for entry: TimedBeacon in _beacons:
		_free_beacon(entry.node)
	_beacons.clear()
	_set_layout(_new_layout(null))


## Balizas vivas, para el barrido de etapa (RunRoot).
func beacon_count() -> int:
	return _beacons.size()


## --- puertas del clima -----------------------------------------------------
## El clima vive en el nodo Weather; estas puertas siguen aquí porque otros
## nodos llegan por el grupo "world_director": enemy_loot.gd,
## arena_probe.gd, scripts/ui/game/hud/weather_badge.gd y
## scripts/enemies/mythos/hell_transformation.gd.

## La fila de WEATHER_CATALOG con ese id, o vacío (arena_probe.gd la usa).
static func weather_row(id: String) -> Dictionary:
	return WeatherDirector.weather_row(id)


## FUERZA un clima: detiene el que haya y empieza aunque no haya pasado la
## pausa (el probe, BONK_WEATHER_NOW).
func start_sky_event(kind: String) -> void:
	_weather.start_sky_event(kind)


## Un charco de ácido durante la lluvia radiactiva (EnemyBase al morir).
func spawn_acid_pool(at: Vector3) -> void:
	_weather.spawn_acid_pool(at)


## Verdadero mientras `id` sea el clima activo.
func is_weather_active(id: String) -> bool:
	return _weather.is_weather_active(id)


## La arena cambió de cielo (HellTransformation): los climas vuelven desde
## ahora a este sol y ambiente. Devuelve el Environment propio de la arena.
func rebase_sky(sun_color: Color, sun_energy: float, ambient_color: Color,
		ambient_energy: float) -> Environment:
	return _weather.rebase_sky(sun_color, sun_energy, ambient_color, ambient_energy)


## El cielo «original» de la arena ahora, sin el tinte del clima en curso
## (sun_color, sun_energy, ambient_color, ambient_energy): lo pide quien va
## a cambiar el cielo por un rato y devolverlo con rebase_sky().
func sky_base() -> Dictionary:
	return _weather.sky_base()


## Un StageLayout para `arena` (null = vacío) con las distancias del reparto.
func _new_layout(arena: Node3D) -> StageLayout:
	var layout := StageLayout.new(self, arena)
	layout.bounds_margin = bounds_margin
	layout.min_distance_from_spawn = min_distance_from_spawn
	layout.min_distance_between = min_distance_between
	layout.min_distance_from_keepouts = min_distance_from_keepouts
	layout.spread_tries = spread_tries
	layout.same_kind_spread = same_kind_spread
	return layout


## Cambia el layout del director y el del clima, que comparte el mismo.
func _set_layout(layout: StageLayout) -> void:
	_layout = layout
	_weather.layout = layout


## Levanta el portal de salida el primer frame en que la etapa cuenta como
## superada (RunState.stage_cleared). Se consulta cada frame, igual que la
## meta en RunManager.
func _tick_exit_portal() -> void:
	if _exit_portal_spawned or not RunState.stage_cleared:
		return
	_exit_portal_spawned = true
	var portal := EXIT_PORTAL_SCENE.instantiate() as ExitPortal
	_layout.stage_parent().add_child(portal)
	portal.global_position = _layout.exit_portal_point(exit_portal_min_distance)
	# Su baliza arde hasta que el grupo lo cruza: poi_worth_showing() la
	# apaga cuando el portal se consume.
	_raise_beacon(portal.global_position, portal.portal_color, portal, INF)
	get_tree().call_group("boss_ui", "track_objective", portal)
	_announce(exit_portal_announce)
	# Línea de log para los soaks headless.
	print("Exit portal opened at %.1fs" % RunState.run_time)


## --- eventos ----------------------------------------------------------------

## Peso de una fila de EVENT_LIBRARY ahora mismo. Un peso 0 saca el evento
## del sorteo (sale otro): así un evento que no puede ocurrir no gasta la
## ventana.
func _event_weight(row: Dictionary) -> float:
	if row.has("cap_group") \
			and get_tree().get_node_count_in_group(row["cap_group"]) >= int(row["cap"]):
		return 0.0
	return float(event_weight_overrides.get(row["id"], row["weight"]))


## Sortea una fila de EVENT_LIBRARY por peso y llama a su `method`. Hoy
## nadie la llama: las filas están guardadas para más adelante.
func _fire_random_event() -> void:
	var total := 0.0
	for row: Dictionary in EVENT_LIBRARY:
		total += maxf(_event_weight(row), 0.0)
	if total <= 0.0:
		return
	var roll := randf() * total
	var chosen: Dictionary = {}
	for row: Dictionary in EVENT_LIBRARY:
		var weight := _event_weight(row)
		# Las filas con peso 0 se saltan: una tirada justo en el borde no
		# puede elegir un evento muerto.
		if weight <= 0.0:
			continue
		chosen = row
		roll -= weight
		if roll <= 0.0:
			break
	if chosen.is_empty():
		return
	print("World event: %s at %.1fs" % [String(chosen["id"]), RunState.stage_time])
	call(chosen["method"], chosen)


## Avistamiento de estrella: lo más raro del mapa cruza el campo. Sale por
## la puerta de power-ups del spawner, que ya pone el padre, el grupo y la
## línea "Power-up dropped:".
func _event_star(row: Dictionary) -> void:
	var spawner := get_tree().get_first_node_in_group("enemy_spawner")
	if spawner == null or not spawner.has_method("spawn_powerup_pickup"):
		return
	var at := _event_point()
	if spawner.call("spawn_powerup_pickup", at + Vector3.UP * 0.6, "star") == null:
		return
	_raise_row_beacon(row, at, null)
	_announce(String(row["announce"]))


## Jauría de élite alrededor de un jugador al azar. El aviso promete una
## recompensa, así que solo sale si el spawner tuvo sitio bajo su tope.
func _event_elite_pack(row: Dictionary) -> void:
	var anchor := Coop.random_player(get_tree())
	if anchor == null:
		return
	# Por grupo y no con call_group: hace falta la respuesta del spawner.
	var spawner := get_tree().get_first_node_in_group("enemy_spawner")
	if spawner == null or not spawner.has_method("spawn_pressure_burst"):
		return
	var spawned: int = spawner.call(
			"spawn_pressure_burst", anchor.global_position, elite_pack_size, true)
	if spawned <= 0:
		return
	_announce(String(row["announce"]))


## Un punto para un evento: lejos de un jugador vivo al azar, caminable y
## apoyado en el suelo (ver StageLayout.event_point).
func _event_point() -> Vector3:
	return _layout.event_point(event_min_distance, event_max_distance)


## La baliza de una fila de EVENT_LIBRARY: su beacon_color (o `color`, si
## se da) y su beacon_time (INF si falta). Sin color no hay baliza.
func _raise_row_beacon(row: Dictionary, at: Vector3, poi: Node, sink_poi: bool = false,
		color: Variant = null) -> void:
	if color == null:
		color = row.get("beacon_color")
	if color == null:
		return
	_raise_beacon(at, color as Color, poi, float(row.get("beacon_time", INF)), sink_poi)


## Levanta una baliza sobre `at` y la anota. `poi` es lo que señala (null
## si no hay nada que vigilar); `sink_poi` hunde el cofre al apagarse.
func _raise_beacon(at: Vector3, color: Color, poi: Node, seconds: float,
		sink_poi: bool = false) -> void:
	_beacons.append(TimedBeacon.new(_spawn_beacon(at, color), poi, seconds, sink_poi))


## Una pasada por las balizas vivas: se apaga la que señala un POI usado o
## desaparecido, o la que agotó su tiempo. Solo el cofre de suministros se
## hunde con ella.
func _tick_beacons(delta: float) -> void:
	for i in range(_beacons.size() - 1, -1, -1):
		var entry := _beacons[i]
		if not entry.poi_worth_showing():
			_free_beacon(entry.node)
			_beacons.remove_at(i)
			continue
		entry.time_left -= delta
		if entry.time_left > 0.0:
			continue
		_free_beacon(entry.node)
		if entry.sink_poi and entry.poi is Chest:
			_despawn_chest(entry.poi as Chest)
		_beacons.remove_at(i)


## El cofre de suministros que nadie abrió se hunde. Puede que ya no exista
## (un cofre abierto se hunde y se libera solo).
func _despawn_chest(chest: Chest) -> void:
	if chest == null or not is_instance_valid(chest) or chest.is_queued_for_deletion():
		return
	# Un cofre perdido no cuenta para la misión chests_opened.
	chest.meta_stat_id = ""
	chest.consume()
	# El cofre anima con su propio tween, no con uno del director: un cambio
	# de etapa a mitad liberaría el cofre bajo un tween ajeno todavía
	# animándolo. Duración y bajada: grupo «Cofre perdido» del cofre.
	chest.sink_lost()


## Levanta una baliza (Beacon.tscn) del color dado sobre `at`.
func _spawn_beacon(at: Vector3, color: Color) -> Node3D:
	var beacon := BEACON_SCENE.instantiate() as Beacon
	beacon.color = color
	_layout.stage_parent().add_child(beacon)
	beacon.global_position = at
	return beacon


func _free_beacon(beacon: Node3D) -> void:
	if beacon != null and is_instance_valid(beacon):
		beacon.queue_free()


## Muestra un aviso centrado en el HUD (grupo "boss_ui").
func _announce(message: String) -> void:
	get_tree().call_group("boss_ui", "announce", message)
