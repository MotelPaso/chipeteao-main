class_name RouletteShrineLook
extends Node3D
## Cómo se ve el altar de la ruleta: un zócalo octogonal, una columna corta
## bajo la rueda, un aro de bronce sostenido por cuatro brazos alrededor de
## la rueda, una flecha de oro que marca el premio y dos dados al pie. La
## rueda (que el altar hace girar) pasa a ser un disco de gajos de colores.
## Va como hijo de Visual en RouletteShrine.tscn; la rueda, sus rayos y la
## luz siguen siendo del altar.

@export_group("Medidas")
## Radio del zócalo, en metros.
@export var plinth_radius: float = 1.05
## Radio de la columna bajo la rueda, en metros.
@export var column_radius: float = 0.36
## Cuánto más ancho que la rueda es el aro, en metros.
@export var rim_gap: float = 0.12
## Gajos de la rueda.
@export_range(4, 24) var slices: int = 12

@export_group("Colores")
## Piedra del zócalo y la columna.
@export var stone_color: Color = Color(0.58, 0.56, 0.55)
## Cara de arriba del zócalo, basa y capitel.
@export var top_color: Color = Color(0.74, 0.71, 0.65)
## Bronce del aro y sus brazos.
@export var bronze_color: Color = Color(0.62, 0.45, 0.22)
## Oro de la flecha.
@export var gold_color: Color = Color(0.96, 0.76, 0.25)
## Colores de los gajos de la rueda, en orden.
@export var slice_colors: Array[Color] = [Color(0.86, 0.22, 0.2), Color(0.97, 0.78, 0.25),
		Color(0.18, 0.62, 0.6), Color(0.55, 0.3, 0.78)]
## Color de los dados.
@export var dice_color: Color = Color(0.95, 0.93, 0.88)
## Color de los puntos de los dados.
@export var pip_color: Color = Color(0.15, 0.12, 0.12)

var _rng := RandomNumberGenerator.new()
## Radio de la rueda, que se lee de su malla al rehacerla.
var _wheel_reach: float = 1.4


func _ready() -> void:
	_restyle_wheel()
	_build.call_deferred()


## La rueda del altar pasa a ser un disco de gajos de colores con canto oscuro.
func _restyle_wheel() -> void:
	var wheel := get_parent().get_node_or_null("Wheel") as MeshInstance3D
	var disc := wheel.mesh as CylinderMesh if wheel != null else null
	if disc == null:
		return
	var mesh := LowPolyMesh.new(9)
	var reach := disc.top_radius
	_wheel_reach = reach
	var half := disc.height * 0.5
	var top_ring := mesh.ring(Vector3.UP * half, reach, slices)
	var low_ring := mesh.ring(Vector3.DOWN * half, reach, slices)
	mesh.band(low_ring, top_ring, bronze_color.darkened(0.3))
	mesh.cap(low_ring, bronze_color.darkened(0.4), Vector3.UP)
	for index in slices:
		var next := (index + 1) % slices
		mesh.triangle(Vector3.UP * half, top_ring[index], top_ring[next],
				slice_colors[index % slice_colors.size()], Vector3.DOWN)
	wheel.mesh = mesh.commit()
	wheel.material_override = LowPolyMesh.MATERIAL


func _build() -> void:
	_rng.seed = hash(Vector3i(roundi(global_position.x * 10.0), 29, roundi(global_position.z * 10.0)))
	var stone := LowPolyMesh.new(int(_rng.seed))
	var glow := LowPolyMesh.new(int(_rng.seed) + 1)
	var wheel := get_parent().get_node_or_null("Wheel") as Node3D
	var wheel_y := wheel.position.y if wheel != null else 1.3
	var top := ShrineKit.plinth(stone, Vector3.ZERO, plinth_radius, 2, 0.2, 0.82, 8, stone_color,
			top_color, PI / 8.0)
	ShrineKit.column(stone, Vector3.UP * top, wheel_y - top - 0.1, column_radius, 8, stone_color,
			top_color, PI / 8.0)
	_rim(stone, wheel_y, _wheel_reach + rim_gap, top)
	_pointer(stone, wheel_y, _wheel_reach + rim_gap)
	for turn: float in [-1.0, 1.0]:
		_die(stone, Vector3(turn * plinth_radius * 1.05, 0.11, plinth_radius * 0.75 * -turn))
	ShrineKit.hang(self, stone, glow)


## El aro de bronce alrededor de la rueda y los cuatro brazos que lo sostienen.
func _rim(stone: LowPolyMesh, y: float, reach: float, foot: float) -> void:
	var low_ring := stone.ring(Vector3.UP * (y - 0.07), reach, 24)
	var high_ring := stone.ring(Vector3.UP * (y + 0.07), reach, 24)
	stone.band(low_ring, high_ring, bronze_color)
	ShrineKit.annulus(stone, Vector3.UP * (y + 0.07), reach, reach + 0.1, 24, bronze_color.lightened(0.1))
	for index in 4:
		var out := Vector3.FORWARD.rotated(Vector3.UP, TAU * float(index) / 4.0 + PI / 4.0)
		ShrineKit.strut(stone, out * plinth_radius * 0.75 + Vector3.UP * foot,
				out * (reach + 0.05) + Vector3.UP * (y - 0.07), 0.07, bronze_color)


## La flecha de oro: apunta al centro desde el frente, sobre el aro.
func _pointer(stone: LowPolyMesh, y: float, reach: float) -> void:
	var tip := Vector3(0.0, y + 0.16, reach - 0.25)
	var back := Vector3(0.0, y + 0.16, reach + 0.25)
	var side := Vector3(0.16, 0.0, 0.0)
	var up := Vector3(0.0, 0.07, 0.0)
	var inside := (tip + back) * 0.5
	for lift: Vector3 in [up, -up]:
		stone.triangle(tip, back + side + lift, back - side + lift, gold_color, inside - lift)
	stone.quad(back + side + up, back + side - up, back - side - up, back - side + up, gold_color,
			inside)
	for turn: float in [-1.0, 1.0]:
		stone.triangle(tip, back + side * turn + up, back + side * turn - up, gold_color, inside)
	ShrineKit.strut(stone, back + Vector3(0.0, -0.05, 0.0), back + Vector3(0.0, -0.3, 0.1), 0.06,
			gold_color.darkened(0.2))


## Un dado de 0.22 m con los puntos de la cara de arriba.
func _die(stone: LowPolyMesh, center: Vector3) -> void:
	var side := 0.22
	var turn := _rng.randf() * TAU
	var basis := Basis(Vector3.UP, turn)
	stone.block(Transform3D(basis, center), Vector3.ONE * side, dice_color)
	var face := center + Vector3.UP * (side * 0.5 + 0.004)
	var pips := _rng.randi_range(1, 6)
	var spots: Array[Vector2] = [Vector2(0, 0), Vector2(-1, -1), Vector2(1, 1), Vector2(-1, 1),
			Vector2(1, -1), Vector2(-1, 0), Vector2(1, 0)]
	var chosen: Array[Vector2] = []
	match pips:
		1:
			chosen = [spots[0]]
		2:
			chosen = [spots[1], spots[2]]
		3:
			chosen = [spots[0], spots[1], spots[2]]
		4:
			chosen = [spots[1], spots[2], spots[3], spots[4]]
		5:
			chosen = [spots[0], spots[1], spots[2], spots[3], spots[4]]
		_:
			chosen = [spots[1], spots[2], spots[3], spots[4], spots[5], spots[6]]
	for spot: Vector2 in chosen:
		var at := face + basis * Vector3(spot.x * side * 0.28, 0.0, spot.y * side * 0.28)
		var pip := stone.ring(at, side * 0.07, 5, turn)
		stone.cap(pip, pip_color, at + Vector3.DOWN)
