class_name BridgeMasonry
extends RefCounted
## La cantería del Gran Puente: arma su malla (LowPolyMesh, un tono por
## sillar) con las medidas y los colores de su Bridge. No pone colisión: las
## formas son del Bridge, que comparte con esto los contornos de las pilas y
## de las escaleras.
##
## Ninguna escena usa este script: lo que alguien podría querer tocar está
## en las constantes de aquí arriba. Las medidas y los colores están en
## scenes/world/props/Bridge.tscn.

# --- edita aquí --------------------------------------------------------------
## Alto de una hilada y largo de un sillar, en metros.
const COURSE: float = 0.74
const BLOCK: float = 1.5
## Tramos rectos con que se dibuja cada arco.
const ARCH_STEPS: int = 10
## Ancho de las dovelas, el aro claro de cada arco, en metros.
const RING_WIDTH: float = 0.5
## Losas a lo ancho del tablero.
const PAVERS_ACROSS: int = 4
## Lados de cada torre.
const TOWER_SIDES: int = 8
## Metros bajo la punta de cada torre donde cuelga el dintel de la cabecera.
const LINTEL_DROP: float = 2.2
## Color del cuenco de los braseros y del corazón de la llama.
const BOWL_COLOR := Color(0.2, 0.19, 0.2)
const FLAME_CORE := Color(1.0, 0.9, 0.5)
# -----------------------------------------------------------------------------

## Dónde va cada llama, en el espacio del puente. Lo llena build().
var flame_spots: Array[Vector3] = []

var _bridge: Bridge = null
var _mesh: LowPolyMesh = null
var _flame_mesh: ArrayMesh = null
var _flame_material: StandardMaterial3D = null


func _init(bridge: Bridge) -> void:
	_bridge = bridge


## La malla de piedra del puente entero, lista para colgar de él.
func build() -> MeshInstance3D:
	_mesh = LowPolyMesh.new(_bridge.shape_seed)
	flame_spots.clear()
	_deck()
	_arches()
	for side: float in [-1.0, 1.0]:
		_abutment(side)
		_parapet(side)
		_lintel(side)
		for turn: float in [-1.0, 1.0]:
			if _bridge.has_stairs(side):
				_stairs(side, turn)
			_tower(side, turn)
	return _mesh.instance("Stone")


## Una llama de brasero: la misma malla para las cuatro, sin sombra propia.
func flame() -> MeshInstance3D:
	if _flame_mesh == null:
		var fire := LowPolyMesh.new(_bridge.shape_seed + 7)
		fire.blob(Vector3(0.0, 0.95, 0.0), Vector3(0.78, 1.25, 0.78), _bridge.flame_color, 5, 3, 0.22)
		fire.blob(Vector3(0.0, 0.62, 0.0), Vector3(0.42, 0.75, 0.42), FLAME_CORE, 4, 3, 0.15)
		_flame_mesh = fire.commit()
		_flame_material = StandardMaterial3D.new()
		_flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_flame_material.vertex_color_use_as_albedo = true
	var view := MeshInstance3D.new()
	view.name = "Flame"
	view.mesh = _flame_mesh
	view.material_override = _flame_material
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return view


# --- piezas ------------------------------------------------------------------------

## El tablero: una hilada de remate en cada costado y las losas de arriba.
func _deck() -> void:
	var b := _bridge
	var half_length := b.span * 0.5 + b.overlap
	var half_width := b.deck_width() * 0.5
	for turn: float in [-1.0, 1.0]:
		_wall(Vector3(-half_length, 0.0, turn * half_width), Vector3.RIGHT, half_length * 2.0,
				-b.deck_thickness, 0.0, Vector3(0.0, 0.0, turn), b.trim_color, b.trim_color)
	_paving(Vector3(-half_length, 0.0, -half_width), Vector3.RIGHT, half_length * 2.0,
			Vector3.BACK, half_width * 2.0, PAVERS_ACROSS)


## Los arcos: la bóveda de cada uno, sus dos frentes con el aro de dovelas,
## y las pilas con sus tajamares.
func _arches() -> void:
	var b := _bridge
	var half_width := b.deck_width() * 0.5
	var spring := b.spring_y()
	var rise := b.crown_y() - spring
	var half_arch := b.arch_span() * 0.5
	var left := -b.clear_span() * 0.5
	for index in b.pier_count + 1:
		var middle := left + half_arch
		_vault(middle, half_arch, spring, rise, half_width)
		left += half_arch * 2.0
		if index < b.pier_count:
			_pier(index, spring, half_width)
			left += b.pier_thickness


## La bóveda de un arco de centro `middle` y media luz `half_arch`.
func _vault(middle: float, half_arch: float, spring: float, rise: float,
		half_width: float) -> void:
	var b := _bridge
	var top := -b.deck_thickness
	var heart := Vector3(middle, spring, 0.0)
	var curve := PackedVector3Array()
	for step in ARCH_STEPS + 1:
		var angle := PI * (1.0 - float(step) / float(ARCH_STEPS))
		curve.append(Vector3(middle + cos(angle) * half_arch, spring + sin(angle) * rise, 0.0))
	for step in ARCH_STEPS:
		var from := curve[step]
		var to := curve[step + 1]
		var tone := _stone((from.y + to.y) * 0.5)
		# El intradós: lo que se ve desde el fondo del cañón.
		_mesh.plate(from + Vector3.FORWARD * half_width, to + Vector3.FORWARD * half_width,
				to + Vector3.BACK * half_width, from + Vector3.BACK * half_width, tone,
				Vector3(middle, 0.0, 0.0))
		for turn: float in [-1.0, 1.0]:
			var face := Vector3(0.0, 0.0, turn * half_width)
			var inside := Vector3((from.x + to.x) * 0.5, top, 0.0)
			# El tímpano: del arco hasta el tablero.
			_mesh.plate(from + face, to + face, Vector3(to.x, top, face.z),
					Vector3(from.x, top, face.z), _stone(top), inside)
			# La dovela, apenas salida del frente.
			var out := Vector3(0.0, 0.0, turn * (half_width + 0.07))
			var from_far := heart + (from - heart) * (1.0 + RING_WIDTH / (from - heart).length())
			var to_far := heart + (to - heart) * (1.0 + RING_WIDTH / (to - heart).length())
			from_far.y = minf(from_far.y, top)
			to_far.y = minf(to_far.y, top)
			_mesh.plate(from + out, to + out, to_far + out, from_far + out, b.trim_color, inside)


## La pila `index`: seis caras de sillares hasta el arranque de los arcos,
## los dos frentes hasta el tablero y la tapa en punta de cada tajamar.
func _pier(index: int, spring: float, half_width: float) -> void:
	var b := _bridge
	var x := b.pier_x(index)
	var half := b.pier_thickness * 0.5
	var outline := b.pier_hull(index, -b.drop, spring).slice(0, 6)
	var center := Vector3(x, 0.0, 0.0)
	for corner in 6:
		var from := outline[corner]
		var to := outline[(corner + 1) % 6]
		var along := Vector3(to.x - from.x, 0.0, to.z - from.z)
		var out := Vector3(along.z, 0.0, -along.x).normalized()
		var middle := (from + to) * 0.5
		if out.dot(Vector3(middle.x, 0.0, middle.z) - center) < 0.0:
			out = -out
		_wall(Vector3(from.x, 0.0, from.z), along.normalized(), along.length(), -b.drop, spring,
				out, b.stone_low_color, b.stone_color)
	for turn: float in [-1.0, 1.0]:
		var face := turn * half_width
		_wall(Vector3(x - half, 0.0, face), Vector3.RIGHT, b.pier_thickness, spring,
				-b.deck_thickness, Vector3(0.0, 0.0, turn), b.stone_low_color, b.stone_color)
		var cap := b.cutwater_cap(index, turn)
		var inside := Vector3(x, spring - 1.0, face)
		_mesh.triangle(cap[0], cap[2], cap[3], b.moss_color, inside)
		_mesh.triangle(cap[2], cap[1], cap[3], b.moss_color, inside)


## El estribo de la orilla `side` (-1, +1): su frente bajo el primer arco y
## las dos alas que asoman a cada lado del tablero.
func _abutment(side: float) -> void:
	var b := _bridge
	var front := side * b.clear_span() * 0.5
	var out := Vector3(-side, 0.0, 0.0)
	_wall(Vector3(front, 0.0, -b.width * 0.5), Vector3.BACK, b.width, -b.drop, b.spring_y(),
			out, b.stone_low_color, b.stone_color)
	var deck_half := b.deck_width() * 0.5
	for turn: float in [-1.0, 1.0]:
		var edge := Vector3(front, 0.0, turn * deck_half)
		_wall(edge, Vector3(0.0, 0.0, turn), b.wing, b.spring_y(), 0.0, out, b.stone_low_color,
				b.stone_color)
		# La cara de arriba del ala, fuera de la baranda: nadie la pisa.
		var back := Vector3(side * (b.span * 0.5 + b.overlap), 0.0, turn * deck_half)
		var reach := Vector3(0.0, 0.0, turn * b.wing)
		_mesh.plate(edge, back, back + reach, edge + reach, b.moss_color,
				edge + Vector3(0.0, -1.0, 0.0))


## La baranda del costado `turn` (-1, +1) del tablero: paños entre postes.
func _parapet(turn: float) -> void:
	var b := _bridge
	var z := turn * (b.deck_width() - b.parapet_thickness) * 0.5
	# De torre a torre: los postes de las puntas quedan dentro de ellas.
	var half_length := b.span * 0.5 - b.tower_inset
	var posts := maxi(roundi(half_length * 2.0 / b.post_every), 1)
	var gap := half_length * 2.0 / float(posts)
	for index in posts + 1:
		var x := -half_length + gap * float(index)
		_mesh.block(Transform3D(Basis.IDENTITY, Vector3(x, (b.parapet_height + 0.3) * 0.5, z)),
				Vector3(0.72, b.parapet_height + 0.3, b.parapet_thickness + 0.16), b.trim_color)
		if index < posts:
			_mesh.block(Transform3D(Basis.IDENTITY,
					Vector3(x + gap * 0.5, b.parapet_height * 0.5, z)),
					Vector3(gap - 0.7, b.parapet_height, b.parapet_thickness), b.stone_color)


## La torre de la orilla `side` y del costado `turn`: zócalo, fuste, collar
## y el cuenco del brasero. Anota dónde va su llama.
func _tower(side: float, turn: float) -> void:
	var b := _bridge
	var foot := b.tower_spot(side, turn)
	var radius := b.tower_radius
	var top := b.tower_height
	var spin := PI / float(TOWER_SIDES)
	# (altura, radio, color) de cada anillo, de abajo arriba.
	var rings: Array[Vector3] = [
		Vector3(-1.2, radius * 1.24, 0.0), Vector3(0.9, radius * 1.24, 0.0),
		Vector3(1.15, radius, 1.0), Vector3(top * 0.5, radius * 0.95, 1.0),
		Vector3(top - 1.5, radius * 0.9, 1.0), Vector3(top - 1.3, radius * 1.16, 2.0),
		Vector3(top - 0.85, radius * 1.16, 2.0), Vector3(top - 0.7, radius * 0.74, 3.0),
		Vector3(top, radius * 1.22, 3.0),
	]
	var tones: Array[Color] = [b.stone_low_color, b.stone_color, b.trim_color, BOWL_COLOR]
	var lower := _mesh.ring(foot + Vector3.UP * rings[0].x, rings[0].y, TOWER_SIDES, spin)
	for index in range(1, rings.size()):
		var upper := _mesh.ring(foot + Vector3.UP * rings[index].x, rings[index].y, TOWER_SIDES,
				spin)
		_mesh.band(lower, upper, tones[int(rings[index].z)])
		lower = upper
	var embers := _mesh.ring(foot + Vector3.UP * (top - 0.25), radius * 1.05, TOWER_SIDES, spin)
	_mesh.cap(embers, b.flame_color.darkened(0.35), foot)
	flame_spots.append(foot + Vector3.UP * (top - 0.2))


## El dintel entre las dos torres de la orilla `side`, con su remate.
func _lintel(side: float) -> void:
	var b := _bridge
	if b.lintel_height <= 0.0:
		return
	var x := b.tower_spot(side, 1.0).x
	var reach := b.tower_spot(side, 1.0).z
	var y := b.tower_height - LINTEL_DROP - b.lintel_height * 0.5
	_mesh.block(Transform3D(Basis.IDENTITY, Vector3(x, y, 0.0)),
			Vector3(b.tower_radius * 1.3, b.lintel_height, reach * 2.0), b.trim_color)
	_mesh.block(Transform3D(Basis.IDENTITY, Vector3(x, y + b.lintel_height * 0.5 + 0.4, 0.0)),
			Vector3(b.tower_radius * 1.5, 0.8, 2.2), b.stone_color)
	for turn: float in [-1.0, 1.0]:
		_mesh.block(Transform3D(Basis.IDENTITY, Vector3(x, y - b.lintel_height * 0.5 - 0.35,
				turn * (reach - b.tower_radius - 0.45))),
				Vector3(b.tower_radius * 1.1, 0.7, 0.9), b.stone_color)
	for face: float in [-1.0, 1.0]:
		_banner(Vector3(x + face * (b.tower_radius * 0.65 + 0.06),
				y - b.lintel_height * 0.5, 0.0), face)


## El estandarte que cuelga del dintel hacia `facing` (-1, +1 en X): un paño
## con su franja y la punta partida en dos.
func _banner(top: Vector3, facing: float) -> void:
	var b := _bridge
	var half := b.banner_width * 0.5
	var drop := b.banner_length
	var inside := top - Vector3(facing, 0.0, 0.0)
	var body := drop * 0.72
	_mesh.plate(top + Vector3(0.0, 0.0, -half), top + Vector3(0.0, 0.0, half),
			top + Vector3(0.0, -body, half), top + Vector3(0.0, -body, -half),
			b.banner_color, inside)
	var band := top + Vector3(0.0, -body, 0.0)
	_mesh.plate(band + Vector3(0.0, 0.0, -half), band + Vector3(0.0, 0.0, half),
			band + Vector3(0.0, -drop * 0.1, half), band + Vector3(0.0, -drop * 0.1, -half),
			b.banner_trim_color, inside)
	var tail := band + Vector3(0.0, -drop * 0.1, 0.0)
	for turn: float in [-1.0, 1.0]:
		_mesh.triangle(tail + Vector3(0.0, 0.0, turn * half), tail,
				tail + Vector3(0.0, -drop * 0.18, turn * half), b.banner_color, inside)


## La escalera de la orilla `side` que baja hacia `turn`: el descanso, los
## peldaños y la cara de afuera, que cae inclinada como la roca.
func _stairs(side: float, turn: float) -> void:
	var b := _bridge
	var hull := b.stair_hull(side, turn)
	var near := hull[0].z
	var landing := absf(hull[3].z - near)
	var run := absf(hull[4].z - hull[3].z)
	var inner := side * (b.span * 0.5 + 0.2)
	# El descanso.
	_paving(Vector3(inner, 0.0, near), Vector3(hull[1].x - inner, 0.0, 0.0).normalized(),
			absf(hull[1].x - inner), Vector3(0.0, 0.0, turn), landing, 2)
	# Los peldaños: cada uno, su huella y su contrahuella.
	var steps := maxi(roundi(b.drop / b.step_rise), 1)
	var rise := b.drop / float(steps)
	var going := run / float(steps)
	var solid := Vector3(inner, -b.drop, hull[3].z)
	for step in steps:
		var y := -(float(step) + 0.5) * rise
		var above := 0.0 if step == 0 else y + rise
		var from_z := hull[3].z + turn * going * float(step)
		var to_z := from_z + turn * going
		var outer := hull[1].x - side * b.stair_batter() * -y
		_mesh.plate(Vector3(inner, y, from_z), Vector3(outer, y, from_z),
				Vector3(outer, y, to_z), Vector3(inner, y, to_z), b.paving_color, solid)
		_mesh.plate(Vector3(inner, y, from_z), Vector3(outer, y, from_z),
				Vector3(outer, above, from_z), Vector3(inner, above, from_z), b.trim_color,
				Vector3(inner, y, from_z - turn))
	# La cara de afuera: sillares bajo el descanso y bajo la bajada.
	var lean := Vector3(-side * b.stair_batter(), 0.0, 0.0)
	var courses := ceili(b.drop / COURSE)
	for course in courses:
		var high := -float(course) * COURSE
		var low := maxf(high - COURSE, -b.drop)
		var length := landing + run * (-high / b.drop)
		var corner := Vector3(hull[1].x, 0.0, near)
		_wall(corner, Vector3(0.0, 0.0, turn), length, low, high, Vector3(-side, 0.0, 0.0),
				b.stone_low_color, b.stone_color, lean)
		# El triángulo entre el último sillar y la bajada.
		var edge := corner + Vector3(0.0, 0.0, turn * length)
		var next := landing + run * (-low / b.drop)
		_mesh.triangle(edge + lean * -high + Vector3.UP * high,
				edge + lean * -low + Vector3.UP * low,
				corner + Vector3(0.0, 0.0, turn * next) + lean * -low + Vector3.UP * low,
				_stone((high + low) * 0.5), Vector3(side * b.span * 0.5, low, edge.z))


# --- ayudas ------------------------------------------------------------------------

## Un muro vertical de sillares en aparejo trabado. Arranca en `corner` (XZ),
## corre `length` metros hacia `along` y va de la altura `low` a `high`;
## `out` mira hacia fuera. Con `lean`, cada metro que baja se corre eso en
## horizontal (un muro en talud). El tono va de `deep` abajo a `shallow` arriba.
func _wall(corner: Vector3, along: Vector3, length: float, low: float, high: float,
		out: Vector3, deep: Color, shallow: Color, lean: Vector3 = Vector3.ZERO) -> void:
	if length <= 0.05 or high - low <= 0.02:
		return
	var courses := ceili((high - low) / COURSE)
	for course in courses:
		var top := high - float(course) * COURSE
		var bottom := maxf(top - COURSE, low)
		var tone := deep.lerp(shallow, clampf(1.0 + (top + bottom) * 0.5 / _bridge.drop, 0.0, 1.0))
		# Aparejo trabado: una hilada sí y otra no empieza con medio sillar
		# (se cuenta desde el tablero, así dos muros vecinos coinciden).
		var cursor := -BLOCK * 0.5 if absi(roundi(top / COURSE)) % 2 == 1 else 0.0
		while cursor < length - 0.05:
			var from := maxf(cursor, 0.0)
			var to := minf(cursor + BLOCK, length)
			cursor += BLOCK
			if to - from < 0.05:
				continue
			var a := corner + along * from
			var c := corner + along * to
			_mesh.plate(a + lean * -bottom + Vector3.UP * bottom,
					c + lean * -bottom + Vector3.UP * bottom,
					c + lean * -top + Vector3.UP * top, a + lean * -top + Vector3.UP * top,
					tone, (a + c) * 0.5 + Vector3.UP * (top + bottom) * 0.5 - out)


## Un piso de losas a la altura de `corner`: `length` metros hacia `along`
## por `depth` metros hacia `across`, con `rows` losas a lo ancho.
func _paving(corner: Vector3, along: Vector3, length: float, across: Vector3, depth: float,
		rows: int) -> void:
	var count := maxi(roundi(length / BLOCK), 1)
	var step := along * (length / float(count))
	var row := across * (depth / float(rows))
	for index in count:
		for lane in rows:
			var a := corner + step * float(index) + row * float(lane)
			_mesh.plate(a, a + step, a + step + row, a + row, _bridge.paving_color,
					a + Vector3.DOWN)


## El tono de un sillar a la altura `y` (0 = el tablero, -drop = el fondo).
func _stone(y: float) -> Color:
	return _bridge.stone_low_color.lerp(_bridge.stone_color,
			clampf(1.0 + y / _bridge.drop, 0.0, 1.0))
