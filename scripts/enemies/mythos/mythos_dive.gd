class_name MythosDive
extends MythosMove
## Picada: marca un disco donde está el raider, se lanza ahí y golpea el
## suelo. Después queda posado un momento, a tiro de las armas cortas: es la
## ventana de un raider cuerpo a cuerpo. El golpe cae en el disco marcado,
## no donde esté el raider al final.

enum Step { WINDUP, PERCHED }

@export_group("Picada")
## Segundos de aviso entre el disco y el golpe, con agresividad 0.
@export var windup: float = 1.1
## Multiplicador del aviso con agresividad 1 (nunca avisa menos que esto).
@export var windup_at_full_aggression: float = 0.75
## Radio del golpe y de su disco de aviso, en metros.
@export var radius: float = 4.2
## Daño del golpe a cada raider dentro del disco (valor base).
@export var damage: float = 40.0
## Metros sobre el suelo por encima de los cuales el golpe no alcanza.
@export var height_window: float = 1.6
## Segundos finales del aviso en los que el cuerpo vuela hasta la marca.
@export var dash_time: float = 0.32
## Segundos posado después del golpe, con agresividad 0.
@export var recover: float = 2.0
## Multiplicador de ese descanso con agresividad 1.
@export var recover_at_full_aggression: float = 0.6
## Sonido del golpe (fila de Sfx.SOUND_LIBRARY).
@export var impact_sfx: StringName = &"fire_whoosh"

var _step: Step = Step.WINDUP
var _timer: float = 0.0
var _windup_total: float = 0.0
var _from: Vector3 = Vector3.ZERO
var _mark: Vector3 = Vector3.ZERO


func scale_damage(multiplier: float) -> void:
	damage *= multiplier


func begin(target: Node3D) -> void:
	_step = Step.WINDUP
	_windup_total = windup * aggression_lerp(1.0, windup_at_full_aggression)
	_timer = _windup_total
	_from = boss.global_position
	_mark = boss.safe_point(target.global_position)
	Telegraph.spawn_disc(boss, _mark, radius, _windup_total, boss.telegraph_color)
	boss.rig.set_pose(MythosRig.Pose.WINDUP)


func tick(delta: float) -> bool:
	_timer -= delta
	match _step:
		Step.WINDUP:
			if _timer <= dash_time:
				# El último tramo del aviso es el vuelo: el cuerpo llega a la
				# marca justo cuando el disco termina de llenarse.
				boss.rig.set_pose(MythosRig.Pose.DIVE)
				var t := 1.0 - clampf(_timer / maxf(dash_time, 0.01), 0.0, 1.0)
				boss.glide_to(_from.lerp(_mark, t * t))
			if _timer <= 0.0:
				_impact()
		Step.PERCHED:
			if _timer <= 0.0:
				boss.rig.set_pose(MythosRig.Pose.FLY)
				return true
	return false


func cancel() -> void:
	boss.rig.set_pose(MythosRig.Pose.FLY)


func _impact() -> void:
	boss.glide_to(_mark)
	boss.strike_ground([_mark], radius, height_window, damage)
	Sfx.play(impact_sfx)
	boss.rig.set_pose(MythosRig.Pose.PERCH)
	_step = Step.PERCHED
	_timer = recover * aggression_lerp(1.0, recover_at_full_aggression)
