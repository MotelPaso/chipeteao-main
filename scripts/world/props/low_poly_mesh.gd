class_name LowPolyMesh
extends RefCounted
## Arma una malla facetada con color de vértice a partir de piezas simples
## (caras, prismas entre dos anillos, cajas, copas). La usan los props que
## se construyen en código: el árbol hueco, los portales de piedra, los
## menhires, las ruinas y la vegetación del suelo.
##
## Cada cara lleva su propia normal (sombreado plano) y un brillo apenas
## distinto, que es lo que hace que se lean las aristas. El material es
## blanco y toma el color del vértice: así el infierno de Mythos sabe
## quemarlo (HellDressing reconoce un BaseMaterial3D con color de vértice).

## Material compartido de todo lo que arma esta clase.
const MATERIAL: StandardMaterial3D = preload("res://assets/materials/vertex_paint.tres")
## Cuánto varía el brillo de una cara a la siguiente (0 = todas iguales).
const FACE_SHADE: float = 0.09

var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _rng := RandomNumberGenerator.new()


## `seed_value` fija el brillo de cada cara: la misma semilla da la misma malla.
func _init(seed_value: int = 0) -> void:
	_rng.seed = seed_value


## Una cara triangular que mira hacia fuera del sólido cuyo interior
## contiene a `inside`.
func triangle(a: Vector3, b: Vector3, c: Vector3, color: Color, inside: Vector3) -> void:
	if (b - a).cross(c - a).length_squared() < 0.0000001:
		return
	_face(a, b, c, _shade(color), inside)


## Una cara de cuatro lados (a-b-c-d en orden alrededor de la cara).
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, inside: Vector3) -> void:
	triangle(a, b, c, color, inside)
	triangle(a, c, d, color, inside)


## Una losa: una cara de cuatro lados con un solo tono (un sillar, una losa
## del piso). quad() le daría un tono a cada mitad y se vería la diagonal.
func plate(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, inside: Vector3) -> void:
	var shaded := _shade(color)
	_face(a, b, c, shaded, inside)
	_face(a, c, d, shaded, inside)


## Un sillar: una caja de tamaño `size` centrada en el origen de `frame`,
## con las seis caras del mismo tono.
func block(frame: Transform3D, size: Vector3, color: Color) -> void:
	var half := size * 0.5
	var shaded := _shade(color)
	var corners := PackedVector3Array()
	for y: float in [-half.y, half.y]:
		for turn: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			corners.append(frame * Vector3(turn.x * half.x, y, turn.y * half.z))
	for side in 4:
		var next := (side + 1) % 4
		_face(corners[side], corners[next], corners[next + 4], shaded, frame.origin)
		_face(corners[side], corners[next + 4], corners[side + 4], shaded, frame.origin)
	for base: int in [0, 4]:
		_face(corners[base], corners[base + 1], corners[base + 2], shaded, frame.origin)
		_face(corners[base], corners[base + 2], corners[base + 3], shaded, frame.origin)


## Las caras laterales entre dos anillos con la misma cantidad de puntos
## (un tramo de tronco, un pilar): `lower` abajo y `upper` arriba.
func band(lower: PackedVector3Array, upper: PackedVector3Array, color: Color) -> void:
	var inside := Vector3.ZERO
	for point: Vector3 in lower:
		inside += point
	for point: Vector3 in upper:
		inside += point
	inside /= float(lower.size() + upper.size())
	var count := lower.size()
	for index in count:
		var next := (index + 1) % count
		quad(lower[index], lower[next], upper[next], upper[index], color, inside)


## Una tapa: el polígono `ring` cerrado en abanico hacia su centro, mirando
## lejos de `inside`.
func cap(ring: PackedVector3Array, color: Color, inside: Vector3) -> void:
	var middle := Vector3.ZERO
	for point: Vector3 in ring:
		middle += point
	middle /= float(ring.size())
	for index in ring.size():
		triangle(middle, ring[index], ring[(index + 1) % ring.size()], color, inside)


## Un anillo de `sides` puntos alrededor de `center`, en el plano horizontal,
## de radio `radius` (cada punto, entre 1 - `wobble` y 1 + `wobble` veces),
## girado `turn` radianes.
func ring(center: Vector3, radius: float, sides: int, turn: float = 0.0,
		wobble: float = 0.0) -> PackedVector3Array:
	var points := PackedVector3Array()
	for index in sides:
		var angle := turn + TAU * float(index) / float(sides)
		var reach := radius * (1.0 + _rng.randf_range(-wobble, wobble))
		points.append(center + Vector3(cos(angle) * reach, 0.0, sin(angle) * reach))
	return points


## Una caja de tamaño `size` centrada en el origen de `frame` (que la gira y
## la ubica), con las seis caras.
func box(frame: Transform3D, size: Vector3, color: Color) -> void:
	var half := size * 0.5
	var corners := PackedVector3Array()
	for y: float in [-half.y, half.y]:
		for turn: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			corners.append(frame * Vector3(turn.x * half.x, y, turn.y * half.z))
	var lower := corners.slice(0, 4)
	var upper := corners.slice(4, 8)
	band(lower, upper, color)
	cap(upper, color, frame.origin)
	cap(lower, color, frame.origin)


## Una copa: una esfera de pocas caras, de semiejes `radii`, con cada punto
## corrido hasta `wobble` veces su radio para que no sea una bola perfecta.
func blob(center: Vector3, radii: Vector3, color: Color, segments: int = 7, rings: int = 4,
		wobble: float = 0.14) -> void:
	var rows: Array[PackedVector3Array] = []
	for row in range(1, rings):
		var polar := PI * float(row) / float(rings)
		var points := PackedVector3Array()
		for index in segments:
			var angle := TAU * (float(index) + 0.5 * float(row % 2)) / float(segments)
			var reach := 1.0 + _rng.randf_range(-wobble, wobble)
			points.append(center + Vector3(sin(polar) * cos(angle) * radii.x,
					cos(polar) * radii.y, sin(polar) * sin(angle) * radii.z) * reach)
		rows.append(points)
	var top := center + Vector3.UP * radii.y
	var bottom := center - Vector3.UP * radii.y
	for index in segments:
		var next := (index + 1) % segments
		triangle(top, rows[0][index], rows[0][next], color, center)
		triangle(bottom, rows[rows.size() - 1][index], rows[rows.size() - 1][next], color, center)
	for row in rows.size() - 1:
		for index in segments:
			var next := (index + 1) % segments
			quad(rows[row][index], rows[row][next], rows[row + 1][next], rows[row + 1][index],
					color, center)


## `color` con el brillo al azar de una cara.
func _shade(color: Color) -> Color:
	var shaded := color * (1.0 + _rng.randf_range(-FACE_SHADE, FACE_SHADE))
	shaded.a = 1.0
	return shaded


## Agrega el triángulo a-b-c con el color ya elegido, mirando hacia fuera
## del sólido cuyo interior contiene a `inside`.
func _face(a: Vector3, b: Vector3, c: Vector3, shaded: Color, inside: Vector3) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 0.0000001:
		return
	normal = normal.normalized()
	# Godot dibuja la cara horaria: vista desde fuera, cross(b - a, c - a)
	# tiene que mirar hacia dentro.
	if normal.dot((a + b + c) / 3.0 - inside) > 0.0:
		var swap := b
		b = c
		c = swap
	else:
		normal = -normal
	for vertex: Vector3 in [a, b, c]:
		_vertices.append(vertex)
		_normals.append(normal)
		_colors.append(shaded)


## True si todavía no se le agregó ninguna cara.
func is_empty() -> bool:
	return _vertices.is_empty()


## Caras (triángulos) agregadas hasta ahora.
func face_count() -> int:
	return _vertices.size() / 3


## La malla con todo lo agregado hasta ahora.
func commit() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays())
	return mesh


## Los arreglos de superficie con todo lo agregado hasta ahora, para quien
## arma una malla de varias superficies.
func arrays() -> Array:
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = _vertices
	out[Mesh.ARRAY_NORMAL] = _normals
	out[Mesh.ARRAY_COLOR] = _colors
	return out


## Un MeshInstance3D con la malla y el material compartido, listo para colgar.
func instance(node_name: String) -> MeshInstance3D:
	var view := MeshInstance3D.new()
	view.name = node_name
	view.mesh = commit()
	view.material_override = MATERIAL
	return view
