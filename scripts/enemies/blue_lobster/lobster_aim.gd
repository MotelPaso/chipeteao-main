class_name LobsterAim
extends RefCounted
## Lo que comparten los ataques de la Langosta Azul para apuntar: adónde va a
## estar un raider y hacia dónde queda un punto, a ras de suelo.

# --- Edita aquí ---------------------------------------------------------------
## Cuántas veces puede crecer, como mucho, el tope del adelanto (max_lead de
## cada ataque) cuando el raider corre más rápido que su velocidad base.
const LEAD_GROWTH_MAX: float = 2.5


## Dónde va a estar `target` dentro de `seconds` si sigue como va, nunca a
## más de `max_lead` metros de donde está ahora. Ese tope es para un raider a
## su velocidad base y crece en proporción si corre más rápido: una build de
## velocidad no deja atrás la puntería. Siempre a ras de sus pies.
static func predicted(target: Node3D, seconds: float, max_lead: float) -> Vector3:
	var body := target as CharacterBody3D
	if body == null or seconds <= 0.0 or max_lead <= 0.0:
		return target.global_position
	var ahead := body.velocity * seconds
	ahead.y = 0.0
	return target.global_position + ahead.limit_length(max_lead * speed_ratio(body))


## Cuántas veces más rápido que su velocidad base se mueve `body` ahora: 1
## como mínimo y LEAD_GROWTH_MAX como mucho. Lo que no es un raider vale 1.
static func speed_ratio(body: CharacterBody3D) -> float:
	var raider := body as Player
	if raider == null or raider.move_speed <= 0.0:
		return 1.0
	var speed := Vector2(body.velocity.x, body.velocity.z).length()
	return clampf(speed / raider.move_speed, 1.0, LEAD_GROWTH_MAX)


## Dirección plana y unitaria de `from` a `to`; `fallback` si están encima.
static func flat_direction(from: Vector3, to: Vector3, fallback: Vector3) -> Vector3:
	var flat := to - from
	flat.y = 0.0
	if flat.length_squared() < 0.0001:
		return fallback
	return flat.normalized()


## `point` retrocedido `gap` metros hacia `from` (en el plano): donde frena un
## cuerpo que va de `from` a `point` y no quiere quedar encima. Si están a
## menos de `gap`, se queda en `from`.
static func short_of(from: Vector3, point: Vector3, gap: float) -> Vector3:
	var flat := point - from
	flat.y = 0.0
	var distance := flat.length()
	if distance <= gap:
		return Vector3(from.x, point.y, from.z)
	return point - flat / distance * gap


## `point` acercado a `origin` hasta quedar a `max_distance` metros como mucho
## (en el plano).
static func within(origin: Vector3, point: Vector3, max_distance: float) -> Vector3:
	var flat := point - origin
	flat.y = 0.0
	if flat.length() <= max_distance:
		return point
	var reached := origin + flat.normalized() * max_distance
	reached.y = point.y
	return reached
