class_name SafeCircle
extends Node3D
## Círculo a salvo del pool: un anillo en el suelo con una columna de luz
## que marca dónde NO llega el Amanecer de Mythos. Aparece, espera y se va
## solo; quien lo pide solo dice dónde, de qué radio y por cuántos segundos.
## Los dos materiales de SafeCircle.tscn son locales a la escena, así cada
## instancia del pool anima su propia opacidad.
## Grupo "safe_circles" mientras está vivo: las zonas de fuego no nacen
## encima de uno (MythosZones) y Mythos los retira todos con dismiss().

const GROUP := &"safe_circles"

@export_group("Aspecto")
## Color del anillo y de la columna de luz.
@export var color: Color = Color(0.45, 0.95, 1.0)
## Opacidad del anillo del suelo (0-1).
@export_range(0.0, 1.0) var ring_alpha: float = 0.95
## Opacidad de la columna de luz (0-1).
@export_range(0.0, 1.0) var beam_alpha: float = 0.4
## Altura de la columna de luz, en metros.
@export var beam_height: float = 10.0
## Segundos que tarda en aparecer y en irse.
@export var fade_time: float = 0.25
## Metros sobre el suelo, para que el anillo no parpadee contra el terreno.
@export var lift: float = 0.12
## Segundos de un latido de la columna de luz.
@export var pulse_period: float = 0.7
## Cuánto baja la opacidad de la columna en cada latido (0 = no late).
@export_range(0.0, 1.0) var pulse_depth: float = 0.45

var _radius: float = 0.0
var _live: bool = false
var _tween: Tween = null

@onready var _ring: MeshInstance3D = $Ring
@onready var _beam: MeshInstance3D = $Beam


## Contrato de nodo del pool: sin animar nada del círculo anterior.
func pool_reset() -> void:
	_kill_tween()
	_live = false
	_radius = 0.0
	_set_alpha(0.0, 0.0)


## Muestra el círculo en `center` (un punto sobre el suelo) durante
## `seconds`; después se va solo.
func show_circle(center: Vector3, radius: float, seconds: float) -> void:
	_kill_tween()
	_live = true
	_radius = radius
	add_to_group(GROUP)
	global_position = center + Vector3.UP * lift
	_ring.scale = Vector3(radius, 1.0, radius)
	_beam.scale = Vector3(radius, beam_height, radius)
	_beam.position = Vector3(0.0, beam_height * 0.5, 0.0)
	_set_alpha(0.0, 0.0)
	_tween = create_tween()
	_tween.tween_method(_fade, 0.0, 1.0, fade_time)
	# Late hasta que se le acaba el tiempo.
	var beats := maxi(int(maxf(seconds - fade_time, 0.0) / maxf(pulse_period, 0.05)), 1)
	for i: int in beats:
		_tween.tween_method(_pulse, 0.0, 1.0, pulse_period)
	_tween.tween_callback(dismiss)


## Se va ya (terminó el ataque o murió el jefe). Uno que ya se fue no cambia.
func dismiss() -> void:
	if not _live:
		return
	_live = false
	remove_from_group(GROUP)
	_kill_tween()
	_tween = create_tween()
	_tween.tween_method(_fade, 1.0, 0.0, fade_time)
	_tween.tween_callback(_release)


## True si un disco de `radius` metros en `at` pisa algún círculo a salvo vivo.
static func overlaps_any(tree: SceneTree, at: Vector3, radius: float) -> bool:
	for node: Node in tree.get_nodes_in_group(GROUP):
		var circle := node as SafeCircle
		if circle == null:
			continue
		var offset := circle.global_position - at
		offset.y = 0.0
		var reach := radius + circle._radius
		if offset.length_squared() < reach * reach:
			return true
	return false


func _fade(amount: float) -> void:
	_set_alpha(ring_alpha * amount, beam_alpha * amount)


func _pulse(phase: float) -> void:
	var dip := 0.5 - 0.5 * cos(phase * TAU)
	_set_alpha(ring_alpha, beam_alpha * (1.0 - pulse_depth * dip))


func _set_alpha(ring: float, beam: float) -> void:
	var ring_material := _ring.material_override as StandardMaterial3D
	if ring_material != null:
		ring_material.albedo_color = Color(color.r, color.g, color.b, ring)
	var beam_material := _beam.material_override as StandardMaterial3D
	if beam_material != null:
		beam_material.albedo_color = Color(color.r, color.g, color.b, beam)


func _release() -> void:
	Pools.release(self)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
