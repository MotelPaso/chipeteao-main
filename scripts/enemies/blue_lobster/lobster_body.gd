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

## Agresividad actual (0-1); la leen los ataques.
var aggression: float = 0.0

## Hacia dónde mira mientras un ataque la lleva (ZERO = mira al raider).
var _face_along: Vector3 = Vector3.ZERO
## Hacia dónde camina en este frame por pedido del ataque en curso; el largo
## es la fracción de su velocidad. Se gasta en cada frame.
var _move_steer: Vector3 = Vector3.ZERO

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
	if not is_fighting():
		return Vector3.ZERO
	if is_attacking():
		var steer := _move_steer
		_move_steer = Vector3.ZERO
		return steer
	return _stalk.intent(seek, distance)


func _facing_direction(steer: Vector3, seek: Vector3) -> Vector3:
	if not is_fighting():
		return Vector3.ZERO
	if _face_along.length_squared() > 0.0001:
		return _face_along
	return seek if seek.length_squared() > 0.0001 else steer


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


## Altura del suelo bajo `point`.
func ground_height(point: Vector3) -> float:
	var terrain := Terrain.find(get_tree())
	return terrain.height_at(point.x, point.z) if terrain != null else point.y
