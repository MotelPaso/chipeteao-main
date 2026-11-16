class_name LobsterGestures
extends Node
## Gestos sueltos de la Langosta Azul (nodo Gestures bajo Visual): movimientos
## cortos que se SUMAN a la pose del rig. Un ataque pide uno con
## LobsterRig.gesture(&"nombre") y el rig lee aquí, en cada frame, cuánto
## sumarle a cada parte:
##   snap_left    la pinza izquierda se abre de golpe y se cierra con un chasquido
##   snap_right   lo mismo con la derecha
##   clack        las dos pinzas chasquean dos veces (una amenaza)
##   roar         se yergue, abre la boca y el abanico y le tiemblan las pinzas
##   flinch       un respingo corto cuando un golpe le duele
##   shake        se sacude entera, como quien se quita la tierra de encima
##   tail_slap    levanta la cola y la descarga contra el suelo
##   hop          un saltito en el lugar
##   throes       los estertores de la muerte: patalea y se le cierran las pinzas

@export_group("Chasquido")
## Segundos que dura el chasquido de una pinza.
@export var snap_seconds: float = 0.32
## Grados que la pinza se abre antes de cerrarse.
@export var snap_open_degrees: float = 30.0
## Grados que el brazo se adelanta con el chasquido.
@export var snap_thrust_degrees: float = 14.0
## Segundos que dura la amenaza de las dos pinzas (dos chasquidos).
@export var clack_seconds: float = 0.7

@export_group("Rugido")
## Segundos que dura el rugido.
@export var roar_seconds: float = 1.4
## Grados que se yergue al rugir.
@export var roar_pitch_degrees: float = 10.0
## Grados que abre la boca.
@export var roar_maw_degrees: float = 30.0
## Grados que abre los brazos.
@export var roar_spread_degrees: float = 14.0
## Grados que le tiemblan las pinzas.
@export var roar_shiver_degrees: float = 5.0

@export_group("Respingo y sacudida")
## Segundos que dura el respingo cuando le duele.
@export var flinch_seconds: float = 0.3
## Grados que se echa atrás.
@export var flinch_pitch_degrees: float = 11.0
## Unidades del modelo que se encoge.
@export var flinch_drop: float = 0.1
## Segundos que tarda en sacudirse.
@export var shake_seconds: float = 0.7
## Grados que se bambolea al sacudirse.
@export var shake_roll_degrees: float = 8.0

@export_group("Cola y salto")
## Segundos que dura el golpe de cola.
@export var tail_slap_seconds: float = 0.55
## Grados que cada segmento de la cola se levanta antes de golpear.
@export var tail_slap_degrees: float = 20.0
## Segundos que dura el saltito.
@export var hop_seconds: float = 0.3
## Altura del saltito, en unidades del modelo.
@export var hop_height: float = 0.22

@export_group("Estertores")
## Segundos que patalea al morir.
@export var throes_seconds: float = 1.3
## Grados que le tiemblan las pinzas y la cola mientras tanto.
@export var throes_degrees: float = 16.0

## Lo que el rig suma en este frame. En grados: inclinación y ladeo del
## tórax, brazos (levantar y abrir, cada uno), pinzas, cola, antenas y boca.
## En unidades del modelo: height. De 0 a 1: fan y tuck.
var pitch: float = 0.0
var roll: float = 0.0
var height: float = 0.0
var raise_left: float = 0.0
var raise_right: float = 0.0
var spread_left: float = 0.0
var spread_right: float = 0.0
var claw_left: float = 0.0
var claw_right: float = 0.0
var tail_curl: float = 0.0
var fan: float = 0.0
var antenna: float = 0.0
var maw: float = 0.0
var tuck: float = 0.0

## Segundos que lleva cada gesto en curso.
var _clocks: Dictionary[StringName, float] = {}


## Arranca un gesto (si ya estaba en curso, vuelve a empezar).
func play(gesture: StringName) -> void:
	_clocks[gesture] = 0.0


## True si hay algún gesto en curso.
func is_busy() -> bool:
	return not _clocks.is_empty()


## Un frame: avanza los gestos en curso.
func tick(delta: float) -> void:
	pitch = 0.0
	roll = 0.0
	height = 0.0
	raise_left = 0.0
	raise_right = 0.0
	spread_left = 0.0
	spread_right = 0.0
	claw_left = 0.0
	claw_right = 0.0
	tail_curl = 0.0
	fan = 0.0
	antenna = 0.0
	maw = 0.0
	tuck = 0.0
	for gesture: StringName in _clocks.keys():
		var clock := _clocks[gesture] + delta
		_clocks[gesture] = clock
		if not _apply(gesture, clock):
			_clocks.erase(gesture)


## Suma lo que aporta un gesto a los `clock` segundos. False si ya terminó.
func _apply(gesture: StringName, clock: float) -> bool:
	match gesture:
		&"snap_left", &"snap_right", &"clack":
			return _apply_claws(gesture, clock)
		&"roar", &"flinch", &"shake":
			return _apply_body(gesture, clock)
		&"tail_slap", &"hop", &"throes":
			return _apply_rest(gesture, clock)
	return false


## Los chasquidos: la pinza se abre rápido y se cierra de golpe.
func _apply_claws(gesture: StringName, clock: float) -> bool:
	if gesture == &"clack":
		var whole := clock / maxf(clack_seconds, 0.01)
		# Dos chasquidos seguidos, uno por mitad.
		var beat := fmod(clampf(whole, 0.0, 0.999) * 2.0, 1.0)
		var both := _snap_curve(beat)
		claw_left += both
		claw_right += both
		spread_left += 6.0 * sin(beat * PI)
		spread_right += 6.0 * sin(beat * PI)
		return whole < 1.0
	var t := clock / maxf(snap_seconds, 0.01)
	var open := _snap_curve(clampf(t, 0.0, 1.0))
	var thrust := snap_thrust_degrees * sin(clampf(t, 0.0, 1.0) * PI)
	if gesture == &"snap_left":
		claw_left += open
		raise_left -= thrust
	else:
		claw_right += open
		raise_right -= thrust
	return t < 1.0


## Grados que una pinza suma a lo largo de un chasquido (t de 0 a 1): se abre
## en la primera mitad y se cierra de golpe, más de lo que estaba.
func _snap_curve(t: float) -> float:
	var open := smoothstep(0.0, 0.45, t) * (1.0 - smoothstep(0.5, 0.62, t))
	var shut := smoothstep(0.5, 0.62, t) * (1.0 - smoothstep(0.75, 1.0, t))
	return snap_open_degrees * (open - shut * 1.6)


## Los gestos de cuerpo entero.
func _apply_body(gesture: StringName, clock: float) -> bool:
	match gesture:
		&"roar":
			var t := clock / maxf(roar_seconds, 0.01)
			# Sube rápido, se sostiene y cae.
			var hold := smoothstep(0.0, 0.15, t) * (1.0 - smoothstep(0.78, 1.0, t))
			var shiver := roar_shiver_degrees * hold * sin(clock * 42.0)
			pitch += roar_pitch_degrees * hold
			maw += roar_maw_degrees * hold
			fan += hold
			antenna += 24.0 * hold
			spread_left += roar_spread_degrees * hold
			spread_right += roar_spread_degrees * hold
			claw_left += 18.0 * hold + shiver
			claw_right += 18.0 * hold - shiver
			return t < 1.0
		&"flinch":
			var t := clampf(clock / maxf(flinch_seconds, 0.01), 0.0, 1.0)
			var kick := sin(t * PI) * (1.0 - t)
			pitch += flinch_pitch_degrees * kick
			height -= flinch_drop * kick
			raise_left += 16.0 * kick
			raise_right += 16.0 * kick
			antenna += 30.0 * kick
			return t < 1.0
		_:
			var t := clampf(clock / maxf(shake_seconds, 0.01), 0.0, 1.0)
			var swell := sin(t * PI)
			roll += shake_roll_degrees * swell * sin(clock * 34.0)
			antenna += 14.0 * swell * sin(clock * 27.0)
			claw_left += 10.0 * swell * absf(sin(clock * 22.0))
			claw_right += 10.0 * swell * absf(sin(clock * 22.0))
			return t < 1.0


## La cola, el saltito y los estertores.
func _apply_rest(gesture: StringName, clock: float) -> bool:
	match gesture:
		&"tail_slap":
			var t := clampf(clock / maxf(tail_slap_seconds, 0.01), 0.0, 1.0)
			var up := smoothstep(0.0, 0.4, t) * (1.0 - smoothstep(0.4, 0.55, t))
			var down := smoothstep(0.4, 0.55, t) * (1.0 - smoothstep(0.7, 1.0, t))
			tail_curl += tail_slap_degrees * (down * 0.7 - up)
			fan += up
			return t < 1.0
		&"hop":
			var t := clampf(clock / maxf(hop_seconds, 0.01), 0.0, 1.0)
			height += hop_height * sin(t * PI)
			tuck += 0.5 * sin(t * PI)
			return t < 1.0
		_:
			var t := clampf(clock / maxf(throes_seconds, 0.01), 0.0, 1.0)
			# Cada vez más débil, hasta quedarse quieta.
			var fade := (1.0 - t) * (1.0 - t)
			var twitch := throes_degrees * fade
			claw_left += twitch * sin(clock * 23.0)
			claw_right += twitch * sin(clock * 19.0 + 1.3)
			raise_left += twitch * 0.6 * sin(clock * 15.0)
			raise_right += twitch * 0.6 * sin(clock * 17.0 + 0.7)
			tail_curl += twitch * 0.5 * sin(clock * 12.0)
			return t < 1.0
