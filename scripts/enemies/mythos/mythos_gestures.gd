class_name MythosGestures
extends Node
## Gestos sueltos del fénix (nodo Gestures bajo Visual): movimientos cortos
## que se SUMAN a la pose del rig. Un ataque pide uno con
## MythosRig.gesture(&"nombre") y el rig lee aquí, en cada frame, cuánto
## sumarle al cuello, al pico, a las alas, al cuerpo y al giro:
##   roar    cabeza arriba, pico abierto y alas que se abren (el grito)
##   spit    echa la cabeza atrás y la lanza adelante con el pico abierto
##   flap    un aletazo fuerte: alas arriba y golpe hacia abajo
##   flinch  una sacudida corta cuando le duele
##   spin    una vuelta entera sobre sí mismo
## Además ladea el cuerpo cuando se mueve de costado.

@export_group("Grito")
## Segundos que dura el grito.
@export var roar_seconds: float = 1.5
## Grados que levanta la cabeza al gritar.
@export var roar_neck_degrees: float = 24.0
## Grados que abre el pico al gritar.
@export var roar_jaw_degrees: float = 36.0
## Grados que abre las alas al gritar.
@export var roar_wing_degrees: float = 22.0

@export_group("Escupir fuego")
## Segundos que dura el gesto de lanzar una bola de fuego.
@export var spit_seconds: float = 0.5
## Grados que echa la cabeza atrás antes de lanzarla adelante.
@export var spit_neck_degrees: float = 22.0
## Grados que abre el pico al lanzarla.
@export var spit_jaw_degrees: float = 30.0

@export_group("Aletazo")
## Segundos que dura el aletazo.
@export var flap_seconds: float = 0.55
## Grados que suben las alas antes de golpear hacia abajo.
@export var flap_wing_degrees: float = 50.0

@export_group("Sacudida y vuelta")
## Segundos que dura la sacudida cuando le duele.
@export var flinch_seconds: float = 0.3
## Grados de esa sacudida.
@export var flinch_pitch_degrees: float = 12.0
## Segundos que tarda en dar la vuelta sobre sí mismo.
@export var spin_seconds: float = 0.9

@export_group("Ladeo")
## Grados que se ladea por cada metro por segundo que se mueve de costado.
@export var bank_per_speed: float = 2.4
## Tope de ese ladeo, en grados.
@export var bank_max_degrees: float = 26.0
## Rapidez con que llega a su ladeo (por segundo).
@export var bank_speed: float = 4.0

## Lo que el rig suma en este frame: cuello, pico, alas, cuerpo y ladeo en
## grados; el giro sobre sí mismo en radianes.
var neck: float = 0.0
var jaw: float = 0.0
var wing: float = 0.0
var pitch: float = 0.0
var roll: float = 0.0
var yaw: float = 0.0

## Segundos que lleva cada gesto en curso.
var _clocks: Dictionary[StringName, float] = {}


## Arranca un gesto (si ya estaba en curso, vuelve a empezar).
func play(gesture: StringName) -> void:
	_clocks[gesture] = 0.0


## Un frame: avanza los gestos y el ladeo. `lateral_speed` son los metros por
## segundo que el fénix se mueve hacia su derecha.
func tick(delta: float, lateral_speed: float) -> void:
	neck = 0.0
	jaw = 0.0
	wing = 0.0
	pitch = 0.0
	yaw = 0.0
	for gesture: StringName in _clocks.keys():
		var clock := _clocks[gesture] + delta
		_clocks[gesture] = clock
		if not _apply(gesture, clock):
			_clocks.erase(gesture)
	var wanted := clampf(-lateral_speed * bank_per_speed, -bank_max_degrees, bank_max_degrees)
	roll = lerpf(roll, wanted, 1.0 - exp(-bank_speed * delta))


## Suma lo que aporta un gesto a los `clock` segundos. False si ya terminó.
func _apply(gesture: StringName, clock: float) -> bool:
	match gesture:
		&"roar":
			var t := clock / maxf(roar_seconds, 0.01)
			# Sube rápido, se sostiene y cae.
			var hold := smoothstep(0.0, 0.18, t) * (1.0 - smoothstep(0.75, 1.0, t))
			neck += roar_neck_degrees * hold
			jaw += roar_jaw_degrees * hold
			wing += roar_wing_degrees * hold
			return t < 1.0
		&"spit":
			var t := clock / maxf(spit_seconds, 0.01)
			# Atrás en el primer tercio, adelante de golpe y de vuelta.
			var back := smoothstep(0.0, 0.3, t) * (1.0 - smoothstep(0.3, 0.45, t))
			var forward := smoothstep(0.3, 0.45, t) * (1.0 - smoothstep(0.6, 1.0, t))
			neck += spit_neck_degrees * (back - forward)
			jaw += spit_jaw_degrees * forward
			return t < 1.0
		&"flap":
			var t := clock / maxf(flap_seconds, 0.01)
			var up := smoothstep(0.0, 0.3, t) * (1.0 - smoothstep(0.3, 0.5, t))
			var down := smoothstep(0.3, 0.5, t) * (1.0 - smoothstep(0.6, 1.0, t))
			wing += flap_wing_degrees * (up - down * 1.3)
			pitch += 8.0 * up
			return t < 1.0
		&"flinch":
			var t := clock / maxf(flinch_seconds, 0.01)
			pitch += flinch_pitch_degrees * sin(t * PI) * (1.0 - t)
			return t < 1.0
		&"spin":
			var t := clampf(clock / maxf(spin_seconds, 0.01), 0.0, 1.0)
			yaw += TAU * smoothstep(0.0, 1.0, t)
			return t < 1.0
	return false
