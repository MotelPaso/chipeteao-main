extends RefCounted
## El suelo real bajo un punto, para los ataques y para los jefes que se
## mueven sobre el relieve: el terreno o, encima de él, lo que se pisa (el
## tablero de un puente, el estrado de una meseta, una roca). El terreno solo
## (Terrain.height_at) no ve nada de eso: un raider parado en el Gran Puente
## queda unos 6 m «en el aire» para un ataque que mide con él.
##
## Se busca desde una altura de referencia, la de quien pregunta (el raider,
## el centro de una onda, el cuerpo del jefe): el rayo baja desde RISE metros
## sobre ella, así lo que queda muy arriba no cuenta (el tablero, visto desde
## el cauce que cruza). Se usa con preload, sin class_name:
## const AttackFloor := preload("res://scripts/fx/attack_floor.gd")

## Edita aquí (no hay Inspector).
##
## Capa de colisión del mundo (terreno, rocas, mesetas, puentes). Los raiders
## y los enemigos también están en ella: el rayo se los salta.
const WORLD_MASK: int = 1
## Metros sobre la altura de referencia desde donde baja el rayo: lo más alto
## que un ataque o un cuerpo sube a algo que se pisa. Tiene que quedar bajo la
## altura del tablero de un puente sobre su cauce (unos 6 m).
const RISE: float = 2.0
## Metros bajo el terreno hasta donde baja el rayo.
const DROP: float = 3.0
## Cuerpos que el rayo se salta, como mucho, bajo un mismo punto.
const TRIES: int = 4
## Un suelo cuenta como ALTO (un tablero, un estrado, una roca) si queda más
## de estos metros sobre el terreno.
const RAISED_STEP: float = 0.6


## Altura en metros del suelo real bajo (point.x, point.z), buscado desde
## point.y (o desde el terreno, si point.y queda por debajo de él). `from`
## pone el mundo y el Terrain; sin árbol responde el terreno solo.
static func height(from: Node3D, point: Vector3) -> float:
	var base := terrain_height(from, point)
	if not from.is_inside_tree():
		return base
	var space := from.get_world_3d().direct_space_state
	if space == null:
		return base
	var top := maxf(point.y, base) + RISE
	var skip: Array[RID] = []
	for _attempt: int in TRIES:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
				Vector3(point.x, top, point.z), Vector3(point.x, base - DROP, point.z),
				WORLD_MASK, skip))
		if hit.is_empty():
			return base
		if not hit["collider"] is CharacterBody3D:
			return (hit["position"] as Vector3).y
		skip.append(hit["rid"] as RID)
	return base


## `point` con su altura llevada al suelo real (ver height).
static func on_floor(from: Node3D, point: Vector3) -> Vector3:
	point.y = height(from, point)
	return point


## True si el suelo real bajo `point` queda más de RAISED_STEP sobre el
## terreno: un tablero, un estrado o una roca que un raider pisa.
static func is_raised(from: Node3D, point: Vector3) -> bool:
	return height(from, point) - terrain_height(from, point) > RAISED_STEP


## La altura del terreno solo bajo `point` (point.y si no hay Terrain).
static func terrain_height(from: Node3D, point: Vector3) -> float:
	var terrain := Terrain.find(from.get_tree()) if from.is_inside_tree() else null
	return terrain.height_at(point.x, point.z) if terrain != null else point.y
