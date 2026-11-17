class_name LobsterPincers
extends LobsterMove
## Tenazas: una RÁFAGA. Se alza con una pinza en alto (el aviso) mientras se
## le viene encima al raider, y un disco marca dónde la va a cerrar. El disco
## PERSIGUE al raider adelantándose a su carrera hasta un instante antes del
## golpe; ahí se clava, un segundo aviso lo marca y la langosta se lanza y
## cierra la pinza en ese punto. Varias seguidas, alternando pinzas y volviendo
## a apuntar, y para terminar el REMATE: alza las dos pinzas y las baja juntas,
## una a cada lado, sobre dos discos. Cada golpe cae donde se clavó su disco,
## no donde esté el raider al final: se esquiva cambiando de rumbo cuando se
## clava (correr derecho no alcanza), derrapando o saltando.

enum Step { REAR, LUNGE, GAP, REST }

@export_group("Tenazas")
## Pinzazos seguidos con agresividad 0 (después viene el remate).
@export var snaps: int = 3
## Pinzazos extra con agresividad 1.
@export var extra_snaps_at_full_aggression: int = 1
## Segundos de aviso antes de cada pinzazo, con agresividad 0.
@export var windup: float = 0.62
## Multiplicador del aviso con agresividad 1 (nunca avisa menos que esto).
@export var windup_at_full_aggression: float = 0.85
## Cuánto cambia al azar el aviso de cada pinzazo (0.3 = hasta 30 % más corto o más largo): con un ritmo irregular no se esquiva de memoria.
@export_range(0.0, 0.6) var windup_jitter: float = 0.3
## Segundos antes del golpe en los que el disco deja de perseguir al raider: la ventana para salir.
@export var lock_seconds: float = 0.34
## Radio de cada pinzazo y de su disco de aviso, en metros.
@export var radius: float = 3.0
## Metros delante de la langosta donde cierra la pinza.
@export var reach: float = 2.8
## Metros que avanza, como mucho, con cada pinzazo.
@export var lunge: float = 6.0
## Segundos que dura ese avance.
@export var lunge_time: float = 0.14
## Fracción de su velocidad con que se acerca mientras avisa (0-1).
@export_range(0.0, 1.0) var advance_factor: float = 0.85
## Daño de cada pinzazo a cada raider dentro del disco (valor base).
@export var damage: float = 4.0
## Metros sobre el suelo por encima de los cuales el golpe no alcanza (se esquiva saltando en cuanto el disco se clava).
@export var height_window: float = 1.4
## Segundos entre un golpe y el aviso del siguiente.
@export var gap: float = 0.18
## Segundos quieta después del último golpe: una ventana para pegarle.
@export var recover: float = 1.1
## Segundos que se adelanta al raider para ubicar el disco (0 = lo marca donde está). Con lock_seconds + lunge_time acierta justo a quien corre derecho.
@export var lead_seconds: float = 0.48
## Tope de ese adelanto, en metros, para un raider a velocidad base.
@export var max_lead: float = 4.4
## Sonido de cada pinzazo (fila de Sfx.SOUND_LIBRARY).
@export var snap_sfx: StringName = &"lobster_snap"
## Sonido cuando el disco se clava (fila de Sfx.SOUND_LIBRARY).
@export var lock_sfx: StringName = &"lobster_lock"

@export_group("Remate")
## Si la ráfaga termina con el remate de las dos pinzas.
@export var slam: bool = true
## Segundos de aviso del remate.
@export var slam_windup: float = 0.8
## Segundos antes del remate en los que sus discos dejan de perseguir al raider: la ventana para salir.
@export var slam_lock_seconds: float = 0.5
## Radio de cada uno de los dos discos del remate, en metros.
@export var slam_radius: float = 3.3
## Metros entre el centro del remate y cada disco (uno a cada lado).
@export var slam_spread: float = 2.4
## Daño del remate a cada raider dentro de sus discos (valor base).
@export var slam_damage: float = 8.0
## Sonido del remate (fila de Sfx.SOUND_LIBRARY).
@export var slam_sfx: StringName = &"lobster_slam"

var _step: Step = Step.REAR
var _timer: float = 0.0
var _snaps_left: int = 0
## True mientras avisa y da el remate.
var _finishing: bool = false
var _target: Node3D = null
var _from: Vector3 = Vector3.ZERO
var _to: Vector3 = Vector3.ZERO
var _mark: Vector3 = Vector3.ZERO
var _locked: bool = false
## Dónde cae el golpe en curso, ya clavado (un punto, o los dos del remate).
var _spots: Array[Vector3] = []
## Los discos que persiguen al raider; se sueltan en cuanto se clavan.
var _discs: Array[TelegraphDisc] = []


func scale_damage(multiplier: float) -> void:
	damage *= multiplier
	slam_damage *= multiplier


func begin(target: Node3D) -> void:
	_target = target
	_snaps_left = maxi(aggression_count(snaps, extra_snaps_at_full_aggression), 1)
	_finishing = false
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
	_drop_discs()
	boss.face_along(Vector3.ZERO)
	boss.rig.set_anger(0.0)
	boss.rig.set_pose(LobsterRig.Pose.STALK)


# --- privados ---------------------------------------------------------------------

## Se alza (con la otra pinza, o con las dos en el remate) y sus discos
## empiezan a perseguir al raider.
func _rear() -> void:
	_step = Step.REAR
	_locked = false
	var seconds := slam_windup if _finishing \
			else windup * aggression_lerp(1.0, windup_at_full_aggression) \
			* randf_range(1.0 - windup_jitter, 1.0 + windup_jitter)
	_timer = maxf(seconds, _lock_window() + 0.05)
	_mark = _aim_point()
	_drop_discs()
	for spot: Vector3 in _spots_now():
		_discs.append(Telegraph.spawn_moving_disc(spot, _radius_now(), _timer,
				boss.telegraph_color))
	if _finishing:
		boss.rig.set_pose(LobsterRig.Pose.THREAT)
		boss.rig.set_anger(1.0)
		return
	boss.rig.lead_left = not boss.rig.lead_left
	boss.rig.set_pose(LobsterRig.Pose.REAR)
	boss.rig.set_anger(0.7)


func _tick_rear() -> void:
	if not _locked:
		if _timer > _lock_window():
			_mark = _aim_point()
			var spots := _spots_now()
			for index: int in _discs.size():
				if _discs[index] != null:
					_discs[index].move_to(spots[index])
		else:
			_lock()
	else:
		boss.feel.dread(1.0 if _finishing else 0.5)
	var toward := LobsterAim.flat_direction(boss.global_position, _mark,
			-boss.global_transform.basis.z)
	boss.face_along(toward)
	# Mientras avisa se le viene encima, hasta quedar a un paso del disco.
	if boss.global_position.distance_to(_mark) > reach:
		boss.walk(toward * advance_factor)
	if _timer <= 0.0:
		_launch(toward)


## Se lanza hacia la marca para cerrar la pinza (o bajar las dos).
func _launch(toward: Vector3) -> void:
	if not _locked:
		_lock()
	_from = boss.global_position
	var travel := clampf(_from.distance_to(_mark) - reach, 0.0, lunge)
	_to = boss.safe_point(_from + toward * travel)
	_step = Step.LUNGE
	_timer = lunge_time
	if _finishing:
		boss.rig.set_pose(LobsterRig.Pose.SLAM)
		return
	boss.rig.set_pose(LobsterRig.Pose.SNAP)
	boss.rig.gesture(&"snap_left" if boss.rig.lead_left else &"snap_right")


## Los discos se clavan: ya no persiguen, y un segundo aviso marca dónde cae.
func _lock() -> void:
	_locked = true
	_spots = _spots_now()
	# Los que perseguían vuelven solos al pool al cumplir su tiempo.
	_discs.clear()
	for spot: Vector3 in _spots:
		Telegraph.spawn_disc(boss, spot, _radius_now(), maxf(_timer, 0.05), boss.impact_color)
	Sfx.play(lock_sfx)


## Dónde apunta ahora: sobre el raider, adelantándose a su carrera, y nunca más
## lejos de lo que alcanza con su avance.
func _aim_point() -> Vector3:
	if not has_target(_target):
		return _mark
	var wanted := LobsterAim.predicted(_target, lead_seconds, max_lead)
	return boss.floor_point(LobsterAim.within(boss.global_position, wanted, reach + lunge))


## Dónde caería el golpe que se está avisando: la marca, o en el remate un
## punto a cada lado de ella (uno por pinza).
func _spots_now() -> Array[Vector3]:
	if not _finishing:
		return [_mark]
	var toward := LobsterAim.flat_direction(boss.global_position, _mark,
			-boss.global_transform.basis.z)
	var side := Vector3(-toward.z, 0.0, toward.x) * slam_spread
	return [boss.floor_point(_mark + side), boss.floor_point(_mark - side)]


func _radius_now() -> float:
	return slam_radius if _finishing else radius


func _lock_window() -> float:
	return slam_lock_seconds if _finishing else lock_seconds


func _drop_discs() -> void:
	for disc: TelegraphDisc in _discs:
		release_disc(disc)
	_discs.clear()


func _strike() -> void:
	boss.glide_to(_to)
	var hit := boss.strike_ground(_spots, _radius_now(), height_window,
			slam_damage if _finishing else damage)
	boss.rig.set_anger(0.0)
	if _finishing:
		_finish_strike()
		return
	boss.feel.shock(LobsterFeel.Shock.HEAVY if not hit.is_empty() else LobsterFeel.Shock.LIGHT,
			_mark)
	boss.fx.snap(_mark, radius, LobsterAim.flat_direction(_from, _mark,
			-boss.global_transform.basis.z))
	Sfx.play(snap_sfx)
	_snaps_left -= 1
	_step = Step.GAP
	_timer = gap
	if _snaps_left > 0:
		return
	if slam:
		_finishing = true
		return
	_rest()


## El remate ya cayó: el golpe más grande de la ráfaga. Descansa con las dos
## pinzas clavadas en el suelo (la langosta vuelve a su pose al terminar).
func _finish_strike() -> void:
	boss.feel.shock(LobsterFeel.Shock.CRUSHING, _mark)
	boss.fx.slam(_spots, slam_radius)
	Sfx.play(slam_sfx)
	_finishing = false
	_step = Step.REST
	_timer = recover
	boss.face_along(Vector3.ZERO)


func _rest() -> void:
	_step = Step.REST
	_timer = recover
	boss.face_along(Vector3.ZERO)
	boss.rig.set_pose(LobsterRig.Pose.STALK)
