class_name FireTornado
extends Node3D
## Tornado de fuego del pool. Primero se FORMA (aviso: un remolino pálido que
## crece, sin dañar), después gira y quema a los raiders en pie que toque, y
## al final se deshace solo. Puede perseguir al raider más cercano (cambia de
## rumbo de a poco, así se lo puede torear), avanzar en línea o en curva, o
## girar alrededor de un punto mientras se le acerca (orbit: la jaula).
## Lleva su propio tick de daño, como FireZone. Nunca daña a un raider caído
## y se deshace si se le acerca, para que se lo pueda reanimar. El brillo del
## suelo marca su radio de daño.
## Grupo "fire_tornados": el jefe los deshace todos al morir (dissipate).

enum Stage { IDLE, FORMING, SPINNING, FADING }

const GROUP := &"fire_tornados"

@export_group("Daño")
## Segundos entre aplicaciones de daño.
@export var tick_interval: float = 0.4
## Metros sobre el suelo por encima de los cuales no alcanza (alto a propósito: no se salta).
@export var height_window: float = 6.0
## Metros de margen alrededor de un raider caído: más cerca que eso, el tornado se deshace.
@export var downed_clearance: float = 2.0

@export_group("Persecución")
## Segundos entre una elección de raider y la siguiente.
@export var retarget_seconds: float = 0.6
## Rapidez con que cambia de rumbo, por segundo (bajo = gira de a poco y se lo puede torear).
@export var steer_rate: float = 2.0

@export_group("Aspecto")
## Altura del embudo, en metros.
@export var funnel_height: float = 14.0
## Ancho de la boca del embudo, en veces el radio de daño.
@export var funnel_width: float = 1.6
## Segundos que tarda en deshacerse.
@export var fade_time: float = 0.7
## Opacidad del brillo del suelo que marca el radio de daño (0-1).
@export_range(0.0, 1.0) var ground_alpha: float = 0.6
## Color de ese brillo.
@export var ground_color: Color = Color(1.0, 0.45, 0.08)
## Sonido al terminar de formarse (fila de Sfx.SOUND_LIBRARY).
@export var roar_sfx: StringName = &"fire_tornado"

var _stage: Stage = Stage.IDLE
var _radius: float = 0.0
var _dps: float = 0.0
var _speed: float = 0.0
var _chase: bool = true
var _heading: Vector3 = Vector3.ZERO
var _turn_rate: float = 0.0
var _velocity: Vector3 = Vector3.ZERO
## En órbita (orbit): el punto alrededor del que gira, los radianes por
## segundo, los metros por segundo que se acerca y hasta dónde llega.
var _orbiting: bool = false
var _orbit_center: Vector3 = Vector3.ZERO
var _orbit_speed: float = 0.0
var _orbit_closing: float = 0.0
var _orbit_min: float = 0.0
var _warn_total: float = 1.0
## Segundos que gira una vez formado.
var _life: float = 0.0
var _left: float = 0.0
var _tick_left: float = 0.0
var _retarget_left: float = 0.0
var _target: Node3D = null
var _terrain: Terrain = null
var _fade_tween: Tween = null

@onready var _funnel: MeshInstance3D = $Funnel
@onready var _core: MeshInstance3D = $Core
@onready var _ground: MeshInstance3D = $Ground
@onready var _embers: GPUParticles3D = $Embers


func _ready() -> void:
	set_physics_process(false)


## Contrato de nodo del pool: tornado nuevo en cada adquisición.
func pool_reset() -> void:
	_kill_fade()
	_stage = Stage.IDLE
	_target = null
	_velocity = Vector3.ZERO
	_orbiting = false
	_embers.emitting = false
	_set_form(0.0)
	set_physics_process(false)


## Arranca en `at` (un punto sobre el suelo): se forma durante `warn_seconds`
## y después gira `life_seconds` quemando `dps` por segundo a quien toque
## dentro de `radius`. Con `chase` persigue al raider más cercano a `speed`
## m/s; sin él avanza hacia `heading` y tuerce `turn_rate` radianes por segundo.
func start(at: Vector3, radius: float, warn_seconds: float, life_seconds: float, dps: float,
		speed: float, chase: bool = true, heading: Vector3 = Vector3.ZERO,
		turn_rate: float = 0.0) -> void:
	_kill_fade()
	_terrain = Terrain.find(get_tree())
	_radius = radius
	_dps = dps
	_speed = speed
	_chase = chase
	_heading = Vector3(heading.x, 0.0, heading.z).normalized()
	_turn_rate = turn_rate
	_velocity = Vector3.ZERO
	_orbiting = false
	_warn_total = maxf(warn_seconds, 0.01)
	_life = maxf(life_seconds, 0.0)
	_left = _warn_total
	_tick_left = tick_interval
	_retarget_left = 0.0
	_target = null
	_stage = Stage.FORMING
	add_to_group(GROUP)
	global_position = _on_ground(at)
	var mouth := radius * funnel_width
	_funnel.scale = Vector3(mouth, funnel_height, mouth)
	_funnel.position = Vector3(0.0, funnel_height * 0.5, 0.0)
	_core.scale = Vector3(mouth * 0.5, funnel_height * 0.92, mouth * 0.5)
	_core.position = Vector3(0.0, funnel_height * 0.46, 0.0)
	_ground.scale = Vector3(radius, 1.0, radius)
	_embers.emitting = false
	_set_form(0.0)
	set_physics_process(true)


## Después de start(): en vez de perseguir o avanzar, gira alrededor de
## `center` a `angular_speed` radianes por segundo (el signo es el sentido)
## mientras se le acerca `closing_speed` metros por segundo, hasta quedar a
## `min_distance` metros.
func orbit(center: Vector3, angular_speed: float, closing_speed: float,
		min_distance: float) -> void:
	_orbiting = true
	_orbit_center = center
	_orbit_speed = angular_speed
	_orbit_closing = closing_speed
	_orbit_min = min_distance


## Radio de daño en metros (0 si no está en uso).
func tornado_radius() -> float:
	return _radius if _stage != Stage.IDLE else 0.0


## Se deshace ya (murió el jefe, un raider cayó a su lado). Uno que ya se
## está deshaciendo no cambia.
func dissipate() -> void:
	if _stage == Stage.IDLE or _stage == Stage.FADING:
		return
	_stage = Stage.FADING
	_embers.emitting = false
	set_physics_process(false)
	_kill_fade()
	_fade_tween = create_tween()
	_fade_tween.tween_method(_set_form, 1.0, 0.0, fade_time)
	_fade_tween.tween_callback(_release)


func _physics_process(delta: float) -> void:
	_left -= delta
	if _stage == Stage.FORMING:
		_set_form(0.55 * (1.0 - clampf(_left / _warn_total, 0.0, 1.0)))
		if _left <= 0.0:
			_stage = Stage.SPINNING
			_left = _life
			_embers.emitting = true
			_set_form(1.0)
			Sfx.play(roar_sfx)
		return
	if _left <= 0.0 or _downed_raider_close():
		dissipate()
		return
	_move(delta)
	_tick_left -= delta
	if _tick_left <= 0.0:
		_tick_left = tick_interval
		_burn_raiders()


## Un paso de órbita, de persecución o de rumbo fijo, siempre a ras de suelo.
func _move(delta: float) -> void:
	if _orbiting:
		var arm := global_position - _orbit_center
		arm.y = 0.0
		var distance := maxf(arm.length() - _orbit_closing * delta,
				minf(_orbit_min, arm.length()))
		arm = arm.normalized().rotated(Vector3.UP, _orbit_speed * delta) * distance
		global_position = _on_ground(_orbit_center + arm)
		return
	var wanted := _heading * _speed
	if _chase:
		_retarget_left -= delta
		if _retarget_left <= 0.0 or not is_instance_valid(_target) \
				or not _target.is_in_group(&"player"):
			_retarget_left = retarget_seconds
			_target = Coop.nearest_player(get_tree(), global_position)
		if _target != null:
			var to_target := _target.global_position - global_position
			to_target.y = 0.0
			wanted = to_target.normalized() * _speed
	elif _turn_rate != 0.0:
		_heading = _heading.rotated(Vector3.UP, _turn_rate * delta)
		wanted = _heading * _speed
	_velocity = _velocity.lerp(wanted, 1.0 - exp(-steer_rate * delta))
	global_position = _on_ground(global_position + _velocity * delta)


## Raiders EN PIE dentro del radio. Sin atacante, como el fuego del suelo.
func _burn_raiders() -> void:
	var amount := _dps * tick_interval
	for body: Node3D in Coop.alive_players(get_tree()):
		var to_body := body.global_position - global_position
		if absf(to_body.y) > height_window:
			continue
		to_body.y = 0.0
		if to_body.length_squared() > _radius * _radius:
			continue
		var health := Health.find_in(body)
		if health != null and not health.is_dead:
			health.take_damage(amount)


func _downed_raider_close() -> bool:
	var reach := _radius + downed_clearance
	for node: Node in get_tree().get_nodes_in_group(&"downed_players"):
		var body := node as Node3D
		if body == null or not body.is_inside_tree():
			continue
		var to_body := body.global_position - global_position
		to_body.y = 0.0
		if to_body.length_squared() <= reach * reach:
			return true
	return false


func _on_ground(point: Vector3) -> Vector3:
	if _terrain != null:
		point.y = _terrain.height_at(point.x, point.z)
	return point


## Cuánto se ve: 0 invisible, 1 formado del todo.
func _set_form(amount: float) -> void:
	_funnel.set_instance_shader_parameter(&"form", amount)
	_core.set_instance_shader_parameter(&"form", amount)
	var material := _ground.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = Color(ground_color.r, ground_color.g, ground_color.b,
				ground_alpha * amount)


func _release() -> void:
	_stage = Stage.IDLE
	remove_from_group(GROUP)
	Pools.release(self)


func _kill_fade() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
