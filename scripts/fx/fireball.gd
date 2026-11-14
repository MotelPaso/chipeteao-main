class_name Fireball
extends Node3D
## Bola de fuego del pool. Sale de un punto, vuela en arco hasta su marca y
## estalla: daña a los raiders EN PIE dentro del radio que se avisó. En el
## camino no choca con nada ni daña a nadie. Quien la lanza pone el aviso en
## el suelo (el color es suyo) y puede pedir que le avisen cuando cae, para
## dejar fuego donde cayó.
## Grupo "fireballs" mientras vuela: el jefe las apaga todas al morir (fizzle).

const GROUP := &"fireballs"

@export_group("Vuelo")
## Radio visible de la bola, en metros.
@export var ball_radius: float = 1.3
## Altura del arco, en metros por cada metro de recorrido.
@export var arc_per_meter: float = 0.3
## Altura mínima del arco, en metros.
@export var min_arc: float = 3.0
## Altura máxima del arco, en metros.
@export var max_arc: float = 14.0
## Vueltas por segundo que gira la bola.
@export var spin_turns: float = 1.2
## Tamaño del resplandor alrededor de la bola, en veces su radio.
@export var glow_scale: float = 1.7

@export_group("Estallido")
## Temblor de cámara del estallido.
@export var shake_strength: float = 0.28
## Segundos que dura ese temblor.
@export var shake_seconds: float = 0.35
## Sonido del estallido (fila de Sfx.SOUND_LIBRARY).
@export var blast_sfx: StringName = &"fireball_blast"

var _from: Vector3 = Vector3.ZERO
var _to: Vector3 = Vector3.ZERO
var _arc: float = 0.0
var _seconds: float = 1.0
var _elapsed: float = 0.0
var _radius: float = 0.0
var _damage: float = 0.0
var _height_window: float = 0.0
var _attacker: EnemyBase = null
var _on_land: Callable = Callable()
var _flying: bool = false

@onready var _ball: MeshInstance3D = $Ball
@onready var _glow: MeshInstance3D = $Glow
@onready var _trail: GPUParticles3D = $Trail


func _ready() -> void:
	set_physics_process(false)


## Contrato de nodo del pool: sin vuelo ni llamada pendientes.
func pool_reset() -> void:
	_flying = false
	_on_land = Callable()
	_attacker = null
	set_physics_process(false)


## Lanza la bola de `from` a `to` (un punto sobre el suelo) en `seconds`. Al
## caer daña con `damage` a los raiders en pie a menos de `radius` metros y
## por debajo de `height_window`, a nombre de `attacker`, y llama a `on_land`
## con el punto donde cayó.
func launch(from: Vector3, to: Vector3, radius: float, seconds: float, damage: float,
		height_window: float, attacker: EnemyBase, on_land: Callable = Callable()) -> void:
	_from = from
	_to = to
	_radius = radius
	_seconds = maxf(seconds, 0.05)
	_damage = damage
	_height_window = height_window
	_attacker = attacker
	_on_land = on_land
	_elapsed = 0.0
	_arc = clampf(from.distance_to(to) * arc_per_meter, min_arc, max_arc)
	_flying = true
	add_to_group(GROUP)
	global_position = from
	_ball.scale = Vector3.ONE * ball_radius
	_glow.scale = Vector3.ONE * ball_radius * glow_scale
	_glow.set_instance_shader_parameter(&"charge", 1.0)
	_trail.restart()
	_trail.emitting = true
	set_physics_process(true)


## Se apaga en el aire sin dañar a nadie (murió quien la lanzó).
func fizzle() -> void:
	if _flying:
		_finish()


func _physics_process(delta: float) -> void:
	if not _flying:
		return
	_elapsed += delta
	var t := clampf(_elapsed / _seconds, 0.0, 1.0)
	global_position = _from.lerp(_to, t) + Vector3.UP * _arc * 4.0 * t * (1.0 - t)
	_ball.rotate_x(spin_turns * TAU * delta)
	if t >= 1.0:
		_explode()


func _explode() -> void:
	var spots: Array[Vector3] = [_to]
	if is_instance_valid(_attacker) and _attacker.is_inside_tree():
		_attacker.damage_players_in_discs(spots, _radius, _height_window, _damage, _attacker)
	if _on_land.is_valid():
		_on_land.call(_to)
	var burst := Pools.acquire_scene(Pools.EMBER_BURST_SCENE) as EmberBurst
	if burst != null:
		burst.play(_to, _radius)
	Juice.shake(shake_strength, shake_seconds)
	Sfx.play(blast_sfx)
	_finish()


func _finish() -> void:
	_flying = false
	_trail.emitting = false
	remove_from_group(GROUP)
	set_physics_process(false)
	Pools.release(self)
