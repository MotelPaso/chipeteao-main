class_name BossField
extends Node3D
## Los LÍMITES del campo de batalla de un jefe (nodo de una BossArena, grupo
## "arena_bounds"): un CLARO redondo con unas pocas coberturas adentro. Es lo
## que en un mapa hace el scatter: responde por nombre las mismas preguntas
## (is_walkable, can_place, nearest_place, random_walkable_point…), así el
## jefe, el botín, el Vuelo y el harness funcionan aquí sin saber dónde están.
##
## El claro es el círculo de `clearing_radius` metros alrededor de este nodo.
## Las COBERTURAS son los cuerpos del grupo "boss_cover" de la misma arena: su
## huella en el suelo sale de sus propias formas de colisión (el contorno
## convexo de todas: apenas más que lo que choca). Fuera del claro y dentro de
## una cobertura no se camina ni se coloca nada, y encima de una cobertura
## nadie se queda parado (CoverPerch).
##
## También levanta el BORDE: un anillo de paredes altas sin dibujo justo
## donde termina el claro (como los muros Perimeter de un mapa), para que
## nadie salga caminando, saltando ni volando. El arrecife y las piezas
## grandes que se ven en el borde van por fuera de ese anillo.

## Grupo de las coberturas del claro (cuerpos con colisión en la capa 1).
const COVER_GROUP: StringName = &"boss_cover"
## Capa de colisión del mundo.
const WORLD_LAYER: int = 1
## Lados con que se aproxima el contorno redondo de una forma de colisión.
const ROUND_SIDES: int = 12
## Paso, en metros, de los anillos donde nearest_place busca un lugar libre.
const SEARCH_STEP: float = 0.75
## Puntos por anillo de esa búsqueda.
const SEARCH_SPOKES: int = 16
## Intentos de random_walkable_point antes de devolver el centro.
const RANDOM_TRIES: int = 64

@export_group("Arena")
## Mitad del lado del suelo de la arena, en metros (el Terrain mide 2x esto). Tiene que pasar de clearing_radius: lo que sobra es el borde que se ve y no se pisa. Lo leen el Terrain, el Backdrop, los jefes y el Vuelo por el grupo "arena_bounds".
@export var arena_half_extent: float = 100.0
## Radio del claro donde se pelea, en metros.
@export var clearing_radius: float = 52.0

@export_group("Colocación")
## Metros que guarda con el borde del claro y con cada cobertura lo que se COLOCA (el jefe, un cofre, el portal): así nada queda pegado a una pared.
@export var place_margin: float = 1.5
## Tope, en metros, del margen propio de quien pregunta dónde colocar algo. Un jefe pide el suyo pensando en los cortes de un mapa (la langosta, 5 m); aquí el borde y las coberturas son sólidos y bajos, y con un margen así pegarse a ellos dejaría al raider fuera del alcance de sus saltos y sus salidas de túnel. Más alto = el jefe cae más lejos de las coberturas y del borde.
@export var asked_margin_cap: float = 2.0

@export_group("Borde")
## Altura de la pared sin dibujo del borde, en metros (más que el techo del Vuelo).
@export var wall_height: float = 24.0
## Grosor de esa pared, en metros.
@export var wall_thickness: float = 2.0
## Tramos rectos con que se arma el anillo: más tramos, más redondo.
@export_range(12, 96) var wall_segments: int = 48

@export_group("Coberturas")
## Segundos que un raider puede quedarse parado ENCIMA de una cobertura antes de bajar solo a la arena libre más cercana: las coberturas son para esconderse detrás, no para pelear desde arriba.
@export var perch_seconds: float = 0.4
## Metros sobre la arena desde los que un raider apoyado dentro de la huella de una cobertura cuenta como encima de ella.
@export var perch_height: float = 1.0

## Huella en el suelo de cada cobertura: {polygon, center, radius}. `polygon`
## es el contorno convexo (PackedVector2Array, XZ de mundo) y `center`/`radius`
## el círculo que lo envuelve. Se arma la primera vez que alguien pregunta.
var _footprints: Array[Dictionary] = []
var _footprints_built: bool = false
var _rng := RandomNumberGenerator.new()
## Nadie se queda parado encima de una cobertura (ver CoverPerch).
@onready var _perch := CoverPerch.new(self)


func _enter_tree() -> void:
	# Antes del _ready de cualquier hermano: el Terrain y el spawner lo buscan
	# ahí, igual que al scatter de un mapa.
	add_to_group("arena_bounds")


func _ready() -> void:
	_rng.seed = randi()
	_raise_wall()


func _physics_process(delta: float) -> void:
	_perch.tick(delta, perch_seconds, perch_height, place_margin)


# --- Fachada del grupo "arena_bounds": otros nodos llaman estos métodos por
# nombre (jefes, botín, jugador, harness). Conservar nombres y firmas.

## True si `xz` cae en el claro y fuera de toda cobertura.
func is_walkable(xz: Vector2) -> bool:
	return _in_clearing(xz, 0.0) and not _in_cover(xz, 0.0)


## True: lo que un jefe suelta en este campo (cofres, gemas, orbes) se corre
## al lugar libre más cercano, fuera de las coberturas y del borde. Lo
## preguntan EnemyLoot.drop_point y pickup_point.
func clears_drops() -> bool:
	return true


## True si en `xz` se puede COLOCAR algo: dentro del claro y a place_margin
## más `margin` metros (hasta asked_margin_cap) de su borde y de cada cobertura.
func can_place(xz: Vector2, margin: float = 0.0) -> bool:
	var gap := place_margin + clampf(margin, 0.0, asked_margin_cap)
	return _in_clearing(xz, gap) and not _in_cover(xz, gap)


## Lo mismo que can_place: aquí no hay cortes ni puentes que distinguir.
func can_build(xz: Vector2, margin: float = 0.0) -> bool:
	return can_place(xz, margin)


## Lo mismo que can_place, para la decoración que brota del suelo del claro.
func can_grow(xz: Vector2, margin: float = 0.0) -> bool:
	return can_place(xz, margin)


## El punto más cercano a `xz` donde can_place dice que sí (el mismo `xz` si
## sirve). Con `also`, el punto además tiene que pasar esa pregunta (recibe el
## XZ). Busca en anillos alrededor de `xz`, sin RNG; si no encuentra, el centro.
func nearest_place(xz: Vector2, margin: float = 0.0, also: Callable = Callable()) -> Vector2:
	if _fits(xz, margin, also):
		return xz
	var reach := clearing_radius * 2.0
	var radius := SEARCH_STEP
	while radius <= reach:
		var best := Vector2.INF
		for spoke: int in SEARCH_SPOKES:
			var angle := TAU * float(spoke) / float(SEARCH_SPOKES)
			var candidate := xz + Vector2(cos(angle), sin(angle)) * radius
			if _fits(candidate, margin, also) and (best == Vector2.INF
					or candidate.length_squared() < best.length_squared()):
				# Entre los del mismo anillo, el que mira al centro del claro.
				best = candidate
		if best != Vector2.INF:
			return best
		radius += SEARCH_STEP
	return _center()


## Un punto del claro al azar (uniforme sobre su área) donde se puede colocar
## algo, a `margin` metros del borde; el centro si RANDOM_TRIES intentos fallan.
func random_walkable_point(margin: float = 4.0) -> Vector2:
	var reach := maxf(clearing_radius - place_margin - margin, 0.0)
	for _attempt: int in RANDOM_TRIES:
		var angle := _rng.randf() * TAU
		var candidate := _center() + Vector2(cos(angle), sin(angle)) * reach * sqrt(_rng.randf())
		if can_place(candidate, margin):
			return candidate
	return _center()


## Aquí no hay puentes que la horda cruce por debajo.
func horde_lanes() -> ReliefLanes:
	return null


## Una arena de jefe se construye igual en cada viaje: no hay semilla de partida.
func run_seed() -> int:
	return 0


## Sin mesetas: el Terrain no aplana ningún claro extra.
func mesa_sites() -> PackedVector2Array:
	return PackedVector2Array()


## Sin máscara de celdas: las preguntas de celda existen para el harness, que
## las hace a cualquier "arena_bounds".
func blocked_cells() -> Array[Vector2i]:
	return []


func blocked_cell_count() -> int:
	return 0


func open_cell_count() -> int:
	var cells := int(round(arena_half_extent * 2.0 / cell_size()))
	return cells * cells


func cell_size() -> float:
	return 5.0


func cell_of(xz: Vector2) -> Vector2i:
	return Vector2i(floori((xz.x + arena_half_extent) / cell_size()),
			floori((xz.y + arena_half_extent) / cell_size()))


func cell_center(cell: Vector2i) -> Vector2:
	return Vector2((float(cell.x) + 0.5) * cell_size() - arena_half_extent,
			(float(cell.y) + 0.5) * cell_size() - arena_half_extent)


# --- lo que piden la arena y el harness ---------------------------------------

## Las coberturas del claro: los cuerpos del grupo "boss_cover" de esta arena.
func covers() -> Array[Node3D]:
	var found: Array[Node3D] = []
	var arena := get_parent()
	for node: Node in get_tree().get_nodes_in_group(COVER_GROUP):
		var cover := node as Node3D
		if cover != null and (arena == null or arena.is_ancestor_of(cover)):
			found.append(cover)
	return found


## La huella de cada cobertura: su contorno convexo en el suelo (XZ de mundo).
func cover_outlines() -> Array[PackedVector2Array]:
	_build_footprints()
	var outlines: Array[PackedVector2Array] = []
	for footprint: Dictionary in _footprints:
		outlines.append(footprint["polygon"] as PackedVector2Array)
	return outlines


## Metros de `xz` a la cobertura más cercana (0 dentro de una; INF sin coberturas).
func cover_distance(xz: Vector2) -> float:
	_build_footprints()
	var nearest := INF
	for footprint: Dictionary in _footprints:
		nearest = minf(nearest, _polygon_distance(xz, footprint["polygon"] as PackedVector2Array))
	return nearest


## True si llevar un cuerpo por tierra, en línea recta, de `from` a `to` lo
## mete en una cobertura o lo saca del claro: el tramo cruza una huella, o
## termina a menos de `clearance` metros de una (o del borde) acercándose.
## Alejarse nunca se bloquea: quien ya está pegado puede salir. Lo pregunta
## un jefe cuando un ataque lo desliza sin chocar con nada (una embestida).
func blocks_path(from: Vector2, to: Vector2, clearance: float = 0.0) -> bool:
	var centre := _center()
	var out := to.distance_to(centre)
	if out > clearing_radius - clearance and out > from.distance_to(centre):
		return true
	_build_footprints()
	for footprint: Dictionary in _footprints:
		var middle := footprint["center"] as Vector2
		var reach := float(footprint["radius"]) + clearance
		if Geometry2D.get_closest_point_to_segment(middle, from, to).distance_to(middle) > reach:
			continue
		var polygon := footprint["polygon"] as PackedVector2Array
		var starts := _polygon_distance(from, polygon)
		var ends := _polygon_distance(to, polygon)
		if ends <= clearance and ends < starts:
			return true
		if starts > 0.0 and ends > 0.0 and _crosses(from, to, polygon):
			return true
	return false


# --- privados -------------------------------------------------------------------

func _center() -> Vector2:
	return Vector2(global_position.x, global_position.z)


func _fits(xz: Vector2, margin: float, also: Callable) -> bool:
	return can_place(xz, margin) and (not also.is_valid() or bool(also.call(xz)))


## True si `xz` queda dentro del claro, a `gap` metros o más de su borde.
func _in_clearing(xz: Vector2, gap: float) -> bool:
	var reach := clearing_radius - gap
	return reach > 0.0 and xz.distance_squared_to(_center()) <= reach * reach


## True si `xz` cae dentro de una cobertura o a menos de `gap` metros de ella.
func _in_cover(xz: Vector2, gap: float) -> bool:
	_build_footprints()
	for footprint: Dictionary in _footprints:
		var reach := float(footprint["radius"]) + gap
		if xz.distance_squared_to(footprint["center"] as Vector2) > reach * reach:
			continue
		if _polygon_distance(xz, footprint["polygon"] as PackedVector2Array) <= gap:
			return true
	return false


## Metros de `point` al contorno `polygon` (0 si cae adentro).
func _polygon_distance(point: Vector2, polygon: PackedVector2Array) -> float:
	if polygon.size() < 3:
		return INF
	if Geometry2D.is_point_in_polygon(point, polygon):
		return 0.0
	var nearest := INF
	for index: int in polygon.size():
		var from := polygon[index]
		var to := polygon[(index + 1) % polygon.size()]
		nearest = minf(nearest,
				point.distance_to(Geometry2D.get_closest_point_to_segment(point, from, to)))
	return nearest


## True si el tramo de `from` a `to` corta algún lado del contorno `polygon`.
func _crosses(from: Vector2, to: Vector2, polygon: PackedVector2Array) -> bool:
	for index: int in polygon.size():
		if Geometry2D.segment_intersects_segment(from, to, polygon[index],
				polygon[(index + 1) % polygon.size()]) != null:
			return true
	return false


## Arma la huella de cada cobertura con sus formas de colisión. Se guarda una
## sola vez, en cuanto todas las coberturas armaron sus formas (las coberturas
## no se mueven); antes se vuelve a medir en cada pregunta.
func _build_footprints() -> void:
	if _footprints_built or not is_inside_tree():
		return
	var arena := get_parent()
	# Las coberturas entran a su grupo al entrar al árbol y arman sus formas en
	# su _ready: con todas listas, la huella ya no cambia y se guarda.
	var found := covers()
	var all_ready := true
	for cover: Node3D in found:
		all_ready = all_ready and cover.is_node_ready()
	_footprints_built = arena == null or arena.is_node_ready() or all_ready
	_footprints.clear()
	for cover: Node3D in found:
		var points := PackedVector2Array()
		for node: Node in _collision_holders(cover):
			points.append_array(_shape_outline(node as CollisionShape3D))
		if points.size() < 3:
			continue
		var polygon := Geometry2D.convex_hull(points)
		# convex_hull repite el primer punto al final.
		if polygon.size() > 3 and polygon[0].is_equal_approx(polygon[polygon.size() - 1]):
			polygon.remove_at(polygon.size() - 1)
		var center := Vector2.ZERO
		for corner: Vector2 in polygon:
			center += corner
		center /= float(polygon.size())
		var radius := 0.0
		for corner: Vector2 in polygon:
			radius = maxf(radius, corner.distance_to(center))
		_footprints.append({"polygon": polygon, "center": center, "radius": radius})


## Las formas de colisión de `cover` (él mismo o sus cuerpos hijos) que están
## en la capa del mundo.
func _collision_holders(cover: Node3D) -> Array[Node]:
	var holders: Array[Node] = []
	for node: Node in cover.find_children("*", "CollisionShape3D", true, false):
		var holder := node as CollisionShape3D
		var body := holder.get_parent() as CollisionObject3D
		if holder.disabled or holder.shape == null or body == null \
				or body.collision_layer & WORLD_LAYER == 0:
			continue
		holders.append(holder)
	return holders


## Los puntos de la forma de `holder` proyectados al suelo (XZ de mundo).
func _shape_outline(holder: CollisionShape3D) -> PackedVector2Array:
	var local: Array[Vector3] = []
	var shape := holder.shape
	if shape is BoxShape3D:
		var half := (shape as BoxShape3D).size * 0.5
		for x: float in [-half.x, half.x]:
			for y: float in [-half.y, half.y]:
				for z: float in [-half.z, half.z]:
					local.append(Vector3(x, y, z))
	elif shape is SphereShape3D:
		local = _ring((shape as SphereShape3D).radius, [0.0])
	elif shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		local = _ring(cylinder.radius, [-cylinder.height * 0.5, cylinder.height * 0.5])
	elif shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		var reach := maxf(capsule.height * 0.5 - capsule.radius, 0.0)
		local = _ring(capsule.radius, [-reach, reach])
		local.append(Vector3(0.0, capsule.height * 0.5, 0.0))
		local.append(Vector3(0.0, -capsule.height * 0.5, 0.0))
	elif shape is ConvexPolygonShape3D:
		for point: Vector3 in (shape as ConvexPolygonShape3D).points:
			local.append(point)
	elif shape is ConcavePolygonShape3D:
		for point: Vector3 in (shape as ConcavePolygonShape3D).get_faces():
			local.append(point)
	var outline := PackedVector2Array()
	for point: Vector3 in local:
		var world := holder.global_transform * point
		outline.append(Vector2(world.x, world.z))
	return outline


## Un círculo de ROUND_SIDES puntos de radio `radius`, repetido en cada altura.
func _ring(radius: float, heights: Array[float]) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for height: float in heights:
		for side: int in ROUND_SIDES:
			var angle := TAU * float(side) / float(ROUND_SIDES)
			points.append(Vector3(cos(angle) * radius, height, sin(angle) * radius))
	return points


## Levanta el anillo de paredes del borde: tramos rectos cuya cara interior
## pasa por el círculo del claro, solapados en las esquinas para no dejar rendija.
func _raise_wall() -> void:
	var body := StaticBody3D.new()
	body.name = "Wall"
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	add_child(body)
	var segments := maxi(wall_segments, 12)
	# La cara interior de cada tramo toca el círculo en su punto medio; el
	# tramo se alarga lo que haga falta para cerrar con sus vecinos.
	var centre_reach := clearing_radius + wall_thickness * 0.5
	var outer := clearing_radius + wall_thickness
	var length := 2.0 * outer * tan(PI / float(segments)) + wall_thickness
	var box := BoxShape3D.new()
	box.size = Vector3(length, wall_height, wall_thickness)
	for index: int in segments:
		var angle := TAU * float(index) / float(segments)
		var holder := CollisionShape3D.new()
		holder.shape = box
		holder.position = Vector3(cos(angle) * centre_reach, wall_height * 0.5 - 2.0,
				sin(angle) * centre_reach)
		# El grosor (eje Z de la caja) apunta hacia afuera.
		holder.rotation.y = PI * 0.5 - angle
		body.add_child(holder)
