class_name LobsterBurrow
extends LobsterMove
## Emboscada: se entierra de cabeza y avanza bajo tierra como un montículo del
## que solo asoman los ojos y las antenas. Un disco de aviso PERSIGUE al
## raider; cuando el montículo lo alcanza (o se le acaba el túnel) el disco se
## clava, el suelo tiembla y la langosta sale de golpe hacia arriba con las
## pinzas por delante, vuelve a enterrarse en el acto y sale OTRA VEZ: una
## cadena de salidas cada vez más encima. La última es la más grande. Se
## esquiva derrapando o saltando en cuanto el disco se clava, o alejándose
## del montículo mientras persigue; correr derecho no alcanza, y dar media
## vuelta al clavarse tampoco. Bajo tierra pasa por debajo de los raiders (no
## choca con ellos) y sigue siendo un blanco: las armas le pegan al montículo.

enum Step { DIG, TUNNEL, LOCKED, POP, REST }

@export_group("Emboscada")
## Salidas seguidas con agresividad 0.
@export var eruptions: int = 3
## Salidas extra con agresividad 1.
@export var extra_eruptions_at_full_aggression: int = 1
## Segundos que tarda en enterrarse la primera vez.
@export var dig_seconds: float = 0.45
## Segundos que tarda en volver a enterrarse entre una salida y la siguiente.
@export var redig_seconds: float = 0.25
## Metros por segundo a los que avanza bajo tierra.
@export var tunnel_speed: float = 17.0
## Segundos que como mucho pasa bajo tierra antes de clavar el disco.
@export var max_tunnel_seconds: float = 1.8
## Metros al disco a los que ya lo da por alcanzado y lo clava.
@export var catch_distance: float = 1.2
## Segundos entre que el disco se clava y la salida, con agresividad 0: la ventana para salir.
@export var lock_seconds: float = 0.5
## Multiplicador de esa ventana con agresividad 1 (nunca menos que esto).
@export var lock_at_full_aggression: float = 0.85
## Radio de cada salida y de su disco de aviso, en metros.
@export var radius: float = 3.6
## Daño de cada salida a cada raider dentro del disco (valor base).
@export var damage: float = 6.0
## Metros sobre el suelo por encima de los cuales la salida no alcanza (se esquiva saltando en cuanto el disco se clava).
@export var height_window: float = 1.3
## Segundos que se adelanta al raider para ubicar el disco.
@export var lead_seconds: float = 0.4
## Tope de ese adelanto, en metros, para un raider a velocidad base.
@export var max_lead: float = 4.0
## Metros que se hunde el modelo bajo tierra.
@export var depth: float = 1.9
## Metros que salta al salir.
@export var pop_height: float = 3.2
## Segundos que dura ese salto.
@export var pop_seconds: float = 0.42
## Metros antes del raider por donde sale: no le sale justo debajo, lo alcanza con las pinzas. El disco de aviso marca por dónde sale.
@export var stand_off: float = 2.0
## Segundos quieta después de la última salida: una ventana para pegarle.
@export var recover: float = 1.3
## Altura a la que le apuntan las armas mientras está bajo tierra, en metros (el montículo).
@export var buried_aim_height: float = 0.4
## Sonido al enterrarse (fila de Sfx.SOUND_LIBRARY).
@export var dig_sfx: StringName = &"lobster_dig"
## Sonido cuando el disco se clava (fila de Sfx.SOUND_LIBRARY).
@export var lock_sfx: StringName = &"lobster_rumble"
## Sonido de la salida (fila de Sfx.SOUND_LIBRARY).
@export var erupt_sfx: StringName = &"lobster_slam"

@export_group("Última salida")
## Radio de la última salida de la cadena y de su disco de aviso, en metros.
@export var final_radius: float = 5.0
## Daño de la última salida a cada raider dentro del disco (valor base).
@export var final_damage: float = 10.0
## Segundos entre que su disco se clava y la salida: la ventana para salir.
@export var final_lock_seconds: float = 0.58
## Metros que salta al salir la última vez.
@export var final_pop_height: float = 5.2
## Segundos que dura ese salto.
@export var final_pop_seconds: float = 0.6

var _step: Step = Step.DIG
var _timer: float = 0.0
var _eruptions_left: int = 0
## True desde la segunda vez que se entierra en esta cadena.
var _redigging: bool = false
## Lo que mide el salto de la salida en curso.
var _pop_height: float = 0.0
var _pop_seconds: float = 0.5
var _target: Node3D = null
var _mark: Vector3 = Vector3.ZERO
## Dónde se enterró esta vez: desde ahí se mide por dónde sale.
var _dug_at: Vector3 = Vector3.ZERO
## La altura a la que le apuntan las armas fuera de la tierra.
var _aim_height: float = 1.0
## El disco que persigue al raider; se devuelve al pool en cuanto se clava.
var _disc: TelegraphDisc = null


func scale_damage(multiplier: float) -> void:
	damage *= multiplier
	final_damage *= multiplier


func begin(target: Node3D) -> void:
	_target = target
	_eruptions_left = maxi(aggression_count(eruptions, extra_eruptions_at_full_aggression), 1)
	_redigging = false
	_aim_height = boss.aim_height
	_mark = boss.global_position
	_dig()


func tick(delta: float) -> bool:
	_timer -= delta
	match _step:
		Step.DIG:
			var t := 1.0 - clampf(_timer / maxf(_dig_time(), 0.01), 0.0, 1.0)
			boss.rig.sink = depth * t
			if _timer <= 0.0:
				_tunnel()
		Step.TUNNEL:
			_tick_tunnel(delta)
		Step.LOCKED:
			boss.feel.dread(1.0)
			_creep(delta)
			if _timer <= 0.0:
				_erupt()
		Step.POP:
			var t := 1.0 - clampf(_timer / maxf(_pop_seconds, 0.01), 0.0, 1.0)
			boss.rig.lift = _pop_height * sin(t * PI)
			if _timer <= 0.0:
				_after_pop()
		Step.REST:
			return _timer <= 0.0
	return false


func cancel() -> void:
	release_disc(_disc)
	_disc = null
	boss.pass_under_raiders(false)
	boss.aim_height = _aim_height
	boss.rig.sink = 0.0
	boss.rig.lift = 0.0
	boss.rig.set_mound(0.0)
	boss.rig.set_dust(false)
	boss.rig.set_anger(0.0)
	boss.face_along(Vector3.ZERO)
	boss.rig.set_pose(LobsterRig.Pose.STALK)


# --- privados ---------------------------------------------------------------------

func _dig() -> void:
	_step = Step.DIG
	_timer = _dig_time()
	_dug_at = boss.global_position
	boss.rig.set_pose(LobsterRig.Pose.DIG)
	boss.rig.set_dust(true)
	boss.rig.set_mound(1.0)
	boss.fx.dig(boss.core_point())
	Sfx.play(dig_sfx)


## Ya bajo tierra: el disco aparece sobre el raider y lo persigue.
func _tunnel() -> void:
	_step = Step.TUNNEL
	_timer = max_tunnel_seconds
	boss.rig.sink = depth
	boss.rig.set_pose(LobsterRig.Pose.TUNNEL)
	boss.aim_height = buried_aim_height
	boss.pass_under_raiders(true)
	_mark = _aim_point()
	_disc = Telegraph.spawn_moving_disc(_mark, _radius_now(), max_tunnel_seconds,
			boss.telegraph_color)


func _tick_tunnel(delta: float) -> void:
	_mark = _aim_point()
	if _disc != null and _timer > 0.03:
		_disc.move_to(_mark)
	_creep(delta)
	var gap := boss.global_position - _mark
	gap.y = 0.0
	if gap.length() <= catch_distance or _timer <= 0.0:
		_lock()


## Avanza bajo tierra hacia la marca, sin chocar con nada.
func _creep(delta: float) -> void:
	var to_mark := _mark - boss.global_position
	to_mark.y = 0.0
	var distance := to_mark.length()
	if distance < 0.05:
		return
	var direction := to_mark / distance
	var before := boss.global_position
	boss.glide_to(before + direction * minf(scaled(tunnel_speed) * delta, distance))
	boss.fx.tunnel_trail(before, boss.global_position)
	boss.face_along(direction)


## El disco se clava: un segundo aviso marca por dónde sale, y el suelo tiembla.
func _lock() -> void:
	_step = Step.LOCKED
	_timer = final_lock_seconds if _is_last() \
			else lock_seconds * aggression_lerp(1.0, lock_at_full_aggression)
	release_disc(_disc)
	_disc = null
	Telegraph.spawn_disc(boss, _mark, _radius_now(), _timer, boss.impact_color)
	Sfx.play(lock_sfx)
	boss.rig.set_anger(1.0)


func _erupt() -> void:
	var last := _is_last()
	_step = Step.POP
	_pop_height = final_pop_height if last else pop_height
	_pop_seconds = final_pop_seconds if last else pop_seconds
	_timer = _pop_seconds
	boss.glide_to(_mark)
	boss.pass_under_raiders(false)
	boss.aim_height = _aim_height
	boss.rig.sink = 0.0
	boss.rig.set_mound(0.0)
	boss.rig.set_pose(LobsterRig.Pose.ERUPT)
	boss.rig.snap_to_pose()
	boss.strike_ground([_mark], _radius_now(), height_window, final_damage if last else damage)
	boss.fx.eruption(_mark, _radius_now(), last)
	boss.feel.shock(LobsterFeel.Shock.CRUSHING if last else LobsterFeel.Shock.HEAVY, _mark)
	Sfx.play(erupt_sfx)
	boss.rig.set_anger(0.0)
	_eruptions_left -= 1


func _after_pop() -> void:
	boss.rig.lift = 0.0
	if _eruptions_left > 0:
		_redigging = true
		_dig()
		return
	_step = Step.REST
	_timer = recover
	boss.rig.set_dust(false)
	boss.face_along(Vector3.ZERO)
	boss.rig.set_pose(LobsterRig.Pose.STALK)
	boss.rig.gesture(&"shake")


## True si la salida que viene es la última de la cadena (la grande). Una
## cadena de una sola salida no tiene última grande.
func _is_last() -> bool:
	return _eruptions_left == 1 and _redigging


func _radius_now() -> float:
	return scaled(final_radius if _is_last() else radius)


func _dig_time() -> float:
	return redig_seconds if _redigging else dig_seconds


## Adónde va el raider, llevado a un lugar donde la langosta cabe. Sin raider
## a quien seguir, la marca se queda donde estaba.
func _aim_point() -> Vector3:
	if not has_target(_target):
		return _mark
	return boss.safe_point(LobsterAim.short_of(_dug_at,
			LobsterAim.predicted(_target, lead_seconds, max_lead), stand_off))
