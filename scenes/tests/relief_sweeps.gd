class_name ReliefSweeps
extends RefCounted
## Los barridos estáticos de una arena con relieve por zonas. Corren al
## empezar la etapa (run) y la colocación otra vez más tarde (placement), y
## cada uno imprime UNA línea `Relief sweep: …` que tools/verificar.sh lee:
##
##   gap        caras tocables del suelo o de la roca entre 45 y 60 grados
##   raider     celdas abiertas que el spawn no alcanza / que no vuelven a él
##   horde      lo mismo con los pasos de la horda
##   placement  cosas puestas sobre un corte, rampa o puente, enterradas o
##              flotando, POIs que el raider no alcanza, spawns que la horda
##              no alcanza, mesetas y formaciones pegadas a un corte (lo
##              hace ReliefPlacement)
##   slope      pendiente p95 del suelo abierto lejos de cortes y rampas
##   rim, edge  el borde de la arena y el suelo de afuera del muro (los
##              arma ReliefEdgeSweeps, relief_edge_sweeps.gd)
##   hell       mallas que el infierno de Mythos dejaría sin quemar, por tipo
##              (interactuables, que no arden a propósito; el Backdrop con
##              StandardMaterial3D, que tiñe HellSky; cuerpos vivos; lo que
##              salió del pool; y el resto, que quedaría verde). Corre cuando
##              el bosque de afuera (grupo forest_edge) avisa que terminó.
##
## Todos los conteos tienen que dar cero (slope y hell tienen cota en el
## gate). NUNCA se afloja una tolerancia de aquí para hacerlos pasar: lo que
## cede es el relieve o quien coloca.

## Tangentes de 45 y 60 grados al cuadrado: la franja que nadie camina ni trepa.
const GAP_FROM_SQ: float = 1.0
const GAP_TO_SQ: float = 3.0
## Una cara de roca más chica que esto (m²) no cuenta: nadie se apoya en ella.
const FACE_MIN_AREA: float = 0.03
## Radio de la esfera con que se prueba si algo tapa una cara, y a cuánto de
## la cara se la pone, en metros.
const TOUCH_RADIUS: float = 0.1
const TOUCH_OFFSET: float = 0.14
## Metros alrededor de cortes y rampas que la medida de pendiente deja fuera
## (la cornisa enterrada llega a 4.7 m).
const SLOPE_KEEPOUT: float = 4.8
## Muestras con nombre por barrido cuando un conteo no da cero.
const DETAIL_LIMIT: int = ReliefPlacement.DETAIL_LIMIT

var graph: ReliefGraph = null

var _placement := ReliefPlacement.new()

var _tree: SceneTree = null
var _arena: Node3D = null
var _terrain: Terrain = null
var _bounds: Node3D = null
var _raiders: Array[RID] = []
## 1 en las celdas que el raider (o la horda) alcanza desde el spawn Y desde
## las que vuelve a él.
var _raider_ok := PackedByteArray()
var _horde_ok := PackedByteArray()
## 1 en las celdas que el raider (o la horda) alcanza desde el spawn, vuelva o no.
var _raider_seen := PackedByteArray()
var _horde_seen := PackedByteArray()
## True cuando el barrido del infierno ya corrió en esta etapa.
var _hell_done: bool = true
var _heights := PackedFloat32Array()
var _samples: int = 0
## El alcance de ida del último _sweep_reach.
var _last_seen := PackedByteArray()


## Arma el grafo y corre todos los barridos de comienzo de etapa. False si
## la arena no tiene relieve por zonas (no imprime nada).
func run(tree: SceneTree, arena: Node3D, raiders: Array[RID]) -> bool:
	_tree = tree
	_arena = arena
	_raiders = raiders
	_terrain = null
	_bounds = null
	for node: Node in tree.get_nodes_in_group(&"terrain"):
		if arena.is_ancestor_of(node):
			_terrain = node as Terrain
	for node: Node in tree.get_nodes_in_group(&"arena_bounds"):
		if arena.is_ancestor_of(node) and node.has_method(&"blocked_cells"):
			_bounds = node as Node3D
	if _terrain == null or _bounds == null or not _terrain.has_relief():
		return false
	var started := Time.get_ticks_msec()
	graph = ReliefGraph.new()
	graph.build(_terrain, _bounds, raiders)
	var counts := [0, 0, 0, 0]
	for cell_state: int in graph.state:
		counts[cell_state] += 1
	print("Relief graph: cells=%d open=%d tight=%d wall=%d obstacle=%d rays=%d shapes=%d in %d ms" % [
			graph.state.size(), counts[0], counts[1], counts[2], counts[3], graph.rays,
			graph.shapes, Time.get_ticks_msec() - started])
	_load_collider()
	_sweep_gap()
	var home := graph.nearest_open(_spawn_xz(), 4.0)
	_raider_ok = _sweep_reach("raider", home, graph.raider_next)
	_raider_seen = _last_seen
	_horde_ok = _sweep_reach("horde", home, graph.horde_next)
	_horde_seen = _last_seen
	_placement.setup(_tree, _arena, _terrain, _bounds, _raiders, graph, _raider_ok, _horde_ok)
	placement("start")
	_sweep_slope()
	_sweep_rim()
	_sweep_edge()
	_hell_done = false
	try_hell()
	print("Relief sweep: done in %d ms" % (Time.get_ticks_msec() - started))
	return true


## True mientras el barrido del infierno espera al bosque de afuera.
func hell_pending() -> bool:
	return graph != null and not _hell_done


## Corre el barrido del infierno si el bosque de afuera (grupo forest_edge)
## ya terminó de armarse: lo que todavía no existe no se puede contar.
func try_hell() -> void:
	if _hell_done:
		return
	for node: Node in _tree.get_nodes_in_group(&"forest_edge"):
		if _arena.is_ancestor_of(node) and node.has_method(&"is_built") \
				and not bool(node.call(&"is_built")):
			return
	_hell_done = true
	ReliefHellSweep.run(_tree, _arena, _terrain)


## El barrido de colocación, con la etiqueta `tag` (start, 120…).
func placement(tag: String) -> void:
	if graph != null:
		_placement.run(tag)


## True si un raider llega del spawn a la celda `cell` y vuelve.
func raider_reaches(cell: int) -> bool:
	return cell != ReliefGraph.NONE and _raider_ok[cell] == 1


## Imprime el grafo alrededor de `xz` (un carácter por celda, norte arriba):
## `.` abierta y alcanzada por el raider, `o` abierta sin alcanzar, `t`
## justa, `#` pared, `X` obstáculo; debajo, las alturas en decímetros.
## Solo depuración (BONK_RELIEF_DUMP).
func dump(xz: Vector2, radius: int) -> void:
	var home := graph.cell_of(xz)
	if home == ReliefGraph.NONE:
		return
	print("Relief dump: around (%.1f, %.1f) radius=%d" % [xz.x, xz.y, radius])
	var marks := [".", "t", "#", "X"]
	for dz in range(-radius, radius + 1):
		var row := ""
		var levels := ""
		for dx in range(-radius, radius + 1):
			var ix := home % graph.side + dx
			var iz := home / graph.side + dz
			if ix < 0 or iz < 0 or ix >= graph.side or iz >= graph.side:
				row += " "
				continue
			var index := iz * graph.side + ix
			var mark: String = marks[graph.state[index]]
			if graph.state[index] == ReliefGraph.OPEN and _raider_ok[index] == 0:
				mark = "o"
			row += mark
			levels += "%4d" % roundi(graph.floor_y[index] * 10.0)
		print("Relief dump: %s  %s" % [row, levels])


# --- hueco 45-60 -------------------------------------------------------------------

func _load_collider() -> void:
	var shape := (_terrain.get_node("CollisionShape3D") as CollisionShape3D).shape \
			as HeightMapShape3D
	_heights = shape.map_data
	_samples = shape.map_width


## Altura del COLISIONADOR del terreno (no de la superficie que se pisa).
func _collider_height(x: float, z: float) -> float:
	var half := _terrain.size * 0.5
	var fx := clampf(x + half, 0.0, float(_samples - 1))
	var fz := clampf(z + half, 0.0, float(_samples - 1))
	var ix := mini(int(fx), _samples - 2)
	var iz := mini(int(fz), _samples - 2)
	var tx := fx - float(ix)
	var row := iz * _samples + ix
	return lerpf(lerpf(_heights[row], _heights[row + 1], tx),
			lerpf(_heights[row + _samples], _heights[row + _samples + 1], tx), fz - float(iz))


## Caras entre 45 y 60 grados que un cuerpo puede tocar: las del colisionador
## del terreno que no tapa ninguna roca ni puente, y las de la roca de los
## cortes que asoman sobre el suelo.
func _sweep_gap() -> void:
	var notes: Array[String] = []
	var counted := _gap_ground(notes)
	var rock := 0
	for node: Node in _bounds.get_children():
		if node is CliffWall:
			rock += _gap_rock(node as CliffWall, notes)
	print("Relief sweep: gap faces=%d ground=%d rock=%d checked=%d" % [
			counted.x + rock, counted.x, rock, counted.y])
	for note: String in notes:
		print("Relief sweep detail: gap %s" % note)


## Celdas del colisionador del terreno con una cara de 45 a 60 grados que
## nada tapa (x) y cuántas caras de esa franja se revisaron (y).
func _gap_ground(notes: Array[String]) -> Vector2i:
	var touch := SphereShape3D.new()
	touch.radius = TOUCH_RADIUS
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = touch
	query.collision_mask = ReliefGraph.WORLD_LAYER
	var excluded: Array[RID] = _raiders.duplicate()
	excluded.append(_terrain.get_rid())
	query.exclude = excluded
	var space := _terrain.get_world_3d().direct_space_state
	var half := _terrain.size * 0.5
	var ground := 0
	var checked := 0
	# Los cuatro triángulos de esquina de cada celda: cubren las dos formas
	# de partir el cuadrado, sea cual sea la diagonal del motor de física.
	for iz in _samples - 1:
		for ix in _samples - 1:
			var row := iz * _samples + ix
			var along_low := _heights[row + 1] - _heights[row]
			var along_high := _heights[row + _samples + 1] - _heights[row + _samples]
			var across_low := _heights[row + _samples] - _heights[row]
			var across_high := _heights[row + _samples + 1] - _heights[row + 1]
			var steep := maxf(maxf(absf(along_low), absf(along_high)),
					maxf(absf(across_low), absf(across_high)))
			if steep * steep * 2.0 <= GAP_FROM_SQ:
				continue
			var corners: Array[Vector3] = [Vector3(along_low, across_low, 0.0),
					Vector3(along_low, across_high, 1.0), Vector3(along_high, across_low, 2.0),
					Vector3(along_high, across_high, 3.0)]
			for corner: Vector3 in corners:
				var slope_sq := corner.x * corner.x + corner.y * corner.y
				if slope_sq <= GAP_FROM_SQ or slope_sq >= GAP_TO_SQ:
					continue
				checked += 1
				# Centro del triángulo de esa esquina, y un punto apenas fuera
				# de la cara, del lado de arriba.
				var x := float(ix) + (0.33 if int(corner.z) % 2 == 0 else 0.67) - half
				var z := float(iz) + (0.33 if int(corner.z) < 2 else 0.67) - half
				var normal := Vector3(-corner.x, 1.0, -corner.y).normalized()
				var at := Vector3(x, _collider_height(x, z), z) + normal * TOUCH_OFFSET
				query.transform = Transform3D(Basis(), at)
				if space.intersect_shape(query, 1).is_empty():
					ground += 1
					if notes.size() < DETAIL_LIMIT:
						notes.append("ground face at (%.1f, %.1f, %.1f) slope=%.1f" % [
								x, at.y, z, rad_to_deg(atan(sqrt(slope_sq)))])
					break
	return Vector2i(ground, checked)


## Caras de `wall` entre 45 y 60 grados que asoman sobre el suelo.
func _gap_rock(wall: CliffWall, notes: Array[String]) -> int:
	var view := wall.get_node_or_null("Mesh") as MeshInstance3D
	if view == null or view.mesh == null:
		return 0
	var vertices: PackedVector3Array = view.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var found := 0
	for index in range(0, vertices.size() - 2, 3):
		var v0 := vertices[index]
		var v1 := vertices[index + 1]
		var v2 := vertices[index + 2]
		var cross := (v1 - v0).cross(v2 - v0)
		var area := cross.length() * 0.5
		if area < FACE_MIN_AREA:
			continue
		var up := absf(cross.y) / (area * 2.0)
		var slope_sq := (1.0 - up * up) / maxf(up * up, 0.000001)
		if slope_sq <= GAP_FROM_SQ or slope_sq >= GAP_TO_SQ:
			continue
		var middle := (v0 + v1 + v2) / 3.0
		if middle.y < _collider_height(middle.x, middle.z) - 0.02:
			continue
		found += 1
		if notes.size() < DETAIL_LIMIT:
			notes.append("rock face of %s at (%.1f, %.1f, %.1f) slope=%.1f area=%.2f" % [
					wall.name, middle.x, middle.y, middle.z, rad_to_deg(atan(sqrt(slope_sq))),
					area])
	return found


# --- alcance -----------------------------------------------------------------------

func _spawn_xz() -> Vector2:
	var origin: Vector3 = _arena.call(&"spawn_origin") if _arena.has_method(&"spawn_origin") \
			else Vector3.ZERO
	return Vector2(origin.x, origin.z)


## Celdas abiertas que `home` no alcanza con los pasos `next` y celdas
## abiertas que no vuelven a `home`. Devuelve las que cumplen las dos cosas.
func _sweep_reach(who: String, home: int, next: PackedInt32Array) -> PackedByteArray:
	var forward := ReliefSearch.reach(graph, home, next)
	_last_seen = forward
	var back := ReliefSearch.reach_back(graph, home, next)
	var open := 0
	var unreachable := 0
	var no_return := 0
	var notes: Array[String] = []
	var both := PackedByteArray()
	both.resize(graph.state.size())
	for index in graph.state.size():
		if forward[index] == 1 and back[index] == 1:
			both[index] = 1
		if graph.state[index] != ReliefGraph.OPEN:
			continue
		open += 1
		if forward[index] == 0:
			unreachable += 1
			if notes.size() < DETAIL_LIMIT:
				notes.append("unreachable %s" % _cell_text(index))
		elif back[index] == 0:
			no_return += 1
			if notes.size() < DETAIL_LIMIT:
				notes.append("no return from %s" % _cell_text(index))
	print("Relief sweep: %s open=%d unreachable=%d no_return=%d" % [
			who, open, unreachable, no_return])
	for note: String in notes:
		print("Relief sweep detail: %s %s" % [who, note])
	return both


func _cell_text(index: int) -> String:
	var at := graph.stand(index)
	return "(%.1f, %.1f, %.1f) on %s" % [at.x, at.y, at.z, _floor_name(at)]


## Qué cuerpo hace de piso en `at`: el nombre del primero que toca un rayo
## que baja desde un poco más arriba. Solo para las líneas de detalle.
func _floor_name(at: Vector3) -> String:
	var ray := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.6, at + Vector3.DOWN * 0.6,
			ReliefGraph.WORLD_LAYER, _raiders)
	var hit := _terrain.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return "nothing"
	var body := hit["collider"] as Node
	return String(body.name) if body != null else "?"


# --- borde, pendiente e infierno ----------------------------------------------------

func _sweep_rim() -> void:
	ReliefEdgeSweeps.rim(graph, _terrain, _raider_seen, _horde_seen)


func _sweep_edge() -> void:
	ReliefEdgeSweeps.edge(_terrain, WorldDigest.GROUND_SHADER_PATH)


## La pendiente p95 del suelo caminable, con la misma medida congelada de
## WorldDigest, dejando fuera los cortes, las rampas y los puentes.
func _sweep_slope() -> void:
	var slope := WorldDigest.ground_slope(_tree, _arena, func(center: Vector2) -> bool:
		return _terrain.relief_distance(center, SLOPE_KEEPOUT) < SLOPE_KEEPOUT)
	print("Relief sweep: slope p95=%.2f max=%.2f cells=%d" % [
			slope["p95"], slope["max"], slope["cells"]])
