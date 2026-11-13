class_name MythosRig
extends Node3D
## Rig del fénix (nodo Visual de Mythos.tscn). El CUERPO físico de Mythos va
## por el suelo; lo que vuela es este rig: el nodo Hover sube, baja y se
## inclina, y las alas (WingL, WingR) y la cola (Tail) se animan aquí.
## Mythos y sus ataques solo piden una pose con set_pose().
## Solo mueve Hover y lo que cuelga de él: Visual (este nodo) queda libre
## para los tweens de BossBase y la caída al morir.

enum Pose { FLY, WINDUP, DIVE, PERCH, CAST, ASHES }

@export_group("Vuelo")
## Tamaño del fénix (1 = como está armado en la escena).
@export var body_scale: float = 1.3
## Altura en metros del cuerpo del fénix sobre el suelo, en vuelo normal.
@export var hover_height: float = 2.6
## Altura en metros mientras está posado tras una picada.
@export var perch_height: float = 1.4
## Metros que sube al cargar un ataque.
@export var windup_rise: float = 0.9
## Amplitud del vaivén vertical, en metros.
@export var bob_amplitude: float = 0.2
## Segundos de un vaivén completo.
@export var bob_period: float = 1.7
## Rapidez con que pasa de una pose a otra (por segundo).
@export var pose_speed: float = 7.0

@export_group("Alas")
## Segundos de un aleteo completo en vuelo normal.
@export var flap_period: float = 0.55
## Amplitud del aleteo en vuelo normal, en grados.
@export var flap_degrees: float = 34.0
## Ángulo de las alas levantadas al cargar un ataque, en grados.
@export var raised_degrees: float = 52.0
## Ángulo hacia atrás de las alas recogidas en la picada, en grados.
@export var swept_degrees: float = 58.0
## Amplitud del aleteo lento mientras está posado, en grados.
@export var perch_flap_degrees: float = 14.0

@export_group("Cuerpo")
## Inclinación del cuerpo en la picada, en grados (negativo = pico hacia abajo).
@export var dive_pitch_degrees: float = -48.0
## Vaivén de la cola hacia los lados, en grados.
@export var tail_sway_degrees: float = 14.0

@export_group("Cenizas")
## Escala a la que se encoge el fénix cuando cae en cenizas.
@export var ashes_scale: float = 0.22
## Altura en metros de la brasa sobre el montón de cenizas.
@export var ashes_height: float = 0.55
## Segundos de un latido de la brasa.
@export var ashes_pulse_period: float = 0.9

@export_group("Llegada")
## Altura en metros desde la que baja al llegar.
@export var arrival_height: float = 34.0

var _pose: Pose = Pose.FLY
var _time: float = 0.0
var _height: float = 0.0
var _wing_base: float = 0.0
var _wing_sweep: float = 0.0
var _pitch: float = 0.0
var _scale: float = 1.0
## Avance de la llegada (0 = en lo alto, 1 = en su altura de vuelo); -1 fuera de ella.
var _arrival: float = -1.0

@onready var _hover: Node3D = $Hover
@onready var _wing_left: Node3D = $Hover/WingL
@onready var _wing_right: Node3D = $Hover/WingR
@onready var _tail: Node3D = $Hover/Tail
@onready var _ash_mound: Node3D = $AshMound


func _ready() -> void:
	_height = hover_height
	_ash_mound.visible = false
	_apply(0.0)


func _process(delta: float) -> void:
	_time += delta
	_apply(delta)


## Cambia la pose; el rig llega a ella en unos frames.
func set_pose(pose: Pose) -> void:
	_pose = pose
	_ash_mound.visible = pose == Pose.ASHES


func pose() -> Pose:
	return _pose


## Avance de la llegada desde el cielo: 0 arriba, 1 en su altura de vuelo.
## Fuera de la llegada, end_arrival().
func set_arrival_progress(progress: float) -> void:
	_arrival = clampf(progress, 0.0, 1.0)


func end_arrival() -> void:
	_arrival = -1.0


## Altura en metros del cuerpo del fénix sobre los pies de Mythos, ahora.
func body_height() -> float:
	return _hover.position.y if _hover != null else hover_height


func _apply(delta: float) -> void:
	var blend := Juice.damp(pose_speed, delta) if delta > 0.0 else 1.0
	var want_height := hover_height
	var want_base := 0.0
	var want_sweep := 0.0
	var want_pitch := 0.0
	var want_scale := 1.0
	var flap := flap_degrees
	var period := flap_period
	match _pose:
		Pose.WINDUP:
			want_height = hover_height + windup_rise
			want_base = raised_degrees
			flap = flap_degrees * 0.25
		Pose.DIVE:
			want_height = perch_height
			want_sweep = swept_degrees
			want_pitch = dive_pitch_degrees
			flap = 0.0
		Pose.PERCH:
			want_height = perch_height
			flap = perch_flap_degrees
			period = flap_period * 2.2
		Pose.CAST:
			want_height = hover_height + windup_rise * 0.5
			want_base = raised_degrees * 0.45
			flap = flap_degrees * 0.3
		Pose.ASHES:
			want_height = ashes_height
			want_scale = ashes_scale
			want_sweep = swept_degrees
			flap = 0.0
	_height = lerpf(_height, want_height, blend)
	_wing_base = lerpf(_wing_base, want_base, blend)
	_wing_sweep = lerpf(_wing_sweep, want_sweep, blend)
	_pitch = lerpf(_pitch, want_pitch, blend)
	_scale = lerpf(_scale, want_scale, blend)
	var height := _height
	if _arrival >= 0.0:
		# Baja frenando: rápido en lo alto, suave al llegar a su altura.
		var ease_out := 1.0 - pow(1.0 - _arrival, 3.0)
		height = lerpf(arrival_height, _height, ease_out)
	var bob := sin(_time * TAU / maxf(bob_period, 0.01)) * bob_amplitude
	if _pose == Pose.ASHES:
		# La brasa late en su sitio en vez de mecerse.
		bob = 0.0
		var pulse := 1.0 + 0.18 * sin(_time * TAU / maxf(ashes_pulse_period, 0.01))
		_hover.scale = Vector3.ONE * _scale * body_scale * pulse
	else:
		_hover.scale = Vector3.ONE * _scale * body_scale
	_hover.position.y = height + bob
	_hover.rotation.x = deg_to_rad(_pitch)
	var wing := deg_to_rad(_wing_base
			+ sin(_time * TAU / maxf(period, 0.01)) * flap)
	var sweep := deg_to_rad(_wing_sweep)
	# Las alas son espejo: el mismo ángulo con signo contrario.
	_wing_left.rotation = Vector3(0.0, sweep, -wing)
	_wing_right.rotation = Vector3(0.0, -sweep, wing)
	_tail.rotation.y = deg_to_rad(sin(_time * TAU / 2.3) * tail_sway_degrees)
