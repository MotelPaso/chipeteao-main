class_name StageLayout
extends RefCounted
## Dónde cabe cada cosa en la etapa actual: la máscara caminable de la
## arena, los puntos que ya ocupan los POI, la altura del suelo y los
## muestreos de puntos (libres, en anillo, para el portal de salida). El
## WorldDirector crea uno nuevo en cada etapa y lo comparte con su nodo
## Weather.
## Los muestreos usan el RNG de la partida (BONK_GAME_SEED): cambiar el
## orden o la cantidad de tiradas cambia el mapa que sale con cada semilla.

## Intentos de muestreo de un punto libre para un POI.
const CLEAR_POINT_ATTEMPTS: int = 60
## Intentos de muestreo en un anillo antes de rendirse.
const RING_POINT_ATTEMPTS: int = 24
## Altura (metros) de la sonda de suelo cuando no hay terreno.
const GROUND_PROBE_HEIGHT: float = 20.0
## Con terreno, la sonda empieza esto sobre su punto más alto (cabe una
## meseta sobre una loma) y termina esto bajo el más bajo (metros).
const PROBE_HEADROOM: float = 30.0
const PROBE_UNDERSHOOT: float = 2.0
## Un POI del reparto puesto por encima de esta altura (metros) está sobre
## una plataforma y conserva su y; el resto se apoya en el relieve.
const POI_PLATFORM_Y: float = 0.5
## Semiancho (metros) que se usa si la arena no publica el suyo.
const DEFAULT_HALF_EXTENT: float = 80.0

## Distancias del reparto (metros). Sin valor propio: el director les copia
## sus exports del grupo "Reparto de POI" al crear el layout; edítalas ahí.
var bounds_margin: float
var min_distance_from_spawn: float
var min_distance_between: float
var min_distance_from_keepouts: float

## Arena de la etapa; null entre etapas.
var arena: Node3D = null

## Nodo que da acceso al árbol (el director).
var _host: Node = null
## Nodo de límites de la arena (el scatter, grupo "arena_bounds"): tamaño y
## máscara caminable.
var _bounds: Node3D = null
## Semiancho BRUTO de la arena; bounds_margin se resta en cada uso.
var _arena_half_extent: float = DEFAULT_HALF_EXTENT
## Puntos ya ocupados por un POI (movido o creado), para que lo siguiente
## guarde su distancia.
var _placed_points: Array[Vector2] = []
## Puntos fijos que evitar: plataformas y grupos de rocas.
var _anchor_points: Array[Vector2] = []
## Los POI movidos, para liberar el punto de los que el inicio irregular quita.
var _placed_pois: Array[Node3D] = []


## `stage_arena` null crea un layout vacío (entre etapas).
func _init(host: Node, stage_arena: Node3D = null) -> void:
	_host = host
	arena = stage_arena
	if stage_arena == null:
		return
	for node: Node in _tree().get_nodes_in_group("arena_bounds"):
		var bounds := node as Node3D
		if bounds != null and stage_arena.is_ancestor_of(bounds):
			_bounds = bounds
			_arena_half_extent = float(bounds.get("arena_half_extent"))
			break


## La arena de la etapa (la propia o, en medio de un cambio, la que
## publica RunRoot), o null si no hay ninguna.
func current_arena() -> Node3D:
	if arena != null and is_instance_valid(arena):
		return arena
	var root := _tree().get_first_node_in_group("run_root")
	if root != null and root.has_method("arena_root"):
		var found: Variant = root.call("arena_root")
		if found is Node3D and is_instance_valid(found):
			return found
	return null


## Padre de todo lo que se pone en la etapa: la arena, así un cambio de
## etapa se lo lleva todo. Sin arena (carreras en el cambio) usa el host,
## para no fallar.
func stage_parent() -> Node:
	var found := current_arena()
	return found if found != null else _host


## Crea `scene` bajo stage_parent() y la pone en `at` (el punto ya está
## sorteado antes de crear el nodo).
func spawn_at(scene: PackedScene, at: Vector3) -> Node3D:
	var node := scene.instantiate() as Node3D
	stage_parent().add_child(node)
	node.global_position = at
	return node


## --- máscara y suelo --------------------------------------------------------

func walkable_xz(xz: Vector2) -> bool:
	if _bounds == null or not _bounds.has_method("is_walkable"):
		return true
	return bool(_bounds.call("is_walkable", xz))


func walkable(pos: Vector3) -> bool:
	return walkable_xz(Vector2(pos.x, pos.z))


## Último recurso cuando el muestreo no encuentra nada: el muestreo de la
## propia máscara, que sabe dónde están las celdas abiertas.
func random_walkable_point() -> Vector2:
	if _bounds != null and _bounds.has_method("random_walkable_point"):
		var point: Variant = _bounds.call("random_walkable_point", bounds_margin)
		if point is Vector2:
			return point
	return Vector2.ZERO


## Altura del suelo (capa 1) bajo un punto: un POI bajo una meseta
## quedaría enterrado y su Area3D no vería al jugador que subió.
func ground_height(pos: Vector3) -> float:
	var space := _tree().root.world_3d.direct_space_state
	# El rayo cubre TODO el relieve: desde sobre la meseta más alta hasta
	# bajo la hondonada más honda.
	var terrain := Terrain.find(_tree())
	var top := GROUND_PROBE_HEIGHT
	var bottom := -1.0
	if terrain != null:
		top = terrain.max_height + PROBE_HEADROOM
		bottom = terrain.min_height - PROBE_UNDERSHOOT
	var ray := PhysicsRayQueryParameters3D.create(
			Vector3(pos.x, top, pos.z), Vector3(pos.x, bottom, pos.z), 1)
	# Los jugadores comparten la capa 1 con el mundo: una cabeza no es suelo.
	var excluded: Array[RID] = []
	for node: Node in Coop.alive_players(_tree()):
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


## Altura del terreno en un punto, o 0 sin terreno. Para apoyar algo en el
## suelo sin el rayo, que también vería los props de encima.
func terrain_height(xz: Vector2) -> float:
	var terrain := Terrain.find(_tree())
	return terrain.height_at(xz.x, xz.y) if terrain != null else 0.0


## --- reparto ----------------------------------------------------------------

## Mueve cada interactuable de "scatter_keepout" a un punto libre; el resto
## del grupo (plataformas, rocas) queda como obstáculo fijo.
func shuffle_ground_interactables() -> void:
	var movable: Array[Node3D] = []
	var anchors: Array[Vector2] = []
	for node: Node in _tree().get_nodes_in_group("scatter_keepout"):
		var spot := node as Node3D
		if spot == null:
			continue
		if spot is Interactable:
			movable.append(spot)
		else:
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
		var new_y := authored_y if authored_y > POI_PLATFORM_Y else terrain_height(spot_xz)
		poi.global_position = Vector3(spot_xz.x, new_y, spot_xz.y)
	_placed_points = placed
	_placed_pois = movable
	_anchor_points = anchors


## Rehace los puntos ocupados con los POI que siguen en pie, para que un
## punto liberado por el inicio irregular no reserve espacio alrededor de nada.
func refresh_placed_points() -> void:
	var points: Array[Vector2] = []
	for poi: Node3D in _placed_pois:
		if is_instance_valid(poi) and not poi.is_queued_for_deletion():
			points.append(Vector2(poi.global_position.x, poi.global_position.z))
	_placed_points = points


## Un punto libre nuevo para algo que se crea durante la etapa, apoyado en
## el terreno; queda anotado para los siguientes.
func claim_clear_point() -> Vector3:
	var spot := _find_clear_point(_arena_half_extent - bounds_margin, _placed_points, _anchor_points)
	_placed_points.append(spot)
	return Vector3(spot.x, terrain_height(spot), spot.y)


## --- muestreos --------------------------------------------------------------

## Una muestra en el anillo alrededor de `origin`, en la dirección `angle`
## (radianes) y a una distancia al azar entre los dos radios (metros),
## dentro de la franja de la arena. No mira la máscara ni el suelo.
func ring_sample(origin: Vector3, angle: float, min_distance: float,
		max_distance: float) -> Vector3:
	var limit := _arena_half_extent - bounds_margin
	var pos := origin + Vector3(cos(angle), 0.0, sin(angle)) \
			* randf_range(min_distance, max_distance)
	pos.x = clampf(pos.x, -limit, limit)
	pos.z = clampf(pos.z, -limit, limit)
	return pos


## Un punto CAMINABLE en el anillo alrededor de `origin` (sin altura), o
## Vector3.INF si no sale ninguno en RING_POINT_ATTEMPTS intentos.
func ring_point(origin: Vector3, min_distance: float, max_distance: float) -> Vector3:
	for attempt in RING_POINT_ATTEMPTS:
		var pos := ring_sample(origin, randf() * TAU, min_distance, max_distance)
		if walkable(pos):
			return pos
	return Vector3.INF


## Como ring_point, pero apoyado en el suelo. La lluvia y los meteoritos
## caen por aquí, así nada del clima termina dentro de una roca.
func rain_point(origin: Vector3, min_distance: float, max_distance: float) -> Vector3:
	var pos := ring_point(origin, min_distance, max_distance)
	if pos != Vector3.INF:
		pos.y = ground_height(pos)
	return pos


## Un punto lejos de un jugador vivo al azar, en una celda caminable y
## apoyado en lo que haya. Si todo el anillo está tapado, usa el muestreo
## de inicio, que respeta la máscara.
func event_point(min_distance: float, max_distance: float) -> Vector3:
	var anchor := Coop.random_player(_tree())
	var origin := anchor.global_position if anchor != null else Vector3.ZERO
	var pos := ring_point(origin, min_distance, max_distance)
	if pos == Vector3.INF:
		pos = claim_clear_point()
	pos.y = ground_height(pos)
	return pos


## Un punto caminable al menos a `min_distance` (metros) de todo jugador:
## la salida es un destino, no algo que se pisa al terminar. Muestrea el
## cuadrado de la arena y se queda con el punto más lejano.
func exit_portal_point(min_distance: float) -> Vector3:
	var limit := _arena_half_extent - bounds_margin
	var best := Vector3.ZERO
	var best_distance := -1.0
	for attempt in CLEAR_POINT_ATTEMPTS:
		var candidate := Vector3(randf_range(-limit, limit), 0.0, randf_range(-limit, limit))
		if not walkable(candidate):
			continue
		var nearest := distance_to_nearest_player(candidate)
		if nearest > best_distance:
			best_distance = nearest
			best = candidate
		if nearest >= min_distance:
			break
	if best_distance < 0.0:
		# Todas las muestras cayeron en una pared de la máscara.
		var point := random_walkable_point()
		best = Vector3(point.x, 0.0, point.y)
	best.y = ground_height(best)
	return best


## Distancia (metros) al jugador vivo más cercano; 0 si no hay ninguno.
func distance_to_nearest_player(at: Vector3) -> float:
	var nearest := INF
	for node: Node in Coop.alive_players(_tree()):
		var body := node as Node3D
		if body != null:
			nearest = minf(nearest, at.distance_to(body.global_position))
	return 0.0 if nearest == INF else nearest


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
		if not walkable_xz(candidate):
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
		return random_walkable_point()
	return best


func _tree() -> SceneTree:
	return _host.get_tree()
