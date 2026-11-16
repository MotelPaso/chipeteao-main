class_name MythosWaves
extends MythosMove
## Ondas de fuego: bate las alas y manda anillos de llamas a ras de suelo que
## se abren desde él, uno tras otro. Cada anillo golpea a quien alcance en el
## suelo: se esquivan SALTANDO justo cuando pasan. Con agresividad salen más
## anillos, más seguidos y más rápidos. Con return_waves es la Marea de
## fuego (el nodo Tide de la segunda fase): después de abrirse, los anillos
## vuelven desde lejos y se cierran sobre él.

@export_group("Ondas")
## Escena de la onda (FireWave, sale de Pools). El alto de sus llamas está en esa escena.
@export var wave_scene: PackedScene = preload("res://scenes/fx/FireWave.tscn")
## Segundos de carga antes de la primera onda.
@export var windup: float = 0.8
## Ondas con agresividad 0.
@export var waves: int = 2
## Ondas extra con agresividad 1.
@export var extra_at_full_aggression: int = 2
## Segundos entre una onda y la siguiente, con agresividad 0.
@export var interval: float = 0.95
## Multiplicador de esa espera con agresividad 1.
@export var interval_at_full_aggression: float = 0.8
## Metros por segundo a los que se abre cada onda, con agresividad 0.
@export var speed: float = 13.0
## Multiplicador de esa velocidad con agresividad 1.
@export var speed_at_full_aggression: float = 1.2
## Radio en metros hasta el que llega cada onda.
@export var max_radius: float = 28.0
## Daño de cada onda a cada raider que alcance (valor base).
@export var damage: float = 30.0
## Metros sobre el suelo desde los que un raider ya no es alcanzado (un salto llega a 1,9).
@export var height_window: float = 1.0
## Ancho del anillo que golpea, en metros.
@export var band: float = 1.4
## Ondas que después VUELVEN, cerrándose desde max_radius hacia él (0 = ninguna).
@export var return_waves: int = 0
## Segundos entre la última onda que sale y la primera que vuelve.
@export var return_pause: float = 1.1
## Segundos quieto después de la última onda.
@export var recover: float = 0.7
## Sonido de cada onda (fila de Sfx.SOUND_LIBRARY).
@export var wave_sfx: StringName = &"phoenix_flap"

var _timer: float = 0.0
var _left: int = 0
var _returning_left: int = 0
var _recovering: bool = false


func scale_damage(multiplier: float) -> void:
	damage *= multiplier


func begin(_target: Node3D) -> void:
	_timer = windup
	_left = maxi(aggression_count(waves, extra_at_full_aggression), 1)
	_returning_left = return_waves
	_recovering = false
	boss.rig.set_pose(MythosRig.Pose.WINDUP)


func tick(delta: float) -> bool:
	_timer -= delta
	if _timer > 0.0:
		return false
	if _recovering:
		return true
	# Primero las que salen; después, si las hay, las que vuelven.
	var returning := _left <= 0
	var pace := speed * aggression_lerp(1.0, speed_at_full_aggression)
	if returning:
		FireWave.spawn(wave_scene, boss.global_position, max_radius, 1.5, pace, damage,
				height_window, band, boss)
		_returning_left -= 1
	else:
		FireWave.spawn(wave_scene, boss.global_position, 1.5, max_radius, pace, damage,
				height_window, band, boss)
		_left -= 1
	boss.rig.gesture(&"slam")
	boss.feel.shock(MythosFeel.Shock.LIGHT, boss.global_position)
	Sfx.play(wave_sfx)
	if _left > 0 or (returning and _returning_left > 0):
		_timer = interval * aggression_lerp(1.0, interval_at_full_aggression)
		return false
	if _returning_left > 0:
		_timer = return_pause
		return false
	_recovering = true
	_timer = recover
	boss.rig.set_pose(boss.rest_pose())
	return false


func cancel() -> void:
	boss.rig.set_pose(boss.rest_pose())
