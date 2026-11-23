class_name LobsterEntranceCamera
extends Camera3D
## La cámara de la cinemática de la Langosta Azul (nodo Camera de
## LobsterEntrance.tscn). Sus hijos Shot (LobsterEntranceShot) son los planos,
## en orden: la cinemática le dice cuál toca y esta cámara se planta donde ese
## plano pide, sin transición (son cortes), y lo sostiene con su movimiento
## (un empujón, una subida o bajada, un giro) y el temblor del golpe.
## Un plano encuadra a la langosta, al equipo o al centro de la arena. Al
## equipo lo encuadra entero: se aleja lo que haga falta para que entren
## todos los raiders. En un plano "aislado" solo ve a la langosta contra un
## fondo oscuro (nodo Backdrop) con su propia luz (nodo Light); para eso la
## langosta suma una capa visual propia (ISOLATION_LAYER).
## En los demás planos ve el mundo entero. Tampoco ahí tapa nada a quien
## filma: lo sólido del mapa acerca la cámara hasta quedar por delante, y la
## decoración que cruza la vista se esconde mientras dura el plano
## (LobsterEntranceSight).

## Capa visual que solo llevan las piezas de la langosta, el fondo y la luz.
const ISOLATION_LAYER: int = 1 << 19
## Altura sobre los pies de la langosta desde la que se mide si un plano en el
## mundo tiene la vista libre.
const SIGHT_HEIGHT: float = 1.6
## Metros mínimos de la cámara sobre el suelo.
const GROUND_CLEARANCE: float = 0.35
## Altura sobre los pies de un raider a la que se lo encuadra, y la de su cabeza.
const RAIDER_AIM: float = 1.0
const RAIDER_HEAD: float = 1.8
## Segundos que se le dan al último plano de un acto para medir su movimiento.
const LAST_SHOT_SPAN: float = 2.0

@export_group("Temblor")
## Metros que se sacude la cámara con un temblor de 1.
@export var shake_metres: float = 0.16
## Segundos que tarda en asentarse el temblor de un golpe.
@export var shake_seconds: float = 0.45

@export_group("Vista libre")
## Metros que la cámara queda por delante de lo que le tapa la vista en un plano en el mundo.
@export var sight_margin: float = 0.6
## Metros mínimos de la cámara a lo que mira cuando algo la obliga a acercarse.
@export var min_distance: float = 2.0
## Metros alrededor de la línea entre la cámara y lo que filma que quedan libres: la decoración y los enemigos que la cruzan se esconden mientras dura el plano.
@export var sight_clearance: float = 1.0
## La decoración de más de estos metros de radio nunca se esconde (el suelo, una meseta, una formación de roca).
@export var hide_radius_limit: float = 9.0

@export_group("Equipo")
## Metros de aire alrededor del equipo en un plano que lo encuadra.
@export var party_margin: float = 2.5

var _shots: Array[LobsterEntranceShot] = []
## Metros libres de cada plano en el mundo (medidos antes de congelarlo).
var _clear: Array[float] = []
var _boss: BlueLobster = null
var _party: Array[Node3D] = []
## El mundo en que se filma: el mapa de la etapa o la arena del jefe.
var _arena: Node3D = null
var _shot: LobsterEntranceShot = null
var _shot_clock: float = 0.0
var _shake: float = 0.0
var _clock: float = 0.0
## Lo que la cámara ve en un plano en el mundo: todo menos la capa propia.
var _world_mask: int = 0
var _sight: LobsterEntranceSight = null

@onready var _backdrop: MeshInstance3D = $Backdrop
@onready var _light: Light3D = $Light


func _ready() -> void:
	_world_mask = cull_mask & ~ISOLATION_LAYER
	_backdrop.layers = ISOLATION_LAYER
	_light.light_cull_mask = ISOLATION_LAYER
	_backdrop.visible = false
	_light.visible = false
	_sight = LobsterEntranceSight.new(get_tree())
	_sight.clearance = sight_clearance
	_sight.hide_radius_limit = hide_radius_limit
	for child: Node in get_children():
		var shot := child as LobsterEntranceShot
		if shot != null:
			_shots.append(shot)
			_clear.append(shot.distance)


## Los segundos en que entra cada plano del acto `act`, en orden.
func shot_times(act: LobsterEntranceShot.Act) -> PackedFloat32Array:
	var times := PackedFloat32Array()
	for shot: LobsterEntranceShot in _shots:
		if shot.act == act:
			times.append(shot.at_seconds)
	return times


## El plano del acto `act` que toca a los `seconds` segundos de ese acto (-1
## antes del primero).
func shot_at(act: LobsterEntranceShot.Act, seconds: float) -> int:
	var index := -1
	for candidate: int in _shots.size():
		if _shots[candidate].act == act and seconds >= _shots[candidate].at_seconds:
			index = candidate
	return index


func shot(index: int) -> LobsterEntranceShot:
	return _shots[index] if index >= 0 and index < _shots.size() else null


## Prepara los planos del acto `act` en el mundo `arena`, con `party` (los
## raiders) y `boss` (null mientras no existe). En un mapa de etapa hay que
## llamarlo ANTES de congelarlo: congelado, el mapa sale de la física y la
## vista libre ya no se puede medir.
func stage(act: LobsterEntranceShot.Act, arena: Node3D, party: Array[Node3D],
		boss: BlueLobster) -> void:
	_sight.clear()
	_arena = arena
	_party = party
	_boss = boss
	var keep := boss.global_position if boss != null else _party_center()
	_sight.collect(arena, keep, boss)
	for index: int in _shots.size():
		var candidate := _shots[index]
		if candidate.act != act or candidate.isolated:
			continue
		var eye := _focus_point(candidate) + Vector3.UP * (
				SIGHT_HEIGHT if candidate.subject == LobsterEntranceShot.Subject.BOSS else 0.0)
		var free := minf(_free_distance(eye, _direction(candidate, 0.0), candidate.distance),
				_free_distance(eye, _direction(candidate, 1.0), candidate.distance))
		_clear[index] = free


## Corta al plano `index`: la cámara queda plantada ahí desde este frame.
func cut_to(index: int) -> void:
	_sight.show_hidden()
	_shot = shot(index)
	if _shot == null:
		return
	_shot_clock = 0.0
	_shake = _shot.hit_shake
	fov = _shot.fov
	cull_mask = ISOLATION_LAYER if _shot.isolated else _world_mask
	_backdrop.visible = _shot.isolated
	_light.visible = _shot.isolated
	_place(index)
	if not _shot.isolated:
		_sight.hide_crossing(_eyes(index), _targets(), _boss)


## Un frame del plano en curso.
func shoot(delta: float) -> void:
	if _shot == null:
		return
	_clock += delta
	_shot_clock += delta
	_shake = move_toward(_shake, 0.0, delta / maxf(shake_seconds, 0.01))
	_place(_shots.find(_shot))


## Cuántas cosas escondió el plano en curso para que no tapen a quien filma.
func hidden_count() -> int:
	return _sight.hidden_count()


## Cuántas cosas siguen tapando a quien filma el plano en curso (tiene que
## dar 0): raiders, coberturas de la arena y decoración que no se escondió.
func blocking_count() -> int:
	if _shot == null or _shot.isolated:
		return 0
	var covers: Array[PackedVector2Array] = []
	var bounds := get_tree().get_first_node_in_group(&"arena_bounds")
	if bounds != null and bounds.has_method(&"cover_outlines"):
		covers = bounds.call(&"cover_outlines")
	var raiders: Array[Node3D] = []
	if _shot.subject == LobsterEntranceShot.Subject.BOSS:
		raiders = _party
	return _sight.blocking(_eyes(_shots.find(_shot)), _targets(), raiders, covers)


## Cuántos raiders quedan dentro del cuadro del plano en curso, de cuántos.
func party_in_view() -> Vector2i:
	var seen := 0
	for raider: Node3D in _party:
		if is_instance_valid(raider) and is_position_in_frustum(
				raider.global_position + Vector3.UP * RAIDER_AIM):
			seen += 1
	return Vector2i(seen, _party.size())


## Suma un temblor de `strength` (0-1) al plano en curso.
func shake(strength: float) -> void:
	_shake = clampf(maxf(_shake, strength), 0.0, 1.0)


## Devuelve a la vista lo que el plano en curso escondió (el mundo se va).
func show_hidden() -> void:
	_sight.show_hidden()


## La cinemática terminó: deja de ver solo a la langosta y devuelve lo escondido.
func release() -> void:
	_sight.clear()
	_shot = null
	_boss = null
	_party = []
	_arena = null
	cull_mask = _world_mask | ISOLATION_LAYER
	_backdrop.visible = false
	_light.visible = false


# --- privados ---------------------------------------------------------------------

## Planta la cámara donde pide el plano `index`, mirando a lo que mira.
func _place(index: int) -> void:
	var progress := clampf(_shot_clock / maxf(_shot_span(index), 0.1), 0.0, 1.0)
	var focus := _focus_point(_shot)
	var at := _camera_point(index, progress)
	var terrain := Terrain.find(get_tree())
	if terrain != null:
		at.y = maxf(at.y, terrain.height_at(at.x, at.z) + GROUND_CLEARANCE)
	# El temblor: dos senos que no van juntos, sin tocar ningún RNG.
	var jolt := shake_metres * _shake * _shake
	at += global_basis.x * sin(_clock * 71.0) * jolt + global_basis.y * sin(_clock * 53.0 + 1.3) * jolt
	global_position = at
	var target := focus + Vector3.UP * _shot.look_lift
	if at.distance_squared_to(target) > 0.0001:
		# Mirando casi a plomo hace falta otro "arriba" para no perder el horizonte.
		var steep := absf((target - at).normalized().y) > 0.98
		look_at(target, _front(_shot) if steep else Vector3.UP)
	rotation.z = deg_to_rad(_shot.roll_degrees)


## Dónde está la cámara del plano `index` cuando lleva `progress` (0-1) de su duración.
func _camera_point(index: int, progress: float) -> Vector3:
	var of := _shots[index]
	var reach := minf(of.distance, _clear[index])
	if of.subject == LobsterEntranceShot.Subject.PARTY:
		# Que entren todos pesa más que la vista libre: lo que tape se esconde.
		reach = maxf(reach, _party_fit(of.fov))
	reach = maxf(reach - of.push_in * progress, minf(min_distance, of.distance))
	return _focus_point(of) + _direction(of, progress) * reach \
			+ Vector3.UP * (of.height + of.rise * progress)


## Segundos que dura el plano `index`: hasta que entra el siguiente de su acto.
func _shot_span(index: int) -> float:
	if index < 0:
		return LAST_SHOT_SPAN
	for next: int in range(index + 1, _shots.size()):
		if _shots[next].act == _shots[index].act:
			return _shots[next].at_seconds - _shots[index].at_seconds
	return LAST_SHOT_SPAN


## Hacia dónde queda la cámara, vista desde lo que filma, cuando el plano
## lleva `progress` (0-1) de su duración.
func _direction(of: LobsterEntranceShot, progress: float) -> Vector3:
	return _front(of).rotated(Vector3.UP,
			deg_to_rad(of.around_degrees + of.orbit_degrees * progress))


## El frente de lo que filma el plano, en el suelo.
func _front(of: LobsterEntranceShot) -> Vector3:
	var front := Vector3.FORWARD
	var boss_arena := _arena as BossArena
	match of.subject:
		LobsterEntranceShot.Subject.BOSS:
			if _boss != null:
				front = -_boss.global_basis.z
		LobsterEntranceShot.Subject.PARTY:
			if boss_arena != null:
				front = boss_arena.boss_origin() - _party_center()
			else:
				front = Vector3.ZERO
				for raider: Node3D in _party:
					if is_instance_valid(raider):
						front -= raider.global_basis.z
		LobsterEntranceShot.Subject.ARENA:
			if boss_arena != null:
				front = boss_arena.spawn_origin() - _arena_center()
	front.y = 0.0
	return front.normalized() if front.length_squared() > 0.0001 else Vector3.FORWARD


## El punto del mundo que mira el plano.
func _focus_point(of: LobsterEntranceShot) -> Vector3:
	match of.subject:
		LobsterEntranceShot.Subject.PARTY:
			return _party_center() + Vector3.UP * RAIDER_AIM
		LobsterEntranceShot.Subject.ARENA:
			return _arena_center()
	if _boss == null:
		return _arena_center()
	var rig := _boss.rig
	match of.focus:
		LobsterEntranceShot.Focus.CLAW:
			# La pinza grande es la derecha.
			return rig.claw_point(false)
		LobsterEntranceShot.Focus.BODY:
			return rig.center_point() + Vector3.UP * rig.body_height()
		LobsterEntranceShot.Focus.TAIL:
			return rig.tail_point()
	return rig.head_point()


## El centro del equipo, a ras de sus pies.
func _party_center() -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	for raider: Node3D in _party:
		if is_instance_valid(raider):
			sum += raider.global_position
			count += 1
	return sum / float(count) if count > 0 else Vector3.ZERO


## El centro de la arena del jefe, a ras de suelo (o el del equipo sin arena).
func _arena_center() -> Vector3:
	var boss_arena := _arena as BossArena
	return boss_arena.portal_origin() if boss_arena != null else _party_center()


## Metros a los que tiene que estar la cámara para que entre todo el equipo
## con una apertura de `shot_fov` grados.
func _party_fit(shot_fov: float) -> float:
	var center := _party_center()
	var spread := 0.0
	for raider: Node3D in _party:
		if is_instance_valid(raider):
			spread = maxf(spread, raider.global_position.distance_to(center))
	return (spread + party_margin) / maxf(sin(deg_to_rad(shot_fov) * 0.5), 0.05)


## Desde dónde mira el plano `index`: donde empieza y donde termina su movimiento.
func _eyes(index: int) -> Array[Vector3]:
	if index < 0:
		return [global_position]
	return [_camera_point(index, 0.0), _camera_point(index, 1.0)]


## Lo que tiene que verse entero en el plano en curso: la langosta (cara,
## lomo, cola y pinzas) o cada raider (cuerpo y cabeza).
func _targets() -> Array[Vector3]:
	var targets: Array[Vector3] = []
	if _shot != null and _shot.subject == LobsterEntranceShot.Subject.BOSS and _boss != null:
		var rig := _boss.rig
		targets = [rig.head_point(), rig.center_point() + Vector3.UP * rig.body_height(),
				rig.tail_point(), rig.claw_point(true), rig.claw_point(false)]
	elif _shot != null and _shot.subject == LobsterEntranceShot.Subject.PARTY:
		for raider: Node3D in _party:
			if is_instance_valid(raider):
				targets.append(raider.global_position + Vector3.UP * RAIDER_AIM)
				targets.append(raider.global_position + Vector3.UP * RAIDER_HEAD)
	return targets


## Metros que se puede alejar la cámara desde `eye` hacia `direction` sin que
## el mapa le tape la vista, hasta `wanted`. Los personajes no cuentan.
func _free_distance(eye: Vector3, direction: Vector3, wanted: float) -> float:
	var space := get_world_3d().direct_space_state
	if space == null:
		return wanted
	var skip: Array[RID] = []
	for _attempt: int in 6:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
				eye, eye + direction * wanted, LobsterBody.WORLD_MASK, skip))
		if hit.is_empty():
			return wanted
		if hit["collider"] is CharacterBody3D:
			skip.append(hit["rid"] as RID)
			continue
		return maxf(eye.distance_to(hit["position"] as Vector3) - sight_margin, min_distance)
	return wanted
