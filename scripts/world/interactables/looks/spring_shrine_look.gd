class_name SpringShrineLook
extends Node3D
## Cómo se ve el manantial: una fuente de piedra octogonal sobre un escalón,
## con borde tallado, una columna al medio con un cuenco del que caen cuatro
## chorros, y musgo y helechos alrededor. Va como hijo de Visual en
## SpringShrine.tscn; el agua (que el manantial baja con cada uso) y la luz
## siguen siendo del altar.

@export_group("Medidas")
## Radio del escalón de abajo, en metros.
@export var step_radius: float = 2.05
## Radio de afuera del borde de la fuente, en metros (igual a la colisión del altar).
@export var basin_outer: float = 1.7
## Radio de adentro del borde de la fuente, en metros.
@export var basin_inner: float = 1.48
## Alto del borde de la fuente, en metros.
@export var basin_height: float = 0.78
## Alto de la columna del medio, en metros.
@export var column_height: float = 1.4
## Radio del cuenco sobre la columna, en metros.
@export var bowl_radius: float = 0.5
## Helechos alrededor de la fuente.
@export_range(0, 8) var ferns: int = 4

@export_group("Colores")
## Piedra de la fuente.
@export var stone_color: Color = Color(0.62, 0.62, 0.6)
## Borde y escalón.
@export var top_color: Color = Color(0.75, 0.73, 0.68)
## Fondo de la fuente.
@export var floor_color: Color = Color(0.3, 0.36, 0.36)
## Chorros de agua.
@export var water_color: Color = Color(0.6, 0.88, 0.98)
## Color del musgo.
@export var moss_color: Color = Color(0.36, 0.5, 0.3)
## Color de los helechos.
@export var fern_color: Color = Color(0.2, 0.5, 0.3)

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_build.call_deferred()


func _build() -> void:
	_rng.seed = hash(Vector3i(roundi(global_position.x * 10.0), 31, roundi(global_position.z * 10.0)))
	var stone := LowPolyMesh.new(int(_rng.seed))
	var glow := LowPolyMesh.new(int(_rng.seed) + 1)
	var turn := PI / 8.0
	var step := ShrineKit.plinth(stone, Vector3.ZERO, step_radius, 1, 0.16, 1.0, 8, stone_color,
			top_color, turn)
	var outer_low := stone.ring(Vector3.UP * (step - 0.05), basin_outer, 8, turn)
	var outer_high := stone.ring(Vector3.UP * basin_height, basin_outer, 8, turn)
	stone.band(outer_low, outer_high, stone_color)
	ShrineKit.annulus(stone, Vector3.UP * basin_height, basin_inner, basin_outer + 0.06, 8,
			top_color, turn)
	var floor_y := step + 0.08
	ShrineKit.inner_wall(stone, stone.ring(Vector3.UP * floor_y, basin_inner, 8, turn),
			stone.ring(Vector3.UP * basin_height, basin_inner, 8, turn), stone_color.darkened(0.2))
	stone.cap(stone.ring(Vector3.UP * floor_y, basin_inner, 8, turn), floor_color,
			Vector3.UP * (floor_y - 1.0))
	# Una runa en cada cara del borde que da afuera, alternadas.
	for face in 8:
		if face % 2 == 1:
			continue
		var out := Vector3.FORWARD.rotated(Vector3.UP, TAU * (float(face) + 0.5) / 8.0 + turn)
		ShrineKit.glyph(glow, out * (basin_outer * cos(PI / 8.0) + 0.02)
				+ Vector3.UP * ((step + basin_height) * 0.5), out, Vector3.UP, 0.32, water_color)
	var crown := ShrineKit.column(stone, Vector3.UP * floor_y, column_height, 0.2, 8, stone_color,
			top_color, turn)
	_bowl(stone, glow, crown)
	_ferns_and_moss(stone, step)
	ShrineKit.hang(self, stone, glow)


## El cuenco de arriba de la columna y los cuatro chorros que caen al agua.
func _bowl(stone: LowPolyMesh, glow: LowPolyMesh, crown: Vector3) -> void:
	var low := stone.ring(crown, bowl_radius * 0.4, 8)
	var high := stone.ring(crown + Vector3.UP * 0.22, bowl_radius, 8)
	stone.band(low, high, top_color)
	glow.cap(glow.ring(crown + Vector3.UP * 0.2, bowl_radius * 0.92, 8), water_color,
			crown + Vector3.DOWN)
	stone.blob(crown + Vector3.UP * 0.42, Vector3.ONE * 0.12, top_color, 6, 4, 0.05)
	var water := get_parent().get_node_or_null("Water") as Node3D
	var surface := water.position.y if water != null else basin_height - 0.12
	for index in 4:
		var out := Vector3.FORWARD.rotated(Vector3.UP, TAU * float(index) / 4.0 + PI / 4.0)
		var lip := crown + Vector3.UP * 0.2 + out * bowl_radius
		var side := Vector3(-out.z, 0.0, out.x) * 0.07
		var land := Vector3(0.0, surface, 0.0) + out * (bowl_radius + 0.22)
		var bend := lip + out * 0.12 + Vector3.DOWN * 0.1
		glow.plate(lip - side, lip + side, bend + side, bend - side, water_color, lip - out)
		glow.plate(bend - side, bend + side, land + side * 1.4, land - side * 1.4, water_color,
				bend - out)


## Musgo sobre el escalón y helechos al pie.
func _ferns_and_moss(stone: LowPolyMesh, step: float) -> void:
	var spots := PackedVector3Array()
	for index in 5:
		var angle := _rng.randf() * TAU
		spots.append(Vector3(cos(angle), 0.0, sin(angle)) * (basin_outer + 0.2) + Vector3.UP * step)
	ShrineKit.moss(stone, spots, 0.28, moss_color, _rng)
	for index in ferns:
		var angle := _rng.randf() * TAU
		var root := Vector3(cos(angle), 0.0, sin(angle)) * (step_radius + 0.35)
		root.y = ShrineKit.ground_offset(self, root)
		for frond in 6:
			var out := Vector3.FORWARD.rotated(Vector3.UP, TAU * float(frond) / 6.0 + _rng.randf())
			var reach := _rng.randf_range(0.55, 0.9)
			var side := Vector3(-out.z, 0.0, out.x) * reach * 0.18
			var bend := root + out * reach * 0.5 + Vector3.UP * reach * 0.5
			var tip := root + out * reach + Vector3.UP * reach * 0.2
			stone.triangle(root, bend + side, bend - side, fern_color, bend + Vector3.DOWN)
			stone.triangle(bend - side, bend + side, tip, fern_color, bend + Vector3.DOWN)
