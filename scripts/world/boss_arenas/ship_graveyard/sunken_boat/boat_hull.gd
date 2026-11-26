class_name BoatHull
extends RefCounted
## El casco de madera de un naufragio (SunkenBoat): la forma del casco, el
## forro exterior e interior tabla por tabla, la borda, los agujeros, el
## espejo de popa, la cubierta y los palos. Se crea con `.new()`; los valores
## de diseño los pasa SunkenBoat, que es quien los exporta.
##
## Espacio del casco: la quilla en y = 0, la proa hacia +X, la manga por Z.
## `frame` lo lleva al espacio del prop.

## Cortes a lo largo del casco.
const STATIONS: int = 12
## Tablas por banda, de la quilla a la borda.
const STRAKES: int = 6
## Qué tan aguda es la proa (más alto = proa más llena).
const BOW_POWER: float = 2.2
## Cuánto sube la borda en las puntas, como fracción del alto.
const SHEER: float = 0.12
## Lados de un palo (mástil, bauprés, remo).
const POST_SIDES: int = 6

## Del espacio del casco al del prop.
var frame := Transform3D.IDENTITY
var half_length: float = 1.0
var beam: float = 1.0
var depth: float = 1.0
## Ancho del espejo de popa como fracción de la manga (0 = popa aguda).
var stern_fill: float = 0.6
## Tramo a lo largo de X que se construye.
var x_from: float = -1.0
var x_to: float = 1.0
var plank_thickness: float = 0.14
var rot_chance: float = 0.18
var dark_color := Color(0.30, 0.22, 0.16)
var light_color := Color(0.42, 0.32, 0.22)
var rot_color := Color(0.24, 0.28, 0.22)

var _rng: RandomNumberGenerator
## Celdas del casco sin tabla: Vector3i(corte, tabla, banda).
var _holes: Dictionary = {}


## `rng` es el del prop: así toda la forma sale de una sola semilla.
func _init(rng: RandomNumberGenerator) -> void:
	_rng = rng


## Fija la forma: medio largo, manga, alto, ancho del espejo de popa y el
## tramo [from, to] a lo largo de X que se construye.
func shape(new_half_length: float, new_beam: float, new_depth: float, new_stern_fill: float,
		from: float, to: float) -> void:
	half_length = new_half_length
	beam = new_beam
	depth = new_depth
	stern_fill = new_stern_fill
	x_from = from
	x_to = to


## Media manga del casco en `x`: aguda en la proa, con espejo en la popa.
func half_beam(x: float) -> float:
	var u := x / half_length
	if u >= 0.0:
		return beam * 0.5 * (1.0 - pow(minf(u, 1.0), BOW_POWER))
	return beam * 0.5 * (1.0 - (1.0 - stern_fill) * u * u)


## Alto de la borda en `x`: sube un poco hacia las puntas.
func depth_at(x: float) -> float:
	var u := x / half_length
	return depth * (1.0 + SHEER * u * u)


## Punto del forro exterior en `x`, a la altura `s` (0 quilla, 1 borda), banda `side` (±1).
func outer(x: float, s: float, side: float) -> Vector3:
	var angle := s * PI * 0.5
	return Vector3(x, depth_at(x) * (1.0 - cos(angle)), side * half_beam(x) * sin(angle))


## Punto del forro interior, una tabla hacia dentro del exterior.
func inner(x: float, s: float, side: float) -> Vector3:
	var angle := s * PI * 0.5
	var height := depth_at(x)
	return Vector3(x, plank_thickness + (height - plank_thickness) * (1.0 - cos(angle)),
			side * maxf(half_beam(x) - plank_thickness, 0.0) * sin(angle))


func station_x(index: int) -> float:
	return lerpf(x_from, x_to, float(index) / float(STATIONS - 1))


## Elige `count` agujeros de una o dos celdas de ancho y alto.
func make_holes(count: int) -> void:
	for hole in count:
		var station := _rng.randi_range(2, STATIONS - 4)
		var strake := _rng.randi_range(1, STRAKES - 3)
		var side := _rng.randi() % 2
		for along in _rng.randi_range(1, 2):
			for up in _rng.randi_range(1, 2):
				_holes[Vector3i(station + along, strake + up, side)] = true


## Forro exterior e interior, tabla por tabla, y la borda que los une.
func build_shell(mesh: LowPolyMesh) -> void:
	for side_index in 2:
		var side := -1.0 if side_index == 0 else 1.0
		for station in STATIONS - 1:
			var x0 := station_x(station)
			var x1 := station_x(station + 1)
			for strake in STRAKES:
				if _holes.has(Vector3i(station, strake, side_index)):
					_hole_shard(mesh, x0, x1, strake, side)
				else:
					_plank(mesh, x0, x1, strake, side)
			var out0 := outer(x0, 1.0, side)
			var out1 := outer(x1, 1.0, side)
			plate(mesh, out0, out1, inner(x1, 1.0, side), inner(x0, 1.0, side), light_color,
					(out0 + out1) * 0.5 + Vector3.DOWN)


## El espejo de popa: cierra el casco en `x_from`, por fuera y por dentro.
func build_transom(mesh: LowPolyMesh) -> void:
	for strake in STRAKES:
		var s0 := float(strake) / STRAKES
		var s1 := float(strake + 1) / STRAKES
		var a := outer(x_from, s0, -1.0)
		var b := outer(x_from, s1, -1.0)
		var c := outer(x_from, s1, 1.0)
		var d := outer(x_from, s0, 1.0)
		var color := dark_color if strake % 2 == 0 else light_color
		plate(mesh, a, b, c, d, color, (a + c) * 0.5 + Vector3.RIGHT)
		plate(mesh, a, b, c, d, rot_color, (a + c) * 0.5 + Vector3.LEFT)


## La cubierta de proa, desde la fracción `from` del largo hasta la punta,
## en tres tablas a lo largo y con un hueco.
func build_deck(mesh: LowPolyMesh, from: float) -> void:
	var first := ceili(from * (STATIONS - 1))
	var gap := _rng.randi_range(first, STATIONS - 3)
	for station in range(first, STATIONS - 1):
		var x0 := station_x(station)
		var x1 := station_x(station + 1)
		for plank in 3:
			if station == gap and plank == 1:
				continue
			var z0 := lerpf(-1.0, 1.0, float(plank) / 3.0)
			var z1 := lerpf(-1.0, 1.0, float(plank + 1) / 3.0)
			var a := _deck_point(x0, z0)
			var b := _deck_point(x1, z0)
			var c := _deck_point(x1, z1)
			var d := _deck_point(x0, z1)
			var color := light_color if plank % 2 == 0 else dark_color
			plate(mesh, a, b, c, d, color, (a + c) * 0.5 + Vector3.DOWN)
			plate(mesh, a, b, c, d, rot_color, (a + c) * 0.5 + Vector3.UP)


## Un palo de `from` a `to` en el espacio `space`, con la punta de `to`
## astillada.
func post(mesh: LowPolyMesh, space: Transform3D, from: Vector3, to: Vector3, radius: float,
		color: Color) -> void:
	var along := (to - from).normalized()
	var reference := Vector3.RIGHT if absf(along.dot(Vector3.RIGHT)) < 0.9 else Vector3.UP
	var across := along.cross(reference).normalized()
	var over := across.cross(along)
	var lower := PackedVector3Array()
	var upper := PackedVector3Array()
	for corner in POST_SIDES:
		var angle := TAU * float(corner) / float(POST_SIDES)
		var offset := (across * cos(angle) + over * sin(angle)) * radius
		lower.append(space * (from + offset))
		upper.append(space * (to + offset + along * _rng.randf_range(-radius, radius) * 1.5))
	mesh.band(lower, upper, color)
	mesh.cap(upper, color.lightened(0.1), space * from.lerp(to, 0.5))
	mesh.cap(lower, color, space * from.lerp(to, 0.5))


## Una tabla de cuatro lados en espacio del casco, mirando lejos de `inside`.
func plate(mesh: LowPolyMesh, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color,
		inside: Vector3) -> void:
	mesh.plate(frame * a, frame * b, frame * c, frame * d, color, frame * inside)


## Una celda del casco: la tabla de fuera y su cara de dentro.
func _plank(mesh: LowPolyMesh, x0: float, x1: float, strake: int, side: float) -> void:
	var s0 := float(strake) / STRAKES
	var s1 := float(strake + 1) / STRAKES
	var color := dark_color if strake % 2 == 0 else light_color
	if _rng.randf() < rot_chance:
		color = rot_color
	var axis := _axis(x0, x1)
	plate(mesh, outer(x0, s0, side), outer(x1, s0, side), outer(x1, s1, side),
			outer(x0, s1, side), color, axis)
	var a := inner(x0, s0, side)
	var c := inner(x1, s1, side)
	# El interior mira hacia el eje del barco.
	plate(mesh, a, inner(x1, s0, side), c, inner(x0, s1, side), rot_color.darkened(0.15),
			(a + c) - axis)


## Una astilla que cuelga del borde de arriba de un agujero.
func _hole_shard(mesh: LowPolyMesh, x0: float, x1: float, strake: int, side: float) -> void:
	var s1 := float(strake + 1) / STRAKES
	var reach := lerpf(s1, float(strake) / STRAKES, _rng.randf_range(0.4, 0.75))
	var a := outer(x0, s1, side)
	var b := outer(x1, s1, side)
	var tip := outer(lerpf(x0, x1, _rng.randf_range(0.25, 0.75)), reach, side)
	var axis := _axis(x0, x1)
	var center := (a + b + tip) / 3.0
	mesh.triangle(frame * a, frame * b, frame * tip, dark_color, frame * axis)
	mesh.triangle(frame * a, frame * b, frame * tip, rot_color, frame * (center * 2.0 - axis))


## Un punto del eje del barco entre los cortes `x0` y `x1`: queda dentro del
## hueco del casco, así el forro exterior mira lejos de él.
func _axis(x0: float, x1: float) -> Vector3:
	return Vector3((x0 + x1) * 0.5, depth * 0.6, 0.0)


## Punto de la cubierta en `x`, a la fracción `across` (-1 a 1) de su ancho.
func _deck_point(x: float, across: float) -> Vector3:
	var half := maxf(half_beam(x) - plank_thickness, 0.0)
	return Vector3(x, depth_at(x) - plank_thickness, across * half)
