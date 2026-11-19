class_name MythosBody
extends BossBase
## El cuerpo de Mythos en la arena: lo que sus ataques le piden para ubicar
## un punto, mover el cuerpo, posarlo o hacerlo despegar (nodo Flight),
## golpear el suelo y marcar zonas de fuego (nodo Zones). Mythos (mythos.gd)
## hereda de aquí y suma las fases, las vidas y la elección de ataques.
##
## El suelo que pisa y que golpea es el real (AttackFloor): el tablero del
## Gran Puente y el estrado de una meseta cuentan, no solo el terreno.

const AttackFloor := preload("res://scripts/fx/attack_floor.gd")

## Agresividad actual (0-1); la leen los ataques.
var aggression: float = 0.0
## El rig que vuela (nodo Visual); los ataques le piden poses y gestos.
var rig: MythosRig = null

## Hacia dónde mira mientras un ataque lo lleva (ZERO = mira al raider).
var _face_along: Vector3 = Vector3.ZERO

## Su capa de colisión de siempre, para devolvérsela tras play_dead(). Se lee
## al entrar al árbol: más tarde un «Tiempo detenido» puede tenerla en 0.
@onready var _alive_layer: int = collision_layer
@onready var _zones: MythosZones = $Zones
@onready var _flight: MythosFlight = $Flight
## Lo que se siente de sus golpes (nodo Feel): los ataques le dicen qué tan
## fuerte fue cada uno y cuánto falta para los más grandes.
@onready var feel: MythosFeel = $Feel


## True mientras pelea. Mythos lo redefine con sus fases.
func is_fighting() -> bool:
	return true


## Fracción de su vuelo que mantiene ahora (0 = quieto). Mythos lo redefine:
## entera entre ataques y, en medio de uno, la que ese ataque le deje.
func _flight_share() -> float:
	return 1.0


func _pick_target() -> Node3D:
	return _flight.pick_target(get_tree())


func _movement_intent(seek: Vector3, distance: float) -> Vector3:
	var share := _flight_share()
	return _flight.intent(seek, distance) * share if share > 0.0 else Vector3.ZERO


func _facing_direction(steer: Vector3, seek: Vector3) -> Vector3:
	if not is_fighting():
		return Vector3.ZERO
	if _face_along.length_squared() > 0.0001:
		return _face_along
	return seek if seek.length_squared() > 0.0001 else steer


## Lo saca de la pelea como si hubiera muerto: las armas dejan de apuntarle,
## nadie choca con él y la flecha del HUD ya no lo señala. Sigue pisando el
## suelo (su máscara no cambia).
func play_dead() -> void:
	collision_layer = 0
	remove_from_group(&"enemies")
	remove_from_group(&"boss")


## Lo devuelve a la pelea después de play_dead().
func rise_again() -> void:
	collision_layer = _alive_layer
	add_to_group(&"enemies")
	add_to_group(&"boss")


## Punto del que salen sus plumas y sus bolas de fuego: el pico.
func muzzle_point() -> Vector3:
	return rig.beak_point()


## Lo posa en tierra (la Picada, al caer): desde ahí usa sus ataques de tierra.
func land() -> void:
	_flight.land(aggression)
	rig.set_pose(MythosRig.Pose.PERCH)


## Lo devuelve al vuelo (el Aletazo, al terminar).
func take_off() -> void:
	_flight.take_off()
	rig.set_pose(MythosRig.Pose.FLY)


## La pose de descanso de su postura: posado o volando. Los ataques vuelven
## a ella al terminar.
func rest_pose() -> MythosRig.Pose:
	return _flight.pose()


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


## Aviso en el suelo de un golpe suyo: un sigilo de `radius` metros en
## `center` que se llena en `seconds`; con `locked` se ve clavado. Devuelve
## el aviso por si hay que correrlo mientras carga (FireSigil.move_to).
func warn_disc(center: Vector3, radius: float, seconds: float,
		locked: bool = false) -> FireSigil:
	var sigil := Pools.acquire_scene(Pools.FIRE_SIGIL_SCENE) as FireSigil
	if sigil != null:
		sigil.show_disc(center, radius, seconds, locked)
	return sigil


## El estallido de fuego de un golpe de `radius` metros en `at` (solo el
## efecto: el daño lo hace el ataque).
func blast(at: Vector3, radius: float) -> void:
	FireBlast.spawn(Pools.FIRE_BLAST_SCENE, at, radius)


## Golpe de suelo avisado contra todos los raiders dentro de algún disco.
func strike_ground(spots: Array[Vector3], radius: float, height_window: float,
		damage: float) -> Array[Node3D]:
	return _resolve_ground_hit(spots, radius, height_window, damage)


## Marca una zona de fuego si cae en suelo caminable y el nodo Zones la deja
## salir. Con `on_raiders` puede nacer bajo un raider en pie (siempre avisa
## antes de arder); nunca nace junto a uno caído. Devuelve true si salió.
func spawn_fire_zone(center: Vector3, radius: float, warn_seconds: float,
		burn_seconds: float, dps: float, on_raiders: bool = false) -> bool:
	var at := _clamp_to_arena(center)
	if not _is_walkable(at):
		return false
	at.y = _ground_height(at)
	return _zones.mark(at, radius, warn_seconds, burn_seconds, dps, on_raiders)


## Apaga todo lo que sus ataques dejaron en la arena.
func _clear_hazards() -> void:
	_zones.extinguish_all()
	var tree := get_tree()
	tree.call_group(SafeCircle.GROUP, "dismiss")
	tree.call_group(Fireball.GROUP, "fizzle")
	tree.call_group(FireTornado.GROUP, "dissipate")
	tree.call_group(FireWave.GROUP, "dissipate")


## Además de lo que deja BossBase, un suelo alto que un raider pisa (el
## tablero de un puente, el estrado de una meseta) aunque quede cerca de un
## corte: ahí sigue al raider. Nunca dentro de una formación de roca.
func _is_walkable(point: Vector3) -> bool:
	if super._is_walkable(point):
		return true
	if _bounds == null or not _bounds.has_method("is_walkable") \
			or not bool(_bounds.call("is_walkable", Vector2(point.x, point.z))):
		return false
	return AttackFloor.is_raised(self, point)


## El suelo real bajo `point`, buscado desde su altura (ver AttackFloor).
func _ground_height(point: Vector3) -> float:
	return AttackFloor.height(self, point)
