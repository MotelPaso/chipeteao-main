class_name LobsterBurrow
extends LobsterMove
## Emboscada: se entierra de cabeza y avanza bajo tierra como un montículo del
## que solo asoman los ojos y las antenas. Un disco de aviso PERSIGUE al
## raider; cuando el montículo lo alcanza (o se le acaba el túnel) el disco se
## clava, el suelo tiembla y la langosta sale de golpe hacia arriba con las
## pinzas por delante. Se esquiva cambiando de rumbo cuando el disco se clava.
## Bajo tierra sigue siendo un blanco: las armas le pegan al montículo. Con
## agresividad vuelve a enterrarse y sale una segunda vez.

enum Step { DIG, TUNNEL, LOCKED, POP, REST }

@export_group("Emboscada")
## Salidas seguidas con agresividad 0.
@export var eruptions: int = 1
## Salidas extra con agresividad 1.
@export var extra_eruptions_at_full_aggression: int = 1
## Segundos que tarda en enterrarse.
@export var dig_seconds: float = 0.6
## Metros por segundo a los que avanza bajo tierra.
@export var tunnel_speed: float = 12.0
## Segundos que como mucho pasa bajo tierra antes de clavar el disco.
@export var max_tunnel_seconds: float = 2.4
## Metros al disco a los que ya lo da por alcanzado y lo clava.
@export var catch_distance: float = 1.2
## Segundos entre que el disco se clava y la salida, con agresividad 0: la ventana para salir.
@export var lock_seconds: float = 0.55
## Multiplicador de esa ventana con agresividad 1 (nunca menos que esto).
@export var lock_at_full_aggression: float = 0.8
## Radio de la salida y de su disco de aviso, en metros.
@export var radius: float = 3.2
## Daño de la salida a cada raider dentro del disco (valor base).
@export var damage: float = 9.0
## Metros sobre el suelo por encima de los cuales la salida no alcanza.
@export var height_window: float = 1.6
## Segundos que se adelanta al raider para ubicar el disco.
@export var lead_seconds: float = 0.3
## Tope de ese adelanto, en metros, para un raider a velocidad base.
@export var max_lead: float = 3.5
## Metros que se hunde el modelo bajo tierra.
@export var depth: float = 1.9
## Metros que salta al salir.
@export var pop_height: float = 2.8
## Segundos que dura ese salto.
@export var pop_seconds: float = 0.55
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
## Escena del salpicón de tierra (SplashBurst, sale de Pools). Vacío = sin salpicón.
@export var burst_scene: PackedScene = preload("res://scenes/fx/SplashBurst.tscn")

var _step: Step = Step.DIG
var _timer: float = 0.0
var _eruptions_left: int = 0
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


func begin(target: Node3D) -> void:
	_target = target
	_eruptions_left = maxi(aggression_count(eruptions, extra_eruptions_at_full_aggression), 1)
	_aim_height = boss.aim_height
	_mark = boss.global_position
	_dig()


func tick(delta: float) -> bool:
	_timer -= delta
	match _step:
		Step.DIG:
			var t := 1.0 - clampf(_timer / maxf(dig_seconds, 0.01), 0.0, 1.0)
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
			var t := 1.0 - clampf(_timer / maxf(pop_seconds, 0.01), 0.0, 1.0)
			boss.rig.lift = pop_height * sin(t * PI)
			if _timer <= 0.0:
				_after_pop()
		Step.REST:
			return _timer <= 0.0
	return false


func cancel() -> void:
	release_disc(_disc)
	_disc = null
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
	_timer = dig_seconds
	_dug_at = boss.global_position
	boss.rig.set_pose(LobsterRig.Pose.DIG)
	boss.rig.set_dust(true)
	boss.rig.set_mound(1.0)
	Sfx.play(dig_sfx)


## Ya bajo tierra: el disco aparece sobre el raider y lo persigue.
func _tunnel() -> void:
	_step = Step.TUNNEL
	_timer = max_tunnel_seconds
	boss.rig.sink = depth
	boss.rig.set_pose(LobsterRig.Pose.TUNNEL)
	boss.aim_height = buried_aim_height
	_mark = _aim_point()
	_disc = Telegraph.spawn_moving_disc(_mark, radius, max_tunnel_seconds, boss.telegraph_color)


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
	boss.glide_to(boss.global_position + direction * minf(tunnel_speed * delta, distance))
	boss.face_along(direction)


## El disco se clava: un segundo aviso marca por dónde sale, y el suelo tiembla.
func _lock() -> void:
	_step = Step.LOCKED
	_timer = lock_seconds * aggression_lerp(1.0, lock_at_full_aggression)
	release_disc(_disc)
	_disc = null
	Telegraph.spawn_disc(boss, _mark, radius, _timer, boss.impact_color)
	Sfx.play(lock_sfx)
	boss.rig.set_anger(1.0)


func _erupt() -> void:
	_step = Step.POP
	_timer = pop_seconds
	boss.glide_to(_mark)
	boss.aim_height = _aim_height
	boss.rig.sink = 0.0
	boss.rig.set_mound(0.0)
	boss.rig.set_pose(LobsterRig.Pose.ERUPT)
	boss.rig.snap_to_pose()
	boss.strike_ground([_mark], radius, height_window, damage)
	SplashBurst.spawn(burst_scene, _mark, 2.0)
	boss.feel.shock(LobsterFeel.Shock.HEAVY, _mark)
	Sfx.play(erupt_sfx)
	boss.rig.set_anger(0.0)
	_eruptions_left -= 1


func _after_pop() -> void:
	boss.rig.lift = 0.0
	if _eruptions_left > 0:
		_dig()
		return
	_step = Step.REST
	_timer = recover
	boss.rig.set_dust(false)
	boss.face_along(Vector3.ZERO)
	boss.rig.set_pose(LobsterRig.Pose.STALK)
	boss.rig.gesture(&"shake")


## Adónde va el raider, llevado a un lugar donde la langosta cabe. Sin raider
## a quien seguir, la marca se queda donde estaba.
func _aim_point() -> Vector3:
	if not has_target(_target):
		return _mark
	return boss.safe_point(LobsterAim.short_of(_dug_at,
			LobsterAim.predicted(_target, lead_seconds, max_lead), stand_off))
