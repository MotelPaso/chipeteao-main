class_name LobsterBody
extends BossBase
## El cuerpo de la Langosta Azul en la arena: cómo ronda entre un ataque y
## otro (nodo Stalk) y lo que sus ataques le piden para ubicar un punto,
## llevar el cuerpo, mirar hacia un lado o golpear el suelo. BlueLobster
## (blue_lobster.gd) hereda de aquí y suma las fases y la elección de ataques.
## Camina A TRAVÉS de la horda: su máscara de colisión (BlueLobster.tscn) solo
## ve el mundo y a los raiders. La horda sí la ve a ella y se aparta.
## Contrato por nombre: bar_visible_changed (BossBar).

## Su barra de vida tiene que irse (llega sin aviso) o volver (empieza la pelea).
signal bar_visible_changed(shown: bool)

## Capa de colisión del mundo (terreno, rocas, mesetas). Los raiders también
## están en ella: al buscar el suelo se los salta.
const WORLD_MASK: int = 1
## El suelo real se busca con un rayo hacia abajo desde estos metros sobre el
## terreno (más que la roca más alta) hasta estos metros por debajo.
const GROUND_PROBE_UP: float = 20.0
const GROUND_PROBE_DOWN: float = 3.0
## Un escalón de hasta estos metros sobre el terreno se pisa sin más revisión.
const GROUND_STEP: float = 0.6
## Algo más alto solo se pisa si es ANCHO: a GROUND_SUPPORT_REACH metros del
## punto, en cruz, tiene que haber suelo a no más de GROUND_LEVEL_SLACK metros
## de esa altura en al menos GROUND_SUPPORT de los cuatro lados. Una formación
## de roca o una meseta lo cumplen; un tronco, no.
const GROUND_SUPPORT_REACH: float = 0.9
const GROUND_LEVEL_SLACK: float = 1.2
const GROUND_SUPPORT: int = 2
## Cosas angostas que se saltan, como mucho, al buscar el suelo bajo un punto.
const GROUND_TRIES: int = 4
## Por debajo de esta fracción de lo que quería avanzar en un frame cuenta
## como trabada; no cuenta si se mueve en vertical (trepa o cae) a más de
## STUCK_VERTICAL_SPEED metros por segundo.
const STUCK_PROGRESS: float = 0.25
const STUCK_VERTICAL_SPEED: float = 0.5

## Agresividad actual (0-1); la leen los ataques.
var aggression: float = 0.0

## El rig (nodo Visual) y lo que se siente de sus golpes (nodo Feel): los
## mueven sus ataques.
@onready var rig: LobsterRig = $Visual
@onready var feel: LobsterFeel = $Feel

## Hacia dónde mira mientras un ataque la lleva (ZERO = mira al raider).
var _face_along: Vector3 = Vector3.ZERO
## Hacia dónde camina en este frame por pedido del ataque en curso; el largo
## es la fracción de su velocidad. Se gasta en cada frame.
var _move_steer: Vector3 = Vector3.ZERO
## Metros por segundo que quiso avanzar en este frame mientras rondaba, y los
## segundos que lleva sin lograrlo (trabada contra algo).
var _wanted_speed: float = 0.0
var _stuck_time: float = 0.0

@onready var _stalk: LobsterStalk = $Stalk
## Su velocidad de siempre: los ataques la cambian con set_pace().
@onready var _walk_speed: float = move_speed


## True mientras pelea. BlueLobster lo redefine con sus fases.
func is_fighting() -> bool:
	return true


## True mientras hace un ataque (entonces camina solo si el ataque lo pide).
## BlueLobster lo redefine con sus fases.
func is_attacking() -> bool:
	return false


func _pick_target() -> Node3D:
	return _stalk.pick_target(get_tree(), global_position)


func _movement_intent(seek: Vector3, distance: float) -> Vector3:
	_wanted_speed = 0.0
	if not is_fighting():
		return Vector3.ZERO
	if is_attacking():
		var steer := _move_steer
		_move_steer = Vector3.ZERO
		return steer
	set_pace(_stalk.pace(distance))
	var intent := _stalk.intent(seek, distance)
	_wanted_speed = intent.length() * move_speed
	return intent


func _facing_direction(steer: Vector3, seek: Vector3) -> Vector3:
	if not is_fighting():
		return Vector3.ZERO
	if _face_along.length_squared() > 0.0001:
		return _face_along
	return seek if seek.length_squared() > 0.0001 else steer


# --- atasco ------------------------------------------------------------------------

## Segundos que lleva queriendo avanzar sin lograrlo mientras ronda.
func stuck_time() -> float:
	return _stuck_time


## Deja de contar el atasco (acaba de salir de él con un ataque).
func clear_stuck() -> void:
	_stuck_time = 0.0


## Tras cada frame de física: `before` es dónde estaba antes de moverse.
## Cuenta los segundos en que quiso avanzar rondando y casi no se movió.
func _watch_stuck(before: Vector3, delta: float) -> void:
	var moved := global_position - before
	var vertical := absf(moved.y)
	moved.y = 0.0
	var blocked := _wanted_speed > 1.0 and not is_attacking() \
			and moved.length() < _wanted_speed * delta * STUCK_PROGRESS \
			and vertical < STUCK_VERTICAL_SPEED * delta
	_stuck_time = _stuck_time + delta if blocked else maxf(_stuck_time - delta, 0.0)


# --- presencia en el HUD -----------------------------------------------------------

## La saca del HUD y del mapa: sin barra, sin flecha y sin marcador (llega
## sin aviso). Sigue en el grupo "enemies".
func hide_presence() -> void:
	remove_from_group(&"boss")
	remove_from_group(&"map_markers")
	bar_visible_changed.emit(false)


## La devuelve al HUD y al mapa (empieza la pelea).
func show_presence() -> void:
	add_to_group(&"boss")
	add_to_group(&"map_markers")
	bar_visible_changed.emit(true)


# --- lo que piden los ataques (nodos Moves) ----------------------------------------

## Camina en este frame hacia `direction`; su largo (0-1) es la fracción de
## su velocidad. El ataque lo pide en cada frame en que quiere avanzar.
func walk(direction: Vector3) -> void:
	_move_steer = Vector3(direction.x, 0.0, direction.z).limit_length(1.0)


## Multiplica su velocidad de caminata (1 = la de siempre).
func set_pace(factor: float) -> void:
	move_speed = _walk_speed * maxf(factor, 0.0)


## Hace que mire hacia `direction` mientras dura el ataque (ZERO = al raider).
func face_along(direction: Vector3) -> void:
	_face_along = Vector3(direction.x, 0.0, direction.z)


## Gira el cuerpo ya, sin esperar su velocidad de giro, hacia `direction`.
func snap_facing(direction: Vector3) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() > 0.0001:
		rotation.y = atan2(-flat.x, -flat.z)


## El suelo bajo el centro del modelo, que es el eje sobre el que gira (el
## cuerpo físico va en su cabeza).
func core_point() -> Vector3:
	return floor_point(rig.center_point())


## `point` llevado a un lugar de la arena donde cabe el cuerpo, a ras de suelo.
func safe_point(point: Vector3) -> Vector3:
	var safe := _safe_arena_point(point)
	safe.y = ground_height(safe)
	return safe


## `point` recortado a la arena y a ras de suelo (para un aviso, que puede
## pisar escenografía).
func floor_point(point: Vector3) -> Vector3:
	var at := _clamp_to_arena(point)
	at.y = ground_height(at)
	return at


## Lleva el cuerpo a `point`, a ras de suelo, sin chocar con nada (un salto,
## un túnel, una embestida).
func glide_to(point: Vector3) -> void:
	global_position = Vector3(point.x, ground_height(point), point.z)
	velocity = Vector3.ZERO


## Metros que el cuerpo puede recorrer desde `from` hacia `direction` antes de
## dar con una celda bloqueada o con el borde de la arena, hasta `length`.
func clear_run(from: Vector3, direction: Vector3, length: float, step: float = 1.0) -> float:
	var flat := Vector3(direction.x, 0.0, direction.z).normalized()
	var reached := 0.0
	while reached + step <= length:
		var probe := from + flat * (reached + step)
		if not _is_walkable(probe) or _clamp_to_arena(probe) != probe:
			break
		reached += step
	return reached


## Golpe de suelo avisado contra todos los raiders dentro de algún disco, con
## su destello. El temblor lo pide el ataque (nodo Feel), según su tamaño.
func strike_ground(spots: Array[Vector3], radius: float, height_window: float,
		damage: float) -> Array[Node3D]:
	for spot: Vector3 in spots:
		Telegraph.spawn_disc(self, spot, radius, impact_flash_time, impact_color)
	return damage_players_in_discs(spots, radius, height_window, damage, self)


## Golpe de un cuerpo que cruza de `from` a `to` a ras de suelo: daña a cada
## raider en pie a menos de `half_width` metros de ese tramo y a menos de
## `height_window` metros de su altura. `hit` lleva los que ya recibieron este
## golpe (ids de instancia): cada uno lo recibe una sola vez por más frames
## que dure el cruce. Devuelve cuántos golpeó ahora.
func strike_along(from: Vector3, to: Vector3, half_width: float, height_window: float,
		damage: float, hit: Dictionary[int, bool]) -> int:
	var landed := 0
	var span := to - from
	var lane_height := (from.y + to.y) * 0.5
	span.y = 0.0
	for raider: Node3D in Coop.alive_players(get_tree()):
		var id := raider.get_instance_id()
		if hit.has(id):
			continue
		var offset := raider.global_position - from
		if absf(raider.global_position.y - lane_height) > height_window:
			continue
		offset.y = 0.0
		var along := clampf(offset.dot(span) / maxf(span.length_squared(), 0.0001), 0.0, 1.0)
		if offset.distance_to(span * along) > half_width:
			continue
		hit[id] = true
		var health := Health.find_in(raider)
		if health != null and not health.is_dead \
				and health.take_damage(damage, false, self) > 0.0:
			landed += 1
	return landed


## Altura del suelo REAL bajo `point`: el terreno o lo que tenga encima y sea
## lo bastante ancho para pararse (una formación de roca, una meseta). Los
## personajes y lo angosto (un tronco) no cuentan. Así un ataque que lleva el
## cuerpo nunca lo deja metido dentro de una roca.
func ground_height(point: Vector3) -> float:
	var terrain := Terrain.find(get_tree())
	var base := terrain.height_at(point.x, point.z) if terrain != null else point.y
	if not is_inside_tree():
		return base
	var space := get_world_3d().direct_space_state
	if space == null:
		return base
	var skip: Array[RID] = [get_rid()]
	for _attempt: int in GROUND_TRIES:
		var hit := _ray_down(space, point.x, point.z, base, skip)
		if hit.is_empty():
			return base
		var top := (hit["position"] as Vector3).y
		if not hit["collider"] is CharacterBody3D \
				and (top - base <= GROUND_STEP or _is_broad(space, point, base, top, skip)):
			return top
		skip.append(hit["rid"] as RID)
	return base


# --- privados ---------------------------------------------------------------------

## Lo primero que hay bajo (x, z) en la capa del mundo, sin contar `skip`.
func _ray_down(space: PhysicsDirectSpaceState3D, x: float, z: float, base: float,
		skip: Array[RID]) -> Dictionary:
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(
			Vector3(x, base + GROUND_PROBE_UP, z), Vector3(x, base - GROUND_PROBE_DOWN, z),
			WORLD_MASK, skip))


## True si alrededor de `point` hay suelo a la altura `top` en al menos
## GROUND_SUPPORT de los cuatro lados.
func _is_broad(space: PhysicsDirectSpaceState3D, point: Vector3, base: float, top: float,
		skip: Array[RID]) -> bool:
	var supported := 0
	for side: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var hit := _ray_down(space, point.x + side.x * GROUND_SUPPORT_REACH,
				point.z + side.y * GROUND_SUPPORT_REACH, base, skip)
		if not hit.is_empty() \
				and absf((hit["position"] as Vector3).y - top) <= GROUND_LEVEL_SLACK:
			supported += 1
	return supported >= GROUND_SUPPORT
