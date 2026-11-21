class_name LobsterHead
extends Node
## La cabeza de la Langosta Azul (nodo HeadLife bajo Visual): lo que hacen
## solos los ojos, las antenas y la boca. El rig (LobsterRig) lo avanza en
## cada frame y le dice a qué punto mirar.
##   OJOS     cada ojo gira en su pedúnculo para seguir al blanco; cada tanto
##            uno se distrae y mira a otro lado
##   ANTENAS  se mecen, apuntan en parte hacia el blanco, se echan atrás
##            cuando la pose lo pide y sus tramos van atrasados como látigos
##   BOCA     las mandíbulas mastican y los palpos se agitan
## Mueve pivotes de nombre único de BlueLobster.tscn: %Head, %EyeL/R,
## %AntennaL1-3 / %AntennaR1-3, %MandibleL/R y %FeelerL/R.

@export_group("Mirada")
## Grados que cada ojo gira hacia los lados para seguir a su blanco.
@export var gaze_yaw_max: float = 60.0
## Grados que se inclina para mirarlo arriba o abajo.
@export var gaze_pitch_max: float = 28.0
## Rapidez con que los ojos alcanzan a su blanco (por segundo).
@export var gaze_speed: float = 9.0
## Segundos, más o menos, entre una distracción de un ojo y la siguiente.
@export var stray_every: float = 4.0
## Segundos que dura cada distracción.
@export var stray_seconds: float = 0.7
## Grados que el ojo distraído se desvía.
@export var stray_degrees: float = 45.0

@export_group("Antenas")
## Grados que las antenas se mecen solas.
@export var sway_degrees: float = 9.0
## Segundos de un vaivén completo.
@export var sway_seconds: float = 3.1
## Parte del giro hacia el blanco que las antenas acompañan (0-1).
@export_range(0.0, 1.0) var point_share: float = 0.35
## Grados que cada tramo se queda atrás por cada radián por segundo que gira el cuerpo.
@export var whip_per_turn: float = 14.0
## Grados que cada tramo se echa atrás por cada metro por segundo que avanza.
@export var whip_per_speed: float = 2.2
## Tope de ese arrastre, en grados por tramo.
@export var whip_max: float = 40.0
## Dureza del rebote de las antenas (más alto = alcanzan antes al cuerpo).
@export var whip_stiffness: float = 55.0
## Freno de ese rebote (más bajo = rebotan más veces).
@export var whip_damping: float = 6.0

@export_group("Boca")
## Grados que las mandíbulas se abren al masticar.
@export var chew_degrees: float = 4.0
## Mordidas por segundo.
@export var chew_per_second: float = 3.0
## Grados que se agitan los palpos.
@export var feeler_degrees: float = 12.0

## Punto del mundo que mira (INF = mira al frente).
var _gaze: Vector3 = Vector3.INF
var _clock: float = 0.0
## Por lado (0 izquierda, 1 derecha): giro e inclinación actuales del ojo,
## cuánto falta para su próxima distracción, cuánto le queda y hacia dónde.
var _eye_yaw: Array[float] = [0.0, 0.0]
var _eye_pitch: Array[float] = [0.0, 0.0]
var _stray_in: Array[float] = [0.0, 0.0]
var _stray_left: Array[float] = [0.0, 0.0]
var _stray_yaw: Array[float] = [0.0, 0.0]
## Arrastre de los látigos, igual para las dos antenas: hacia un lado y hacia
## atrás, con la velocidad de cada resorte.
var _whip_yaw: float = 0.0
var _whip_back: float = 0.0
var _whip_yaw_speed: float = 0.0
var _whip_back_speed: float = 0.0
## Rotación de reposo de cada pivote, tal como está armado en la escena.
var _rest: Dictionary[Node3D, Vector3] = {}
## Azar propio: las distracciones no tocan el RNG de la partida.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

@onready var _head: Node3D = %Head
@onready var _eyes: Array[Node3D] = [%EyeL, %EyeR]
@onready var _antennae: Array[Array] = [
	[%AntennaL1, %AntennaL2, %AntennaL3], [%AntennaR1, %AntennaR2, %AntennaR3],
]
@onready var _mandibles: Array[Node3D] = [%MandibleL, %MandibleR]
@onready var _feelers: Array[Node3D] = [%FeelerL, %FeelerR]


func _ready() -> void:
	_rng.randomize()
	for side: int in 2:
		_stray_in[side] = _rng.randf_range(0.5, 1.5) * stray_every
		_rest[_eyes[side]] = _eyes[side].rotation
		_rest[_mandibles[side]] = _mandibles[side].rotation
		_rest[_feelers[side]] = _feelers[side].rotation
		for segment: Node3D in _antennae[side]:
			_rest[segment] = segment.rotation


## Le da un punto del mundo para seguir con los ojos y las antenas.
func gaze_at(point: Vector3) -> void:
	_gaze = point


## Deja de seguir un punto: mira al frente.
func gaze_ahead() -> void:
	_gaze = Vector3.INF


## Punto del mundo donde está su cara (entre los ojos).
func face_point() -> Vector3:
	return _head.global_position


## Un frame. `antenna_back` son los grados que la pose echa las antenas hacia
## atrás, `maw` los que abre la boca, `turn_rate` cuánto gira el cuerpo
## (rad/s) y `forward_speed` cuánto avanza (m/s).
func tick(delta: float, antenna_back: float, maw: float, turn_rate: float,
		forward_speed: float) -> void:
	if delta <= 0.0:
		return
	var step := minf(delta, 1.0 / 30.0)
	_clock += step
	var look := _look_angles()
	_tick_eyes(step, look)
	_tick_antennae(step, antenna_back, look.x, turn_rate, forward_speed)
	_tick_mouth(maw)


# --- partes -----------------------------------------------------------------------

## Giro e inclinación (grados) desde la cabeza hasta el punto que mira.
func _look_angles() -> Vector2:
	if not _gaze.is_finite():
		return Vector2.ZERO
	var local := _head.global_transform.affine_inverse() * _gaze
	var yaw := rad_to_deg(atan2(-local.x, -local.z))
	var pitch := rad_to_deg(atan2(local.y, Vector2(local.x, local.z).length()))
	return Vector2(yaw, pitch)


func _tick_eyes(delta: float, look: Vector2) -> void:
	var blend := Juice.damp(gaze_speed, delta)
	for side: int in 2:
		var want_yaw := clampf(look.x, -gaze_yaw_max, gaze_yaw_max)
		if _stray_left[side] > 0.0:
			_stray_left[side] -= delta
			want_yaw = _stray_yaw[side]
		else:
			_stray_in[side] -= delta
			if _stray_in[side] <= 0.0:
				_stray_in[side] = _rng.randf_range(0.5, 1.5) * stray_every
				_stray_left[side] = stray_seconds
				_stray_yaw[side] = stray_degrees * (1.0 if _rng.randf() < 0.5 else -1.0)
		_eye_yaw[side] = lerpf(_eye_yaw[side], want_yaw, blend)
		_eye_pitch[side] = lerpf(_eye_pitch[side],
				clampf(look.y, -gaze_pitch_max, gaze_pitch_max), blend)
		var eye := _eyes[side]
		var rest := _rest[eye]
		# El pedúnculo se inclina hacia donde mira: giro primero, después la
		# inclinación de reposo más lo que sube o baja la mirada.
		eye.rotation = Vector3(rest.x + deg_to_rad(_eye_pitch[side]) * 0.7,
				deg_to_rad(_eye_yaw[side]), rest.z)


func _tick_antennae(delta: float, antenna_back: float, look_yaw: float, turn_rate: float,
		forward_speed: float) -> void:
	var want_yaw := clampf(-turn_rate * whip_per_turn, -whip_max, whip_max)
	_whip_yaw_speed = _spring_speed(_whip_yaw, _whip_yaw_speed, want_yaw, delta)
	_whip_yaw += _whip_yaw_speed * delta
	var want_back := clampf(forward_speed * whip_per_speed, -whip_max * 0.5, whip_max)
	_whip_back_speed = _spring_speed(_whip_back, _whip_back_speed, want_back, delta)
	_whip_back += _whip_back_speed * delta
	var point := clampf(look_yaw, -45.0, 45.0) * point_share
	for side: int in 2:
		# Cada antena se mece a su ritmo: la derecha va desfasada.
		var phase := _clock * TAU / maxf(sway_seconds, 0.1) + float(side) * 2.1
		var sway_yaw := sway_degrees * sin(phase)
		var sway_pitch := sway_degrees * 0.6 * sin(phase * 1.31 + 0.8)
		var segments: Array = _antennae[side]
		for index: int in segments.size():
			var segment := segments[index] as Node3D
			var rest := _rest[segment]
			# La base lleva el vaivén y apunta; los tramos de afuera llevan el
			# arrastre y la mayor parte de lo que la pose las echa atrás.
			var back := antenna_back * (0.5 if index == 0 else 0.35) \
					+ (_whip_back if index > 0 else 0.0)
			var yaw := (_whip_yaw if index > 0 else sway_yaw + point)
			var pitch := back + (sway_pitch if index == 0 else 0.0)
			segment.rotation = Vector3(rest.x + deg_to_rad(pitch), rest.y + deg_to_rad(yaw),
					rest.z)


func _tick_mouth(maw: float) -> void:
	var chew := chew_degrees * absf(sin(_clock * chew_per_second * PI))
	for side: int in 2:
		# Las mandíbulas se abren hacia afuera: la izquierda gira al revés que la derecha.
		var outward := 1.0 if side == 0 else -1.0
		var mandible := _mandibles[side]
		mandible.rotation.y = _rest[mandible].y + deg_to_rad(maw + chew) * outward
		var feeler := _feelers[side]
		feeler.rotation.x = _rest[feeler].x \
				+ deg_to_rad(feeler_degrees) * sin(_clock * 9.0 + float(side) * 1.7)


## Velocidad nueva de un resorte que está en `value` y quiere llegar a `target`.
func _spring_speed(value: float, speed: float, target: float, delta: float) -> float:
	return speed + ((target - value) * whip_stiffness - speed * whip_damping) * delta
