class_name MythosVolley
extends MythosMove
## Plumas ardientes: tras una carga corta con las alas en alto, varias tandas
## de plumas de fuego (EnemyBolt del pool) en abanico. Apunta adonde el raider
## VA a estar, y cada tanda sale corrida medio paso, sobre los huecos de la
## anterior: quedarse quieto en un hueco no sirve. Con agresividad salen más
## plumas y más tandas.

@export_group("Plumas")
## Escena de la pluma (un EnemyBolt; sale de Pools). Su velocidad y alcance están en esa escena.
@export var bolt_scene: PackedScene = preload("res://scenes/enemies/FireFeather.tscn")
## Segundos de carga antes de la primera tanda.
@export var windup: float = 0.55
## Plumas por tanda con agresividad 0.
@export var bolt_count: int = 7
## Plumas extra por tanda con agresividad 1.
@export var extra_bolts_at_full_aggression: int = 4
## Ancho total del abanico, en grados.
@export var spread_degrees: float = 58.0
## Daño de cada pluma (valor base; el grado y el poder de la party lo escalan).
@export var bolt_damage: float = 16.0
## Tandas con agresividad 0.
@export var waves: int = 2
## Tandas extra con agresividad 1.
@export var extra_waves_at_full_aggression: int = 2
## Segundos entre una tanda y la siguiente.
@export var wave_delay: float = 0.38
## Cuánto se adelanta al raider (0 = le apunta donde está, 1 = donde va a estar cuando llegue la pluma).
@export_range(0.0, 1.0) var lead: float = 0.85
## Tope de ese adelanto, en metros, para un raider a velocidad base (crece si corre más rápido).
@export var max_lead: float = 7.0
## Segundos quieto después de la última tanda.
@export var recover: float = 0.4
## Altura en metros sobre los pies del raider a la que apuntan las plumas.
@export var target_height: float = 0.9
## Sonido de cada tanda (fila de Sfx.SOUND_LIBRARY).
@export var launch_sfx: StringName = &"fire_feathers"

var _target: Node3D = null
var _timer: float = 0.0
var _waves_left: int = 0
var _wave_index: int = 0
var _recovering: bool = false


func scale_damage(multiplier: float) -> void:
	bolt_damage *= multiplier


func begin(target: Node3D) -> void:
	_target = target
	_timer = windup
	_waves_left = maxi(aggression_count(waves, extra_waves_at_full_aggression), 1)
	_wave_index = 0
	_recovering = false
	boss.rig.set_pose(MythosRig.Pose.WINDUP)


func tick(delta: float) -> bool:
	_timer -= delta
	if _timer > 0.0:
		return false
	if _recovering:
		return true
	_launch()
	# Cada oleada sale de un ala distinta.
	boss.rig.gesture(&"swipe_left" if _wave_index % 2 == 0 else &"swipe_right")
	_waves_left -= 1
	_wave_index += 1
	if _waves_left > 0:
		_timer = wave_delay
		return false
	_recovering = true
	_timer = recover
	boss.rig.set_pose(boss.rest_pose())
	return false


func cancel() -> void:
	boss.rig.set_pose(boss.rest_pose())


## Una tanda: el abanico entero, corrido medio paso en las tandas impares.
func _launch() -> void:
	var count := maxi(aggression_count(bolt_count, extra_bolts_at_full_aggression), 1)
	var shift := 0.5 if _wave_index % 2 == 1 else 0.0
	MythosBolts.fan(boss, bolt_scene, boss.muzzle_point(), _target, count,
			deg_to_rad(spread_degrees), bolt_damage, shift, lead, max_lead, target_height)
	Sfx.play(launch_sfx)
