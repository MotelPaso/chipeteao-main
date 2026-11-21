class_name FireWave
extends Node3D
## Onda de fuego del pool: un anillo de llamas que se abre a ras de suelo
## desde un punto (o se cierra hacia él), siguiendo el relieve. Daña UNA vez
## a cada raider en pie que el anillo alcance por debajo de su altura: se
## esquiva SALTANDO justo cuando pasa. Con daño 0 es solo un efecto (así la
## usan las cinemáticas de Mythos, con una instancia propia y open()).
## El anillo son tramos de llama (el cuadro de 1 x 1 del nodo Wall de
## FireWave.tscn) en un MultiMesh propio de cada instancia.
## Grupo "fire_waves": el jefe las apaga todas al morir (dissipate).

const GROUP := &"fire_waves"
const AttackFloor := preload("res://scripts/fx/attack_floor.gd")

@export_group("Aspecto")
## Tramos de llama del anillo.
@export var segments: int = 56
## Alto de las llamas, en metros.
@export var wall_height: float = 2.4
## Cuánto se pisan dos tramos vecinos (1 = se tocan justo).
@export var segment_overlap: float = 1.2
## Segundos que tarda en apagarse al llegar a su radio máximo.
@export var fade_time: float = 0.3
## Metros detrás del anillo a los que lo sigue una estela de llamas bajas (0 = sin estela).
@export var wake_distance: float = 1.3
## Alto de esa estela, en veces el de las llamas del anillo.
@export var wake_height: float = 0.5

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
var _fade_tween: Tween = null

@onready var _wall: MultiMeshInstance3D = $Wall


func _ready() -> void:
	# Cada onda del pool mueve sus propios tramos: copia el MultiMesh de la
	# escena (que trae la malla del tramo) en vez de compartirlo.
	var multimesh := _wall.multimesh.duplicate() as MultiMesh
	# La mitad de los tramos es el anillo y la otra mitad, su estela.
	multimesh.instance_count = maxi(segments, 3) * 2
	# El anillo llega lejos de su centro: una caja fija evita que se recorte.
	multimesh.custom_aabb = AABB(Vector3(-80.0, -12.0, -80.0), Vector3(160.0, 30.0, 160.0))
	_wall.multimesh = multimesh
	set_physics_process(false)


## Contrato de nodo del pool: onda nueva en cada adquisición.
func pool_reset() -> void:
	_kill_fade()
	_live = false
	_hit.clear()
	_wall.visible = false
	set_physics_process(false)


## Saca del pool una onda y la abre desde `center` (un punto sobre el suelo):
## nace con `start_radius` y avanza `speed` m/s hasta `end_radius` (si es
## menor que el de partida, el anillo se CIERRA hacia el centro). Golpea con
## `damage` a los raiders en pie que estén a menos de `height_window` metros
## del suelo cuando el anillo (de `band` metros de ancho) les pasa.
static func spawn(scene: PackedScene, center: Vector3, start_radius: float,
		end_radius: float, speed: float, damage: float, height_window: float, band: float,
		attacker: Node3D) -> FireWave:
	var wave := Pools.acquire_scene(scene) as FireWave
	if wave != null:
		wave.open(center, start_radius, end_radius, speed, damage, height_window, band,
				attacker)
	return wave


## Se apaga ya (murió el jefe). Una que ya se está apagando no cambia.
func dissipate() -> void:
	if not _live:
		return
	_live = false
	set_physics_process(false)
	_kill_fade()
	_fade_tween = create_tween()
	_fade_tween.tween_method(_set_fade, 1.0, 0.0, fade_time)
	_fade_tween.tween_callback(_release)


## Abre ESTA onda desde `center`, con lo mismo que pide spawn(). Para una
## onda que ya está en el árbol y no salió del pool.
func open(center: Vector3, start_radius: float, end_radius: float, speed: float,
		damage: float, height_window: float, band: float, attacker: Node3D) -> void:
	_kill_fade()
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
	_wall.visible = true
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	_radius = move_toward(_radius, _end_radius, _speed * delta)
	_place_segments()
	if _damage > 0.0:
		_hit_raiders()
	if is_equal_approx(_radius, _end_radius):
		dissipate()


## Reparte los tramos: el anillo y, detrás de él según hacia dónde avanza,
## su estela de llamas bajas.
func _place_segments() -> void:
	var count := maxi(segments, 3)
	_place_ring(0, count, _radius, wall_height)
	var behind := -wake_distance if _end_radius >= _radius else wake_distance
	var wake_radius := _radius + behind
	_place_ring(count, count, wake_radius,
			wall_height * wake_height if wake_distance > 0.0 and wake_radius > 0.3 else 0.0)


## Un anillo de `count` tramos de `height` metros de alto y `radius` de
## radio, desde el tramo `first`, cada uno a la altura del suelo en su punto.
func _place_ring(first: int, count: int, radius: float, height: float) -> void:
	var multimesh := _wall.multimesh
	var width := TAU * radius / float(count) * segment_overlap
	var center := global_position
	for index: int in count:
		var angle := TAU * float(index) / float(count)
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		var at := outward * radius
		at.y = AttackFloor.height(self, center + at) - center.y + height * 0.5
		var tangent := Vector3(-outward.z, 0.0, outward.x)
		multimesh.set_instance_transform(first + index, Transform3D(
				Basis(tangent * width, Vector3.UP * height, outward), at))


## Golpea una vez a cada raider en pie que el anillo alcanza sin saltar,
## en el suelo por el que corre (una onda que cruza el cauce pasa bajo el
## tablero del puente sin tocar a quien está arriba).
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
		var ground := AttackFloor.height(self, Vector3(body.global_position.x, center.y,
				body.global_position.z))
		if absf(body.global_position.y - ground) > _height_window:
			continue
		_hit[id] = true
		var health := Health.find_in(body)
		if health != null and not health.is_dead:
			health.take_damage(_damage, false,
					_attacker if is_instance_valid(_attacker) else null)


func _set_fade(amount: float) -> void:
	_wall.set_instance_shader_parameter(&"fade", amount)


func _release() -> void:
	_wall.visible = false
	remove_from_group(GROUP)
	Pools.release(self)


func _kill_fade() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
