class_name MythosClaws
extends MythosMove
## Garras: posado en tierra, se alza (el aviso) y da zarpazos hacia el
## raider, uno tras otro; con cada uno avanza un paso y vuelve a apuntar.
## Cada zarpazo cae en el disco que marcó, no donde esté el raider al final.

enum Step { REAR, LUNGE, GAP, REST }

@export_group("Garras")
## Zarpazos seguidos con agresividad 0.
@export var swipes: int = 2
## Zarpazos extra con agresividad 1.
@export var extra_swipes_at_full_aggression: int = 1
## Segundos de aviso antes de cada zarpazo, con agresividad 0.
@export var windup: float = 0.6
## Multiplicador del aviso con agresividad 1 (nunca avisa menos que esto).
@export var windup_at_full_aggression: float = 0.75
## Radio de cada zarpazo y de su disco de aviso, en metros.
@export var radius: float = 3.2
## Metros delante de Mythos donde cae el centro del zarpazo.
@export var reach: float = 3.2
## Metros que avanza con cada zarpazo.
@export var lunge: float = 2.2
## Segundos que dura ese avance.
@export var lunge_time: float = 0.12
## Daño de cada zarpazo a cada raider dentro del disco (valor base).
@export var damage: float = 30.0
## Metros sobre el suelo por encima de los cuales el zarpazo no alcanza.
@export var height_window: float = 1.6
## Segundos entre un zarpazo y el aviso del siguiente.
@export var gap: float = 0.3
## Segundos quieto después del último zarpazo: otra ventana para pegarle.
@export var recover: float = 1.8
## Sonido de cada zarpazo (fila de Sfx.SOUND_LIBRARY).
@export var swipe_sfx: StringName = &"fire_whoosh"

var _step: Step = Step.REAR
var _timer: float = 0.0
var _swipes_left: int = 0
var _target: Node3D = null
var _from: Vector3 = Vector3.ZERO
var _to: Vector3 = Vector3.ZERO
var _mark: Vector3 = Vector3.ZERO


func scale_damage(multiplier: float) -> void:
	damage *= multiplier


func begin(target: Node3D) -> void:
	_target = target
	_swipes_left = maxi(aggression_count(swipes, extra_swipes_at_full_aggression), 1)
	_rear()


func tick(delta: float) -> bool:
	_timer -= delta
	match _step:
		Step.REAR:
			if _timer <= 0.0:
				_step = Step.LUNGE
				_timer = lunge_time
				boss.rig.set_pose(MythosRig.Pose.SLASH)
		Step.LUNGE:
			var t := 1.0 - clampf(_timer / maxf(lunge_time, 0.01), 0.0, 1.0)
			boss.glide_to(_from.lerp(_to, t))
			if _timer <= 0.0:
				_strike()
		Step.GAP:
			if _timer <= 0.0:
				_rear()
		Step.REST:
			return _timer <= 0.0
	return false


func cancel() -> void:
	boss.rig.set_pose(boss.rest_pose())


## Se alza y marca el próximo zarpazo hacia donde está el raider ahora.
func _rear() -> void:
	_from = boss.global_position
	var direction := -boss.global_transform.basis.z
	if is_instance_valid(_target) and _target.is_inside_tree():
		var to_target := _target.global_position - _from
		to_target.y = 0.0
		if to_target.length_squared() > 0.01:
			direction = to_target.normalized()
	direction.y = 0.0
	_to = boss.safe_point(_from + direction * lunge)
	_mark = boss.floor_point(_from + direction * reach)
	_timer = windup * aggression_lerp(1.0, windup_at_full_aggression)
	Telegraph.spawn_disc(boss, _mark, radius, _timer, boss.telegraph_color)
	boss.rig.set_pose(MythosRig.Pose.REAR)
	_step = Step.REAR


func _strike() -> void:
	boss.glide_to(_to)
	boss.strike_ground([_mark], radius, height_window, damage)
	Sfx.play(swipe_sfx)
	_swipes_left -= 1
	if _swipes_left > 0:
		_step = Step.GAP
		_timer = gap
		return
	_step = Step.REST
	_timer = recover
	boss.rig.set_pose(boss.rest_pose())
