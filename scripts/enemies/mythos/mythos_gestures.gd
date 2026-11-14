class_name MythosGestures
extends Node
## Gestos sueltos del fénix (nodo Gestures bajo Visual): movimientos cortos
## que se SUMAN a la pose del rig. Un ataque pide uno con
## MythosRig.gesture(&"nombre") y el rig lee aquí, en cada frame, cuánto
## sumarle al cuello, al pico, a las alas, al cuerpo y al giro:
##   roar         cabeza arriba, pico abierto y alas que se abren (el grito)
##   screech      estira el cuello, abre el pico y le tiemblan las alas
##   spit         echa la cabeza atrás y la lanza adelante con el pico abierto
##   flap         un aletazo fuerte: alas arriba y golpe hacia abajo
##   slam         levanta las alas y las descarga con todo el cuerpo
##   swipe_left   un ala sola barre hacia adelante y el cuerpo acompaña
##   swipe_right  lo mismo con la otra
##   flinch       una sacudida corta cuando le duele
##   stagger      se tambalea: lo que le pasa cuando pierde una vida
##   shake        se sacude las plumas, como un pájaro mojado
##   spin         una vuelta entera sobre sí mismo
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

@export_group("Chillido")
## Segundos que dura el chillido.
@export var screech_seconds: float = 0.8
## Grados que baja la cabeza al estirar el cuello.
@export var screech_neck_degrees: float = 14.0
## Grados que abre el pico.
@export var screech_jaw_degrees: float = 30.0
## Grados que le tiemblan las alas.
@export var screech_shiver_degrees: float = 5.0

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

@export_group("Golpe de alas")
## Segundos que dura el golpe con las dos alas.
@export var slam_seconds: float = 0.7
## Grados que suben las alas antes de descargarlas.
@export var slam_wing_degrees: float = 58.0
## Grados que el cuerpo se echa hacia adelante con el golpe.
@export var slam_pitch_degrees: float = 20.0
## Metros que el cuerpo baja con el golpe.
@export var slam_drop: float = 0.9

@export_group("Barrido de ala")
## Segundos que dura el barrido con un ala.
@export var swipe_seconds: float = 0.5
## Grados que baja el ala al barrer.
@export var swipe_wing_degrees: float = 55.0
## Grados que el cuerpo gira acompañando al ala.
@export var swipe_twist_degrees: float = 16.0

@export_group("Sacudidas y vuelta")
## Segundos que dura la sacudida cuando le duele.
@export var flinch_seconds: float = 0.3
## Grados de esa sacudida.
@export var flinch_pitch_degrees: float = 12.0
## Segundos que se tambalea al perder una vida.
@export var stagger_seconds: float = 1.1
## Grados que se echa atrás al tambalearse.
@export var stagger_pitch_degrees: float = 26.0
## Grados que se bambolea hacia los lados al tambalearse.
@export var stagger_roll_degrees: float = 22.0
## Segundos que tarda en sacudirse las plumas.
@export var shake_seconds: float = 0.8
## Grados que se bambolea al sacudirse las plumas.
@export var shake_roll_degrees: float = 9.0
## Grados que abre las alas al sacudirse las plumas.
@export var shake_wing_degrees: float = 12.0
## Segundos que tarda en dar la vuelta sobre sí mismo.
@export var spin_seconds: float = 0.9

@export_group("Ladeo")
## Grados que se ladea por cada metro por segundo que se mueve de costado.
@export var bank_per_speed: float = 2.4
## Tope de ese ladeo, en grados.
@export var bank_max_degrees: float = 26.0
## Rapidez con que llega a su ladeo (por segundo).
@export var bank_speed: float = 4.0

## Lo que el rig suma en este frame. En grados: cuello, pico, las dos alas a
## la vez (wing), cada ala por su cuenta, inclinación del cuerpo, ladeo y
## giro del torso (twist). En radianes: la vuelta sobre sí mismo (yaw). En
## metros: lo que baja el cuerpo (drop).
var neck: float = 0.0
var jaw: float = 0.0
var wing: float = 0.0
var wing_left: float = 0.0
var wing_right: float = 0.0
var pitch: float = 0.0
var roll: float = 0.0
var twist: float = 0.0
var yaw: float = 0.0
var drop: float = 0.0

## Segundos que lleva cada gesto en curso.
var _clocks: Dictionary[StringName, float] = {}
## Ladeo por moverse de costado, en grados: llega de a poco.
var _bank: float = 0.0


## Arranca un gesto (si ya estaba en curso, vuelve a empezar).
func play(gesture: StringName) -> void:
	_clocks[gesture] = 0.0


## True si hay algún gesto en curso.
func is_busy() -> bool:
	return not _clocks.is_empty()


## Un frame: avanza los gestos y el ladeo. `lateral_speed` son los metros por
## segundo que el fénix se mueve hacia su derecha.
func tick(delta: float, lateral_speed: float) -> void:
	neck = 0.0
	jaw = 0.0
	wing = 0.0
	wing_left = 0.0
	wing_right = 0.0
	pitch = 0.0
	roll = 0.0
	twist = 0.0
	yaw = 0.0
	drop = 0.0
	for gesture: StringName in _clocks.keys():
		var clock := _clocks[gesture] + delta
		_clocks[gesture] = clock
		if not _apply(gesture, clock):
			_clocks.erase(gesture)
	var wanted := clampf(-lateral_speed * bank_per_speed, -bank_max_degrees, bank_max_degrees)
	_bank = lerpf(_bank, wanted, 1.0 - exp(-bank_speed * delta))
	roll += _bank


## Suma lo que aporta un gesto a los `clock` segundos. False si ya terminó.
func _apply(gesture: StringName, clock: float) -> bool:
	match gesture:
		&"roar", &"screech", &"spit":
			return _apply_head(gesture, clock)
		&"flap", &"slam", &"swipe_left", &"swipe_right":
			return _apply_wings(gesture, clock)
		&"flinch", &"stagger", &"shake", &"spin":
			return _apply_body(gesture, clock)
	return false


## Los gestos de cabeza y pico.
func _apply_head(gesture: StringName, clock: float) -> bool:
	match gesture:
		&"roar":
			var t := clock / maxf(roar_seconds, 0.01)
			# Sube rápido, se sostiene y cae.
			var hold := smoothstep(0.0, 0.18, t) * (1.0 - smoothstep(0.75, 1.0, t))
			neck += roar_neck_degrees * hold
			jaw += roar_jaw_degrees * hold
			wing += roar_wing_degrees * hold
			return t < 1.0
		&"screech":
			var t := clock / maxf(screech_seconds, 0.01)
			var hold := smoothstep(0.0, 0.15, t) * (1.0 - smoothstep(0.7, 1.0, t))
			neck -= screech_neck_degrees * hold
			jaw += screech_jaw_degrees * hold
			wing += screech_shiver_degrees * hold * sin(clock * 38.0)
			return t < 1.0
		_:
			var t := clock / maxf(spit_seconds, 0.01)
			# Atrás en el primer tercio, adelante de golpe y de vuelta.
			var back := smoothstep(0.0, 0.3, t) * (1.0 - smoothstep(0.3, 0.45, t))
			var forward := smoothstep(0.3, 0.45, t) * (1.0 - smoothstep(0.6, 1.0, t))
			neck += spit_neck_degrees * (back - forward)
			jaw += spit_jaw_degrees * forward
			return t < 1.0


## Los gestos de alas: suben primero (el aviso) y después golpean.
func _apply_wings(gesture: StringName, clock: float) -> bool:
	match gesture:
		&"flap":
			var t := clock / maxf(flap_seconds, 0.01)
			var up := smoothstep(0.0, 0.3, t) * (1.0 - smoothstep(0.3, 0.5, t))
			var down := smoothstep(0.3, 0.5, t) * (1.0 - smoothstep(0.6, 1.0, t))
			wing += flap_wing_degrees * (up - down * 1.3)
			pitch += 8.0 * up
			return t < 1.0
		&"slam":
			var t := clock / maxf(slam_seconds, 0.01)
			var up := smoothstep(0.0, 0.35, t) * (1.0 - smoothstep(0.35, 0.5, t))
			var down := smoothstep(0.35, 0.5, t) * (1.0 - smoothstep(0.65, 1.0, t))
			wing += slam_wing_degrees * (up - down * 1.2)
			# Se echa atrás al cargar y cae hacia adelante con el golpe.
			pitch += slam_pitch_degrees * (up * 0.5 - down)
			drop += slam_drop * down
			return t < 1.0
		_:
			var t := clock / maxf(swipe_seconds, 0.01)
			var up := smoothstep(0.0, 0.25, t) * (1.0 - smoothstep(0.25, 0.45, t))
			var down := smoothstep(0.25, 0.45, t) * (1.0 - smoothstep(0.6, 1.0, t))
			var sweep := swipe_wing_degrees * (up * 0.5 - down)
			if gesture == &"swipe_left":
				wing_left += sweep
				twist += swipe_twist_degrees * (down - up * 0.5)
			else:
				wing_right += sweep
				twist -= swipe_twist_degrees * (down - up * 0.5)
			return t < 1.0


## Los gestos de cuerpo entero.
func _apply_body(gesture: StringName, clock: float) -> bool:
	match gesture:
		&"flinch":
			var t := clock / maxf(flinch_seconds, 0.01)
			pitch += flinch_pitch_degrees * sin(t * PI) * (1.0 - t)
			return t < 1.0
		&"stagger":
			var t := clock / maxf(stagger_seconds, 0.01)
			var fade := 1.0 - clampf(t, 0.0, 1.0)
			pitch += stagger_pitch_degrees * sin(clampf(t, 0.0, 1.0) * PI)
			roll += stagger_roll_degrees * fade * sin(clock * 14.0)
			wing += stagger_roll_degrees * fade * sin(clock * 19.0)
			neck -= stagger_pitch_degrees * 0.6 * sin(clampf(t, 0.0, 1.0) * PI)
			return t < 1.0
		&"shake":
			var t := clock / maxf(shake_seconds, 0.01)
			var swell := sin(clampf(t, 0.0, 1.0) * PI)
			roll += shake_roll_degrees * swell * sin(clock * 30.0)
			wing += shake_wing_degrees * swell * absf(sin(clock * 22.0))
			return t < 1.0
		_:
			var t := clampf(clock / maxf(spin_seconds, 0.01), 0.0, 1.0)
			yaw += TAU * smoothstep(0.0, 1.0, t)
			return t < 1.0
