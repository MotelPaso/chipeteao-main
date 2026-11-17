class_name GiantMushroom
extends StaticBody3D
## Un hongo gigante del Bosque Hueco, armado en código (LowPolyMesh): un pie
## grueso, un sombrero ancho bajo el que cabe un raider, unas motas que
## brillan y dos o tres hongos chicos a su lado. Escena:
## scenes/world/props/GiantMushroom.tscn.
##
## Solo el pie del hongo grande frena: el sombrero y los hongos chicos se
## atraviesan. Cada hongo sale distinto según dónde lo plantaron (su forma se
## siembra con su posición), así el mismo mapa da siempre los mismos hongos.

## Lados del pie y del sombrero.
const SIDES: int = 7
## Metros que el pie baja bajo el suelo, para que una loma no lo deje en el aire.
const SINK: float = 0.6

@export_group("Forma")
## Alto mínimo del pie, en metros.
@export var stem_height_min: float = 2.4
## Alto máximo del pie, en metros.
@export var stem_height_max: float = 4.4
## Radio del pie en su base, en metros. Es también lo que frena.
@export var stem_radius: float = 0.55
## Radio mínimo del sombrero, en metros.
@export var cap_radius_min: float = 1.7
## Radio máximo del sombrero, en metros.
@export var cap_radius_max: float = 2.7
## Hongos chicos alrededor del grande, como máximo.
@export_range(0, 5) var sprouts: int = 3
## Motas sobre el sombrero.
@export_range(0, 9) var spots: int = 5

@export_group("Colores")
## Colores del sombrero: cada hongo toma uno.
@export var cap_colors: Array[Color] = [Color(0.78, 0.2, 0.2), Color(0.55, 0.3, 0.72),
		Color(0.16, 0.6, 0.62), Color(0.9, 0.52, 0.2)]
## Color del pie y del envés del sombrero.
@export var stem_color: Color = Color(0.9, 0.86, 0.76)
## Color de las motas, que no reciben sombra: se ven encendidas.
@export var spot_color: Color = Color(1.0, 0.96, 0.78)

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# Lo que frena va ya: el scatter mide la huella del prop apenas lo cuelga.
	# Llega hasta el alto mínimo del pie; más arriba no hay con qué chocar.
	var shape := CylinderShape3D.new()
	shape.radius = stem_radius
	shape.height = stem_height_min + SINK
	var holder := CollisionShape3D.new()
	holder.shape = shape
	holder.position = Vector3.UP * (stem_height_min - SINK) * 0.5
	add_child(holder)
	# La malla espera a que quien lo plantó lo ponga en su lugar.
	_build.call_deferred()


func _build() -> void:
	# La forma sale del lugar: la misma semilla de partida, los mismos hongos.
	_rng.seed = hash(Vector3i(roundi(global_position.x * 10.0), 7, roundi(global_position.z * 10.0)))
	var mesh := LowPolyMesh.new(int(_rng.seed))
	var glow := LowPolyMesh.new(int(_rng.seed) + 1)
	var cap := cap_colors[_rng.randi() % cap_colors.size()] if not cap_colors.is_empty() \
			else Color(0.78, 0.2, 0.2)
	var height := _rng.randf_range(stem_height_min, stem_height_max)
	_grow(mesh, glow, Vector3.ZERO, height, stem_radius,
			_rng.randf_range(cap_radius_min, cap_radius_max), cap, spots)
	for index in _rng.randi_range(mini(1, sprouts), sprouts):
		var angle := _rng.randf() * TAU
		var reach := stem_radius + _rng.randf_range(0.6, 1.1)
		var small := _rng.randf_range(0.22, 0.4)
		_grow(mesh, glow, Vector3(cos(angle) * reach, 0.0, sin(angle) * reach), height * small,
				stem_radius * small * 1.2, cap_radius_max * small, cap, 0)
	add_child(mesh.instance("Mushroom"))
	if not glow.is_empty():
		var shine := StandardMaterial3D.new()
		shine.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		shine.vertex_color_use_as_albedo = true
		var lights := glow.instance("Spots")
		lights.material_override = shine
		lights.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(lights)


## Un hongo con el pie en `foot`: pie de `height` metros, sombrero de radio
## `cap_radius` y `dots` motas.
func _grow(mesh: LowPolyMesh, glow: LowPolyMesh, foot: Vector3, height: float, radius: float,
		cap_radius: float, cap: Color, dots: int) -> void:
	var turn := _rng.randf() * TAU
	var lean := Vector3(_rng.randf_range(-0.12, 0.12), 0.0, _rng.randf_range(-0.12, 0.12)) * height
	var base := mesh.ring(foot + Vector3.DOWN * SINK, radius * 1.25, SIDES, turn, 0.06)
	var waist := mesh.ring(foot + lean * 0.5 + Vector3.UP * height * 0.5, radius * 0.8, SIDES, turn)
	var neck := mesh.ring(foot + lean + Vector3.UP * height, radius * 0.9, SIDES, turn)
	mesh.band(base, waist, stem_color)
	mesh.band(waist, neck, stem_color)
	var top := foot + lean + Vector3.UP * height
	# El sombrero: el envés, el ala y la cúpula.
	var brim := mesh.ring(top + Vector3.DOWN * cap_radius * 0.12, cap_radius, SIDES, turn + 0.3, 0.07)
	var shoulder := mesh.ring(top + Vector3.UP * cap_radius * 0.28, cap_radius * 0.72, SIDES,
			turn + 0.3)
	var crown := mesh.ring(top + Vector3.UP * cap_radius * 0.5, cap_radius * 0.3, SIDES, turn + 0.3)
	mesh.band(neck, brim, stem_color.darkened(0.12))
	mesh.band(brim, shoulder, cap)
	mesh.band(shoulder, crown, cap.lightened(0.08))
	mesh.cap(crown, cap.lightened(0.14), top)
	for dot in dots:
		var angle := _rng.randf() * TAU
		var out := _rng.randf_range(0.3, 0.8)
		var at := top + Vector3(cos(angle), 0.0, sin(angle)) * (cap_radius * out) \
				+ Vector3.UP * cap_radius * lerpf(0.47, 0.1, out)
		var size := cap_radius * _rng.randf_range(0.07, 0.12)
		glow.blob(at, Vector3(size, size * 0.6, size), spot_color, 5, 3, 0.1)
