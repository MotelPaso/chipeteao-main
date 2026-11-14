class_name MythosDive
extends MythosMove
## Picada: marca un disco adonde el raider va corriendo, se lanza ahí y golpea
## el suelo; del golpe sale una onda de fuego que hay que saltar. Después queda
## POSADO en tierra (Mythos.land), a tiro de las armas cortas, y pelea desde
## ahí con sus Garras hasta que despega con un Aletazo. El golpe cae en el
## disco marcado, no donde esté el raider al final.

enum Step { WINDUP, PERCHED }

@export_group("Picada")
## Segundos de aviso entre el disco y el golpe, con agresividad 0.
@export var windup: float = 1.0
## Multiplicador del aviso con agresividad 1 (nunca avisa menos que esto).
@export var windup_at_full_aggression: float = 0.7
## Radio del golpe y de su disco de aviso, en metros.
@export var radius: float = 5.0
## Daño del golpe a cada raider dentro del disco (valor base).
@export var damage: float = 50.0
## Metros sobre el suelo por encima de los cuales el golpe no alcanza.
@export var height_window: float = 1.6
## Segundos que se adelanta al raider para marcar el disco.
@export var lead_seconds: float = 0.35
## Tope de ese adelanto, en metros.
@export var max_lead: float = 4.0
## Segundos finales del aviso en los que el cuerpo vuela hasta la marca.
@export var dash_time: float = 0.3
## Segundos posado y quieto justo después del golpe (la ventana más segura para pegarle), con agresividad 0.
@export var recover: float = 2.4
## Multiplicador de ese descanso con agresividad 1.
@export var recover_at_full_aggression: float = 0.7
## Sonido del golpe (fila de Sfx.SOUND_LIBRARY).
@export var impact_sfx: StringName = &"fire_whoosh"

@export_group("Onda de fuego")
## Escena de la onda que sale del golpe (FireWave, sale de Pools). Vacío = sin onda.
@export var wave_scene: PackedScene = preload("res://scenes/fx/FireWave.tscn")
## Radio en metros hasta el que llega la onda.
@export var wave_radius: float = 20.0
## Metros por segundo a los que se abre.
@export var wave_speed: float = 14.0
## Daño de la onda a cada raider que alcance en el suelo (valor base).
@export var wave_damage: float = 28.0
## Metros sobre el suelo desde los que un raider ya no es alcanzado (se esquiva saltando).
@export var wave_height_window: float = 1.0
## Ancho del anillo que golpea, en metros.
@export var wave_band: float = 1.4

var _step: Step = Step.WINDUP
var _timer: float = 0.0
var _from: Vector3 = Vector3.ZERO
var _mark: Vector3 = Vector3.ZERO


func scale_damage(multiplier: float) -> void:
	damage *= multiplier
	wave_damage *= multiplier


func begin(target: Node3D) -> void:
	_step = Step.WINDUP
	_timer = windup * aggression_lerp(1.0, windup_at_full_aggression)
	_from = boss.global_position
	_mark = boss.safe_point(MythosBolts.predicted(target, lead_seconds, max_lead))
	Telegraph.spawn_disc(boss, _mark, radius, _timer, boss.telegraph_color)
	boss.rig.set_pose(MythosRig.Pose.WINDUP)


func tick(delta: float) -> bool:
	_timer -= delta
	if _step == Step.PERCHED:
		return _timer <= 0.0
	if _timer <= dash_time:
		# El último tramo del aviso es el vuelo: el cuerpo llega a la marca
		# justo cuando el disco termina de llenarse.
		boss.rig.set_pose(MythosRig.Pose.DIVE)
		boss.rig.set_trail(true)
		var t := 1.0 - clampf(_timer / maxf(dash_time, 0.01), 0.0, 1.0)
		boss.glide_to(_from.lerp(_mark, t * t))
	if _timer <= 0.0:
		_impact()
	return false


func cancel() -> void:
	boss.rig.set_trail(false)
	boss.rig.set_pose(boss.rest_pose())


func _impact() -> void:
	boss.glide_to(_mark)
	boss.strike_ground([_mark], radius, height_window, damage)
	# La onda nace en el borde del golpe: quien salió del disco todavía tiene
	# que saltarla.
	if wave_scene != null:
		FireWave.spawn(wave_scene, _mark, radius, wave_radius, wave_speed, wave_damage,
				wave_height_window, wave_band, boss)
	boss.rig.burst()
	boss.rig.set_trail(false)
	Sfx.play(impact_sfx)
	boss.land()
	# Recién posado se sacude las plumas.
	boss.rig.gesture(&"shake")
	_step = Step.PERCHED
	_timer = recover * aggression_lerp(1.0, recover_at_full_aggression)
