class_name LobsterMotion
extends Node
## Vida propia del cuerpo de la Langosta Azul (nodo Motion bajo Visual): lo que
## se mueve SOLO, sin que un ataque lo pida. El rig (LobsterRig) lee aquí, en
## cada frame, cuánto sumarle a cada parte:
##   RESPIRA   las pinzas se abren y se cierran apenas y el abanico late
##   EMPUJE    se inclina hacia donde corre y se ladea al ir de costado
##   ARRASTRE  la cola va atrasada: se queda atrás al girar y rebota un poco
##   MANÍAS    cada tanto, si solo está rondando, chasquea una pinza, da un
##             golpe de cola o se sacude
## Lo de la cabeza (ojos, antenas y boca) lo lleva LobsterHead, y las patas,
## LobsterGait.

@export_group("Respira")
## Segundos de una respiración completa.
@export var breath_seconds: float = 2.2
## Grados que las pinzas se abren y se cierran al respirar.
@export var breath_claw_degrees: float = 5.0
## Cuánto late el abanico de la cola (0-1).
@export_range(0.0, 1.0) var breath_fan: float = 0.12
## Unidades del modelo que el cuerpo sube y baja al respirar.
@export var breath_height: float = 0.018

@export_group("Empuje")
## Grados que baja la cabeza por cada metro por segundo que avanza.
@export var lean_per_speed: float = 1.1
## Tope de esa inclinación, en grados.
@export var lean_max: float = 12.0
## Grados que se ladea por cada metro por segundo que va de costado.
@export var bank_per_speed: float = 1.4
## Tope de ese ladeo, en grados.
@export var bank_max: float = 11.0
## Rapidez con que llega a esa inclinación (por segundo).
@export var lean_speed: float = 5.0

@export_group("Arrastre")
## Grados que cada segmento de la cola se queda atrás por cada radián por segundo que gira.
@export var tail_per_turn: float = 5.0
## Tope de ese arrastre, en grados por segmento.
@export var tail_yaw_max: float = 15.0
## Grados que cada segmento se levanta por cada metro por segundo que avanza.
@export var tail_per_speed: float = 0.5
## Tope de eso, en grados por segmento.
@export var tail_lift_max: float = 7.0
## Dureza del rebote de la cola (más alto = alcanza antes al cuerpo).
@export var spring_stiffness: float = 70.0
## Freno de ese rebote (más bajo = rebota más veces).
@export var spring_damping: float = 8.0

@export_group("Manías")
## Segundos mínimos entre una manía y la siguiente.
@export var fidget_min_seconds: float = 2.5
## Segundos máximos entre una manía y la siguiente.
@export var fidget_max_seconds: float = 5.5
## Gestos que puede hacer como manía (ver LobsterGestures).
@export var fidget_gestures: Array[StringName] = [
	&"snap_left", &"snap_right", &"clack", &"tail_slap", &"shake",
]

## Lo que el rig suma en este frame. En grados: inclinación (lean), ladeo
## (bank), pinzas (claw), cola hacia un lado y hacia arriba por segmento. En
## unidades del modelo: height. De 0 a 1: fan.
var lean: float = 0.0
var bank: float = 0.0
var claw: float = 0.0
var fan: float = 0.0
var height: float = 0.0
var tail_yaw: float = 0.0
var tail_lift: float = 0.0

var _clock: float = 0.0
var _tail_yaw_speed: float = 0.0
var _tail_lift_speed: float = 0.0
var _fidget_left: float = 0.0
## Azar propio: las manías no tocan el RNG de la partida.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_fidget_left = _rng.randf_range(fidget_min_seconds, fidget_max_seconds)


## Un frame. `velocity` es la velocidad del cuerpo en el mundo, `basis` hacia
## dónde mira el modelo (su -Z es el frente), `turn_rate` cuánto gira (rad/s)
## e `idle` si solo está rondando. Devuelve el gesto de la manía que le acaba
## de dar, o &"" si ninguna.
func tick(delta: float, velocity: Vector3, basis: Basis, turn_rate: float,
		idle: bool) -> StringName:
	if delta <= 0.0:
		return &""
	# Un tirón de frames no debe disparar los resortes.
	var step := minf(delta, 1.0 / 30.0)
	_clock += step
	var frame := basis.orthonormalized()
	var forward_speed := velocity.dot(-frame.z)
	var side_speed := velocity.dot(frame.x)
	var breath := sin(_clock * TAU / maxf(breath_seconds, 0.1))
	claw = breath_claw_degrees * breath
	fan = breath_fan * breath
	height = breath_height * breath
	var blend := Juice.damp(lean_speed, step)
	lean = lerpf(lean, clampf(-forward_speed * lean_per_speed, -lean_max, lean_max), blend)
	bank = lerpf(bank, clampf(-side_speed * bank_per_speed, -bank_max, bank_max), blend)
	var want_yaw := clampf(-turn_rate * tail_per_turn, -tail_yaw_max, tail_yaw_max)
	_tail_yaw_speed = _spring_speed(tail_yaw, _tail_yaw_speed, want_yaw, step)
	tail_yaw += _tail_yaw_speed * step
	var want_lift := clampf(absf(forward_speed) * tail_per_speed, 0.0, tail_lift_max)
	_tail_lift_speed = _spring_speed(tail_lift, _tail_lift_speed, want_lift, step)
	tail_lift += _tail_lift_speed * step
	return _tick_fidget(step, idle)


## Velocidad nueva de un resorte que está en `value` y quiere llegar a `target`.
func _spring_speed(value: float, speed: float, target: float, delta: float) -> float:
	return speed + ((target - value) * spring_stiffness - speed * spring_damping) * delta


## Las manías: una cada tanto, y solo si está rondando.
func _tick_fidget(delta: float, idle: bool) -> StringName:
	_fidget_left -= delta
	if _fidget_left > 0.0 or not idle or fidget_gestures.is_empty():
		return &""
	_fidget_left = _rng.randf_range(fidget_min_seconds, fidget_max_seconds)
	return fidget_gestures[_rng.randi_range(0, fidget_gestures.size() - 1)]
