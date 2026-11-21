class_name LobsterEntranceCamera
extends Camera3D
## La cámara de la entrada de la Langosta Azul (nodo Camera de
## LobsterEntrance.tscn). Sus hijos Shot (LobsterEntranceShot) son los planos,
## en orden: la entrada le dice cuál toca y esta cámara se planta donde ese
## plano pide, sin transición (son cortes), y lo sostiene con un empujón
## lento y el temblor del golpe.
## En los planos "aislados" solo ve a la langosta contra un fondo oscuro (nodo
## Backdrop) con su propia luz (nodo Light): nada del mapa puede taparle la
## cara. Para eso la langosta suma una capa visual propia (ISOLATION_LAYER).
## En los demás planos ve el mundo entero, con la horda congelada. Ahí tampoco
## la tapa nada: lo sólido (una roca, una meseta) acerca la cámara hasta
## quedar por delante, y la decoración que cruza la vista (la copa de un
## árbol, un tronco, un enemigo congelado) se esconde mientras dura ese plano.

## Capa visual que solo llevan las piezas de la langosta, el fondo y la luz.
const ISOLATION_LAYER: int = 1 << 19
## Altura sobre los pies de la langosta desde la que se mide si un plano en el
## mundo tiene la vista libre.
const SIGHT_HEIGHT: float = 1.6
## Metros mínimos de la cámara sobre el suelo.
const GROUND_CLEARANCE: float = 0.35
## Grupos de la arena de los que cuelga la decoración del mapa.
const SCENERY_GROUPS: Array[StringName] = [&"arena_bounds", &"scatter_keepout"]

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
## Metros alrededor de la línea entre la cámara y la langosta que quedan libres: la decoración y los enemigos que la cruzan se esconden mientras dura el plano.
@export var sight_clearance: float = 1.0
## La decoración de más de estos metros de radio nunca se esconde (el suelo, una meseta, una formación de roca).
@export var hide_radius_limit: float = 9.0

var _shots: Array[LobsterEntranceShot] = []
## Metros libres de cada plano en el mundo (medidos antes de congelarlo).
var _clear: Array[float] = []
var _boss: BlueLobster = null
var _shot: LobsterEntranceShot = null
var _shot_clock: float = 0.0
var _shake: float = 0.0
var _clock: float = 0.0
## Lo que la cámara ve en un plano en el mundo: todo menos la capa propia.
var _world_mask: int = 0
## La decoración del mapa que podría tapar un plano: cada entrada es
## [malla, centro en el mundo, radio]. Se junta antes de congelar el mundo.
var _scenery: Array[Array] = []
## Lo que este plano escondió, para devolverlo cuando termine.
var _hidden: Array[Node3D] = []

@onready var _backdrop: MeshInstance3D = $Backdrop
@onready var _light: Light3D = $Light


func _ready() -> void:
	_world_mask = cull_mask & ~ISOLATION_LAYER
	_backdrop.layers = ISOLATION_LAYER
	_light.light_cull_mask = ISOLATION_LAYER
	_backdrop.visible = false
	_light.visible = false
	for child: Node in get_children():
		var shot := child as LobsterEntranceShot
		if shot != null:
			_shots.append(shot)


## Los segundos de la canción en que entra cada plano, en orden.
func shot_times() -> PackedFloat32Array:
	var times := PackedFloat32Array()
	for shot: LobsterEntranceShot in _shots:
		times.append(shot.at_seconds)
	return times


## El plano que toca a los `seconds` segundos (-1 antes del primero).
func shot_at(seconds: float) -> int:
	var index := -1
	for candidate: int in _shots.size():
		if seconds >= _shots[candidate].at_seconds:
			index = candidate
	return index


func shot(index: int) -> LobsterEntranceShot:
	return _shots[index] if index >= 0 and index < _shots.size() else null


## Prepara la entrada de `boss`, con el mundo todavía en marcha: mide cuánta
## vista libre tiene cada plano en el mundo (congelado, el mapa sale de la
## física y ya no se puede medir).
func stage(boss: BlueLobster) -> void:
	_boss = boss
	_clear.clear()
	_collect_scenery()
	var eye := boss.global_position + Vector3.UP * SIGHT_HEIGHT
	for candidate: LobsterEntranceShot in _shots:
		var free := candidate.distance
		if not candidate.isolated:
			free = _free_distance(eye, _direction(candidate), candidate.distance)
		_clear.append(free)


## Corta al plano `index`: la cámara queda plantada ahí desde este frame.
func cut_to(index: int) -> void:
	_show_hidden()
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
		_hide_occluders(index)


## Un frame del plano en curso.
func shoot(delta: float) -> void:
	if _shot == null or _boss == null:
		return
	_clock += delta
	_shot_clock += delta
	_shake = move_toward(_shake, 0.0, delta / maxf(shake_seconds, 0.01))
	_place(_shots.find(_shot))


## Cuántas cosas escondió el plano en curso para que no tapen a la langosta.
func hidden_count() -> int:
	return _hidden.size()


## Suma un temblor de `strength` (0-1) al plano en curso.
func shake(strength: float) -> void:
	_shake = clampf(maxf(_shake, strength), 0.0, 1.0)


## La entrada terminó: deja de ver solo a la langosta y devuelve lo escondido.
func release() -> void:
	_show_hidden()
	_scenery.clear()
	_shot = null
	cull_mask = _world_mask | ISOLATION_LAYER
	_backdrop.visible = false
	_light.visible = false


# --- privados ---------------------------------------------------------------------

## Planta la cámara donde pide el plano `index`, mirando a lo que mira.
func _place(index: int) -> void:
	var focus := _focus_point(_shot)
	var reach := minf(_shot.distance, _clear[index]) if index < _clear.size() else _shot.distance
	var span := _shot_span(index)
	var pushed := _shot.push_in * clampf(_shot_clock / maxf(span, 0.1), 0.0, 1.0)
	reach = maxf(reach - pushed, minf(min_distance, _shot.distance))
	var at := focus + _direction(_shot) * reach + Vector3.UP * _shot.height
	var terrain := Terrain.find(get_tree())
	if terrain != null:
		at.y = maxf(at.y, terrain.height_at(at.x, at.z) + GROUND_CLEARANCE)
	# El temblor: dos senos que no van juntos, sin tocar ningún RNG.
	var jolt := shake_metres * _shake * _shake
	at += global_basis.x * sin(_clock * 71.0) * jolt + global_basis.y * sin(_clock * 53.0 + 1.3) * jolt
	global_position = at
	var target := focus + Vector3.UP * _shot.look_lift
	if at.distance_squared_to(target) > 0.0001:
		look_at(target, Vector3.UP)
	rotation.z = deg_to_rad(_shot.roll_degrees)


## Segundos que dura el plano `index` (hasta que entra el siguiente).
func _shot_span(index: int) -> float:
	if index < 0 or index + 1 >= _shots.size():
		return 2.0
	return _shots[index + 1].at_seconds - _shots[index].at_seconds


## Hacia dónde queda la cámara, vista desde la langosta: su frente girado
## around_degrees (en el plano).
func _direction(of: LobsterEntranceShot) -> Vector3:
	var front := -_boss.global_basis.z
	front.y = 0.0
	return front.normalized().rotated(Vector3.UP, deg_to_rad(of.around_degrees))


## El punto del mundo que mira el plano.
func _focus_point(of: LobsterEntranceShot) -> Vector3:
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


## Junta las mallas de la decoración del mapa con su centro y su radio.
func _collect_scenery() -> void:
	_scenery.clear()
	for group: StringName in SCENERY_GROUPS:
		for holder: Node in get_tree().get_nodes_in_group(group):
			for node: Node in holder.find_children("*", "MeshInstance3D", true, false):
				var view := node as MeshInstance3D
				if view.mesh == null:
					continue
				var box := view.get_aabb()
				var stretch := view.global_basis.get_scale()
				# El radio es la mitad de su lado más largo: para una copa, lo que tapa.
				var radius := maxf(box.size.x, maxf(box.size.y, box.size.z)) * 0.5 \
						* maxf(stretch.x, maxf(stretch.y, stretch.z))
				var center := view.global_transform * box.get_center()
				# Lo muy grande no se esconde, ni aquello sobre lo que está parada.
				if radius <= hide_radius_limit \
						and center.distance_to(_boss.global_position) > radius:
					_scenery.append([view, center, radius])


## Esconde, mientras dure el plano `index`, lo que cruza la vista entre la
## cámara y la langosta: decoración del mapa y enemigos congelados. Mira la
## vista desde donde la cámara empieza y desde donde termina su empujón.
func _hide_occluders(index: int) -> void:
	var rig := _boss.rig
	var targets: Array[Vector3] = [rig.head_point(),
			rig.center_point() + Vector3.UP * rig.body_height(), rig.tail_point(),
			rig.claw_point(true), rig.claw_point(false)]
	var eyes: Array[Vector3] = [global_position]
	var focus := _focus_point(_shot)
	eyes.append(global_position.move_toward(focus, maxf(_shot.push_in, 0.0)))
	for entry: Array in _scenery:
		var view := entry[0] as MeshInstance3D
		if not is_instance_valid(view) or not view.visible:
			continue
		if _crosses_sight(entry[1], float(entry[2]), eyes, targets):
			view.visible = false
			_hidden.append(view)
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		var body := node as EnemyBase
		if body == null or body == _boss or not body.visible:
			continue
		if _crosses_sight(body.aim_point(), 1.0, eyes, targets):
			body.visible = false
			_hidden.append(body)


## True si una esfera de `radius` metros en `center` queda a menos de
## sight_clearance de alguna línea entre un punto de `eyes` y uno de `targets`.
func _crosses_sight(center: Vector3, radius: float, eyes: Array[Vector3],
		targets: Array[Vector3]) -> bool:
	var reach := radius + sight_clearance
	for eye: Vector3 in eyes:
		for target: Vector3 in targets:
			var line := target - eye
			var along := clampf((center - eye).dot(line) / maxf(line.length_squared(), 0.0001),
					0.0, 1.0)
			if center.distance_to(eye + line * along) < reach:
				return true
	return false


## Devuelve a la vista lo que el plano anterior escondió.
func _show_hidden() -> void:
	for node: Node3D in _hidden:
		if is_instance_valid(node):
			node.visible = true
	_hidden.clear()


## Metros que se puede alejar la cámara desde `eye` hacia `direction` sin que
## el mapa le tape la vista, hasta `wanted`. Los personajes no cuentan: la
## horda congelada es parte del plano.
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
