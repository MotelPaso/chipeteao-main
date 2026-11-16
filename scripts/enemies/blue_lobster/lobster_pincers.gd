class_name LobsterPincers
extends LobsterMove
## Tenazas: se alza con una pinza en alto (el aviso) mientras avanza, y un
## disco marca dónde la va a cerrar. El disco PERSIGUE al raider hasta un
## instante antes del golpe; ahí se clava, un segundo aviso lo marca y la
## langosta se lanza y cierra la pinza en ese punto. Varias seguidas,
## alternando pinzas y volviendo a apuntar. Cada pinzazo cae donde se clavó su
## disco, no donde esté el raider al final: se esquiva saliendo del disco.

enum Step { REAR, LUNGE, GAP, REST }

@export_group("Tenazas")
## Pinzazos seguidos con agresividad 0.
@export var snaps: int = 2
## Pinzazos extra con agresividad 1.
@export var extra_snaps_at_full_aggression: int = 1
## Segundos de aviso antes de cada pinzazo, con agresividad 0.
@export var windup: float = 0.7
## Multiplicador del aviso con agresividad 1 (nunca avisa menos que esto).
@export var windup_at_full_aggression: float = 0.8
## Segundos antes del golpe en los que el disco deja de perseguir al raider: la ventana para salir.
@export var lock_seconds: float = 0.36
## Radio de cada pinzazo y de su disco de aviso, en metros.
@export var radius: float = 2.6
## Metros delante de la langosta donde cierra la pinza.
@export var reach: float = 2.8
## Metros que avanza, como mucho, con cada pinzazo.
@export var lunge: float = 3.4
## Segundos que dura ese avance.
@export var lunge_time: float = 0.12
## Fracción de su velocidad con que se acerca mientras avisa (0-1).
@export_range(0.0, 1.0) var advance_factor: float = 0.45
## Daño de cada pinzazo a cada raider dentro del disco (valor base).
@export var damage: float = 5.0
## Metros sobre el suelo por encima de los cuales el pinzazo no alcanza.
@export var height_window: float = 1.6
## Segundos entre un pinzazo y el aviso del siguiente.
@export var gap: float = 0.3
## Segundos quieta después del último pinzazo: una ventana para pegarle.
@export var recover: float = 1.1
## Segundos que se adelanta al raider para ubicar el disco (0 = lo marca donde está).
@export var lead_seconds: float = 0.0
## Tope de ese adelanto, en metros, para un raider a velocidad base.
@export var max_lead: float = 2.0
## Sonido de cada pinzazo (fila de Sfx.SOUND_LIBRARY).
@export var snap_sfx: StringName = &"lobster_snap"
## Sonido cuando el disco se clava (fila de Sfx.SOUND_LIBRARY).
@export var lock_sfx: StringName = &"lobster_lock"
## Escena del salpicón del golpe (SplashBurst, sale de Pools). Vacío = sin salpicón.
@export var burst_scene: PackedScene = preload("res://scenes/fx/SplashBurst.tscn")

var _step: Step = Step.REAR
var _timer: float = 0.0
var _snaps_left: int = 0
var _target: Node3D = null
var _from: Vector3 = Vector3.ZERO
var _to: Vector3 = Vector3.ZERO
var _mark: Vector3 = Vector3.ZERO
var _locked: bool = false
## El disco que persigue al raider; se suelta en cuanto se clava.
var _disc: TelegraphDisc = null


func scale_damage(multiplier: float) -> void:
	damage *= multiplier


func begin(target: Node3D) -> void:
	_target = target
	_snaps_left = maxi(aggression_count(snaps, extra_snaps_at_full_aggression), 1)
	_mark = boss.floor_point(boss.global_position)
	_rear()


func tick(delta: float) -> bool:
	_timer -= delta
	match _step:
		Step.REAR:
			_tick_rear()
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
	release_disc(_disc)
	_disc = null
	boss.face_along(Vector3.ZERO)
	boss.rig.set_anger(0.0)
	boss.rig.set_pose(LobsterRig.Pose.STALK)


# --- privados ---------------------------------------------------------------------

## Se alza con la otra pinza y el disco empieza a perseguir al raider.
func _rear() -> void:
	_step = Step.REAR
	_locked = false
	_timer = maxf(windup * aggression_lerp(1.0, windup_at_full_aggression), lock_seconds + 0.05)
	_mark = _aim_point()
	_disc = Telegraph.spawn_moving_disc(_mark, radius, _timer, boss.telegraph_color)
	boss.rig.lead_left = not boss.rig.lead_left
	boss.rig.set_pose(LobsterRig.Pose.REAR)
	boss.rig.set_anger(0.7)


func _tick_rear() -> void:
	if not _locked:
		if _timer > lock_seconds:
			_mark = _aim_point()
			if _disc != null:
				_disc.move_to(_mark)
		else:
			_lock()
	var toward := LobsterAim.flat_direction(boss.global_position, _mark,
			-boss.global_transform.basis.z)
	boss.face_along(toward)
	# Mientras avisa se le viene encima, hasta quedar a un paso del disco.
	if boss.global_position.distance_to(_mark) > reach:
		boss.walk(toward * advance_factor)
	if _timer <= 0.0:
		_from = boss.global_position
		var travel := clampf(_from.distance_to(_mark) - reach, 0.0, lunge)
		_to = boss.safe_point(_from + toward * travel)
		_step = Step.LUNGE
		_timer = lunge_time
		boss.rig.set_pose(LobsterRig.Pose.SNAP)
		boss.rig.gesture(&"snap_left" if boss.rig.lead_left else &"snap_right")


## El disco se clava: ya no persigue, y un segundo aviso marca dónde cae.
func _lock() -> void:
	_locked = true
	_disc = null
	Telegraph.spawn_disc(boss, _mark, radius, maxf(_timer, 0.05), boss.impact_color)
	Sfx.play(lock_sfx)


## Dónde cierra la pinza: sobre el raider (o adonde va), nunca más lejos de
## lo que alcanza con su avance.
func _aim_point() -> Vector3:
	if not has_target(_target):
		return _mark
	var wanted := LobsterAim.predicted(_target, lead_seconds, max_lead)
	return boss.floor_point(LobsterAim.within(boss.global_position, wanted, reach + lunge))


func _strike() -> void:
	boss.glide_to(_to)
	var hit := boss.strike_ground([_mark], radius, height_window, damage)
	boss.feel.shock(LobsterFeel.Shock.HEAVY if not hit.is_empty() else LobsterFeel.Shock.LIGHT,
			_mark)
	SplashBurst.spawn(burst_scene, _mark, 0.8)
	Sfx.play(snap_sfx)
	boss.rig.set_anger(0.0)
	_snaps_left -= 1
	if _snaps_left > 0:
		_step = Step.GAP
		_timer = gap
		return
	_step = Step.REST
	_timer = recover
	boss.face_along(Vector3.ZERO)
	boss.rig.set_pose(LobsterRig.Pose.STALK)
