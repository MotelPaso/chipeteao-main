class_name RuinStairs
extends StaticBody3D
## La escalera del estrado del bosque (RuinDais): peldaños de piedra entre
## dos muretes que bajan con la pendiente, con un poste rematado por una
## bola de piedra a cada lado del pie. Escena:
## scenes/world/props/RuinStairs.tscn.
##
## La colisión es la cuña lisa de la rampa de las otras arenas (4 m de largo,
## 3 de ancho y 2 de alto a escala 1, subiendo hacia +X): se camina igual y
## los peldaños son dibujo. Los postes del pie van en un cuerpo aparte
## (`Posts`): son un obstáculo, no un piso.

@export_group("Medidas")
## Largo de la escalera a escala 1, en metros. Igual a la cuña de colisión.
@export var run: float = 4.0
## Alto de la escalera a escala 1, en metros. Igual a la cuña de colisión.
@export var rise: float = 2.0
## Ancho de la escalera a escala 1, en metros. Igual a la cuña de colisión.
@export var width: float = 3.0
## Peldaños dibujados.
@export_range(3, 16) var steps: int = 8
## Ancho de cada murete, en metros.
@export var cheek_width: float = 0.32
## Alto de los postes del pie, en metros.
@export var post_height: float = 1.0

@export_group("Colores")
## Piedra de los muretes.
@export var stone_color: Color = Color(0.6, 0.59, 0.54)
## Huellas de los peldaños.
@export var tread_color: Color = Color(0.71, 0.69, 0.61)
## Frentes de los peldaños, cornisa de los muretes y postes.
@export var trim_color: Color = Color(0.77, 0.74, 0.66)
## Musgo de los peldaños de abajo.
@export var moss_color: Color = Color(0.36, 0.5, 0.3)

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_add_posts()
	_build.call_deferred()


func _build() -> void:
	_rng.seed = hash(Vector3i(roundi(global_position.x * 10.0), 13, roundi(global_position.z * 10.0)))
	var stone := LowPolyMesh.new(int(_rng.seed))
	_treads(stone)
	for turn: float in [-1.0, 1.0]:
		_cheek(stone, turn)
		_post(stone, turn)
	add_child(stone.instance("Stone"))


## Los postes del pie, en un cuerpo aparte.
func _add_posts() -> void:
	var posts := StaticBody3D.new()
	posts.name = "Posts"
	add_child(posts)
	for turn: float in [-1.0, 1.0]:
		var shape := BoxShape3D.new()
		shape.size = Vector3(cheek_width + 0.1, post_height, cheek_width + 0.1)
		var holder := CollisionShape3D.new()
		holder.shape = shape
		holder.position = _post_foot(turn) + Vector3.UP * post_height * 0.5
		posts.add_child(holder)


func _post_foot(turn: float) -> Vector3:
	return Vector3(-run * 0.5 - cheek_width * 0.5, 0.0, turn * (width * 0.5 - cheek_width * 0.5))


## Los peldaños: la huella de cada uno a la altura de la cuña en su medio,
## así quien sube no se hunde ni flota más de medio peldaño.
func _treads(stone: LowPolyMesh) -> void:
	var inner := width * 0.5 - cheek_width
	var going := run / float(steps)
	var lift := rise / float(steps)
	for step in steps:
		var x0 := -run * 0.5 + going * float(step)
		var x1 := x0 + going
		var y := lift * (float(step) + 0.5)
		var below := 0.0 if step == 0 else lift * (float(step) - 0.5)
		var tone := tread_color.lerp(moss_color, 0.35) if step < 2 and _rng.randf() < 0.6 \
				else tread_color
		stone.plate(Vector3(x0, y, -inner), Vector3(x1, y, -inner), Vector3(x1, y, inner),
				Vector3(x0, y, inner), tone, Vector3((x0 + x1) * 0.5, y - 1.0, 0.0))
		stone.plate(Vector3(x0, below, -inner), Vector3(x0, y, -inner), Vector3(x0, y, inner),
				Vector3(x0, below, inner), trim_color, Vector3(x0 + 1.0, y, 0.0))


## El murete del lado `turn` (-1, +1): de afuera, de adentro y su cornisa,
## siguiendo la pendiente.
func _cheek(stone: LowPolyMesh, turn: float) -> void:
	var inner := turn * (width * 0.5 - cheek_width)
	var outer := turn * width * 0.5
	var low_x := -run * 0.5
	var high_x := run * 0.5
	var cap := 0.22
	var foot_y := -0.3
	for face: float in [inner, outer]:
		stone.plate(Vector3(low_x, foot_y, face), Vector3(high_x, foot_y, face),
				Vector3(high_x, rise + cap, face), Vector3(low_x, cap + 0.2, face), stone_color,
				Vector3(0.0, rise * 0.5, (inner + outer) * 0.5))
	# La cornisa de arriba del murete y su frente al pie.
	stone.plate(Vector3(low_x, cap + 0.2, inner), Vector3(high_x, rise + cap, inner),
			Vector3(high_x, rise + cap, outer), Vector3(low_x, cap + 0.2, outer), trim_color,
			Vector3(0.0, -1.0, (inner + outer) * 0.5))
	stone.plate(Vector3(low_x, foot_y, inner), Vector3(low_x, cap + 0.2, inner),
			Vector3(low_x, cap + 0.2, outer), Vector3(low_x, foot_y, outer), stone_color.darkened(0.08),
			Vector3(0.0, 0.0, (inner + outer) * 0.5))


## El poste del pie del lado `turn`, rematado por una bola de piedra.
func _post(stone: LowPolyMesh, turn: float) -> void:
	var foot := _post_foot(turn)
	var side := cheek_width + 0.1
	stone.block(Transform3D(Basis.IDENTITY, foot + Vector3.UP * (post_height * 0.5 - 0.15)),
			Vector3(side, post_height + 0.3, side), trim_color)
	stone.blob(foot + Vector3.UP * (post_height + side * 0.4), Vector3.ONE * side * 0.45,
			trim_color.lightened(0.05), 6, 4, 0.05)
