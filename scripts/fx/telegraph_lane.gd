class_name TelegraphLane
extends Node3D
## Carril de aviso del pool: una hilera de galones sobre el suelo, de un punto
## a otro, que marca por dónde va a pasar un golpe (la Embestida de la
## Langosta Azul). Sigue el relieve, se LLENA desde el origen hasta la punta
## durante la carga (lo lleno se lee como cuenta regresiva) y quien avisa
## puede moverlo mientras apunta (aim) y cambiarle el color cuando se clava
## (lock). Solo es visual: el momento del golpe y el daño los decide quien lo
## llama. Vuelve solo al pool al terminar la carga.
## Los tramos son planos de 1 x 1 en un MultiMesh propio de cada instancia;
## el color y la opacidad de cada tramo van en el color de su instancia.
## Grupo "telegraph_lanes": quien los lanza los apaga al morir (dismiss).

const GROUP := &"telegraph_lanes"

@export_group("Aspecto")
## Largo de cada tramo, en metros.
@export var segment_length: float = 1.6
## Tramos que puede tener como mucho (el carril más largo mide esto por segment_length).
@export var max_segments: int = 20
## Metros sobre el suelo, para que no parpadee contra el terreno.
@export var lift: float = 0.07
## Opacidad de los tramos que la carga todavía no llenó (0-1).
@export_range(0.0, 1.0) var empty_alpha: float = 0.22
## Opacidad de los tramos ya llenos (0-1).
@export_range(0.0, 1.0) var full_alpha: float = 0.75
## Segundos que tarda en desvanecerse al terminar.
@export var fade_time: float = 0.18

var _from: Vector3 = Vector3.ZERO
var _to: Vector3 = Vector3.ZERO
var _width: float = 1.0
var _duration: float = 1.0
var _elapsed: float = 0.0
var _color: Color = Color.WHITE
var _fade: float = 1.0
var _live: bool = false
var _terrain: Terrain = null
var _fade_tween: Tween = null

@onready var _strip: MultiMeshInstance3D = $Strip


func _ready() -> void:
	# Cada carril del pool mueve sus propios tramos: copia el MultiMesh de la
	# escena en vez de compartirlo.
	var multimesh := _strip.multimesh.duplicate() as MultiMesh
	multimesh.instance_count = maxi(max_segments, 1)
	multimesh.visible_instance_count = 0
	multimesh.custom_aabb = AABB(Vector3(-60.0, -12.0, -60.0), Vector3(120.0, 26.0, 120.0))
	_strip.multimesh = multimesh
	set_process(false)


## Contrato de nodo del pool: carril nuevo en cada adquisición.
func pool_reset() -> void:
	_kill_fade()
	_live = false
	_strip.visible = false
	set_process(false)


## Saca del pool un carril de `from` a `to`, de `width` metros de ancho, que
## se llena en `seconds` con el color `color`.
static func spawn(scene: PackedScene, from: Vector3, to: Vector3, width: float,
		seconds: float, color: Color) -> TelegraphLane:
	var lane := Pools.acquire_scene(scene) as TelegraphLane
	if lane != null:
		lane.show_lane(from, to, width, seconds, color)
	return lane


## Muestra ESTE carril, con lo mismo que pide spawn().
func show_lane(from: Vector3, to: Vector3, width: float, seconds: float, color: Color) -> void:
	_kill_fade()
	_terrain = Terrain.find(get_tree())
	_from = from
	_to = to
	_width = width
	_duration = maxf(seconds, 0.05)
	_elapsed = 0.0
	_color = color
	_fade = 1.0
	_live = true
	add_to_group(GROUP)
	global_transform = Transform3D.IDENTITY
	_place()
	_strip.visible = true
	set_process(true)


## Corre el carril a otro tramo sin cortar su carga (un aviso que apunta).
func aim(from: Vector3, to: Vector3) -> void:
	_from = from
	_to = to


## El aviso se clavó: cambia de color y queda lleno hasta el golpe.
func lock(color: Color) -> void:
	_color = color
	_elapsed = maxf(_elapsed, _duration * 0.999)
	_duration = INF


## Se apaga ya. Uno que ya se está apagando no cambia.
func dismiss() -> void:
	if not _live:
		return
	_live = false
	_kill_fade()
	_fade_tween = create_tween()
	_fade_tween.tween_method(_set_fade, 1.0, 0.0, fade_time)
	_fade_tween.tween_callback(_release)


func _process(delta: float) -> void:
	if _live:
		_elapsed += delta
		if _elapsed >= _duration:
			dismiss()
	_place()


## Reparte los tramos entre los dos puntos, cada uno a la altura del suelo.
func _place() -> void:
	var multimesh := _strip.multimesh
	var span := _to - _from
	span.y = 0.0
	var length := span.length()
	var count := clampi(ceili(length / maxf(segment_length, 0.1)), 0, multimesh.instance_count)
	multimesh.visible_instance_count = count
	if count == 0:
		return
	var forward := span / length
	var right := Vector3(-forward.z, 0.0, forward.x)
	var piece := length / float(count)
	var filled := clampf(_elapsed / _duration, 0.0, 1.0) if _duration != INF else 1.0
	for index: int in count:
		var at := _from + forward * (piece * (float(index) + 0.5))
		at.y = (_terrain.height_at(at.x, at.z) if _terrain != null else _from.y) + lift
		multimesh.set_instance_transform(index, Transform3D(
				Basis(right * _width, Vector3.UP, forward * piece), at))
		var reached := float(index) / float(count) < filled
		multimesh.set_instance_color(index,
				Color(_color, (full_alpha if reached else empty_alpha) * _fade))


func _set_fade(amount: float) -> void:
	_fade = amount


func _release() -> void:
	_strip.visible = false
	set_process(false)
	remove_from_group(GROUP)
	Pools.release(self)


func _kill_fade() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null
