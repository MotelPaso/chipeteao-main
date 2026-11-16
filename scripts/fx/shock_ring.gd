class_name ShockRing
extends Node3D
## Onda de choque del pool: un anillo de agua y tierra levantada que se abre a
## ras de suelo desde un punto, siguiendo el relieve. Daña UNA vez a cada
## raider en pie que el anillo alcance por debajo de su altura: se esquiva
## SALTANDO justo cuando pasa. Con daño 0 es solo un efecto (el barrido del
## Coletazo de la Langosta Azul).
## El anillo son tramos (el cuadro de 1 x 1 del nodo Crest de ShockRing.tscn)
## en un MultiMesh propio de cada instancia.
## Grupo "shock_rings": quien las lanza las apaga todas al morir (dissipate).

const GROUP := &"shock_rings"

@export_group("Aspecto")
## Tramos del anillo.
@export var segments: int = 48
## Alto de la cresta, en metros.
@export var crest_height: float = 1.3
## Cuánto se pisan dos tramos vecinos (1 = se tocan justo).
@export var segment_overlap: float = 1.25
## Segundos que tarda en apagarse al llegar a su radio máximo.
@export var fade_time: float = 0.25

var _radius: float = 0.0
var _end_radius: float = 0.0
var _speed: float = 0.0
var _damage: float = 0.0
var _height_window: float = 0.0
var _band: float = 0.0
var _attacker: Node3D = null
var _live: bool = false
## Raiders que esta onda ya golpeó (ids de instancia).
var _hit: Dictionary[int, bool] = {}
var _terrain: Terrain = null
var _fade_tween: Tween = null

@onready var _crest: MultiMeshInstance3D = $Crest


func _ready() -> void:
	# Cada onda del pool mueve sus propios tramos: copia el MultiMesh de la
	# escena (que trae la malla del tramo) en vez de compartirlo.
	var multimesh := _crest.multimesh.duplicate() as MultiMesh
	multimesh.instance_count = maxi(segments, 3)
	# El anillo llega lejos de su centro: una caja fija evita que se recorte.
	multimesh.custom_aabb = AABB(Vector3(-60.0, -12.0, -60.0), Vector3(120.0, 26.0, 120.0))
	_crest.multimesh = multimesh
	set_physics_process(false)


## Contrato de nodo del pool: onda nueva en cada adquisición.
func pool_reset() -> void:
	_kill_fade()
	_live = false
	_hit.clear()
	_attacker = null
	_crest.visible = false
	set_physics_process(false)


## Saca del pool una onda y la abre desde `center` (un punto sobre el suelo):
## nace con `start_radius` y avanza `speed` m/s hasta `end_radius`. Golpea con
## `damage` a los raiders en pie que estén a menos de `height_window` metros
## del suelo cuando el anillo (de `band` metros de ancho) les pasa.
static func spawn(scene: PackedScene, center: Vector3, start_radius: float,
		end_radius: float, speed: float, damage: float, height_window: float, band: float,
		attacker: Node3D) -> ShockRing:
	var ring := Pools.acquire_scene(scene) as ShockRing
	if ring != null:
		ring.open(center, start_radius, end_radius, speed, damage, height_window, band,
				attacker)
	return ring


## Abre ESTA onda desde `center`, con lo mismo que pide spawn().
func open(center: Vector3, start_radius: float, end_radius: float, speed: float,
		damage: float, height_window: float, band: float, attacker: Node3D) -> void:
	_kill_fade()
	_terrain = Terrain.find(get_tree())
	_radius = start_radius
	_end_radius = end_radius
	_speed = absf(speed)
	_damage = damage
	_height_window = height_window
	_band = band
	_attacker = attacker
	_hit.clear()
	_live = true
	add_to_group(GROUP)
	global_transform = Transform3D(Basis.IDENTITY, center)
	_set_fade(1.0)
	_place_segments()
	_crest.visible = true
	set_physics_process(true)


## Se apaga ya (murió quien la lanzó). Una que ya se está apagando no cambia.
func dissipate() -> void:
	if not _live:
		return
	_live = false
	set_physics_process(false)
	_kill_fade()
	_fade_tween = create_tween()
	_fade_tween.tween_method(_set_fade, 1.0, 0.0, fade_time)
	_fade_tween.tween_callback(_release)


func _physics_process(delta: float) -> void:
	_radius = move_toward(_radius, _end_radius, _speed * delta)
	_place_segments()
	if _damage > 0.0:
		_hit_raiders()
	if is_equal_approx(_radius, _end_radius):
		dissipate()


## Reparte los tramos en el anillo, cada uno a la altura del suelo en su punto.
func _place_segments() -> void:
	var multimesh := _crest.multimesh
	var count := multimesh.instance_count
	var width := TAU * _radius / float(count) * segment_overlap
	var center := global_position
	for index: int in count:
		var angle := TAU * float(index) / float(count)
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		var at := outward * _radius
		var ground := center.y
		if _terrain != null:
			ground = _terrain.height_at(center.x + at.x, center.z + at.z)
		at.y = ground - center.y + crest_height * 0.5
		var tangent := Vector3(-outward.z, 0.0, outward.x)
		multimesh.set_instance_transform(index, Transform3D(
				Basis(tangent * width, Vector3.UP * crest_height, outward), at))


## Golpea una vez a cada raider en pie que el anillo alcanza sin saltar.
func _hit_raiders() -> void:
	var center := global_position
	for body: Node3D in Coop.alive_players(get_tree()):
		var id := body.get_instance_id()
		if _hit.has(id):
			continue
		var offset := body.global_position - center
		offset.y = 0.0
		if absf(offset.length() - _radius) > _band * 0.5:
			continue
		var ground := center.y
		if _terrain != null:
			ground = _terrain.height_at(body.global_position.x, body.global_position.z)
		if body.global_position.y - ground > _height_window:
			continue
		_hit[id] = true
		var health := Health.find_in(body)
		if health != null and not health.is_dead:
			health.take_damage(_damage, false,
					_attacker if is_instance_valid(_attacker) else null)


func _set_fade(amount: float) -> void:
	_crest.set_instance_shader_parameter(&"fade", amount)


func _release() -> void:
	_crest.visible = false
	remove_from_group(GROUP)
	Pools.release(self)


func _kill_fade() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
