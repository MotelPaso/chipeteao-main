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
const SUPPLY_CHEST_SCENE := preload("res://scenes/world/director/SupplyChest.tscn")
const PORTAL_SHRINE_SCENE := preload("res://scenes/world/director/PortalShrine.tscn")
const EXIT_PORTAL_SCENE := preload("res://scenes/world/director/ExitPortal.tscn")
const BEACON_SCENE := preload("res://scenes/world/director/Beacon.tscn")
const Beacon := preload("res://scripts/world/run/director/beacon.gd")

## Eventos del mundo, una fila por evento: edita aquí el peso, el aviso y
## la baliza de cada uno. Campos:
##   id:           identificador; event_weight_overrides lo usa como clave.
##   weight:       peso relativo del sorteo.
##   scene:        POI que aparece lejos de un jugador al azar.
##   method:       solo en los eventos que hacen algo más que poner `scene`;
##                 se llama con call(row) y catalog_lint.gd revisa que exista.
##   announce:     aviso en el HUD (texto del jugador).
##   beacon_color: color de la baliza sobre el evento; sin él no hay baliza.
##   beacon_time:  segundos que arde la baliza; INF = hasta que el POI se usa.
##   altar:        cadencia de altares: el peso sube con el minuto y vale 0
##                 mientras haya demasiados altares sin usar.
##   cap_group/cap: con `cap` o más nodos en el grupo `cap_group`, el evento
##                 pesa 0 y sale otro.
##   log:          línea de log al aparecer, para los soaks (no traducir).
const EVENT_LIBRARY: Array[Dictionary] = [
	{
		# Mínimo Raro y con suerte extra (SupplyChest.tscn). Se hunde si nadie
		# lo abre antes de que se apague su baliza.
		"id": "supply_chest", "weight": 1.0, "method": &"_event_supply_chest",
		"scene": SUPPLY_CHEST_SCENE,
		"announce": "Un cofre de suministros zumba en algún lugar del campo...",
		"beacon_color": Color(1.0, 0.82, 0.3), "beacon_time": 40.0,
	},
	{
		"id": "elite_pack", "weight": 1.0, "method": &"_event_elite_pack",
		"announce": "¡Una jauría shiny te huele el rastro!",
	},
	{
		# Las gemas tienen su propia duración; la baliza se apaga antes.
		"id": "essence_rift", "weight": 1.0, "method": &"_event_essence_rift",
		"announce": "Se abre una grieta de esencia...",
		"beacon_color": Color(0.35, 0.95, 0.6), "beacon_time": 30.0,
	},
	{
		"id": "charge_altar", "weight": 1.6, "altar": true, "scene": CHARGE_SHRINE_SCENE,
		"announce": "Se alza un altar de carga — párate en su anillo",
		"beacon_color": Color(0.45, 0.85, 1.0), "beacon_time": INF,
		"log": "Altar placed: charge",
	},
	{
		"id": "demonic_altar", "weight": 0.5, "altar": true, "scene": CURSE_SHRINE_SCENE,
		"announce": "Un obelisco demoníaco sale del suelo a zarpazos...",
		"beacon_color": Color(1.0, 0.35, 0.3), "beacon_time": INF,
		"log": "Altar placed: demonic",
	},
	{
		# Un solo manantial a la vez; se queda hasta que alguien bebe.
		"id": "spring", "weight": 0.7, "scene": SPRING_SHRINE_SCENE,
		"announce": "Un manantial brota en algún lugar del campo...",
		"beacon_color": Color(0.4, 0.8, 1.0), "beacon_time": INF,
		"cap_group": &"springs", "cap": 1,
	},
	{
		# La estrella solo aparece con este evento: no cae de enemigos ni se
		# vende. La baliza marca dónde se vio, no dónde está: se mueve.
		"id": "star_sighting", "weight": 0.15, "method": &"_event_star",
		"announce": "Algo brillante cruza el campo...",
		"beacon_color": Color(1.0, 0.9, 0.35), "beacon_time": 12.0,
	},
	{
		# El tipo de puesto se sortea en secreto; el color de la baliza es el
		# de su fila en Vendor.VENDOR_LIBRARY.
		"id": "vendor", "weight": 0.8, "method": &"_event_vendor", "scene": VENDOR_SCENE,
		"announce": "¡Llega un vendedor!", "beacon_time": INF,
		"cap_group": &"vendors", "cap": 2,
	},
	{
		"id": "pet_box", "weight": 0.35, "scene": PET_BOX_SCENE,
		"announce": "Una caja con una huella aparece en el campo...",
	},
	{
		"id": "event_altar", "weight": 0.4, "scene": EVENT_ALTAR_SCENE,
		"announce": "Un cristal de tormenta se alza en el campo...",
	},
	{
		"id": "lucky_block", "weight": 0.25, "scene": LUCKY_BLOCK_SCENE,
		"announce": "Un bloque dorado aparece en algún lugar...",
	},
]



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
@export var first_event_at: float = 60.0
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
## Enemigos shiny de la jauría de élite.
@export var elite_pack_size: int = 3
## Gemas de XP que suelta la grieta de esencia.
@export var rift_gem_count: int = 10
## XP de cada gema de la grieta (una gema normal vale 1).
@export var rift_gem_value: int = 3
## Pesos que reemplazan los de EVENT_LIBRARY, por id de evento; 0 quita el
## evento. Vale para todas las arenas: el director es uno por partida.
@export var event_weight_overrides: Dictionary[String, float] = {}
@export_group("Altars (iteration 47)")
## Cuánto sube el peso de los altares por minuto: peso x (1 + esto x minutos).
@export var altar_weight_per_minute: float = 0.25
## Tope de ese multiplicador del peso de los altares.
@export var altar_weight_max_scale: float = 3.0
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
## Aviso en el HUD cuando se abre el portal de salida.
@export var exit_portal_announce: String = "Se abrió el portal de salida — crúzalo cuando quieras"
## Portales al inicio de la etapa; van en pares, así que conviene un número par.
@export var portal_count: int = 4
## Ruletas al inicio de la etapa.
@export var roulette_count: int = 1
## Reparto de la etapa actual: arena, máscara, puntos ocupados y
## muestreos. Uno nuevo por etapa; entre etapas, uno vacío.
var _layout: StageLayout = null
## Un portal de salida por etapa.
var _exit_portal_spawned: bool = false
var _event_timer: float = 0.0
## Balizas vivas (cofres de suministros, altares, manantiales, grietas...).
var _beacons: Array[TimedBeacon] = []
## El clima activo, o vacío: {id, group, time_left}. Vive en el nodo
## Weather; hud.gd, event_altar.gd y el probe lo leen aquí con
## get("active_weather").
var active_weather: Dictionary:
	get:
		return _weather.active_weather if _weather != null else {}

## El clima (RunSystems.tscn > WorldDirector > Weather).
@onready var _weather: WeatherDirector = $Weather


func _ready() -> void:
	_set_layout(_new_layout(null))
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
	_set_layout(_new_layout(arena))
	# El clima olvida las luces de la arena anterior y vuelve a buscarlas.
	_weather.begin_stage(_layout)
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
		_layout.shuffle_ground_interactables()
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
	_spawn_at(PET_BOX_SCENE, _layout.claim_clear_point())


## 0-1 altares de evento al inicio de la etapa, como la caja de mascota.
func _spawn_start_event_altars() -> void:
	# Con probabilidad 0 no se tira ningún dado (ver la caja de mascota):
	# cambiaría dónde caen los portales, las ruletas y los POI movidos.
	if start_event_altar_chance <= 0.0 or randf() >= start_event_altar_chance:
		return
	_spawn_at(EVENT_ALTAR_SCENE, _layout.claim_clear_point())


## 0-1 bloques de la suerte al inicio de la etapa; con probabilidad 0 no
## se tira ningún dado.
func _spawn_start_lucky_blocks() -> void:
	if lucky_block_start_chance <= 0.0 or randf() >= lucky_block_start_chance:
		return
	_spawn_at(LUCKY_BLOCK_SCENE, _layout.claim_clear_point())


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


## Un StageLayout para `arena` (null = vacío) con las distancias del reparto.
func _new_layout(arena: Node3D) -> StageLayout:
	var layout := StageLayout.new(self, arena)
	layout.bounds_margin = bounds_margin
	layout.min_distance_from_spawn = min_distance_from_spawn
	layout.min_distance_between = min_distance_between
	layout.min_distance_from_keepouts = min_distance_from_keepouts
	return layout


## Cambia el layout del director y el del clima, que comparte el mismo.
func _set_layout(layout: StageLayout) -> void:
	_layout = layout
	_weather.layout = layout


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
	_layout.refresh_placed_points()
	var extra := randi_range(extra_start_chests_min, extra_start_chests_max)
	for i in extra:
		var chest := CHEST_SCENE.instantiate() as Chest
		# ANTES de add_child: el cofre elige su tinte y su texto en _ready.
		if randf() < free_start_chest_chance:
			chest.free_open = true
			freebies += 1
		_layout.stage_parent().add_child(chest)
		chest.global_position = _layout.claim_clear_point()
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
		_weather.stop_weather()
		return
	_tick_exit_portal()
	_tick_beacons(delta)
	if not events_enabled:
		return
	_weather.tick(delta)
	_event_timer -= delta
	if _event_timer > 0.0:
		return
	_event_timer = _next_event_gap()
	# El clima tira DESPUÉS del evento: ese orden es parte del sorteo.
	_fire_random_event()
	_weather.maybe_roll()


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


## --- objetos de inicio ------------------------------------------------------

## Portales en pares al azar (PortalShrine.tscn). El color sale del índice
## del par de creación (i / 2) y los pares se forman después de mezclar:
## el color no indica cuál es la pareja.
func _spawn_portals() -> void:
	var count := portal_count - (portal_count % 2)
	var portals: Array[PortalShrine] = []
	for i in count:
		var portal := PORTAL_SHRINE_SCENE.instantiate() as PortalShrine
		# El nombre sale en el log "Portal used:".
		portal.name = "Portal%d" % (i + 1)
		portal.pair_index = i / 2
		_layout.stage_parent().add_child(portal)
		portal.global_position = _layout.claim_clear_point()
		portals.append(portal)
	portals.shuffle()
	for i in range(0, portals.size() - 1, 2):
		portals[i].twin = portals[i + 1]
		portals[i + 1].twin = portals[i]
	if count > 0:
		print("Portals placed: %d (%d pairs)" % [count, count / 2])


func _spawn_roulettes() -> void:
	for i in roulette_count:
		_spawn_at(ROULETTE_SHRINE_SCENE, _layout.claim_clear_point())


## Crea `scene` en la arena y la pone en `at` (ya calculado: el punto se
## sortea antes de crear el nodo).
func _spawn_at(scene: PackedScene, at: Vector3) -> Node3D:
	var node := scene.instantiate() as Node3D
	_layout.stage_parent().add_child(node)
	node.global_position = at
	return node


## --- eventos ----------------------------------------------------------------

## Peso de una fila de EVENT_LIBRARY ahora mismo. Un peso 0 saca el evento
## del sorteo (sale otro): así un evento que no puede ocurrir no gasta la
## ventana. Los altares pesan más con el minuto y valen 0 mientras haya
## demasiados sin usar.
func _event_weight(row: Dictionary) -> float:
	var weight := float(event_weight_overrides.get(row["id"], row["weight"]))
	if row.has("cap_group") \
			and get_tree().get_node_count_in_group(row["cap_group"]) >= int(row["cap"]):
		return 0.0
	if not bool(row.get("altar", false)) or weight <= 0.0:
		return weight
	if _unspent_altars() >= _altar_cap():
		return 0.0
	return weight * minf(1.0 + altar_weight_per_minute * _minutes(), altar_weight_max_scale)


## Sortea una fila de EVENT_LIBRARY por peso y la ejecuta: su `method` si
## lo tiene, si no pone su `scene`.
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
	if chosen.has("method"):
		call(chosen["method"], chosen)
	else:
		_event_spawn_poi(chosen)


## Evento simple: el POI de la fila lejos de un jugador, con su baliza (si
## la fila tiene beacon_color), su aviso y su línea de log.
func _event_spawn_poi(row: Dictionary) -> void:
	var poi := _spawn_at(row["scene"], _event_point())
	if row.has("beacon_color"):
		_raise_beacon(poi.global_position, row["beacon_color"], poi, float(row["beacon_time"]))
	_announce(String(row["announce"]))
	if row.has("log"):
		print(String(row["log"]))


## Llega un puesto. El TIPO se sortea aquí y no se nombra en el aviso ni
## en la baliza: ir a ver cuál es, es el evento.
func _event_vendor(row: Dictionary) -> void:
	var vendor := (row["scene"] as PackedScene).instantiate() as Node3D
	var kind: Dictionary = Vendor.VENDOR_LIBRARY[randi() % Vendor.VENDOR_LIBRARY.size()]
	# ANTES de entrar al árbol: Vendor._ready lo lee para elegir su texto,
	# su color y la figura tras el mostrador.
	vendor.set("kind", String(kind.id))
	_layout.stage_parent().add_child(vendor)
	vendor.global_position = _event_point()
	_raise_beacon(vendor.global_position, kind.get("color", Color.WHITE), vendor,
			float(row["beacon_time"]))
	_announce(String(row["announce"]))
	print("Vendor arrived: %s" % String(kind.id))


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
	_raise_beacon(at, row["beacon_color"], null, float(row["beacon_time"]))
	_announce(String(row["announce"]))


## Cofre de suministros (SupplyChest.tscn): se hunde si nadie lo abre
## antes de que se apague su baliza.
func _event_supply_chest(row: Dictionary) -> void:
	var chest := (row["scene"] as PackedScene).instantiate() as Chest
	# add_child ANTES de buscar el punto: Chest._ready sortea la rareza con
	# el RNG de la partida, y ese orden es parte del sorteo.
	_layout.stage_parent().add_child(chest)
	chest.global_position = _event_point()
	_raise_beacon(chest.global_position, row["beacon_color"], chest,
			float(row["beacon_time"]), true)
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


## Grieta de esencia: un círculo de gemas de XP y un orbe de vida.
func _event_essence_rift(row: Dictionary) -> void:
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
	_raise_beacon(center, row["beacon_color"], null, float(row["beacon_time"]))
	_announce(String(row["announce"]))


## Un punto para un evento: lejos de un jugador vivo al azar, caminable y
## apoyado en el suelo (ver StageLayout.event_point).
func _event_point() -> Vector3:
	return _layout.event_point(event_min_distance, event_max_distance)


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
	# El tween es del COFRE, no del director: un cambio de etapa dentro de
	# los 0.4 s liberaría el cofre bajo un tween ajeno todavía animándolo.
	var tween := chest.create_tween()
	tween.tween_property(chest, "scale", Vector3.ONE * 0.05, 0.4) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(chest.queue_free)


## Levanta una baliza (Beacon.tscn) del color dado sobre `at`.
func _spawn_beacon(at: Vector3, color: Color) -> Node3D:
	var beacon := BEACON_SCENE.instantiate() as Beacon
	beacon.color = color
	_layout.stage_parent().add_child(beacon)
	beacon.global_position = at
	return beacon


## --- puertas del clima -----------------------------------------------------
## El clima vive en el nodo Weather; estas puertas siguen aquí porque otros
## nodos llegan por el grupo "world_director": event_altar.gd, enemy_base.gd,
## arena_probe.gd, hud.gd.

## La fila de WEATHER_CATALOG con ese id, o vacío (arena_probe.gd la usa).
static func weather_row(id: String) -> Dictionary:
	return WeatherDirector.weather_row(id)


## FUERZA un clima: detiene el que haya y empieza aunque no haya pasado la
## pausa (el altar de evento, el probe, BONK_WEATHER_NOW).
func start_sky_event(kind: String) -> void:
	_weather.start_sky_event(kind)


## Un clima al azar que el altar de evento puede invocar.
func random_altar_weather() -> String:
	return _weather.random_altar_weather()


## Un charco de ácido durante la lluvia radiactiva (EnemyBase al morir).
func spawn_acid_pool(at: Vector3) -> void:
	_weather.spawn_acid_pool(at)


## Verdadero mientras `id` sea el clima activo.
func is_weather_active(id: String) -> bool:
	return _weather.is_weather_active(id)


func _free_beacon(beacon: Node3D) -> void:
	if beacon != null and is_instance_valid(beacon):
		beacon.queue_free()


## Muestra un aviso centrado en el HUD (grupo "boss_ui").
func _announce(message: String) -> void:
	get_tree().call_group("boss_ui", "announce", message)
