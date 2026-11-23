extends Node
## Sonda del CAMPO de cada arena de jefe (filas de BossArenaCatalog): sin
## partida y sin raiders, arma la arena con su jefe y mide que el claro, las
## coberturas y el borde sirvan para pelear. Corre headless en unos segundos:
##
##     godot --headless --path . res://scenes/tests/BossFieldProbe.tscn
##
## Por cada arena imprime (tools/verificar.sh busca la última línea):
##   Probe field size:   radio del claro, el ataque más largo del jefe con el
##                       raider más rápido, el largo de su cuerpo y si entra.
##   Probe field covers: cuántas coberturas hay, si chocan en la capa del
##                       mundo, si tapan a un raider de pie, y el lugar que
##                       queda entre ellas, hasta el borde y hasta los puntos
##                       de llegada del equipo y del jefe.
##   Probe field ground: muestras del claro fuera de las coberturas donde un
##                       raider (a pie o volando) choca con algo: tiene que
##                       dar 0.
##   Probe field rim:    lugares del borde por donde cabe la cápsula de un
##                       raider: tiene que dar 0.
##   Probe field: arena=<id> ok=true|false
## y al final «Probe field: done arenas=<n> failed=<n>».

## Cápsula de un raider, en metros.
const RAIDER_RADIUS: float = 0.4
const RAIDER_HEIGHT: float = 1.8
## Capa de colisión del mundo.
const WORLD_LAYER: int = 1
## Radio mínimo y máximo del claro, en metros.
const CLEARING_MIN: float = 45.0
const CLEARING_MAX: float = 60.0
## Coberturas que pide el diseño, mínimo y máximo.
const COVERS_MIN: int = 4
const COVERS_MAX: int = 6
## Metros que tienen que sobrar, además del cuerpo del jefe, entre dos
## coberturas y entre una cobertura y el borde.
const ROOM_SPARE: float = 3.0
## Metros mínimos de una cobertura al punto de llegada del equipo y al del jefe.
const POINT_CLEARANCE: float = 12.0
## Paso de la grilla de muestras del suelo, en metros.
const GROUND_STEP: float = 1.0
## Alto de la columna que se prueba en cada muestra (el techo del Vuelo y algo más).
const COLUMN_HEIGHT: float = 14.0
## Direcciones y alturas (sobre el suelo) en que se prueba el borde.
const RIM_DIRECTIONS: int = 1440
const RIM_HEIGHTS: Array[float] = [0.0, 4.0, 8.0, 12.0, 14.0]
## Direcciones y alturas de los rayos que prueban si una cobertura tapa a un raider.
const SIGHT_DIRECTIONS: int = 12
const SIGHT_HEIGHTS: Array[float] = [0.3, 0.9, 1.7]
## Segundos que espera a que el jefe tome su pose antes de medirlo.
const SETTLE_SECONDS: float = 0.4

var _arena: BossArena = null


func _ready() -> void:
	# Pools y RunRoot.stage_parent le preguntan al grupo "run_root" por la arena.
	add_to_group(&"run_root")
	var failed := 0
	for row: Dictionary in BossArenaCatalog.ARENA_LIBRARY:
		if not await _check(row):
			failed += 1
	print("Probe field: done arenas=%d failed=%d" % [BossArenaCatalog.ARENA_LIBRARY.size(), failed])
	get_tree().quit()


## Lo que RunRoot.stage_parent le pregunta al grupo "run_root".
func arena_root() -> Node3D:
	return _arena


func _check(row: Dictionary) -> bool:
	var id := String(row.id)
	_arena = BossArenaCatalog.scene_of(row, "arena_scene").instantiate() as BossArena
	add_child(_arena)
	var field := get_tree().get_first_node_in_group(&"arena_bounds") as BossField
	var boss := _add_boss(row)
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	await get_tree().physics_frame
	var body := _body_length(boss)
	var ok := _check_size(id, field, boss, body)
	ok = _check_covers(id, field, body) and ok
	ok = _check_ground(id, field) and ok
	ok = _check_rim(id, field) and ok
	print("Probe field: arena=%s ok=%s" % [id, ok])
	_arena.queue_free()
	await get_tree().process_frame
	_arena = null
	return ok


## El jefe de la fila, parado en su punto de la arena (sin viaje no hay cinemática).
func _add_boss(row: Dictionary) -> Node3D:
	var boss := BossArenaCatalog.scene_of(row, "boss_scene").instantiate() as Node3D
	_arena.boss_parent().add_child(boss)
	boss.global_position = _arena.boss_origin()
	return boss


# --- tamaño -------------------------------------------------------------------------

## Largo del cuerpo del jefe en planta: de la cara a la cola si su modelo lo
## dice (rig.head_point / tail_point), o el lado mayor de su forma de colisión.
func _body_length(boss: Node3D) -> float:
	var rig: Variant = boss.get("rig")
	if rig is Node and (rig as Node).has_method(&"head_point") and (rig as Node).has_method(&"tail_point"):
		var head: Vector3 = (rig as Node).call(&"head_point")
		var tail: Vector3 = (rig as Node).call(&"tail_point")
		return Vector2(head.x - tail.x, head.z - tail.z).length()
	var longest := 0.0
	for node: Node in boss.find_children("*", "CollisionShape3D", true, false):
		var shape := (node as CollisionShape3D).shape
		if shape != null:
			var size := shape.get_debug_mesh().get_aabb().size
			longest = maxf(longest, maxf(size.x, size.z))
	return longest


## El ataque que más lejos lleva al jefe: la distancia desde la que lo usa
## (max_range) o lo que recorre (max_distance, length) contra el raider más
## rápido (Reach.max_growth). Devuelve {meters, move}.
func _longest_move(boss: Node3D) -> Dictionary:
	var growth := 1.0
	var reach := boss.get_node_or_null("Reach")
	if reach != null and reach.get("max_growth") != null:
		growth = maxf(float(reach.get("max_growth")), 1.0)
	var longest := {"meters": 0.0, "move": "none"}
	var moves := boss.get_node_or_null("Moves")
	if moves == null:
		return longest
	for move: Node in moves.get_children():
		for key: String in ["max_range", "max_distance", "length"]:
			var value: Variant = move.get(key)
			if value == null:
				continue
			var meters := float(value) * (1.0 if key == "max_range" else growth)
			if meters > float(longest.meters):
				longest = {"meters": meters, "move": "%s.%s" % [move.name, key]}
	return longest


func _check_size(id: String, field: BossField, boss: Node3D, body: float) -> bool:
	var longest := _longest_move(boss)
	var radius := field.clearing_radius
	var needed := float(longest.meters) + body * 2.0
	var ok := radius >= CLEARING_MIN and radius <= CLEARING_MAX and radius * 2.0 >= needed
	print("Probe field size: arena=%s clearing=%.1f diameter=%.1f longest_move=%.1f (%s) body=%.1f needed=%.1f ok=%s" % [
			id, radius, radius * 2.0, float(longest.meters), longest.move, body, needed, ok])
	return ok


# --- coberturas ---------------------------------------------------------------------

func _check_covers(id: String, field: BossField, body: float) -> bool:
	var covers := field.covers()
	var outlines := field.cover_outlines()
	var centre := Vector2(field.global_position.x, field.global_position.z)
	var spawn := _flat(_arena.spawn_origin())
	var reveal := _flat(_arena.boss_origin())
	var on_layer := 0
	var hide_min := SIGHT_DIRECTIONS
	for cover: Node3D in covers:
		if _on_world_layer(cover):
			on_layer += 1
		hide_min = mini(hide_min, _hidden_directions(cover))
	var gap_min := INF
	var rim_gap_min := INF
	var spawn_min := INF
	var reveal_min := INF
	for index: int in outlines.size():
		for other: int in range(index + 1, outlines.size()):
			gap_min = minf(gap_min, _outline_gap(outlines[index], outlines[other]))
		for corner: Vector2 in outlines[index]:
			rim_gap_min = minf(rim_gap_min, field.clearing_radius - corner.distance_to(centre))
		spawn_min = minf(spawn_min, _point_gap(spawn, outlines[index]))
		reveal_min = minf(reveal_min, _point_gap(reveal, outlines[index]))
	var room := body + ROOM_SPARE
	var ok := covers.size() >= COVERS_MIN and covers.size() <= COVERS_MAX \
			and outlines.size() == covers.size() and on_layer == covers.size() \
			and hide_min == SIGHT_DIRECTIONS and gap_min >= room and rim_gap_min >= room \
			and spawn_min >= POINT_CLEARANCE and reveal_min >= POINT_CLEARANCE
	print("Probe field covers: arena=%s count=%d outlines=%d on_world_layer=%d hide_min=%d/%d gap_min=%.1f rim_gap_min=%.1f room=%.1f landing_min=%.1f reveal_min=%.1f ok=%s" % [
			id, covers.size(), outlines.size(), on_layer, hide_min, SIGHT_DIRECTIONS, gap_min,
			rim_gap_min, room, spawn_min, reveal_min, ok])
	return ok


## True si `cover` (o un cuerpo suyo) choca en la capa del mundo.
func _on_world_layer(cover: Node3D) -> bool:
	var bodies: Array[Node] = cover.find_children("*", "CollisionObject3D", true, false)
	bodies.append(cover)
	for node: Node in bodies:
		var body := node as CollisionObject3D
		if body != null and body.collision_layer & WORLD_LAYER != 0:
			return true
	return false


## En cuántas de SIGHT_DIRECTIONS direcciones `cover` tapa a un raider de pie:
## rayos horizontales que cruzan su centro a la altura de los pies, la cintura
## y la cabeza, y los tres tienen que dar en ella.
func _hidden_directions(cover: Node3D) -> int:
	var space := _arena.get_world_3d().direct_space_state
	var centre := cover.global_position
	var ground := _ground(centre.x, centre.z)
	var reach := 9.0
	var hidden := 0
	for index: int in SIGHT_DIRECTIONS:
		var angle := TAU * float(index) / float(SIGHT_DIRECTIONS)
		var along := Vector3(cos(angle), 0.0, sin(angle)) * reach
		var blocked := true
		for height: float in SIGHT_HEIGHTS:
			var eye := Vector3(centre.x, ground + height, centre.z)
			var query := PhysicsRayQueryParameters3D.create(eye - along, eye + along, WORLD_LAYER)
			var hit := space.intersect_ray(query)
			var collider := hit.get("collider") as Node
			if collider == null or not (collider == cover or cover.is_ancestor_of(collider)):
				blocked = false
		if blocked:
			hidden += 1
	return hidden


# --- suelo --------------------------------------------------------------------------

## Recorre el claro en una grilla: fuera de las coberturas, la columna que
## ocupa un raider (de pie o volando) no puede tocar nada más que el suelo, y
## BossField tiene que decir que ahí se camina.
func _check_ground(id: String, field: BossField) -> bool:
	var space := _arena.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var column := CylinderShape3D.new()
	column.radius = RAIDER_RADIUS
	column.height = COLUMN_HEIGHT
	query.shape = column
	query.collision_mask = WORLD_LAYER
	query.exclude = _terrain_rids()
	var reach := field.clearing_radius - RAIDER_RADIUS - 0.05
	var samples := 0
	var blocked := 0
	var unwalkable := 0
	var step_max := 0.0
	var first := ""
	var x := -reach
	while x <= reach:
		var z := -reach
		while z <= reach:
			var xz := Vector2(x, z)
			if xz.length() <= reach and field.cover_distance(xz) > RAIDER_RADIUS + 0.05:
				samples += 1
				var ground := _ground(x, z)
				step_max = maxf(step_max, absf(_ground(x + GROUND_STEP, z) - ground))
				query.transform = Transform3D(Basis.IDENTITY,
						Vector3(x, ground + 0.05 + COLUMN_HEIGHT * 0.5, z))
				var hits := space.intersect_shape(query, 1)
				if not hits.is_empty():
					blocked += 1
					if first.is_empty():
						first = "%s@(%.0f,%.0f)" % [(hits[0].collider as Node).name, x, z]
				if not field.is_walkable(xz):
					unwalkable += 1
			z += GROUND_STEP
		x += GROUND_STEP
	var ok := samples > 0 and blocked == 0 and unwalkable == 0
	print("Probe field ground: arena=%s samples=%d blocked=%d unwalkable=%d step_max=%.2f first=%s ok=%s" % [
			id, samples, blocked, unwalkable, step_max, first if not first.is_empty() else "none", ok])
	return ok


# --- borde --------------------------------------------------------------------------

## Para la cápsula de un raider justo detrás del borde del claro, en cada
## dirección y altura: tiene que quedar metida en la pared. Una que no toca
## nada es un hueco por donde se sale.
func _check_rim(id: String, field: BossField) -> bool:
	var space := _arena.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = RAIDER_RADIUS
	capsule.height = RAIDER_HEIGHT
	query.shape = capsule
	query.collision_mask = WORLD_LAYER
	query.exclude = _terrain_rids()
	var centre := field.global_position
	var reach := field.clearing_radius + RAIDER_RADIUS + 0.3
	var escapes := 0
	var first := ""
	for index: int in RIM_DIRECTIONS:
		var angle := TAU * float(index) / float(RIM_DIRECTIONS)
		var x := centre.x + cos(angle) * reach
		var z := centre.z + sin(angle) * reach
		var ground := _ground(x, z)
		for height: float in RIM_HEIGHTS:
			query.transform = Transform3D(Basis.IDENTITY,
					Vector3(x, ground + height + RAIDER_HEIGHT * 0.5 + 0.05, z))
			if space.intersect_shape(query, 1).is_empty():
				escapes += 1
				if first.is_empty():
					first = "%.1fdeg@%.0fm" % [rad_to_deg(angle), height]
	var ok := escapes == 0
	print("Probe field rim: arena=%s sweeps=%d escapes=%d first=%s ok=%s" % [
			id, RIM_DIRECTIONS * RIM_HEIGHTS.size(), escapes,
			first if not first.is_empty() else "none", ok])
	return ok


# --- utilitarios --------------------------------------------------------------------

func _flat(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z)


func _ground(x: float, z: float) -> float:
	var terrain := Terrain.find(get_tree())
	return terrain.height_at(x, z) if terrain != null else 0.0


## El cuerpo del suelo: las pruebas de choque no lo cuentan.
func _terrain_rids() -> Array[RID]:
	var rids: Array[RID] = []
	var terrain := Terrain.find(get_tree())
	if terrain != null:
		rids.append(terrain.get_rid())
	return rids


## Metros de `point` al contorno convexo `outline` (0 si cae adentro).
func _point_gap(point: Vector2, outline: PackedVector2Array) -> float:
	if Geometry2D.is_point_in_polygon(point, outline):
		return 0.0
	var nearest := INF
	for index: int in outline.size():
		var closest := Geometry2D.get_closest_point_to_segment(point, outline[index],
				outline[(index + 1) % outline.size()])
		nearest = minf(nearest, point.distance_to(closest))
	return nearest


## Metros entre dos contornos convexos que no se tocan: la distancia mínima
## siempre pasa por una esquina de alguno de los dos.
func _outline_gap(one: PackedVector2Array, other: PackedVector2Array) -> float:
	var nearest := INF
	for corner: Vector2 in one:
		nearest = minf(nearest, _point_gap(corner, other))
	for corner: Vector2 in other:
		nearest = minf(nearest, _point_gap(corner, one))
	return nearest
