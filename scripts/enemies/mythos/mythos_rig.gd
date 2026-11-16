class_name MythosRig
extends Node3D
## Rig del fénix (nodo Visual de Mythos.tscn). El CUERPO físico de Mythos va
## por el suelo; lo que vuela es este rig. El modelo está armado en vuelo
## horizontal (pico a -Z) y aquí se lo mueve girando sus pivotes:
##   Hover     sube, baja, cambia de tamaño y gira sobre sí mismo
##   Body      se yergue, se clava de pico y se ladea
##   Neck/Head deshacen esa inclinación para que siga mirando al frente
##   Jaw       abre el pico
##   WingL/R   el brazo del ala: aletea, se levanta o se echa atrás
##   HandL/R   el tramo de afuera: va un poco atrasado y se pliega
##   Tail      se levanta para no clavarse en el suelo, y se mece
##   Legs      cuelgan, o se adelantan con las garras por delante
## Mythos y sus ataques piden una POSE con set_pose() y gestos sueltos con
## gesture() (los lleva el nodo Gestures). Lo que se mueve solo (la cabeza
## que sigue a su blanco, la cola y las patas que van atrasadas, los saltitos
## en tierra, las manías) lo lleva el nodo Motion. Las plumas se mecen solas
## en su shader. En la cinemática de llegada el modelo deja el cuerpo y vuela
## por su cuenta (fly_at): la pose sigue mandando en alas, patas y tamaño.
## En la segunda fase toma su FORMA RENACIDA (ascend): crece, cambia de
## color (los shaders mezclan hacia su paleta renacida) y aparecen las piezas
## que cuelgan de los pivotes Ascended*: la aureola, la corona y las plumas
## largas de más.
## Visual (este nodo) queda libre para los tweens de BossBase y la caída al
## morir: aquí solo se mueve lo que cuelga de Hover.

## FLY, WINDUP, CAST, GLIDE y NOVA son poses de vuelo; PERCH, REAR y SLASH,
## de tierra; DIVE es la caída de una a otra y ASHES la brasa entre vidas.
enum Pose { FLY, WINDUP, DIVE, PERCH, CAST, ASHES, REAR, SLASH, GLIDE, NOVA }

## Shaders del fénix que saben mezclar hacia la forma renacida.
const ASCEND_SHADERS: Array[String] = ["phoenix_plumage.gdshader", "phoenix_body.gdshader"]

@export_group("Tamaño")
## Tamaño del fénix en su primera forma (1 = como está armado en la escena).
@export var body_scale: float = 1.7
## Cuántas veces más grande es su forma renacida.
@export var ascended_scale: float = 1.35
## Segundos que tarda en tomar la forma renacida.
@export var ascend_seconds: float = 1.4

@export_group("Vuelo")
## Altura en metros del cuerpo del fénix sobre el suelo, en vuelo normal.
@export var hover_height: float = 4.6
## Esa altura en su forma renacida.
@export var ascended_hover_height: float = 6.2
## Altura del cuerpo mientras está posado, en metros por cada unidad de tamaño.
@export var perch_height: float = 1.2
## Metros que sube al cargar un ataque.
@export var windup_rise: float = 1.1
## Metros que el cuerpo sube y baja con cada aleteo.
@export var bob_amplitude: float = 0.2
## Rapidez con que pasa de una pose a otra (por segundo).
@export var pose_speed: float = 6.0
## Rapidez con que entra a las poses de golpe (zarpazo y picada), por segundo.
@export var strike_pose_speed: float = 16.0
## Metros que baja en el vuelo rasante de la Pasada de fuego.
@export var glide_drop: float = 1.6
## Inclinación en el vuelo rasante, en grados.
@export var glide_pitch_degrees: float = 6.0

@export_group("Cuerpo")
## Inclinación del cuerpo en vuelo normal, en grados (positivo = pico arriba, cuerpo erguido).
@export var fly_pitch_degrees: float = 44.0
## Inclinación al cargar un ataque, en grados.
@export var windup_pitch_degrees: float = 64.0
## Inclinación al conjurar, en grados.
@export var cast_pitch_degrees: float = 56.0
## Inclinación en la picada, en grados (negativo = pico hacia abajo).
@export var dive_pitch_degrees: float = -30.0
## Inclinación mientras está posado, en grados.
@export var perch_pitch_degrees: float = 24.0
## Parte de la inclinación que el cuello y la cabeza deshacen para seguir mirando al frente (0-1).
@export_range(0.0, 1.0) var head_level: float = 0.9
## Parte de la inclinación que la cola deshace para no clavarse en el suelo (0-1).
@export_range(0.0, 1.0) var tail_level: float = 0.5
## Vaivén de la cola hacia los lados, en grados.
@export var tail_sway_degrees: float = 8.0
## Grados que las patas se adelantan en la picada, con las garras por delante.
@export var dive_legs_degrees: float = 60.0

@export_group("En tierra")
## Metros que se alza al avisar un zarpazo o el despegue.
@export var rear_rise: float = 0.8
## Inclinación al alzarse, en grados (cuerpo casi vertical).
@export var rear_pitch_degrees: float = 70.0
## Inclinación en el zarpazo, en grados (se echa hacia adelante).
@export var slash_pitch_degrees: float = 2.0
## Ángulo de las alas en el zarpazo, en grados (negativo = golpean hacia abajo).
@export var slash_wing_degrees: float = -22.0

@export_group("Amanecer")
## Metros que sube sobre su altura de vuelo mientras carga el Amanecer.
@export var nova_rise: float = 2.6
## Inclinación mientras carga, en grados.
@export var nova_pitch_degrees: float = 76.0
## Tamaño al que se hincha con la carga completa (1 = no cambia).
@export var nova_scale: float = 1.1

@export_group("Alas")
## Segundos de un aleteo completo en vuelo normal.
@export var flap_period: float = 1.05
## Amplitud del aleteo del brazo del ala, en grados.
@export var flap_degrees: float = 30.0
## Amplitud del aleteo del tramo de afuera (la mano), en grados.
@export var hand_flap_degrees: float = 26.0
## Atraso de la mano respecto del brazo, como fracción de un aleteo (0-0.5).
@export_range(0.0, 0.5) var hand_lag: float = 0.16
## Ángulo de las alas levantadas al cargar un ataque, en grados.
@export var raised_degrees: float = 46.0
## Ángulo de las alas abiertas al conjurar, en grados.
@export var cast_degrees: float = 16.0
## Ángulo hacia atrás de las alas recogidas en la picada, en grados.
@export var swept_degrees: float = 52.0
## Grados que la mano se pliega hacia atrás en la picada y al posarse.
@export var folded_degrees: float = 48.0
## Amplitud del aleteo lento mientras está posado, en grados.
@export var perch_flap_degrees: float = 9.0

@export_group("Cenizas")
## Escala a la que se encoge el fénix cuando cae en cenizas.
@export var ashes_scale: float = 0.16
## Altura en metros de la brasa sobre el montón de cenizas.
@export var ashes_height: float = 0.55
## Segundos de un latido de la brasa.
@export var ashes_pulse_period: float = 0.9

@export_group("Vuelo dirigido")
## Parte de la inclinación que el cuello y la cabeza deshacen mientras lo lleva la cinemática (bajo = la cabeza apunta adonde vuela).
@export_range(0.0, 1.0) var directed_head_level: float = 0.25

## Metros que se suman a la altura de la pose: flight_lift lo lleva el vuelo
## (sube y baja mientras gira) y lift el ataque en curso (la Picada).
var flight_lift: float = 0.0
var lift: float = 0.0

var _pose: Pose = Pose.FLY
## Lo que pide la pose actual; _apply lo rearma en cada frame.
var _want: MythosPoseTarget = MythosPoseTarget.new()
var _time: float = 0.0
## Fase del aleteo, en radianes: avanza según el período de la pose.
var _flap_phase: float = 0.0
## Valores actuales, que persiguen a los de la pose: altura (m), inclinación,
## ala, mano, barrido del ala, pliegue de la mano y patas (grados), amplitudes
## del aleteo (grados) y escala.
var _height: float = 0.0
var _pitch: float = 0.0
var _wing: float = 0.0
var _hand: float = 0.0
var _sweep: float = 0.0
var _fold: float = 0.0
var _legs_angle: float = 0.0
var _flap: float = 0.0
var _hand_flap: float = 0.0
var _scale: float = 1.0
## Vuelo dirigido (fly_at): dónde va el modelo y cómo se orienta, en el mundo.
var _directed: bool = false
var _fly_point: Vector3 = Vector3.ZERO
var _fly_yaw: float = 0.0
var _fly_pitch: float = 0.0
var _fly_roll: float = 0.0
## Cuánto tomó la forma renacida (0-1).
var _ascend: float = 0.0
var _ascend_tween: Tween = null
## Las piezas cuyo shader mezcla hacia la forma renacida.
var _tinted: Array[MeshInstance3D] = []
var _last_position: Vector3 = Vector3.ZERO

@onready var _hover: Node3D = %Hover
@onready var _body: Node3D = %Body
@onready var _neck: Node3D = %Neck
@onready var _head: Node3D = %Head
@onready var _jaw: Node3D = %Jaw
@onready var _wing_left: Node3D = %WingL
@onready var _wing_right: Node3D = %WingR
@onready var _hand_left: Node3D = %HandL
@onready var _hand_right: Node3D = %HandR
@onready var _tail: Node3D = %Tail
@onready var _legs: Node3D = %Legs
@onready var _ash_mound: Node3D = %AshMound
@onready var _nova: MythosNova = %Nova
@onready var _trail: CPUParticles3D = %Trail
@onready var _burst: CPUParticles3D = %Burst
@onready var _aura: CPUParticles3D = %Aura
@onready var _halo: MythosHalo = %Halo
@onready var _gestures: MythosGestures = $Gestures
@onready var _motion: MythosMotion = $Motion
@onready var _ascended_parts: Array[Node3D] = [%AscendedCrown, %AscendedBack,
		%AscendedTail, %AscendedWingL, %AscendedWingR]


func _ready() -> void:
	_ash_mound.visible = false
	for node: Node in _hover.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var material := mesh.get_surface_override_material(0) as ShaderMaterial
		if material != null and material.shader != null \
				and ASCEND_SHADERS.has(material.shader.resource_path.get_file()):
			_tinted.append(mesh)
	_set_ascend(0.0)
	_last_position = global_position
	_apply(0.0)


func _process(delta: float) -> void:
	_time += delta
	var velocity := (global_position - _last_position) / delta if delta > 0.0 else Vector3.ZERO
	_last_position = global_position
	# Gestures lo ladea con lo que se mueve hacia su derecha; Motion suma el
	# resto de lo que el movimiento le hace al cuerpo.
	_gestures.tick(delta, velocity.dot(global_basis.x))
	_motion.tick(delta, velocity, _hover.global_transform, _head.global_position,
			_pose == Pose.PERCH, _pose == Pose.FLY or _pose == Pose.PERCH)
	_apply(delta)


## Cambia la pose; el rig llega a ella en unos frames.
func set_pose(pose: Pose) -> void:
	_pose = pose
	_ash_mound.visible = pose == Pose.ASHES


func pose() -> Pose:
	return _pose


## Un gesto suelto encima de la pose: &"roar", &"spit", &"flap", &"flinch"
## o &"spin" (ver MythosGestures).
func gesture(gesture_name: StringName) -> void:
	_gestures.play(gesture_name)


## Le da un punto del mundo para seguir con la cabeza (su blanco, la cámara).
func gaze_at(point: Vector3) -> void:
	_motion.gaze_at(point)


## Deja de seguir un punto con la cabeza.
func gaze_ahead() -> void:
	_motion.gaze_ahead()


## Vuelo dirigido (la llegada): el modelo deja el cuerpo y va a `point` (en
## el mundo) mirando hacia `yaw` (radianes, en el mundo), con `pitch_degrees`
## de inclinación (positivo = pico arriba) y `roll_degrees` de ladeo
## (positivo = ala izquierda abajo). Dura hasta stop_flying().
func fly_at(point: Vector3, yaw: float, pitch_degrees: float, roll_degrees: float) -> void:
	_directed = true
	_fly_point = point
	_fly_yaw = yaw
	_fly_pitch = pitch_degrees
	_fly_roll = roll_degrees
	_place_body()


## Termina el vuelo dirigido: el modelo vuelve sobre el cuerpo, en su pose.
func stop_flying() -> void:
	_directed = false


## Toma (o deja) la forma renacida de la segunda fase, de a poco.
func ascend(on: bool) -> void:
	if _ascend_tween != null and _ascend_tween.is_valid():
		_ascend_tween.kill()
	_ascend_tween = create_tween()
	_ascend_tween.tween_method(_set_ascend, _ascend, 1.0 if on else 0.0, ascend_seconds) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Carga del Amanecer: de 0 a 1 la bola de luz crece alrededor del fénix;
## con un valor negativo se apaga.
func set_nova(charge: float) -> void:
	_nova.charge(charge)


## Un estallido de luz: la bola crece de golpe hasta `radius` (unidades del
## modelo) y se apaga en `seconds`.
func pop_nova(radius: float, seconds: float) -> void:
	_nova.pop(radius, seconds)


## Enciende o apaga la estela de fuego que deja al moverse rápido.
func set_trail(on: bool) -> void:
	_trail.emitting = on


## Una ráfaga de brasas alrededor del cuerpo.
func burst() -> void:
	_burst.restart()
	_burst.emitting = true


## Altura en metros del cuerpo del fénix sobre los pies de Mythos, ahora.
func body_height() -> float:
	return _hover.position.y if _hover != null else hover_height


## Punto del mundo donde está su cabeza: de ahí salen plumas y bolas de fuego.
func beak_point() -> Vector3:
	return _head.global_position


## Tamaño actual del modelo, sin contar lo que encoge o hincha la pose.
func _size() -> float:
	return body_scale * lerpf(1.0, ascended_scale, _ascend)


func _apply(delta: float) -> void:
	MythosPoses.fill(_want, self, _pose, lerpf(hover_height, ascended_hover_height, _ascend),
			_size(), _nova.charge_amount)
	var speed := strike_pose_speed if _pose == Pose.SLASH or _pose == Pose.DIVE else pose_speed
	var blend := Juice.damp(speed, delta) if delta > 0.0 else 1.0
	_height = lerpf(_height, _want.height, blend)
	_pitch = lerpf(_pitch, _want.pitch, blend)
	_wing = lerpf(_wing, _want.wing, blend)
	_hand = lerpf(_hand, _want.hand, blend)
	_sweep = lerpf(_sweep, _want.sweep, blend)
	_fold = lerpf(_fold, _want.fold, blend)
	_legs_angle = lerpf(_legs_angle, _want.legs, blend)
	_flap = lerpf(_flap, _want.flap, blend)
	_hand_flap = lerpf(_hand_flap, _want.hand_flap, blend)
	_scale = lerpf(_scale, _want.scale, blend)
	_flap_phase = fmod(_flap_phase
			+ delta * _motion.flap_rate * TAU / maxf(_want.period, 0.01), TAU)
	_place_body()
	_place_wings()
	_place_tail_and_legs()


## Altura, tamaño e inclinación del cuerpo; el cuello y la cabeza deshacen la
## inclinación para seguir mirando al frente, y los gestos se suman encima.
func _place_body() -> void:
	var height := _height - _gestures.drop
	var size := _scale * _size()
	if _pose == Pose.ASHES:
		# La brasa late en su sitio en vez de mecerse.
		size *= 1.0 + 0.18 * sin(_time * TAU / maxf(ashes_pulse_period, 0.01))
	else:
		# El cuerpo sube cuando las alas bajan, y en tierra avanza a saltitos.
		height += -sin(_flap_phase) * bob_amplitude * (_flap / maxf(flap_degrees, 0.01)) \
				+ _motion.hop + flight_lift + lift
	_hover.position = Vector3(0.0, height, 0.0)
	_hover.scale = Vector3.ONE * size
	_hover.rotation.y = _gestures.yaw
	var pitch := deg_to_rad(_pitch + _gestures.pitch + _motion.lean)
	var roll := _gestures.roll
	var level := head_level
	if _directed:
		# La cinemática lo lleva: va donde le dicen y la cabeza apunta adonde vuela.
		_hover.global_position = _fly_point
		_hover.rotation.y += _fly_yaw - global_rotation.y
		pitch = deg_to_rad(_fly_pitch + _gestures.pitch)
		roll += _fly_roll
		level = directed_head_level
	_body.rotation = Vector3(pitch, deg_to_rad(_gestures.twist), deg_to_rad(roll))
	# El cuello y la cabeza se reparten la mirada; la cabeza cabecea apenas
	# con el aleteo y es la que se ladea.
	var look := Vector2(deg_to_rad(_motion.head_pitch), deg_to_rad(_motion.head_yaw)) * 0.5
	_neck.rotation.x = -pitch * level * 0.55 + deg_to_rad(_gestures.neck) + look.x
	_neck.rotation.y = look.y
	_head.rotation.x = -pitch * level * 0.45 + deg_to_rad(2.5) * sin(_flap_phase - 0.6) + look.x
	_head.rotation.y = look.y
	_head.rotation.z = deg_to_rad(_motion.head_roll)
	_jaw.rotation.x = -deg_to_rad(_gestures.jaw)


## Brazo y mano de cada ala. Las alas son espejo: el mismo ángulo con signo
## contrario.
func _place_wings() -> void:
	var arm := _wing + sin(_flap_phase) * _flap + _gestures.wing + _motion.wing
	var hand := deg_to_rad(_hand + sin(_flap_phase - hand_lag * TAU) * _hand_flap)
	var sweep := deg_to_rad(_sweep)
	var fold := deg_to_rad(_fold)
	# El borde de ataque baja un poco en el golpe hacia abajo.
	var twist := deg_to_rad(7.0) * cos(_flap_phase) * (_flap / maxf(flap_degrees, 0.01))
	_wing_left.rotation = Vector3(twist, sweep, -deg_to_rad(arm + _gestures.wing_left))
	_wing_right.rotation = Vector3(twist, -sweep, deg_to_rad(arm + _gestures.wing_right))
	_hand_left.rotation = Vector3(0.0, fold, -hand)
	_hand_right.rotation = Vector3(0.0, -fold, hand)


func _place_tail_and_legs() -> void:
	_tail.rotation.x = -deg_to_rad(_pitch) * tail_level + deg_to_rad(_motion.tail_pitch)
	_tail.rotation.y = deg_to_rad(tail_sway_degrees) * sin(_time * TAU / 2.6) \
			+ deg_to_rad(_motion.tail_yaw)
	_legs.rotation.x = deg_to_rad(_legs_angle + _motion.legs)


## Cuánto tomó la forma renacida: color de cada pieza, piezas de más y aura.
func _set_ascend(amount: float) -> void:
	_ascend = amount
	for mesh: MeshInstance3D in _tinted:
		mesh.set_instance_shader_parameter(&"ascend", clampf(amount, 0.0, 1.0))
	for part: Node3D in _ascended_parts:
		part.visible = amount > 0.01
		part.scale = Vector3.ONE * maxf(amount, 0.001)
	_aura.emitting = amount > 0.5
	_halo.set_ascend(amount)

