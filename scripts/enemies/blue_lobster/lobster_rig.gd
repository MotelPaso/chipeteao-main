class_name LobsterRig
extends Node3D
## Rig de la Langosta Azul (nodo Visual de BlueLobster.tscn). El CUERPO físico
## va siempre por el suelo y queda en su cabeza (body_setback); lo que salta,
## se alza o se entierra es este rig.
## El modelo está armado mirando a -Z y aquí se lo mueve girando sus pivotes:
##   Root     sube (lift), se hunde (sink), gira sobre sí mismo y da el tamaño
##   Thorax   la altura del cuerpo, su inclinación y su ladeo
##   Arm, Elbow, Claw y Thumb (L y R)   cada brazo y su pinza
##   Tail1-5 y Fan   la cola segmentada y su abanico
## La langosta y sus ataques piden una POSE con set_pose() (la tabla está en
## LobsterPoses) y gestos sueltos con gesture() (nodo Gestures). Lo que se
## mueve solo lo llevan los nodos Motion (respira, se inclina, la cola va
## atrasada, manías), HeadLife (ojos, antenas y boca) y Gait (las ocho patas).
## Visual (este nodo) queda libre para los tweens de BossBase: aquí solo se
## mueve lo que cuelga de Root.
## El material del caparazón es uno solo y no se toca: el brillo de carga se
## escribe como uniform por instancia (`anger`) en cada pieza.

## STALK es la de ronda. REAR y SNAP son de UNA pinza (lead_left dice cuál);
## SIDE, DASH, COIL y SWEEP llevan un flanco adelante (side dice cuál).
enum Pose {
	STALK, REAR, SNAP, THREAT, CROUCH, LEAP, DIVE, SLAM, SIDE, DASH, COIL, SWEEP, DIG, TUNNEL,
	ERUPT, DEAD,
}

## Poses a las que entra de golpe (strike_pose_speed).
const STRIKE_POSES: Array[Pose] = [
	Pose.SNAP, Pose.DIVE, Pose.SLAM, Pose.DASH, Pose.SWEEP, Pose.ERUPT,
]
## Shader del caparazón y sus uniforms por instancia: el brillo de carga y
## cuánto se deshace cerca de la cámara.
const SHELL_SHADER := "lobster_shell.gdshader"
const ANGER_PARAM := &"anger"
const NEAR_FADE_PARAM := &"near_fade"
## Cambio mínimo del brillo de carga que vale la pena escribir en las piezas.
const ANGER_STEP: float = 0.04

@export_group("Tamaño")
## Tamaño de la langosta (1 = como está armada en la escena).
@export var body_scale: float = 1.55
## Metros que el modelo va corrido hacia atrás del cuerpo físico. Con esto el cuerpo físico (lo que choca, a lo que apuntan las armas y desde donde se miden las distancias) queda en su CABEZA y no en la mitad del lomo.
@export var body_setback: float = 1.4

@export_group("Poses")
## Rapidez con que pasa de una pose a otra (por segundo).
@export var pose_speed: float = 7.0
## Rapidez con que entra a las poses de golpe (pinzazo, caída, embestida), por segundo.
@export var strike_pose_speed: float = 22.0

@export_group("Cola")
## Parte de la inclinación del tórax que la cola deshace para seguir a ras del suelo (0-1).
@export_range(0.0, 1.0) var tail_level: float = 0.6
## Cuánto más se enrosca cada segmento que el anterior (1 = todos igual).
@export var tail_curl_growth: float = 1.2
## Apertura del abanico cerrado, como fracción del abierto (0-1).
@export_range(0.0, 1.0) var fan_closed: float = 0.25

@export_group("Efectos")
## Rapidez con que se enciende y se apaga el brillo de carga (por segundo).
@export var anger_speed: float = 6.0
## Rapidez con que crece y se achica el montículo de la Emboscada (por segundo).
@export var mound_speed: float = 7.0

## Metros que el modelo sube sobre el cuerpo (el Salto) y metros que se hunde
## (la Emboscada); los llevan los ataques.
var lift: float = 0.0
var sink: float = 0.0
## Grados que el modelo gira de más sobre sí mismo (el Coletazo).
var spin: float = 0.0
## Qué flanco lleva adelante en las poses de costado: 1 o -1.
var side: float = 1.0
## Qué pinza golpea en las poses de una sola pinza.
var lead_left: bool = true
## Si le dan manías mientras ronda (la entrada las apaga).
var fidgets: bool = true

var _pose: Pose = Pose.STALK
## Lo que pide la pose de ahora y los valores actuales, que la persiguen.
var _want: LobsterPoseTarget = LobsterPoseTarget.new()
var _now: LobsterPoseTarget = LobsterPoseTarget.new()
var _last_position: Vector3 = Vector3.ZERO
var _last_facing: float = 0.0
## Brillo de carga: lo pedido, lo de ahora y lo último escrito en las piezas.
var _anger_wanted: float = 0.0
var _anger: float = 0.0
var _anger_written: float = 0.0
var _mound_wanted: float = 0.0
var _mound: float = 0.0
var _mound_full: Vector3 = Vector3.ONE
## Las piezas con el shader del caparazón.
var _shell_meshes: Array[MeshInstance3D] = []
## Rotación de reposo de cada pivote, tal como está armado en la escena.
var _rest: Dictionary[Node3D, Vector3] = {}

@onready var _root: Node3D = %Root
@onready var _thorax: Node3D = %Thorax
@onready var _arm_left: Node3D = %ArmL
@onready var _arm_right: Node3D = %ArmR
@onready var _elbow_left: Node3D = %ElbowL
@onready var _elbow_right: Node3D = %ElbowR
@onready var _claw_left: Node3D = %ClawL
@onready var _claw_right: Node3D = %ClawR
@onready var _thumb_left: Node3D = %ThumbL
@onready var _thumb_right: Node3D = %ThumbR
@onready var _tail: Array[Node3D] = [%Tail1, %Tail2, %Tail3, %Tail4, %Tail5]
@onready var _fan_blades: Array[Node3D] = [%FanL1, %FanL2, %FanR1, %FanR2]
@onready var _mound_mesh: MeshInstance3D = %Mound
@onready var _dust: CPUParticles3D = %Dust
@onready var _gestures: LobsterGestures = $Gestures
@onready var _motion: LobsterMotion = $Motion
@onready var _head: LobsterHead = $HeadLife
@onready var _gait: LobsterGait = $Gait


func _ready() -> void:
	_root.scale = Vector3.ONE * body_scale
	for pivot: Node3D in [_arm_left, _arm_right, _elbow_left, _elbow_right, _claw_left,
			_claw_right, _fan_blades[0], _fan_blades[1], _fan_blades[2], _fan_blades[3]]:
		_rest[pivot] = pivot.rotation
	for node: Node in _root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var material := mesh.get_surface_override_material(0) as ShaderMaterial
		if material != null and material.shader != null \
				and material.shader.resource_path.get_file() == SHELL_SHADER:
			_shell_meshes.append(mesh)
	_mound_full = _mound_mesh.scale
	_mound_mesh.visible = false
	_last_position = global_position
	_last_facing = global_rotation.y
	_gait.setup(_root, _thorax, body_scale)
	snap_to_pose()


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	var velocity := (global_position - _last_position) / delta
	_last_position = global_position
	var facing := global_rotation.y + _root.rotation.y
	var turn_rate := angle_difference(_last_facing, facing) / delta
	_last_facing = facing
	_gestures.tick(delta)
	var idle := fidgets and _pose == Pose.STALK and not _gestures.is_busy()
	var fidget := _motion.tick(delta, velocity, _root.global_basis, turn_rate, idle)
	if not fidget.is_empty():
		_gestures.play(fidget)
	_apply(delta)
	_head.tick(delta, _now.antenna + _gestures.antenna, _now.maw + _gestures.maw, turn_rate,
			velocity.dot(-_root.global_basis.z.normalized()))
	_gait.tick(delta, velocity, _now.tuck + _gestures.tuck)
	_tick_anger(delta)
	_tick_mound(delta)


# --- lo que piden la langosta, sus ataques y la entrada ---------------------------

## Cambia la pose; el rig llega a ella en unos frames.
func set_pose(new_pose: Pose) -> void:
	_pose = new_pose


func pose() -> Pose:
	return _pose


## Lleva el rig a la pose de ahora ya, sin transición, y apoya las patas (el
## cuerpo acaba de aparecer o de cambiar de sitio).
func snap_to_pose() -> void:
	LobsterPoses.fill(_want, _pose, lead_left, side)
	_now.copy_from(_want)
	_place()
	_gait.plant()


## Un gesto suelto encima de la pose (ver LobsterGestures).
func gesture(gesture_name: StringName) -> void:
	_gestures.play(gesture_name)


## Le da un punto del mundo para seguir con los ojos y las antenas.
func gaze_at(point: Vector3) -> void:
	_head.gaze_at(point)


## Deja de seguir un punto: mira al frente.
func gaze_ahead() -> void:
	_head.gaze_ahead()


## Brillo de carga del caparazón (0-1): sube mientras prepara un golpe.
func set_anger(amount: float) -> void:
	_anger_wanted = clampf(amount, 0.0, 1.0)


## Enciende o apaga el polvo que levanta al correr o al cavar.
func set_dust(on: bool) -> void:
	_dust.emitting = on


## Tamaño del montículo de tierra que la tapa bajo tierra (0 = sin montículo).
func set_mound(amount: float) -> void:
	_mound_wanted = clampf(amount, 0.0, 1.0)


## Enciende o apaga la trama con que el caparazón se deshace cerca de la
## cámara (la entrada la apaga: ahí la cámara se le pega a propósito).
func set_near_fade(on: bool) -> void:
	for mesh: MeshInstance3D in _shell_meshes:
		mesh.set_instance_shader_parameter(NEAR_FADE_PARAM, 1.0 if on else 0.0)


## Suma `bit` a la capa visual de todas sus piezas (la entrada la filma sola
## con una cámara que solo ve esa capa).
func add_visual_layer(bit: int) -> void:
	for node: Node in find_children("*", "VisualInstance3D", true, false):
		(node as VisualInstance3D).layers |= bit


## Altura en metros del centro del tórax sobre los pies del cuerpo, ahora.
func body_height() -> float:
	return _thorax.position.y * body_scale + _root.position.y


## Punto del mundo donde está su cara.
func head_point() -> Vector3:
	return _head.face_point()


## Punto del mundo donde está el centro del modelo (el eje sobre el que gira).
func center_point() -> Vector3:
	return _root.global_position


## Punto del mundo donde está la punta de una pinza.
func claw_point(left: bool) -> Vector3:
	var claw := _claw_left if left else _claw_right
	return claw.global_transform * Vector3(0.0, 0.0, -1.2)


## Punto del mundo donde está el abanico de la cola.
func tail_point() -> Vector3:
	return _tail[4].global_transform * Vector3(0.0, 0.0, 0.7)


# --- privados ---------------------------------------------------------------------

func _apply(delta: float) -> void:
	LobsterPoses.fill(_want, _pose, lead_left, side)
	var speed := strike_pose_speed if STRIKE_POSES.has(_pose) else pose_speed
	_now.blend_toward(_want, Juice.damp(speed, delta))
	_place()


func _place() -> void:
	_place_body()
	_place_arm(_arm_left, _elbow_left, _claw_left, _thumb_left, -1.0,
			_now.raise_left + _gestures.raise_left, _now.spread_left + _gestures.spread_left,
			_now.elbow_left, _now.wrist_left,
			_now.claw_left + _gestures.claw_left + _motion.claw)
	_place_arm(_arm_right, _elbow_right, _claw_right, _thumb_right, 1.0,
			_now.raise_right + _gestures.raise_right, _now.spread_right + _gestures.spread_right,
			_now.elbow_right, _now.wrist_right,
			_now.claw_right + _gestures.claw_right + _motion.claw)
	_place_tail()


## Altura, giro e inclinación del cuerpo, con lo que suman los gestos, la
## vida propia y las pisadas.
func _place_body() -> void:
	_root.position = Vector3(0.0, lift - sink, body_setback)
	_root.rotation.y = deg_to_rad(_now.yaw + spin)
	_thorax.position.y = _now.height + _gestures.height + _motion.height + _gait.bob
	_thorax.rotation = Vector3(deg_to_rad(_now.pitch + _gestures.pitch + _motion.lean), 0.0,
			deg_to_rad(_now.roll + _gestures.roll + _motion.bank))


## Un brazo: hombro (levantar y abrir), codo, muñeca y el dedo móvil de la
## pinza. `outward` es -1 para el izquierdo y 1 para el derecho: los brazos
## son espejo y giran al revés.
func _place_arm(shoulder: Node3D, elbow: Node3D, claw: Node3D, thumb: Node3D, outward: float,
		raise: float, spread: float, bend: float, wrist: float, open: float) -> void:
	var rest := _rest[shoulder]
	shoulder.rotation = Vector3(rest.x + deg_to_rad(raise),
			rest.y - deg_to_rad(spread) * outward, rest.z)
	rest = _rest[elbow]
	elbow.rotation = Vector3(rest.x, rest.y + deg_to_rad(bend) * outward, rest.z)
	rest = _rest[claw]
	claw.rotation = Vector3(rest.x + deg_to_rad(wrist), rest.y, rest.z)
	thumb.rotation.y = deg_to_rad(maxf(open, 0.0)) * outward


## La cola: cada segmento se enrosca un poco más que el anterior, los dos
## primeros deshacen la inclinación del tórax y el abanico se abre o se cierra.
func _place_tail() -> void:
	var level := -(_now.pitch + _gestures.pitch + _motion.lean) * tail_level
	var curl := _now.tail_curl + _gestures.tail_curl - _motion.tail_lift
	var yaw := _now.tail_yaw + _motion.tail_yaw
	var weight := 1.0
	for index: int in _tail.size():
		var counter := level * 0.5 if index < 2 else 0.0
		_tail[index].rotation = Vector3(deg_to_rad(curl * weight + counter),
				deg_to_rad(yaw * weight), 0.0)
		weight *= tail_curl_growth
	var spread := lerpf(fan_closed, 1.0,
			clampf(_now.fan + _gestures.fan + _motion.fan, 0.0, 1.0))
	for blade: Node3D in _fan_blades:
		blade.rotation.y = _rest[blade].y * spread


## El brillo de carga persigue a lo pedido y se escribe en las piezas solo
## cuando cambió lo bastante.
func _tick_anger(delta: float) -> void:
	_anger = lerpf(_anger, _anger_wanted, Juice.damp(anger_speed, delta))
	var value := 0.0 if _anger_wanted <= 0.0 and _anger < ANGER_STEP else _anger
	if is_equal_approx(value, _anger_written) \
			or (value > 0.0 and absf(value - _anger_written) < ANGER_STEP):
		return
	_anger_written = value
	for mesh: MeshInstance3D in _shell_meshes:
		mesh.set_instance_shader_parameter(ANGER_PARAM, value)


func _tick_mound(delta: float) -> void:
	_mound = lerpf(_mound, _mound_wanted, Juice.damp(mound_speed, delta))
	_mound_mesh.visible = _mound > 0.02
	if _mound_mesh.visible:
		_mound_mesh.scale = _mound_full * Vector3(0.55 + 0.45 * _mound, _mound, 0.55 + 0.45 * _mound)
