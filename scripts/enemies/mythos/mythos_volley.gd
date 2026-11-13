class_name MythosVolley
extends MythosMove
## Plumas ardientes: tras una carga corta con las alas en alto, un abanico de
## plumas de fuego (EnemyBolt del pool) hacia el raider. Con agresividad
## salen más plumas y, pasado un umbral, una segunda tanda.

@export_group("Plumas")
## Escena de la pluma (un EnemyBolt; sale de Pools).
@export var bolt_scene: PackedScene = preload("res://scenes/enemies/FireFeather.tscn")
## Segundos de carga antes de soltar las plumas.
@export var windup: float = 0.6
## Plumas por tanda con agresividad 0.
@export var bolt_count: int = 5
## Plumas extra por tanda con agresividad 1.
@export var extra_bolts_at_full_aggression: int = 4
## Ancho total del abanico, en grados.
@export var spread_degrees: float = 46.0
## Daño de cada pluma (valor base; el grado y el poder de la party lo escalan).
@export var bolt_damage: float = 14.0
## Agresividad (0-1) desde la que sale una segunda tanda.
@export_range(0.0, 1.0) var second_wave_aggression: float = 0.55
## Segundos entre la primera tanda y la segunda.
@export var second_wave_delay: float = 0.4
## Segundos quieto después de la última tanda.
@export var recover: float = 0.45
## Altura en metros sobre los pies del raider a la que apuntan las plumas.
@export var target_height: float = 0.9
## Sonido de cada tanda (fila de Sfx.SOUND_LIBRARY).
@export var launch_sfx: StringName = &"fire_feathers"

var _target: Node3D = null
var _timer: float = 0.0
var _waves_left: int = 0
var _recovering: bool = false


func scale_damage(multiplier: float) -> void:
	bolt_damage *= multiplier


func begin(target: Node3D) -> void:
	_target = target
	_timer = windup
	_waves_left = 2 if boss.aggression >= second_wave_aggression else 1
	_recovering = false
	boss.rig.set_pose(MythosRig.Pose.WINDUP)


func tick(delta: float) -> bool:
	_timer -= delta
	if _timer > 0.0:
		return false
	if _recovering:
		return true
	_launch()
	_waves_left -= 1
	if _waves_left > 0:
		_timer = second_wave_delay
		return false
	_recovering = true
	_timer = recover
	boss.rig.set_pose(MythosRig.Pose.FLY)
	return false


## Una tanda: el abanico entero en el plano, con la inclinación que lleva la
## pluma central hasta el raider.
func _launch() -> void:
	if bolt_scene == null or not is_instance_valid(_target):
		return
	var origin := boss.muzzle_point()
	var aim := _target.global_position + Vector3.UP * target_height
	var flat := aim - origin
	var drop := flat.y
	flat.y = 0.0
	var reach := flat.length()
	if reach < 0.1:
		return
	var base_angle := atan2(flat.z, flat.x)
	var spread := deg_to_rad(spread_degrees)
	var count := maxi(aggression_count(bolt_count, extra_bolts_at_full_aggression), 1)
	for i: int in count:
		var bolt := Pools.acquire_scene(bolt_scene) as EnemyBolt
		if bolt == null:
			return
		bolt.damage = bolt_damage
		bolt.launcher = boss
		bolt.global_position = origin
		var t := 0.5 if count == 1 else float(i) / float(count - 1)
		var angle := base_angle + lerpf(-spread * 0.5, spread * 0.5, t)
		var direction := Vector3(cos(angle) * reach, drop, sin(angle) * reach).normalized()
		bolt.look_at(origin + direction, WeaponBase.safe_up(direction))
	Sfx.play(launch_sfx)
