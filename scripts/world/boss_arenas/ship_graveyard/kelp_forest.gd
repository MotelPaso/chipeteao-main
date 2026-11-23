class_name KelpForest
extends Node3D
## Un bosque de algas altas en el borde de la arena del Cementerio de barcos.
## El nodo va en el origen de la arena y planta las algas en un sector de
## anillo a su alrededor. Todas comparten una misma hoja (un tallo en cruz
## con hojas alternadas) dibujada con un MultiMesh; el vaivén lo hace el
## shader kelp_sway.gdshader con TIME, sin costo por cuadro en el script.
##
## Es decorado: no tiene colisión ni proyecta sombra.

const SHADER: Shader = preload("res://assets/shaders/kelp_sway.gdshader")
## Metros que el pie del alga baja bajo la arena, para que una loma no lo deje en el aire.
const SINK: float = 0.5
## Tramos del tallo, de abajo hacia arriba.
const STEM_SEGMENTS: int = 8
## Medio ancho del tallo en la base y en la punta, en anchos del alga.
const STEM_HALF_BASE: float = 0.1
const STEM_HALF_TIP: float = 0.04
## Hojas a lo largo del tallo, y en qué fracción de la altura empiezan y terminan.
const LEAVES: int = 12
const LEAF_FROM: float = 0.14
const LEAF_TO: float = 0.96
## Giro entre una hoja y la siguiente (ángulo áureo), para que rodeen el tallo.
const LEAF_TURN: float = 2.39996
## Lo que sube una hoja de la base a la punta y su medio ancho, en altos del alga.
const LEAF_RISE: float = 0.045
const LEAF_HALF_WIDTH: float = 0.012
## Largo de una hoja en anchos del alga (al azar entre mínimo y máximo), y
## cuánto se acortan las de la punta (1 = igual que las de abajo).
const LEAF_LENGTH_MIN: float = 0.35
const LEAF_LENGTH_MAX: float = 0.5
const LEAF_TIP_SHRINK: float = 0.6
## Radianes al azar que se corre el giro de cada hoja.
const LEAF_TURN_JITTER: float = 0.3
## Cuánto más clara es una hoja que el tallo a su misma altura (0-1).
const LEAF_BRIGHTEN: float = 0.12

@export_group("Lugar")
## Distancia mínima al nodo de un alga, en metros.
@export var inner_radius: float = 58.0
## Distancia máxima al nodo de un alga, en metros.
@export var outer_radius: float = 92.0
## Ángulo donde empieza el sector, en grados (0 = +X, crece hacia +Z).
@export var arc_from_degrees: float = -30.0
## Ángulo donde termina el sector, en grados.
@export var arc_to_degrees: float = 48.0
## Semilla de la forma: la misma semilla da el mismo bosque.
@export var shape_seed: int = 0

@export_group("Forma")
## Cantidad de algas.
@export_range(0, 2000) var count: int = 260
## Alto mínimo de un alga, en metros (las del borde de adentro).
@export var height_min: float = 9.0
## Alto máximo de un alga, en metros (las del borde de afuera).
@export var height_max: float = 24.0
## Ancho mínimo de un alga de hoja a hoja, en metros.
@export var width_min: float = 1.2
## Ancho máximo de un alga de hoja a hoja, en metros.
@export var width_max: float = 2.2
## Cuánto pesa la distancia al alto (0 = alto al azar, 1 = solo la distancia).
@export_range(0.0, 1.0) var height_by_distance: float = 0.7

@export_group("Movimiento")
## Metros que se corre la punta del alga más alta.
@export var sway_amount: float = 1.6
## Velocidad del vaivén, en radianes por segundo.
@export var sway_speed: float = 0.55
## Variación al azar del vaivén entre algas (0 = todas igual).
@export_range(0.0, 1.0) var sway_variation: float = 0.25

@export_group("Colores")
## Color del pie del alga.
@export var base_color: Color = Color(0.12, 0.3, 0.16)
## Color de la punta del alga.
@export var tip_color: Color = Color(0.5, 0.66, 0.25)
## Color que tiñe todo el bosque (blanco = sin cambio).
@export var tint: Color = Color(1.0, 1.0, 1.0)

var _rng := RandomNumberGenerator.new()
var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _uvs := PackedVector2Array()


func _ready() -> void:
	_rng.seed = shape_seed
	var view := MultiMeshInstance3D.new()
	view.name = "Kelp"
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"sway_amount", sway_amount)
	material.set_shader_parameter(&"sway_speed", sway_speed)
	material.set_shader_parameter(&"tint", tint)
	view.material_override = material
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = _build_blade()
	multimesh.instance_count = count
	view.custom_aabb = _plant(multimesh)
	view.multimesh = multimesh
	add_child(view)


## Ubica cada alga en el sector y devuelve la caja que ocupa el bosque,
## con margen para el vaivén (el shader mueve las puntas fuera de la malla).
func _plant(multimesh: MultiMesh) -> AABB:
	var box := AABB()
	var inner_sq := inner_radius * inner_radius
	var outer_sq := outer_radius * outer_radius
	var span := maxf(outer_radius - inner_radius, 0.001)
	for index: int in count:
		# La raíz del área reparte las algas parejo por superficie.
		var reach := sqrt(lerpf(inner_sq, outer_sq, _rng.randf()))
		var angle := deg_to_rad(lerpf(arc_from_degrees, arc_to_degrees, _rng.randf()))
		var outward := clampf((reach - inner_radius) / span, 0.0, 1.0)
		var grow := lerpf(_rng.randf(), outward, height_by_distance)
		var height := lerpf(height_min, height_max, grow)
		var width := _rng.randf_range(width_min, width_max)
		var foot := Vector3(cos(angle) * reach, -SINK, sin(angle) * reach)
		var basis := Basis(Vector3.UP, _rng.randf() * TAU) \
				* Basis.from_scale(Vector3(width, height + SINK, width))
		multimesh.set_instance_transform(index, Transform3D(basis, foot))
		var sway_scale := height / maxf(height_max, 0.001) \
				* (1.0 + _rng.randf_range(-sway_variation, sway_variation))
		multimesh.set_instance_custom_data(index, Color(_rng.randf(), sway_scale, 0.0, 0.0))
		var stalk := AABB(foot - Vector3(width, 0.0, width), Vector3(width * 2.0, height + SINK, width * 2.0))
		box = stalk if index == 0 else box.merge(stalk)
	var margin := sway_amount * (1.0 + sway_variation) * 1.2
	return box.grow(margin)


## La hoja compartida, de alto 1 y ancho 1, con el pie en y = 0.
func _build_blade() -> ArrayMesh:
	_vertices.clear()
	_normals.clear()
	_colors.clear()
	_uvs.clear()
	# El tallo: dos cintas en cruz, para que no desaparezca visto de canto.
	for side: Vector3 in [Vector3.RIGHT, Vector3.BACK]:
		for segment: int in STEM_SEGMENTS:
			var low := float(segment) / float(STEM_SEGMENTS)
			var high := float(segment + 1) / float(STEM_SEGMENTS)
			var low_half := side * lerpf(STEM_HALF_BASE, STEM_HALF_TIP, low)
			var high_half := side * lerpf(STEM_HALF_BASE, STEM_HALF_TIP, high)
			var a := Vector3.UP * low - low_half
			var b := Vector3.UP * low + low_half
			var c := Vector3.UP * high + high_half
			var d := Vector3.UP * high - high_half
			_triangle(a, b, c, 0.0)
			_triangle(a, c, d, 0.0)
	for leaf: int in LEAVES:
		_leaf(leaf)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Una hoja que sale del tallo hacia afuera y un poco hacia arriba, con la
## cara vertical: una punta, dos secciones anchas y otra punta.
func _leaf(leaf: int) -> void:
	var at := lerpf(LEAF_FROM, LEAF_TO, float(leaf) / float(LEAVES - 1))
	var turn := float(leaf) * LEAF_TURN + _rng.randf_range(-LEAF_TURN_JITTER, LEAF_TURN_JITTER)
	var out := Vector3(cos(turn), 0.0, sin(turn))
	var length := _rng.randf_range(LEAF_LENGTH_MIN, LEAF_LENGTH_MAX) * lerpf(1.0, LEAF_TIP_SHRINK, at)
	var base := Vector3.UP * at + out * STEM_HALF_TIP
	var points: Array[Vector3] = []
	for step: float in [0.35, 0.7]:
		points.append(base + out * length * step + Vector3.UP * LEAF_RISE * step)
	var tip := base + out * length + Vector3.UP * LEAF_RISE
	var width := Vector3.UP * LEAF_HALF_WIDTH
	_triangle(base, points[0] - width, points[0] + width, LEAF_BRIGHTEN)
	_triangle(points[0] - width, points[1] - width, points[1] + width, LEAF_BRIGHTEN)
	_triangle(points[0] - width, points[1] + width, points[0] + width, LEAF_BRIGHTEN)
	_triangle(points[1] - width, tip, points[1] + width, LEAF_BRIGHTEN)


## Agrega el triángulo a-b-c con su normal plana; el color va del pie a la
## punta según la altura de cada vértice, más `brighten` en las hojas.
## Godot dibuja de frente la cara horaria: su normal es cross(c - a, b - a).
func _triangle(a: Vector3, b: Vector3, c: Vector3, brighten: float) -> void:
	var normal := (c - a).cross(b - a).normalized()
	for vertex: Vector3 in [a, b, c]:
		var along := clampf(vertex.y, 0.0, 1.0)
		var color := base_color.lerp(tip_color, clampf(along + brighten, 0.0, 1.0))
		_vertices.append(vertex)
		_normals.append(normal)
		# El shader usa el color tal cual: se pasa a lineal aquí.
		_colors.append(color.srgb_to_linear())
		_uvs.append(Vector2(0.0, along))
