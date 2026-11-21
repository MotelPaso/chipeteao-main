class_name CliffWall
extends StaticBody3D
## La roca de UN corte del relieve por zonas (un acantilado, el costado de
## una rampa, una pared del cañón): una cinta facetada a lo largo de la
## línea de corte (ReliefLayout.CutPath).
##
## QUÉ ES. En cada punto de la línea, un perfil de siete filas: del lado
## alto, una CORNISA que sale enterrada del suelo, sube un labio y llega al
## borde; del lado bajo, una CARA empinada que baja del borde hasta
## enterrarse al pie. Donde el corte se acaba (el pie de una rampa, un
## extremo del cañón) el perfil entero se hunde y la roca desaparece.
##
## POR QUÉ LA CORNISA ES ANCHA. El colisionador del terreno lleva el escalón
## del corte corrido ReliefLayout.LEDGE_INSET metros hacia el lado alto. La
## cornisa lo tapa entero: lo que se pisa y lo que se ve junto a un corte es
## esta roca, nunca el escalón.
##
## LA COLISIÓN ES LA MALLA, como en RockFormation: cada cuadrado de la cinta
## es también un prisma convexo (sus cuatro esquinas más las mismas hundidas
## bajo el suelo), partido por la diagonal más alta.
##
## NINGUNA CARA ENTRE 45 Y 60 GRADOS. La horda camina hasta 45 y trepa desde
## 60: en medio se queda trabada. La cornisa va muy por debajo de 45 y la
## cara muy por encima de 60 a CUALQUIER altura del corte, porque su avance
## horizontal es una fracción fija de lo que baja (FACE_RUN). build() cuenta
## las caras que quedaran en la franja (gap_faces, debería ser 0).
##
## La levanta el scatter (ReliefDressing) como hija suya, así arde con el
## bosque en el infierno de Mythos igual que las formaciones.

## Edita aquí (no hay Inspector). Lo que cambia por bioma (colores, material)
## viene del RockFormationStyle del scatter.
##
## Filas del perfil, del lado alto al bajo.
const ROWS: int = 7
## Metros hacia el lado alto, desde la línea de corte, de las tres filas de
## la cornisa: la enterrada, la interior y la del medio.
const LEDGE_BURIED: float = ReliefLayout.LEDGE_INSET + 3.2
const LEDGE_INNER: float = ReliefLayout.LEDGE_INSET + 1.6
const LEDGE_MID: float = 1.4
## Metros hacia el lado bajo de la fila del borde.
const CREST_OUT: float = 0.15
## Metros bajo el suelo de la fila enterrada de la cornisa y de la del pie.
const BURY_TOP: float = 0.45
const BURY_FOOT: float = 0.7
## El labio: cuánto sobresale el borde sobre el suelo del lado alto, en
## metros. Crece con la altura del corte, entre estos dos topes.
const LIP_MIN: float = 0.08
const LIP_PER_METER: float = 0.05
const LIP_MAX: float = 0.32
## Avance horizontal de la cara por metro que baja: 0.24 son 76 grados.
const FACE_RUN: float = 0.24
## A qué fracción del avance y de la bajada van las dos filas intermedias de
## la cara, y cuánto varía esa bajada de un punto a otro (da el facetado).
const FACE_ACROSS: Array[float] = [0.4, 0.75]
const FACE_DOWN: Array[float] = [0.42, 0.78]
const FACE_WOBBLE: float = 0.04
## Un corte más bajo que esto no lleva roca: el perfil va enterrado, apenas
## CLOSED_SINK metros bajo el suelo. Así la roca asoma de a poco y su cornisa
## no sube más empinada que la rampa que acompaña.
const CLOSED_HEIGHT: float = 0.12
const CLOSED_SINK: float = 0.03
## Una faceta más chica que esto (m²) es una astilla: no se dibuja ni cuenta.
const SLIVER_AREA: float = 0.03
## Corrimiento de cada perfil a lo largo de la línea, en metros, y de las
## filas de la cornisa a lo ancho: rompe la regularidad de la cinta.
const JITTER_ALONG: float = 0.3
const JITTER_ACROSS: float = 0.12
## Fondo de cada prisma de colisión bajo el suelo del lado bajo, en metros.
const PRISM_DEPTH: float = 1.6
## La franja prohibida, en grados (con un grado de holgura a cada lado).
const GAP_FROM: float = 44.0
const GAP_TO: float = 61.0
## Sombreado horneado, igual que el de RockFormation.
const CAP_FROM: float = 0.8
const CAP_TO: float = 0.94
const STEEP_SHADE: float = 0.58
const FOOT_SHADE: float = 0.78
const FOOT_HEIGHT: float = 2.5
const GRAIN: float = 0.07
const STRATA_FREQUENCY: float = 3.1

## Aspecto del bioma; lo pone quien la crea antes de build().
var style: RockFormationStyle = null

## Estadísticas para el log, válidas tras build().
var face_count: int = 0
var prism_count: int = 0
## Caras con pendiente entre GAP_FROM y GAP_TO (debería ser 0).
var gap_faces: int = 0
## Mayor altura visible del corte, en metros.
var tallest: float = 0.0

var _terrain: Terrain = null
var _seed: int = 0
var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()


## Levanta la roca sobre `path`. `terrain` da el suelo de cada lado y
## `noise_seed` (la semilla de partida) fija el facetado.
func build(path: ReliefLayout.CutPath, terrain: Terrain, noise_seed: int) -> void:
	if style == null:
		style = RockFormationStyle.new()
	_terrain = terrain
	_seed = noise_seed
	var count := path.points.size()
	var tops := PackedVector3Array()
	var floors := PackedFloat32Array()
	var feet := PackedFloat32Array()
	var open := PackedByteArray()
	tops.resize(count * ROWS)
	floors.resize(count * ROWS)
	feet.resize(count)
	open.resize(count)
	for index in count:
		var visible := path.upper[index] - path.lower[index]
		open[index] = 1 if visible >= CLOSED_HEIGHT else 0
		tallest = maxf(tallest, visible)
		feet[index] = _profile(path, index, tops, floors)
	var owner_id := create_shape_owner(self)
	for index in count - 1:
		if open[index] == 0 and open[index + 1] == 0:
			continue
		for row in ROWS - 1:
			var a := index * ROWS + row
			_quad(owner_id, tops, floors, a, a + ROWS, a + 1, a + ROWS + 1,
					(feet[index] + feet[index + 1]) * 0.5, (index * ROWS + row) * 2)
	if not _vertices.is_empty():
		_attach_mesh()


## Las ROWS esquinas del perfil del punto `index`, con el fondo de su prisma
## en `floors`. Devuelve la altura del suelo al pie, para el sombreado.
func _profile(path: ReliefLayout.CutPath, index: int, tops: PackedVector3Array,
		floors: PackedFloat32Array) -> float:
	var normal := path.normals[index]
	var miter := path.miter[index]
	var point := path.points[index]
	var upper := path.upper[index]
	var lower := path.lower[index]
	# El perfil se corre a lo largo de la línea, y sus alturas con él (se
	# interpolan hacia el vecino): si no, el corrimiento empinaría la cornisa.
	var shift := _hash(index, 1) * JITTER_ALONG
	var toward := index + (1 if shift > 0.0 else -1)
	if toward >= 0 and toward < path.points.size() and is_equal_approx(miter, 1.0):
		var reach := point.distance_to(path.points[toward])
		var t := absf(shift) / maxf(reach, 0.001)
		point = point.lerp(path.points[toward], t)
		upper = lerpf(upper, path.upper[toward], t)
		lower = lerpf(lower, path.lower[toward], t)
	var visible := upper - lower
	var lip := clampf(LIP_MIN + LIP_PER_METER * visible, LIP_MIN, LIP_MAX) \
			* (1.0 + _hash(index, 2) * 0.25)
	var shut := path.upper[index] - path.lower[index] < CLOSED_HEIGHT
	# Lado alto: enterrada, interior, medio y borde.
	var across: Array[float] = [-LEDGE_BURIED, -LEDGE_INNER + _hash(index, 3) * JITTER_ACROSS,
			-LEDGE_MID + _hash(index, 4) * JITTER_ACROSS, CREST_OUT]
	var rise: Array[float] = [-BURY_TOP, lip * 0.3, lip * (0.75 + _hash(index, 5) * 0.2), lip]
	var crest := Vector3.ZERO
	for row in 4:
		var at := point + normal * (across[row] * miter)
		var ground := _terrain.base_height_at(at.x, at.y)
		var height := ground + upper + rise[row]
		if shut:
			height = ground + minf(upper, lower) - (BURY_TOP if row == 0 else CLOSED_SINK)
		tops[index * ROWS + row] = Vector3(at.x, height, at.y)
		floors[index * ROWS + row] = ground + lower - PRISM_DEPTH
		crest = tops[index * ROWS + row]
	# Lado bajo: dos filas de cara y el pie enterrado. El avance es una
	# fracción fija de la bajada, así la cara nunca se acuesta.
	var drop := visible + lip
	var run := FACE_RUN * drop * miter
	var foot := point + normal * (CREST_OUT * miter + run + 0.05)
	var foot_ground := _terrain.base_height_at(foot.x, foot.y) + lower
	for step in 3:
		var row := 4 + step
		var at := foot
		var height := foot_ground - BURY_FOOT
		if step < 2:
			at = point + normal * (CREST_OUT * miter + run * FACE_ACROSS[step])
			height = lerpf(crest.y, foot_ground,
					FACE_DOWN[step] + _hash(index, 6 + step) * FACE_WOBBLE)
		if shut:
			height = minf(height, foot_ground - (CLOSED_SINK if step < 2 else BURY_FOOT))
		tops[index * ROWS + row] = Vector3(at.x, height, at.y)
		floors[index * ROWS + row] = foot_ground - PRISM_DEPTH
	return foot_ground


## Dos facetas y un prisma de colisión para el cuadrado entre dos perfiles
## vecinos y dos filas vecinas: a-b son la fila de arriba (un punto y el
## siguiente), c-d la de abajo.
func _quad(owner_id: int, tops: PackedVector3Array, floors: PackedFloat32Array, a: int, b: int,
		c: int, d: int, foot: float, key: int) -> void:
	# La diagonal MÁS ALTA: la envolvente superior de las cuatro esquinas, así
	# el prisma y las dos caras dibujadas son la misma superficie.
	if tops[a].y + tops[d].y >= tops[b].y + tops[c].y:
		_emit(tops[a], tops[b], tops[d], foot, key)
		_emit(tops[a], tops[d], tops[c], foot, key + 1)
	else:
		_emit(tops[a], tops[b], tops[c], foot, key)
		_emit(tops[b], tops[d], tops[c], foot, key + 1)
	var hull := PackedVector3Array()
	for corner: int in [a, b, c, d]:
		hull.append(tops[corner])
		hull.append(Vector3(tops[corner].x, minf(floors[corner], tops[corner].y - 0.5),
				tops[corner].z))
	var prism := ConvexPolygonShape3D.new()
	prism.points = hull
	shape_owner_add_shape(owner_id, prism)
	prism_count += 1


## Una faceta de sombreado plano, con la cara frontal hacia arriba (misma
## regla de sentido que el suelo del Terrain y que RockFormation).
func _emit(v0: Vector3, v1: Vector3, v2: Vector3, foot: float, key: int) -> void:
	var cross := (v1 - v0).cross(v2 - v0)
	if cross.y > 0.0:
		var swap := v1
		v1 = v2
		v2 = swap
		cross = -cross
	if cross.length() * 0.5 < SLIVER_AREA:
		return
	var normal := (-cross).normalized()
	var slope := rad_to_deg(acos(clampf(normal.y, -1.0, 1.0)))
	if slope > GAP_FROM and slope < GAP_TO:
		gap_faces += 1
	var height := maxf((v0.y + v1.y + v2.y) / 3.0 - foot, 0.0)
	var tint := _facet_color(normal, height, key)
	for vertex: Vector3 in [v0, v1, v2]:
		_vertices.append(vertex)
		_normals.append(normal)
		_colors.append(tint)
	face_count += 1


func _attach_mesh() -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var view := MeshInstance3D.new()
	view.name = "Mesh"
	view.mesh = mesh
	view.material_override = style.surface_material if style.surface_material != null \
			else RockFormation.DEFAULT_MATERIAL
	add_child(view)
	_vertices = PackedVector3Array()
	_normals = PackedVector3Array()
	_colors = PackedColorArray()


## Roca en las caras, tinte de cima en la cornisa, caras empinadas más
## oscuras, más oscuro al pie, bandas por altura y grano por faceta.
func _facet_color(normal: Vector3, height: float, key: int) -> Color:
	var cap := smoothstep(CAP_FROM, CAP_TO, normal.y) * style.cap_strength
	var tone := style.rock_color.lerp(style.cap_color, cap)
	var slope := lerpf(1.1, STEEP_SHADE, smoothstep(0.35, 0.95, 1.0 - normal.y))
	var foot := lerpf(FOOT_SHADE, 1.0, clampf(height / FOOT_HEIGHT, 0.0, 1.0))
	var band := 1.0 + style.strata_strength * sin(height * STRATA_FREQUENCY)
	var grain := 1.0 + _hash(key, 11) * GRAIN
	var value := slope * foot * band * grain
	return Color(tone.r * value, tone.g * value, tone.b * value, 1.0)


## Número determinista en [-1, 1] para el índice `index` y la sal `salt`: el
## facetado no saca números de ningún RNG.
func _hash(index: int, salt: int) -> float:
	var h := (index * 374761393 + salt * 668265263 + _seed * 1442695041) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	h = h ^ (h >> 16)
	return float(h & 0xffff) / 32767.5 - 1.0
