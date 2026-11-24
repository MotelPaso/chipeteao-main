class_name CoralReef
extends Node3D
## El ARRECIFE que rodea el claro del cementerio de barcos (nodo Reef de
## ShipGraveyard.tscn): un anillo de roca baja cubierta de corales de colores,
## pegado por fuera al borde del claro. Es lo que hace que el límite del campo
## se lea como paisaje. No choca con nada: lo que frena es la pared sin dibujo
## de BossField, que pasa justo por su cara interior.
##
## Todo se arma en código (LowPolyMesh): rocas en varias filas, cada vez más
## altas hacia afuera, y sobre cada una corales de cinco formas (ramas,
## abanicos, cerebros, esponjas de tubo y mesas). El anillo se parte en
## `sectors` mallas para que la cámara no dibuje la parte que tiene a la espalda.

## Lados de los tubos (ramas, esponjas, pies de mesa).
const TUBE_SIDES: int = 4
## Lados de un abanico y de una mesa.
const FAN_SIDES: int = 6
## Cuánto de su alto queda una roca hundida en la arena (0-1).
const ROCK_SINK: float = 0.35
## Formas de coral, en el orden en que se sortean.
enum Growth { BRANCH, FAN, BRAIN, SPONGE, TABLE }

@export_group("Anillo")
## Radio interior del arrecife, en metros. 0 = el radio del claro (lo lee del nodo "arena_bounds" de la arena), que es lo normal: así el arrecife siempre empieza donde termina el campo.
@export var inner_radius: float = 0.0
## Mallas en que se parte el anillo.
@export_range(1, 12) var sectors: int = 6
## Semilla de la forma: la misma semilla da el mismo arrecife.
@export var shape_seed: int = 7

@export_group("Roca")
## Filas de roca, de adentro hacia afuera.
@export_range(1, 5) var rows: int = 3
## Metros entre una fila y la siguiente.
@export var row_gap: float = 5.5
## Metros entre rocas vecinas de la primera fila (las de afuera van más separadas).
@export_range(0.5, 30.0, 0.1) var rock_spacing: float = 4.2
## Radio mínimo de una roca de la primera fila, en metros.
@export var rock_radius_min: float = 2.0
## Radio máximo de una roca de la primera fila, en metros.
@export var rock_radius_max: float = 3.6
## Alto mínimo de una roca de la primera fila, en metros.
@export var rock_height_min: float = 1.3
## Alto máximo de una roca de la primera fila, en metros (bajo: no tiene que tapar lo que hay detrás).
@export var rock_height_max: float = 2.6
## Cuánto crecen las rocas de cada fila hacia afuera (1.3 = 30 % más por fila).
@export var row_growth: float = 1.45
## Arcos del borde donde va SOLO la primera fila, cada uno (desde, hasta) en grados (0 = +X, crece hacia +Z): ahí están las piezas grandes y las filas de afuera las taparían.
@export var open_arcs: Array[Vector2] = [Vector2(121.0, 179.0), Vector2(214.0, 328.0)]
## Metros de arena entre el borde del claro y la roca más cercana.
@export var edge_gap: float = 0.8
## Color de la roca.
@export var rock_color: Color = Color(0.74, 0.62, 0.56)
## Color de la roca en las filas de afuera (más oscura: se pierde en el agua).
@export var rock_far_color: Color = Color(0.4, 0.42, 0.48)

@export_group("Corales")
## Corales por roca, en promedio.
@export var corals_per_rock: float = 2.8
## Alto mínimo de un coral, en metros.
@export var coral_height_min: float = 1.0
## Alto máximo de un coral, en metros.
@export var coral_height_max: float = 3.2
## Colores de los corales: cada uno toma uno al azar.
@export var coral_colors: Array[Color] = [Color(0.98, 0.42, 0.4), Color(1.0, 0.62, 0.22),
		Color(0.8, 0.42, 0.9), Color(0.25, 0.85, 0.78), Color(0.98, 0.88, 0.38),
		Color(0.95, 0.5, 0.72)]

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = shape_seed
	var inner := _inner_radius()
	var meshes: Array[LowPolyMesh] = []
	for sector: int in maxi(sectors, 1):
		meshes.append(LowPolyMesh.new(shape_seed + sector))
	for row: int in rows:
		_build_row(meshes, inner, row)
	for sector: int in meshes.size():
		if not meshes[sector].is_empty():
			add_child(meshes[sector].instance("Reef%d" % sector))


## Triángulos del arrecife entero (lo lee la sonda de costo).
func triangle_count() -> int:
	var total := 0
	for child: Node in get_children():
		var view := child as MeshInstance3D
		if view != null and view.mesh != null:
			total += view.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() / 3
	return total


# --- privados ---------------------------------------------------------------------

## El radio donde empieza el arrecife: el del export o, en 0, el del claro.
func _inner_radius() -> float:
	if inner_radius > 0.0:
		return inner_radius
	var bounds := get_tree().get_first_node_in_group(&"arena_bounds")
	var radius: Variant = bounds.get("clearing_radius") if bounds != null else null
	return float(radius) if radius != null else 52.0


## Una fila de rocas alrededor del claro, con sus corales. Cada roca va a la
## malla del sector donde cae.
func _build_row(meshes: Array[LowPolyMesh], inner: float, row: int) -> void:
	var grow := pow(row_growth, float(row))
	var radius_min := rock_radius_min * grow
	var radius_max := rock_radius_max * grow
	# La fila empieza donde su roca más chica queda a edge_gap del claro; las
	# más grandes se corren hacia afuera lo que les sobra de radio.
	var ring := inner + radius_min + edge_gap + row_gap * float(row) * (1.0 + 0.25 * float(row))
	var count := maxi(int(TAU * ring / (rock_spacing * grow)), 6)
	var color := rock_color.lerp(rock_far_color, float(row) / float(maxi(rows - 1, 1)))
	for index: int in count:
		var angle := TAU * (float(index) + _rng.randf_range(-0.3, 0.3)) / float(count)
		var radius := _rng.randf_range(radius_min, radius_max)
		var height := _rng.randf_range(rock_height_min, rock_height_max) * grow
		var reach := ring + _rng.randf_range(0.0, row_gap * 0.5) + (radius - radius_min) * 1.2
		if row > 0 and _in_open_arc(angle):
			continue
		var center := Vector3(cos(angle) * reach, height * (0.5 - ROCK_SINK), sin(angle) * reach)
		var radii := Vector3(radius, height, radius * _rng.randf_range(0.75, 1.2))
		var mesh := meshes[_sector_of(angle, meshes.size())]
		mesh.blob(center, radii, color, 7, 4, 0.22)
		var growths := int(corals_per_rock) + (1 if _rng.randf() < fmod(corals_per_rock, 1.0) else 0)
		for _growth: int in growths:
			_grow_coral(mesh, center, radii, grow)


## True si `angle` (radianes) cae en alguno de los arcos abiertos.
func _in_open_arc(angle: float) -> bool:
	var degrees := fposmod(rad_to_deg(angle), 360.0)
	for arc: Vector2 in open_arcs:
		var from := fposmod(arc.x, 360.0)
		var span := fposmod(arc.y - arc.x, 360.0)
		if fposmod(degrees - from, 360.0) <= span:
			return true
	return false


func _sector_of(angle: float, count: int) -> int:
	return clampi(int(fposmod(angle, TAU) / TAU * float(count)), 0, count - 1)


## Un coral sobre la roca de centro `center` y semiejes `radii`.
func _grow_coral(mesh: LowPolyMesh, center: Vector3, radii: Vector3, grow: float) -> void:
	if coral_colors.is_empty():
		return
	# Un punto de la mitad de arriba de la roca, y hacia dónde crece desde ahí.
	var turn := _rng.randf() * TAU
	var lift := _rng.randf_range(0.35, 1.0)
	var side := sqrt(maxf(1.0 - lift * lift, 0.0))
	var out := Vector3(cos(turn) * side, lift, sin(turn) * side)
	var foot := center + Vector3(out.x * radii.x, out.y * radii.y, out.z * radii.z) * 0.92
	var up := (out * 0.6 + Vector3.UP).normalized()
	var height := _rng.randf_range(coral_height_min, coral_height_max) * sqrt(grow)
	var color := coral_colors[_rng.randi() % coral_colors.size()]
	match _rng.randi() % Growth.size():
		Growth.BRANCH:
			_grow_branches(mesh, foot, up, height, color)
		Growth.FAN:
			_grow_fan(mesh, foot, up, height, turn, color)
		Growth.BRAIN:
			mesh.blob(foot + up * height * 0.25, Vector3.ONE * height * 0.45, color, 6, 3, 0.18)
		Growth.SPONGE:
			_grow_sponge(mesh, foot, up, height, color)
		Growth.TABLE:
			_grow_table(mesh, foot, up, height, color)


## Coral de ramas: tres a cinco tubos que se abren desde el mismo pie.
func _grow_branches(mesh: LowPolyMesh, foot: Vector3, up: Vector3, height: float,
		color: Color) -> void:
	for _branch: int in _rng.randi_range(3, 5):
		var lean := Vector3(_rng.randf_range(-0.7, 0.7), 0.0, _rng.randf_range(-0.7, 0.7))
		var tip := foot + (up + lean).normalized() * height * _rng.randf_range(0.6, 1.0)
		var girth := height * _rng.randf_range(0.07, 0.11)
		_tube(mesh, foot, tip, girth, girth * 0.55, color, color.lightened(0.25))


## Coral de abanico: una media rueda plana y parada, visible de los dos lados.
func _grow_fan(mesh: LowPolyMesh, foot: Vector3, up: Vector3, height: float, turn: float,
		color: Color) -> void:
	var across := Vector3(cos(turn + PI * 0.5), 0.0, sin(turn + PI * 0.5))
	var facing := across.cross(up).normalized()
	var rim := PackedVector3Array()
	for index: int in FAN_SIDES + 1:
		var sweep := lerpf(-1.25, 1.25, float(index) / float(FAN_SIDES))
		rim.append(foot + (up * cos(sweep) + across * sin(sweep)) * height
				* _rng.randf_range(0.82, 1.0))
	for index: int in FAN_SIDES:
		# Dos veces, una por cara: LowPolyMesh dibuja un solo lado.
		mesh.triangle(foot, rim[index], rim[index + 1], color, foot + facing + up * height * 0.5)
		mesh.triangle(foot, rim[index], rim[index + 1], color.darkened(0.15),
				foot - facing + up * height * 0.5)


## Esponja de tubo: dos o tres tubos gruesos con la boca oscura.
func _grow_sponge(mesh: LowPolyMesh, foot: Vector3, up: Vector3, height: float,
		color: Color) -> void:
	for _pipe: int in _rng.randi_range(2, 3):
		var offset := Vector3(_rng.randf_range(-0.3, 0.3), 0.0, _rng.randf_range(-0.3, 0.3)) * height
		var girth := height * _rng.randf_range(0.14, 0.2)
		_tube(mesh, foot + offset, foot + offset + up * height * _rng.randf_range(0.55, 1.0),
				girth, girth * 1.15, color, color.darkened(0.6))


## Coral de mesa: un pie corto y un plato ancho, visible desde arriba y desde abajo.
func _grow_table(mesh: LowPolyMesh, foot: Vector3, up: Vector3, height: float,
		color: Color) -> void:
	var top := foot + up * height * 0.5
	_tube(mesh, foot, top, height * 0.12, height * 0.09, color.darkened(0.2), color)
	var plate := mesh.ring(top, height * 0.8, FAN_SIDES, _rng.randf() * TAU, 0.15)
	mesh.cap(plate, color, top + Vector3.DOWN)
	mesh.cap(plate, color.darkened(0.25), top + Vector3.UP)


## Un tubo de TUBE_SIDES lados de `from` a `to`, de radio `from_radius` en el
## pie y `to_radius` en la punta, con su tapa de color `tip_color`.
func _tube(mesh: LowPolyMesh, from: Vector3, to: Vector3, from_radius: float,
		to_radius: float, color: Color, tip_color: Color) -> void:
	var axis := (to - from).normalized()
	var side := axis.cross(Vector3.RIGHT if absf(axis.x) < 0.9 else Vector3.FORWARD).normalized()
	var other := axis.cross(side)
	var lower := PackedVector3Array()
	var upper := PackedVector3Array()
	for index: int in TUBE_SIDES:
		var angle := TAU * float(index) / float(TUBE_SIDES)
		var spoke := side * cos(angle) + other * sin(angle)
		lower.append(from + spoke * from_radius)
		upper.append(to + spoke * to_radius)
	mesh.band(lower, upper, color)
	mesh.cap(upper, tip_color, from)
