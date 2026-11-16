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
##              no alcanza, mesetas y formaciones pegadas a un corte
##   slope      pendiente p95 del suelo abierto lejos de cortes y rampas
##   hell       mallas que el infierno de Mythos dejaría sin quemar, por tipo
##              (interactuables, que no arden a propósito; el Backdrop, que
##              tiñe HellSky; cuerpos vivos; lo que salió del pool; y el
##              resto, que quedaría verde)
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
## Metros alrededor de cortes y rampas que la medida de pendiente deja fuera
## (la cornisa enterrada llega a 4.7 m).
const SLOPE_KEEPOUT: float = 4.8
## Medio lado de una plataforma y media rampa de meseta a escala 1, en metros.
const PLATFORM_REACH: float = 4.3
const RAMP_REACH: float = 2.5
## Lo que una formación asoma fuera de sus celdas (RockFormationStyle.margin_max).
const FORMATION_SKIRT: float = 2.0
## Muestras con nombre por barrido cuando un conteo no da cero.
const DETAIL_LIMIT: int = 4

var graph: ReliefGraph = null

var _tree: SceneTree = null
var _arena: Node3D = null
var _terrain: Terrain = null
var _bounds: Node3D = null
var _raiders: Array[RID] = []
## 1 en las celdas que el raider (o la horda) alcanza desde el spawn Y desde
## las que vuelve a él.
var _raider_ok := PackedByteArray()
var _horde_ok := PackedByteArray()
var _heights := PackedFloat32Array()
var _samples: int = 0


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
	_horde_ok = _sweep_reach("horde", home, graph.horde_next)
	placement("start")
	_sweep_slope()
	_sweep_hell()
	print("Relief sweep: done in %d ms" % (Time.get_ticks_msec() - started))
	return true


## El barrido de colocación, con la etiqueta `tag` (start, 120…).
func placement(tag: String) -> void:
	if graph == null:
		return
	var bad := {"on_relief": 0, "misplaced": 0, "raider_unreachable": 0,
			"horde_unreachable": 0, "crowding": 0}
	var notes: Array[String] = []
	var props := _check_props(bad, notes)
	var pois := _check_pois(bad, notes)
	var spawns := _check_spawns(bad, notes)
	_check_formations(bad, notes)
	print(("Relief sweep: placement at=%s props=%d pois=%d spawns=%d on_relief=%d misplaced=%d"
			+ " raider_unreachable=%d horde_unreachable=%d crowding=%d") % [tag, props, pois,
			spawns, bad["on_relief"], bad["misplaced"], bad["raider_unreachable"],
			bad["horde_unreachable"], bad["crowding"]])
	for note: String in notes:
		print("Relief sweep detail: placement at=%s %s" % [tag, note])


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
	var notes: Array[String] = []
	var ground := 0
	var checked := 0
	# Los cuatro triángulos de esquina de cada celda: cubren las dos formas
	# de partir el cuadrado, sea cual sea la diagonal del motor de física.
	for iz in _samples - 1:
		for ix in _samples - 1:
			var row := iz * _samples + ix
			var h00 := _heights[row]
			var h10 := _heights[row + 1]
			var h01 := _heights[row + _samples]
			var h11 := _heights[row + _samples + 1]
			var along_low := h10 - h00
			var along_high := h11 - h01
			var across_low := h01 - h00
			var across_high := h11 - h10
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
				var cx := 0.33 if int(corner.z) % 2 == 0 else 0.67
				var cz := 0.33 if int(corner.z) < 2 else 0.67
				var x := float(ix) + cx - half
				var z := float(iz) + cz - half
				var normal := Vector3(-corner.x, 1.0, -corner.y).normalized()
				var at := Vector3(x, _collider_height(x, z), z) + normal * TOUCH_OFFSET
				query.transform = Transform3D(Basis(), at)
				if space.intersect_shape(query, 1).is_empty():
					ground += 1
					if notes.size() < DETAIL_LIMIT:
						notes.append("ground face at (%.1f, %.1f, %.1f) slope=%.1f" % [
								x, at.y, z, rad_to_deg(atan(sqrt(slope_sq)))])
					break
	var rock := 0
	for node: Node in _bounds.get_children():
		if node is CliffWall:
			rock += _gap_rock(node as CliffWall, notes)
	print("Relief sweep: gap faces=%d ground=%d rock=%d checked=%d" % [
			ground + rock, ground, rock, checked])
	for note: String in notes:
		print("Relief sweep detail: gap %s" % note)


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
	var forward := graph.reach(home, next)
	var back := graph.reach_back(home, next)
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
	return "(%.1f, %.1f, %.1f)" % [at.x, at.y, at.z]


# --- colocación --------------------------------------------------------------------

## Props del scatter: nada sobre un corte, rampa o puente, nada enterrado ni
## flotando, y mesetas y plataformas lejos de los cortes.
func _check_props(bad: Dictionary, notes: Array[String]) -> int:
	var count := 0
	for node: Node in _bounds.get_children():
		var prop := node as Node3D
		if prop == null or prop is CliffWall or prop is Bridge or prop is RockFormation:
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
		if prop.scene_file_path == ReliefGraph.DECK_SCENES[0]:
			reach = PLATFORM_REACH * prop.scale.x
		elif prop.scene_file_path == ReliefGraph.DECK_SCENES[1]:
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
		if not raider_reaches(graph.nearest_open(xz, POI_REACH, at.y, LEVEL_WINDOW)):
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
		var cell := graph.nearest_open(xz, SPAWN_REACH, at.y, LEVEL_WINDOW)
		if cell == ReliefGraph.NONE or _horde_ok[cell] == 0:
			_flag(bad, "horde_unreachable", notes, what, at)
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
		if graph._is_ground(hit["collider"]) or hit["collider"] is RockFormation:
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


# --- pendiente e infierno ----------------------------------------------------------

## La pendiente p95 del suelo caminable, con la misma medida congelada de
## WorldDigest, dejando fuera los cortes, las rampas y los puentes.
func _sweep_slope() -> void:
	var slope := WorldDigest.ground_slope(_tree, _arena, func(center: Vector2) -> bool:
		return _terrain.relief_distance(center, SLOPE_KEEPOUT) < SLOPE_KEEPOUT)
	print("Relief sweep: slope p95=%.2f max=%.2f cells=%d" % [
			slope["p95"], slope["max"], slope["cells"]])


## Las mallas que HellDressing no quemaría, por tipo: bajo un Interactable
## (no arden a propósito), bajo el Backdrop (las tiñe HellSky), las de un
## cuerpo vivo, las de algo que salió del pool (un dardo en vuelo, una gema:
## Pools los cuelga de la arena) y el resto, que es lo que quedaría verde en
## el infierno.
func _sweep_hell() -> void:
	var burning: Dictionary[int, bool] = {}
	for child: Node in _terrain.find_children("*", "MeshInstance3D", true, false):
		var view := child as MeshInstance3D
		var material := view.material_override as ShaderMaterial
		if material != null and material.shader != null \
				and material.shader.resource_path == WorldDigest.GROUND_SHADER_PATH:
			burning[view.get_instance_id()] = true
	for group: StringName in WorldDigest.PROP_GROUPS:
		for node: Node in _tree.get_nodes_in_group(group):
			if not _arena.is_ancestor_of(node) or node is Interactable:
				continue
			for child: Node in node.find_children("*", "MeshInstance3D", true, false):
				if WorldDigest._prop_burns(child as MeshInstance3D):
					burning[child.get_instance_id()] = true
	var backdrop := _terrain.get_node_or_null(_terrain.backdrop_path)
	var counts := {"interactable": 0, "backdrop": 0, "body": 0, "pooled": 0, "other": 0}
	var skipped := 0
	var notes: Array[String] = []
	for child: Node in _arena.find_children("*", "MeshInstance3D", true, false):
		if burning.has(child.get_instance_id()):
			continue
		skipped += 1
		var kind := "other"
		var up := child.get_parent()
		while up != null and up != _arena:
			if up is Interactable:
				kind = "interactable"
				break
			if up == backdrop:
				kind = "backdrop"
				break
			# Un cuerpo vivo (la horda que ya apareció) no es parte del mapa.
			if up is CharacterBody3D:
				kind = "body"
				break
			# Tampoco lo que NodePool creó: lleva su marca desde que nace.
			if up.has_meta(NodePool.META_OWNER):
				kind = "pooled"
				break
			up = up.get_parent()
		counts[kind] = int(counts[kind]) + 1
		if kind == "other" and notes.size() < DETAIL_LIMIT:
			notes.append(String(_arena.get_path_to(child)))
	print(("Relief sweep: hell skipped=%d interactable=%d backdrop=%d bodies=%d pooled=%d"
			+ " unburnt=%d") % [skipped, counts["interactable"], counts["backdrop"],
			counts["body"], counts["pooled"], counts["other"]])
	for note: String in notes:
		print("Relief sweep detail: hell unburnt %s" % note)
