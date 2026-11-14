class_name MythosFlight
extends Node
## Cómo se mueve Mythos (nodo Flight de Mythos.tscn). Tiene dos posturas:
##   EN VUELO   gira alrededor del raider a air_distance. Si el raider se le
##              acerca retrocede despacio: corriendo se lo alcanza.
##   EN TIERRA  (tras una Picada) camina hacia el raider, al alcance de las
##              armas cortas, hasta que se le acaba el tiempo y despega. Si
##              el raider se le va lejos, despega antes.
## También elige a qué raider persigue. Mythos le pide la dirección en cada
## frame (intent); los ataques lo posan y lo hacen despegar a través de
## Mythos.land() y Mythos.take_off().

@export_group("En vuelo")
## Distancia al raider, en metros, a la que gira mientras vuela.
@export var air_distance: float = 9.0
## Margen en metros alrededor de air_distance dentro del cual solo gira.
@export var air_band: float = 1.5
## Fracción de su velocidad a la que gira alrededor del raider (0-1).
@export_range(0.0, 1.0) var orbit_speed_factor: float = 0.4
## Fracción de su velocidad a la que retrocede si el raider se le acerca (0-1). Bajo = corriendo se lo alcanza.
@export_range(0.0, 1.0) var retreat_speed_factor: float = 0.2
## Segundos entre un cambio de sentido del giro y el siguiente.
@export var orbit_flip_seconds: float = 6.0

@export_group("En tierra")
## Distancia al raider, en metros, a la que se detiene cuando camina hacia él (las armas cortas llegan).
@export var ground_distance: float = 2.3
## Fracción de su velocidad a la que camina en tierra (0-1). Más lento que un raider: se le puede huir.
@export_range(0.0, 1.0) var ground_speed_factor: float = 0.36
## Segundos que pasa en tierra tras una Picada antes de despegar, con agresividad 0.
@export var ground_seconds: float = 7.0
## Multiplicador de ese tiempo con agresividad 1.
@export var ground_seconds_at_full_aggression: float = 0.75
## Distancia al raider, en metros, desde la que deja de seguirlo a pie y despega antes de tiempo.
@export var ground_leash: float = 13.0
## Segundos que el raider tiene que pasar así de lejos para que despegue.
@export var ground_leash_seconds: float = 1.2

@export_group("Objetivo")
## Segundos que persigue al mismo raider antes de elegir otro al azar.
@export var focus_seconds: float = 8.0

var _grounded: bool = false
var _ground_left: float = 0.0
## Metros al raider en el último frame en que se movió, y segundos seguidos
## que lleva más lejos que ground_leash estando en tierra.
var _distance: float = 0.0
var _far_seconds: float = 0.0
var _orbit_sign: float = 1.0
var _flip_left: float = 0.0
var _focus: Node3D = null
var _focus_left: float = 0.0


## Un frame de pelea: corren el tiempo en tierra, el giro y el foco.
func tick(delta: float) -> void:
	_focus_left -= delta
	if _grounded:
		_ground_left -= delta
		_far_seconds = _far_seconds + delta if _distance > ground_leash else 0.0
		return
	_flip_left -= delta
	if _flip_left <= 0.0:
		_flip_left = orbit_flip_seconds
		_orbit_sign = 1.0 if randf() < 0.5 else -1.0


func is_grounded() -> bool:
	return _grounded


## True cuando le toca despegar: ya pasó su tiempo en tierra, o el raider
## se le alejó demasiado para seguirlo a pie.
func wants_takeoff() -> bool:
	return _grounded and (_ground_left <= 0.0 or _far_seconds >= ground_leash_seconds)


## Queda posado en tierra; `aggression` (0-1) acorta cuánto se queda.
func land(aggression: float) -> void:
	_grounded = true
	_ground_left = ground_seconds * lerpf(1.0, ground_seconds_at_full_aggression, aggression)
	_distance = 0.0
	_far_seconds = 0.0


func take_off() -> void:
	_grounded = false
	_flip_left = 0.0


## Hacia dónde quiere moverse: `seek` es la dirección al raider y `distance`
## los metros hasta él. El largo del resultado es la fracción de su velocidad.
func intent(seek: Vector3, distance: float) -> Vector3:
	_distance = distance
	if _grounded:
		return seek * ground_speed_factor if distance > ground_distance else Vector3.ZERO
	var tangent := Vector3(-seek.z, 0.0, seek.x) * _orbit_sign
	if distance > air_distance + air_band:
		return (seek + tangent * 0.5).normalized()
	if distance < air_distance - air_band:
		return tangent * orbit_speed_factor - seek * retreat_speed_factor
	return tangent * orbit_speed_factor


## Persigue a un raider por un rato y después elige otro al azar, así en
## co-op la presión no cae siempre sobre el mismo.
func pick_target(tree: SceneTree) -> Node3D:
	if _focus_left <= 0.0 or not is_instance_valid(_focus) \
			or not _focus.is_in_group(&"player"):
		_focus = Coop.random_player(tree)
		_focus_left = focus_seconds
	return _focus
