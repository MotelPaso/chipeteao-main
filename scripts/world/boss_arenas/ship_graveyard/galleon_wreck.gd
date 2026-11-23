class_name GalleonWreck
extends Node3D
## Una mitad de un galeón partido en dos, tumbado en el fondo del mar, armado
## en código (LowPolyMesh). La escena pone dos: la proa y la popa, con un
## hueco entre ambas. Es decorado lejano: no tiene colisión.
##
## El origen queda en la arena, en el centro del corte. La mitad se extiende
## hacia +X, la manga va en Z y la quilla queda enterrada bajo y = 0. Se arma
## derecha: quien la coloca la inclina y la gira. Mástiles, roda, portas y
## timón los arma GalleonRigging (galleon/galleon_rigging.gd) con estos exports.

enum Half { BOW, STERN }

## Media cuaderna, de la quilla a la borda: x = fracción de la media manga,
## y = fracción del alto del casco.
const PROFILE: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(0.3, 0.04), Vector2(0.68, 0.16),
		Vector2(0.93, 0.36), Vector2(1.0, 0.56), Vector2(0.94, 0.8), Vector2(0.86, 1.0)]
## Tramos del casco a lo largo de la mitad.
const STATIONS: int = 16
## Hileras de tablas de la cubierta, de banda a banda.
const DECK_ROWS: int = 5
## Separación de las portas y ventanas sobre su pared, para que no parpadeen.
const PANEL_LIFT: float = 0.05
## Desde qué fracción del largo empieza a afinarse la proa, y cuánto sube su quilla (fracción del alto).
const BOW_TAPER_START: float = 0.4
const BOW_KEEL_RISE: float = 0.55
## Ancho mínimo de la roda, en fracción de la manga (evita caras degeneradas).
const STEM_WIDTH: float = 0.02
## Desde qué fracción del largo se angosta la popa, y cuánto suben su quilla y su borda.
const STERN_TAPER_START: float = 0.55
const STERN_KEEL_RISE: float = 0.18
const STERN_SHEER: float = 0.8
## Cuánto puede variar el borde roto de una tabla entre su canto de abajo y el de arriba, en metros.
const PLANK_JAG: float = 0.7
## Sección de una cuaderna suelta (ancho en X, grueso), en metros.
const RIB_SIZE := Vector2(0.35, 0.3)
## Cuánto se meten las cuadernas hacia dentro del forro, en metros.
const RIB_INSET: float = 0.18
## Metros que la primera cuaderna asoma por delante del corte.
const RIB_OVERHANG: float = 1.2

@export_group("Forma")
## Qué mitad del barco arma: la proa (BOW) o la popa (STERN).
@export var half: Half = Half.STERN
## Semilla de la forma: la misma semilla da el mismo casco.
@export var shape_seed: int = 0
## Largo de la mitad, desde el corte, en metros.
@export var length: float = 30.0
## Manga (ancho máximo del casco), en metros.
@export var beam: float = 10.0
## Alto del casco de la quilla a la borda, en metros.
@export var hull_height: float = 8.0
## Metros de quilla enterrados bajo la arena.
@export var buried_depth: float = 1.6
## Metros que la cubierta queda por debajo de la borda.
@export var deck_drop: float = 0.6
## Metros que sube la borda en la punta de la proa.
@export var bow_rise: float = 1.6
## Ancho del espejo de popa, en fracción de la manga.
@export_range(0.3, 1.0) var transom_width: float = 0.72

@export_group("Corte")
## Metros que las tablas rotas se adentran desde el corte, como máximo.
@export var break_ragged: float = 3.2
## Cuadernas sueltas que asoman en el corte.
@export_range(0, 9) var rib_count: int = 6
## Tablas que faltan en los costados.
@export_range(0, 20) var missing_planks: int = 6
## Agujeros en la cubierta.
@export_range(0, 6) var deck_holes: int = 2

@export_group("Popa y proa")
## Alto del castillo de popa sobre la borda, en metros.
@export var castle_height: float = 4.0
## Dónde empieza el castillo de popa, en fracción del largo.
@export_range(0.4, 0.9) var castle_start: float = 0.7
## Ventanas oscuras en la pared trasera del castillo.
@export_range(0, 6) var window_count: int = 4
## Largo del bauprés quebrado, en metros.
@export var bowsprit_length: float = 7.0
## Ángulo del bauprés sobre la horizontal, en grados.
@export var bowsprit_angle: float = 28.0
## Metros que la roda sube sobre la borda.
@export var stem_rise: float = 1.4

@export_group("Mástiles")
## Mástiles: el primero sigue en pie, el segundo cayó y se apoya hacia un costado.
@export_range(0, 2) var mast_count: int = 2
## Alto mínimo del mástil en pie sobre la cubierta, en metros (está quebrado).
@export var mast_height_min: float = 14.0
## Alto máximo del mástil en pie sobre la cubierta, en metros.
@export var mast_height_max: float = 20.0
## Radio del mástil en su pie, en metros.
@export var mast_radius: float = 0.45
## Largo de la verga del mástil en pie, en metros.
@export var yard_length: float = 13.0
## Metros que una punta de la verga cuelga más baja que la otra.
@export var yard_droop: float = 2.0
## Jirones de vela colgando de la verga.
@export_range(0, 8) var sail_rags: int = 4
## Largo mínimo de un jirón, en metros.
@export var rag_length_min: float = 3.0
## Largo máximo de un jirón, en metros.
@export var rag_length_max: float = 6.0
## Largo del mástil caído, en metros: se apoya en la borda y su punta queda en la arena.
@export var fallen_mast_length: float = 16.0

@export_group("Detalle")
## Portas de cañón por costado.
@export_range(0, 14) var gun_ports: int = 8
## Lado de una porta, en metros.
@export var port_size: float = 0.75
## Cañones que asoman por costado.
@export_range(0, 4) var cannon_count: int = 2
## Metros que asoma un cañón.
@export var cannon_length: float = 1.8
## Percebes y corales pegados al casco.
@export_range(0, 120) var growth_count: int = 60
## Radio mínimo de un percebe o coral, en metros.
@export var growth_size_min: float = 0.25
## Radio máximo de un percebe o coral, en metros.
@export var growth_size_max: float = 0.8
## Probabilidad (0 a 1) de que una tabla esté podrida.
@export_range(0.0, 1.0) var rot_chance: float = 0.2

@export_group("Colores")
## Tablas oscuras del casco.
@export var dark_plank: Color = Color(0.5, 0.36, 0.24)
## Tablas claras del casco.
@export var light_plank: Color = Color(0.68, 0.52, 0.36)
## Tablas podridas, verdosas.
@export var rot_plank: Color = Color(0.36, 0.46, 0.34)
## Caras de dentro del casco, que se ven por el corte.
@export var interior_color: Color = Color(0.16, 0.12, 0.1)
## Portas y ventanas.
@export var opening_color: Color = Color(0.05, 0.04, 0.04)
## Hierro de cañones y herrajes.
@export var iron_color: Color = Color(0.2, 0.21, 0.24)
## Jirones de vela.
@export var sail_color: Color = Color(0.78, 0.76, 0.66)
## Colores de percebes y corales: cada uno toma uno.
@export var growth_colors: Array[Color] = [Color(0.95, 0.42, 0.38), Color(0.98, 0.62, 0.25),
		Color(0.3, 0.8, 0.75)]

var _rng := RandomNumberGenerator.new()
var _rigging: GalleonRigging


func _ready() -> void:
	_rng.seed = shape_seed
	var mesh := LowPolyMesh.new(shape_seed)
	_rigging = GalleonRigging.new(self, mesh, _rng)
	_build_hull(mesh)
	_build_ribs(mesh)
	_build_deck(mesh)
	if half == Half.STERN:
		_build_sterncastle(mesh)
		_rigging.build_rudder()
	else:
		_rigging.build_bow()
	_rigging.build_masts()
	_rigging.build_gun_ports()
	_build_growths(mesh)
	add_child(mesh.instance("Galleon"))


## Forma del casco en `x`: (media manga, y de la quilla, y de la borda).
func shape_at(x: float) -> Vector3:
	var t := clampf(x / length, 0.0, 1.0)
	var width := 1.0
	var rise := 0.0
	var sheer := 0.0
	if half == Half.BOW:
		var taper := clampf((t - BOW_TAPER_START) / (1.0 - BOW_TAPER_START), 0.0, 1.0)
		width = maxf(1.0 - pow(taper, 2.2), STEM_WIDTH)
		rise = smoothstep(0.55, 1.0, t) * BOW_KEEL_RISE
		sheer = smoothstep(0.5, 1.0, t) * bow_rise
	else:
		width = lerpf(1.0, transom_width, smoothstep(STERN_TAPER_START, 1.0, t))
		rise = smoothstep(0.7, 1.0, t) * STERN_KEEL_RISE
		sheer = smoothstep(0.4, 1.0, t) * STERN_SHEER
	return Vector3(beam * 0.5 * width, -buried_depth + rise * hull_height,
			-buried_depth + hull_height + sheer)


## Punto del forro en `x`, a la fracción `ratio` del alto, en el costado `side` (-1 o 1).
func surface_point(x: float, ratio: float, side: float) -> Vector3:
	var shape := shape_at(x)
	var k := 0
	while k < PROFILE.size() - 2 and PROFILE[k + 1].y < ratio:
		k += 1
	var f := clampf((ratio - PROFILE[k].y) / (PROFILE[k + 1].y - PROFILE[k].y), 0.0, 1.0)
	var point := PROFILE[k].lerp(PROFILE[k + 1], f)
	return Vector3(x, lerpf(shape.y, shape.z, point.y), side * shape.x * point.x)


## Punto `j` del anillo de la cuaderna en `x`: 0 es la borda de babor, el del
## medio la quilla y el último la borda de estribor.
func _hull_point(x: float, j: int) -> Vector3:
	var shape := shape_at(x)
	var last := PROFILE.size() - 1
	var side := -1.0 if j < last else 1.0
	var point := PROFILE[absi(j - last)]
	return Vector3(x, lerpf(shape.y, shape.z, point.y), side * shape.x * point.x)


## Punto de la línea de crujía (el eje del barco) a media altura en `x`.
func _axis(x: float) -> Vector3:
	var shape := shape_at(x)
	return Vector3(x, (shape.y + shape.z) * 0.5, 0.0)


## Tono de una tabla suelta: entre la oscura y la clara, o podrida.
func _plank_tone() -> Color:
	if _rng.randf() < rot_chance:
		return rot_plank
	return dark_plank.lerp(light_plank, _rng.randf())


## El forro, tabla por tabla, con el borde roto en el corte y algunas tablas que faltan.
func _build_hull(mesh: LowPolyMesh) -> void:
	var strakes := PROFILE.size() * 2 - 2
	var step := length / float(STATIONS)
	var missing: Dictionary = {}
	for n in missing_planks:
		var strake := _rng.randi_range(0, 3)
		if _rng.randf() < 0.5:
			strake = strakes - 1 - strake
		missing[Vector2i(strake, _rng.randi_range(1, int(STATIONS * 0.45)))] = true
	var starts: Array[float] = []
	for j in strakes + 1:
		starts.append(_rng.randf_range(0.0, break_ragged))
	for i in strakes:
		var tone := dark_plank.lerp(light_plank, _rng.randf())
		var start_low := starts[i]
		var start_high := clampf(start_low + _rng.randf_range(-PLANK_JAG, PLANK_JAG), 0.0, break_ragged)
		for k in STATIONS:
			var x1 := step * float(k + 1)
			if x1 <= maxf(start_low, start_high) or missing.has(Vector2i(i, k)):
				continue
			var x0 := step * float(k)
			var color := rot_plank if _rng.randf() < rot_chance else tone
			_shell_plate(mesh, _hull_point(maxf(x0, start_low), i), _hull_point(x1, i),
					_hull_point(x1, i + 1), _hull_point(maxf(x0, start_high), i + 1), color)


## Una tabla del forro: la cara de fuera con `color` y la de dentro oscura.
func _shell_plate(mesh: LowPolyMesh, a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		color: Color) -> void:
	var middle := (a + b + c + d) * 0.25
	var axis := _axis(middle.x)
	mesh.plate(a, b, c, d, color, axis)
	mesh.plate(a, b, c, d, interior_color, middle + (middle - axis).normalized())


## Cuadernas en U que asoman por el corte, algunas quebradas, y algún bao suelto.
func _build_ribs(mesh: LowPolyMesh) -> void:
	var last := PROFILE.size() * 2 - 2
	for r in rib_count:
		var x := lerpf(-RIB_OVERHANG, break_ragged + 0.6, (float(r) + 0.5) / float(rib_count)) \
				+ _rng.randf_range(-0.2, 0.2)
		var axis := _axis(x)
		var cut_port := _rng.randi_range(0, 3)
		var cut_starboard := _rng.randi_range(0, 3)
		var color := rot_plank.darkened(0.15) if _rng.randf() < 0.4 else dark_plank.darkened(0.2)
		for j in range(cut_port, last - cut_starboard):
			var a := _hull_point(x, j)
			var b := _hull_point(x, j + 1)
			a += (axis - a).normalized() * RIB_INSET
			b += (axis - b).normalized() * RIB_INSET
			_rigging.beam(a, b, RIB_SIZE, color)
		if cut_port == 0 and cut_starboard == 0:
			var deck_y := shape_at(x).z - deck_drop
			var reach := _deck_half_width(x) - RIB_INSET
			_rigging.beam(Vector3(x, deck_y, -reach), Vector3(x, deck_y, reach), RIB_SIZE, color)


## Media manga de la cubierta en `x`.
func _deck_half_width(x: float) -> float:
	var shape := shape_at(x)
	var ratio := (shape.z - deck_drop - shape.y) / (shape.z - shape.y)
	return absf(surface_point(x, ratio, 1.0).z)


## La cubierta en tablas, rota cerca del corte y con un par de agujeros.
func _build_deck(mesh: LowPolyMesh) -> void:
	var step := length / float(STATIONS)
	var end_x := length * castle_start if half == Half.STERN else length
	var holes: Dictionary = {}
	for h in deck_holes:
		var k := _rng.randi_range(3, int(STATIONS * 0.6))
		var row := _rng.randi_range(0, DECK_ROWS - 2)
		holes[Vector2i(k, row)] = true
		holes[Vector2i(k, row + 1)] = true
	for row in DECK_ROWS:
		var start := _rng.randf_range(0.3, break_ragged + 0.8)
		var f0 := -1.0 + 2.0 * float(row) / float(DECK_ROWS)
		var f1 := -1.0 + 2.0 * float(row + 1) / float(DECK_ROWS)
		for k in STATIONS:
			var x0 := maxf(step * float(k), start)
			var x1 := minf(step * float(k + 1), end_x)
			if x1 <= x0 or holes.has(Vector2i(k, row)):
				continue
			var a := _deck_point(x0, f0)
			var b := _deck_point(x1, f0)
			var c := _deck_point(x1, f1)
			var d := _deck_point(x0, f1)
			var middle := (a + b + c + d) * 0.25
			mesh.plate(a, b, c, d, _plank_tone(), middle + Vector3.DOWN)
			mesh.plate(a, b, c, d, interior_color, middle + Vector3.UP)


## Punto de la cubierta en `x`, a la fracción `across` (-1 babor, 1 estribor) de la manga.
func _deck_point(x: float, across: float) -> Vector3:
	return Vector3(x, shape_at(x).z - deck_drop, across * _deck_half_width(x))


## El espejo de popa y el castillo, con sus ventanas oscuras.
func _build_sterncastle(mesh: LowPolyMesh) -> void:
	var ring := PackedVector3Array()
	for j in PROFILE.size() * 2 - 1:
		ring.append(_hull_point(length, j))
	var stern_axis := _axis(length)
	mesh.cap(ring, dark_plank, stern_axis + Vector3.LEFT)
	mesh.cap(ring, interior_color, stern_axis + Vector3.RIGHT)
	var start := length * castle_start
	var xs: Array[float] = [start]
	for k in STATIONS:
		var x := length * float(k) / float(STATIONS)
		if x > start + 0.01:
			xs.append(x)
	xs.append(length)
	for n in xs.size() - 1:
		var x0 := xs[n]
		var x1 := xs[n + 1]
		var inside := Vector3((x0 + x1) * 0.5, shape_at(x0).z + castle_height * 0.5, 0.0)
		for side: float in [-1.0, 1.0]:
			mesh.plate(_castle_point(x0, side, 0.0), _castle_point(x1, side, 0.0),
					_castle_point(x1, side, 0.5), _castle_point(x0, side, 0.5), _plank_tone(), inside)
			mesh.plate(_castle_point(x0, side, 0.5), _castle_point(x1, side, 0.5),
					_castle_point(x1, side, 1.0), _castle_point(x0, side, 1.0), _plank_tone(), inside)
		mesh.plate(_castle_point(x0, -1.0, 1.0), _castle_point(x1, -1.0, 1.0),
				_castle_point(x1, 1.0, 1.0), _castle_point(x0, 1.0, 1.0), _plank_tone(), inside)
	_castle_walls(mesh, start)


## Pared delantera (con su puerta) y trasera (con sus ventanas) del castillo.
func _castle_walls(mesh: LowPolyMesh, start: float) -> void:
	var front_low := shape_at(start).z - deck_drop
	var front_reach := absf(_castle_point(start, 1.0, 0.0).z)
	var front_top := _castle_point(start, 1.0, 1.0)
	var front_inside := Vector3(start + 1.0, front_top.y - castle_height * 0.5, 0.0)
	mesh.plate(Vector3(start, front_low, -front_reach), Vector3(start, front_low, front_reach),
			front_top, _castle_point(start, -1.0, 1.0), light_plank, front_inside)
	var door_x := start - PANEL_LIFT
	var door_low := shape_at(start).z
	var door_top := door_low + castle_height * 0.55
	mesh.plate(Vector3(door_x, door_low, -0.6), Vector3(door_x, door_low, 0.6),
			Vector3(door_x, door_top, 0.6), Vector3(door_x, door_top, -0.6), opening_color,
			front_inside)
	var back_inside := Vector3(length - 1.0, shape_at(length).z + castle_height * 0.5, 0.0)
	mesh.plate(_castle_point(length, -1.0, 0.0), _castle_point(length, 1.0, 0.0),
			_castle_point(length, 1.0, 1.0), _castle_point(length, -1.0, 1.0), dark_plank,
			back_inside)
	var reach := absf(_castle_point(length, 1.0, 0.5).z) * 0.75
	var middle_y := shape_at(length).z + castle_height * 0.5
	var size := minf(castle_height * 0.35, 2.0 * reach / float(maxi(window_count, 1)) * 0.6)
	var wx := length + PANEL_LIFT
	for w in window_count:
		var z := lerpf(-reach, reach, (float(w) + 0.5) / float(window_count))
		mesh.plate(Vector3(wx, middle_y - size, z - size * 0.5),
				Vector3(wx, middle_y - size, z + size * 0.5),
				Vector3(wx, middle_y + size, z + size * 0.5),
				Vector3(wx, middle_y + size, z - size * 0.5), opening_color, back_inside)


## Punto de la pared del castillo en `x`, en el costado `side`, a la fracción `up` de su alto.
func _castle_point(x: float, side: float, up: float) -> Vector3:
	var shape := shape_at(x)
	var reach := shape.x * PROFILE[PROFILE.size() - 1].x * lerpf(1.0, 0.92, up)
	return Vector3(x, shape.z + castle_height * up, side * reach)


## Percebes y corales en el casco, más tupidos cerca de la arena.
func _build_growths(mesh: LowPolyMesh) -> void:
	if growth_colors.is_empty():
		return
	for g in growth_count:
		var x := _rng.randf_range(0.2, length - 0.5)
		var ratio := lerpf(0.15, 0.95, pow(_rng.randf(), 1.6))
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var size := _rng.randf_range(growth_size_min, growth_size_max)
		var color := growth_colors[_rng.randi() % growth_colors.size()]
		mesh.blob(surface_point(x, ratio, side), Vector3(size * _rng.randf_range(1.0, 1.6),
				size * _rng.randf_range(0.6, 1.0), size), color, 6, 3, 0.2)
