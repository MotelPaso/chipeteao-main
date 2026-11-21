class_name ReliefGraph
extends RefCounted
## El mapa de una arena con relieve por zonas visto como lo ve la FÍSICA:
## una celda por metro cuadrado, con el piso que un cuerpo encuentra ahí y
## los pasos que puede dar a sus vecinas. Lo arma el arnés una vez por etapa
## y lo usan los barridos (ReliefSweeps, ReliefPlacement) y el ruteo del bot
## (ReliefNav); los recorridos sobre él viven en ReliefSearch.
##
## PISO de una celda: lo primero que toca un rayo desde arriba que sea suelo
## o un tablero (el Terrain, la cornisa de un corte, un puente, una meseta y
## su rampa). Lo demás (troncos, rocas, formaciones) es obstáculo: el rayo
## lo atraviesa y sigue. En este juego nada caminable tiene hueco debajo,
## así que un piso por celda alcanza.
##
## CELDA ABIERTA: su piso tiene menos de 45 grados, no cae en una celda
## bloqueada de la máscara y la cápsula de un raider cabe parada ahí sin
## tocar nada. Las demás son:
## - JUSTA: piso caminable, pero la cápsula roza el suelo o la roca de un
##   corte (el pie de un acantilado, un pliegue). Se camina por ella; no
##   cuenta como lugar donde estar ni donde poner algo.
## - PARED: piso de 45 grados o más (la cara de un corte). Se pasa por
##   encima cayendo, saltando o trepando.
## - OBSTÁCULO: un prop o una formación de la máscara con su faldón de roca
##   (FORMATION_REACH metros más allá de sus celdas). No se pasa.
##
## PASOS entre celdas ABIERTAS o JUSTAS. En las cuatro direcciones rectas:
## - caminar: a la vecina si el desnivel es menor que el avance (45°). También
##   en diagonal, si un cuerpo cabe por la esquina (se sondea con física
##   cuando alguna de las dos vecinas rectas no se camina);
## - caer: a una celda más baja, pasando por encima de celdas PARED. Es de
##   ida solamente;
## - saltar (raider): subir hasta RAIDER_JUMP metros;
## - trepar (horda): subir hasta HORDE_CLIMB metros si lo que hay delante es
##   una cara de 60 grados o más.

## Reglas de los pasos (metros). Son las del enunciado del barrido: no se tocan
## para hacerlo pasar.
const RAIDER_JUMP: float = 1.5
const HORDE_CLIMB: float = 8.0
## Desnivel máximo por metro que todavía es caminar (45 grados).
const WALK_RISE: float = 1.0
## Coseno de 45 grados: un piso con la normal más acostada no se pisa.
const FLOOR_MIN_NORMAL_Y: float = 0.7071
## Normal.y máxima de una cara que la horda trepa (60 grados; el mismo 0.5
## de EnemyBase._blocked_by_geometry).
const CLIMB_MAX_NORMAL_Y: float = 0.5
## Celdas PARED que un paso puede pasar por encima (la cara de un corte de
## 6.4 m ocupa dos; el pie y el borde, una más cada uno).
const MAX_SKIP: int = 4
## La cápsula del raider (Player.tscn) y la holgura con que se la apoya.
const CAPSULE_RADIUS: float = 0.4
const CAPSULE_HEIGHT: float = 1.8
const CAPSULE_LIFT: float = 0.08
## Capa del mundo (suelo, props, muros). Los enemigos van en otra.
const WORLD_LAYER: int = 1
## Rayos por celda como máximo: cada obstáculo atravesado gasta uno.
const MAX_RAY_PASSES: int = 5
## Escenas de prop que son un tablero donde pararse, además de los tipos
## Terrain, CliffWall y Bridge: las plataformas de meseta y sus rampas.
const PLATFORM_SCENES: Array[String] = [
	"res://scenes/world/props/Platform.tscn", "res://scenes/world/props/RuinDais.tscn",
]
const RAMP_SCENES: Array[String] = [
	"res://scenes/world/props/Ramp.tscn", "res://scenes/world/props/RuinStairs.tscn",
]
const DECK_SCENES: Array[String] = [
	"res://scenes/world/props/Platform.tscn", "res://scenes/world/props/Ramp.tscn",
	"res://scenes/world/props/RuinDais.tscn", "res://scenes/world/props/RuinStairs.tscn",
]
## Estado de una celda (ver la cabecera). Hasta TIGHT se camina.
const OPEN: int = 0
const TIGHT: int = 1
const WALL: int = 2
const OBSTACLE: int = 3
## Las ocho direcciones, en el orden de los arreglos de pasos: primero las
## cuatro rectas, después las cuatro diagonales.
const STEPS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP,
	Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]
## Pasos por celda en raider_next y horde_next.
const WAYS: int = 8
## Lo que una formación asoma fuera de sus celdas de máscara, en metros
## (RockFormationStyle.margin_max): esa franja es roca, no suelo abierto.
const FORMATION_REACH: float = 2.0
## Tolerancia en metros entre el piso de una esquina y el de las dos celdas
## que une un paso en diagonal.
const CORNER_LEVEL: float = 0.7
## "Sin paso" en raider_next y horde_next.
const NONE: int = -1

## Celdas por lado y mitad del lado de la arena.
var side: int = 0
var half: float = 0.0
## Por celda: altura del piso, estado y adónde lleva cada dirección (WAYS
## por celda) para un raider y para la horda.
var floor_y := PackedFloat32Array()
var state := PackedByteArray()
var raider_next := PackedInt32Array()
var horde_next := PackedInt32Array()
## Rayos y consultas de forma gastados, para el log.
var rays: int = 0
var shapes: int = 0

var _space: PhysicsDirectSpaceState3D = null
var _ray := PhysicsRayQueryParameters3D.new()
var _fit := PhysicsShapeQueryParameters3D.new()
var _raiders: Array[RID] = []
var _top: float = 0.0
var _bottom: float = 0.0


## Arma el grafo de la arena de `terrain`. `bounds` es el scatter (máscara);
## `raiders` son los RID de los cuerpos del equipo, que comparten capa con el
## mundo y no son mundo.
func build(terrain: Terrain, bounds: Node3D, raiders: Array[RID]) -> void:
	_space = terrain.get_world_3d().direct_space_state
	_raiders = raiders
	half = terrain.size * 0.5
	side = int(round(terrain.size))
	_top = terrain.max_height + 30.0
	_bottom = terrain.min_height - 2.0
	floor_y.resize(side * side)
	state.resize(side * side)
	var capsule := CapsuleShape3D.new()
	capsule.radius = CAPSULE_RADIUS
	capsule.height = CAPSULE_HEIGHT
	_fit.shape = capsule
	_fit.collision_mask = WORLD_LAYER
	_fit.exclude = raiders
	_ray.collision_mask = WORLD_LAYER
	var rock := _formation_cells(bounds)
	for index in side * side:
		_probe_cell(index, center(index), rock[index] == 1)
	raider_next.resize(side * side * WAYS)
	horde_next.resize(side * side * WAYS)
	raider_next.fill(NONE)
	horde_next.fill(NONE)
	for index in side * side:
		if state[index] <= TIGHT:
			_link_cell(index)
			_link_diagonals(index)


## Centro plano de una celda.
func center(index: int) -> Vector2:
	return Vector2(float(index % side) + 0.5 - half, float(index / side) + 0.5 - half)


## Punto de mundo donde se para un cuerpo en la celda.
func stand(index: int) -> Vector3:
	var flat := center(index)
	return Vector3(flat.x, floor_y[index], flat.y)


## Celda donde cae una posición plana, o NONE fuera de la arena.
func cell_of(xz: Vector2) -> int:
	var ix := floori(xz.x + half)
	var iz := floori(xz.y + half)
	if ix < 0 or iz < 0 or ix >= side or iz >= side:
		return NONE
	return iz * side + ix


## La celda abierta más cercana a `xz` dentro de `reach` metros (y, si se da
## `near_y`, a menos de `y_window` metros de esa altura), o NONE.
func nearest_open(xz: Vector2, reach: float, near_y: float = INF, y_window: float = 0.0) -> int:
	var home := cell_of(xz)
	if home == NONE:
		return NONE
	var best := NONE
	var best_distance := INF
	var span := ceili(reach)
	for dz in range(-span, span + 1):
		for dx in range(-span, span + 1):
			var ix := home % side + dx
			var iz := home / side + dz
			if ix < 0 or iz < 0 or ix >= side or iz >= side:
				continue
			var index := iz * side + ix
			if state[index] != OPEN:
				continue
			if near_y != INF and absf(floor_y[index] - near_y) > y_window:
				continue
			var distance := center(index).distance_to(xz)
			if distance <= reach and distance < best_distance:
				best_distance = distance
				best = index
	return best


# --- pisos -----------------------------------------------------------------------

## 1 en las celdas de 1 m que caen en una formación de la máscara: sus
## celdas bloqueadas más FORMATION_REACH metros de faldón alrededor.
func _formation_cells(bounds: Node3D) -> PackedByteArray:
	var rock := PackedByteArray()
	rock.resize(side * side)
	var cell_size := float(bounds.call(&"cell_size"))
	var raw: Variant = bounds.call(&"blocked_cells")
	if not (raw is Array):
		return rock
	for cell: Variant in (raw as Array):
		if not (cell is Vector2i):
			continue
		var low := Vector2(cell as Vector2i) * cell_size - Vector2.ONE * FORMATION_REACH
		var high := low + Vector2.ONE * (cell_size + FORMATION_REACH * 2.0)
		for iz in range(maxi(floori(low.y), 0), mini(ceili(high.y), side)):
			for ix in range(maxi(floori(low.x), 0), mini(ceili(high.x), side)):
				var at := Vector2(float(ix) + 0.5, float(iz) + 0.5)
				if at.x > low.x and at.x < high.x and at.y > low.y and at.y < high.y:
					rock[iz * side + ix] = 1
	return rock


## Busca el piso de la celda y decide su estado.
func _probe_cell(index: int, flat: Vector2, masked: bool) -> void:
	var excluded: Array[RID] = _raiders.duplicate()
	var hit: Dictionary = {}
	var through_obstacle := false
	for attempt in MAX_RAY_PASSES:
		_ray.from = Vector3(flat.x, _top, flat.y)
		_ray.to = Vector3(flat.x, _bottom, flat.y)
		_ray.exclude = excluded
		rays += 1
		hit = _space.intersect_ray(_ray)
		if hit.is_empty() or _is_ground(hit["collider"]):
			break
		# Un obstáculo: el rayo sigue por debajo de él.
		through_obstacle = true
		excluded.append(hit["rid"])
		hit = {}
	if hit.is_empty():
		floor_y[index] = _bottom
		state[index] = OBSTACLE
		return
	var point: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	floor_y[index] = point.y
	if masked:
		state[index] = OBSTACLE
		return
	if normal.y < FLOOR_MIN_NORMAL_Y:
		state[index] = OBSTACLE if through_obstacle else WALL
		return
	# La cápsula parada sobre el piso: en una pendiente su semiesfera de abajo
	# toca más arriba que su punto más bajo.
	var lift := CAPSULE_RADIUS / normal.y - CAPSULE_RADIUS + CAPSULE_LIFT
	_fit.transform = Transform3D(Basis(),
			Vector3(flat.x, point.y + lift + CAPSULE_HEIGHT * 0.5, flat.y))
	shapes += 1
	var touching := _space.intersect_shape(_fit, 4)
	if touching.is_empty():
		state[index] = OPEN
		return
	# Rozando suelo o roca de un corte: justa. Contra cualquier otra cosa:
	# obstáculo.
	state[index] = TIGHT
	for other: Dictionary in touching:
		if not _is_ground(other["collider"]):
			state[index] = OBSTACLE


## True si `collider` es suelo o un tablero donde pararse.
func _is_ground(collider: Variant) -> bool:
	if collider is Terrain or collider is CliffWall or collider is Bridge:
		return true
	var node := collider as Node
	return node != null and DECK_SCENES.has(node.scene_file_path)


# --- pasos -----------------------------------------------------------------------

## Calcula adónde lleva cada dirección desde la celda caminable `index`.
func _link_cell(index: int) -> void:
	var ix := index % side
	var iz := index / side
	var from_y := floor_y[index]
	for step in 4:
		var dir := STEPS[step]
		for reach_cells in range(1, MAX_SKIP + 2):
			var nx := ix + dir.x * reach_cells
			var nz := iz + dir.y * reach_cells
			if nx < 0 or nz < 0 or nx >= side or nz >= side:
				break
			var to := nz * side + nx
			if state[to] == OBSTACLE:
				break
			if state[to] == WALL:
				continue
			var rise := floor_y[to] - from_y
			if reach_cells == 1 and absf(rise) < WALK_RISE:
				raider_next[index * WAYS + step] = to
				horde_next[index * WAYS + step] = to
			elif rise < 0.0:
				raider_next[index * WAYS + step] = to
				horde_next[index * WAYS + step] = to
			else:
				if rise <= RAIDER_JUMP and reach_cells <= 2:
					raider_next[index * WAYS + step] = to
				if rise <= HORDE_CLIMB and _steep_face(index, dir, reach_cells, rise):
					horde_next[index * WAYS + step] = to
			break


## Los pasos en diagonal de la celda `index`: solo caminar, a la vecina
## caminable, si un cuerpo cabe por la esquina que comparten.
func _link_diagonals(index: int) -> void:
	var ix := index % side
	var iz := index / side
	var from_y := floor_y[index]
	for step in range(4, WAYS):
		var dir := STEPS[step]
		var nx := ix + dir.x
		var nz := iz + dir.y
		if nx < 0 or nz < 0 or nx >= side or nz >= side:
			continue
		var to := nz * side + nx
		if state[to] > TIGHT or absf(floor_y[to] - from_y) >= WALK_RISE * 1.4142:
			continue
		# Con las dos vecinas rectas caminables y a nivel, la esquina es suelo
		# corrido; si no, se sondea.
		var beside := iz * side + nx
		var behind := nz * side + ix
		var flat := state[beside] <= TIGHT and state[behind] <= TIGHT \
				and absf(floor_y[beside] - from_y) < WALK_RISE \
				and absf(floor_y[behind] - from_y) < WALK_RISE
		if flat or _corner_fits(index, to):
			raider_next[index * WAYS + step] = to
			horde_next[index * WAYS + step] = to


## True si un cuerpo pasa de `from` a `to` (vecinas en diagonal) por la
## esquina que comparten: ahí tiene que haber piso caminable a su nivel y
## caber la cápsula.
func _corner_fits(from: int, to: int) -> bool:
	var a := stand(from)
	var b := stand(to)
	var middle := (a + b) * 0.5
	_ray.from = Vector3(middle.x, maxf(a.y, b.y) + 1.5, middle.z)
	_ray.to = Vector3(middle.x, minf(a.y, b.y) - 1.0, middle.z)
	_ray.exclude = _raiders
	rays += 1
	var hit := _space.intersect_ray(_ray)
	if hit.is_empty() or not _is_ground(hit["collider"]):
		return false
	var point: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	if normal.y < FLOOR_MIN_NORMAL_Y or absf(point.y - middle.y) > CORNER_LEVEL:
		return false
	var lift := CAPSULE_RADIUS / normal.y - CAPSULE_RADIUS + CAPSULE_LIFT
	_fit.transform = Transform3D(Basis(),
			Vector3(middle.x, point.y + lift + CAPSULE_HEIGHT * 0.5, middle.z))
	shapes += 1
	for other: Dictionary in _space.intersect_shape(_fit, 4):
		if not _is_ground(other["collider"]):
			return false
	return true


## True si entre la celda `index` y la que está `reach_cells` más allá en
## `dir` hay una cara que la horda trepa: dos rayos horizontales a distinta
## altura, y los dos tienen que dar con algo de 60 grados o más.
func _steep_face(index: int, dir: Vector2i, reach_cells: int, rise: float) -> bool:
	var from := stand(index)
	var along := Vector3(float(dir.x), 0.0, float(dir.y))
	var hits := 0
	for height: float in [0.3, clampf(rise * 0.5, 0.45, 1.6)]:
		_ray.from = from + Vector3.UP * height
		_ray.to = _ray.from + along * (float(reach_cells) + 0.5)
		_ray.exclude = _raiders
		rays += 1
		var hit := _space.intersect_ray(_ray)
		if hit.is_empty():
			continue
		var normal: Vector3 = hit["normal"]
		if normal.y > CLIMB_MAX_NORMAL_Y:
			return false
		hits += 1
	return hits > 0
