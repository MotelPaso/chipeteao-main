class_name LightShafts
extends Node3D
## Los rayos de luz que bajan de la superficie del mar en el Cementerio de
## barcos: `count` rayos altos y finos, al azar dentro de `radius` metros,
## todos inclinados hacia el mismo sol. Cada rayo son dos cuadros cruzados
## (se ven con cuerpo desde cualquier lado) y todos van en UNA malla, así se
## dibujan de una vez. El brillo, las franjas y el apagado cerca de la cámara
## los hace assets/shaders/light_shaft.gdshader.

const SHADER: Shader = preload("res://assets/shaders/light_shaft.gdshader")

@export_group("Rayos")
## Semilla del reparto: la misma semilla da los mismos rayos.
@export var shape_seed: int = 0
## Cantidad de rayos.
@export_range(1, 64) var count: int = 16
## Radio en el que se reparten los rayos, en metros.
@export var radius: float = 85.0
## Alto de donde bajan los rayos, en metros.
@export var top_height: float = 46.0
## Ancho mínimo de un rayo al llegar a la arena, en metros.
@export var bottom_width_min: float = 1.5
## Ancho máximo de un rayo al llegar a la arena, en metros.
@export var bottom_width_max: float = 4.0
## Cuántas veces más ancho es un rayo arriba que abajo (mínimo).
@export var top_widen_min: float = 1.6
## Cuántas veces más ancho es un rayo arriba que abajo (máximo).
@export var top_widen_max: float = 2.6

@export_group("Sol")
## Inclinación de los rayos respecto de la vertical, en grados (la del nodo Sun de la escena es 26).
@export_range(0.0, 45.0) var sun_tilt_degrees: float = 24.0
## Hacia dónde se inclinan los rayos, en grados alrededor de la vertical (0 = +X, crece hacia +Z; el nodo Sun de la escena alumbra desde 55).
@export var sun_yaw_degrees: float = 55.0
## Cuánto puede desviarse cada rayo de la inclinación común, en grados.
@export_range(0.0, 15.0) var tilt_variance_degrees: float = 3.0

@export_group("Luz")
## Color de la luz.
@export var tint: Color = Color(0.75, 0.92, 1.0)
## Brillo de los rayos (0-1); tiene que ser sutil.
@export_range(0.0, 1.0) var intensity: float = 0.16
## Velocidad de las franjas que corren por el rayo, en vueltas por segundo.
@export_range(0.0, 2.0) var shimmer_speed: float = 0.12
## Metros a la cámara por debajo de los cuales un rayo se apaga.
@export var near_fade: float = 9.0

var _rng := RandomNumberGenerator.new()
var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _uvs := PackedVector2Array()


func _ready() -> void:
	_rng.seed = shape_seed
	for index in count:
		_add_shaft()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"tint", tint)
	material.set_shader_parameter(&"intensity", intensity)
	material.set_shader_parameter(&"shimmer_speed", shimmer_speed)
	material.set_shader_parameter(&"near_fade", near_fade)
	var view := MeshInstance3D.new()
	view.name = "Shafts"
	view.mesh = mesh
	view.material_override = material
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(view)


## Un rayo: dos cuadros cruzados de la arena a `top_height`, inclinados al sol.
func _add_shaft() -> void:
	var spot := sqrt(_rng.randf()) * radius
	var around := _rng.randf() * TAU
	var foot := Vector3(cos(around) * spot, 0.0, sin(around) * spot)
	var variance := deg_to_rad(tilt_variance_degrees)
	var tilt := deg_to_rad(sun_tilt_degrees) + _rng.randf_range(-variance, variance)
	var yaw := deg_to_rad(sun_yaw_degrees) + _rng.randf_range(-variance, variance) * 2.0
	var up := Vector3(sin(tilt) * cos(yaw), cos(tilt), sin(tilt) * sin(yaw))
	var top := foot + up * (top_height / up.y)
	var low_width := _rng.randf_range(bottom_width_min, bottom_width_max)
	var high_width := low_width * _rng.randf_range(top_widen_min, top_widen_max)
	var phase := Color(_rng.randf(), 0.0, 0.0)
	var first := Vector3(cos(around * 3.1), 0.0, sin(around * 3.1))
	# Los dos lados son horizontales: así las cuatro puntas de abajo quedan en la arena.
	var sides: Array[Vector3] = [first, Vector3.UP.cross(first).normalized()]
	for side: Vector3 in sides:
		_add_quad(foot, top, side, low_width, high_width, phase)


## Un cuadro de `foot` a `top`, abierto a lo largo de `side`.
func _add_quad(foot: Vector3, top: Vector3, side: Vector3, low_width: float, high_width: float,
		phase: Color) -> void:
	var corners: Array[Vector3] = [foot - side * low_width * 0.5, foot + side * low_width * 0.5,
			top + side * high_width * 0.5, top - side * high_width * 0.5]
	var uvs: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0),
			Vector2(0.0, 1.0)]
	var normal := side.cross(top - foot).normalized()
	for index: int in [0, 1, 2, 0, 2, 3]:
		_vertices.append(corners[index])
		_normals.append(normal)
		_colors.append(phase)
		_uvs.append(uvs[index])
