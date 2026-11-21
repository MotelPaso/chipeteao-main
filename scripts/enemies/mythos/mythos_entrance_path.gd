class_name MythosEntrancePath
extends RefCounted
## El recorrido del fénix en su cinemática de llegada: dónde va el modelo y
## cómo se orienta según avanza la calma, hasta que golpea el suelo. Los
## valores son exports del nodo Entrance (MythosEntrance, grupos «Cometa»,
## «Anillo de fuego» y «Ascenso y picada»); aquí solo está la geometría.
## Cuatro tramos seguidos alrededor del punto donde aterriza:
##   COMETA   baja del cielo en línea recta hasta quedar rasante, justo en
##            el borde del anillo
##   ANILLO   da la vuelta al punto de llegada, ladeado hacia adentro
##   ASCENSO  cierra el giro mientras sube, hasta quedar quieto en lo alto
##   PICADA   se queda un instante arriba y cae a plomo
## Es una función del avance y nada más: pausar la cinemática o saltarla no
## la desordena.

## Avance (0-1) a cada lado con que se mide hacia dónde vuela.
const HEADING_STEP: float = 0.002
## Avance (0-1) a cada lado con que se mide cuánto gira: es más ancho para
## que el ladeo entre y salga de a poco.
const TURN_STEP: float = 0.012


## Una muestra del recorrido: dónde va el modelo (en el mundo), hacia dónde
## mira (radianes, en el mundo) y su inclinación y su ladeo (grados).
class Sample:
	extends RefCounted
	var point: Vector3 = Vector3.ZERO
	var yaw: float = 0.0
	var pitch: float = 0.0
	var roll: float = 0.0


var _values: MythosEntrance = null
var _center: Vector3 = Vector3.ZERO
## Hacia la cámara y hacia su derecha, a ras de suelo.
var _toward: Vector3 = Vector3.BACK
var _right: Vector3 = Vector3.RIGHT
var _radius: float = 30.0
var _seconds: float = 8.0
## Altura sobre el punto de llegada a la que queda al golpear el suelo.
var _landing_height: float = 2.0


## Fija el recorrido: aterriza en `center`, la cámara está hacia `toward`, el
## anillo tiene `radius` metros y la calma dura `calm_seconds`.
func setup(values: MythosEntrance, center: Vector3, toward: Vector3, radius: float,
		calm_seconds: float, landing_height: float) -> void:
	_values = values
	_center = center
	_toward = Vector3(toward.x, 0.0, toward.z).normalized()
	_right = Vector3.UP.cross(_toward).normalized()
	_radius = radius
	_seconds = maxf(calm_seconds, 0.01)
	_landing_height = landing_height


## Dónde va el modelo con la calma en `progress` (0-1), en el mundo.
func point_at(progress: float) -> Vector3:
	var v := _values
	if progress < v.comet_until:
		return _comet(progress / maxf(v.comet_until, 0.001))
	if progress < v.ring_until:
		return _on_ring(_ring_turn(progress), _radius, v.low_height)
	if progress < v.apex_fraction:
		return _climb(_span(progress, v.ring_until, v.apex_fraction))
	# Arriba se queda quieto hasta plunge_fraction; después cae cada vez más rápido.
	var fall := _span(progress, v.plunge_fraction, v.impact_fraction)
	return _center + Vector3.UP * lerpf(v.apex_height, _landing_height, fall * fall)


## Punto, rumbo, inclinación y ladeo con la calma en `progress` (0-1).
func sample(progress: float) -> Sample:
	var v := _values
	var p := clampf(progress, 0.0, v.impact_fraction)
	var out := Sample.new()
	out.point = point_at(p)
	var facing := atan2(-_toward.x, -_toward.z)
	var travel := _travel(p, HEADING_STEP)
	var flat := Vector2(travel.x, travel.z).length()
	out.yaw = atan2(-travel.x, -travel.z) if flat > 0.0001 else facing
	out.pitch = rad_to_deg(atan2(travel.y, flat)) if travel.length() > 0.0001 else 0.0
	out.roll = _bank(p)
	# Al final del ascenso deja de seguir su rumbo: queda erguido y de frente
	# a la cámara, con las alas abiertas.
	var settle := smoothstep(v.settle_from, 1.0, _span(p, v.ring_until, v.apex_fraction))
	out.yaw = lerp_angle(out.yaw, facing, settle)
	out.pitch = lerpf(out.pitch, v.apex_pitch_degrees, settle)
	out.roll *= 1.0 - settle
	# Y al empezar la picada se clava de pico.
	var tip := smoothstep(0.0, v.tip_over, _span(p, v.plunge_fraction, v.impact_fraction))
	out.pitch = lerpf(out.pitch, v.plunge_pitch_degrees, tip)
	return out


# --- tramos -----------------------------------------------------------------------

## Baja en línea recta hacia el punto del anillo por donde entra. `u` es el
## avance del tramo (0-1).
func _comet(u: float) -> Vector3:
	var v := _values
	# Metros de anillo que recorrería en lo que dura este tramo: con eso llega
	# al anillo a la misma velocidad con que después lo recorre.
	var ring_pace := _radius * TAU * v.ring_laps * v.comet_until \
			/ maxf(v.ring_until - v.comet_until, 0.001)
	var distance := maxf(v.comet_distance, ring_pace * 0.5)
	var left := 1.0 - u
	var back := ring_pace * left + (distance - ring_pace) * left * left
	var height := lerpf(v.low_height, v.comet_height, pow(left, v.comet_drop_curve))
	return _on_ring(0.0, _radius, height) - _toward * back


## Sube cerrando el giro: entra girando igual que en el anillo y termina
## quieto sobre el punto de llegada. `w` es el avance del tramo (0-1).
func _climb(w: float) -> Vector3:
	var v := _values
	var ring_rate := TAU * v.ring_laps * (v.apex_fraction - v.ring_until) \
			/ maxf(v.ring_until - v.comet_until, 0.001)
	var total := maxf(TAU * v.climb_turns, ring_rate * 0.5)
	var turn := TAU * v.ring_laps + ring_rate * w + (total - ring_rate) * w * w
	var rise := smoothstep(0.0, 1.0, w)
	return _on_ring(turn, _radius * (1.0 - rise), lerpf(v.low_height, v.apex_height, rise))


## Radianes de anillo ya recorridos (0 = el punto por donde entra).
func _ring_turn(progress: float) -> float:
	return TAU * _values.ring_laps * _span(progress, _values.comet_until, _values.ring_until)


## El punto a `radius` metros del centro tras girar `turn` radianes desde
## donde entra el fénix, a `height` metros sobre el punto de llegada.
func _on_ring(turn: float, radius: float, height: float) -> Vector3:
	return _center + (_toward * sin(turn) - _right * cos(turn)) * radius + Vector3.UP * height


# --- orientación ------------------------------------------------------------------

## Lo que avanza entre `step` antes y `step` después de `progress`.
func _travel(progress: float, step: float) -> Vector3:
	return point_at(minf(progress + step, _values.impact_fraction)) \
			- point_at(maxf(progress - step, 0.0))


## Rumbo a ras de suelo en `progress`, en radianes (el de la cámara si sube o
## baja a plomo).
func _heading(progress: float) -> float:
	var travel := _travel(progress, HEADING_STEP)
	if Vector2(travel.x, travel.z).length() < 0.0001:
		return atan2(-_toward.x, -_toward.z)
	return atan2(-travel.x, -travel.z)


## Ladeo por estar girando, en grados: cuanto más rápido gira, más se ladea
## hacia adentro.
func _bank(progress: float) -> float:
	var v := _values
	var from := maxf(progress - TURN_STEP, 0.0)
	var to := minf(progress + TURN_STEP, v.impact_fraction)
	if to - from < 0.0001:
		return 0.0
	var turn_rate := angle_difference(_heading(from), _heading(to)) / ((to - from) * _seconds)
	return clampf(turn_rate * v.bank_per_turn_rate, -v.bank_max_degrees, v.bank_max_degrees)


func _span(value: float, from: float, to: float) -> float:
	return clampf((value - from) / maxf(to - from, 0.0001), 0.0, 1.0)
