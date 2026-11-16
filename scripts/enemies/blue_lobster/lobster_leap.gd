class_name LobsterLeap
extends LobsterMove
## Salto aplastante: se agazapa con la cola enroscada, da un coletazo y salta
## alto. El disco de aviso PERSIGUE al raider mientras está en el aire; poco
## antes de caer se clava (un segundo aviso lo marca) y la langosta cae en su
## centro con las pinzas por delante: golpe, salpicón y una onda de choque que
## se abre a ras de suelo y hay que SALTAR. El disco queda un poco antes del
## raider (stand_off), así el cuerpo no le cae encima. Después queda un rato
## aplastada contra el suelo: la ventana más segura para pegarle.

enum Step { CROUCH, AIRBORNE, REST }

@export_group("Salto")
## Segundos agazapada antes de saltar.
@export var crouch_seconds: float = 0.5
## Segundos en el aire, con agresividad 0.
@export var air_seconds: float = 1.2
## Multiplicador del tiempo en el aire con agresividad 1 (nunca menos que esto).
@export var air_at_full_aggression: float = 0.82
## Segundos antes de caer en los que el disco deja de perseguir al raider: la ventana para salir.
@export var lock_seconds: float = 0.55
## Metros que sube en lo más alto del salto.
@export var leap_height: float = 7.5
## Metros que puede cruzar de un salto, como mucho.
@export var max_distance: float = 30.0
## Radio del golpe y de su disco de aviso, en metros.
@export var radius: float = 4.4
## Daño del golpe a cada raider dentro del disco (valor base).
@export var damage: float = 11.0
## Metros sobre el suelo por encima de los cuales el golpe no alcanza.
@export var height_window: float = 1.6
## Segundos que se adelanta al raider para ubicar el disco.
@export var lead_seconds: float = 0.35
## Tope de ese adelanto, en metros, para un raider a velocidad base.
@export var max_lead: float = 4.0
## Metros antes del raider donde cae el cuerpo: no le cae encima, lo alcanza con las pinzas. El disco de aviso marca dónde cae.
@export var stand_off: float = 2.4
## Segundos aplastada después de caer, con agresividad 0: la ventana para pegarle.
@export var recover: float = 1.8
## Multiplicador de ese descanso con agresividad 1.
@export var recover_at_full_aggression: float = 0.7
## Sonido al saltar (fila de Sfx.SOUND_LIBRARY).
@export var jump_sfx: StringName = &"lobster_whoosh"
## Sonido cuando el disco se clava (fila de Sfx.SOUND_LIBRARY).
@export var lock_sfx: StringName = &"lobster_lock"
## Sonido del golpe (fila de Sfx.SOUND_LIBRARY).
@export var impact_sfx: StringName = &"lobster_slam"
## Escena del salpicón del golpe (SplashBurst, sale de Pools). Vacío = sin salpicón.
@export var burst_scene: PackedScene = preload("res://scenes/fx/SplashBurst.tscn")

@export_group("Onda de choque")
## Escena de la onda que sale del golpe (ShockRing, sale de Pools). Vacío = sin onda.
@export var ring_scene: PackedScene = preload("res://scenes/fx/ShockRing.tscn")
## Radio en metros hasta el que llega la onda.
@export var ring_radius: float = 13.0
## Metros por segundo a los que se abre.
@export var ring_speed: float = 12.0
## Daño de la onda a cada raider que alcance en el suelo (valor base).
@export var ring_damage: float = 4.0
## Metros sobre el suelo desde los que un raider ya no es alcanzado (se esquiva saltando).
@export var ring_height_window: float = 0.9
## Ancho del anillo que golpea, en metros.
@export var ring_band: float = 1.3

var _step: Step = Step.CROUCH
var _timer: float = 0.0
var _air: float = 1.0
var _target: Node3D = null
var _from: Vector3 = Vector3.ZERO
var _mark: Vector3 = Vector3.ZERO
var _locked: bool = false
## El disco que persigue al raider; se suelta en cuanto se clava.
var _disc: TelegraphDisc = null


func scale_damage(multiplier: float) -> void:
	damage *= multiplier
	ring_damage *= multiplier


func begin(target: Node3D) -> void:
	_target = target
	_step = Step.CROUCH
	_locked = false
	_air = maxf(air_seconds * aggression_lerp(1.0, air_at_full_aggression), lock_seconds + 0.1)
	_timer = crouch_seconds + _air
	_from = boss.global_position
	_mark = _from
	_mark = _aim_point()
	_disc = Telegraph.spawn_moving_disc(_mark, radius, _timer, boss.telegraph_color)
	boss.rig.set_pose(LobsterRig.Pose.CROUCH)
	boss.rig.set_anger(0.5)


func tick(delta: float) -> bool:
	_timer -= delta
	if _step == Step.REST:
		return _timer <= 0.0
	if not _locked:
		if _timer > lock_seconds:
			_mark = _aim_point()
			if _disc != null:
				_disc.move_to(_mark)
		else:
			_lock()
	else:
		boss.feel.dread(1.0)
	boss.face_along(LobsterAim.flat_direction(boss.global_position, _mark, Vector3.ZERO))
	if _step == Step.CROUCH and _timer <= _air:
		_step = Step.AIRBORNE
		boss.rig.set_pose(LobsterRig.Pose.LEAP)
		boss.rig.gesture(&"tail_slap")
		boss.rig.set_dust(true)
		Sfx.play(jump_sfx)
	if _step == Step.AIRBORNE:
		_fly()
	if _timer <= 0.0:
		_impact()
	return false


func cancel() -> void:
	release_disc(_disc)
	_disc = null
	boss.rig.lift = 0.0
	boss.rig.set_dust(false)
	boss.rig.set_anger(0.0)
	boss.face_along(Vector3.ZERO)
	boss.rig.set_pose(LobsterRig.Pose.STALK)


# --- privados ---------------------------------------------------------------------

## Adónde va el raider, llevado a un lugar donde la langosta cabe y que
## alcanza de un salto. Sin raider a quien seguir, la marca se queda.
func _aim_point() -> Vector3:
	if not has_target(_target):
		return _mark
	var wanted := LobsterAim.short_of(_from,
			LobsterAim.predicted(_target, lead_seconds, max_lead), stand_off)
	return boss.safe_point(LobsterAim.within(_from, wanted, max_distance))


## El disco se clava: ya no persigue, y un segundo aviso marca dónde cae.
func _lock() -> void:
	_locked = true
	_disc = null
	Telegraph.spawn_disc(boss, _mark, radius, maxf(_timer, 0.05), boss.impact_color)
	Sfx.play(lock_sfx)
	boss.rig.set_anger(1.0)


## En el aire: el cuerpo va de donde saltó a la marca, y el modelo sube y baja
## en arco por encima. En la bajada apunta las pinzas al suelo.
func _fly() -> void:
	var t := 1.0 - clampf(_timer / maxf(_air, 0.01), 0.0, 1.0)
	boss.glide_to(_from.lerp(_mark, smoothstep(0.0, 1.0, t)))
	boss.rig.lift = leap_height * 4.0 * t * (1.0 - t)
	if t > 0.55:
		boss.rig.set_pose(LobsterRig.Pose.DIVE)
		boss.rig.set_dust(false)


func _impact() -> void:
	boss.glide_to(_mark)
	boss.rig.lift = 0.0
	boss.strike_ground([_mark], radius, height_window, damage)
	# La onda nace justo por fuera del golpe (a quien ya golpeó no lo vuelve a
	# tocar): quien salió del disco todavía tiene que saltarla.
	if ring_scene != null:
		ShockRing.spawn(ring_scene, _mark, radius + ring_band * 0.5, ring_radius, ring_speed,
				ring_damage, ring_height_window, ring_band, boss)
	SplashBurst.spawn(burst_scene, _mark, 2.2)
	boss.feel.shock(LobsterFeel.Shock.HEAVY, _mark)
	Sfx.play(impact_sfx)
	boss.rig.set_anger(0.0)
	boss.rig.set_pose(LobsterRig.Pose.SLAM)
	boss.face_along(Vector3.ZERO)
	_step = Step.REST
	_timer = recover * aggression_lerp(1.0, recover_at_full_aggression)
