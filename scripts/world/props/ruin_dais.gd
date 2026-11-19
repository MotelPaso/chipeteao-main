class_name RuinDais
extends StaticBody3D
## La meseta del Bosque Hueco: un estrado de piedra en ruinas, con muros de
## sillares, una cornisa, el piso de losas, cuatro postes con brasero en las
## esquinas, runas talladas que apenas brillan, hiedra que cuelga y escombros
## al pie. El scatter lo arma con su escalera (RuinStairs.tscn) pegada a una
## cara y, a veces, un cofre en el centro. Escena:
## scenes/world/props/RuinDais.tscn.
##
## La colisión es la caja de la meseta de las otras arenas (6 x 2 x 6 m a
## escala 1): se juega igual. Los postes van en un cuerpo aparte (`Posts`):
## son un obstáculo que se rodea, no un piso.

## Corazón de la llama de los braseros.
const FLAME_CORE := Color(1.0, 0.9, 0.55)

@export_group("Medidas")
## Medio lado del estrado a escala 1, en metros. Igual a la caja de colisión.
@export var half_side: float = 3.0
## Alto del estrado a escala 1, en metros. Es el mesa_deck_height del scatter.
@export var height: float = 2.0
## Alto de cada hilada de sillares, en metros.
@export var course: float = 0.46
## Largo mínimo de un sillar, en metros.
@export var block_min: float = 0.8
## Largo máximo de un sillar, en metros.
@export var block_max: float = 1.4
## Alto de los postes de las esquinas sobre el piso, en metros.
@export var post_height: float = 1.35
## Lado de los postes, en metros.
@export var post_side: float = 0.6

@export_group("Adornos")
## Ramas de hiedra que cuelgan de cada muro, como máximo.
@export_range(0, 8) var ivy_per_side: int = 4
## Estandartes que cuelgan de la cornisa (en muros al azar, uno por muro).
@export_range(0, 4) var banners: int = 2
## Ancho de cada estandarte, en metros.
@export var banner_width: float = 0.9
## Largo de cada estandarte, en metros.
@export var banner_length: float = 1.5
## Runas talladas en cada muro.
@export_range(0, 6) var runes_per_side: int = 2
## Piedras sueltas al pie del estrado.
@export_range(0, 16) var rubble: int = 7
## Fuerza de la luz de los braseros (0 = sin luz).
@export var light_energy: float = 0.9
## Alcance de esa luz, en metros.
@export var light_range: float = 8.0

@export_group("Colores")
## Piedra de los muros.
@export var stone_color: Color = Color(0.6, 0.59, 0.54)
## Piedra de las hiladas de abajo, más oscura.
@export var stone_low_color: Color = Color(0.42, 0.44, 0.41)
## Losas del piso.
@export var paving_color: Color = Color(0.71, 0.69, 0.61)
## Cornisa y postes.
@export var trim_color: Color = Color(0.77, 0.74, 0.66)
## Musgo de las caras de arriba.
@export var moss_color: Color = Color(0.36, 0.5, 0.3)
## Hiedra de los muros.
@export var ivy_color: Color = Color(0.24, 0.46, 0.25)
## Hierro de los braseros.
@export var iron_color: Color = Color(0.2, 0.19, 0.2)
## Runas talladas.
@export var rune_color: Color = Color(0.45, 0.9, 0.8)
## Llama de los braseros.
@export var flame_color: Color = Color(1.0, 0.52, 0.14)
## Color del paño de los estandartes.
@export var banner_color: Color = Color(0.2, 0.42, 0.36)
## Color de la franja de los estandartes.
@export var banner_trim_color: Color = Color(0.93, 0.74, 0.28)

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_add_posts()
	# La forma sale del lugar, que quien lo coloca fija después de add_child.
	_build.call_deferred()


func _build() -> void:
	_rng.seed = hash(Vector3i(roundi(global_position.x * 10.0), 11, roundi(global_position.z * 10.0)))
	var stone := LowPolyMesh.new(int(_rng.seed))
	var glow := LowPolyMesh.new(int(_rng.seed) + 1)
	for side in 4:
		_wall(stone, glow, side)
	_coping(stone)
	_paving(stone)
	for corner in 4:
		_post(stone, glow, corner)
	_rubble(stone)
	_banners(stone)
	ShrineKit.hang(self, stone, glow)
	if light_energy > 0.0:
		var light := OmniLight3D.new()
		light.light_color = flame_color
		light.light_energy = light_energy
		light.omni_range = light_range
		light.shadow_enabled = false
		light.position = Vector3.UP * (height + post_height + 0.8)
		add_child(light)


## Los cuatro postes de las esquinas, en un cuerpo aparte.
func _add_posts() -> void:
	var posts := StaticBody3D.new()
	posts.name = "Posts"
	add_child(posts)
	for corner in 4:
		var shape := BoxShape3D.new()
		shape.size = Vector3(post_side, post_height, post_side)
		var holder := CollisionShape3D.new()
		holder.shape = shape
		holder.position = _corner(corner) + Vector3.UP * (height + post_height * 0.5)
		posts.add_child(holder)


## El centro de la esquina `corner` (0-3) en el plano del piso, metida medio poste.
func _corner(corner: int) -> Vector3:
	var inset := half_side - post_side * 0.5
	var signs: Array[Vector2] = [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]
	return Vector3(signs[corner].x * inset, 0.0, signs[corner].y * inset)


## El muro `side` (0-3): hiladas de sillares en aparejo trabado, runas y hiedra.
func _wall(stone: LowPolyMesh, glow: LowPolyMesh, side: int) -> void:
	var out := Vector3.FORWARD.rotated(Vector3.UP, PI * 0.5 * float(side))
	var along := Vector3(-out.z, 0.0, out.x)
	var start := out * half_side - along * half_side
	var top := height - 0.18
	var courses := ceili((top + 0.4) / course)
	for row in courses:
		var high := top - float(row) * course
		var low := maxf(high - course, -0.4)
		var tone := stone_low_color.lerp(stone_color, clampf((high + 0.4) / (top + 0.4), 0.0, 1.0))
		var cursor := -_rng.randf_range(0.0, block_min * 0.6) if row % 2 == 1 else 0.0
		while cursor < half_side * 2.0 - 0.05:
			var from := maxf(cursor, 0.0)
			var to := minf(cursor + _rng.randf_range(block_min, block_max), half_side * 2.0)
			cursor = to
			if to - from < 0.05:
				continue
			# Cada sillar asoma un poco distinto: el muro no queda liso.
			var bulge := out * _rng.randf_range(0.0, 0.05)
			var a := start + along * from + bulge
			var b := start + along * to + bulge
			stone.plate(a + Vector3.UP * low, b + Vector3.UP * low, b + Vector3.UP * high,
					a + Vector3.UP * high, tone.lightened(_rng.randf_range(-0.04, 0.04)),
					(a + b) * 0.5 + Vector3.UP * (low + high) * 0.5 - out)
	# La franja tallada a media altura, que asoma un poco del muro.
	var band_low := height * 0.48
	stone.plate(start + out * 0.08 + Vector3.UP * band_low,
			start + along * half_side * 2.0 + out * 0.08 + Vector3.UP * band_low,
			start + along * half_side * 2.0 + out * 0.08 + Vector3.UP * (band_low + 0.2),
			start + out * 0.08 + Vector3.UP * (band_low + 0.2), trim_color.darkened(0.08),
			start + along * half_side - out + Vector3.UP * band_low)
	for index in runes_per_side:
		var spot := start + along * (half_side * 2.0 * (float(index) + 1.0) / float(runes_per_side + 1))
		var center := spot + Vector3.UP * height * 0.72
		var frame_half := Vector2(0.34, 0.4)
		stone.plate(center + out * 0.09 + along * frame_half.x + Vector3.DOWN * frame_half.y,
				center + out * 0.09 - along * frame_half.x + Vector3.DOWN * frame_half.y,
				center + out * 0.09 - along * frame_half.x + Vector3.UP * frame_half.y,
				center + out * 0.09 + along * frame_half.x + Vector3.UP * frame_half.y,
				stone_low_color.darkened(0.25), center - out)
		ShrineKit.glyph(glow, center + out * 0.11, out, Vector3.UP, 0.62, rune_color)
	var vines := _rng.randi_range(1, ivy_per_side) if ivy_per_side > 0 else 0
	for index in vines:
		_ivy(stone, start + along * _rng.randf_range(0.4, half_side * 2.0 - 0.4), out)


## Una rama de hiedra que cuelga de la cornisa por la cara `out` del muro.
func _ivy(stone: LowPolyMesh, top: Vector3, out: Vector3) -> void:
	var along := Vector3(-out.z, 0.0, out.x)
	var drop := _rng.randf_range(0.8, height * 0.85)
	var at := top + Vector3.UP * (height - 0.05) + out * 0.08
	var leaves := maxi(roundi(drop / 0.22), 2)
	for leaf in leaves:
		var center := at + Vector3.DOWN * (float(leaf) * drop / float(leaves)) \
				+ along * _rng.randf_range(-0.12, 0.12)
		var size := _rng.randf_range(0.14, 0.24)
		stone.plate(center + Vector3.UP * size, center + along * size, center + Vector3.DOWN * size,
				center - along * size, ivy_color.lerp(moss_color, _rng.randf() * 0.4),
				center - out * 0.2)


## La cornisa: una moldura que asoma por los cuatro lados, con musgo encima.
func _coping(stone: LowPolyMesh) -> void:
	var low := _square_ring(half_side + 0.12, height - 0.2)
	var high := _square_ring(half_side + 0.12, height)
	stone.band(low, high, trim_color)
	var under := _square_ring(half_side, height - 0.2)
	stone.band(under, low, trim_color.darkened(0.15))


## Un anillo cuadrado de lado 2 x `reach` a la altura `y`.
func _square_ring(reach: float, y: float) -> PackedVector3Array:
	return PackedVector3Array([Vector3(reach, y, reach), Vector3(-reach, y, reach),
			Vector3(-reach, y, -reach), Vector3(reach, y, -reach)])


## El piso: un borde de losas largas y un centro de losas en damero.
func _paving(stone: LowPolyMesh) -> void:
	var y := height + 0.006
	var reach := half_side + 0.12
	var tiles := 6
	var step := reach * 2.0 / float(tiles)
	for row in tiles:
		for column in tiles:
			var a := Vector3(-reach + step * float(column), y, -reach + step * float(row))
			var tone := paving_color.darkened(0.06) if (row + column) % 2 == 0 else paving_color
			var edge := row == 0 or column == 0 or row == tiles - 1 or column == tiles - 1
			if edge and _rng.randf() < 0.35:
				tone = tone.lerp(moss_color, 0.45)
			stone.plate(a, a + Vector3(step, 0.0, 0.0), a + Vector3(step, 0.0, step),
					a + Vector3(0.0, 0.0, step), tone, a + Vector3(step * 0.5, -1.0, step * 0.5))


## El poste de la esquina `corner`, con su brasero.
func _post(stone: LowPolyMesh, glow: LowPolyMesh, corner: int) -> void:
	var foot := _corner(corner) + Vector3.UP * height
	stone.block(Transform3D(Basis.IDENTITY, foot + Vector3.UP * post_height * 0.5),
			Vector3(post_side, post_height, post_side), trim_color)
	stone.block(Transform3D(Basis.IDENTITY, foot + Vector3.UP * (post_height + 0.06)),
			Vector3(post_side * 1.2, 0.12, post_side * 1.2), trim_color.darkened(0.1))
	ShrineKit.brazier(stone, glow, foot + Vector3.UP * (post_height + 0.12), post_side * 0.55,
			iron_color, flame_color, FLAME_CORE)


## Piedras sueltas al pie de los muros.
func _rubble(stone: LowPolyMesh) -> void:
	for index in rubble:
		var angle := _rng.randf() * TAU
		var reach := half_side + _rng.randf_range(0.25, 0.9)
		var spot := Vector3(cos(angle), 0.0, sin(angle)) * reach
		# Contra la caja: el escombro de una esquina va un poco más afuera.
		spot.x = clampf(spot.x, -half_side - 0.9, half_side + 0.9)
		spot.z = clampf(spot.z, -half_side - 0.9, half_side + 0.9)
		var size := _rng.randf_range(0.18, 0.42)
		stone.blob(spot + Vector3.UP * size * 0.3, Vector3(size, size * 0.7, size),
				stone_low_color.lerp(moss_color, _rng.randf() * 0.35), 5, 3, 0.25)


## Los estandartes: uno por muro, en `banners` muros al azar, colgando de la
## cornisa con su franja y la punta partida.
func _banners(stone: LowPolyMesh) -> void:
	var sides: Array[int] = [0, 1, 2, 3]
	for index in mini(banners, 4):
		var side: int = sides.pop_at(_rng.randi_range(0, sides.size() - 1))
		var out := Vector3.FORWARD.rotated(Vector3.UP, PI * 0.5 * float(side))
		var along := Vector3(-out.z, 0.0, out.x)
		var top := out * (half_side + 0.14) + along * _rng.randf_range(-0.8, 0.8) \
				+ Vector3.UP * (height - 0.22)
		var half := banner_width * 0.5
		var body := banner_length * 0.72
		var inside := top - out
		stone.plate(top - along * half, top + along * half, top + along * half + Vector3.DOWN * body,
				top - along * half + Vector3.DOWN * body, banner_color, inside)
		var band := top + Vector3.DOWN * body
		stone.plate(band - along * half, band + along * half,
				band + along * half + Vector3.DOWN * banner_length * 0.1,
				band - along * half + Vector3.DOWN * banner_length * 0.1, banner_trim_color, inside)
		var tail := band + Vector3.DOWN * banner_length * 0.1
		for turn: float in [-1.0, 1.0]:
			stone.triangle(tail + along * turn * half, tail,
					tail + along * turn * half + Vector3.DOWN * banner_length * 0.18, banner_color,
					inside)
