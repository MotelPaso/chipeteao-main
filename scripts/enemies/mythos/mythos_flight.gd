class_name MythosFlight
extends Node
## Cómo se mueve Mythos (nodo Flight de Mythos.tscn). Tiene dos posturas:
##   EN VUELO   no se queda quieto: gira rápido alrededor del raider, se le
##              viene encima y se aleja (el radio del giro «respira») y sube
##              y baja. Sigue girando mientras lanza los ataques que lo
##              permiten (MythosMove.flight_factor). Si el raider se le
##              acerca retrocede despacio: corriendo se lo alcanza.
##              Si el raider se le va lejos (un portal, una carrera larga) no
##              lo sigue por el suelo: cruza la arena VOLANDO derecho hacia
##              él, por encima de rocas y árboles, hasta alcanzarlo.
##              En su forma renacida además da FOGONAZOS: cruza la arena de
##              un tirón, envuelto en llamas, y aparece al otro lado.
##   EN TIERRA  (tras una Picada) camina hacia el raider, al alcance de las
##              armas cortas, hasta que se le acaba el tiempo y despega. Si
##              el raider se le va lejos, despega antes.
## También elige a qué raider persigue y con qué pose se mueve (pose): cuando
## deja de girar para acortar la distancia va de CAZA, y en tierra lo ACECHA
## caminando a embestidas. Mythos le pide la dirección en cada frame
## (intent); los ataques lo posan y lo hacen despegar a través de
## Mythos.land() y Mythos.take_off().

@export_group("En vuelo")
## Distancia media al raider, en metros, a la que gira mientras vuela.
@export var air_distance: float = 10.0
## Margen en metros alrededor de esa distancia dentro del cual solo gira.
@export var air_band: float = 1.5
## Fracción de su velocidad a la que gira alrededor del raider (0-1).
@export_range(0.0, 1.0) var orbit_speed_factor: float = 0.7
## Fracción de su velocidad a la que retrocede si el raider se le acerca (0-1). Bajo = corriendo se lo alcanza.
@export_range(0.0, 1.0) var retreat_speed_factor: float = 0.2
## Segundos entre un cambio de sentido del giro y el siguiente.
@export var orbit_flip_seconds: float = 4.5
## Metros que el giro se agranda y se achica: cuando se achica se le viene encima al raider.
@export var breath_metres: float = 3.0
## Segundos de un vaivén completo de esa distancia.
@export var breath_seconds: float = 5.0
## Metros que sube y baja mientras gira.
@export var lift_metres: float = 1.3
## Segundos de una subida y bajada completa.
@export var lift_seconds: float = 3.1

@export_group("Caza")
## Chillido cuando deja de girar y se le viene encima al raider (fila de Sfx.SOUND_LIBRARY; vacío = ninguno).
@export var hunt_sfx: StringName = &"phoenix_screech"
## Segundos mínimos entre un chillido de caza y el siguiente.
@export var hunt_sfx_cooldown: float = 6.0

@export_group("Persecución")
## Distancia al raider, en metros, desde la que deja de girar y vuela derecho hacia él por encima de todo.
@export var chase_from: float = 26.0
## Distancia al raider, en metros, a la que termina ese vuelo y vuelve a girar.
@export var chase_until: float = 12.0
## Metros por segundo de ese vuelo.
@export var chase_speed: float = 26.0
## Metros que sube mientras persigue.
@export var chase_lift: float = 4.0
## Segundos que persigue de un tirón como mucho: si no lo alcanza (el raider quedó fuera de su arena), deja de intentarlo un rato.
@export var chase_max_seconds: float = 4.0
## Segundos que espera antes de volver a perseguir tras rendirse.
@export var chase_rest_seconds: float = 3.0

@export_group("Fogonazo")
## Segundos entre un fogonazo y el siguiente en su forma renacida, con agresividad 0 (0 = nunca).
@export var blink_every: float = 7.5
## Multiplicador de esa espera con agresividad 1.
@export var blink_every_at_full_aggression: float = 0.6
## Grados mínimos alrededor del raider que cruza con cada fogonazo.
@export var blink_min_degrees: float = 100.0
## Grados máximos (por debajo de 180 no pasa por encima del raider).
@export var blink_max_degrees: float = 150.0
## Segundos que tarda en cruzar.
@export var blink_seconds: float = 0.2
## Radio del estallido de luz con que reaparece, en unidades del modelo.
@export var blink_flash_radius: float = 4.0
## Sonido del fogonazo (fila de Sfx.SOUND_LIBRARY).
@export var blink_sfx: StringName = &"fire_blink"

@export_group("En tierra")
## Distancia al raider, en metros, a la que se detiene cuando camina hacia él (las armas cortas llegan).
@export var ground_distance: float = 2.3
## Fracción de su velocidad a la que camina en tierra (0-1). Más lento que un raider: se le puede huir.
@export_range(0.0, 1.0) var ground_speed_factor: float = 0.32
## Segundos que pasa en tierra tras una Picada antes de despegar, con agresividad 0.
@export var ground_seconds: float = 7.0
## Multiplicador de ese tiempo con agresividad 1.
@export var ground_seconds_at_full_aggression: float = 0.75
## Distancia al raider, en metros, desde la que deja de seguirlo a pie y despega antes de tiempo.
@export var ground_leash: float = 13.0
## Segundos que el raider tiene que pasar así de lejos para que despegue.
@export var ground_leash_seconds: float = 1.2
## Segundos de cada zancada: en tierra no camina parejo, avanza a embestidas.
@export var stride_seconds: float = 0.85
## Fracción de su paso (0-1) a la que baja entre una zancada y la siguiente.
@export_range(0.0, 1.0) var stride_rest: float = 0.65

@export_group("Objetivo")
## Segundos que persigue al mismo raider antes de elegir otro al azar.
@export var focus_seconds: float = 8.0

## True en su forma renacida (lo pone Mythos al renacer): da fogonazos.
var reborn: bool = false

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
## Segundos de vuelo: mueven el vaivén del radio y de la altura.
var _clock: float = 0.0
## Fogonazo: segundos hasta el próximo, segundos que le quedan al que está
## dando (0 = ninguno) y de dónde a dónde cruza.
var _blink_wait: float = 0.0
var _blink_left: float = 0.0
var _blink_from: Vector3 = Vector3.ZERO
var _blink_to: Vector3 = Vector3.ZERO
## True mientras se le viene encima al raider (dejó de girar para acortar la
## distancia), y segundos hasta que puede volver a chillar al hacerlo.
var _closing: bool = false
var _hunt_sfx_left: float = 0.0
## True mientras cruza la arena persiguiendo a un raider que se alejó, los
## segundos que le quedan a esa persecución y los que faltan para otra.
var _chasing: bool = false
var _chase_left: float = 0.0
var _chase_wait: float = 0.0

@onready var _body: MythosBody = get_parent() as MythosBody


## Un frame de pelea: corren el tiempo en tierra, el giro, el foco, la
## persecución y los fogonazos. Con `busy` Mythos está en medio de un
## ataque: sigue girando si el ataque lo deja, pero no empieza a perseguir ni
## da un fogonazo.
func tick(delta: float, busy: bool) -> void:
	_focus_left -= delta
	_clock += delta
	_hunt_sfx_left = maxf(_hunt_sfx_left - delta, 0.0)
	if not busy and _body != null and _body.rig != null:
		# Entre ataques el rig lleva la pose de cómo se está moviendo.
		_body.rig.set_pose(pose())
	if _grounded:
		_ground_left -= delta
		_far_seconds = _far_seconds + delta if _distance > ground_leash else 0.0
		_set_lift(0.0, delta)
		return
	_set_lift(chase_lift if _chasing
			else lift_metres * sin(_clock * TAU / maxf(lift_seconds, 0.1)), delta)
	_flip_left -= delta
	if _flip_left <= 0.0:
		_flip_left = orbit_flip_seconds
		_orbit_sign = 1.0 if randf() < 0.5 else -1.0
	_chase_wait = maxf(_chase_wait - delta, 0.0)
	if _blink_left > 0.0:
		_tick_blink(delta)
	elif _chasing or (not busy and _chase_wait <= 0.0 and _distance > chase_from):
		_tick_chase(delta)
	elif reborn and blink_every > 0.0 and not busy:
		_blink_wait -= delta
		if _blink_wait <= 0.0:
			_begin_blink()


func is_grounded() -> bool:
	return _grounded


## La pose de cómo se está moviendo ahora: posado o acechando a pie en
## tierra; en vuelo, de caza si se le viene encima al raider o lo persigue.
func pose() -> MythosRig.Pose:
	if _grounded:
		return MythosRig.Pose.PROWL if _distance > ground_distance else MythosRig.Pose.PERCH
	return MythosRig.Pose.HUNT if _closing or _chasing else MythosRig.Pose.FLY


## True cuando le toca despegar: ya pasó su tiempo en tierra, o el raider
## se le alejó demasiado para seguirlo a pie.
func wants_takeoff() -> bool:
	return _grounded and (_ground_left <= 0.0 or _far_seconds >= ground_leash_seconds)


## True mientras cruza la arena en un fogonazo o persiguiendo a un raider
## lejano (Mythos no ataca hasta que llega).
func is_crossing() -> bool:
	return _blink_left > 0.0 or _chasing


## Queda posado en tierra; `aggression` (0-1) acorta cuánto se queda.
func land(aggression: float) -> void:
	_grounded = true
	_ground_left = ground_seconds * lerpf(1.0, ground_seconds_at_full_aggression, aggression)
	_distance = 0.0
	_far_seconds = 0.0
	_blink_left = 0.0
	_chasing = false
	_closing = false


func take_off() -> void:
	_grounded = false
	_flip_left = 0.0
	_blink_left = 0.0
	_chasing = false
	_blink_wait = _next_blink_wait()


## Hacia dónde quiere moverse: `seek` es la dirección al raider y `distance`
## los metros hasta él. El largo del resultado es la fracción de su velocidad.
func intent(seek: Vector3, distance: float) -> Vector3:
	_distance = distance
	if _grounded:
		if distance <= ground_distance:
			return Vector3.ZERO
		# A zancadas: embiste, afloja y vuelve a embestir.
		var surge := 0.5 + 0.5 * sin(_clock * TAU / maxf(stride_seconds, 0.1))
		return seek * ground_speed_factor * lerpf(stride_rest, 1.0 + (1.0 - stride_rest), surge)
	if _blink_left > 0.0 or _chasing:
		return Vector3.ZERO
	var radius := air_distance \
			+ breath_metres * sin(_clock * TAU / maxf(breath_seconds, 0.1))
	var tangent := Vector3(-seek.z, 0.0, seek.x) * _orbit_sign
	if distance > radius + air_band:
		# Lejos: se le viene encima a toda velocidad, entrando en espiral.
		_set_closing(true)
		return (seek + tangent * 0.5).normalized()
	_set_closing(false)
	if distance < radius - air_band:
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


# --- privados ---------------------------------------------------------------------

## La altura extra del vuelo llega de a poco al rig, sin saltos al posarse.
func _set_lift(wanted: float, delta: float) -> void:
	if _body == null or _body.rig == null:
		return
	_body.rig.flight_lift = lerpf(_body.rig.flight_lift, wanted, Juice.damp(4.0, delta))


## Un frame de persecución: vuela derecho hacia el raider, sin chocar con
## nada, y al llegar se acomoda en un lugar donde cabe.
func _tick_chase(delta: float) -> void:
	var gap := 0.0
	var to := Vector3.ZERO
	if _body != null and is_instance_valid(_focus) and _focus.is_inside_tree():
		to = _focus.global_position - _body.global_position
		to.y = 0.0
		gap = to.length()
	if gap <= chase_until:
		_end_chase(0.0)
		return
	if not _chasing:
		_chasing = true
		_chase_left = chase_max_seconds
		_body.rig.set_trail(true)
		_body.rig.set_pose(MythosRig.Pose.HUNT)
		_hunt_cry()
	_chase_left -= delta
	if _chase_left <= 0.0:
		_end_chase(chase_rest_seconds)
		return
	var step := minf(chase_speed * delta, gap - chase_until)
	var next := _body.global_position + to / gap * step
	_body.glide_to(_body.safe_point(next) if gap - step <= chase_until + 0.01 else next)
	_distance = gap - step


## Deja de perseguir y no vuelve a intentarlo hasta dentro de `rest` segundos.
func _end_chase(rest: float) -> void:
	_chase_wait = rest
	if not _chasing:
		return
	_chasing = false
	_body.rig.set_trail(false)
	_body.rig.set_pose(pose())


## Empieza o deja de venírsele encima al raider: al empezar deja una estela
## de fuego y, si hace rato que no lo hacía, chilla.
func _set_closing(on: bool) -> void:
	if _closing == on:
		return
	_closing = on
	if _body == null or _body.rig == null:
		return
	_body.rig.set_trail(on)
	if on:
		_hunt_cry()


func _hunt_cry() -> void:
	if _hunt_sfx_left > 0.0:
		return
	_hunt_sfx_left = hunt_sfx_cooldown
	_body.rig.gesture(&"screech")
	if hunt_sfx != &"":
		Sfx.play(hunt_sfx)


func _next_blink_wait() -> float:
	var aggression := _body.aggression if _body != null else 0.0
	return blink_every * lerpf(1.0, blink_every_at_full_aggression, aggression) \
			* randf_range(0.8, 1.2)


## Arranca un fogonazo: elige un punto al otro lado del raider, a la misma
## distancia, y sale disparado hacia ahí envuelto en llamas.
func _begin_blink() -> void:
	_blink_wait = _next_blink_wait()
	if _body == null or not is_instance_valid(_focus) or not _focus.is_inside_tree():
		return
	var center := _focus.global_position
	var arm := _body.global_position - center
	arm.y = 0.0
	if arm.length_squared() < 1.0:
		return
	var turn := deg_to_rad(randf_range(blink_min_degrees, blink_max_degrees)) \
			* (1.0 if randf() < 0.5 else -1.0)
	_blink_from = _body.global_position
	_blink_to = _body.safe_point(center + arm.rotated(Vector3.UP, turn))
	_blink_left = maxf(blink_seconds, 0.01)
	_body.rig.burst()
	_body.rig.set_trail(true)
	Sfx.play(blink_sfx)


func _tick_blink(delta: float) -> void:
	_blink_left = maxf(_blink_left - delta, 0.0)
	var t := 1.0 - _blink_left / maxf(blink_seconds, 0.01)
	_body.glide_to(_blink_from.lerp(_blink_to, t))
	if _blink_left > 0.0:
		return
	_body.rig.set_trail(false)
	_body.rig.burst()
	_body.rig.pop_nova(blink_flash_radius, 0.35)
