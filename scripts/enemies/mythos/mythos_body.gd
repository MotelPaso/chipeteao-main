class_name MythosBody
extends BossBase
## El cuerpo de Mythos en la arena: lo que sus ataques le piden para ubicar
## un punto, mover el cuerpo y golpear el suelo. Mythos (mythos.gd) hereda de
## aquí y suma las fases, las vidas y la elección de ataques.

## Hacia dónde mira mientras un ataque lo lleva (ZERO = mira al raider).
var _face_along: Vector3 = Vector3.ZERO


## `point` llevado a un lugar de la arena donde cabe el cuerpo, a ras de suelo.
func safe_point(point: Vector3) -> Vector3:
	var safe := _safe_arena_point(point)
	safe.y = _ground_height(safe)
	return safe


## `point` recortado a la arena y a ras de suelo (para un aviso o una zona,
## que pueden pisar escenografía).
func floor_point(point: Vector3) -> Vector3:
	var at := _clamp_to_arena(point)
	at.y = _ground_height(at)
	return at


## Lleva el cuerpo a `point`, a ras de suelo (el vuelo de un ataque).
func glide_to(point: Vector3) -> void:
	global_position = Vector3(point.x, _ground_height(point), point.z)
	velocity = Vector3.ZERO


## Hace que mire hacia `direction` mientras dura el ataque (ZERO = al raider).
func face_along(direction: Vector3) -> void:
	_face_along = Vector3(direction.x, 0.0, direction.z)


## Golpe de suelo avisado contra todos los raiders dentro de algún disco.
func strike_ground(spots: Array[Vector3], radius: float, height_window: float,
		damage: float) -> Array[Node3D]:
	return _resolve_ground_hit(spots, radius, height_window, damage)


func _ground_height(point: Vector3) -> float:
	var terrain := Terrain.find(get_tree())
	return terrain.height_at(point.x, point.z) if terrain != null else point.y
