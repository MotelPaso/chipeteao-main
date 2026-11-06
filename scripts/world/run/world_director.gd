extends Node
## Director del mundo: mantiene viva la arena durante toda la partida.
## Vive en RunSystems.tscn (un solo nodo por partida) y Arena._ready le
## avisa de cada etapa por el grupo "world_director". En cada etapa:
##
## 1. Reparto (on_stage_started, antes de que el scatter ponga sus props):
##    cada interactuable de suelo del grupo "scatter_keepout" (altares, el
##    cofre de suelo, los secretos) se mueve a un punto al azar, para que
##    el mapa no se pueda memorizar. Lo que está sobre una plataforma
##    conserva su altura. Después pone los objetos de inicio.
##
## 2. Eventos con aviso en el HUD desde first_event_at hasta el final: cada
##    cierto tiempo sale una fila de EVENT_LIBRARY y puede empezar un clima
##    de WEATHER_CATALOG.
##
## 3. El portal de salida al superar la etapa, y las balizas de luz.
## Todo punto pasa por la máscara caminable de la arena y una sonda de
## suelo: lo anunciado siempre se puede alcanzar y pisar.
## Modo de proceso pausable: los eventos se congelan con la pausa y las cartas.

const CHEST_SCENE := preload("res://scenes/world/chests/Chest.tscn")
const XP_GEM_SCENE := preload("res://scenes/systems/XpGem.tscn")
const CHARGE_SHRINE_SCENE := preload("res://scenes/world/shrines/ChargeShrine.tscn")
const CURSE_SHRINE_SCENE := preload("res://scenes/world/shrines/CurseShrine.tscn")
const SPRING_SHRINE_SCENE := preload("res://scenes/world/shrines/SpringShrine.tscn")
const ROULETTE_SHRINE_SCENE := preload("res://scenes/world/shrines/RouletteShrine.tscn")
const EVENT_ALTAR_SCENE := preload("res://scenes/world/shrines/EventAltar.tscn")
const LUCKY_BLOCK_SCENE := preload("res://scenes/world/chests/LuckyBlock.tscn")
const PET_BOX_SCENE := preload("res://scenes/world/PetBox.tscn")
const VENDOR_SCENE := preload("res://scenes/world/Vendor.tscn")
const PortalShrineScript := preload("res://scripts/world/interactables/portal_shrine.gd")

## Eventos del mundo, una fila por evento. `weight` es el peso relativo
## del sorteo; `method` es el método que lo ejecuta (se llama con call() y
## catalog_lint.gd revisa que exista).
const EVENT_LIBRARY: Array[Dictionary] = [
	{"id": "supply_chest", "weight": 1.0, "method": &"_event_supply_chest"},
	{"id": "elite_pack", "weight": 1.0, "method": &"_event_elite_pack"},
	{"id": "essence_rift", "weight": 1.0, "method": &"_event_essence_rift"},
	# `altar` marca las filas con la cadencia de altares: su peso sube con
	# el minuto y vale 0 mientras haya demasiados altares sin usar.
	{"id": "charge_altar", "weight": 1.6, "method": &"_event_charge_altar", "altar": true},
	{"id": "demonic_altar", "weight": 0.5, "method": &"_event_demonic_altar", "altar": true},
	{"id": "spring", "weight": 0.7, "method": &"_event_spring"},
	# La estrella solo aparece con este evento: no cae de enemigos ni se vende.
	{"id": "star_sighting", "weight": 0.15, "method": &"_event_star"},
	# Puestos y caja de mascota, sin `altar`: si contaran en el tope de
	# altares, dejarían el mapa sin altares.
	{"id": "vendor", "weight": 0.8, "method": &"_event_vendor"},
	{"id": "pet_box", "weight": 0.35, "method": &"_event_pet_box"},
	# El altar de evento tampoco lleva `altar`: no es de carga ni demoníaco.
	{"id": "event_altar", "weight": 0.4, "method": &"_event_event_altar"},
	{"id": "lucky_block", "weight": 0.25, "method": &"_event_lucky_block"},
]

## Segundos que dura la baliza de la estrella. Marca dónde se vio, no
## dónde está: la estrella se mueve y hay que buscarla.
const STAR_BEACON_TIME: float = 12.0
## Intentos de muestreo para un punto libre de POI, y para el anillo de un
## punto de evento antes de recurrir al muestreo de inicio.
const CLEAR_POINT_ATTEMPTS: int = 60
const EVENT_POINT_ATTEMPTS: int = 24
## Altura de la sonda de suelo cuando no hay terreno contra el que medir.
const GROUND_PROBE_HEIGHT: float = 20.0
## Con terreno, la sonda empieza esto sobre su punto más alto (cabe una
## meseta sobre una loma) y termina esto bajo el más bajo (metros).
const PROBE_HEADROOM: float = 30.0
const PROBE_UNDERSHOOT: float = 2.0
## Solo se usa si portal_pair_colors queda vacío en el Inspector.
const DEFAULT_PORTAL_COLORS: Array[Color] = [Color(0.5, 0.9, 1.0)]


## Una baliza viva: el nodo del pilar, el POI que señala y los segundos
## que le quedan. Se apaga junto con su POI: un pilar de 22 m sobre un
## altar ya usado llama a cruzar el mapa por nada.
class TimedBeacon:
	var node: Node3D
	## POI que señala; null en la grieta de esencia, cuyas gemas tienen su
	## propia duración y no dejan nada que vigilar.
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


## Un POI del reparto puesto por encima de esta altura (metros) está sobre
## una plataforma y conserva su y; el resto se apoya en el relieve.
const POI_PLATFORM_Y: float = 0.5

@export_group("Layout Shuffle")
## Mueve los POI de suelo a puntos al azar en cada etapa.
@export var shuffle_layout: bool = true
## Distancia mínima (metros) de un POI movido al punto de aparición.
@export var min_distance_from_spawn: float = 16.0
## Distancia mínima (metros) entre dos POI.
@export var min_distance_between: float = 18.0
## Distancia mínima (metros) a los puntos fijos: plataformas y rocas.
@export var min_distance_from_keepouts: float = 12.0
## Margen (metros) que los POI dejan con el borde de la arena.
@export var bounds_margin: float = 14.0

@export_group("Events")
## Activa los eventos del mundo y el clima.
@export var events_enabled: bool = true
## Segundos desde el inicio de la etapa hasta el primer evento.
@export var first_event_at: float = 75.0
## Pausa mínima y máxima entre eventos (segundos), antes de acortarse con el minuto.
@export var event_gap_min: float = 50.0
@export var event_gap_max: float = 75.0
## Pausa más corta posible entre eventos (segundos), aunque la partida avance.
@export var event_gap_floor: float = 20.0
## Cuánto se acorta la pausa por minuto de partida: pausa / (1 + esto x minutos).
@export var event_gap_decay_per_minute: float = 0.18
## Distancia mínima y máxima (metros) de un evento a un jugador vivo al azar.
@export var event_min_distance: float = 25.0
@export var event_max_distance: float = 45.0
## Segundos que dura el cofre de suministros (y su baliza) antes de hundirse.
@export var chest_lifetime: float = 40.0
## Suerte extra del cofre de suministros al sortear su rareza.
@export var chest_luck_bonus: float = 0.4
## Enemigos shiny de la jauría de élite.
@export var elite_pack_size: int = 3
## Gemas de XP que suelta la grieta de esencia.
@export var rift_gem_count: int = 10
## XP de cada gema de la grieta (una gema normal vale 1).
@export var rift_gem_value: int = 3
## Segundos que dura la baliza de la grieta; las gemas tienen su propia duración.
@export var rift_beacon_lifetime: float = 30.0
## Pesos que reemplazan los de EVENT_LIBRARY, por id de evento; 0 quita el
## evento. Vale para todas las arenas: el director es uno por partida.
@export var event_weight_overrides: Dictionary[String, float] = {}
@export_group("Altars (iteration 47)")
## Cuánto sube el peso de los altares por minuto: peso x (1 + esto x minutos).
@export var altar_weight_per_minute: float = 0.25
## Tope de ese multiplicador del peso de los altares.
@export var altar_weight_max_scale: float = 3.0
## Puestos de venta vivos a la vez, como máximo.
@export var max_vendors: int = 2
## Probabilidad (0-1) de que la etapa empiece con una caja de mascota.
@export var start_pet_box_chance: float = 0.5
## Probabilidad (0-1) de que la etapa empiece con un altar de evento.
@export var start_event_altar_chance: float = 0.5
## Probabilidad (0-1) de que la etapa empiece con un bloque de la suerte.
@export var lucky_block_start_chance: float = 0.5
## Altares sin usar permitidos a la vez al empezar, contando los de la escena.
@export var altar_cap_base: int = 3
## Cada tantos minutos se permite un altar sin usar más.
@export var altar_cap_minutes: float = 3.0
## Probabilidad (0-1) de que cada cofre de inicio (de la escena o extra) sea gratis.
@export var free_start_chest_chance: float = 0.15
@export_group("Exit portal (iteration 49)")
## Distancia mínima (metros) del portal de salida al jugador más cercano.
@export var exit_portal_min_distance: float = 40.0
## Portales al inicio de la etapa; van en pares, así que conviene un número par.
@export var portal_count: int = 4
## Ruletas al inicio de la etapa.
@export var roulette_count: int = 1
## Colores de los portales: los portales se crean de dos en dos y cada dos
## toman el siguiente color de la lista.
@export var portal_pair_colors: Array[Color] = [
	Color(0.5, 0.9, 1.0), Color(0.95, 0.6, 1.0), Color(0.6, 1.0, 0.55), Color(1.0, 0.85, 0.4)]
@export_group("Sky events (iteration 42)")
## Probabilidad (0-1) de luna en cada evento, pasada la pausa sky_event_min_gap.
@export var sky_event_chance: float = 0.18
## Probabilidad extra de luna por cada altar demoníaco usado.
@export var sky_event_chance_per_demonic: float = 0.08
## Segundos sin clima tras terminar uno; vale para lunas, lluvias y desastres.
@export var sky_event_min_gap: float = 150.0
## XP extra (porcentaje) que da la luna llena a todo el grupo.
@export var full_moon_xp_bonus: float = 50.0
## Suerte extra que da la luna llena a todo el grupo.
@export var full_moon_luck_bonus: float = 30.0
## Probabilidad (0-1) de desastre en cada evento; se tira antes que la
## lluvia y la luna. Los pactos demoníacos la suben.
@export var disaster_chance: float = 0.08
## Probabilidad (0-1) de lluvia en cada evento; se tira después del desastre.
@export var rain_chance: float = 0.12
## Duraciones (segundos) que reemplazan las de WEATHER_CATALOG, por id de
## clima. Vale para todas las arenas: el director es uno por partida.
@export var weather_duration_overrides: Dictionary[String, float] = {}
@export_group("Rains (iteration 55)")
## Segundos entre tandas de la lluvia de enemigos.
@export var enemy_rain_interval: float = 1.5
## Enemigos mínimos y máximos por tanda.
@export var enemy_rain_min_drops: int = 3
@export var enemy_rain_max_drops: int = 6
## Distancia mínima y máxima (metros) de cada caída al jugador.
@export var enemy_rain_min_distance: float = 12.0
@export var enemy_rain_max_distance: float = 25.0
## Segundos entre charcos de ácido durante la lluvia radiactiva.
@export var acid_pool_interval: float = 2.0
## Radio (metros) de cada charco de ácido.
@export var acid_pool_radius: float = 2.0
## Segundos que dura cada charco.
@export var acid_pool_lifetime: float = 6.0
## Distancia máxima (metros) de un charco al jugador.
@export var acid_pool_spawn_range: float = 20.0
## Multiplicador de puntos durante la lluvia dorada.
@export var golden_points_multiplier: float = 2.0
## Factor de precio durante la lluvia dorada (0.5 = mitad de precio).
@export var golden_price_discount: float = 0.5
@export_group("Disasters (iteration 55)")
## Enemigos de la ola del tsunami al empezar la etapa.
@export var tsunami_base: int = 40
## Enemigos extra de la ola por minuto de etapa.
@export var tsunami_per_minute: int = 4
## Distancia mínima y máxima (metros) de la ola al jugador.
@export var tsunami_arc_min: float = 40.0
@export var tsunami_arc_max: float = 60.0
## Segundos entre sacudidas de cámara del terremoto.
@export var earthquake_shake_interval: float = 0.5
## Fuerza de cada sacudida de cámara.
@export var earthquake_shake_strength: float = 0.25
## Cuánto se desplaza el HUD durante el terremoto (píxeles).
@export var earthquake_hud_amplitude: float = 14.0
## Vibraciones por segundo del HUD durante el terremoto.
@export var earthquake_hud_hz: float = 20.0
## Segundos entre nubes de polvo sobre cada jugador.
@export var earthquake_dust_interval: float = 3.0
## Segundos entre meteoritos.
@export var meteor_interval: float = 0.8
## Distancia máxima (metros) de un meteorito al jugador.
@export var meteor_range: float = 20.0
## Radio (metros) de cada impacto.
@export var meteor_radius: float = 3.0
## Segundos de aviso en el suelo antes del impacto.
@export var meteor_telegraph: float = 1.2
## Daño de cada impacto a los jugadores; crece con el minuto.
@export var meteor_damage: float = 40.0
## Multiplicador del daño del impacto a los enemigos.
@export var meteor_enemy_scale: float = 3.0

## Semiancho BRUTO de la arena, publicado por el nodo "arena_bounds" (el
## scatter); bounds_margin se resta en cada uso, así que no puede venir ya
## con el margen descontado.
var _arena_half_extent: float = 80.0
## El nodo de límites de la arena: tamaño y máscara caminable.
var _bounds: Node3D = null
## Arena de la etapa actual; todo lo que pone el director cuelga de ella
## (ver _stage_parent).
var _arena: Node3D = null
## Un portal de salida por etapa.
var _exit_portal_spawned: bool = false
var _event_timer: float = 0.0
## Puntos ya ocupados por un POI (movido o creado), para que lo siguiente
## guarde su distancia.
var _placed_points: Array[Vector2] = []
var _anchor_points: Array[Vector2] = []
## Los POI movidos, en el mismo orden que _placed_points, para liberar el
## punto de los que el inicio irregular quita.
var _placed_pois: Array[Node3D] = []
## Balizas vivas (cofres de suministros, altares, manantiales, grietas...).
var _beacons: Array[TimedBeacon] = []
## El clima activo, o vacío: {id, group, time_left}. Uno solo a la vez
## entre los tres grupos: por eso es un solo canal y no tres temporizadores.
var active_weather: Dictionary = {}
## Datos propios del clima activo (start/tick/stop); se vacía al empezar
## uno, así ningún clima lee lo que dejó el anterior.
var _weather_state: Dictionary = {}
var _sky_gap_left: float = 0.0
var _sun: DirectionalLight3D = null
var _sun_color: Color = Color.WHITE
var _sun_energy: float = 1.0
var _environment: Environment = null
var _ambient_color: Color = Color.WHITE
var _ambient_energy: float = 1.0
## El ÚNICO tween que escribe el sol y el ambiente: dos a la vez escriben
## las mismas propiedades cada frame y gana el más largo.
var _sky_tween: Tween = null


func _ready() -> void:
	add_to_group("world_director")


## Inicio de etapa: Arena._ready lo llama por el grupo "world_director".
## El director dura toda la partida, así que aquí olvida todo lo que
## guardaba de la arena anterior.
## Orden dentro de la etapa: el _enter_tree del scatter ya construyó la
## máscara; esto toma la arena, mueve los POI de suelo y pone los objetos
## de inicio; después Arena llama a scatter.place_props(), cuyas zonas
## vedadas ven así las posiciones nuevas.
func on_stage_started(arena: Node3D) -> void:
	set_physics_process(true)
	_arena = arena
	# Vuelve a buscar las luces de la arena nueva. _cache_lights() no hace
	# nada mientras _sun tenga valor: sin estas líneas la etapa 2 teñiría
	# el sol ya liberado de la etapa 1 y ningún evento de cielo se vería.
	_kill_sky_tween()
	_sun = null
	_environment = null
	_sun_color = Color.WHITE
	_sun_energy = 1.0
	_ambient_color = Color.WHITE
	_ambient_energy = 1.0
	active_weather = {}
	_weather_state = {}
	_sky_gap_left = 0.0
	_bounds = null
	for node: Node in get_tree().get_nodes_in_group("arena_bounds"):
		var bounds := node as Node3D
		if bounds != null and arena.is_ancestor_of(bounds):
			_bounds = bounds
			_arena_half_extent = float(bounds.get("arena_half_extent"))
			break
	_placed_points.clear()
	_anchor_points.clear()
	_placed_pois.clear()
	_beacons.clear()
	_event_timer = first_event_at
	# La niebla y el mapa son por etapa. Se reinician aquí y no con la
	# señal stage_changed: la etapa 0 también pasa por aquí.
	var fog := FogOfWar.find(get_tree())
	if fog != null:
		fog.reset_for_stage(arena)
	get_tree().call_group("hud", "on_stage_started", arena)
	_exit_portal_spawned = false
	if shuffle_layout:
		_shuffle_ground_interactables()
	# El inicio irregular va ANTES de los objetos de inicio: quita POI de
	# la escena y sus puntos tienen que quedar libres para los portales y
	# la ruleta.
	_randomize_starting_pois()
	# Objetos de inicio. Este orden es parte del sorteo: no cambiarlo.
	_spawn_portals()
	_spawn_roulettes()
	_spawn_start_pet_boxes()
	_spawn_start_event_altars()
	_spawn_start_lucky_blocks()


## 0-1 cajas de mascota al inicio de la etapa: una mascota tiene que
## sentirse como algo que el mapa ofrece, no algo que siempre está.
## Con probabilidad 0 no se tira ningún dado: el RNG de la partida es uno
## solo y un dado de más aquí mueve todo lo que se sortea después.
func _spawn_start_pet_boxes() -> void:
	if start_pet_box_chance <= 0.0 or randf() >= start_pet_box_chance:
		return
	_spawn_pet_box(_claim_clear_point())


## 0-1 altares de evento al inicio de la etapa, como la caja de mascota.
func _spawn_start_event_altars() -> void:
	# Con probabilidad 0 no se tira ningún dado (ver la caja de mascota):
	# cambiaría dónde caen los portales, las ruletas y los POI movidos.
	if start_event_altar_chance <= 0.0 or randf() >= start_event_altar_chance:
		return
	_spawn_event_altar(_claim_clear_point())


## 0-1 bloques de la suerte al inicio de la etapa; con probabilidad 0 no
## se tira ningún dado.
func _spawn_start_lucky_blocks() -> void:
	if lucky_block_start_chance <= 0.0 or randf() >= lucky_block_start_chance:
		return
	_spawn_lucky_block(_claim_clear_point())


## Fin de etapa: RunRoot lo llama antes de liberar la arena. Para el
## clima, devuelve el cielo y libera las balizas.
func on_stage_ended() -> void:
	# Deja de procesar durante el cambio: este nodo sobrevive a la arena y
	# un evento disparado ahora caería en un mapa a punto de liberarse.
	set_physics_process(false)
	# Primero el stop() del clima: una lluvia dorada sin cerrar dejaría el
	# x2 de puntos y el descuento vivos después de la arena.
	_stop_weather(false)
	_snap_sky_back()
	# Libera los NODOS de las balizas, no solo la lista: el barrido de etapa
	# corre antes de liberar la arena y exige beacons=0.
	for entry: TimedBeacon in _beacons:
		_free_beacon(entry.node)
	_beacons.clear()
	_placed_points.clear()
	_anchor_points.clear()
	_placed_pois.clear()
	_arena = null
	_bounds = null


## Balizas vivas, para el barrido de etapa (RunRoot).
func beacon_count() -> int:
	return _beacons.size()


## Padre de todo lo que pone el director: la arena actual, así un cambio
## de etapa se lo lleva todo. Sin arena (carreras en el cambio) usa la de
## RunRoot, y en último caso este nodo, para no fallar.
func _stage_parent() -> Node:
	if _arena != null and is_instance_valid(_arena):
		return _arena
	var root := get_tree().get_first_node_in_group("run_root")
	if root != null and root.has_method("arena_root"):
		var arena: Variant = root.call("arena_root")
		if arena is Node3D and is_instance_valid(arena):
			return arena
	return self


## La partida puede terminar en medio de un clima: se detiene y el cielo
## vuelve en seco, para que el tinte no pase a la partida siguiente.
func _exit_tree() -> void:
	_stop_weather(false)
	_snap_sky_back()


## Devuelve la luz original de la arena AL INSTANTE (sin tween). Se usa
## cuando la arena se va: un tween sobre un sol liberado es un error.
func _snap_sky_back() -> void:
	_kill_sky_tween()
	if _sun != null and is_instance_valid(_sun):
		_sun.light_color = _sun_color
		_sun.light_energy = _sun_energy
	if _environment != null:
		_environment.ambient_light_color = _ambient_color
		_environment.ambient_light_energy = _ambient_energy


@export_group("Irregular start (iteration 44)")
## Probabilidad (0-1) de quitar cada cofre o altar de la escena en esta etapa.
@export var poi_skip_chance: float = 0.3
## Cofres extra al empezar la etapa: un número al azar entre mínimo y máximo.
@export var extra_start_chests_min: int = 0
@export var extra_start_chests_max: int = 2


## Inicio irregular: quita al azar cofres y altares de la escena (siempre
## queda el primer cofre de suelo), hace gratis algunos cofres y suma
## cofres extra.
func _randomize_starting_pois() -> void:
	var removed := 0
	var chests_kept := 0
	var freebies := 0
	for node: Node in get_tree().get_nodes_in_group("scatter_keepout"):
		if node is Chest or node is ChargeShrine or node is GreedShrine:
			if node is Chest and chests_kept == 0:
				chests_kept += 1  # el primer cofre de suelo siempre se queda
				if _make_start_chest_free(node as Chest):
					freebies += 1
				continue
			if randf() < poi_skip_chance:
				node.queue_free()
				removed += 1
			elif node is Chest:
				chests_kept += 1
				if _make_start_chest_free(node as Chest):
					freebies += 1
	_refresh_placed_points()
	var extra := randi_range(extra_start_chests_min, extra_start_chests_max)
	for i in extra:
		var chest := CHEST_SCENE.instantiate() as Chest
		# ANTES de add_child: el cofre elige su tinte y su texto en _ready.
		if randf() < free_start_chest_chance:
			chest.free_open = true
			freebies += 1
		_stage_parent().add_child(chest)
		chest.global_position = _claim_clear_point()
	print("Start layout: %d POI(s) skipped, %d extra chest(s), %d free" % [
			removed, extra, freebies])


## Hace gratis un cofre de la escena que ya pasó su _ready. Devuelve true si cambió.
func _make_start_chest_free(chest: Chest) -> bool:
	if chest == null or randf() >= free_start_chest_chance:
		return false
	chest.make_free()
	return true


func _physics_process(delta: float) -> void:
	if not RunState.run_active:
		# La partida acaba de terminar (derrota o extracción) y la pantalla
		# final deja la arena viva y en pausa: el clima se detiene aquí, o el
		# HUD quedaría desplazado y el descuento dorado seguiría activo.
		_stop_weather(false)
		return
	_tick_exit_portal()
	_tick_beacons(delta)
	if not events_enabled:
		return
	_tick_weather(delta)
	_event_timer -= delta
	if _event_timer > 0.0:
		return
	_event_timer = _next_event_gap()
	_fire_random_event()
	_maybe_weather()


## Levanta el portal de salida el primer frame en que la etapa cuenta como
## superada (RunState.stage_cleared). Se consulta cada frame, igual que la
## meta en RunManager.
func _tick_exit_portal() -> void:
	if _exit_portal_spawned or not RunState.stage_cleared:
		return
	_exit_portal_spawned = true
	var portal := ExitPortal.new()
	portal.name = "ExitPortal"
	_stage_parent().add_child(portal)
	portal.global_position = _exit_portal_point()
	# Su baliza arde hasta que el grupo lo cruza: poi_worth_showing() la
	# apaga cuando el portal se consume.
	_beacons.append(TimedBeacon.new(
			_spawn_beacon(portal.global_position, portal.portal_color), portal, INF))
	get_tree().call_group("boss_ui", "track_objective", portal)
	_announce("Se abrió el portal de salida — crúzalo cuando quieras")
	# Línea de log para los soaks headless.
	print("Exit portal opened at %.1fs" % RunState.run_time)


## Un punto libre y caminable, al menos a exit_portal_min_distance de todo
## jugador: la salida es un destino, no algo que se pisa al terminar.
## Muestrea el cuadrado de la arena (no un anillo) y se queda con el punto
## más lejano.
func _exit_portal_point() -> Vector3:
	var limit := _arena_half_extent - bounds_margin
	var best := Vector3.ZERO
	var best_distance := -1.0
	for attempt in CLEAR_POINT_ATTEMPTS:
		var candidate := Vector3(randf_range(-limit, limit), 0.0, randf_range(-limit, limit))
		if not _walkable(candidate):
			continue
		var nearest := _distance_to_nearest_player(candidate)
		if nearest > best_distance:
			best_distance = nearest
			best = candidate
		if nearest >= exit_portal_min_distance:
			break
	if best_distance < 0.0:
		# Todas las muestras cayeron en una pared de la máscara: se usa el
		# muestreo que sabe dónde están las celdas abiertas.
		var point := _random_walkable_point()
		best = Vector3(point.x, 0.0, point.y)
	best.y = _ground_height(best)
	return best


## Distancia (metros) al jugador vivo más cercano; 0 si no hay ninguno.
func _distance_to_nearest_player(at: Vector3) -> float:
	var nearest := INF
	for node: Node in Coop.alive_players(get_tree()):
		var body := node as Node3D
		if body != null:
			nearest = minf(nearest, at.distance_to(body.global_position))
	return 0.0 if nearest == INF else nearest


## Minutos de partida; los usan la cadencia de altares y la pausa entre eventos.
func _minutes() -> float:
	return RunState.run_time / 60.0


## Segundos hasta el próximo evento: la ventana base, acortada con el
## minuto, nunca por debajo de event_gap_floor.
func _next_event_gap() -> float:
	var raw := randf_range(event_gap_min, event_gap_max)
	return maxf(raw / (1.0 + event_gap_decay_per_minute * _minutes()), event_gap_floor)


## Altares sin usar que hay ahora, vengan de la escena o del director
## (los dos están en el grupo "altars").
func _unspent_altars() -> int:
	var count := 0
	for node: Node in get_tree().get_nodes_in_group("altars"):
		var available: Variant = node.get("available")
		if (available is bool and bool(available)) and not node.is_queued_for_deletion():
			count += 1
	return count


## Tope de altares sin usar: altar_cap_base + minutos / altar_cap_minutes.
func _altar_cap() -> int:
	return altar_cap_base + floori(_minutes() / maxf(altar_cap_minutes, 0.001))


## --- máscara de la arena ----------------------------------------------------

func _walkable_xz(xz: Vector2) -> bool:
	if _bounds == null or not _bounds.has_method("is_walkable"):
		return true
	return bool(_bounds.call("is_walkable", xz))


func _walkable(pos: Vector3) -> bool:
	return _walkable_xz(Vector2(pos.x, pos.z))


## Último recurso cuando el muestreo no encuentra nada: el muestreo de la
## propia máscara, que sabe dónde están las celdas abiertas.
func _random_walkable_point() -> Vector2:
	if _bounds != null and _bounds.has_method("random_walkable_point"):
		var point: Variant = _bounds.call("random_walkable_point", bounds_margin)
		if point is Vector2:
			return point
	return Vector2.ZERO


## Altura del suelo (capa 1) bajo un punto: un POI bajo una meseta
## quedaría enterrado y su Area3D no vería al jugador que subió.
func _ground_height(pos: Vector3) -> float:
	var space := get_tree().root.world_3d.direct_space_state
	# El rayo cubre TODO el relieve: desde sobre la meseta más alta hasta
	# bajo la hondonada más honda.
	var terrain := Terrain.find(get_tree())
	var top := GROUND_PROBE_HEIGHT
	var bottom := -1.0
	if terrain != null:
		top = terrain.max_height + PROBE_HEADROOM
		bottom = terrain.min_height - PROBE_UNDERSHOOT
	var ray := PhysicsRayQueryParameters3D.create(
			Vector3(pos.x, top, pos.z), Vector3(pos.x, bottom, pos.z), 1)
	# Los jugadores comparten la capa 1 con el mundo: una cabeza no es suelo.
	var excluded: Array[RID] = []
	for node: Node in Coop.alive_players(get_tree()):
		var body := node as CollisionObject3D
		if body != null:
			excluded.append(body.get_rid())
	ray.exclude = excluded
	var hit := space.intersect_ray(ray)
	if hit.is_empty():
		# Nada bajo el punto: la altura del TERRENO, no 0 (0 también es una
		# altura real del relieve y enterraría o haría flotar el POI).
		return terrain.height_at(pos.x, pos.z) if terrain != null else 0.0
	var hit_position: Vector3 = hit["position"]
	return hit_position.y


## --- reparto ----------------------------------------------------------------

## Mueve cada interactuable de "scatter_keepout" a un punto libre; el resto
## del grupo (plataformas, rocas) queda como obstáculo fijo.
func _shuffle_ground_interactables() -> void:
	var movable: Array[Node3D] = []
	var anchors: Array[Vector2] = []
	for node: Node in get_tree().get_nodes_in_group("scatter_keepout"):
		var spot := node as Node3D
		if spot == null:
			continue
		if spot is Interactable:
			movable.append(spot)
		else:
			# Plataformas y grupos de rocas: obstáculos fijos que evitar.
			anchors.append(Vector2(spot.global_position.x, spot.global_position.z))
	var placed: Array[Vector2] = []
	var limit := _arena_half_extent - bounds_margin
	for poi: Node3D in movable:
		var spot_xz := _find_clear_point(limit, placed, anchors)
		placed.append(spot_xz)
		# Los POI de suelo se apoyan en el relieve del punto nuevo; los que
		# están sobre una plataforma (y > POI_PLATFORM_Y) conservan su
		# altura, porque la plataforma no se mueve y el terreno bajo ella
		# es plano.
		var authored_y := poi.global_position.y
		var new_y := authored_y if authored_y > POI_PLATFORM_Y else _terrain_height(spot_xz)
		poi.global_position = Vector3(spot_xz.x, new_y, spot_xz.y)
	_placed_points = placed
	_placed_pois = movable
	_anchor_points = anchors


## Rehace _placed_points con los POI que siguen en pie, para que un punto
## liberado por el inicio irregular no reserve espacio alrededor de nada.
func _refresh_placed_points() -> void:
	var points: Array[Vector2] = []
	for poi: Node3D in _placed_pois:
		if is_instance_valid(poi) and not poi.is_queued_for_deletion():
			points.append(Vector2(poi.global_position.x, poi.global_position.z))
	_placed_points = points


## Un punto libre nuevo para algo que se crea durante la etapa; queda
## anotado para los siguientes.
func _claim_clear_point() -> Vector3:
	var spot := _find_clear_point(_arena_half_extent - bounds_margin, _placed_points, _anchor_points)
	_placed_points.append(spot)
	return Vector3(spot.x, _terrain_height(spot), spot.y)


## Altura del terreno en un punto, o 0 sin terreno. Para colocar algo en
## el suelo sin el rayo, que también vería los props encima.
func _terrain_height(xz: Vector2) -> float:
	var terrain := Terrain.find(get_tree())
	return terrain.height_at(xz.x, xz.y) if terrain != null else 0.0


## --- objetos de inicio ------------------------------------------------------

## Portales en pares al azar. Los colores se asignan de dos en dos por
## orden de creación y los pares se forman después de mezclar: el color
## no indica cuál es la pareja.
func _spawn_portals() -> void:
	var count := portal_count - (portal_count % 2)
	# Sin colores, el índice del par sería un módulo por cero.
	var colors := portal_pair_colors if not portal_pair_colors.is_empty() \
			else DEFAULT_PORTAL_COLORS
	var portals: Array = []
	for i in count:
		var portal: Interactable = PortalShrineScript.new()
		portal.name = "Portal%d" % (i + 1)
		portal.set("pair_color", colors[(i / 2) % colors.size()])
		_stage_parent().add_child(portal)
		portal.global_position = _claim_clear_point()
		portals.append(portal)
	portals.shuffle()
	for i in range(0, portals.size() - 1, 2):
		portals[i].set("twin", portals[i + 1])
		portals[i + 1].set("twin", portals[i])
	if count > 0:
		print("Portals placed: %d (%d pairs)" % [count, count / 2])


func _spawn_roulettes() -> void:
	for i in roulette_count:
		var wheel := ROULETTE_SHRINE_SCENE.instantiate() as Node3D
		_stage_parent().add_child(wheel)
		wheel.global_position = _claim_clear_point()


## Busca al azar un punto dentro de +-limit que cumpla todas las
## distancias; si se acaban los intentos devuelve el mejor candidato visto,
## así un mapa lleno empeora en vez de colgarse.
func _find_clear_point(limit: float, placed: Array[Vector2],
		anchors: Array[Vector2]) -> Vector2:
	var best := Vector2.ZERO
	var best_score := -INF
	for attempt in CLEAR_POINT_ATTEMPTS:
		var candidate := Vector2(randf_range(-limit, limit), randf_range(-limit, limit))
		# Nunca en una celda bloqueada de la máscara.
		if not _walkable_xz(candidate):
			continue
		var clearance := candidate.length() - min_distance_from_spawn
		for other: Vector2 in placed:
			clearance = minf(clearance, candidate.distance_to(other) - min_distance_between)
		for anchor: Vector2 in anchors:
			clearance = minf(clearance,
					candidate.distance_to(anchor) - min_distance_from_keepouts)
		if clearance >= 0.0:
			return candidate
		if clearance > best_score:
			best_score = clearance
			best = candidate
	if best_score == -INF:
		# Ningún candidato era caminable y `best` sigue en (0,0), el punto
		# de aparición: se pide a la máscara una celda abierta de verdad.
		return _random_walkable_point()
	return best


## --- eventos ----------------------------------------------------------------

## Peso de una fila de EVENT_LIBRARY ahora mismo. Un peso 0 saca el evento
## del sorteo (sale otro): así un evento que no puede ocurrir no gasta la
## ventana. Los altares pesan más con el minuto y valen 0 mientras haya
## demasiados sin usar.
func _event_weight(row: Dictionary) -> float:
	var weight := float(event_weight_overrides.get(row["id"], row["weight"]))
	# Un solo manantial en el mapa.
	if String(row["id"]) == "spring" \
			and get_tree().get_node_count_in_group(&"springs") > 0:
		return 0.0
	# Como mucho max_vendors puestos a la vez.
	if String(row["id"]) == "vendor" \
			and get_tree().get_node_count_in_group(&"vendors") >= max_vendors:
		return 0.0
	if not bool(row.get("altar", false)) or weight <= 0.0:
		return weight
	if _unspent_altars() >= _altar_cap():
		return 0.0
	return weight * minf(1.0 + altar_weight_per_minute * _minutes(), altar_weight_max_scale)


## Sortea una fila de EVENT_LIBRARY por peso y llama a su método.
func _fire_random_event() -> void:
	var total := 0.0
	for row: Dictionary in EVENT_LIBRARY:
		total += maxf(_event_weight(row), 0.0)
	if total <= 0.0:
		return
	var roll := randf() * total
	var chosen: StringName = &""
	for row: Dictionary in EVENT_LIBRARY:
		var weight := _event_weight(row)
		# Las filas con peso 0 se saltan: una tirada justo en el borde no
		# puede elegir un evento muerto.
		if weight <= 0.0:
			continue
		chosen = row["method"]
		roll -= weight
		if roll <= 0.0:
			break
	if chosen.is_empty():
		return
	call(chosen)


func _event_charge_altar() -> void:
	_event_altar(CHARGE_SHRINE_SCENE, "Se alza un altar de carga — párate en su anillo")


func _event_demonic_altar() -> void:
	_event_altar(CURSE_SHRINE_SCENE, "Un obelisco demoníaco sale del suelo a zarpazos...")


## Altar de carga o demoníaco lejos de un jugador. No caduca, así que su
## baliza tampoco: arde hasta que el altar se usa.
func _event_altar(scene: PackedScene, message: String) -> void:
	var altar := scene.instantiate() as Node3D
	_stage_parent().add_child(altar)
	altar.global_position = _event_point()
	var color := Color(1.0, 0.35, 0.3) if scene == CURSE_SHRINE_SCENE \
			else Color(0.45, 0.85, 1.0)
	_beacons.append(TimedBeacon.new(
			_spawn_beacon(altar.global_position, color), altar, INF))
	_announce(message)
	# Línea de log para los soaks headless.
	print("Altar placed: %s" % ("demonic" if scene == CURSE_SHRINE_SCENE else "charge"))


## El único manantial. Como un altar: se queda hasta que alguien bebe, y
## su baliza arde hasta entonces.
func _event_spring() -> void:
	var spring := SPRING_SHRINE_SCENE.instantiate() as Node3D
	_stage_parent().add_child(spring)
	spring.global_position = _event_point()
	_beacons.append(TimedBeacon.new(
			_spawn_beacon(spring.global_position, Color(0.4, 0.8, 1.0)),
			spring, INF))
	_announce("Un manantial brota en algún lugar del campo...")


## Llega un puesto. El TIPO se sortea aquí y no se nombra en el aviso ni
## en la baliza: ir a ver cuál es, es el evento.
func _event_vendor() -> void:
	var vendor := VENDOR_SCENE.instantiate() as Node3D
	var row: Dictionary = Vendor.VENDOR_LIBRARY[randi() % Vendor.VENDOR_LIBRARY.size()]
	# ANTES de entrar al árbol: Vendor._ready lo lee para elegir su texto,
	# su color y la figura tras el mostrador.
	vendor.set("kind", String(row.id))
	_stage_parent().add_child(vendor)
	vendor.global_position = _event_point()
	# Como un altar, la baliza arde hasta que el puesto se va.
	_beacons.append(TimedBeacon.new(
			_spawn_beacon(vendor.global_position, row.get("color", Color.WHITE)),
			vendor, INF))
	_announce("¡Llega un vendedor!")
	print("Vendor arrived: %s" % String(row.id))


## Un bloque de la suerte. Más raro que un altar porque siempre paga algo bueno.
func _event_lucky_block() -> void:
	_spawn_lucky_block(_event_point())
	_announce("Un bloque dorado aparece en algún lugar...")


func _spawn_lucky_block(at: Vector3) -> Node3D:
	var block := LUCKY_BLOCK_SCENE.instantiate() as Node3D
	_stage_parent().add_child(block)
	block.global_position = at
	return block


## El altar de evento: gratis, de un uso, e invoca un clima sorpresa.
func _event_event_altar() -> void:
	_spawn_event_altar(_event_point())
	_announce("Un cristal de tormenta se alza en el campo...")


func _spawn_event_altar(at: Vector3) -> Node3D:
	var altar := EVENT_ALTAR_SCENE.instantiate() as Node3D
	_stage_parent().add_child(altar)
	altar.global_position = at
	return altar


## Una caja de mascota, gratis y de un uso. Más rara que un puesto: una
## mascota cambia más la partida y no cuesta nada.
func _event_pet_box() -> void:
	_spawn_pet_box(_event_point())
	_announce("Una caja con una huella aparece en el campo...")


func _spawn_pet_box(at: Vector3) -> Node3D:
	var box := PET_BOX_SCENE.instantiate() as Node3D
	_stage_parent().add_child(box)
	box.global_position = at
	return box


## Avistamiento de estrella: lo más raro del mapa cruza el campo. Sale por
## la puerta de power-ups del spawner, que ya pone el padre, el grupo y la
## línea "Power-up dropped:".
func _event_star() -> void:
	var spawner := get_tree().get_first_node_in_group("enemy_spawner")
	if spawner == null or not spawner.has_method("spawn_powerup_pickup"):
		return
	var at := _event_point()
	if spawner.call("spawn_powerup_pickup", at + Vector3.UP * 0.6, "star") == null:
		return
	_beacons.append(TimedBeacon.new(
			_spawn_beacon(at, Color(1.0, 0.9, 0.35)), null, STAR_BEACON_TIME))
	_announce("Algo brillante cruza el campo...")


## Un punto lejos de un jugador vivo al azar: dentro de la franja de la
## arena, en una celda CAMINABLE y apoyado en lo que haya. Un evento dentro
## de una pared de la máscara gastaría su ventana sin que nadie llegue.
func _event_point() -> Vector3:
	var anchor := Coop.random_player(get_tree())
	var origin := anchor.global_position if anchor != null else Vector3.ZERO
	var limit := _arena_half_extent - bounds_margin
	var pos := Vector3.ZERO
	var found := false
	for attempt in EVENT_POINT_ATTEMPTS:
		var angle := randf() * TAU
		pos = origin + Vector3(cos(angle), 0.0, sin(angle)) \
				* randf_range(event_min_distance, event_max_distance)
		pos.x = clampf(pos.x, -limit, limit)
		pos.z = clampf(pos.z, -limit, limit)
		if _walkable(pos):
			found = true
			break
	if not found:
		# Todo el anillo alrededor del jugador está tapado: se usa el
		# muestreo de inicio, que respeta la máscara.
		pos = _claim_clear_point()
	pos.y = _ground_height(pos)
	return pos


## Cofre de suministros: nunca común (mínimo Raro y con suerte extra), y se
## hunde si nadie lo abre antes de que se apague su baliza.
func _event_supply_chest() -> void:
	var chest := CHEST_SCENE.instantiate() as Chest
	chest.min_rarity = "Rare"
	chest.luck_bonus = chest_luck_bonus
	_stage_parent().add_child(chest)
	chest.global_position = _event_point()
	_beacons.append(TimedBeacon.new(
			_spawn_beacon(chest.global_position, Color(1.0, 0.82, 0.3)),
			chest, chest_lifetime, true))
	_announce("Un cofre de suministros zumba en algún lugar del campo...")


## Jauría de élite alrededor de un jugador al azar. El aviso promete una
## recompensa, así que solo sale si el spawner tuvo sitio bajo su tope.
func _event_elite_pack() -> void:
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
	_announce("¡Una jauría shiny te huele el rastro!")


## Grieta de esencia: un círculo de gemas de XP y un orbe de vida.
func _event_essence_rift() -> void:
	var center := _event_point()
	for i in rift_gem_count:
		var gem := Pools.acquire_scene(XP_GEM_SCENE) as XpGem
		if gem == null:
			break
		gem.xp_value = rift_gem_value
		var angle := TAU * float(i) / float(rift_gem_count)
		gem.global_position = center + Vector3(cos(angle), 0.0, sin(angle)) \
				* randf_range(0.6, 2.6) + Vector3.UP * 0.6
	if not HealthOrb.at_soft_cap(get_tree()):
		var orb := Pools.acquire_scene(Pools.HEALTH_ORB_SCENE) as HealthOrb
		if orb != null:
			orb.global_position = center + Vector3.UP * 0.6
	# Las gemas tienen su propia duración; la baliza se apaga antes y no
	# tiene POI que vigilar.
	_beacons.append(TimedBeacon.new(
			_spawn_beacon(center, Color(0.35, 0.95, 0.6)), null, rift_beacon_lifetime))
	_announce("Se abre una grieta de esencia...")


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
	# El tween es del COFRE, no del director: un cambio de etapa dentro de
	# los 0.4 s liberaría el cofre bajo un tween ajeno todavía animándolo.
	var tween := chest.create_tween()
	tween.tween_property(chest, "scale", Vector3.ONE * 0.05, 0.4) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(chest.queue_free)


## Pilar de luz alto y sin sombreado que se ve desde toda la arena, con un
## pulso suave para que se lea como invitación y no como amenaza.
func _spawn_beacon(at: Vector3, color: Color) -> Node3D:
	var beacon := Node3D.new()
	_stage_parent().add_child(beacon)
	beacon.global_position = at
	var pillar := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.55
	mesh.bottom_radius = 0.25
	mesh.height = 22.0
	# Teselado explícito: 16 lados bastan para que la tapa de 0.55 m se vea
	# redonda, y los anillos solo subdividen un lado recto.
	mesh.radial_segments = 16
	mesh.rings = 0
	pillar.mesh = mesh
	pillar.position.y = 11.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(color.r, color.g, color.b, 0.35)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.6
	pillar.material_override = material
	beacon.add_child(pillar)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 2.4
	light.omni_range = 9.0
	light.position.y = 1.6
	beacon.add_child(light)
	var pulse := beacon.create_tween().set_loops()
	pulse.tween_property(pillar, "scale", Vector3(1.25, 1.0, 1.25), 0.8) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(pillar, "scale", Vector3.ONE, 0.8) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return beacon


## --- clima ------------------------------------------------------------------
## UN canal para lunas, lluvias y desastres: `active_weather` guarda como
## mucho una fila, así que nunca se solapan.
##
## En el código esto es WEATHER, nunca "event": EVENT_LIBRARY es la tabla
## de eventos de POI. Para el jugador la palabra sigue siendo «evento».
##
## Campos de cada fila:
##   id/group:   identificador y grupo: moon | rain | disaster.
##   weight:     peso del sorteo DENTRO de su grupo.
##   duration:   segundos, antes de weather_duration_overrides y, en lunas
##               y lluvias, de RunState.sky_duration_multiplier. Los
##               desastres no se alargan con los pactos.
##   start/tick/stop: métodos que se llaman con call(); tick y stop pueden
##               ir vacíos. catalog_lint.gd revisa que existan.
##   follow_up:  la fila que empieza en cuanto esta termina, sin pausa
##               (las lunas malas -> luna llena; las dos lluvias -> lluvia
##               dorada, el premio por aguantar la mala).
##   follow_up_only: nunca sale por sorteo, solo como follow_up.
const WEATHER_CATALOG: Array[Dictionary] = [
	{
		"id": "blood_moon", "group": "moon", "weight": 1.0, "duration": 45.0,
		"start": &"_weather_start_blood_moon", "tick": &"", "stop": &"",
		"follow_up": "full_moon",
	},
	{
		"id": "eclipse", "group": "moon", "weight": 1.0, "duration": 45.0,
		"start": &"_weather_start_eclipse", "tick": &"", "stop": &"",
		"follow_up": "full_moon",
	},
	{
		"id": "full_moon", "group": "moon", "weight": 1.0, "duration": 40.0,
		"start": &"_weather_start_full_moon", "tick": &"", "stop": &"",
		"follow_up_only": true,
	},
	{
		"id": "enemy_rain", "group": "rain", "weight": 1.0, "duration": 35.0,
		"start": &"_weather_start_enemy_rain", "tick": &"_weather_tick_enemy_rain",
		"stop": &"", "follow_up": "golden_rain",
	},
	{
		"id": "radioactive_rain", "group": "rain", "weight": 1.0, "duration": 40.0,
		"start": &"_weather_start_radioactive_rain",
		"tick": &"_weather_tick_radioactive_rain",
		"stop": &"_weather_stop_radioactive_rain", "follow_up": "golden_rain",
	},
	{
		"id": "golden_rain", "group": "rain", "weight": 1.0, "duration": 40.0,
		"start": &"_weather_start_golden_rain", "tick": &"",
		"stop": &"_weather_stop_golden_rain", "follow_up_only": true,
	},
	{
		# Una sola ola: su tick la vierte en tres segundos y termina el
		# desastre él mismo. Puede volver a salir más tarde.
		"id": "enemy_tsunami", "group": "disaster", "weight": 1.0, "duration": 3.0,
		"start": &"_weather_start_tsunami", "tick": &"_weather_tick_tsunami",
		"stop": &"",
	},
	{
		"id": "earthquake", "group": "disaster", "weight": 1.0, "duration": 25.0,
		"start": &"_weather_start_earthquake", "tick": &"_weather_tick_earthquake",
		"stop": &"_weather_stop_earthquake",
	},
	{
		"id": "meteor_shower", "group": "disaster", "weight": 1.0, "duration": 30.0,
		"start": &"_weather_start_meteors", "tick": &"_weather_tick_meteors",
		"stop": &"",
	},
]

## Grupos que un pacto demoníaco puede alargar (RunState.sky_duration_multiplier).
const STRETCHABLE_GROUPS: Array[String] = ["moon", "rain"]
## Climas que el altar de evento no invoca: los dos premios. Un altar que
## diera la lluvia dorada directa haría inútiles las lluvias que la ganan.
const ALTAR_EXCLUDED: Array[String] = ["golden_rain", "full_moon"]
## Tope de charcos de ácido vivos y distancia mínima entre ellos (metros).
## Pasado el tope se saltan; subir el tope no es la solución.
const MAX_LIVE_ACID_POOLS: int = 24
const ACID_POOL_SPACING: float = 3.0
## Tope de avisos de meteorito vivos, por lo mismo (el pool de discos es
## de 32 y lo usa todo el juego).
const MAX_LIVE_TELEGRAPHS: int = 16
## Enemigos que el tsunami vierte por frame de física: cuarenta en un solo
## frame dan un tirón visible.
const TSUNAMI_PER_FRAME: int = 6
## Medio ancho del arco del que viene la ola (radianes, ~60 grados en total).
const TSUNAMI_ARC_SPREAD: float = 0.52
## Daño por segundo del ácido a un jugador dentro de un charco.
const ACID_DAMAGE_PER_SECOND: float = 4.0


## La fila de WEATHER_CATALOG con ese id, o vacío.
static func weather_row(id: String) -> Dictionary:
	for row: Dictionary in WEATHER_CATALOG:
		if String(row.id) == id:
			return row
	return {}


## Segundos que dura esta fila, con el reemplazo del Inspector y, solo en
## lunas y lluvias, el multiplicador de los pactos.
func _weather_duration(row: Dictionary) -> float:
	var seconds := float(weather_duration_overrides.get(String(row.id), row.duration))
	if STRETCHABLE_GROUPS.has(String(row.group)):
		seconds *= RunState.sky_duration_multiplier
	return seconds


## La tirada de clima de cada evento: primero el grupo más raro, para que
## las lluvias y lunas no tapen a los desastres.
func _maybe_weather() -> void:
	if not active_weather.is_empty() or _sky_gap_left > 0.0:
		return
	# Con probabilidad 0 un grupo NO tira dado: el RNG de la partida es uno
	# solo y un dado de más cambia todo lo que se sortea después.
	var disaster_odds := disaster_chance + RunState.disaster_chance_bonus
	if disaster_odds > 0.0 and randf() < disaster_odds:
		_start_weather(_roll_group("disaster"))
		return
	var rain_odds := rain_chance + RunState.event_chance_bonus
	if rain_odds > 0.0 and randf() < rain_odds:
		_start_weather(_roll_group("rain"))
		return
	# Los pactos demoníacos venden probabilidad de luna, además del extra
	# que suma cada altar demoníaco usado.
	var chance := sky_event_chance + RunState.event_chance_bonus \
			+ sky_event_chance_per_demonic * float(RunState.demonic_uses)
	if randf() >= chance:
		return
	_start_weather(_roll_group("moon"))


## Un id al azar del grupo, por peso, sin las filas follow_up_only.
func _roll_group(group: String) -> String:
	var total := 0.0
	for row: Dictionary in WEATHER_CATALOG:
		if String(row.group) == group and not bool(row.get("follow_up_only", false)):
			total += float(row.weight)
	if total <= 0.0:
		return ""
	var roll := randf() * total
	for row: Dictionary in WEATHER_CATALOG:
		if String(row.group) != group or bool(row.get("follow_up_only", false)):
			continue
		roll -= float(row.weight)
		if roll <= 0.0:
			return String(row.id)
	return ""


## Entrada PÚBLICA por grupo (el probe, BONK_WEATHER_NOW, el altar de
## evento): FUERZA un clima. Detiene el que haya y empieza aunque no haya
## pasado la pausa; si no hiciera nada, el altar parecería roto y fallaría
## la puerta CIELO_TRAS_AVANCE de verificar.sh.
func start_sky_event(kind: String) -> void:
	_start_weather(kind, true)


## La tirada del altar de evento: cualquier fila menos los dos premios.
func random_altar_weather() -> String:
	var total := 0.0
	for row: Dictionary in WEATHER_CATALOG:
		if not ALTAR_EXCLUDED.has(String(row.id)):
			total += float(row.weight)
	if total <= 0.0:
		return ""
	var roll := randf() * total
	for row: Dictionary in WEATHER_CATALOG:
		if ALTAR_EXCLUDED.has(String(row.id)):
			continue
		roll -= float(row.weight)
		if roll <= 0.0:
			return String(row.id)
	return ""


func _start_weather(id: String, forced: bool = false) -> void:
	if id.is_empty():
		return
	var row := weather_row(id)
	if row.is_empty():
		push_warning("WorldDirector: unknown weather '%s'" % id)
		return
	if not active_weather.is_empty():
		if not forced:
			return
		# Forzado: el clima activo se detiene bien, con su stop(), que es lo
		# que suelta el tinte, la fuente de puntos y el desplazamiento del HUD.
		_stop_weather(false)
	_cache_lights()
	_weather_state = {}
	var seconds := _weather_duration(row)
	active_weather = {"id": id, "group": String(row.group), "time_left": seconds}
	call(row.start)
	if String(row.group) == "disaster":
		# Línea aparte para que un soak distinga los desastres del resto.
		print("Disaster: %s" % id)
	print("Weather started: %s" % id)


func _tick_weather(delta: float) -> void:
	_sky_gap_left = maxf(_sky_gap_left - delta, 0.0)
	if active_weather.is_empty():
		return
	var row := weather_row(String(active_weather.id))
	var tick: StringName = row.get("tick", &"")
	if not tick.is_empty():
		call(tick, delta)
	# El tick puede terminar el clima él mismo (el tsunami, cuando vierte
	# su ola); entonces no queda nada que descontar.
	if active_weather.is_empty():
		return
	active_weather.time_left = float(active_weather.time_left) - delta
	if float(active_weather.time_left) > 0.0:
		return
	_stop_weather(true)


## Termina el clima activo. `chain` es false al desmontar (cambio de etapa,
## salida de la partida): el follow_up no puede empezar en una arena que se va.
func _stop_weather(chain: bool) -> void:
	if active_weather.is_empty():
		return
	var id := String(active_weather.id)
	var row := weather_row(id)
	var stop: StringName = row.get("stop", &"")
	active_weather = {}
	if not stop.is_empty():
		call(stop)
	_weather_state = {}
	print("Weather ended: %s" % id)
	if not chain:
		return
	var follow_up := String(row.get("follow_up", ""))
	if not follow_up.is_empty():
		# Directo al siguiente, sin devolver el cielo: un tween de vuelta de
		# 2 s competiría con el de 1.5 s del siguiente y ganaría el más largo.
		_start_weather(follow_up)
		return
	_restore_sky()
	_sky_gap_left = sky_event_min_gap


## --- lunas ------------------------------------------------------------------

func _weather_start_blood_moon() -> void:
	var seconds := float(active_weather.time_left)
	get_tree().call_group("enemy_spawner", "set_sky_event", "blood_moon", seconds)
	_tint_sky(Color(1.0, 0.25, 0.2), 0.9, Color(0.5, 0.1, 0.1))
	_announce("LUNA DE SANGRE — ¡la horda enloquece!")
	_print_sky_event("blood_moon", seconds)


func _weather_start_eclipse() -> void:
	var seconds := float(active_weather.time_left)
	get_tree().call_group("enemy_spawner", "set_sky_event", "eclipse", seconds)
	_tint_sky(Color(0.35, 0.3, 0.5), 0.35, Color(0.12, 0.1, 0.2))
	_announce("ECLIPSE — las sombras entran por todos lados")
	_print_sky_event("eclipse", seconds)


## Etiqueta de las dos ventajas de la luna llena: una segunda luna dentro
## de la primera las reemplaza en vez de sumarlas (solo
## clear_timed_boons quita por etiqueta).
const FULL_MOON_TAG: String = "full_moon"


func _weather_start_full_moon() -> void:
	# El pacto vende "lunas más largas", así que la buena también crece.
	var seconds := float(active_weather.time_left)
	# A los dos grupos (de pie y caídos) y con etiqueta, como la lluvia
	# dorada: quien estaba caído al salir la luna también la recibe, y una
	# luna forzada (altar de evento) reemplaza las ventajas en vez de sumarlas.
	for body: Node3D in _all_raiders():
		var stats := PlayerStats.find_in(body)
		if stats != null:
			stats.clear_timed_boons(FULL_MOON_TAG)
			stats.add_timed_boon("xp_gain", full_moon_xp_bonus, seconds, FULL_MOON_TAG)
			stats.add_timed_boon("luck", full_moon_luck_bonus, seconds, FULL_MOON_TAG)
	_tint_sky(Color(0.85, 0.9, 1.0), 1.3, Color(0.6, 0.65, 0.9))
	_announce("LUNA LLENA — la fortuna y la sabiduría te sonríen")
	_print_sky_event("full_moon", seconds)


## Las lunas imprimen esta línea TAL CUAL: la puerta CIELO_TRAS_AVANCE de
## verificar.sh la cuenta tras cada cambio de etapa para probar que el
## director volvió a buscar las luces del mapa nuevo. Lluvias y desastres
## no la imprimen.
func _print_sky_event(kind: String, seconds: float) -> void:
	print("Sky event: %s for %.0fs" % [kind, seconds])


## --- lluvias ----------------------------------------------------------------

func _weather_start_enemy_rain() -> void:
	_weather_state["drop_left"] = 0.0
	_tint_sky(Color(0.6, 0.8, 1.0), 0.8, Color(0.35, 0.45, 0.6))
	_announce("LLUVIA DE ENEMIGOS — ¡caen del cielo!")


## Los enemigos "caen" como un aviso en el suelo más un destello, y después
## aparecen en el suelo. NO se sueltan desde arriba: un cuerpo cayendo es lo
## que el detector de cuerpos en el aire del harness atrapa, y ese detector
## no se amplía por decorado.
func _weather_tick_enemy_rain(delta: float) -> void:
	_weather_state["drop_left"] = float(_weather_state.get("drop_left", 0.0)) - delta
	if float(_weather_state["drop_left"]) > 0.0:
		return
	_weather_state["drop_left"] = enemy_rain_interval
	var anchor_body := Coop.random_player(get_tree())
	if anchor_body == null:
		return
	var wanted := randi_range(enemy_rain_min_drops, enemy_rain_max_drops)
	var points: Array[Vector3] = []
	for i in wanted:
		var point := _rain_point(anchor_body.global_position,
				enemy_rain_min_distance, enemy_rain_max_distance)
		if point == Vector3.INF:
			continue
		points.append(point)
		Telegraph.spawn_disc(self, point, 1.4, 1.0, Color(0.6, 0.85, 1.0))
		Juice.burst(point + Vector3.UP * 3.0, Color(0.6, 0.85, 1.0), 6)
	if not points.is_empty():
		# Sin el cupo de horda (false): la lluvia es clima de 35 s, y con
		# ese cupo la arena se quedaba en su tope toda la ventana, un muro
		# que no deja pasar. El tsunami sí es una ola.
		get_tree().call_group("enemy_spawner", "spawn_at_points", points, false)


func _weather_start_radioactive_rain() -> void:
	_weather_state["pool_left"] = 0.0
	_tint_sky(Color(0.5, 1.0, 0.4), 0.85, Color(0.2, 0.4, 0.15))
	_announce("LLUVIA RADIACTIVA — el suelo se vuelve ácido")


func _weather_tick_radioactive_rain(delta: float) -> void:
	_weather_state["pool_left"] = float(_weather_state.get("pool_left", 0.0)) - delta
	if float(_weather_state["pool_left"]) > 0.0:
		return
	_weather_state["pool_left"] = acid_pool_interval
	var anchor_body := Coop.random_player(get_tree())
	if anchor_body == null:
		return
	var point := _rain_point(anchor_body.global_position, 2.0, acid_pool_spawn_range)
	if point != Vector3.INF:
		spawn_acid_pool(point)


func _weather_stop_radioactive_rain() -> void:
	# Los charcos sobreviven a la lluvia a propósito: cada uno caduca con
	# su propio reloj, y el cambio de etapa recoge los que queden con
	# Pools.release_all_live.
	pass


## PÚBLICO (EnemyBase lo llama al morir durante la lluvia radiactiva): un
## charco de ácido, si cabe bajo el tope y respeta la distancia. Si no, se
## salta en silencio: un aviso aquí haría fallar un soak por funcionar bien.
func spawn_acid_pool(at: Vector3) -> void:
	if not is_weather_active("radioactive_rain"):
		return
	var live := get_tree().get_nodes_in_group(&"acid_pools")
	if live.size() >= MAX_LIVE_ACID_POOLS:
		return
	var spacing_sq := ACID_POOL_SPACING * ACID_POOL_SPACING
	for node: Node in live:
		var pool := node as Node3D
		if pool != null and pool.global_position.distance_squared_to(at) < spacing_sq:
			return
	var fresh := Pools.acquire_scene(Pools.ACID_POOL_SCENE) as AcidPool
	if fresh == null:
		return
	fresh.play(at, acid_pool_radius, acid_pool_lifetime, ACID_DAMAGE_PER_SECOND)


## Verdadero mientras `id` sea el clima activo. Es LA consulta pública para
## lo que cambia con un clima (el ácido de EnemyBase, el HUD).
func is_weather_active(id: String) -> bool:
	return not active_weather.is_empty() and String(active_weather.id) == id


func _weather_start_golden_rain() -> void:
	_tint_sky(Color(1.0, 0.85, 0.4), 1.2, Color(0.6, 0.5, 0.2))
	# A los dos grupos: un jugador caído también gana los puntos que el
	# grupo junta por él, y la fuente se le quita igual al terminar.
	for body: Node3D in _all_raiders():
		if body.has_method("set_points_source"):
			body.call("set_points_source", "golden_rain", golden_points_multiplier)
	RunState.price_discount = golden_price_discount
	_announce("LLUVIA DORADA — todo brilla y todo vale la mitad")


func _weather_stop_golden_rain() -> void:
	for body: Node3D in _all_raiders():
		if body.has_method("clear_points_source"):
			body.call("clear_points_source", "golden_rain")
	RunState.price_discount = 1.0


## Todos los jugadores, de pie o caídos. Un efecto de grupo tiene que
## llegar a los dos: un cuerpo caído sale de "player" y entra en
## "downed_players".
func _all_raiders() -> Array[Node3D]:
	var bodies: Array[Node3D] = []
	for group: String in ["player", "downed_players"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body != null and is_instance_valid(body):
				bodies.append(body)
	return bodies


## Un punto caminable y apoyado en el suelo en un anillo alrededor de
## `origin`, o Vector3.INF si la máscara no ofrece ninguno. La lluvia y los
## meteoritos caen por aquí, así nada del clima termina dentro de una roca.
func _rain_point(origin: Vector3, min_distance: float, max_distance: float) -> Vector3:
	for attempt in EVENT_POINT_ATTEMPTS:
		var angle := randf() * TAU
		var pos := origin + Vector3(cos(angle), 0.0, sin(angle)) \
				* randf_range(min_distance, max_distance)
		var limit := _arena_half_extent - bounds_margin
		pos.x = clampf(pos.x, -limit, limit)
		pos.z = clampf(pos.z, -limit, limit)
		if _walkable(pos):
			pos.y = _ground_height(pos)
			return pos
	return Vector3.INF


## --- desastres --------------------------------------------------------------

func _weather_start_tsunami() -> void:
	var anchor_body := Coop.random_player(get_tree())
	var origin := anchor_body.global_position if anchor_body != null else Vector3.ZERO
	var angle := randf() * TAU
	_weather_state["angle"] = angle
	_weather_state["origin"] = origin
	# Con el reloj de la ETAPA, no el de la partida, como las hordas: cada
	# mapa tiene su propio tramo, y con el reloj de la partida la ola de
	# una tercera etapa saldría enorme.
	var wanted := tsunami_base + tsunami_per_minute * int(RunState.stage_time / 60.0)
	_weather_state["left"] = wanted
	_announce("¡TSUNAMI DE ENEMIGOS! %s" % _compass_word(angle))


## Vierte la ola durante los tres segundos de la fila, por tandas de
## TSUNAMI_PER_FRAME; el tope de horda de spawn_at_points limita el total.
func _weather_tick_tsunami(_delta: float) -> void:
	var left := int(_weather_state.get("left", 0))
	if left <= 0:
		return
	var chunk := mini(left, TSUNAMI_PER_FRAME)
	var origin: Vector3 = _weather_state.get("origin", Vector3.ZERO)
	var angle := float(_weather_state.get("angle", 0.0))
	var points: Array[Vector3] = []
	for i in chunk:
		# Un arco de un solo lado: un tsunami es un muro que viene de un
		# lugar, no un anillo que se cierra (eso es una horda).
		var spread := angle + randf_range(-TSUNAMI_ARC_SPREAD, TSUNAMI_ARC_SPREAD)
		var pos := origin + Vector3(cos(spread), 0.0, sin(spread)) \
				* randf_range(tsunami_arc_min, tsunami_arc_max)
		var limit := _arena_half_extent - bounds_margin
		pos.x = clampf(pos.x, -limit, limit)
		pos.z = clampf(pos.z, -limit, limit)
		if _walkable(pos):
			points.append(pos)
	if not points.is_empty():
		get_tree().call_group("enemy_spawner", "spawn_at_points", points, true)
	_weather_state["left"] = left - chunk


func _weather_start_earthquake() -> void:
	_weather_state["shake_left"] = 0.0
	_weather_state["dust_left"] = 0.0
	_weather_state["hud_time"] = 0.0
	_announce("¡TERREMOTO! El suelo no se queda quieto")


func _weather_tick_earthquake(delta: float) -> void:
	_weather_state["shake_left"] = float(_weather_state.get("shake_left", 0.0)) - delta
	if float(_weather_state["shake_left"]) <= 0.0:
		_weather_state["shake_left"] = earthquake_shake_interval
		Juice.shake(earthquake_shake_strength)
	_weather_state["dust_left"] = float(_weather_state.get("dust_left", 0.0)) - delta
	if float(_weather_state["dust_left"]) <= 0.0:
		_weather_state["dust_left"] = earthquake_dust_interval
		for body: Node3D in _all_raiders():
			Juice.burst(body.global_position, Color(0.6, 0.55, 0.45), 8)
	# El HUD es un CanvasLayer: UN desplazamiento mueve todo lo que tiene
	# (barras, reloj, minimapas). El mapa de Tab está en otra capa y queda
	# quieto a propósito: un mapa que tiembla no se puede leer.
	var hud_time := float(_weather_state.get("hud_time", 0.0)) + delta
	_weather_state["hud_time"] = hud_time
	var phase := hud_time * earthquake_hud_hz * TAU
	get_tree().call_group("hud", "set_quake_offset", Vector2(
			sin(phase) * earthquake_hud_amplitude,
			cos(phase * 1.3) * earthquake_hud_amplitude))


func _weather_stop_earthquake() -> void:
	get_tree().call_group("hud", "set_quake_offset", Vector2.ZERO)


func _weather_start_meteors() -> void:
	_weather_state["meteor_left"] = 0.0
	_weather_state["pending"] = []
	_tint_sky(Color(1.0, 0.6, 0.35), 0.95, Color(0.4, 0.25, 0.15))
	_announce("¡LLUVIA DE METEORITOS! Sal de los círculos")


## Descuenta los avisos pendientes (los que llegan a 0 impactan) y, cada
## meteor_interval, marca un impacto nuevo cerca de un jugador al azar.
func _weather_tick_meteors(delta: float) -> void:
	var pending: Array = _weather_state.get("pending", [])
	for i in range(pending.size() - 1, -1, -1):
		var strike: Dictionary = pending[i]
		strike["left"] = float(strike["left"]) - delta
		if float(strike["left"]) > 0.0:
			pending[i] = strike
			continue
		pending.remove_at(i)
		_meteor_impact(strike["at"])
	_weather_state["pending"] = pending
	_weather_state["meteor_left"] = float(_weather_state.get("meteor_left", 0.0)) - delta
	if float(_weather_state["meteor_left"]) > 0.0:
		return
	_weather_state["meteor_left"] = meteor_interval
	if pending.size() >= MAX_LIVE_TELEGRAPHS:
		return
	var anchor_body := Coop.random_player(get_tree())
	if anchor_body == null:
		return
	var at := _rain_point(anchor_body.global_position, 3.0, meteor_range)
	if at == Vector3.INF:
		return
	Telegraph.spawn_disc(self, at, meteor_radius, meteor_telegraph,
			Color(1.0, 0.55, 0.2))
	pending.append({"at": at, "left": meteor_telegraph})
	_weather_state["pending"] = pending


## Cae un meteorito. Daña a jugadores y enemigos (a estos más): quedarse
## quieto es el error.
func _meteor_impact(at: Vector3) -> void:
	Juice.burst(at + Vector3.UP * 0.5, Color(1.0, 0.6, 0.25), 26)
	Juice.shake(0.35)
	Telegraph.spawn_disc(self, at, meteor_radius * 0.8, 0.5, Color(0.35, 0.2, 0.15))
	var damage := meteor_damage * (1.0 + _minutes() * 0.05)
	var radius_sq := meteor_radius * meteor_radius
	for body: Node3D in _all_raiders():
		if _flat_distance_sq(body.global_position, at) <= radius_sq:
			var health := Health.find_in(body)
			if health != null and not health.is_dead:
				health.take_damage(damage)
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node3D
		if enemy == null or not enemy.is_inside_tree():
			continue
		if _flat_distance_sq(enemy.global_position, at) > radius_sq:
			continue
		var enemy_health := Health.find_in(enemy)
		if enemy_health != null and not enemy_health.is_dead:
			enemy_health.take_damage(damage * meteor_enemy_scale)


## Distancia al cuadrado en el plano XZ (ignora la altura).
static func _flat_distance_sq(a: Vector3, b: Vector3) -> float:
	var span := a - b
	span.y = 0.0
	return span.length_squared()


## De dónde viene el tsunami, para el aviso: cuatro rumbos bastan para
## saber hacia dónde correr.
static func _compass_word(angle: float) -> String:
	var turns := fposmod(angle / TAU, 1.0)
	if turns < 0.125 or turns >= 0.875:
		return "desde el este"
	if turns < 0.375:
		return "desde el sur"
	if turns < 0.625:
		return "desde el oeste"
	return "desde el norte"


## Guarda el sol y el ambiente de la arena actual y sus valores originales.
## No hace nada si ya los tiene (on_stage_started los olvida en cada etapa).
func _cache_lights() -> void:
	if _sun != null:
		return
	# La ARENA, no current_scene: current_scene es la raíz de la partida y
	# sus luces son las de la arena que tenga debajo.
	var scene := _stage_parent()
	if scene == null or scene == self:
		return
	for node: Node in scene.find_children("*", "DirectionalLight3D", true, false):
		_sun = node as DirectionalLight3D
		_sun_color = _sun.light_color
		_sun_energy = _sun.light_energy
		break
	for node: Node in scene.find_children("*", "WorldEnvironment", true, false):
		var world_environment := node as WorldEnvironment
		if world_environment == null or world_environment.environment == null:
			break
		# El Environment de la arena es un sub_resource COMPARTIDO por todas
		# las instancias de la escena: teñirlo pasaría a la partida
		# siguiente. Se trabaja sobre una copia propia de esta arena.
		_environment = world_environment.environment.duplicate()
		world_environment.environment = _environment
		_ambient_color = _environment.ambient_light_color
		_ambient_energy = _environment.ambient_light_energy
		break


## Lleva el sol y el ambiente a un tinte en 1.5 s. `sun_energy` multiplica
## la energía original del sol.
func _tint_sky(sun_color: Color, sun_energy: float, ambient: Color) -> void:
	_kill_sky_tween()
	_sky_tween = create_tween().set_parallel()
	if _sun != null:
		_sky_tween.tween_property(_sun, "light_color", sun_color, 1.5)
		_sky_tween.tween_property(_sun, "light_energy", _sun_energy * sun_energy, 1.5)
	if _environment != null:
		_sky_tween.tween_property(_environment, "ambient_light_color", ambient, 1.5)


## Devuelve el cielo original de la arena en 2 s.
func _restore_sky() -> void:
	_kill_sky_tween()
	_sky_tween = create_tween().set_parallel()
	if _sun != null:
		_sky_tween.tween_property(_sun, "light_color", _sun_color, 2.0)
		_sky_tween.tween_property(_sun, "light_energy", _sun_energy, 2.0)
	if _environment != null:
		_sky_tween.tween_property(_environment, "ambient_light_color", _ambient_color, 2.0)


func _kill_sky_tween() -> void:
	if _sky_tween != null and _sky_tween.is_valid():
		_sky_tween.kill()
	_sky_tween = null


func _free_beacon(beacon: Node3D) -> void:
	if beacon != null and is_instance_valid(beacon):
		beacon.queue_free()


## Muestra un aviso centrado en el HUD (grupo "boss_ui").
func _announce(message: String) -> void:
	get_tree().call_group("boss_ui", "announce", message)
