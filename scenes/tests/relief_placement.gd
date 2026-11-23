class_name ReliefPlacement
extends RefCounted
## El barrido de COLOCACIÓN de una arena con relieve por zonas. Lo corre
## ReliefSweeps al empezar la etapa y otra vez a los 120 s, y revisa lo que
## hay puesto en el mapa contra los cortes:
##
##   on_relief           algo sobre un corte, una rampa o un puente
##   misplaced           algo enterrado o flotando
##   raider_unreachable  un POI, o un lugar que el director elegiría para la
##                       salida o un evento, al que un raider no llega (o
##                       del que no vuelve)
##   horde_unreachable   un spawn desde el que la horda no llega
##   crowding            una meseta, una plataforma o una formación pegada
##                       al borde o al pie de un corte
##
## Imprime `Relief sweep: placement at=<tag> …` y, por cada conteo que no da
## cero, líneas `Relief sweep detail:` con el lugar. NUNCA se afloja una
## tolerancia de aquí para hacerlo pasar: cede el relieve o quien coloca.

## Metros a un corte, rampa o puente bajo los cuales algo está "encima":
## para un prop o un POI (la cornisa visible mide 3.3 m) y para un spawn.
const ON_RELIEF_PROP: float = 3.5
const ON_RELIEF_SPAWN: float = 2.5
## Metros que una meseta, una plataforma o una formación guarda con el borde
## o el pie de un corte.
const CROWDING: float = 3.0
## Tolerancia en metros entre la altura de algo y el piso que tiene debajo.
const SETTLE: float = 0.4
## Radio en metros donde se busca la celda abierta de un POI o de un spawn,
## y ventana de altura alrededor de la suya.
const POI_REACH: float = 2.5
const SPAWN_REACH: float = 2.0
const LEVEL_WINDOW: float = 1.5
## Spawns muestreados de cada tipo (anillo y banda): 200 en total.
const SPAWN_SAMPLES: int = 100
## Lugares muestreados de cada tipo que el director elige durante la etapa
## (la salida y los eventos): 2000 en total. Son muchos porque lo que se
## busca, un punto encima de un tronco, sale en menos de uno de cada cien.
const PLACE_SAMPLES: int = 1000
## Medio lado de una plataforma y media rampa de meseta a escala 1, en metros.
const PLATFORM_REACH: float = 4.3
const RAMP_REACH: float = 2.5
## Lo que una formación asoma fuera de sus celdas (RockFormationStyle.margin_max).
const FORMATION_SKIRT: float = 2.0
## Muestras con nombre por barrido cuando un conteo no da cero.
const DETAIL_LIMIT: int = 4

var _tree: SceneTree = null
var _arena: Node3D = null
var _terrain: Terrain = null
var _bounds: Node3D = null
var _raiders: Array[RID] = []
var _graph: ReliefGraph = null
## 1 en las celdas desde las que el raider (o la horda) llega al spawn y vuelve.
var _raider_ok := PackedByteArray()
var _horde_ok := PackedByteArray()


## Lo que el barrido necesita de la etapa: lo arma ReliefSweeps.run().
func setup(tree: SceneTree, arena: Node3D, terrain: Terrain, bounds: Node3D,
		raiders: Array[RID], graph: ReliefGraph, raider_ok: PackedByteArray,
		horde_ok: PackedByteArray) -> void:
	_tree = tree
	_arena = arena
	_terrain = terrain
	_bounds = bounds
	_raiders = raiders
	_graph = graph
	_raider_ok = raider_ok
	_horde_ok = horde_ok


## Corre el barrido y lo imprime con la etiqueta `tag` (start, 120…).
func run(tag: String) -> void:
	var bad := {"on_relief": 0, "misplaced": 0, "raider_unreachable": 0,
			"horde_unreachable": 0, "crowding": 0}
	var notes: Array[String] = []
	var props := _check_props(bad, notes)
	var pois := _check_pois(bad, notes)
	var spawns := _check_spawns(bad, notes)
	var places := _check_places(bad, notes)
	_check_formations(bad, notes)
	print(("Relief sweep: placement at=%s props=%d pois=%d spawns=%d places=%d on_relief=%d"
			+ " misplaced=%d raider_unreachable=%d horde_unreachable=%d crowding=%d") % [tag,
			props, pois, spawns, places, bad["on_relief"], bad["misplaced"],
			bad["raider_unreachable"], bad["horde_unreachable"], bad["crowding"]])
	for note: String in notes:
		print("Relief sweep detail: placement at=%s %s" % [tag, note])


## Props del scatter: nada sobre un corte, rampa o puente, nada enterrado ni
## flotando, y mesetas y plataformas lejos de los cortes.
func _check_props(bad: Dictionary, notes: Array[String]) -> int:
	var count := 0
	for node: Node in _bounds.get_children():
		var prop := node as Node3D
		# La roca de un corte, un puente, una formación y las estructuras del
		# relieve (portales, hito, agua) son el relieve mismo, no algo puesto
		# encima: que no tapen un paso lo comprueban los barridos de alcance.
		# La vegetación del suelo y el bosque de afuera del muro no tienen
		# colisión (y el bosque de afuera ni siquiera está en la arena).
		if prop == null or prop is CliffWall or prop is Bridge or prop is RockFormation \
				or prop.is_in_group(ReliefStructures.GROUP) or prop is GroundCover \
				or prop is ForestEdge:
			continue
		count += 1
		var xz := Vector2(prop.global_position.x, prop.global_position.z)
		var near := _terrain.relief_distance(xz, 24.0)
		var what := "prop %s" % prop.scene_file_path.get_file()
		if near < ON_RELIEF_PROP:
			_flag(bad, "on_relief", notes, what, prop.global_position)
		if not _settled(prop):
			_flag(bad, "misplaced", notes, what, prop.global_position)
		var reach := 0.0
		if ReliefGraph.PLATFORM_SCENES.has(prop.scene_file_path):
			reach = PLATFORM_REACH * prop.scale.x
		elif ReliefGraph.RAMP_SCENES.has(prop.scene_file_path):
			reach = RAMP_REACH * prop.scale.x
		if reach > 0.0 and near - reach < CROWDING:
			_flag(bad, "crowding", notes, what, prop.global_position)
	return count


## POIs: fuera de cortes, rampas y puentes, apoyados, y en una celda que un
## raider alcanza y de la que vuelve. Uno ya gastado no cuenta: se está
## hundiendo (Interactable.sink_away) y nadie tiene que llegar a él.
func _check_pois(bad: Dictionary, notes: Array[String]) -> int:
	var count := 0
	for node: Node in _arena.find_children("*", "Node3D", true, false):
		var poi := node as Interactable
		if poi == null or poi.is_queued_for_deletion() or not poi.is_inside_tree() \
				or not poi.available:
			continue
		count += 1
		var at := poi.global_position
		var xz := Vector2(at.x, at.z)
		var what := "poi %s" % poi.name
		if _terrain.relief_distance(xz, ON_RELIEF_PROP) < ON_RELIEF_PROP:
			_flag(bad, "on_relief", notes, what, at)
		if not _settled(poi):
			_flag(bad, "misplaced", notes, what, at)
		var cell := _graph.nearest_open(xz, POI_REACH, at.y, LEVEL_WINDOW)
		if cell == ReliefGraph.NONE or _raider_ok[cell] == 0:
			_flag(bad, "raider_unreachable", notes, what, at)
	return count


## Spawns muestreados del anillo y de la banda de oleadas alrededor del
## raider líder: fuera del relieve, apoyados y donde la horda llega y vuelve.
func _check_spawns(bad: Dictionary, notes: Array[String]) -> int:
	var spawner: EnemySpawner = null
	for node: Node in _tree.get_nodes_in_group(&"enemy_spawner"):
		if _arena.is_ancestor_of(node):
			spawner = node as EnemySpawner
	var lead := Coop.nearest_player(_tree, Vector3.ZERO)
	if spawner == null or lead == null:
		return 0
	var points: SpawnPoints = spawner.get("_points")
	var count := 0
	for sample in SPAWN_SAMPLES * 2:
		var at := spawner.ring_position(lead)
		var what := "ring spawn"
		if sample >= SPAWN_SAMPLES:
			what = "band spawn"
			at = points.on_ground(points.band_position(lead.global_position,
					spawner.surge_min_radius, spawner.surge_max_radius, randf() * TAU))
		count += 1
		var xz := Vector2(at.x, at.z)
		if _terrain.relief_distance(xz, ON_RELIEF_SPAWN) < ON_RELIEF_SPAWN:
			_flag(bad, "on_relief", notes, what, at)
		if _buried(at, []) or at.y - _floor_under(at, []) > SETTLE:
			_flag(bad, "misplaced", notes, what, at)
		var cell := _graph.nearest_open(xz, SPAWN_REACH, at.y, LEVEL_WINDOW)
		if cell == ReliefGraph.NONE or _horde_ok[cell] == 0:
			_flag(bad, "horde_unreachable", notes, what, at)
	return count


## Lugares que el director elige durante la etapa, muestreados con sus
## propias funciones (la salida, lejos de todos, y el anillo de los eventos
## alrededor del raider líder): fuera del relieve, apoyados, y donde un
## raider llega y vuelve. Encima de un tronco nadie alcanza un portal.
func _check_places(bad: Dictionary, notes: Array[String]) -> int:
	var director := _tree.get_first_node_in_group(&"world_director")
	var lead := Coop.nearest_player(_tree, Vector3.ZERO)
	if director == null or lead == null:
		return 0
	var layout := director.get("_layout") as StageLayout
	if layout == null:
		return 0
	var exit_gap := float(director.get("exit_portal_min_distance"))
	var event_min := float(director.get("event_min_distance"))
	var event_max := float(director.get("event_max_distance"))
	var count := 0
	for sample in PLACE_SAMPLES * 2:
		var what := "exit point"
		var at := Vector3.INF
		if sample < PLACE_SAMPLES:
			at = layout.exit_portal_point(exit_gap)
		else:
			what = "event point"
			at = layout.rain_point(lead.global_position, event_min, event_max)
		if at == Vector3.INF:
			continue
		count += 1
		var xz := Vector2(at.x, at.z)
		if _terrain.relief_distance(xz, ON_RELIEF_PROP) < ON_RELIEF_PROP:
			_flag(bad, "on_relief", notes, what, at)
		if _buried(at, []) or at.y - _floor_under(at, []) > SETTLE:
			_flag(bad, "misplaced", notes, what, at)
		var cell := _graph.nearest_open(xz, POI_REACH, at.y, LEVEL_WINDOW)
		if cell == ReliefGraph.NONE or _raider_ok[cell] == 0:
			_flag(bad, "raider_unreachable", notes, what, at)
	return count


## Formaciones de la máscara: ninguna pegada al borde o al pie de un corte.
func _check_formations(bad: Dictionary, notes: Array[String]) -> void:
	var cell_size := float(_bounds.call(&"cell_size"))
	var reach := cell_size * 0.7072 + FORMATION_SKIRT
	var raw: Variant = _bounds.call(&"blocked_cells")
	if not (raw is Array):
		return
	for cell: Variant in (raw as Array):
		var center: Vector2 = _bounds.call(&"cell_center", cell)
		if _terrain.relief_distance(center, reach + CROWDING) - reach < CROWDING:
			_flag(bad, "crowding", notes, "formation cell",
					Vector3(center.x, _terrain.height_at(center.x, center.y), center.y))


func _flag(bad: Dictionary, key: String, notes: Array[String], what: String,
		at: Vector3) -> void:
	bad[key] = int(bad[key]) + 1
	if notes.size() < DETAIL_LIMIT * 2:
		notes.append("%s: %s at (%.1f, %.1f, %.1f)" % [key, what, at.x, at.y, at.z])


## True si `node` está apoyado: nada sólido encima (enterrado) y un piso a
## SETTLE metros o menos por debajo (flotando), sin contar sus propios cuerpos.
func _settled(node: Node3D) -> bool:
	var own: Array[RID] = []
	if node is CollisionObject3D:
		own.append((node as CollisionObject3D).get_rid())
	for child: Node in node.find_children("*", "CollisionObject3D", true, false):
		own.append((child as CollisionObject3D).get_rid())
	var at := node.global_position
	if _buried(at, own):
		return false
	return at.y - _floor_under(at, own) <= SETTLE


## True si sobre `at` hay suelo, roca o un tablero: está enterrado. Un prop
## encima (la copa de otro árbol del borde) no entierra a nadie.
func _buried(at: Vector3, own: Array[RID]) -> bool:
	var excluded: Array[RID] = _raiders.duplicate()
	excluded.append_array(own)
	var space := _terrain.get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(
			Vector3(at.x, _terrain.max_height + 30.0, at.z), at + Vector3.UP * (SETTLE + 0.05),
			ReliefGraph.WORLD_LAYER)
	for attempt in ReliefGraph.MAX_RAY_PASSES:
		ray.exclude = excluded
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			return false
		if _graph._is_ground(hit["collider"]) or hit["collider"] is RockFormation:
			return true
		excluded.append(hit["rid"])
	return false


## Altura del primer piso bajo `at` (desde SETTLE metros por encima), o
## -INF si no hay nada en 3 m.
func _floor_under(at: Vector3, own: Array[RID]) -> float:
	var excluded: Array[RID] = _raiders.duplicate()
	excluded.append_array(own)
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * SETTLE,
			at + Vector3.DOWN * 3.0, ReliefGraph.WORLD_LAYER)
	ray.exclude = excluded
	var hit := _terrain.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return -INF
	return (hit["position"] as Vector3).y
