class_name PlayerCamera
extends SpringArm3D
## Cámara de un raider: vista con mouse o stick, los tres modos (tercera
## persona, primera persona y órbita libre) y el zoom de la órbita. Es el
## nodo CameraRig de Player.tscn: su spring_length es la distancia en
## tercera persona. Player decide cuándo corre cada paso (entrada y tick de
## física), así el orden del tick queda escrito en Player._physics_process.

## Modos que rota la acción "camera_mode" de cada jugador: THIRD_PERSON
## (por defecto; la vista gira el cuerpo), FIRST_PERSON (brazo en los ojos
## y la foca propia oculta) y FREE_ORBIT (la cámara orbita y el cuerpo mira
## hacia donde camina; las armas apuntan solas).
enum CameraMode { THIRD_PERSON, FIRST_PERSON, FREE_ORBIT }

## Capa visual del rig por slot: RIG_LAYER_BASE + slot + 1 en vez de la
## capa 1, para que la cámara en primera persona oculte solo su propio
## cuerpo y los compañeros lo sigan viendo.
const RIG_LAYER_BASE: int = 10

@export_group("Mouse y stick")
## Sensibilidad base del mouse, en radianes por píxel; el ajuste de opciones la multiplica.
@export var mouse_sensitivity: float = 0.003

@export_group("Inclinación")
## Inclinación inicial de la cámara, en grados (negativo mira hacia abajo).
@export var initial_pitch_deg: float = -20.0
## Inclinación mínima en tercera persona y órbita libre, en grados.
@export var min_pitch_deg: float = -80.0
## Inclinación máxima en tercera persona y órbita libre, en grados.
@export var max_pitch_deg: float = 10.0

@export_group("Primera persona")
## Largo del brazo en primera persona, en metros (la cámara queda en los ojos).
@export var first_person_arm_length: float = 0.05
## Inclinación mínima en primera persona, en grados.
@export var first_person_min_pitch_deg: float = -85.0
## Inclinación máxima en primera persona, en grados.
@export var first_person_max_pitch_deg: float = 85.0

@export_group("Órbita libre")
## Distancia mínima de la cámara, en metros.
@export var free_orbit_min_distance: float = 2.5
## Distancia máxima de la cámara, en metros.
@export var free_orbit_max_distance: float = 11.0
## Cuánto acerca o aleja cada paso de zoom (rueda o cruceta), en metros.
@export var free_orbit_zoom_step: float = 1.0
## Rapidez con que el cuerpo gira hacia donde camina, por segundo.
@export var free_orbit_turn_speed: float = 10.0

@onready var _body: Player = get_parent() as Player

var _camera_mode: CameraMode = CameraMode.THIRD_PERSON
## Giro del cuerpo en primera y tercera persona (se copia a su rotation.y).
var _yaw: float = 0.0
var _pitch: float = 0.0
## Órbita libre: giro de la cámara en el mundo (separado del cuerpo) y
## distancia actual (setup() la toma del spring_length de la escena).
var _orbit_yaw: float = 0.0
var _orbit_distance: float = 0.0
## spring_length de la escena (tercera persona); se restaura al volver a ese modo.
var _third_person_arm_length: float = 5.0


## Prepara la cámara; Player._ready la llama después de aplicar el personaje.
func setup() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# El brazo ignora la cápsula propia; si no, acerca la cámara.
	add_excluded_object(_body.get_rid())
	# ...y la de cada compañero: los raiders comparten la capa 1 con el mundo.
	# Diferido porque RunSystems crea los slots 1+ después del _ready de este.
	_exclude_party.call_deferred()
	if Coop.is_coop():
		# En pantalla dividida pintan las cámaras de cada viewport; esta solo
		# les presta su transformación.
		view_camera().current = false
	_yaw = _body.rotation.y
	_pitch = deg_to_rad(clamp(initial_pitch_deg, min_pitch_deg, max_pitch_deg))
	rotation.x = _pitch
	_third_person_arm_length = spring_length
	_orbit_distance = clampf(_third_person_arm_length,
			free_orbit_min_distance, free_orbit_max_distance)
	# Cada malla del rig pasa de la capa 1 a la capa visual del slot (ver
	# RIG_LAYER_BASE), que todas las cámaras ven salvo la propia en primera persona.
	_apply_rig_layer(_body.seal_rig)
	# Lo que se cuelgue del rig después (efectos, accesorios) también recibe
	# la capa; si no, su dueño lo vería flotando en primera persona.
	_body.seal_rig.child_entered_tree.connect(_apply_rig_layer)


## Entrada de cámara de este jugador (Player._unhandled_input la reenvía).
## Caído conserva la vista (mirar la pelea y ver llegar al rescatador), pero
## no el cambio de modo ni el zoom: cambiar de modo gira el cuerpo.
func handle_input(event: InputEvent, downed: bool) -> void:
	if not downed:
		# Por eventos, así la rueda del mouse y los botones del pad entran
		# igual, ya filtrados por slot en el set de acciones.
		if event.is_action_pressed(_body.slot_action(&"camera_mode")):
			_cycle_camera_mode()
			return
		if _camera_mode == CameraMode.FREE_ORBIT:
			if event.is_action_pressed(_body.slot_action(&"camera_zoom_in")):
				_set_orbit_distance(_orbit_distance - free_orbit_zoom_step)
				return
			if event.is_action_pressed(_body.slot_action(&"camera_zoom_out")):
				_set_orbit_distance(_orbit_distance + free_orbit_zoom_step)
				return
	if not _owns_mouse():
		return
	# Esc es del PauseMenu (Player se pausa con el árbol). Un clic vuelve a
	# capturar el mouse si quedó libre durante la partida.
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_apply_look(event.relative)
	elif event is InputEventMouseButton and event.pressed \
			and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## Stick derecho (el pad asignado en co-op; cualquiera en solo) por el
## mismo camino que el mouse. Dividir por la sensibilidad base pasa de
## radianes por segundo a las unidades de _apply_look, así el ajuste de
## sensibilidad escala igual al pad.
func apply_stick_look(delta: float) -> void:
	var stick := Coop.look_vector(_body.player_index)
	if stick == Vector2.ZERO:
		return
	_apply_look(stick * Coop.LOOK_SPEED * delta / maxf(mouse_sensitivity, 0.0001))


## Base con que se lee el movimiento: la del cuerpo en primera y tercera
## persona (su giro es el de la vista); en órbita libre, la de la cámara.
func move_basis() -> Basis:
	return Basis(Vector3.UP, _orbit_yaw) \
			if _camera_mode == CameraMode.FREE_ORBIT else _body.transform.basis


## Solo órbita libre: el cuerpo gira hacia su dirección de movimiento.
func face_movement(wish_dir: Vector3, delta: float) -> void:
	if _camera_mode != CameraMode.FREE_ORBIT or wish_dir == Vector3.ZERO:
		return
	_body.rotation.y = lerp_angle(_body.rotation.y, atan2(-wish_dir.x, -wish_dir.z),
			minf(free_orbit_turn_speed * delta, 1.0))


## Mantiene el giro del brazo en el MUNDO igual al de la órbita aunque el
## cuerpo gire (el giro del brazo es relativo al cuerpo). También corre
## caído, para que la vista siga moviendo la cámara en órbita libre.
func pin_orbit_arm() -> void:
	if _camera_mode == CameraMode.FREE_ORBIT:
		rotation.y = wrapf(_orbit_yaw - _body.rotation.y, -PI, PI)


func camera_mode() -> CameraMode:
	return _camera_mode


## Camera3D propia de este raider (ver Player.view_camera).
func view_camera() -> Camera3D:
	return get_node_or_null("Camera3D") as Camera3D


## Capa visual del cuerpo propio de este slot (ver RIG_LAYER_BASE).
func rig_visual_layer() -> int:
	return 1 << (RIG_LAYER_BASE + _body.player_index)


## Las cápsulas de los compañeros no bloquean el brazo de la cámara.
func _exclude_party() -> void:
	for node: Node in get_tree().get_nodes_in_group("player"):
		var mate := node as Player
		if mate != null and mate != _body:
			add_excluded_object(mate.get_rid())


## Pasa `root` y todo lo que cuelga de él a la capa visual de este slot.
func _apply_rig_layer(root: Node) -> void:
	var layer := rig_visual_layer()
	var self_visual := root as VisualInstance3D
	if self_visual != null:
		self_visual.layers = layer
	for node: Node in root.find_children("*", "VisualInstance3D", true, false):
		(node as VisualInstance3D).layers = layer


## True si este cuerpo usa el mouse: siempre en solo; en co-op, solo el
## slot del teclado.
func _owns_mouse() -> bool:
	return not Coop.is_coop() or Coop.device_for_slot(_body.player_index) == Coop.KEYBOARD_DEVICE


## Vista con mouse: la sensibilidad de opciones (SaveData.mouse_sensitivity,
## multiplicador 0.3-2.0) escala la base exportada en cada evento. En
## primera y tercera persona el giro mueve el cuerpo; en órbita libre, solo
## la cámara.
func _apply_look(relative: Vector2) -> void:
	var sensitivity: float = mouse_sensitivity * SaveData.mouse_sensitivity
	var wide := _camera_mode == CameraMode.FIRST_PERSON
	_pitch = clamp(_pitch - relative.y * sensitivity,
			deg_to_rad(first_person_min_pitch_deg if wide else min_pitch_deg),
			deg_to_rad(first_person_max_pitch_deg if wide else max_pitch_deg))
	rotation.x = _pitch
	if _camera_mode == CameraMode.FREE_ORBIT:
		_orbit_yaw = wrapf(_orbit_yaw - relative.x * sensitivity, -PI, PI)
	else:
		# Se envuelve igual que la órbita: sin esto el ángulo crece sin límite
		# y la precisión de float32 vuelve escalonado el giro lento.
		_yaw = wrapf(_yaw - relative.x * sensitivity, -PI, PI)
		_body.rotation.y = _yaw


func _cycle_camera_mode() -> void:
	var was_free := _camera_mode == CameraMode.FREE_ORBIT
	_camera_mode = ((int(_camera_mode) + 1) % CameraMode.size()) as CameraMode
	_apply_camera_mode(was_free)


func _apply_camera_mode(was_free: bool = false) -> void:
	var camera := view_camera()
	var rig_bit := rig_visual_layer()
	# Cada cambio de modo reinicia el estado transitorio; luego el modo pone el suyo.
	camera.cull_mask |= rig_bit
	rotation.y = 0.0
	if was_free:
		# De órbita libre a un modo atado al cuerpo: el giro de la cámara pasa
		# a ser el del cuerpo, así la vista no salta.
		_yaw = wrapf(_orbit_yaw, -PI, PI)
		_body.rotation.y = _yaw
	match _camera_mode:
		CameraMode.THIRD_PERSON:
			spring_length = _third_person_arm_length
		CameraMode.FIRST_PERSON:
			# Brazo en los ojos; la foca propia se oculta SOLO para esta
			# cámara (el rig está en la capa visual del slot).
			spring_length = first_person_arm_length
			camera.cull_mask &= ~rig_bit
		CameraMode.FREE_ORBIT:
			_orbit_yaw = _yaw
			spring_length = _orbit_distance
	# Vuelve a acotar la inclinación al rango del modo (primera persona permite más).
	var wide := _camera_mode == CameraMode.FIRST_PERSON
	_pitch = clamp(_pitch,
			deg_to_rad(first_person_min_pitch_deg if wide else min_pitch_deg),
			deg_to_rad(first_person_max_pitch_deg if wide else max_pitch_deg))
	rotation.x = _pitch


func _set_orbit_distance(distance: float) -> void:
	_orbit_distance = clampf(distance, free_orbit_min_distance, free_orbit_max_distance)
	if _camera_mode == CameraMode.FREE_ORBIT:
		spring_length = _orbit_distance
