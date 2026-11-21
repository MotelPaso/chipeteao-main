class_name FireZone
extends Node3D
## Zona de fuego del pool: se MARCA en el suelo (aviso), se enciende, daña a
## los raiders en pie que estén dentro y se apaga sola. La pide un jefe con
## mark(). Lleva su propio tick de daño, como AcidPool: no hay nadie detrás
## que la avance, y así nada queda en una lista que un cambio de etapa filtre.
##
## Nunca daña a la horda ni a un raider caído, y se apaga si un raider cae
## dentro o pegado a ella, para que se lo pueda reanimar.
## Grupo "fire_zones": el jefe cuenta las vivas contra su tope y las apaga
## todas al morir (extinguish).
## El disco escribe uniforms POR INSTANCIA de assets/shaders/fire_zone.gdshader
## (charge, burn, fade): el material de la escena se comparte sin duplicarlo.

enum Stage { IDLE, MARKED, BURNING, FADING }

const GROUP := &"fire_zones"

@export_group("Daño")
## Segundos entre aplicaciones de daño mientras arde.
@export var tick_interval: float = 0.5
## Metros sobre el suelo de la zona por encima de los cuales el fuego no alcanza (un salto lo cruza).
@export var height_window: float = 1.6
## Metros de margen alrededor de un raider caído: con uno más cerca que eso del borde, la zona se apaga.
@export var downed_clearance: float = 1.5

@export_group("Aspecto")
## Segundos que tarda en apagarse.
@export var fade_time: float = 0.6
## Segundos que tarda el aviso en volverse lava al encenderse.
@export var ignite_time: float = 0.25
## Metros sobre el suelo, para que el disco no parpadee contra el terreno.
@export var lift: float = 0.08
## Radio en metros para el que están pensadas las llamas de la escena; se escalan contra él.
@export var flames_reference_radius: float = 2.6

@export_group("Sonido")
## Sonido al encenderse (fila de Sfx.SOUND_LIBRARY).
@export var ignite_sfx: StringName = &"zone_ignite"

var _stage: Stage = Stage.IDLE
var _radius: float = 0.0
var _damage_per_second: float = 0.0
var _warn_seconds: float = 0.0
var _burn_seconds: float = 0.0
var _left: float = 0.0
var _tick_left: float = 0.0
var _burn_mix: float = 0.0
var _fade_tween: Tween = null

@onready var _disc: MeshInstance3D = $Disc
@onready var _flames: GPUParticles3D = $Flames


func _ready() -> void:
	add_to_group(GROUP)
	set_physics_process(false)


## Contrato del pool: zona nueva en cada adquisición.
func pool_reset() -> void:
	if not is_in_group(GROUP):
		add_to_group(GROUP)
	_kill_fade()
	_stage = Stage.IDLE
	_burn_mix = 0.0
	_flames.emitting = false
	_write_look(0.0, 0.0, 1.0)


## Marca la zona en `center`: `warn_seconds` de aviso y después
## `burn_seconds` ardiendo con `dps` de daño por segundo.
func mark(center: Vector3, radius: float, warn_seconds: float, burn_seconds: float,
		dps: float) -> void:
	_kill_fade()
	global_position = center + Vector3.UP * lift
	_radius = radius
	_damage_per_second = dps
	_warn_seconds = maxf(warn_seconds, 0.01)
	_burn_seconds = burn_seconds
	_left = _warn_seconds
	_burn_mix = 0.0
	_stage = Stage.MARKED
	_disc.scale = Vector3(radius, 1.0, radius)
	_flames.scale = Vector3.ONE * maxf(radius / maxf(flames_reference_radius, 0.01), 0.2)
	_flames.emitting = false
	_write_look(0.0, 0.0, 1.0)
	set_physics_process(true)


## True mientras la zona hace daño.
func is_burning() -> bool:
	return _stage == Stage.BURNING


## Radio de daño en metros (0 si la zona no está en uso).
func zone_radius() -> float:
	return _radius if _stage != Stage.IDLE else 0.0


## Se apaga ya, haya llegado o no a encenderse (muere el jefe, cae un raider
## dentro). Una zona que ya se está apagando no cambia.
func extinguish() -> void:
	if _stage == Stage.IDLE or _stage == Stage.FADING:
		return
	_stage = Stage.FADING
	_flames.emitting = false
	set_physics_process(false)
	_kill_fade()
	_fade_tween = create_tween()
	_fade_tween.tween_method(_set_fade, 1.0, 0.0, fade_time)
	_fade_tween.tween_callback(_release)


func _physics_process(delta: float) -> void:
	match _stage:
		Stage.MARKED:
			_left -= delta
			_write_look(1.0 - clampf(_left / _warn_seconds, 0.0, 1.0), 0.0, 1.0)
			if _left <= 0.0:
				_ignite()
		Stage.BURNING:
			_burn_mix = minf(_burn_mix + delta / maxf(ignite_time, 0.01), 1.0)
			_write_look(1.0, _burn_mix, 1.0)
			_left -= delta
			if _left <= 0.0 or _downed_raider_close():
				extinguish()
				return
			_tick_left -= delta
			if _tick_left <= 0.0:
				_tick_left = tick_interval
				_burn_raiders()


## El aviso terminó: la zona se enciende, salvo que haya un raider caído al
## lado (entonces se va sin arder).
func _ignite() -> void:
	if _downed_raider_close():
		extinguish()
		return
	_stage = Stage.BURNING
	_left = _burn_seconds
	# El primer golpe cae un tick después de encenderse, no en el mismo frame.
	_tick_left = tick_interval
	_flames.emitting = true
	Sfx.play(ignite_sfx)


## Raiders EN PIE dentro del disco y a su altura. Sin atacante: el fuego del
## suelo no tiene a quién devolverle las espinas ni el reflejo.
func _burn_raiders() -> void:
	var amount := _damage_per_second * tick_interval
	var radius_sq := _radius * _radius
	for body: Node3D in Coop.alive_players(get_tree()):
		var to_body := body.global_position - global_position
		if absf(to_body.y) > height_window:
			continue
		to_body.y = 0.0
		if to_body.length_squared() > radius_sq:
			continue
		var health := Health.find_in(body)
		if health != null and not health.is_dead:
			health.take_damage(amount)


## True si un raider caído queda dentro de la zona o a menos de
## downed_clearance de su borde.
func _downed_raider_close() -> bool:
	var reach := _radius + downed_clearance
	var reach_sq := reach * reach
	for node: Node in get_tree().get_nodes_in_group(&"downed_players"):
		var body := node as Node3D
		if body == null or not body.is_inside_tree():
			continue
		var to_body := body.global_position - global_position
		to_body.y = 0.0
		if to_body.length_squared() <= reach_sq:
			return true
	return false


func _write_look(charge: float, burn: float, fade: float) -> void:
	_disc.set_instance_shader_parameter(&"charge", charge)
	_disc.set_instance_shader_parameter(&"burn", burn)
	_disc.set_instance_shader_parameter(&"fade", fade)


func _set_fade(value: float) -> void:
	_disc.set_instance_shader_parameter(&"fade", value)


func _release() -> void:
	_stage = Stage.IDLE
	Pools.release(self)


func _kill_fade() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
