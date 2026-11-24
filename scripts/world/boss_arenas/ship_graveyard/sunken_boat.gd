class_name SunkenBoat
extends Node3D
## Un naufragio chico del cementerio de barcos, armado en código
## (LowPolyMesh): la proa de una balandra saliendo de la arena, un casco
## volcado con la quilla al aire o un bote de remos medio lleno de arena.
## El casco de madera lo arma BoatHull (sunken_boat/boat_hull.gd).
##
## Marco local: el largo del barco va por X (la proa hacia +X) y el origen
## está sobre la arena, en el medio del naufragio. Es solo decorado: no tiene
## colisión. La misma semilla da el mismo barco.

enum Kind { SLOOP_BOW, CAPSIZED, LONGBOAT }

## El casco de madera (BoatHull). Va por preload: así compila aunque la caché de
## clases globales todavía no lo conozca.
const Hull := preload("res://scripts/world/boss_arenas/ship_graveyard/sunken_boat/boat_hull.gd")
## Metros que la borda del casco volcado queda bajo la arena.
const CAPSIZED_SINK: float = 0.4
## Pasos de la búsqueda del borde de la arena dentro del bote.
const FILL_STEPS: int = 14

@export_group("Forma")
## Qué naufragio es.
@export var kind: Kind = Kind.SLOOP_BOW
## Semilla de la forma: la misma semilla da el mismo barco.
@export var shape_seed: int = 1
## Grosor de las tablas del casco, en metros.
@export var plank_thickness: float = 0.14
## Probabilidad de que una tabla esté podrida (0 a 1).
@export_range(0.0, 1.0) var rot_chance: float = 0.18

@export_group("Proa de balandra")
## Largo del trozo de proa, del corte enterrado a la punta, en metros.
@export var sloop_length: float = 14.0
## Manga (ancho) de la balandra, en metros.
@export var sloop_beam: float = 5.0
## Alto del casco de la quilla a la borda, en metros.
@export var sloop_depth: float = 3.2
## Ángulo con que la proa sale de la arena, en grados.
@export_range(5.0, 85.0, 0.5) var sloop_angle_deg: float = 35.0
## Metros bajo la arena que queda el punto más alto del corte.
@export var bury_depth: float = 1.5
## Alto del muñón del mástil sobre la cubierta, en metros.
@export var mast_stump_height: float = 2.5
## Largo del bauprés quebrado, en metros.
@export var bowsprit_length: float = 2.6

@export_group("Casco volcado")
## Largo del casco volcado, en metros.
@export var capsized_length: float = 16.0
## Manga (ancho) del casco volcado, en metros.
@export var capsized_beam: float = 5.0
## Alto de la quilla sobre la arena, en metros.
@export var capsized_height: float = 3.0
## Agujeros en las tablas, como máximo (la semilla elige entre 2 y este número).
@export_range(0, 6) var capsized_holes: int = 3
## Cuánto asoma el timón sobre la quilla, en metros.
@export var rudder_height: float = 1.6

@export_group("Bote de remos")
## Largo del bote, en metros.
@export var longboat_length: float = 6.0
## Manga (ancho) del bote, en metros.
@export var longboat_beam: float = 1.8
## Alto del bote de la quilla a la borda, en metros.
@export var longboat_depth: float = 0.8
## Inclinación del bote hacia un costado, en grados.
@export var longboat_tilt_deg: float = 14.0
## Hasta dónde lo llena la arena, como fracción del alto (0 a 1).
@export_range(0.0, 1.0) var sand_fill: float = 0.55
## Largo de un remo entero, en metros (los dos están quebrados).
@export var oar_length: float = 2.8

@export_group("Corales")
## Bultos de coral o percebes pegados al casco.
@export_range(0, 20) var growth_count: int = 6
## Radio mínimo de un bulto, en metros.
@export var growth_size_min: float = 0.2
## Radio máximo de un bulto, en metros.
@export var growth_size_max: float = 0.45

@export_group("Colores")
## Color de las tablas oscuras.
@export var plank_dark_color: Color = Color(0.5, 0.36, 0.24)
## Color de las tablas claras.
@export var plank_light_color: Color = Color(0.68, 0.52, 0.36)
## Color de la madera podrida (y del interior del casco).
@export var rot_color: Color = Color(0.36, 0.46, 0.34)
## Color de la arena que lo cubre o lo llena.
@export var sand_color: Color = Color(0.82, 0.78, 0.62)
## Colores de los corales: cada bulto toma uno.
@export var growth_colors: Array[Color] = [Color(0.95, 0.42, 0.38), Color(0.3, 0.8, 0.75)]


var _rng := RandomNumberGenerator.new()
var _hull: Hull


func _ready() -> void:
	_rng.seed = shape_seed
	var mesh := LowPolyMesh.new(shape_seed)
	_hull = Hull.new(_rng)
	_hull.plank_thickness = plank_thickness
	_hull.rot_chance = rot_chance
	_hull.dark_color = plank_dark_color
	_hull.light_color = plank_light_color
	_hull.rot_color = rot_color
	match kind:
		Kind.SLOOP_BOW:
			_build_sloop(mesh)
		Kind.CAPSIZED:
			_build_capsized(mesh)
		Kind.LONGBOAT:
			_build_longboat(mesh)
	_build_growths(mesh)
	add_child(mesh.instance("SunkenBoat"))


func _build_sloop(mesh: LowPolyMesh) -> void:
	var angle := deg_to_rad(sloop_angle_deg)
	# El casco sigue hacia atrás lo justo para que su corte quede `bury_depth`
	# bajo la arena; lo que asoma mide `sloop_length`.
	_hull.shape(sloop_length, sloop_beam, sloop_depth, 1.0, -bury_depth / sin(angle), sloop_length)
	var turn := Basis(Vector3.BACK, angle) * Basis(Vector3.RIGHT, _rng.randf_range(-0.15, 0.15))
	# En x = 0 del casco el punto más alto de la borda toca la arena.
	var top := _hull.outer(0.0, 1.0, 1.0)
	for side: float in [-1.0, 1.0]:
		for strake in Hull.STRAKES + 1:
			var point := _hull.outer(0.0, float(strake) / Hull.STRAKES, side)
			if (turn * point).y > (turn * top).y:
				top = point
	var lift := -(turn * top).y
	# Centra en X lo que asoma: de donde la borda entra en la arena a la punta.
	var entry := (turn * top).x
	var tip := (turn * Vector3(sloop_length, _hull.depth_at(sloop_length), 0.0)).x
	var keel_entry := (turn * Vector3(-lift / turn.x.y, 0.0, 0.0)).x
	_hull.frame = Transform3D(turn, Vector3(-(entry + tip) * 0.5, lift, 0.0))
	_hull.make_holes(1)
	_hull.build_shell(mesh)
	_hull.build_deck(mesh, 0.45)
	var mast_x := sloop_length * 0.32
	_hull.post(mesh, _hull.frame, Vector3(mast_x, 0.0, 0.0),
			Vector3(mast_x, _hull.depth_at(mast_x) + mast_stump_height, 0.0), 0.3,
			plank_light_color)
	var stem := Vector3(sloop_length - 1.0, _hull.depth_at(sloop_length), 0.0)
	var reach := Vector3(cos(0.26), sin(0.26), 0.0) * (bowsprit_length + 1.0)
	_hull.post(mesh, _hull.frame, stem, stem + reach, 0.18, plank_dark_color)
	var crossing := (entry + keel_entry) * 0.5 + _hull.frame.origin.x
	_sand_mound(mesh, Vector3(crossing, 0.0, 0.0),
			Vector3(sloop_beam * 0.6, 0.7, sloop_beam * 0.7))


func _build_capsized(mesh: LowPolyMesh) -> void:
	_hull.shape(capsized_length * 0.5, capsized_beam, capsized_height + CAPSIZED_SINK, 0.6,
			-capsized_length * 0.5, capsized_length * 0.5)
	var turn := Basis(Vector3.UP, _rng.randf_range(-0.05, 0.05)) \
			* Basis(Vector3.RIGHT, PI + _rng.randf_range(-0.08, 0.08))
	_hull.frame = Transform3D(turn, Vector3(0.0, capsized_height, 0.0))
	_hull.make_holes(_rng.randi_range(mini(2, capsized_holes), capsized_holes))
	_hull.build_shell(mesh)
	_hull.build_transom(mesh)
	# La quilla: una viga a lo largo del lomo.
	var keel := Transform3D(Basis.IDENTITY, Vector3(0.0, -0.12, 0.0))
	mesh.block(_hull.frame * keel, Vector3(capsized_length * 0.94, 0.26, 0.28), plank_dark_color)
	# El timón asoma por la popa, un poco girado sobre su eje.
	var tall := _hull.depth * 0.4 + rudder_height
	var rudder := Transform3D(Basis(Vector3.UP, _rng.randf_range(-0.4, 0.4)),
			Vector3(-_hull.half_length - 0.4, _hull.depth * 0.4 - tall * 0.5, 0.0))
	mesh.block(_hull.frame * rudder, Vector3(1.0, tall, 0.16), plank_light_color)
	for side: float in [-1.0, 1.0]:
		for index in 2:
			var along := _rng.randf_range(-0.35, 0.35) * capsized_length
			_sand_mound(mesh, Vector3(along, 0.0, side * capsized_beam * 0.5),
					Vector3(_rng.randf_range(2.0, 3.2), 0.55, 1.1))


func _build_longboat(mesh: LowPolyMesh) -> void:
	_hull.shape(longboat_length * 0.5, longboat_beam, longboat_depth, 0.45,
			-longboat_length * 0.5, longboat_length * 0.5)
	var lean := 1.0 if _rng.randf() < 0.5 else -1.0
	var turn := Basis(Vector3.UP, _rng.randf_range(-0.2, 0.2)) \
			* Basis(Vector3.RIGHT, lean * deg_to_rad(longboat_tilt_deg)) \
			* Basis(Vector3.BACK, _rng.randf_range(-0.06, 0.06))
	_hull.frame = Transform3D(turn, Vector3(0.0, -longboat_depth * 0.3, 0.0))
	_hull.build_shell(mesh)
	_hull.build_transom(mesh)
	_build_sand_fill(mesh)
	for along: float in [-0.25, 0.2]:
		var x := along * longboat_length
		var width := (_hull.half_beam(x) - plank_thickness) * 2.0
		var seat := Transform3D(Basis(Vector3.UP, _rng.randf_range(-0.08, 0.08)),
				Vector3(x, longboat_depth - 0.18, 0.0))
		mesh.block(_hull.frame * seat, Vector3(0.3, 0.06, width), plank_light_color)
	for side: float in [-1.0, 1.0]:
		_build_oar(mesh, side)
	_sand_mound(mesh, Vector3(0.0, 0.0, lean * longboat_beam * 0.55),
			Vector3(longboat_length * 0.4, 0.3, 0.6))


## La arena dentro del bote: una superficie horizontal (en el espacio del
## prop) a `sand_fill` del alto en el medio del bote, un poco más alta al centro.
func _build_sand_fill(mesh: LowPolyMesh) -> void:
	var level := (_hull.frame * Vector3(0.0, longboat_depth * sand_fill, 0.0)).y
	var edges: Array[PackedVector3Array] = []
	for station in Hull.STATIONS:
		edges.append(_fill_edge(_hull.station_x(station), level))
	for station in Hull.STATIONS - 1:
		var ring0 := edges[station]
		var ring1 := edges[station + 1]
		for half in 2:
			var a := ring0[half]
			var c := ring1[half + 1]
			mesh.plate(a, ring1[half], c, ring0[half + 1], sand_color, (a + c) * 0.5 + Vector3.DOWN)


## Borde de la arena en el corte `x`, a la altura `level` del prop: babor,
## medio y estribor, ya en espacio del prop.
func _fill_edge(x: float, level: float) -> PackedVector3Array:
	var port := _hull.frame * _hull.inner(x, _fill_reach(x, -1.0, level), -1.0)
	var starboard := _hull.frame * _hull.inner(x, _fill_reach(x, 1.0, level), 1.0)
	var middle := (port + starboard) * 0.5 + Vector3.UP * _rng.randf_range(0.03, 0.1)
	return PackedVector3Array([port, middle, starboard])


## Altura `s` del forro interior (0 quilla, 1 borda) de la banda `side` donde
## el forro corta la altura `level` del prop. Si la borda queda bajo la arena,
## la arena llega hasta la borda.
func _fill_reach(x: float, side: float, level: float) -> float:
	var low := 0.0
	var high := 1.0
	if (_hull.frame * _hull.inner(x, high, side)).y <= level:
		return high
	# La quilla está bajo `level` y la borda sobre él: hay un corte en el medio.
	for step in FILL_STEPS:
		var middle := (low + high) * 0.5
		if (_hull.frame * _hull.inner(x, middle, side)).y < level:
			low = middle
		else:
			high = middle
	return (low + high) * 0.5


## Un remo quebrado tirado en la arena al lado `side` (±1) del bote.
func _build_oar(mesh: LowPolyMesh, side: float) -> void:
	var yaw := Basis(Vector3.UP, _rng.randf_range(-0.5, 0.5))
	var at := Vector3(_rng.randf_range(-0.3, 0.3) * longboat_length, 0.05,
			side * (longboat_beam * 0.5 + _rng.randf_range(0.6, 1.2)))
	var shaft := oar_length * _rng.randf_range(0.5, 0.85)
	var start := at + yaw * Vector3(-shaft * 0.5, 0.0, 0.0)
	var end := at + yaw * Vector3(shaft * 0.5, 0.0, 0.0)
	_hull.post(mesh, Transform3D.IDENTITY, start, end, 0.06, plank_light_color)
	var blade := Transform3D(yaw, start + yaw * Vector3(-0.4, 0.0, 0.0))
	mesh.block(blade, Vector3(0.9, 0.05, 0.24), plank_dark_color)


## Un montón de arena aplastado contra el naufragio, en espacio del prop.
func _sand_mound(mesh: LowPolyMesh, center: Vector3, radii: Vector3) -> void:
	mesh.blob(center + Vector3.DOWN * radii.y * 0.4, radii, sand_color, 7, 4, 0.12)


func _build_growths(mesh: LowPolyMesh) -> void:
	if growth_colors.is_empty():
		return
	for index in growth_count:
		var x := lerpf(_hull.x_from, _hull.x_to, _rng.randf_range(0.15, 0.85))
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var at := _hull.frame * _hull.outer(x, _rng.randf_range(0.1, 0.8), side)
		var size := _rng.randf_range(growth_size_min, growth_size_max)
		var color := growth_colors[_rng.randi() % growth_colors.size()]
		mesh.blob(at, Vector3(size, size * 0.7, size), color, 6, 3, 0.2)
