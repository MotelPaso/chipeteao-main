class_name LobsterLeap
extends LobsterMove
## Salto aplastante: se agazapa con la cola enroscada, da un coletazo y salta
## alto. El disco de aviso PERSIGUE al raider mientras está en el aire; poco
## antes de caer se clava (un segundo aviso lo marca) y la langosta cae en su
## centro con las pinzas por delante: golpe, salpicón y una onda de choque que
## se abre a ras de suelo y hay que SALTAR. Aplastada contra el suelo da un
## coletazo y manda una RÉPLICA: otra onda, con el tiempo justo para caer del
## primer salto y volver a saltar; la anuncia levantando la cola. El disco
## queda un poco antes del raider (stand_off), así el cuerpo no le cae encima.
## Mientras está aplastada es la ventana para pegarle, saltando la réplica.

enum Step { CROUCH, AIRBORNE, REST }

## Cuántas veces su avance más rápido puede recorrer el salto en un frame
## mientras recupera lo que esperó subiendo junto a una pared (ver _fly).
const CATCH_UP: float = 2.0

@export_group("Salto")
## Segundos agazapada antes de saltar.
@export var crouch_seconds: float = 0.5
## Segundos en el aire, con agresividad 0.
@export var air_seconds: float = 1.0
## Multiplicador del tiempo en el aire con agresividad 1 (nunca menos que esto).
@export var air_at_full_aggression: float = 0.85
## Segundos antes de caer en los que el disco deja de perseguir al raider: la ventana para salir.
@export var lock_seconds: float = 0.5
## Metros que sube en lo más alto del salto.
@export var leap_height: float = 9.0
## Metros que puede cruzar de un salto, como mucho.
@export var max_distance: float = 30.0
## Radio del golpe y de su disco de aviso, en metros.
@export var radius: float = 5.0
## Daño del golpe a cada raider dentro del disco (valor base).
@export var damage: float = 11.0
## Metros sobre el suelo por encima de los cuales el golpe no alcanza (se esquiva saltando cuando el disco se clava).
@export var height_window: float = 1.4
## Segundos que se adelanta al raider para ubicar el disco.
@export var lead_seconds: float = 0.45
## Tope de ese adelanto, en metros, para un raider a velocidad base.
@export var max_lead: float = 4.5
## Metros antes del raider donde cae el cuerpo: no le cae encima, lo alcanza con las pinzas. El disco de aviso marca dónde cae.
@export var stand_off: float = 2.4
## Segundos aplastada después de caer, con agresividad 0: la ventana para pegarle.
@export var recover: float = 1.6
## Multiplicador de ese descanso con agresividad 1.
@export var recover_at_full_aggression: float = 0.8
## Sonido al saltar (fila de Sfx.SOUND_LIBRARY).
@export var jump_sfx: StringName = &"lobster_whoosh"
## Sonido cuando el disco se clava (fila de Sfx.SOUND_LIBRARY).
@export var lock_sfx: StringName = &"lobster_lock"
## Sonido del golpe (fila de Sfx.SOUND_LIBRARY).
@export var impact_sfx: StringName = &"lobster_slam"

@export_group("Onda de choque")
## Escena de la onda que sale del golpe (ShockRing, sale de Pools). Vacío = sin onda.
@export var ring_scene: PackedScene = preload("res://scenes/fx/ShockRing.tscn")
## Ondas seguidas que salen del golpe: la primera al caer y las demás como réplicas.
@export var rings: int = 2
## Segundos entre una onda y la siguiente: lo justo para caer de un salto y volver a saltar.
@export var ring_gap_seconds: float = 1.1
## Radio en metros con que nace cada onda, bajo su cuerpo. A quien el golpe ya le dio, la primera no lo toca.
@export var ring_start_radius: float = 1.5
## Radio en metros hasta el que llega cada onda.
@export var ring_radius: float = 17.0
## Metros por segundo a los que se abre.
@export var ring_speed: float = 15.0
## Daño de la onda a cada raider que alcance en el suelo (valor base).
@export var ring_damage: float = 4.0
## Metros sobre el suelo desde los que un raider ya no es alcanzado (se esquiva saltando).
@export var ring_height_window: float = 0.9
## Ancho del anillo que golpea, en metros.
@export var ring_band: float = 1.3
## Segundos antes de cada réplica en los que la anuncia: levanta la cola y suena.
@export var aftershock_cue_seconds: float = 0.45
## Sonido de ese anuncio (fila de Sfx.SOUND_LIBRARY).
@export var aftershock_cue_sfx: StringName = &"lobster_hiss"

var _step: Step = Step.CROUCH
var _timer: float = 0.0
var _air: float = 1.0
var _target: Node3D = null
var _from: Vector3 = Vector3.ZERO
var _mark: Vector3 = Vector3.ZERO
var _locked: bool = false
## Fracción del salto ya recorrida en horizontal (0 al despegar, 1 en la marca).
var _progress: float = 0.0
## Réplicas que faltan, segundos hasta la próxima y si ya la anunció.
var _rings_left: int = 0
var _ring_timer: float = 0.0
var _ring_cued: bool = false
## El disco que persigue al raider; se suelta en cuanto se clava.
var _disc: TelegraphDisc = null


func scale_damage(multiplier: float) -> void:
	damage *= multiplier
	ring_damage *= multiplier


func begin(target: Node3D) -> void:
	_target = target
	_step = Step.CROUCH
	_locked = false
	_progress = 0.0
	_air = maxf(air_seconds * aggression_lerp(1.0, air_at_full_aggression), lock_seconds + 0.1)
	_timer = crouch_seconds + _air
	_from = boss.global_position
	_mark = _from
	_mark = _aim_point()
	_disc = Telegraph.spawn_moving_disc(_mark, scaled(radius), _timer, boss.telegraph_color)
	boss.rig.set_pose(LobsterRig.Pose.CROUCH)
	boss.rig.set_anger(0.5)


func tick(delta: float) -> bool:
	_timer -= delta
	if _step == Step.REST:
		_tick_aftershocks(delta)
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
		boss.fx.takeoff(boss.core_point())
		Sfx.play(jump_sfx)
	if _step == Step.AIRBORNE:
		_fly(delta)
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
## alcanza de un salto, también sobre el piso elevado que pise él (el tablero
## del Gran Puente). Sin raider a quien seguir, la marca se queda.
func _aim_point() -> Vector3:
	if not has_target(_target):
		return _mark
	var wanted := LobsterAim.short_of(_from,
			LobsterAim.predicted(_target, lead_seconds, max_lead), stand_off)
	return boss.safe_point(LobsterAim.within(_from, wanted, scaled(max_distance)),
			_target.global_position)


## El disco se clava: ya no persigue, y un segundo aviso marca dónde cae.
func _lock() -> void:
	_locked = true
	_disc = null
	Telegraph.spawn_disc(boss, _mark, scaled(radius), maxf(_timer, 0.05), boss.impact_color)
	Sfx.play(lock_sfx)
	boss.rig.set_anger(1.0)


## En el aire: el cuerpo va de donde saltó a la marca, y el modelo sube y baja
## en arco por encima. En la bajada apunta las pinzas al suelo.
func _fly(delta: float) -> void:
	var t := 1.0 - clampf(_timer / maxf(_air, 0.01), 0.0, 1.0)
	var arc := leap_height * 4.0 * t * (1.0 - t)
	# smoothstep avanza a lo sumo 1.5 / _air por segundo: para ponerse al día
	# avanza hasta CATCH_UP veces eso en un frame.
	var reach := CATCH_UP * 1.5 * delta / maxf(_air, 0.01)
	var progress := minf(smoothstep(0.0, 1.0, t), _progress + reach)
	var line := _from.lerp(_mark, progress)
	# Subiendo, si el suelo de adelante queda por encima del modelo (salta a lo
	# alto de un corte desde su pie), primero sube en el lugar y avanza cuando
	# ya lo pasa: así no trepa la pared de un tirón.
	if t < 0.5 and boss.ground_height(line) > line.y + arc:
		progress = _progress
		line = _from.lerp(_mark, progress)
	_progress = progress
	boss.fly_to(line)
	# El modelo sigue su arco sobre la recta del salto aunque el cuerpo haya
	# tenido que subir al borde de un corte: así no da un tirón al cruzarlo.
	boss.rig.lift = maxf(line.y + arc - boss.global_position.y, 0.0)
	if t > 0.55:
		boss.rig.set_pose(LobsterRig.Pose.DIVE)
		boss.rig.set_dust(false)


func _impact() -> void:
	boss.fly_to(_mark)
	boss.rig.lift = 0.0
	_send_ring(boss.strike_ground([_mark], scaled(radius), height_window, damage))
	boss.fx.landing(_mark, scaled(radius))
	boss.feel.shock(LobsterFeel.Shock.CRUSHING, _mark)
	Sfx.play(impact_sfx)
	boss.rig.set_anger(0.0)
	boss.rig.set_pose(LobsterRig.Pose.SLAM)
	boss.face_along(Vector3.ZERO)
	_step = Step.REST
	_rings_left = maxi(rings - 1, 0)
	_ring_timer = ring_gap_seconds
	_ring_cued = false
	# El descanso alcanza siempre para todas las réplicas.
	_timer = maxf(recover * aggression_lerp(1.0, recover_at_full_aggression),
			ring_gap_seconds * float(_rings_left) + 0.2)


## Una onda de choque desde donde cayó. Nace bajo su cuerpo y se abre: quien
## salió del disco tiene un instante para saltarla. A los `spared` (los que el
## golpe ya alcanzó) no los toca.
func _send_ring(spared: Array[Node3D] = []) -> void:
	if ring_scene == null:
		return
	var ring := ShockRing.spawn(ring_scene, _mark, ring_start_radius, scaled(ring_radius),
			scaled(ring_speed), ring_damage, ring_height_window, scaled(ring_band), boss)
	if ring != null:
		ring.spare(spared)


## Aplastada contra el suelo: cada tanto levanta la cola (el anuncio) y un
## coletazo manda otra onda.
func _tick_aftershocks(delta: float) -> void:
	if _rings_left <= 0:
		return
	_ring_timer -= delta
	if not _ring_cued and _ring_timer <= aftershock_cue_seconds:
		_ring_cued = true
		boss.rig.gesture(&"tail_slap")
		boss.rig.set_anger(1.0)
		Sfx.play(aftershock_cue_sfx)
	if _ring_timer > 0.0:
		return
	_rings_left -= 1
	_ring_timer = ring_gap_seconds
	_ring_cued = false
	_send_ring()
	boss.rig.set_anger(0.0)
	boss.fx.aftershock(_mark, scaled(radius))
	boss.feel.shock(LobsterFeel.Shock.HEAVY, _mark)
	Sfx.play(impact_sfx)
