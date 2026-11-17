class_name SpawnPoints
extends RefCounted
## Dónde cae un spawn: el anillo alrededor de un raider, la banda de las
## oleadas, la máscara caminable de la arena, el espacio libre alrededor de
## la party y la altura del suelo bajo el punto.
## Los radios y márgenes son exports del spawner (grupo «Anillo de spawn» de
## enemy_spawner.gd); las arenas usan los valores del script. Lo usan
## EnemySpawner, BossSchedule y HordeSchedule.
## Orden del RNG: ring_position tira el ángulo y luego band_position un
## randf_range por intento; no las reordenes.

## Edita aquí. Intentos de una muestra de anillo/banda para hallar una celda
## caminable; el último candidato se usa igual (un spawn nunca se pierde en
## silencio).
const RING_ATTEMPTS: int = 8
## Altura sobre el suelo hallado por el rayo, en metros: el enemigo se
## asienta en vez de nacer un frame dentro del suelo.
const SPAWN_GROUND_OFFSET: float = 0.05
## Altura de inicio del rayo de suelo sin Terrain, en metros: sobre toda
## plataforma y meseta, bajo el techo de los muros de máscara.
const GROUND_PROBE_HEIGHT: float = 12.0
## Con Terrain, el rayo parte esta altura sobre su punto más alto y termina
## esta otra bajo el más bajo, en metros (ver ground_height).
const PROBE_HEADROOM: float = 30.0
const PROBE_UNDERSHOOT: float = 2.0
## Media placa usable, en metros, solo si la escena no tiene nodo en el grupo
## "arena_bounds" (las arenas lo tienen: es su scatter).
const FALLBACK_HALF_EXTENT: float = 78.0
## Metros que un spawn guarda con un corte, una rampa o un puente del
## relieve por zonas: nadie nace sobre una cornisa ni en mitad de una rampa.
## En una arena sin relieve no cuenta.
const RELIEF_MARGIN: float = 4.0
## Con relieve por zonas, metros sobre el suelo a partir de los cuales lo
## que hay bajo un punto es la punta de un prop (el tronco de un árbol mide
## 3-4.5 m) y no un lugar donde nacer. Una roca suelta queda por debajo.
const PROP_TOP: float = 1.2

var _spawner: EnemySpawner = null
## Nodo de límites de arena (el scatter): también responde is_walkable()
## para la máscara irregular de la arena.
var _bounds: Node3D = null
## Media placa donde puede caer un spawn, en metros: el arena_half_extent del
## scatter menos arena_edge_margin, fijado en read_bounds.
var _arena_half_extent: float = FALLBACK_HALF_EXTENT
## Spawns descartados este minuto por falta de espacio, y el minuto que se
## está contando. Se imprime una vez por minuto mientras no sea cero, para
## que un soak vea si el chequeo se está comiendo la rampa.
var _clearance_skips: int = 0
var _clearance_report_minute: int = -1


func _init(spawner: EnemySpawner) -> void:
	_spawner = spawner


## Busca el nodo "arena_bounds" y fija la media placa. Lo llama
## EnemySpawner._ready.
func read_bounds() -> void:
	_bounds = _spawner.get_tree().get_first_node_in_group("arena_bounds") as Node3D
	if _bounds != null:
		_arena_half_extent = float(_bounds.get("arena_half_extent")) - _spawner.arena_edge_margin


## Posición del anillo alrededor del jugador, a distancia de spawn y sobre
## el suelo.
func ring_position(player: Node3D) -> Vector3:
	return on_ground(band_position(player.global_position, _spawner.min_radius,
			_spawner.max_radius, randf() * TAU))


## `pos` con su altura bajada al suelo que tiene debajo.
func on_ground(pos: Vector3) -> Vector3:
	pos.y = ground_height(pos) + SPAWN_GROUND_OFFSET
	return pos


## True si `pos` queda lo bastante lejos de todo raider en pie. Los cuerpos
## derribados no cuentan: tratarlos como zona prohibida abriría huecos
## muertos en el anillo.
func has_player_clearance(pos: Vector3) -> bool:
	var clearance_sq := _spawner.min_player_clearance * _spawner.min_player_clearance
	for node: Node in Coop.alive_players(_spawner.get_tree()):
		var body := node as Node3D
		if body == null:
			continue
		var away := pos - body.global_position
		away.y = 0.0
		if away.length_squared() < clearance_sq:
			return false
	return true


## Cuenta un spawn descartado e informa el total una vez por minuto de juego.
func register_clearance_skip() -> void:
	_clearance_skips += 1
	var minute := floori(_spawner.run_minutes())
	if minute == _clearance_report_minute:
		return
	_clearance_report_minute = minute
	# Log de una línea (convención de RunManager) para los soaks headless.
	print("Spawn skipped: no clearance x%d" % _clearance_skips)


## Un punto caminable en la banda [min_r, max_r] alrededor de `center`, que
## empieza en `angle` y gira 1/RING_ATTEMPTS de vuelta por intento. Los
## candidatos fuera de la placa se REINTENTAN, no se recortan: recortar X y Z
## por separado juntaría todos los ángulos en la misma esquina junto a un
## borde. El último intento se usa aunque esté bloqueado (los trepadores
## salen), así que un spawn nunca se pierde en silencio; con relieve por
## zonas se corre antes al punto libre más cercano (ver _off_relief).
func band_position(center: Vector3, min_r: float, max_r: float, angle: float) -> Vector3:
	var pos := center
	var found := false
	for attempt in RING_ATTEMPTS:
		var heading := angle + TAU * float(attempt) / float(RING_ATTEMPTS)
		pos = center + Vector3(cos(heading), 0.0, sin(heading)) * randf_range(min_r, max_r)
		if absf(pos.x) > _arena_half_extent or absf(pos.z) > _arena_half_extent:
			continue
		# El espacio libre es parte de "¿sirve este punto?": girar por la
		# banda es justo como se resuelve un hueco bloqueado.
		if _walkable(pos) and has_player_clearance(pos):
			found = true
			break
	pos.x = clampf(pos.x, -_arena_half_extent, _arena_half_extent)
	pos.z = clampf(pos.z, -_arena_half_extent, _arena_half_extent)
	return pos if found else _off_relief(pos)


## Baja el punto de spawn hasta la geometría del mundo (capa 1) que haya
## debajo (suelo, roca, plataforma) para que un enemigo nunca nazca dentro
## de un prop. Las copas de árbol no tienen colisión. Si el rayo no toca
## nada, usa la altura del Terrain (o 0 sin Terrain).
func ground_height(pos: Vector3) -> float:
	# El rayo cubre todo el relieve: desde sobre la cima más alta hasta bajo
	# el fondo más hondo.
	var tree := _spawner.get_tree()
	var terrain := Terrain.find(tree)
	var top := GROUND_PROBE_HEIGHT
	var bottom := -1.0
	if terrain != null:
		top = terrain.max_height + PROBE_HEADROOM
		bottom = terrain.min_height - PROBE_UNDERSHOOT
	var ray := PhysicsRayQueryParameters3D.create(
			Vector3(pos.x, top, pos.z), Vector3(pos.x, bottom, pos.z), 1)
	# Los raiders comparten la capa 1 con el mundo, así que se excluye a TODA
	# la party: si no, un spawn sobre un compañero usaría su cabeza de suelo.
	var excluded: Array[RID] = []
	for node: Node in Coop.alive_players(tree):
		var body := node as CollisionObject3D
		if body != null:
			excluded.append(body.get_rid())
	ray.exclude = excluded
	var hit := _spawner.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		# La altura del TERRAIN, no 0: cero es una altura real en un relieve,
		# y usarla metería cuerpos dentro o debajo de una colina.
		return terrain.height_at(pos.x, pos.z) if terrain != null else 0.0
	var hit_position: Vector3 = hit["position"]
	return hit_position.y


## True si un cuerpo puede aparecer en `pos`: celda abierta de la máscara y,
## con relieve por zonas, lejos de cortes, rampas y puentes
## (arena_bounds.can_place).
func _walkable(pos: Vector3) -> bool:
	if _bounds == null:
		return true
	if _bounds.has_method("can_place"):
		return bool(_bounds.call("can_place", Vector2(pos.x, pos.z), RELIEF_MARGIN)) \
				and _lands_on_ground(pos)
	if not _bounds.has_method("is_walkable"):
		return true
	return bool(_bounds.call("is_walkable", Vector2(pos.x, pos.z)))


## `pos` corrido al punto más cercano donde un cuerpo puede aparecer
## (arena_bounds.nearest_place), para el spawn que no encontró lugar en su
## banda: junto a muchos cortes, los ocho intentos pueden caer todos sobre
## una cornisa o una rampa. Solo con relieve por zonas; en las demás arenas
## devuelve `pos` tal cual. No saca números de ningún RNG.
func _off_relief(pos: Vector3) -> Vector3:
	if _bounds == null or not _bounds.has_method("nearest_place"):
		return pos
	var terrain := Terrain.find(_spawner.get_tree())
	if terrain == null or not terrain.has_relief():
		return pos
	# El punto libre más cercano que además tenga suelo debajo: la pregunta
	# de colocar no ve lo que se puso después (un farol, un cofre).
	var spot: Vector2 = _bounds.call("nearest_place", Vector2(pos.x, pos.z), RELIEF_MARGIN,
			func(at: Vector2) -> bool: return _lands_on_ground(Vector3(at.x, pos.y, at.y)))
	return Vector3(spot.x, pos.y, spot.y)


## True si lo que hay bajo `pos` es suelo y no la punta de un prop. Solo se
## pregunta con relieve por zonas; en las demás arenas un spawn cae sobre lo
## que toque el rayo, como siempre.
func _lands_on_ground(pos: Vector3) -> bool:
	var terrain := Terrain.find(_spawner.get_tree())
	if terrain == null or not terrain.has_relief():
		return true
	return ground_height(pos) - terrain.height_at(pos.x, pos.z) <= PROP_TOP
