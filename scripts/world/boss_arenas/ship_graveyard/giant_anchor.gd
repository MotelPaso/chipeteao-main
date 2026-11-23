class_name GiantAnchor
extends StaticBody3D
## Un ancla gigante medio enterrada en la arena del Cementerio de barcos: la
## caña inclinada, el cepo y la argolla arriba, y abajo la cruz con un brazo
## enterrado y el otro con su uña de punta. Hierro oxidado con percebes y unos
## eslabones de cadena tirados al costado. Es una cobertura de la pelea.
##
## Solo frenan tres cajas que nacen en la arena: la caña baja, la cruz con la
## uña parada y el brazo enterrado. La cadena es adorno (no frena, no pasa de
## medio metro). Todo sale de `shape_seed`: la misma semilla, la misma ancla.

## Grupo que lee quien marca el suelo tapado por las coberturas.
const COVER_GROUP: StringName = &"boss_cover"
## Metros que las cajas bajan bajo la arena.
const SINK: float = 0.5
## Metros de holgura entre la malla y las cajas que la rodean.
const PAD: float = 0.25
## Lados de los tubos (caña y brazos).
const TUBE_SIDES: int = 8
## Tramos de cada brazo.
const ARM_STEPS: int = 6
## Tramos de la caña.
const SHANK_STEPS: int = 6
## Tramos y lados de la argolla.
const RING_STEPS: int = 12
const RING_SIDES: int = 5
## Tramos y lados de cada eslabón.
const LINK_STEPS: int = 8
const LINK_SIDES: int = 4
## Grosor de la uña, en metros.
const FLUKE_THICKNESS: float = 0.2

@export_group("Forma")
## Semilla de la forma: la misma semilla da la misma ancla.
@export var shape_seed: int = 0
## Inclinación de la caña sobre la arena, en grados (90 = parada).
@export_range(30.0, 90.0) var lean_degrees: float = 65.0
## Largo de la caña, en metros.
@export var shank_length: float = 8.0
## Radio de la caña, en metros.
@export var shank_radius: float = 0.45
## Metros que la cruz queda bajo la arena.
@export var bury_depth: float = 0.5
## Largo del cepo (la barra de arriba), en metros.
@export var stock_length: float = 5.0
## Grosor del cepo, en metros.
@export var stock_thickness: float = 0.5
## Radio de la argolla, en metros.
@export var ring_radius: float = 0.8
## Radio de la curva de los brazos, en metros.
@export var arm_curve_radius: float = 2.4
## Radio del tubo de cada brazo, en metros.
@export var arm_radius: float = 0.32
## Cuánto se curva el brazo con la uña parada, en grados.
@export var standing_arm_degrees: float = 100.0
## Cuánto se curva el brazo que se mete en la arena, en grados.
@export var buried_arm_degrees: float = 60.0
## Largo de cada uña, en metros.
@export var fluke_length: float = 1.5
## Ancho de cada uña, en metros.
@export var fluke_width: float = 2.0
## Percebes pegados a la caña y los brazos.
@export_range(0, 30) var barnacles: int = 14

@export_group("Cadena")
## Eslabones tirados en la arena.
@export_range(0, 8) var chain_links: int = 5
## Largo de cada eslabón, en metros.
@export var link_length: float = 0.9
## Ancho de cada eslabón, en metros.
@export var link_width: float = 0.5
## Radio del hierro del eslabón, en metros.
@export var link_bar_radius: float = 0.08
## Hacia dónde se aleja la cadena de la cruz, en grados (0 = eje X).
@export var chain_yaw_degrees: float = 70.0

@export_group("Colisión")
## Hasta qué alto frena la caja de la caña, en metros.
@export var shank_cover_height: float = 3.4

@export_group("Colores")
## Color del hierro.
@export var iron_color: Color = Color(0.3, 0.32, 0.36)
## Color del óxido.
@export var rust_color: Color = Color(0.74, 0.4, 0.2)
## Cuánto óxido puede tener cada tramo (0 = nada, 1 = todo óxido).
@export_range(0.0, 1.0) var rust_amount: float = 0.75
## Color de los percebes.
@export var barnacle_color: Color = Color(0.85, 0.82, 0.72)

var _rng := RandomNumberGenerator.new()
## Punto de la cruz (abajo de la caña); se corre para centrar la huella.
var _crown := Vector3.ZERO


func _enter_tree() -> void:
	add_to_group(COVER_GROUP)


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_rng.seed = shape_seed
	# Primero lo que frena: se mide la huella con la cruz en x = 0 y se corre
	# para que quede centrada en el origen.
	_crown = Vector3(0.0, -bury_depth, 0.0)
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for points: PackedVector3Array in _cover_point_sets():
		for point: Vector3 in points:
			low = low.min(Vector2(point.x, point.z))
			high = high.max(Vector2(point.x, point.z))
	var middle := (low + high) * 0.5
	_crown -= Vector3(middle.x, 0.0, middle.y)
	var names: Array[String] = ["CrownCover", "ShankCover", "BuriedArmCover"]
	var sets := _cover_point_sets()
	for index in sets.size():
		_add_box_around(sets[index], names[index])
	var mesh := LowPolyMesh.new(shape_seed)
	_build_shank(mesh)
	_build_arms(mesh)
	_build_barnacles(mesh)
	_build_chain(mesh)
	add_child(mesh.instance("Anchor"))


## Eje de la caña (de la cruz hacia arriba).
func _axis() -> Vector3:
	var lean := deg_to_rad(lean_degrees)
	return Vector3(cos(lean), sin(lean), 0.0)


## Perpendicular a la caña en el plano de los brazos.
func _side() -> Vector3:
	var lean := deg_to_rad(lean_degrees)
	return Vector3(-sin(lean), cos(lean), 0.0)


## Punto del brazo `arm` (+1 parado, -1 enterrado) a `angle` radianes de la cruz.
func _arm_point(arm: float, angle: float) -> Vector3:
	var center := _crown + _axis() * arm_curve_radius
	return center + (-_axis() * cos(angle) + _side() * arm * sin(angle)) * arm_curve_radius


## Dirección del brazo en ese punto.
func _arm_tangent(arm: float, angle: float) -> Vector3:
	return (_axis() * sin(angle) + _side() * arm * cos(angle)).normalized()


## Los puntos que encierra cada caja: cruz con brazo parado, caña baja y
## brazo enterrado.
func _cover_point_sets() -> Array[PackedVector3Array]:
	var crown := PackedVector3Array()
	var standing := deg_to_rad(standing_arm_degrees)
	for step in ARM_STEPS + 1:
		var angle := standing * float(step) / float(ARM_STEPS)
		crown.append_array(_tube_ring(_arm_point(1.0, angle), _arm_tangent(1.0, angle), arm_radius))
	crown.append_array(_fluke_outline(1.0))
	var shank := PackedVector3Array()
	var reach := (shank_cover_height - _crown.y) / _axis().y
	for along: float in [0.0, minf(reach, shank_length)]:
		shank.append_array(_tube_ring(_crown + _axis() * along, _axis(), shank_radius))
	var buried := PackedVector3Array()
	var sunk := deg_to_rad(buried_arm_degrees)
	for step in ARM_STEPS + 1:
		var angle := sunk * float(step) / float(ARM_STEPS)
		buried.append_array(_tube_ring(_arm_point(-1.0, angle), _arm_tangent(-1.0, angle),
				arm_radius))
	buried.append_array(_fluke_outline(-1.0))
	return [crown, shank, buried]


## Una caja derecha que nace bajo la arena y encierra `points` (en planta),
## alta hasta el punto más alto de ellos.
func _add_box_around(points: PackedVector3Array, node_name: String) -> void:
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for point: Vector3 in points:
		low = low.min(point)
		high = high.max(point)
	var shape := BoxShape3D.new()
	shape.size = Vector3(high.x - low.x + PAD * 2.0, high.y + SINK, high.z - low.z + PAD * 2.0)
	var holder := CollisionShape3D.new()
	holder.name = node_name
	holder.shape = shape
	holder.position = Vector3((low.x + high.x) * 0.5, (high.y - SINK) * 0.5, (low.z + high.z) * 0.5)
	add_child(holder)


## Un anillo de puntos de radio `radius` alrededor de `center`, perpendicular
## a `tangent`. `reference` fija hacia dónde mira el primer punto.
func _tube_ring(center: Vector3, tangent: Vector3, radius: float,
		reference: Vector3 = Vector3.BACK) -> PackedVector3Array:
	var across := tangent.cross(reference).normalized()
	var other := across.cross(tangent).normalized()
	var points := PackedVector3Array()
	for index in TUBE_SIDES:
		var angle := TAU * float(index) / float(TUBE_SIDES)
		points.append(center + (across * cos(angle) + other * sin(angle)) * radius)
	return points


## Color de un tramo de hierro, con más o menos óxido.
func _rusty() -> Color:
	return iron_color.lerp(rust_color, _rng.randf_range(0.0, rust_amount))


func _build_shank(mesh: LowPolyMesh) -> void:
	var rings: Array[PackedVector3Array] = []
	for step in SHANK_STEPS + 1:
		var along := shank_length * float(step) / float(SHANK_STEPS)
		var radius := shank_radius * lerpf(1.0, 0.85, float(step) / float(SHANK_STEPS))
		rings.append(_tube_ring(_crown + _axis() * along, _axis(), radius))
	for step in SHANK_STEPS:
		mesh.band(rings[step], rings[step + 1], _rusty())
	var top := _crown + _axis() * shank_length
	mesh.cap(rings[SHANK_STEPS], _rusty(), top - _axis())
	# El cepo cruza la caña cerca de la punta, de lado a lado del plano de los brazos.
	var stock_at := top - _axis() * stock_thickness * 2.0
	var frame := Transform3D(Basis(Vector3.BACK, _axis(), _side()), stock_at)
	mesh.box(frame, Vector3(stock_length, stock_thickness, stock_thickness), _rusty())
	for end: float in [-0.5, 0.5]:
		var knob := stock_at + Vector3.BACK * stock_length * end
		mesh.blob(knob, Vector3.ONE * stock_thickness * 0.75, _rusty(), 6, 3, 0.1)
	# La argolla pasa por el ojo de la punta.
	var ring_center := top + _axis() * ring_radius * 0.7
	var path := PackedVector3Array()
	for step in RING_STEPS:
		var angle := TAU * float(step) / float(RING_STEPS)
		path.append(ring_center + (_axis() * cos(angle) + Vector3.BACK * sin(angle)) * ring_radius)
	_closed_tube(mesh, path, ring_radius * 0.2, _side(), RING_SIDES)


func _build_arms(mesh: LowPolyMesh) -> void:
	for arm: float in [1.0, -1.0]:
		var sweep := deg_to_rad(standing_arm_degrees if arm > 0.0 else buried_arm_degrees)
		var previous := PackedVector3Array()
		for step in ARM_STEPS + 1:
			var angle := sweep * float(step) / float(ARM_STEPS)
			var radius := arm_radius * lerpf(1.25, 0.8, float(step) / float(ARM_STEPS))
			var ring := _tube_ring(_arm_point(arm, angle), _arm_tangent(arm, angle), radius)
			if step > 0:
				mesh.band(previous, ring, _rusty())
			previous = ring
		_build_fluke(mesh, arm)
	mesh.blob(_crown, Vector3.ONE * arm_radius * 1.9, _rusty(), 7, 4, 0.1)


## Contorno de la uña del brazo `arm`: una pala ancha a lo largo de Z.
func _fluke_outline(arm: float) -> PackedVector3Array:
	var angle := deg_to_rad(standing_arm_degrees if arm > 0.0 else buried_arm_degrees)
	var tip := _arm_point(arm, angle)
	var along := _arm_tangent(arm, angle) * fluke_length
	var wide := Vector3.BACK * fluke_width * 0.5
	return PackedVector3Array([tip - along * 0.3 - wide * 0.25, tip + along * 0.25 - wide,
			tip + along * 0.7, tip + along * 0.25 + wide, tip - along * 0.3 + wide * 0.25])


func _build_fluke(mesh: LowPolyMesh, arm: float) -> void:
	var angle := deg_to_rad(standing_arm_degrees if arm > 0.0 else buried_arm_degrees)
	var normal := _arm_tangent(arm, angle).cross(Vector3.BACK).normalized()
	var outline := _fluke_outline(arm)
	var front := PackedVector3Array()
	var back := PackedVector3Array()
	for point: Vector3 in outline:
		front.append(point + normal * FLUKE_THICKNESS * 0.5)
		back.append(point - normal * FLUKE_THICKNESS * 0.5)
	var middle := Vector3.ZERO
	for point: Vector3 in outline:
		middle += point / float(outline.size())
	var color := _rusty()
	mesh.band(back, front, color)
	mesh.cap(front, color, middle)
	mesh.cap(back, color, middle)


func _build_barnacles(mesh: LowPolyMesh) -> void:
	for index in barnacles:
		var center: Vector3
		var tangent: Vector3
		var radius: float
		if _rng.randf() < 0.6:
			var along := _rng.randf_range(0.15, 0.75) * shank_length
			center = _crown + _axis() * along
			tangent = _axis()
			radius = shank_radius
		else:
			var arm := 1.0 if _rng.randf() < 0.65 else -1.0
			var sweep := deg_to_rad(standing_arm_degrees if arm > 0.0 else buried_arm_degrees)
			var angle := _rng.randf_range(0.2, 0.9) * sweep
			center = _arm_point(arm, angle)
			tangent = _arm_tangent(arm, angle)
			radius = arm_radius
		var spin := _rng.randf() * TAU
		var out := tangent.cross(Vector3.BACK).normalized().rotated(tangent, spin)
		var size := _rng.randf_range(0.12, 0.22)
		mesh.blob(center + out * radius, Vector3(size, size * 0.7, size), barnacle_color, 5, 3, 0.12)


## Eslabones tirados en la arena desde la cruz, unos acostados y otros de canto.
func _build_chain(mesh: LowPolyMesh) -> void:
	var yaw := deg_to_rad(chain_yaw_degrees)
	var at := Vector3(_crown.x + shank_radius, 0.0, shank_radius + link_length * 0.5)
	for index in chain_links:
		var forward := Vector3(cos(yaw), 0.0, sin(yaw))
		var tilt := 0.0 if index % 2 == 0 else deg_to_rad(40.0)
		var across := forward.cross(Vector3.UP).normalized().rotated(forward, tilt)
		var lift := link_width * 0.5 * sin(tilt) + link_bar_radius * 0.6
		var center := at + Vector3.UP * lift
		var path := PackedVector3Array()
		for step in LINK_STEPS:
			var angle := TAU * float(step) / float(LINK_STEPS)
			path.append(center + forward * cos(angle) * (link_length - link_width) * 0.5
					+ (forward * cos(angle) + across * sin(angle)) * link_width * 0.5)
		_closed_tube(mesh, path, link_bar_radius, forward.cross(across), LINK_SIDES)
		at += forward * link_length * 0.72
		yaw += _rng.randf_range(-0.25, 0.25)


## Un tubo cerrado de `sides` lados que sigue el lazo `path`; `normal` es la
## normal del plano del lazo.
func _closed_tube(mesh: LowPolyMesh, path: PackedVector3Array, radius: float, normal: Vector3,
		sides: int) -> void:
	var rings: Array[PackedVector3Array] = []
	var count := path.size()
	for index in count:
		var tangent := (path[(index + 1) % count] - path[(index - 1 + count) % count]).normalized()
		var outward := normal.cross(tangent).normalized()
		var ring := PackedVector3Array()
		for side in sides:
			var angle := TAU * float(side) / float(sides)
			ring.append(path[index] + (outward * cos(angle) + normal * sin(angle)) * radius)
		rings.append(ring)
	var color := _rusty()
	for index in count:
		mesh.band(rings[index], rings[(index + 1) % count], color)
