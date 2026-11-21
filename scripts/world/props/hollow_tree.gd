class_name HollowTree
extends StaticBody3D
## El Árbol Hueco: el hito de la cumbre del Bosque Hueco. Un tronco enorme
## con la boca oscura de su hueco, raíces que bajan por la roca y una copa
## que se ve desde todo el mapa. Se arma en código (LowPolyMesh) con las
## medidas de abajo; la colisión es solo el tronco: la copa y las raíces no
## frenan a nadie.
##
## Quien lo coloca (ReliefStructures) lo gira para que el hueco mire hacia
## donde llega el raider. `build()` usa `shape_seed` para el desorden de las
## raíces y de la copa: la misma semilla da el mismo árbol.

@export_group("Tronco")
## Altura del tronco hasta donde abren las ramas, en metros.
@export var trunk_height: float = 19.0
## Radio del tronco en la base, en metros.
@export var trunk_base_radius: float = 3.4
## Radio del tronco arriba, en metros.
@export var trunk_top_radius: float = 1.7
## Lados del tronco: pocos = más facetado.
@export_range(5, 14) var trunk_sides: int = 9
## Color de la corteza.
@export var bark_color: Color = Color(0.36, 0.25, 0.17)
## Color del interior del hueco.
@export var hollow_color: Color = Color(0.06, 0.045, 0.04)
## Alto de la boca del hueco, en metros.
@export var hollow_height: float = 4.2

@export_group("Raíces")
## Cuántas raíces bajan del tronco.
@export_range(0, 12) var root_count: int = 7
## Largo de cada raíz desde el tronco, en metros.
@export var root_length: float = 5.5
## Alto de cada raíz donde nace, en metros.
@export var root_height: float = 2.2

@export_group("Copa")
## Cuántos macizos de hojas forman la copa.
@export_range(1, 14) var crown_blobs: int = 9
## Radio de cada macizo de hojas, en metros.
@export var crown_blob_radius: float = 8.0
## Radio del anillo donde se reparten los macizos alrededor del tronco, en metros.
@export var crown_spread: float = 9.5
## Metros sobre el tronco hasta donde sube la copa.
@export var crown_rise: float = 11.0
## Color de las hojas a la sombra.
@export var leaf_dark_color: Color = Color(0.1, 0.36, 0.2)
## Color de las hojas al sol.
@export var leaf_bright_color: Color = Color(0.2, 0.55, 0.28)

## Semilla del desorden de raíces y copa; la fija quien lo coloca.
var shape_seed: int = 0

var _built: bool = false


func _ready() -> void:
	build()


## Arma la malla y la colisión. Una sola vez.
func build() -> void:
	if _built:
		return
	_built = true
	var rng := RandomNumberGenerator.new()
	rng.seed = shape_seed
	var mesh := LowPolyMesh.new(shape_seed)
	_add_trunk(mesh, rng)
	_add_roots(mesh, rng)
	_add_crown(mesh, rng)
	add_child(mesh.instance("Mesh"))
	var shape := CylinderShape3D.new()
	shape.radius = (trunk_base_radius + trunk_top_radius) * 0.5
	shape.height = trunk_height
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0.0, trunk_height * 0.5, 0.0)
	add_child(collision)


## El tronco: anillos cada vez más angostos, y la boca del hueco pintada en
## las caras de abajo que miran hacia -Z.
func _add_trunk(mesh: LowPolyMesh, rng: RandomNumberGenerator) -> void:
	var levels: Array[float] = [-1.5, hollow_height, trunk_height * 0.6, trunk_height]
	var turn := rng.randf() * TAU
	var rings: Array[PackedVector3Array] = []
	for index in levels.size():
		var t := clampf(levels[index] / trunk_height, 0.0, 1.0)
		# Se angosta rápido al principio (el pie ancho) y después casi nada.
		var radius := lerpf(trunk_base_radius, trunk_top_radius, pow(t, 0.55))
		rings.append(mesh.ring(Vector3(0.0, levels[index], 0.0), radius, trunk_sides,
				turn + 0.12 * float(index), 0.08))
	for index in rings.size() - 1:
		if index > 0:
			mesh.band(rings[index], rings[index + 1], bark_color)
			continue
		# El primer tramo, cara por cara: las que miran a -Z son el hueco.
		var axis := Vector3(0.0, (levels[0] + levels[1]) * 0.5, 0.0)
		for side in trunk_sides:
			var next := (side + 1) % trunk_sides
			var facing := (rings[0][side] + rings[0][next]) * 0.5
			var hollow := Vector2(facing.x, facing.z).normalized().dot(Vector2(0.0, -1.0)) > 0.8
			mesh.quad(rings[0][side], rings[0][next], rings[1][next], rings[1][side],
					hollow_color if hollow else bark_color, axis)
	mesh.cap(rings[rings.size() - 1], bark_color, Vector3(0.0, trunk_height * 0.5, 0.0))


## Las raíces: cuñas que salen del pie del tronco y mueren en punta.
func _add_roots(mesh: LowPolyMesh, rng: RandomNumberGenerator) -> void:
	for index in root_count:
		var angle := TAU * (float(index) + rng.randf_range(-0.25, 0.25)) / float(root_count)
		# La boca del hueco (hacia -Z) queda libre.
		if Vector2(cos(angle), sin(angle)).dot(Vector2(0.0, -1.0)) > 0.75:
			continue
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-out.z, 0.0, out.x)
		var length := root_length * rng.randf_range(0.7, 1.15)
		var width := rng.randf_range(0.7, 1.1)
		var height := root_height * rng.randf_range(0.75, 1.2)
		var from := out * (trunk_base_radius * 0.75)
		var tip := out * (trunk_base_radius + length) + side * rng.randf_range(-1.2, 1.2) \
				+ Vector3.DOWN * 1.2
		var crest := from + Vector3.UP * height
		var left := from + side * width + Vector3.DOWN * 1.2
		var right := from - side * width + Vector3.DOWN * 1.2
		var inside := (crest + left + right + tip) * 0.25
		mesh.triangle(crest, left, tip, bark_color, inside)
		mesh.triangle(crest, tip, right, bark_color, inside)
		mesh.triangle(left, right, tip, bark_color, inside)


## La copa: macizos de hojas en un anillo alrededor del tronco y uno arriba,
## con una rama gruesa hacia cada uno.
func _add_crown(mesh: LowPolyMesh, rng: RandomNumberGenerator) -> void:
	var top := Vector3(0.0, trunk_height, 0.0)
	for index in crown_blobs:
		var center := top + Vector3.UP * crown_rise * 0.7
		if index > 0:
			var angle := TAU * (float(index) + rng.randf_range(-0.3, 0.3)) / float(crown_blobs - 1)
			center = top + Vector3(cos(angle), 0.0, sin(angle)) * crown_spread \
					* rng.randf_range(0.75, 1.15) + Vector3.UP * crown_rise * rng.randf_range(0.05, 0.6)
		var radius := crown_blob_radius * rng.randf_range(0.75, 1.15)
		var color := leaf_dark_color.lerp(leaf_bright_color, rng.randf())
		mesh.blob(center, Vector3(radius, radius * rng.randf_range(0.6, 0.8), radius), color)
		# La rama: un prisma de tres lados del tronco al macizo.
		var from := top + Vector3.DOWN * rng.randf_range(1.0, 4.0)
		var lower := mesh.ring(from, trunk_top_radius * 0.7, 3, rng.randf() * TAU)
		var upper := mesh.ring(center + Vector3.DOWN * radius * 0.3, 0.35, 3, rng.randf() * TAU)
		mesh.band(lower, upper, bark_color)
