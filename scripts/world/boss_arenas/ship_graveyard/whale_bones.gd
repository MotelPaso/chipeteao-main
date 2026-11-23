class_name WhaleBones
extends Node3D
## El esqueleto de una ballena gigante tumbada de espaldas en el fondo del
## mar, armado en código (LowPolyMesh): una columna medio enterrada, costillas
## que suben de la arena como una hilera de pilares curvos, el cráneo con sus
## dos mandíbulas tiradas al lado y la cola que se achica hasta desaparecer.
##
## Marco local: la columna corre por +X, del cráneo (x = 0) a la cola
## (x = `length`); el cráneo ocupa x < 0. El origen está sobre la arena. Es
## solo decorado: no tiene colisión. La misma semilla da el mismo esqueleto.

## Lados de cada costilla.
const RIB_SIDES: int = 6
## Tramos de cada costilla entera.
const RIB_SEGMENTS: int = 8
## Lados de cada mandíbula.
const JAW_SIDES: int = 5
## Tramos de cada mandíbula.
const JAW_SEGMENTS: int = 8
## Parte de la columna que ocupan las costillas, empezando y terminando a esta
## fracción de cada punta (0.2 = el 60 % del medio).
const RIB_SPAN_MARGIN: float = 0.2
## Cortes del cráneo, de la nuca a la punta.
const SKULL_SECTIONS: int = 4
## Cuánto se hunde la base del cráneo y de las mandíbulas en la arena, en metros.
const SINK: float = 0.3

@export_group("Forma")
## Semilla de la forma: la misma semilla da el mismo esqueleto.
@export var shape_seed: int = 1
## Largo de la columna, del cráneo a la punta de la cola, en metros.
@export var length: float = 38.0
## Alto de la columna sobre la arena, en metros (centro de las vértebras).
@export var spine_height: float = 0.6
## Ancho de una vértebra junto al cráneo, en metros (se achica hacia la cola).
@export var vertebra_size: float = 1.3
## Distancia entre vértebras, en metros.
@export var vertebra_spacing: float = 1.6
## Metros finales de la cola donde las vértebras se achican hasta nada.
@export var tail_length: float = 8.0

@export_group("Costillas")
## Pares de costillas a lo largo del 60 % del medio de la columna.
@export_range(1, 20) var rib_pairs: int = 11
## Alto de las costillas más altas (las del medio), en metros.
@export var rib_height_max: float = 14.0
## Alto de las costillas de las puntas, en metros.
@export var rib_height_min: float = 6.0
## Cuánto se abren hacia los lados, como fracción de su alto (0.5 = la mitad).
@export var rib_spread: float = 0.5
## Separación mínima entre las dos puntas de un par, en metros.
@export var tip_gap_min: float = 3.0
## Separación máxima entre las dos puntas de un par, en metros.
@export var tip_gap_max: float = 5.0
## Metros que la punta de cada costilla se corre hacia la cola.
@export var rib_sweep: float = 1.5
## Grosor (radio) de una costilla en su base, en metros.
@export var rib_thickness: float = 0.45
## Costillas quebradas a media altura (se eligen con la semilla).
@export_range(0, 12) var broken_ribs: int = 3

@export_group("Cráneo")
## Largo del cráneo, en metros (va de x = 0 hacia x negativo).
@export var skull_length: float = 9.0
## Ancho del cráneo en la nuca, en metros.
@export var skull_width: float = 4.6
## Alto del cráneo en la nuca, en metros.
@export var skull_height: float = 2.4
## Largo de cada mandíbula tirada al lado del cráneo, en metros.
@export var jaw_length: float = 10.0
## Grosor (radio) de una mandíbula en la nuca, en metros.
@export var jaw_thickness: float = 0.5

@export_group("Corales")
## Bultos de coral o percebes pegados a los huesos.
@export_range(0, 30) var growth_count: int = 10
## Radio mínimo de un bulto, en metros.
@export var growth_size_min: float = 0.35
## Radio máximo de un bulto, en metros.
@export var growth_size_max: float = 0.8

@export_group("Colores")
## Color del hueso a la luz.
@export var bone_color: Color = Color(0.86, 0.84, 0.76)
## Color del hueso en sombra (vértebras, bases de las costillas).
@export var bone_shade_color: Color = Color(0.7, 0.69, 0.62)
## Colores de los corales: cada bulto toma uno.
@export var growth_colors: Array[Color] = [Color(0.95, 0.42, 0.38), Color(0.3, 0.8, 0.75)]

var _rng := RandomNumberGenerator.new()
## Puntos de cada costilla y su radio, para pegarles corales.
var _rib_paths: Array[PackedVector3Array] = []
var _rib_radii: Array[PackedFloat32Array] = []


func _ready() -> void:
	_rng.seed = shape_seed
	var mesh := LowPolyMesh.new(shape_seed)
	_build_spine(mesh)
	_build_ribs(mesh)
	_build_skull(mesh)
	_build_jaws(mesh)
	_build_growths(mesh)
	var view := mesh.instance("WhaleBones")
	add_child(view)


## Escala de una vértebra a `x` metros del cráneo: 1 en la nuca, 0.7 donde
## empieza la cola y casi nada en la punta.
func _spine_scale(x: float) -> float:
	var tail_start := maxf(length - tail_length, 0.01)
	if x < tail_start:
		return lerpf(1.0, 0.7, x / tail_start)
	return lerpf(0.7, 0.05, clampf((x - tail_start) / maxf(tail_length, 0.01), 0.0, 1.0))


func _build_spine(mesh: LowPolyMesh) -> void:
	var count := maxi(int(length / maxf(vertebra_spacing, 0.1)), 2)
	for index in count + 1:
		var x := length * float(index) / float(count)
		var grow := _spine_scale(x)
		var size := Vector3(vertebra_spacing * 0.72, vertebra_size * 0.85 * grow,
				vertebra_size * grow)
		var turn := Basis.from_euler(Vector3(_rng.randf_range(-0.12, 0.12),
				_rng.randf_range(-0.1, 0.1), _rng.randf_range(-0.06, 0.06)))
		var frame := Transform3D(turn, Vector3(x, spine_height * grow, 0.0))
		mesh.block(frame, size, bone_shade_color)


func _build_ribs(mesh: LowPolyMesh) -> void:
	var broken: Array[int] = []
	var total := rib_pairs * 2
	while broken.size() < mini(broken_ribs, total):
		var pick := _rng.randi() % total
		if not broken.has(pick):
			broken.append(pick)
	var start := length * RIB_SPAN_MARGIN
	var span := length * (1.0 - RIB_SPAN_MARGIN * 2.0)
	for pair in rib_pairs:
		var along := (float(pair) + 0.5) / float(rib_pairs)
		var x := start + span * along
		var height := lerpf(rib_height_min, rib_height_max, sin(PI * along))
		var tip_half := _rng.randf_range(tip_gap_min, tip_gap_max) * 0.5
		for side: float in [-1.0, 1.0]:
			var index := pair * 2 + (0 if side < 0.0 else 1)
			var reach := _rng.randf_range(0.3, 0.6) if broken.has(index) else 1.0
			_build_rib(mesh, x, height * _rng.randf_range(0.94, 1.04), side, tip_half, reach)


## Una costilla que sale de la columna en `x` hacia el lado `side` (±1),
## sube `height` metros y termina a `tip_half` metros del eje. `reach` < 1
## la deja quebrada a esa fracción del largo.
func _build_rib(mesh: LowPolyMesh, x: float, height: float, side: float, tip_half: float,
		reach: float) -> void:
	var spread := height * rib_spread
	var base := Vector3(x, spine_height, side * vertebra_size * 0.3)
	var out := Vector3(x + rib_sweep * 0.2, spine_height, side * spread)
	var rise := Vector3(x + rib_sweep * 0.7, height * 0.85, side * spread * 1.05)
	var tip := Vector3(x + rib_sweep, height, side * tip_half)
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	var steps := maxi(roundi(RIB_SEGMENTS * reach), 2)
	for step in steps + 1:
		var t := reach * float(step) / float(steps)
		path.append(_bezier(base, out, rise, tip, t))
		radii.append(rib_thickness * lerpf(1.0, 0.4, t))
	_tube(mesh, path, radii, RIB_SIDES, Vector3.RIGHT, bone_shade_color, bone_color, false)
	_rib_paths.append(path)
	_rib_radii.append(radii)


func _build_skull(mesh: LowPolyMesh) -> void:
	var sections: Array[PackedVector3Array] = []
	var centers: Array[Vector3] = []
	for index in SKULL_SECTIONS:
		var t := float(index) / float(SKULL_SECTIONS - 1)
		var x := -skull_length * t
		var half := lerpf(skull_width, skull_width * 0.2, t) * 0.5
		var tall := lerpf(skull_height, skull_height * 0.3, t)
		var bottom := -SINK
		var section := PackedVector3Array()
		for corner: Vector2 in [Vector2(1.0, 0.35), Vector2(0.6, 1.0), Vector2(-0.6, 1.0),
				Vector2(-1.0, 0.35), Vector2(-0.6, 0.0), Vector2(0.6, 0.0)]:
			var wobble := _rng.randf_range(0.94, 1.06)
			section.append(Vector3(x, bottom + corner.y * tall * wobble, corner.x * half * wobble))
		sections.append(section)
		centers.append(Vector3(x, bottom + tall * 0.5, 0.0))
	for index in SKULL_SECTIONS - 1:
		mesh.band(sections[index], sections[index + 1], bone_color)
	mesh.cap(sections[0], bone_shade_color, centers[1])
	mesh.cap(sections[SKULL_SECTIONS - 1], bone_color, centers[SKULL_SECTIONS - 2])
	# Los dos cóndilos de la nuca, donde el cráneo se une a la columna.
	for side: float in [-1.0, 1.0]:
		var knob := Vector3(0.2, skull_height * 0.45 - SINK, side * skull_width * 0.18)
		mesh.blob(knob, Vector3.ONE * skull_height * 0.28, bone_shade_color, 6, 3, 0.1)


func _build_jaws(mesh: LowPolyMesh) -> void:
	for side: float in [-1.0, 1.0]:
		var rear := Vector3(0.6, jaw_thickness * 0.6 - SINK, side * skull_width * 0.5)
		var bow := Vector3(-jaw_length * 0.45, rear.y, side * (skull_width * 0.8
				+ _rng.randf_range(0.0, 1.2)))
		var front := Vector3(0.6 - jaw_length, rear.y * 0.7, side * skull_width * 0.3)
		# Cada mandíbula quedó un poco girada al caer.
		var turn := Basis(Vector3.UP, _rng.randf_range(-0.12, 0.12))
		var path := PackedVector3Array()
		var radii := PackedFloat32Array()
		for step in JAW_SEGMENTS + 1:
			var t := float(step) / float(JAW_SEGMENTS)
			var point := rear.lerp(bow, t).lerp(bow.lerp(front, t), t)
			path.append(rear + turn * (point - rear))
			radii.append(jaw_thickness * lerpf(1.0, 0.45, t))
		_tube(mesh, path, radii, JAW_SIDES, Vector3.UP, bone_shade_color, bone_color, true)


func _build_growths(mesh: LowPolyMesh) -> void:
	if growth_colors.is_empty() or _rib_paths.is_empty():
		return
	for index in growth_count:
		var rib := _rng.randi() % _rib_paths.size()
		var path := _rib_paths[rib]
		var at := _rng.randi_range(1, path.size() - 1)
		var size := maxf(_rib_radii[rib][at] * 1.3,
				_rng.randf_range(growth_size_min, growth_size_max))
		var color := growth_colors[_rng.randi() % growth_colors.size()]
		mesh.blob(path[at], Vector3(size, size * 0.8, size), color, 6, 3, 0.2)


## Un tubo de `sides` lados por los puntos de `path`, de radio `radii` en
## cada punto. `reference` no puede quedar paralelo al tubo: fija hacia dónde
## mira la primera arista. Pasa de `low` a `high` a lo largo. Siempre tapa la
## punta; `cap_start` tapa también el comienzo.
func _tube(mesh: LowPolyMesh, path: PackedVector3Array, radii: PackedFloat32Array, sides: int,
		reference: Vector3, low: Color, high: Color, cap_start: bool) -> void:
	var rings: Array[PackedVector3Array] = []
	var last := path.size() - 1
	for index in path.size():
		var tangent := (path[mini(index + 1, last)] - path[maxi(index - 1, 0)]).normalized()
		var across := tangent.cross(reference).normalized()
		var over := across.cross(tangent)
		var points := PackedVector3Array()
		for corner in sides:
			var angle := TAU * float(corner) / float(sides)
			points.append(path[index] + (across * cos(angle) + over * sin(angle)) * radii[index])
		rings.append(points)
	for index in last:
		var color := low.lerp(high, float(index) / float(maxi(last - 1, 1)))
		mesh.band(rings[index], rings[index + 1], color)
	mesh.cap(rings[last], high, path[last].lerp(path[last - 1], 0.5))
	if cap_start:
		mesh.cap(rings[0], low, path[0].lerp(path[1], 0.5))


## Punto de la curva de Bézier cúbica a-b-c-d en `t` (0 a 1).
func _bezier(a: Vector3, b: Vector3, c: Vector3, d: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	return a * u * u * u + b * 3.0 * u * u * t + c * 3.0 * u * t * t + d * t * t * t
