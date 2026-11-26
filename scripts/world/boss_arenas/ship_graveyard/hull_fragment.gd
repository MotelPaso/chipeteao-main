class_name HullFragment
extends StaticBody3D
## Un pedazo curvo del casco de un barco, parado de canto como un muro roto:
## tablones del lado de fuera (el convexo, hacia -Z), cuadernas del lado de
## dentro, el borde de arriba astillado y uno o dos boquetes altos. Es una
## cobertura de la pelea en el Cementerio de barcos.
##
## Frenan tres cajas derechas que siguen la curva. Los boquetes quedan todos
## por encima de `hole_min_height`, así un raider parado no ve a través.
## Todo sale de `shape_seed`: la misma semilla, el mismo casco.

## Grupo que lee quien marca el suelo tapado por las coberturas.
const COVER_GROUP: StringName = &"boss_cover"
## Metros que el casco y las cajas bajan bajo la arena.
const SINK: float = 0.3
## Columnas a lo largo del casco (cada una, un tramo de tablones).
const COLUMNS: int = 12
## Metros de holgura de las cajas alrededor de la malla.
const PAD: float = 0.05
## Metros que las cajas de las puntas pasan del largo del casco.
const END_PAD: float = 0.3
## Columnas de ancho de cada boquete.
const HOLE_COLUMNS: int = 2

@export_group("Forma")
## Semilla de la forma: la misma semilla da el mismo casco.
@export var shape_seed: int = 0
## Largo del pedazo, en metros.
@export_range(2.0, 30.0, 0.5) var length: float = 9.0
## Alto máximo del borde de arriba, en metros.
@export var height: float = 4.6
## Cuánto se curva: metros que el centro sobresale respecto de las puntas.
@export var curve_depth: float = 0.9
## Grosor del forro de tablones abajo, en metros (sin contar las cuadernas).
@export var base_thickness: float = 1.2
## Grosor del forro arriba, en metros.
@export var top_thickness: float = 0.6
## Metros que el borde de arriba puede bajar en cada astilla.
@export var jaggedness: float = 1.5
## Filas de tablones de abajo arriba.
@export_range(4, 14) var plank_rows: int = 9
## Probabilidad de que un tablón esté podrido (0-1).
@export_range(0.0, 1.0) var rot_chance: float = 0.18

@export_group("Cuadernas")
## Cuadernas (costillas) del lado de dentro.
@export_range(0, 5) var rib_count: int = 4
## Metros que sobresale cada cuaderna abajo.
@export var rib_depth: float = 0.4
## Ancho de cada cuaderna, en metros.
@export var rib_width: float = 0.35

@export_group("Boquetes")
## Boquetes en la parte alta.
@export_range(0, 2) var hole_count: int = 1
## Alto mínimo del borde de abajo de un boquete, en metros.
@export var hole_min_height: float = 2.7
## Filas de tablones que ocupa cada boquete.
@export_range(1, 3) var hole_rows: int = 2

@export_group("Colisión")
## Cajas que siguen la curva.
@export_range(1, 5) var box_count: int = 3
## Largo de cada caja, en metros.
@export var box_length: float = 3.2
## Alto de cada caja sobre la arena, en metros.
@export var box_height: float = 4.0

@export_group("Colores")
## Tablón oscuro.
@export var plank_dark: Color = Color(0.5, 0.36, 0.24)
## Tablón claro.
@export var plank_light: Color = Color(0.68, 0.52, 0.36)
## Tablón podrido, con verdín.
@export var plank_rot: Color = Color(0.36, 0.46, 0.34)
## Color del lado de dentro y de las cuadernas.
@export var frame_color: Color = Color(0.42, 0.3, 0.2)

var _rng := RandomNumberGenerator.new()
## Alto del borde de arriba en cada columna.
var _tops := PackedFloat32Array()
## Columna donde empieza cada boquete y su primera y última fila.
var _holes: Array[Vector3i] = []


func _enter_tree() -> void:
	add_to_group(COVER_GROUP)


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_rng.seed = shape_seed
	_build_boxes()
	_plan_top_and_holes()
	var mesh := LowPolyMesh.new(shape_seed)
	_build_shell(mesh)
	_build_hole_walls(mesh)
	_build_ribs(mesh)
	add_child(mesh.instance("Hull"))


## Centro del grosor del casco a la altura x (la curva, en planta).
func _center(x: float) -> Vector3:
	var along := 2.0 * x / length
	return Vector3(x, 0.0, curve_depth * (along * along - 0.5))


## Normal hacia fuera (lado convexo, de los tablones) en x.
func _outward(x: float) -> Vector3:
	var slope := curve_depth * 8.0 * x / (length * length)
	return Vector3(slope, 0.0, -1.0).normalized()


## Punto de la cara de fuera (`face` = 1) o de dentro (`face` = -1) de la
## columna `column` a la altura `y`.
func _point(column: int, y: float, face: float) -> Vector3:
	var x := lerpf(-length * 0.5, length * 0.5, float(column) / float(COLUMNS))
	var half := lerpf(base_thickness, top_thickness, clampf(y / height, 0.0, 1.0)) * 0.5
	return _center(x) + Vector3.UP * y + _outward(x) * half * face


## Alto del borde de abajo de la fila `row` en la columna `column`.
func _row_height(column: int, row: int) -> float:
	return lerpf(-SINK, _tops[column], float(row) / float(plank_rows))


func _build_boxes() -> void:
	# El rango del grosor va de la punta de las cuadernas a los tablones.
	var offset := -rib_depth * 0.5
	var thickness := base_thickness + rib_depth + PAD * 2.0
	var reach := length * 0.5 + END_PAD - box_length * 0.5
	for index in box_count:
		var x := 0.0 if box_count == 1 else lerpf(-reach, reach, float(index) / float(box_count - 1))
		var slope := curve_depth * 8.0 * x / (length * length)
		var shape := BoxShape3D.new()
		shape.size = Vector3(box_length, box_height + SINK, thickness)
		var holder := CollisionShape3D.new()
		holder.name = "HullCover%d" % index
		holder.shape = shape
		holder.basis = Basis(Vector3.UP, atan2(-slope, 1.0))
		holder.position = _center(x) + _outward(x) * offset \
				+ Vector3.UP * (box_height - SINK) * 0.5
		add_child(holder)


## Elige el alto astillado de cada columna y dónde van los boquetes.
func _plan_top_and_holes() -> void:
	_tops.resize(COLUMNS + 1)
	for column in COLUMNS + 1:
		_tops[column] = height - _rng.randf() * jaggedness
	# Las puntas están arrancadas: más bajas que el resto.
	_tops[0] = height * _rng.randf_range(0.55, 0.75)
	_tops[COLUMNS] = height * _rng.randf_range(0.55, 0.75)
	_holes.clear()
	var free_start := 2
	for index in hole_count:
		var last_start := COLUMNS - 2 - HOLE_COLUMNS
		if free_start > last_start:
			break
		var start := _rng.randi_range(free_start, mini(free_start + 3, last_start))
		free_start = start + HOLE_COLUMNS + 2
		# Las columnas del boquete quedan altas para que sobre tablón arriba.
		for column in range(start, start + HOLE_COLUMNS + 1):
			_tops[column] = height - _rng.randf() * jaggedness * 0.15
		var first := plank_rows
		for row in plank_rows:
			var clear := true
			for column in range(start, start + HOLE_COLUMNS + 1):
				clear = clear and _row_height(column, row) >= hole_min_height
			if clear:
				first = row
				break
		var last := mini(first + hole_rows - 1, plank_rows - 2)
		if first <= last:
			_holes.append(Vector3i(start, first, last))


## La fila `row` del tramo `segment` es un hueco.
func _is_hole(segment: int, row: int) -> bool:
	for hole: Vector3i in _holes:
		if segment >= hole.x and segment < hole.x + HOLE_COLUMNS and row >= hole.y and row <= hole.z:
			return true
	return false


func _build_shell(mesh: LowPolyMesh) -> void:
	var row_colors: Array[Color] = []
	for row in plank_rows:
		row_colors.append(plank_dark if _rng.randf() < 0.5 else plank_light)
	for segment in COLUMNS:
		var next := segment + 1
		for row in plank_rows:
			if _is_hole(segment, row):
				continue
			var color := plank_rot if _rng.randf() < rot_chance else row_colors[row]
			var low_a := _row_height(segment, row)
			var low_b := _row_height(next, row)
			var high_a := _row_height(segment, row + 1)
			var high_b := _row_height(next, row + 1)
			var inside := (_point(segment, low_a, 0.0) + _point(next, high_b, 0.0)) * 0.5
			mesh.plate(_point(segment, low_a, 1.0), _point(next, low_b, 1.0),
					_point(next, high_b, 1.0), _point(segment, high_a, 1.0), color, inside)
			mesh.plate(_point(segment, low_a, -1.0), _point(next, low_b, -1.0),
					_point(next, high_b, -1.0), _point(segment, high_a, -1.0), frame_color, inside)
		# El canto astillado de arriba.
		var top_a := _tops[segment]
		var top_b := _tops[next]
		var below := (_point(segment, top_a, 0.0) + _point(next, top_b, 0.0)) * 0.5 + Vector3.DOWN
		mesh.plate(_point(segment, top_a, 1.0), _point(next, top_b, 1.0),
				_point(next, top_b, -1.0), _point(segment, top_a, -1.0), plank_dark, below)
	# Las dos puntas cortadas.
	for column: int in [0, COLUMNS]:
		var toward := Vector3.RIGHT if column == 0 else Vector3.LEFT
		var top := _tops[column]
		var inside := _point(column, top * 0.5, 0.0) + toward
		mesh.plate(_point(column, -SINK, 1.0), _point(column, top, 1.0),
				_point(column, top, -1.0), _point(column, -SINK, -1.0), plank_dark, inside)


## El canto de madera dentro de cada boquete: piso, techo y los dos lados.
func _build_hole_walls(mesh: LowPolyMesh) -> void:
	for hole: Vector3i in _holes:
		for segment in range(hole.x, hole.x + HOLE_COLUMNS):
			var next := segment + 1
			for row: int in [hole.y, hole.z + 1]:
				var a := _row_height(segment, row)
				var b := _row_height(next, row)
				var middle := (_point(segment, a, 0.0) + _point(next, b, 0.0)) * 0.5
				# El piso mira hacia arriba (lo sólido está abajo) y el techo al revés.
				var solid := Vector3.DOWN if row == hole.y else Vector3.UP
				mesh.plate(_point(segment, a, 1.0), _point(next, b, 1.0),
						_point(next, b, -1.0), _point(segment, a, -1.0), plank_dark,
						middle + solid * 0.1)
		for column: int in [hole.x, hole.x + HOLE_COLUMNS]:
			var low := _row_height(column, hole.y)
			var high := _row_height(column, hole.z + 1)
			var toward := Vector3.LEFT if column == hole.x else Vector3.RIGHT
			var inside := _point(column, (low + high) * 0.5, 0.0) + toward * 0.1
			mesh.plate(_point(column, low, 1.0), _point(column, high, 1.0),
					_point(column, high, -1.0), _point(column, low, -1.0), plank_dark, inside)


## Las cuadernas del lado de dentro: vigas que suben pegadas al forro; alguna
## asoma rota por encima del borde.
func _build_ribs(mesh: LowPolyMesh) -> void:
	for index in rib_count:
		var column := roundi(lerpf(1.5, float(COLUMNS) - 1.5,
				0.5 if rib_count == 1 else float(index) / float(rib_count - 1)))
		var x := lerpf(-length * 0.5, length * 0.5, float(column) / float(COLUMNS))
		var along := Vector3(1.0, 0.0, curve_depth * 8.0 * x / (length * length)).normalized()
		var inward := -_outward(x)
		var top := minf(_tops[column] + _rng.randf_range(-0.4, 0.5), height + 0.3)
		var rings: Array[PackedVector3Array] = []
		for y: float in [-SINK, top * 0.5, top]:
			var base := _point(column, y, -1.0)
			var depth := rib_depth * lerpf(1.0, 0.5, clampf(y / height, 0.0, 1.0))
			var half := along * rib_width * 0.5
			rings.append(PackedVector3Array([base - half, base + half, base + half + inward * depth,
					base - half + inward * depth]))
		mesh.band(rings[0], rings[1], frame_color.darkened(0.1))
		mesh.band(rings[1], rings[2], frame_color.darkened(0.1))
		var middle := Vector3.ZERO
		for point: Vector3 in rings[2]:
			middle += point * 0.25
		mesh.cap(rings[2], frame_color.darkened(0.1), middle + Vector3.DOWN * 0.2)
