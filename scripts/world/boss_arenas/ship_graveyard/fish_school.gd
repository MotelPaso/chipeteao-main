class_name FishSchool
extends Node3D
## Un cardumen de peces chicos que da vueltas alrededor del nodo, en una
## elipse horizontal a la altura del nodo. Todos comparten una malla (un
## rombo con cola) dibujada con un MultiMesh; el shader fish_school.gdshader
## los mueve con TIME, sin costo por cuadro en el script, y sigue aunque el
## mundo esté congelado.
##
## Es decorado: sin colisión ni sombra. No escales ni gires el nodo en X/Z:
## la caja que evita que lo recorten se arma con la elipse sin girar.

const SHADER: Shader = preload("res://assets/shaders/fish_school.gdshader")
## Puntos del cuerpo del pez, en metros (nariz hacia +X).
const NOSE: Vector3 = Vector3(0.27, 0.0, 0.0)
const BACK: Vector3 = Vector3(0.02, 0.085, 0.0)
const BELLY: Vector3 = Vector3(0.02, -0.065, 0.0)
const FLANK: float = 0.055
const REAR: Vector3 = Vector3(-0.13, 0.0, 0.0)
## Cola y aleta del lomo, en metros.
const TAIL_TOP: Vector3 = Vector3(-0.25, 0.08, 0.0)
const TAIL_BOTTOM: Vector3 = Vector3(-0.25, -0.07, 0.0)
const TAIL_NOTCH: Vector3 = Vector3(-0.21, 0.0, 0.0)
const FIN_FRONT: Vector3 = Vector3(0.04, 0.08, 0.0)
const FIN_BACK: Vector3 = Vector3(-0.08, 0.06, 0.0)
const FIN_TOP: Vector3 = Vector3(-0.06, 0.14, 0.0)
## Margen de la caja de recorte, en metros, sobre la elipse y la altura.
const CULL_MARGIN: float = 2.0

@export_group("Forma")
## Cantidad de peces.
@export_range(0, 1000) var count: int = 70
## Tamaño mínimo de un pez (1 = medio metro de largo).
@export var fish_scale_min: float = 1.4
## Tamaño máximo de un pez.
@export var fish_scale_max: float = 2.2
## Semilla de la forma: la misma semilla da el mismo cardumen.
@export var shape_seed: int = 0

@export_group("Recorrido")
## Radios de la elipse en X y en Z, en metros.
@export var loop_radius: Vector2 = Vector2(14, 9)
## Vueltas por segundo; negativo da la vuelta al revés.
@export var loop_speed: float = 0.035
## Alto total del cardumen, en metros (cada pez a una altura al azar).
@export var height_spread: float = 3.0
## Fracción de la vuelta que ocupa el cardumen (0-1; 1 = un anillo entero).
@export_range(0.0, 1.0) var school_length: float = 0.3
## Variación del radio entre peces (0.2 = entre 0.8 y 1.2 veces el radio).
@export_range(0.0, 0.5) var radius_variation: float = 0.2
## Variación de la velocidad entre peces. Con más de 0.05 el cardumen se
## desarma en un anillo en pocos minutos.
@export_range(0.0, 0.5) var speed_variation: float = 0.03
## Metros que sube y baja cada pez.
@export var bob_height: float = 0.35
## Velocidad del sube y baja, en radianes por segundo.
@export var bob_speed: float = 0.9

@export_group("Cola")
## Radianes que gira la punta de la cola en cada aletazo.
@export var wiggle_angle: float = 0.45
## Velocidad del aletazo, en radianes por segundo.
@export var wiggle_speed: float = 9.0

@export_group("Colores")
## Color del lomo.
@export var body_color: Color = Color(0.75, 0.85, 0.95)
## Color de la panza.
@export var belly_color: Color = Color(1.0, 0.75, 0.35)

var _rng := RandomNumberGenerator.new()
var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()


func _ready() -> void:
	_rng.seed = shape_seed
	var view := MultiMeshInstance3D.new()
	view.name = "Fish"
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.material_override = _make_material()
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = _build_fish()
	multimesh.instance_count = count
	for index: int in count:
		var size := _rng.randf_range(fish_scale_min, fish_scale_max)
		multimesh.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3.ONE * size),
				Vector3.ZERO))
		multimesh.set_instance_custom_data(index, Color(
				fposmod(_rng.randf() * school_length, 1.0),
				1.0 + _rng.randf_range(-radius_variation, radius_variation),
				_rng.randf_range(-0.5, 0.5) * height_spread,
				1.0 + _rng.randf_range(-speed_variation, speed_variation)))
	view.multimesh = multimesh
	# El shader ubica a los peces: la caja cubre toda la elipse.
	var reach := Vector3(absf(loop_radius.x), 0.0, absf(loop_radius.y)) * (1.0 + radius_variation)
	reach.y = height_spread * 0.5 + absf(bob_height)
	reach += Vector3.ONE * CULL_MARGIN
	view.custom_aabb = AABB(-reach, reach * 2.0)
	add_child(view)


func _make_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"loop_radius", loop_radius)
	material.set_shader_parameter(&"loop_speed", loop_speed)
	material.set_shader_parameter(&"bob_height", bob_height)
	material.set_shader_parameter(&"bob_speed", bob_speed)
	material.set_shader_parameter(&"wiggle_angle", wiggle_angle)
	material.set_shader_parameter(&"wiggle_speed", wiggle_speed)
	material.set_shader_parameter(&"body_color", body_color)
	material.set_shader_parameter(&"belly_color", belly_color)
	return material


## La malla de un pez: un rombo de cuatro caras por lado y una cola en V,
## con COLOR.a de 0 en la nariz a 1 en la punta de la cola.
func _build_fish() -> ArrayMesh:
	_vertices.clear()
	_normals.clear()
	_colors.clear()
	var ring: Array[Vector3] = [BACK, Vector3(BACK.x, 0.0, FLANK), BELLY,
			Vector3(BACK.x, 0.0, -FLANK)]
	for side: int in ring.size():
		var next := (side + 1) % ring.size()
		_triangle(NOSE, ring[side], ring[next])
		_triangle(REAR, ring[next], ring[side])
	_triangle(REAR, TAIL_TOP, TAIL_NOTCH)
	_triangle(REAR, TAIL_NOTCH, TAIL_BOTTOM)
	_triangle(FIN_FRONT, FIN_BACK, FIN_TOP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Agrega el triángulo a-b-c mirando hacia fuera del centro del pez. Godot
## dibuja de frente la cara horaria: su normal es cross(c - a, b - a).
func _triangle(a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (c - a).cross(b - a).normalized()
	if normal.dot(a + b + c) < 0.0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	var length := NOSE.x - TAIL_TOP.x
	for vertex: Vector3 in [a, b, c]:
		_vertices.append(vertex)
		_normals.append(normal)
		_colors.append(Color(1.0, 1.0, 1.0, clampf((NOSE.x - vertex.x) / length, 0.0, 1.0)))
