class_name MythosStrafe
extends MythosMove
## Pasada de fuego: se aleja, marca una línea que cruza por donde va el
## raider y la recorre en vuelo rasante. Golpea a quien pille en la línea y
## deja una pared de fuego que parte la arena. Con agresividad da una segunda
## pasada, cruzada sobre la primera.
## Cada zona de la línea avisa desde que se marca y se enciende justo cuando
## Mythos pasa por encima.

enum Step { APPROACH, RUN, REST }

@export_group("Pasada")
## Largo de la línea, en metros (la mitad a cada lado del raider).
@export var length: float = 30.0
## Segundos de aviso, con agresividad 0: vuela hasta el inicio de la línea mientras se marca.
@export var windup: float = 1.1
## Multiplicador del aviso con agresividad 1 (nunca avisa menos que esto).
@export var windup_at_full_aggression: float = 0.8
## Metros por segundo del vuelo rasante.
@export var run_speed: float = 30.0
## Segundos que se adelanta al raider para trazar la línea.
@export var lead_seconds: float = 0.4
## Tope de ese adelanto, en metros, para un raider a velocidad base (crece si corre más rápido).
@export var max_lead: float = 4.0
## Grados que la línea se desvía, al azar, de la recta entre Mythos y el raider.
@export var angle_jitter_degrees: float = 35.0
## Daño del golpe al pasar, a cada raider dentro de una zona (valor base).
@export var damage: float = 38.0
## Metros sobre el suelo por encima de los cuales el golpe no alcanza.
@export var height_window: float = 1.8
## Segundos quieto después de la última pasada.
@export var recover: float = 0.6
## Sonido al empezar cada pasada (fila de Sfx.SOUND_LIBRARY).
@export var pass_sfx: StringName = &"fire_whoosh"

@export_group("Pared de fuego")
## Radio de cada zona de la línea, en metros.
@export var zone_radius: float = 2.4
## Metros entre el centro de una zona y la siguiente.
@export var spacing: float = 3.8
## Segundos que arde la pared.
@export var burn_seconds: float = 5.0
## Daño por segundo de cada zona (valor base).
@export var zone_dps: float = 22.0

@export_group("Segunda pasada")
## Agresividad (0-1) desde la que da una segunda pasada.
@export_range(0.0, 1.0) var second_pass_aggression: float = 0.6
## Grados entre la primera pasada y la segunda.
@export var second_pass_degrees: float = 70.0
## Multiplicador del aviso de la segunda pasada.
@export var second_pass_windup: float = 0.75

var _step: Step = Step.APPROACH
var _target: Node3D = null
var _timer: float = 0.0
var _approach_total: float = 0.0
var _passes_left: int = 0
var _from: Vector3 = Vector3.ZERO
var _start: Vector3 = Vector3.ZERO
var _direction: Vector3 = Vector3.FORWARD
var _run_length: float = 0.0
var _travelled: float = 0.0
## Zonas que salieron en esta pasada: su punto y los metros desde el inicio.
var _marks: Array[Vector3] = []
var _mark_at: PackedFloat32Array = PackedFloat32Array()
var _next_mark: int = 0


func scale_damage(multiplier: float) -> void:
	damage *= multiplier
	zone_dps *= multiplier


func begin(target: Node3D) -> void:
	_target = target
	_passes_left = 2 if boss.aggression >= second_pass_aggression else 1
	var to_target := target.global_position - boss.global_position
	to_target.y = 0.0
	var heading := to_target.normalized() if to_target.length_squared() > 0.01 \
			else Vector3.FORWARD
	_plan_pass(heading.rotated(Vector3.UP, deg_to_rad(
			randf_range(-angle_jitter_degrees, angle_jitter_degrees))),
			windup * aggression_lerp(1.0, windup_at_full_aggression))


func tick(delta: float) -> bool:
	match _step:
		Step.APPROACH:
			_timer -= delta
			var t := 1.0 - clampf(_timer / maxf(_approach_total, 0.01), 0.0, 1.0)
			boss.glide_to(_from.lerp(_start, t * t * (3.0 - 2.0 * t)))
			if _timer <= 0.0:
				_step = Step.RUN
				boss.rig.set_trail(true)
				boss.feel.shock(MythosFeel.Shock.LIGHT, boss.global_position)
				Sfx.play(pass_sfx)
		Step.RUN:
			_travelled = minf(_travelled + run_speed * delta, _run_length)
			boss.glide_to(_start + _direction * _travelled)
			while _next_mark < _marks.size() and _mark_at[_next_mark] <= _travelled:
				boss.strike_ground([_marks[_next_mark]], zone_radius, height_window, damage)
				_next_mark += 1
			if _travelled >= _run_length:
				_after_pass()
		Step.REST:
			_timer -= delta
			return _timer <= 0.0
	return false


func cancel() -> void:
	boss.rig.set_trail(false)
	boss.rig.set_pose(boss.rest_pose())


## Traza una pasada en la dirección `heading` y marca su pared de fuego:
## cada zona avisa hasta el momento en que Mythos va a pasar sobre ella.
func _plan_pass(heading: Vector3, warn: float) -> void:
	_passes_left -= 1
	var center := boss.global_position
	if is_instance_valid(_target) and _target.is_inside_tree():
		center = MythosBolts.predicted(_target, lead_seconds, max_lead)
	_start = boss.safe_point(center - heading * length * 0.5)
	var line := boss.safe_point(center + heading * length * 0.5) - _start
	line.y = 0.0
	_run_length = line.length()
	# El recorte a la arena puede torcer un poco la línea: vale la que quedó.
	_direction = line / _run_length if _run_length > 0.1 else heading
	_marks.clear()
	_mark_at.clear()
	for i: int in int(_run_length / maxf(spacing, 0.1)) + 1:
		var along := spacing * float(i)
		var at := boss.floor_point(_start + _direction * along)
		if boss.spawn_fire_zone(at, zone_radius, warn + along / maxf(run_speed, 0.1),
				burn_seconds, zone_dps, true):
			_marks.append(at)
			_mark_at.append(along)
	_next_mark = 0
	_travelled = 0.0
	_from = boss.global_position
	_approach_total = warn
	_timer = warn
	_step = Step.APPROACH
	boss.face_along(_direction)
	boss.rig.set_pose(MythosRig.Pose.GLIDE)
	boss.rig.gesture(&"screech")


func _after_pass() -> void:
	boss.rig.set_trail(false)
	if _passes_left > 0 and is_instance_valid(_target) and _target.is_inside_tree():
		var turn := deg_to_rad(second_pass_degrees) * (1.0 if randf() < 0.5 else -1.0)
		_plan_pass(_direction.rotated(Vector3.UP, turn),
				windup * aggression_lerp(1.0, windup_at_full_aggression) * second_pass_windup)
		return
	_step = Step.REST
	_timer = recover
	boss.face_along(Vector3.ZERO)
	boss.rig.set_pose(boss.rest_pose())
