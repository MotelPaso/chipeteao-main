class_name StandingStones
extends StaticBody3D
## Piedras antiguas del Bosque Hueco, armadas en código (LowPolyMesh). Una
## sola escena hace las cuatro formas, según `layout`:
##
##   MENHIR   una piedra parada
##   GATE     un portal: dos pilares y un dintel, de `span` metros de luz
##   CIRCLE   un círculo de piedras de radio `span` con un altar al medio y
##            algunos dinteles
##   RUIN     una columnata rota: pilares enteros, truncos y caídos en fila
##            a lo largo de `span` metros
##
## Quien las coloca (ReliefStructures) fija `layout`, `span` y `shape_seed`
## antes de que entren al árbol. Cada piedra parada lleva su colisión (un
## cilindro); los dinteles y las piedras caídas no frenan a nadie. Las
## piedras bajan `sink` metros bajo su origen, así una loma no les deja el
## pie en el aire.

enum Layout { MENHIR, GATE, CIRCLE, RUIN }

@export_group("Forma")
## Qué se arma (ver la cabecera).
@export var layout: Layout = Layout.MENHIR
## Luz del portal, radio del círculo o largo de la ruina, en metros.
@export var span: float = 8.0
## Metros que cada piedra baja bajo el suelo.
@export var sink: float = 1.6

@export_group("Piedras")
## Altura mínima de una piedra parada, en metros.
@export var stone_height_min: float = 3.0
## Altura máxima de una piedra parada, en metros.
@export var stone_height_max: float = 4.6
## Radio de una piedra parada en su base, en metros.
@export var stone_radius: float = 0.75
## Altura de los pilares de un portal, en metros.
@export var gate_height: float = 6.4
## Grosor de los pilares y del dintel de un portal, en metros.
@export var gate_thickness: float = 1.5
## Piedras de un círculo.
@export_range(4, 16) var circle_stones: int = 9
## Pilares de una ruina.
@export_range(2, 12) var ruin_pillars: int = 6
## Inclinación máxima de una piedra, en grados.
@export var tilt_degrees: float = 5.0

@export_group("Color")
## Color de la piedra.
@export var stone_color: Color = Color(0.47, 0.49, 0.5)
## Color del musgo de las caras de arriba.
@export var moss_color: Color = Color(0.3, 0.46, 0.27)

## Semilla del desorden de las piedras; la fija quien las coloca.
var shape_seed: int = 0

var _mesh: LowPolyMesh = null
var _rng := RandomNumberGenerator.new()
var _built: bool = false


func _ready() -> void:
	build()


## Arma la malla y las colisiones. Una sola vez.
func build() -> void:
	if _built:
		return
	_built = true
	_rng.seed = shape_seed
	_mesh = LowPolyMesh.new(shape_seed)
	match layout:
		Layout.MENHIR:
			_stone(Vector3.ZERO, _rng.randf_range(stone_height_min, stone_height_max))
		Layout.GATE:
			_gate()
		Layout.CIRCLE:
			_circle()
		Layout.RUIN:
			_ruin()
	add_child(_mesh.instance("Mesh"))


## Una piedra parada en `at` (local), de `height` metros sobre el suelo:
## un prisma de cinco lados que se angosta hacia arriba, algo torcido, con
## la punta musgosa. Con `solid`, lleva su cilindro de colisión.
func _stone(at: Vector3, height: float, radius: float = -1.0, solid: bool = true) -> void:
	var reach := stone_radius * _rng.randf_range(0.85, 1.2) if radius < 0.0 else radius
	var lean := Vector3(_rng.randf_range(-1.0, 1.0), 0.0, _rng.randf_range(-1.0, 1.0)) \
			* tan(deg_to_rad(tilt_degrees)) * height
	var turn := _rng.randf() * TAU
	var lower := _mesh.ring(at + Vector3.DOWN * sink, reach, 5, turn, 0.12)
	var middle := _mesh.ring(at + Vector3.UP * height * 0.55 + lean * 0.55, reach * 0.85, 5,
			turn + 0.2, 0.1)
	var upper := _mesh.ring(at + Vector3.UP * height + lean, reach * 0.5, 5, turn + 0.35, 0.15)
	_mesh.band(lower, middle, stone_color)
	_mesh.band(middle, upper, stone_color.lerp(moss_color, 0.25))
	_mesh.cap(upper, moss_color, at + Vector3.UP * height * 0.5)
	if not solid:
		return
	var shape := CylinderShape3D.new()
	shape.radius = reach * 0.9
	shape.height = height + sink
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = at + Vector3.UP * (height - sink) * 0.5
	add_child(collision)


## Una losa acostada de `from` a `to` (local), de `thickness` metros de
## grosor: un dintel o una piedra caída. Sin colisión.
func _slab(from: Vector3, to: Vector3, thickness: float) -> void:
	var along := to - from
	var length := along.length()
	if length < 0.01:
		return
	var x_axis := along / length
	var z_axis := x_axis.cross(Vector3.UP).normalized()
	var y_axis := z_axis.cross(x_axis).normalized()
	var frame := Transform3D(Basis(x_axis, y_axis, z_axis), (from + to) * 0.5)
	_mesh.box(frame, Vector3(length, thickness, thickness * _rng.randf_range(0.85, 1.1)),
			stone_color.lerp(moss_color, 0.15))


## Un portal: dos pilares a `span` metros entre sí sobre el eje X local, con
## el dintel encima. Se pasa por debajo a lo largo de Z.
func _gate() -> void:
	var half := span * 0.5 + gate_thickness * 0.5
	for side: float in [-1.0, 1.0]:
		_stone(Vector3(half * side, 0.0, 0.0), gate_height * _rng.randf_range(0.96, 1.04),
				gate_thickness * 0.62)
	var top := gate_height + gate_thickness * 0.35
	_slab(Vector3(-half - gate_thickness * 0.8, top, _rng.randf_range(-0.2, 0.2)),
			Vector3(half + gate_thickness * 0.8, top + _rng.randf_range(-0.25, 0.25), 0.0),
			gate_thickness)


## Un círculo de piedras de radio `span`, con un altar bajo en el centro y
## un dintel sobre algunas parejas vecinas.
func _circle() -> void:
	var tops: Array[Vector3] = []
	for index in circle_stones:
		var angle := TAU * (float(index) + _rng.randf_range(-0.12, 0.12)) / float(circle_stones)
		var at := Vector3(cos(angle), 0.0, sin(angle)) * span * _rng.randf_range(0.94, 1.06)
		var height := _rng.randf_range(stone_height_min, stone_height_max)
		_stone(at, height)
		tops.append(at + Vector3.UP * (height + 0.3))
	for index in range(0, circle_stones - 1, 3):
		_slab(tops[index], tops[index + 1], stone_radius * 1.3)
	# El altar: una losa baja, metida en el suelo la mitad de `sink`.
	var altar_top := 1.0
	_mesh.box(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU),
			Vector3(0.0, (altar_top - sink * 0.5) * 0.5, 0.0)),
			Vector3(2.8, altar_top + sink * 0.5, 1.7), stone_color.lerp(moss_color, 0.2))


## Una columnata rota a lo largo de X: pilares enteros, truncos y caídos.
func _ruin() -> void:
	for index in ruin_pillars:
		var at := Vector3(lerpf(-span * 0.5, span * 0.5, float(index) / float(ruin_pillars - 1)),
				0.0, _rng.randf_range(-0.5, 0.5))
		var roll := _rng.randf()
		if roll < 0.25:
			# Caído: una losa en el suelo, atravesada.
			var out := Vector3(_rng.randf_range(-0.5, 0.5), 0.0, 1.0).normalized()
			_slab(at + Vector3.UP * 0.45, at + out * _rng.randf_range(3.0, 4.6)
					+ Vector3.UP * 0.55, stone_radius * 1.5)
		elif roll < 0.6:
			_stone(at, _rng.randf_range(1.2, 2.4), stone_radius * 1.05)
		else:
			_stone(at, _rng.randf_range(stone_height_max * 0.9, stone_height_max * 1.25),
					stone_radius * 1.05)
