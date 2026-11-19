class_name LobsterCharge
extends LobsterMove
## Embestida: adelanta un hombro, abre las pinzas y retrocede para tomar
## carrera, y un carril de galones marca por dónde va a pasar. Mientras avisa,
## el carril GIRA siguiendo al raider (adelantándose a su carrera); un instante
## antes se clava (cambia de color) y la langosta cruza el carril de un tirón,
## golpeando una vez a cada raider que encuentre. Pasa de largo, derrapa
## girando hacia el raider y VUELVE A EMBESTIR, con un aviso más corto: varias
## pasadas seguidas. Después de la última queda un momento recuperándose. Se
## esquiva saliendo del carril en cuanto se clava (derrapando si hace falta) o
## saltándola justo cuando pasa.

enum Step { AIM, LOCKED, DASH, SKID, REST }

@export_group("Embestida")
## Pasadas seguidas con agresividad 0.
@export var passes: int = 3
## Pasadas extra con agresividad 1.
@export var extra_passes_at_full_aggression: int = 1
## Segundos de aviso entre que aparece el carril y la primera embestida, con agresividad 0.
@export var windup: float = 0.95
## Multiplicador del aviso con agresividad 1 (nunca avisa menos que esto).
@export var windup_at_full_aggression: float = 0.85
## Segundos de aviso de cada pasada después de la primera.
@export var repass_windup: float = 0.62
## Segundos antes de la embestida en los que el carril deja de girar: la ventana para salir.
@export var lock_seconds: float = 0.3
## Metros que recorre como mucho en cada pasada.
@export var length: float = 26.0
## Metros que pasa de largo del raider.
@export var overshoot: float = 7.0
## Ancho del carril y del golpe, en metros.
@export var width: float = 5.0
## Metros que retrocede sobre el carril mientras avisa la primera pasada, para tomar carrera.
@export var backstep: float = 2.2
## Metros que retrocede antes de cada pasada siguiente.
@export var repass_backstep: float = 1.0
## Metros por segundo a los que cruza el carril.
@export var run_speed: float = 38.0
## Grados por segundo que el carril puede girar para seguir al raider.
@export var turn_degrees_per_second: float = 130.0
## Daño de cada pasada a cada raider que encuentre en el carril (valor base).
@export var damage: float = 7.0
## Metros sobre el suelo por encima de los cuales la embestida no alcanza (se esquiva saltándola justo cuando pasa).
@export var height_window: float = 1.6
## Segundos que se adelanta al raider para apuntar el carril.
@export var lead_seconds: float = 0.3
## Tope de ese adelanto, en metros, para un raider a velocidad base.
@export var max_lead: float = 3.5
## Segundos que derrapa después de cada pasada.
@export var skid_seconds: float = 0.38
## Metros que recorre derrapando.
@export var skid_distance: float = 2.6
## Segundos quieta después del último derrape: una ventana para pegarle.
@export var recover: float = 1.1
## Sonido de cada embestida (fila de Sfx.SOUND_LIBRARY).
@export var dash_sfx: StringName = &"lobster_whoosh"
## Sonido cuando el carril se clava (fila de Sfx.SOUND_LIBRARY).
@export var lock_sfx: StringName = &"lobster_lock"
## Escena del carril de aviso (TelegraphLane, sale de Pools).
@export var lane_scene: PackedScene = preload("res://scenes/fx/TelegraphLane.tscn")

var _step: Step = Step.AIM
var _timer: float = 0.0
var _passes_left: int = 0
## Lo que duran el aviso entero y el retroceso de esta pasada.
var _windup: float = 1.0
var _backstep: float = 0.0
var _target: Node3D = null
var _from: Vector3 = Vector3.ZERO
var _direction: Vector3 = Vector3.FORWARD
## Metros del carril de ahora y los ya recorridos.
var _run: float = 0.0
var _travelled: float = 0.0
var _lane: TelegraphLane = null
## Raiders ya golpeados en esta pasada (ids de instancia).
var _hit: Dictionary[int, bool] = {}


func scale_damage(multiplier: float) -> void:
	damage *= multiplier


func begin(target: Node3D) -> void:
	_target = target
	_passes_left = maxi(aggression_count(passes, extra_passes_at_full_aggression), 1)
	_direction = -boss.global_transform.basis.z
	_aim_pass(windup * aggression_lerp(1.0, windup_at_full_aggression), backstep)


func tick(delta: float) -> bool:
	_timer -= delta
	match _step:
		Step.AIM:
			_turn_lane(delta)
			_wind_back()
			if _timer <= lock_seconds:
				_lock()
		Step.LOCKED:
			boss.feel.dread(0.8)
			_wind_back()
			if _timer <= 0.0:
				_dash()
		Step.DASH:
			_tick_dash(delta)
		Step.SKID:
			_tick_skid()
		Step.REST:
			return _timer <= 0.0
	return false


func cancel() -> void:
	_drop_lane()
	boss.face_along(Vector3.ZERO)
	boss.rig.set_dust(false)
	boss.rig.set_anger(0.0)
	boss.rig.set_pose(LobsterRig.Pose.STALK)


# --- privados ---------------------------------------------------------------------

## Empieza a avisar una pasada desde donde está: el carril aparece apuntando
## al raider y dura todo el aviso (al clavarse queda lleno hasta el golpe).
func _aim_pass(seconds: float, step_back: float) -> void:
	_step = Step.AIM
	_windup = maxf(seconds, lock_seconds + 0.1)
	_timer = _windup
	_backstep = step_back
	_from = boss.global_position
	_direction = LobsterAim.flat_direction(_from, _aim_point(), _direction)
	_hit.clear()
	_measure_run()
	_drop_lane()
	_lane = TelegraphLane.spawn(lane_scene, _from, _lane_end(), scaled(width), _timer,
			boss.telegraph_color)
	# El flanco que queda adelante se alterna de una pasada a la otra.
	boss.rig.side = -boss.rig.side
	boss.rig.set_pose(LobsterRig.Pose.SIDE)
	boss.rig.set_anger(0.6)
	boss.face_along(_direction)


## Adónde va el raider (o dónde está, si ya no hay a quién apuntar).
func _aim_point() -> Vector3:
	if not has_target(_target):
		return _from + _direction * 8.0
	return LobsterAim.predicted(_target, lead_seconds, max_lead)


## Cuánto mide el carril ahora: hasta pasar de largo al raider, sin atravesar
## una roca ni salirse de la arena.
func _measure_run() -> void:
	var to_target := _aim_point() - _from
	to_target.y = 0.0
	var wanted := clampf(to_target.dot(_direction) + scaled(overshoot), scaled(overshoot),
			scaled(length))
	_run = maxf(boss.clear_run(_from, _direction, wanted), 2.0)


func _lane_end() -> Vector3:
	return _from + _direction * (_run + skid_distance)


## El carril gira hacia el raider, hasta donde le da su velocidad de giro.
func _turn_lane(delta: float) -> void:
	var wanted := LobsterAim.flat_direction(_from, _aim_point(), _direction)
	var angle := _direction.signed_angle_to(wanted, Vector3.UP)
	var step := deg_to_rad(scaled(turn_degrees_per_second)) * delta
	_direction = _direction.rotated(Vector3.UP, clampf(angle, -step, step)).normalized()
	_measure_run()
	boss.face_along(_direction)
	if _lane != null and is_instance_valid(_lane):
		_lane.aim(_from, _lane_end())


func _lock() -> void:
	_step = Step.LOCKED
	if _lane != null and is_instance_valid(_lane):
		_lane.aim(_from, _lane_end())
		_lane.lock(boss.impact_color)
	Sfx.play(lock_sfx)
	boss.rig.set_anger(1.0)


## Mientras avisa retrocede de a poco sobre el carril: toma carrera.
func _wind_back() -> void:
	var wound := 1.0 - clampf(_timer / maxf(_windup, 0.01), 0.0, 1.0)
	boss.glide_to(_from - _direction * _backstep * smoothstep(0.0, 1.0, wound))


func _dash() -> void:
	_step = Step.DASH
	_travelled = -_backstep
	_passes_left -= 1
	boss.rig.set_pose(LobsterRig.Pose.DASH)
	boss.rig.set_dust(true)
	boss.fx.charge_started()
	Sfx.play(dash_sfx)


func _tick_dash(delta: float) -> void:
	var before := boss.global_position
	_travelled = minf(_travelled + scaled(run_speed) * delta, _run)
	if not boss.glide_to(_from + _direction * _travelled) and _travelled > 0.0:
		# El borde de un corte le corta la carrera: derrapa donde quedó.
		_run = _travelled
	var now := boss.global_position
	boss.fx.charge_trail(before, now)
	if boss.strike_along(before, now, scaled(width) * 0.5, height_window, damage, _hit) > 0:
		boss.feel.shock(LobsterFeel.Shock.HEAVY, now)
		boss.fx.charge_hit(now)
	if _travelled >= _run:
		_step = Step.SKID
		_timer = skid_seconds
		boss.fx.skid(now)
		boss.rig.set_pose(LobsterRig.Pose.SIDE)
		boss.rig.set_anger(0.0)
		_drop_lane()
		# Si le queda otra pasada, derrapa ya girando hacia el raider.
		if _passes_left > 0 and has_target(_target):
			boss.face_along(LobsterAim.flat_direction(now, _target.global_position, _direction))


## Frena de golpe (recorre casi todo el derrape al principio) y, según le
## queden pasadas, vuelve a apuntar o descansa.
func _tick_skid() -> void:
	var t := 1.0 - clampf(_timer / maxf(skid_seconds, 0.01), 0.0, 1.0)
	boss.glide_to(_from + _direction * (_run + skid_distance * (1.0 - (1.0 - t) * (1.0 - t))))
	if _timer > 0.0:
		return
	if _passes_left > 0 and has_target(_target):
		_aim_pass(repass_windup, repass_backstep)
		return
	_step = Step.REST
	_timer = recover
	boss.face_along(Vector3.ZERO)
	boss.rig.set_dust(false)
	boss.rig.set_pose(LobsterRig.Pose.STALK)


func _drop_lane() -> void:
	if _lane != null and is_instance_valid(_lane):
		_lane.dismiss()
	_lane = null
