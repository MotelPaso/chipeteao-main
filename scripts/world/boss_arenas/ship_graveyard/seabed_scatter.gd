class_name SeabedScatter
extends Node3D
## Lo CHICO del fondo marino (nodo Scatter de ShipGraveyard.tscn): conchas,
## estrellas de mar, guijarros, matas de pasto marino, ánforas, tablas y
## balas de cañón repartidas por el claro y su borde. Es decoración baja y
## sin colisión: da escala y deja ver la velocidad sobre la arena sin tapar
## la pelea.
##
## Cada tipo es UN MultiMesh (una malla chica armada con LowPolyMesh y
## repetida con otro giro, tamaño y color), así que todo esto son siete
## dibujos. Nada cae dentro de una cobertura: se le pregunta al nodo
## "arena_bounds" de la arena. Va después del Terrain y de las coberturas en el
## árbol: apoya cada pieza en la altura de la arena, y las coberturas ya armaron
## sus formas en su _ready.

## Intentos por pieza antes de darla por perdida (cayó en una cobertura).
const PLACE_TRIES: int = 6
## Metros que una pieza guarda con cada cobertura.
const COVER_GAP: float = 0.5

@export_group("Reparto")
## Radio hasta el que se reparte, en metros desde el centro. 0 = el radio del claro más edge_spill.
@export var reach: float = 0.0
## Metros que el reparto pasa del borde del claro (sin reach propio).
@export var edge_spill: float = 9.0
## Semilla del reparto: la misma semilla da el mismo suelo.
@export var shape_seed: int = 11

@export_group("Cantidades")
## Conchas.
@export var shell_count: int = 150
## Estrellas de mar.
@export var starfish_count: int = 60
## Guijarros.
@export var pebble_count: int = 230
## Matas de pasto marino.
@export var grass_count: int = 280
## Ánforas.
@export var amphora_count: int = 18
## Tablas sueltas.
@export var plank_count: int = 40
## Balas de cañón.
@export var cannonball_count: int = 16

@export_group("Colores")
## Colores de las conchas.
@export var shell_colors: Array[Color] = [Color(0.98, 0.9, 0.84), Color(0.98, 0.72, 0.66),
		Color(0.95, 0.8, 0.5)]
## Colores de las estrellas de mar.
@export var starfish_colors: Array[Color] = [Color(1.0, 0.5, 0.2), Color(0.95, 0.3, 0.35),
		Color(0.7, 0.4, 0.9)]
## Colores de los guijarros.
@export var pebble_colors: Array[Color] = [Color(0.55, 0.55, 0.58), Color(0.42, 0.44, 0.5),
		Color(0.66, 0.6, 0.55)]
## Colores del pasto marino.
@export var grass_colors: Array[Color] = [Color(0.25, 0.6, 0.3), Color(0.4, 0.7, 0.3),
		Color(0.2, 0.5, 0.42)]
## Color de las ánforas.
@export var amphora_color: Color = Color(0.82, 0.48, 0.3)
## Color de las tablas.
@export var plank_color: Color = Color(0.42, 0.32, 0.22)
## Color de las balas de cañón.
@export var cannonball_color: Color = Color(0.2, 0.21, 0.24)

var _rng := RandomNumberGenerator.new()
var _bounds: Node = null
var _terrain: Terrain = null
var _reach: float = 0.0


func _ready() -> void:
	_rng.seed = shape_seed
	_bounds = get_tree().get_first_node_in_group(&"arena_bounds")
	_terrain = Terrain.find(get_tree())
	var radius: Variant = _bounds.get("clearing_radius") if _bounds != null else null
	_reach = reach if reach > 0.0 else (float(radius) if radius != null else 52.0) + edge_spill
	_scatter("Shells", _shell_mesh(), shell_count, Vector2(0.25, 0.55), shell_colors, 0.3)
	_scatter("Starfish", _starfish_mesh(), starfish_count, Vector2(0.3, 0.65), starfish_colors, 0.0)
	_scatter("Pebbles", _pebble_mesh(), pebble_count, Vector2(0.2, 0.75), pebble_colors, 0.4)
	_scatter("Grass", _grass_mesh(), grass_count, Vector2(0.45, 1.0), grass_colors, 0.15)
	_scatter("Amphorae", _amphora_mesh(), amphora_count, Vector2(0.6, 0.95), [amphora_color], 1.2)
	_scatter("Planks", _plank_mesh(), plank_count, Vector2(0.7, 1.6), [plank_color], 0.12)
	_scatter("Cannonballs", _pebble_mesh(), cannonball_count, Vector2(0.28, 0.36),
			[cannonball_color], 0.0)


# --- reparto ----------------------------------------------------------------------

## Un MultiMesh de `count` copias de `mesh` repartidas por el suelo: cada una
## con un giro al azar, una escala entre `sizes.x` y `sizes.y`, un color de
## `colors` y hasta `tilt` radianes de inclinación.
func _scatter(node_name: String, mesh: Mesh, count: int, sizes: Vector2, colors: Array[Color],
		tilt: float) -> void:
	if count <= 0 or mesh == null or colors.is_empty():
		return
	var spots: Array[Transform3D] = []
	var tints: Array[Color] = []
	for _piece: int in count:
		var at := _free_spot()
		if at == Vector3.INF:
			continue
		var basis := Basis(Vector3.UP, _rng.randf() * TAU) \
				* Basis(Vector3.RIGHT, _rng.randf_range(-tilt, tilt)) \
				* Basis.from_scale(Vector3.ONE * _rng.randf_range(sizes.x, sizes.y))
		spots.append(Transform3D(basis, at))
		tints.append(colors[_rng.randi() % colors.size()])
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = spots.size()
	for index: int in spots.size():
		multimesh.set_instance_transform(index, spots[index])
		multimesh.set_instance_color(index, tints[index])
	var view := MultiMeshInstance3D.new()
	view.name = node_name
	view.multimesh = multimesh
	view.material_override = LowPolyMesh.MATERIAL
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(view)


## Un punto del suelo al azar dentro del reparto y fuera de toda cobertura, o
## INF si PLACE_TRIES intentos cayeron en una.
func _free_spot() -> Vector3:
	for _attempt: int in PLACE_TRIES:
		var angle := _rng.randf() * TAU
		var distance := _reach * sqrt(_rng.randf())
		var xz := Vector2(cos(angle), sin(angle)) * distance
		if _bounds != null and _bounds.has_method(&"cover_distance") \
				and float(_bounds.call(&"cover_distance", xz)) < COVER_GAP:
			continue
		var height := _terrain.height_at(xz.x, xz.y) if _terrain != null else 0.0
		return Vector3(xz.x, height, xz.y) + global_position
	return Vector3.INF


# --- mallas (blancas: el color lo pone cada copia) --------------------------------

## Una concha: medio abanico abombado.
func _shell_mesh() -> Mesh:
	var mesh := LowPolyMesh.new(shape_seed)
	var hinge := Vector3(0.0, 0.0, -0.5)
	var rim := PackedVector3Array()
	for index: int in 6:
		var sweep := lerpf(-1.2, 1.2, float(index) / 5.0)
		rim.append(Vector3(sin(sweep) * 0.9, 0.0, cos(sweep) * 0.9 - 0.5))
	var crown := Vector3(0.0, 0.42, 0.1)
	for index: int in 5:
		mesh.triangle(hinge, rim[index], crown, Color.WHITE, Vector3(0.0, -0.5, 0.0))
		mesh.triangle(rim[index], rim[index + 1], crown, Color(0.9, 0.9, 0.9),
				Vector3(0.0, -0.5, 0.0))
	return mesh.commit()


## Una estrella de mar: cinco puntas, apenas levantada en el centro.
func _starfish_mesh() -> Mesh:
	var mesh := LowPolyMesh.new(shape_seed + 1)
	var middle := Vector3(0.0, 0.16, 0.0)
	var rim := PackedVector3Array()
	for index: int in 10:
		var angle := TAU * float(index) / 10.0
		var out := 1.0 if index % 2 == 0 else 0.4
		rim.append(Vector3(cos(angle) * out, 0.03, sin(angle) * out))
	for index: int in 10:
		mesh.triangle(middle, rim[index], rim[(index + 1) % 10], Color.WHITE,
				Vector3(0.0, -1.0, 0.0))
	return mesh.commit()


## Un guijarro: una bola chata de pocas caras.
func _pebble_mesh() -> Mesh:
	var mesh := LowPolyMesh.new(shape_seed + 2)
	mesh.blob(Vector3(0.0, 0.25, 0.0), Vector3(1.0, 0.6, 0.8), Color.WHITE, 5, 3, 0.2)
	return mesh.commit()


## Una mata de pasto marino: cinco hojas angostas, visibles de los dos lados.
func _grass_mesh() -> Mesh:
	var mesh := LowPolyMesh.new(shape_seed + 3)
	for blade: int in 5:
		var turn := TAU * float(blade) / 5.0 + 0.3
		var foot := Vector3(cos(turn), 0.0, sin(turn)) * 0.18
		var side := Vector3(cos(turn + PI * 0.5), 0.0, sin(turn + PI * 0.5)) * 0.09
		var tip := foot * 2.6 + Vector3.UP * lerpf(0.7, 1.0, float(blade % 3) / 2.0)
		var out := Vector3(cos(turn), 0.0, sin(turn))
		mesh.triangle(foot - side, foot + side, tip, Color.WHITE, foot - out + Vector3.UP * 0.4)
		mesh.triangle(foot - side, foot + side, tip, Color(0.8, 0.8, 0.8),
				foot + out * 3.0 + Vector3.UP * 0.4)
	return mesh.commit()


## Un ánfora acostada: un perfil de vasija girado alrededor de su eje.
func _amphora_mesh() -> Mesh:
	var mesh := LowPolyMesh.new(shape_seed + 4)
	# [largo a lo largo del eje, radio] del pie a la boca.
	var profile: Array[Vector2] = [Vector2(-0.55, 0.08), Vector2(-0.3, 0.34), Vector2(0.05, 0.4),
			Vector2(0.35, 0.2), Vector2(0.55, 0.13), Vector2(0.62, 0.2)]
	var previous := PackedVector3Array()
	for station: Vector2 in profile:
		var ring := PackedVector3Array()
		for index: int in 6:
			var angle := TAU * float(index) / 6.0
			ring.append(Vector3(station.x, 0.3 + cos(angle) * station.y, sin(angle) * station.y))
		if not previous.is_empty():
			mesh.band(previous, ring, Color.WHITE)
		previous = ring
	mesh.cap(previous, Color(0.25, 0.2, 0.2), Vector3(0.0, 0.3, 0.0))
	return mesh.commit()


## Una tabla suelta.
func _plank_mesh() -> Mesh:
	var mesh := LowPolyMesh.new(shape_seed + 5)
	mesh.block(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.05, 0.0)), Vector3(1.0, 0.08, 0.2),
			Color.WHITE)
	return mesh.commit()
