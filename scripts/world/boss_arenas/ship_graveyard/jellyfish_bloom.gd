class_name JellyfishBloom
extends Node3D
## Un grupo suelto de medusas grandes que flotan en una caja centrada en el
## nodo. Todas comparten una malla (una campana abierta abajo y seis
## tentáculos) dibujada con un MultiMesh; el shader jellyfish.gdshader las
## hace latir, subir y bajar y derivar con TIME, sin costo por cuadro en el
## script, y siguen aunque el mundo esté congelado.
##
## Es decorado: sin colisión ni sombra. No escales el nodo: la deriva va en
## metros del mundo.

const SHADER: Shader = preload("res://assets/shaders/jellyfish.gdshader")
## Lados de la campana y anillos de la cúpula al borde.
const BELL_SIDES: int = 8
const BELL_RINGS: int = 3
## Alto de la cúpula, en radios de campana (1 = media esfera).
const BELL_HEIGHT: float = 0.8
## Tentáculos, a qué radio cuelgan, cuánto bajan y en cuántos tramos.
const TENTACLES: int = 6
const TENTACLE_RADIUS: float = 0.55
const TENTACLE_LENGTH: float = 2.5
const TENTACLE_SEGMENTS: int = 3
## Medio ancho de un tentáculo arriba y en la punta, en radios de campana.
const TENTACLE_HALF_TOP: float = 0.09
const TENTACLE_HALF_TIP: float = 0.02
## Cuánto se cierran los tentáculos hacia el eje al bajar (0 = rectos).
const TENTACLE_GATHER: float = 0.35

@export_group("Forma")
## Cantidad de medusas.
@export_range(0, 200) var count: int = 14
## Tamaño de la caja donde flotan, en metros, centrada en el nodo.
@export var spread: Vector3 = Vector3(26, 10, 26)
## Radio mínimo de la campana, en metros.
@export var size_min: float = 1.2
## Radio máximo de la campana, en metros.
@export var size_max: float = 2.6
## Semilla de la forma: la misma semilla da el mismo grupo.
@export var shape_seed: int = 0

@export_group("Colores")
## Color del borde que brilla.
@export var glow_color: Color = Color(0.55, 0.9, 1.0)
## Color del centro de la campana.
@export var core_color: Color = Color(0.95, 0.6, 0.9)
## Opacidad del borde de la campana (0-1).
@export_range(0.0, 1.0) var alpha: float = 0.55
## Brillo: más de 1 las hace resaltar contra el agua.
@export_range(0.0, 4.0) var brightness: float = 1.4

@export_group("Movimiento")
## Velocidad del latido, en radianes por segundo.
@export var pulse_speed: float = 1.6
## Cuánto se abre la campana al latir, en fracción del radio.
@export_range(0.0, 0.5) var pulse_amount: float = 0.14
## Metros que sube y baja cada medusa.
@export var bob_height: float = 0.8
## Velocidad del sube y baja, en radianes por segundo.
@export var bob_speed: float = 0.35
## Radio del círculo que recorre a la deriva, en metros.
@export var drift_radius: float = 1.5
## Velocidad de la deriva, en radianes por segundo.
@export var drift_speed: float = 0.12
## Cuánto se mecen las puntas de los tentáculos, en radios de campana.
@export var tentacle_sway: float = 0.35
## Velocidad del vaivén de los tentáculos, en radianes por segundo.
@export var tentacle_speed: float = 1.1

var _rng := RandomNumberGenerator.new()
var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _uvs := PackedVector2Array()


func _ready() -> void:
	_rng.seed = shape_seed
	var view := MultiMeshInstance3D.new()
	view.name = "Jellyfish"
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	view.material_override = _make_material()
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = _build_jellyfish()
	multimesh.instance_count = count
	var half := spread * 0.5
	for index: int in count:
		var size := _rng.randf_range(size_min, size_max)
		var spot := Vector3(_rng.randf_range(-half.x, half.x), _rng.randf_range(-half.y, half.y),
				_rng.randf_range(-half.z, half.z))
		var basis := Basis(Vector3.UP, _rng.randf() * TAU) * Basis.from_scale(Vector3.ONE * size)
		multimesh.set_instance_transform(index, Transform3D(basis, spot))
		# La deriva va hacia un lado o el otro, nunca casi quieta.
		var drift := _rng.randf_range(0.65, 1.0) if _rng.randf() < 0.5 else _rng.randf_range(0.0, 0.35)
		multimesh.set_instance_custom_data(index, Color(_rng.randf(), _rng.randf_range(0.6, 1.4),
				drift, _rng.randf_range(0.8, 1.2)))
	view.multimesh = multimesh
	# El shader mueve las medusas fuera de su lugar: la caja cubre la deriva.
	var reach := half + Vector3.ONE * (size_max * (TENTACLE_LENGTH + 1.0) \
			+ (absf(drift_radius) + absf(bob_height)) * 1.4)
	view.custom_aabb = AABB(-reach, reach * 2.0)
	add_child(view)


func _make_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"glow_color", glow_color)
	material.set_shader_parameter(&"core_color", core_color)
	material.set_shader_parameter(&"alpha", alpha)
	material.set_shader_parameter(&"brightness", brightness)
	material.set_shader_parameter(&"pulse_speed", pulse_speed)
	material.set_shader_parameter(&"pulse_amount", pulse_amount)
	material.set_shader_parameter(&"bob_height", bob_height)
	material.set_shader_parameter(&"bob_speed", bob_speed)
	material.set_shader_parameter(&"drift_radius", drift_radius)
	material.set_shader_parameter(&"drift_speed", drift_speed)
	material.set_shader_parameter(&"tentacle_sway", tentacle_sway)
	material.set_shader_parameter(&"tentacle_speed", tentacle_speed)
	return material


## La malla de una medusa de radio 1: la campana con el borde en y = 0 y los
## tentáculos colgando debajo.
func _build_jellyfish() -> ArrayMesh:
	_vertices.clear()
	_normals.clear()
	_colors.clear()
	_uvs.clear()
	var top := Vector3.UP * BELL_HEIGHT
	var rows: Array[PackedVector3Array] = []
	for row: int in range(1, BELL_RINGS + 1):
		var polar := PI * 0.5 * float(row) / float(BELL_RINGS)
		var points := PackedVector3Array()
		for side: int in BELL_SIDES:
			var angle := TAU * float(side) / float(BELL_SIDES)
			points.append(Vector3(sin(polar) * cos(angle), cos(polar) * BELL_HEIGHT,
					sin(polar) * sin(angle)))
		rows.append(points)
	for side: int in BELL_SIDES:
		var next := (side + 1) % BELL_SIDES
		_triangle(top, rows[0][side], rows[0][next], 1.0)
		for row: int in rows.size() - 1:
			_triangle(rows[row][side], rows[row + 1][side], rows[row + 1][next], 1.0)
			_triangle(rows[row][side], rows[row + 1][next], rows[row][next], 1.0)
	for tentacle: int in TENTACLES:
		_tentacle(TAU * (float(tentacle) + 0.5) / float(TENTACLES))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Una cinta que cuelga del borde interior de la campana en `angle`, con la
## cara mirando hacia afuera y cerrándose un poco hacia el eje al bajar.
func _tentacle(angle: float) -> void:
	var out := Vector3(cos(angle), 0.0, sin(angle))
	var across := Vector3(-out.z, 0.0, out.x)
	var previous := PackedVector3Array()
	for step: int in TENTACLE_SEGMENTS + 1:
		var down := float(step) / float(TENTACLE_SEGMENTS)
		var centre := out * TENTACLE_RADIUS * (1.0 - TENTACLE_GATHER * down) \
				+ Vector3.DOWN * TENTACLE_LENGTH * down
		var half := across * lerpf(TENTACLE_HALF_TOP, TENTACLE_HALF_TIP, down)
		var pair := PackedVector3Array([centre - half, centre + half])
		if step > 0:
			var above := float(step - 1) / float(TENTACLE_SEGMENTS)
			_triangle(previous[0], previous[1], pair[1], 0.0,
					PackedFloat32Array([above, above, down]))
			_triangle(previous[0], pair[1], pair[0], 0.0, PackedFloat32Array([above, down, down]))
		previous = pair


## Agrega el triángulo a-b-c. `bell` va en COLOR.r y `masks` (uno por
## vértice) en COLOR.a: cuánto bajó por el tentáculo. Godot dibuja de frente
## la cara horaria: su normal es cross(c - a, b - a), y se da vuelta para que
## mire lejos del eje (y hacia arriba en la cúpula).
func _triangle(a: Vector3, b: Vector3, c: Vector3, bell: float,
		masks: PackedFloat32Array = PackedFloat32Array([0.0, 0.0, 0.0])) -> void:
	var points: Array[Vector3] = [a, b, c]
	var order: Array[int] = [0, 1, 2]
	var normal := (c - a).cross(b - a).normalized()
	var centre := (a + b + c) / 3.0
	if normal.dot(Vector3(centre.x, maxf(centre.y, 0.0) * bell, centre.z)) < 0.0:
		order = [0, 2, 1]
		normal = -normal
	for index: int in order:
		_vertices.append(points[index])
		_normals.append(normal)
		_colors.append(Color(bell, 0.0, 0.0, masks[index]))
		_uvs.append(Vector2(0.0, points[index].y))
