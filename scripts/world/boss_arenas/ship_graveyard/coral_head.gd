class_name CoralHead
extends StaticBody3D
## Una roca de coral cerebro gigante en el claro del Cementerio de barcos: una
## cúpula abollada con corales chicos de colores encima y en los hombros
## (tubos con ramas, abanicos y perillas). Es una cobertura de la pelea.
##
## Frena un cilindro que nace bajo la arena. La cúpula y los corales bajos
## quedan dentro de él; solo lo que pasa de `overhang_height` puede asomar
## hasta `overhang` metros. Todo sale de `shape_seed`.

## Grupo que lee quien marca el suelo tapado por las coberturas.
const COVER_GROUP: StringName = &"boss_cover"
## Lados de los tubos de coral.
const TUBE_SIDES: int = 5
## Intentos para ubicar cada coral antes de dejarlo.
const TRIES: int = 6
## Lados de cada abanico.
const FAN_POINTS: int = 6

@export_group("Forma")
## Semilla de la forma: la misma semilla da la misma roca.
@export var shape_seed: int = 0
## Radio de la cúpula, en metros.
@export var dome_radius: float = 2.25
## Alto de la cúpula sobre la arena, en metros.
@export var dome_top: float = 3.4
## Alto del centro de la cúpula, en metros (más bajo = más enterrada).
@export var dome_center_height: float = 1.0
## Lados de la cúpula alrededor.
@export_range(7, 20) var dome_segments: int = 14
## Anillos de la cúpula de arriba abajo.
@export_range(4, 12) var dome_rings: int = 8
## Cuánto se abolla la cúpula (0 = lisa).
@export_range(0.0, 0.2) var dome_wobble: float = 0.05
## Grupos de tubos de coral con ramas.
@export_range(0, 14) var tube_clusters: int = 12
## Largo de cada tubo, en metros.
@export var tube_length: float = 0.7
## Radio de cada tubo, en metros.
@export var tube_radius: float = 0.09
## Abanicos de coral arriba.
@export_range(0, 5) var fans: int = 5
## Ancho de cada abanico, en metros.
@export var fan_size: float = 1.0
## Perillas redondas en los hombros.
@export_range(0, 20) var knobs: int = 16

@export_group("Colisión")
## Radio del cilindro que frena, en metros.
@export var cover_radius: float = 2.4
## Alto del cilindro que frena, en metros (sin contar lo enterrado).
@export var cover_height: float = 2.7
## Metros que el cilindro baja bajo la arena.
@export var cover_sink: float = 0.3
## Desde qué alto un coral puede salir del cilindro, en metros.
@export var overhang_height: float = 2.5
## Cuánto puede salir del cilindro lo que pasa de ese alto, en metros.
@export var overhang: float = 0.5

@export_group("Colores")
## Color de la roca de coral.
@export var boulder_color: Color = Color(0.96, 0.52, 0.44)
## Colores de los corales chicos: cada uno toma uno.
@export var coral_colors: Array[Color] = [Color(0.95, 0.42, 0.38), Color(0.98, 0.62, 0.25),
		Color(0.75, 0.4, 0.85), Color(0.3, 0.8, 0.75), Color(0.95, 0.85, 0.4)]

var _rng := RandomNumberGenerator.new()


func _enter_tree() -> void:
	add_to_group(COVER_GROUP)


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_rng.seed = shape_seed
	var shape := CylinderShape3D.new()
	shape.radius = cover_radius
	shape.height = cover_height + cover_sink
	var holder := CollisionShape3D.new()
	holder.name = "CoralCover"
	holder.shape = shape
	holder.position = Vector3.UP * (cover_height - cover_sink) * 0.5
	add_child(holder)
	var mesh := LowPolyMesh.new(shape_seed)
	var radii := _radii()
	mesh.blob(_dome_center(), radii, boulder_color, dome_segments, dome_rings, dome_wobble)
	for index in tube_clusters:
		_grow_tubes(mesh, _rng.randf_range(0.0, deg_to_rad(65.0)))
	for index in fans:
		_grow_fan(mesh)
	for index in knobs:
		_grow_knob(mesh)
	add_child(mesh.instance("CoralHead"))


func _dome_center() -> Vector3:
	return Vector3.UP * dome_center_height


func _radii() -> Vector3:
	return Vector3(dome_radius, dome_top - dome_center_height, dome_radius)


## Punto de la cúpula a `polar` radianes de la cima y `turn` alrededor, con
## su normal; la superficie se toma un poco hacia dentro por la abolladura.
func _surface(polar: float, turn: float) -> Array[Vector3]:
	var radii := _radii() * (1.0 - dome_wobble)
	var offset := Vector3(sin(polar) * cos(turn), cos(polar), sin(polar) * sin(turn))
	var point := _dome_center() + offset * radii
	var normal := Vector3(offset.x / radii.x, offset.y / radii.y, offset.z / radii.z).normalized()
	return [point, normal]


## True si un punto con radio `size` alrededor queda donde puede estar:
## dentro del cilindro abajo, o asomando poco arriba.
func _fits(point: Vector3, size: float) -> bool:
	var reach := Vector2(point.x, point.z).length() + size
	var limit := cover_radius - 0.05
	if point.y - size >= overhang_height:
		limit += overhang
	return reach <= limit


func _pick_color() -> Color:
	if coral_colors.is_empty():
		return boulder_color
	return coral_colors[_rng.randi() % coral_colors.size()]


## Un tubo con una o dos ramas, parado sobre la cúpula a `polar` de la cima.
func _grow_tubes(mesh: LowPolyMesh, polar: float) -> void:
	for attempt in TRIES:
		var spot := _surface(polar, _rng.randf() * TAU)
		var foot: Vector3 = spot[0] - spot[1] * tube_radius
		var up: Vector3 = (spot[1] + Vector3.UP * 1.2).normalized()
		var length := tube_length * _rng.randf_range(0.7, 1.2)
		var tip := foot + up * length
		if not _fits(tip, tube_radius) or not _fits(foot, tube_radius):
			polar *= 0.7
			continue
		var color := _pick_color()
		_tube(mesh, foot, tip, tube_radius, color)
		for branch in _rng.randi_range(1, 2):
			var side := up.cross(Vector3(_rng.randf() - 0.5, 0.0, _rng.randf() - 0.5)).normalized()
			var from := foot.lerp(tip, _rng.randf_range(0.4, 0.7))
			var to := from + (up + side * 0.8).normalized() * length * 0.55
			if _fits(to, tube_radius):
				_tube(mesh, from, to, tube_radius * 0.75, color)
		return


## Un abanico chato y casi parado arriba de la cúpula.
func _grow_fan(mesh: LowPolyMesh) -> void:
	for attempt in TRIES:
		var spot := _surface(_rng.randf_range(0.0, deg_to_rad(35.0)), _rng.randf() * TAU)
		var foot: Vector3 = spot[0] - spot[1] * 0.1
		var size := fan_size * _rng.randf_range(0.7, 1.1)
		var facing := Vector3.FORWARD.rotated(Vector3.UP, _rng.randf() * TAU)
		var across := facing.cross(Vector3.UP).normalized()
		var outline := PackedVector3Array()
		for index in FAN_POINTS:
			var angle := PI * float(index) / float(FAN_POINTS - 1)
			var reach := size * 0.5 * _rng.randf_range(0.85, 1.0)
			outline.append(foot + across * cos(angle) * reach + Vector3.UP * sin(angle) * reach * 1.3)
		var fits := true
		for point: Vector3 in outline:
			fits = fits and _fits(point, 0.05)
		if not fits:
			continue
		var front := PackedVector3Array()
		var back := PackedVector3Array()
		for point: Vector3 in outline:
			front.append(point + facing * 0.04)
			back.append(point - facing * 0.04)
		var middle := foot + Vector3.UP * size * 0.3
		var color := _pick_color()
		mesh.band(back, front, color)
		mesh.cap(front, color, middle)
		mesh.cap(back, color, middle)
		return


## Una perilla redonda medio hundida en los hombros de la cúpula.
func _grow_knob(mesh: LowPolyMesh) -> void:
	for attempt in TRIES:
		var spot := _surface(_rng.randf_range(deg_to_rad(30.0), deg_to_rad(80.0)), _rng.randf() * TAU)
		var size := _rng.randf_range(0.18, 0.34)
		var center: Vector3 = spot[0] - spot[1] * size * 0.35
		if not _fits(center, size):
			continue
		mesh.blob(center, Vector3(size, size * 0.8, size), _pick_color(), 6, 3, 0.1)
		return


## Un tubo de `TUBE_SIDES` lados de `from` a `to`, apenas más fino en la punta.
func _tube(mesh: LowPolyMesh, from: Vector3, to: Vector3, radius: float, color: Color) -> void:
	var axis := (to - from).normalized()
	var across := axis.cross(Vector3.RIGHT if absf(axis.x) < 0.9 else Vector3.BACK).normalized()
	var other := across.cross(axis).normalized()
	var lower := PackedVector3Array()
	var upper := PackedVector3Array()
	for index in TUBE_SIDES:
		var angle := TAU * float(index) / float(TUBE_SIDES)
		var out := across * cos(angle) + other * sin(angle)
		lower.append(from + out * radius)
		upper.append(to + out * radius * 0.8)
	mesh.band(lower, upper, color)
	mesh.cap(upper, color.lightened(0.15), from)
