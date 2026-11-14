class_name MythosMotion
extends Node
## Vida propia del fénix (nodo Motion bajo Visual de Mythos.tscn): lo que se
## mueve SOLO, sin que un ataque lo pida. El rig (MythosRig) lee aquí, en
## cada frame, cuánto sumarle a cada pivote:
##   MIRADA    el cuello y la cabeza siguen al raider que tiene de blanco
##   ARRASTRE  la cola y las patas van atrasadas: se quedan atrás al girar,
##             al avanzar y al caer, y rebotan un poco al alcanzar al cuerpo
##   EMPUJE    se inclina hacia donde vuela y aletea más rápido cuanto más
##             rápido va
##   SALTOS    en tierra avanza a saltitos
##   MANÍAS    cada tanto, si no está atacando, ladea la cabeza o mira a
##             los costados

## Lo que hace cuando le da una manía.
enum Fidget { NONE, TILT, SCAN }

@export_group("Mirada")
## Grados que gira la cabeza hacia cada lado para seguir a su blanco.
@export var gaze_yaw_max: float = 55.0
## Grados que la sube o la baja para seguirlo.
@export var gaze_pitch_max: float = 30.0
## Rapidez con que la cabeza alcanza a su blanco (por segundo).
@export var gaze_speed: float = 7.0
## Si su blanco queda más atrás que estos grados, deja de seguirlo con la cabeza.
@export var gaze_behind_degrees: float = 115.0

@export_group("Arrastre")
## Grados que la cola se queda atrás por cada radián por segundo que gira.
@export var tail_per_turn: float = 9.0
## Tope de ese arrastre hacia los lados, en grados.
@export var tail_yaw_max: float = 32.0
## Grados que la cola se levanta por cada metro por segundo que baja (y que baja cuando sube).
@export var tail_per_climb: float = 2.2
## Tope de ese arrastre hacia arriba y abajo, en grados.
@export var tail_pitch_max: float = 24.0
## Grados que las patas se van hacia atrás por cada metro por segundo que avanza.
@export var legs_per_speed: float = 3.0
## Tope de ese arrastre de las patas, en grados.
@export var legs_max: float = 30.0
## Dureza del rebote de cola y patas (más alto = alcanzan antes al cuerpo).
@export var spring_stiffness: float = 60.0
## Freno de ese rebote (más bajo = rebotan más veces).
@export var spring_damping: float = 7.0

@export_group("Empuje")
## Grados que se inclina hacia adelante por cada metro por segundo que avanza (hacia atrás si retrocede).
@export var lean_per_speed: float = 2.4
## Tope de esa inclinación, en grados.
@export var lean_max: float = 18.0
## Rapidez con que llega a esa inclinación (por segundo).
@export var lean_speed: float = 4.0
## Cuánto más rápido aletea por cada metro por segundo (0.07 = 7 % más).
@export var flap_rate_per_speed: float = 0.07
## Tope de esa prisa (1.7 = 70 % más rápido que quieto).
@export var flap_rate_max: float = 1.7

@export_group("Saltos")
## Altura de cada saltito en tierra, en metros.
@export var hop_height: float = 0.55
## Metros que avanza con cada saltito.
@export var hop_length: float = 2.2
## Velocidad en metros por segundo desde la que salta en vez de quedarse posado.
@export var hop_min_speed: float = 0.6
## Grados que abre las alas en lo alto de cada saltito.
@export var hop_wing_degrees: float = 10.0

@export_group("Manías")
## Segundos mínimos entre una manía y la siguiente.
@export var fidget_min_seconds: float = 3.5
## Segundos máximos entre una manía y la siguiente.
@export var fidget_max_seconds: float = 7.0
## Grados que ladea la cabeza.
@export var tilt_degrees: float = 20.0
## Segundos que la tiene ladeada.
@export var tilt_seconds: float = 1.1
## Grados que mira hacia cada costado.
@export var scan_degrees: float = 40.0
## Segundos que tarda en mirar a los dos costados.
@export var scan_seconds: float = 1.6

## Lo que el rig suma en este frame. En grados: giro, cabeceo y ladeo de la
## cabeza, cola hacia un lado y hacia arriba, patas, inclinación del cuerpo y
## alas. En metros: el saltito (hop). flap_rate multiplica la rapidez del aleteo.
var head_yaw: float = 0.0
var head_pitch: float = 0.0
var head_roll: float = 0.0
var tail_yaw: float = 0.0
var tail_pitch: float = 0.0
var legs: float = 0.0
var lean: float = 0.0
var wing: float = 0.0
var hop: float = 0.0
var flap_rate: float = 1.0

## Punto del mundo que mira (INF = mira al frente).
var _gaze: Vector3 = Vector3.INF
var _gaze_yaw: float = 0.0
var _gaze_pitch: float = 0.0
## Velocidad de cada resorte: cola hacia un lado, cola hacia arriba y patas.
var _tail_yaw_speed: float = 0.0
var _tail_pitch_speed: float = 0.0
var _legs_speed: float = 0.0
var _last_yaw: float = 0.0
var _hop_phase: float = 0.0
var _fidget: Fidget = Fidget.NONE
var _fidget_clock: float = 0.0
var _fidget_left: float = 0.0
## Hacia qué lado ladea la cabeza (1 o -1).
var _fidget_side: float = 1.0
## Azar propio: las manías no tocan el RNG de la partida.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_fidget_left = _rng.randf_range(fidget_min_seconds, fidget_max_seconds)


## Le da un punto del mundo para seguir con la cabeza.
func gaze_at(point: Vector3) -> void:
	_gaze = point


## Deja de seguir un punto: mira al frente.
func gaze_ahead() -> void:
	_gaze = Vector3.INF


## Un frame. `velocity` es la velocidad del cuerpo en el mundo, `frame` el
## transform del modelo (su -Z es el frente), `head` dónde está su cabeza,
## `grounded` si está posado e `idle` si no está en medio de un ataque.
func tick(delta: float, velocity: Vector3, frame: Transform3D, head: Vector3, grounded: bool,
		idle: bool) -> void:
	if delta <= 0.0:
		return
	# Un tirón de frames no debe disparar los resortes.
	var step := minf(delta, 1.0 / 30.0)
	var basis := frame.basis.orthonormalized()
	var forward_speed := velocity.dot(-basis.z)
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	_tick_gaze(step, basis, head)
	_tick_drag(step, basis, velocity.y, forward_speed)
	lean = lerpf(lean, clampf(-forward_speed * lean_per_speed, -lean_max, lean_max),
			Juice.damp(lean_speed, step))
	flap_rate = minf(1.0 + flat_speed * flap_rate_per_speed, flap_rate_max)
	_tick_hop(step, flat_speed, grounded)
	_tick_fidget(step, idle)
	head_yaw = clampf(head_yaw + _gaze_yaw, -gaze_yaw_max, gaze_yaw_max)
	head_pitch = _gaze_pitch


# --- partes -----------------------------------------------------------------------

## La cabeza persigue a su blanco, hasta donde le da el cuello.
func _tick_gaze(delta: float, basis: Basis, head: Vector3) -> void:
	var want_yaw := 0.0
	var want_pitch := 0.0
	if _gaze.is_finite():
		var local := basis.inverse() * (_gaze - head)
		var yaw := rad_to_deg(atan2(-local.x, -local.z))
		if absf(yaw) <= gaze_behind_degrees:
			want_yaw = clampf(yaw, -gaze_yaw_max, gaze_yaw_max)
			want_pitch = clampf(rad_to_deg(atan2(local.y, Vector2(local.x, local.z).length())),
					-gaze_pitch_max, gaze_pitch_max)
	var blend := Juice.damp(gaze_speed, delta)
	_gaze_yaw = lerpf(_gaze_yaw, want_yaw, blend)
	_gaze_pitch = lerpf(_gaze_pitch, want_pitch, blend)


## Cola y patas: cada una es un resorte que persigue adonde la deja el
## movimiento del cuerpo.
func _tick_drag(delta: float, basis: Basis, climb_speed: float, forward_speed: float) -> void:
	var yaw := basis.get_euler().y
	var turn_rate := angle_difference(_last_yaw, yaw) / delta
	_last_yaw = yaw
	var want_yaw := clampf(-turn_rate * tail_per_turn, -tail_yaw_max, tail_yaw_max)
	_tail_yaw_speed = _spring_speed(tail_yaw, _tail_yaw_speed, want_yaw, delta)
	tail_yaw += _tail_yaw_speed * delta
	var want_pitch := clampf(climb_speed * tail_per_climb, -tail_pitch_max, tail_pitch_max)
	_tail_pitch_speed = _spring_speed(tail_pitch, _tail_pitch_speed, want_pitch, delta)
	tail_pitch += _tail_pitch_speed * delta
	var want_legs := clampf(-forward_speed * legs_per_speed, -legs_max, legs_max)
	_legs_speed = _spring_speed(legs, _legs_speed, want_legs, delta)
	legs += _legs_speed * delta


## Velocidad nueva de un resorte que está en `value` y quiere llegar a `target`.
func _spring_speed(value: float, speed: float, target: float, delta: float) -> float:
	return speed + ((target - value) * spring_stiffness - speed * spring_damping) * delta


## En tierra avanza a saltitos: sube y baja según lo que camina.
func _tick_hop(delta: float, flat_speed: float, grounded: bool) -> void:
	if grounded and flat_speed > hop_min_speed:
		_hop_phase = fmod(_hop_phase + flat_speed * delta * PI / maxf(hop_length, 0.01), PI)
		hop = hop_height * sin(_hop_phase)
	else:
		_hop_phase = 0.0
		hop = lerpf(hop, 0.0, Juice.damp(12.0, delta))
	wing = hop_wing_degrees * hop / maxf(hop_height, 0.01)


## Las manías: una a la vez, y solo si no está atacando.
func _tick_fidget(delta: float, idle: bool) -> void:
	head_yaw = 0.0
	head_roll = 0.0
	if _fidget == Fidget.NONE:
		_fidget_left -= delta
		if _fidget_left <= 0.0 and idle:
			_fidget = Fidget.TILT if _rng.randf() < 0.5 else Fidget.SCAN
			_fidget_clock = 0.0
			_fidget_side = 1.0 if _rng.randf() < 0.5 else -1.0
			_fidget_left = _rng.randf_range(fidget_min_seconds, fidget_max_seconds)
		return
	_fidget_clock += delta
	var seconds := tilt_seconds if _fidget == Fidget.TILT else scan_seconds
	var t := clampf(_fidget_clock / maxf(seconds, 0.01), 0.0, 1.0)
	if _fidget == Fidget.TILT:
		# Ladea rápido, sostiene y vuelve.
		head_roll = tilt_degrees * _fidget_side \
				* smoothstep(0.0, 0.2, t) * (1.0 - smoothstep(0.75, 1.0, t))
	else:
		head_yaw = scan_degrees * _fidget_side * sin(t * TAU) * sin(t * PI)
	if t >= 1.0 or not idle:
		_fidget = Fidget.NONE
