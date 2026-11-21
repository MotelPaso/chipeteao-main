class_name MythosStorm
extends MythosMove
## Tormenta de plumas (segunda fase): gira sobre sí mismo y suelta plumas de
## fuego en varios brazos que van rotando, como un aspersor. Los brazos
## dibujan espirales que se abren: cerca de él no hay por dónde pasar, lejos
## los huecos entre pluma y pluma se agrandan. Se esquiva tomando distancia y
## pasando por los huecos, o saltando el brazo que viene. Con agresividad
## salen más brazos.

@export_group("Tormenta")
## Escena de la pluma (un EnemyBolt; sale de Pools). Su velocidad y alcance están en esa escena.
@export var bolt_scene: PackedScene = preload("res://scenes/enemies/FireFeather.tscn")
## Segundos de carga antes de la primera pluma.
@export var windup: float = 0.8
## Brazos de la espiral con agresividad 0.
@export var arms: int = 3
## Brazos extra con agresividad 1.
@export var extra_arms_at_full_aggression: int = 2
## Segundos que dura la tormenta.
@export var seconds: float = 3.4
## Segundos entre una pluma y la siguiente de cada brazo.
@export var step_seconds: float = 0.1
## Grados que giran los brazos entre una pluma y la siguiente.
@export var turn_degrees: float = 12.0
## Daño de cada pluma (valor base).
@export var bolt_damage: float = 12.0
## Altura en metros sobre el suelo a la que vuelan las plumas (baja: se pueden saltar).
@export var bolt_height: float = 1.0
## Segundos quieto después de la última pluma.
@export var recover: float = 0.8
## Sonido de la tormenta, cada tanto (fila de Sfx.SOUND_LIBRARY).
@export var launch_sfx: StringName = &"fire_feathers"
## Cada cuántas plumas suena.
@export var sfx_every: int = 5

var _timer: float = 0.0
var _left: float = 0.0
var _step_left: float = 0.0
var _angle: float = 0.0
## Hacia qué lado giran los brazos (1 o -1): cambia en cada tormenta.
var _turn: float = 1.0
var _shots: int = 0
var _recovering: bool = false


func scale_damage(multiplier: float) -> void:
	bolt_damage *= multiplier


func begin(_target: Node3D) -> void:
	_timer = windup
	_left = seconds
	_step_left = 0.0
	_angle = randf() * TAU
	_turn = -_turn
	_shots = 0
	_recovering = false
	boss.rig.set_pose(MythosRig.Pose.CAST)
	boss.rig.gesture(&"spin")


func tick(delta: float) -> bool:
	_timer -= delta
	if _timer > 0.0:
		return false
	if _recovering:
		return true
	_left -= delta
	_step_left -= delta
	while _step_left <= 0.0:
		_step_left += maxf(step_seconds, 0.02)
		_volley()
	if _left <= 0.0:
		_recovering = true
		_timer = recover
		boss.rig.set_pose(boss.rest_pose())
	return false


func cancel() -> void:
	boss.rig.set_pose(boss.rest_pose())


## Una pluma por brazo, y los brazos giran un paso.
func _volley() -> void:
	var count := maxi(aggression_count(arms, extra_arms_at_full_aggression), 1)
	var origin := boss.global_position + Vector3.UP * bolt_height
	for index: int in count:
		var angle := _angle + TAU * float(index) / float(count)
		MythosBolts.shot(boss, bolt_scene, origin, Vector3(cos(angle), 0.0, sin(angle)),
				bolt_damage)
	_angle += deg_to_rad(turn_degrees) * _turn
	_shots += 1
	if _shots % maxi(sfx_every, 1) == 1:
		# Sigue girando sobre sí mismo mientras dura.
		boss.rig.gesture(&"spin")
		Sfx.play(launch_sfx)
