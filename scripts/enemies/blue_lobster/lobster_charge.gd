class_name LobsterCharge
extends LobsterMove
## Embestida: adelanta un hombro, abre las pinzas y retrocede para tomar
## carrera, y un carril de galones marca por dónde va a pasar. Mientras avisa,
## el carril GIRA siguiendo al raider; un instante antes se clava (cambia de color) y la
## langosta cruza el carril de un tirón, golpeando una vez a cada raider que
## encuentre. Pasa de largo, derrapa y queda un momento recuperándose: se
## esquiva saliendo del carril en cuanto se clava.

enum Step { AIM, LOCKED, DASH, SKID, REST }

@export_group("Embestida")
## Segundos de aviso entre que aparece el carril y la embestida, con agresividad 0.
@export var windup: float = 1.15
## Multiplicador del aviso con agresividad 1 (nunca avisa menos que esto).
@export var windup_at_full_aggression: float = 0.78
## Segundos antes de la embestida en los que el carril deja de girar: la ventana para salir.
@export var lock_seconds: float = 0.45
## Metros que recorre como mucho.
@export var length: float = 22.0
## Metros que pasa de largo del raider.
@export var overshoot: float = 7.0
## Ancho del carril y del golpe, en metros.
@export var width: float = 4.4
## Metros que retrocede sobre el carril mientras avisa, para tomar carrera.
@export var backstep: float = 2.2
## Metros por segundo a los que cruza el carril.
@export var run_speed: float = 30.0
## Grados por segundo que el carril puede girar para seguir al raider.
@export var turn_degrees_per_second: float = 75.0
## Daño a cada raider que encuentre en el carril (valor base).
@export var damage: float = 9.0
## Metros sobre el suelo por encima de los cuales la embestida no alcanza.
@export var height_window: float = 1.6
## Segundos que se adelanta al raider para apuntar el carril.
@export var lead_seconds: float = 0.2
## Tope de ese adelanto, en metros, para un raider a velocidad base.
@export var max_lead: float = 3.0
## Segundos que derrapa después de cruzar.
@export var skid_seconds: float = 0.45
## Metros que recorre derrapando.
@export var skid_distance: float = 2.6
## Segundos quieta después del derrape: una ventana para pegarle.
@export var recover: float = 1.0
## Sonido de la embestida (fila de Sfx.SOUND_LIBRARY).
@export var dash_sfx: StringName = &"lobster_whoosh"
## Sonido cuando el carril se clava (fila de Sfx.SOUND_LIBRARY).
@export var lock_sfx: StringName = &"lobster_lock"
## Escena del carril de aviso (TelegraphLane, sale de Pools).
@export var lane_scene: PackedScene = preload("res://scenes/fx/TelegraphLane.tscn")

var _step: Step = Step.AIM
var _timer: float = 0.0
## Lo que dura el aviso entero esta vez.
var _windup: float = 1.0
var _target: Node3D = null
var _from: Vector3 = Vector3.ZERO
var _direction: Vector3 = Vector3.FORWARD
## Metros del carril de ahora y los ya recorridos.
var _run: float = 0.0
var _travelled: float = 0.0
var _lane: TelegraphLane = null
## Raiders ya golpeados en esta embestida (ids de instancia).
var _hit: Dictionary[int, bool] = {}


func scale_damage(multiplier: float) -> void:
	damage *= multiplier


func begin(target: Node3D) -> void:
	_target = target
	_step = Step.AIM
	_windup = maxf(windup * aggression_lerp(1.0, windup_at_full_aggression), lock_seconds + 0.1)
	_timer = _windup
	_from = boss.global_position
	_direction = LobsterAim.flat_direction(_from, _aim_point(), -boss.global_transform.basis.z)
	_hit.clear()
	_measure_run()
	# El carril dura todo el aviso: al clavarse (lock) queda lleno hasta el golpe.
	_lane = TelegraphLane.spawn(lane_scene, _from, _lane_end(), width, _timer,
			boss.telegraph_color)
	# El flanco que queda adelante se alterna de una embestida a la otra.
	boss.rig.side = -boss.rig.side
	boss.rig.set_pose(LobsterRig.Pose.SIDE)
	boss.rig.set_anger(0.6)
	boss.face_along(_direction)


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
			var t := 1.0 - clampf(_timer / maxf(skid_seconds, 0.01), 0.0, 1.0)
			# Frena de golpe: recorre casi todo el derrape al principio.
			boss.glide_to(_from + _direction * (_run + skid_distance * (1.0 - (1.0 - t) * (1.0 - t))))
			if _timer <= 0.0:
				_rest()
		Step.REST:
			return _timer <= 0.0
	return false


func cancel() -> void:
	if _lane != null and is_instance_valid(_lane):
		_lane.dismiss()
	_lane = null
	boss.face_along(Vector3.ZERO)
	boss.rig.set_dust(false)
	boss.rig.set_anger(0.0)
	boss.rig.set_pose(LobsterRig.Pose.STALK)


# --- privados ---------------------------------------------------------------------

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
	var wanted := clampf(to_target.dot(_direction) + overshoot, overshoot, length)
	_run = maxf(boss.clear_run(_from, _direction, wanted), 2.0)


func _lane_end() -> Vector3:
	return _from + _direction * (_run + skid_distance)


## El carril gira hacia el raider, hasta donde le da su velocidad de giro.
func _turn_lane(delta: float) -> void:
	var wanted := LobsterAim.flat_direction(_from, _aim_point(), _direction)
	var angle := _direction.signed_angle_to(wanted, Vector3.UP)
	var step := deg_to_rad(turn_degrees_per_second) * delta
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
	boss.glide_to(_from - _direction * backstep * smoothstep(0.0, 1.0, wound))


func _dash() -> void:
	_step = Step.DASH
	_travelled = -backstep
	boss.rig.set_pose(LobsterRig.Pose.DASH)
	boss.rig.set_dust(true)
	Sfx.play(dash_sfx)


func _tick_dash(delta: float) -> void:
	var before := boss.global_position
	_travelled = minf(_travelled + run_speed * delta, _run)
	boss.glide_to(_from + _direction * _travelled)
	var now := boss.global_position
	if boss.strike_along(before, now, width * 0.5, height_window, damage, _hit) > 0:
		boss.feel.shock(LobsterFeel.Shock.HEAVY, now)
	if _travelled >= _run:
		_step = Step.SKID
		_timer = skid_seconds
		boss.rig.set_pose(LobsterRig.Pose.SIDE)
		boss.rig.set_anger(0.0)
		if _lane != null and is_instance_valid(_lane):
			_lane.dismiss()
		_lane = null


func _rest() -> void:
	_step = Step.REST
	_timer = recover
	boss.face_along(Vector3.ZERO)
	boss.rig.set_dust(false)
	boss.rig.set_pose(LobsterRig.Pose.STALK)
