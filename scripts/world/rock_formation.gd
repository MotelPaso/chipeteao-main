class_name RockFormation
extends StaticBody3D
## Un macizo de roca levantado sobre una región conexa de celdas bloqueadas
## de la máscara de la arena.
##
## QUÉ ES. Un campo de alturas facetado sobre la huella de la región: un
## acantilado empinado que empieza con un margen ruidoso FUERA de las celdas
## bloqueadas, y luego una subida más lenta hacia una cresta cuya altura
## sigue la profundidad dentro de la región: una cresta de dos celdas se lee
## como cresta, un macizo compacto tiene cumbre. Sombreado plano, un color
## por faceta: roca en las caras, tinte de cima en las partes casi planas,
## bandas de estratos por altura.
##
## LA COLISIÓN ES LA MALLA. Cada cuadrado de la cuadrícula que asoma sobre
## el suelo es también un prisma convexo: sus cuatro esquinas de superficie
## más las mismas cuatro hundidas bajo el terreno. El cuadrado se parte por
## la diagonal MÁS ALTA, que es justo la envolvente superior de esas
## esquinas, así la tapa del prisma son los dos triángulos que se ven: nada
## invisible con qué chocar, nada visible que se atraviese. Prismas
## convexos y no un trimesh a propósito: un trimesh no tiene interior, y el
## barrido de máscara del ArenaProbe pone una cápsula DENTRO de la roca en
## cada borde de celda; contra un sólido convexo eso es un choque, contra un
## trimesh es una "abertura".
##
## EL SELLO. La máscara se impone solo con esta geometría (no hay muros
## invisibles), así que todo borde que una celda bloqueada comparte con una
## abierta debe ser sólido a la altura de la cápsula. Dos decisiones lo
## vuelven estructural y no probable: el paso de faceta divide exacto el
## tamaño de celda, así cada borde de celda es una fila de aristas (un
## vértice sobre un borde solo se mueve A LO LARGO de él); y la huella
## empieza al menos style.margin_min fuera del borde, donde el acantilado ya está
## bien sobre el suelo. build() mide lo segundo en cada vértice de borde y
## avisa bajo SEAL_MIN_HEIGHT, lo que hace fallar tools/verificar.sh.
##
## La construye una vez place_props() del scatter, después del terreno: toda
## altura aquí es relativa a Terrain.height_at, así la formación se apoya en
## el relieve en vez de flotar sobre una hondonada.

## Ajustes de forma y sombreado comunes a todos los biomas. Este nodo se crea
## por código y no tiene Inspector: edita aquí. Lo que cambia por bioma vive
## en RockFormationStyle (assets/world/rock_style_<mapa>.tres).
##
## Material de las caras si el estilo no trae otro: albedo blanco
## multiplicado por los colores de vértice por faceta que se arman abajo.
const DEFAULT_MATERIAL: Material = preload("res://assets/materials/rock_formation.tres")
## Profundidad en metros a la que se hunden los vértices exteriores de la
## huella, para que la roca toque el relieve sin costura visible.
const BURY_DEPTH: float = 0.8
## Fondo de cada prisma de colisión bajo el suelo, en metros: lo bastante
## hondo para que ningún cuerpo sobre el terreno se cuele bajo un prisma.
const PRISM_DEPTH: float = 1.6
## Desplazamiento de un vértice fuera de su lugar en la cuadrícula, como
## fracción del paso. Bajo 0.25 todo cuadrado queda convexo en planta, y la
## envolvente del prisma depende de eso.
const JITTER: float = 0.22
## La distancia interior deja de medirse pasados estos metros: el perfil
## ya se aplanó mucho antes.
const INTERIOR_CAP: float = 24.0
## Altura mínima de roca sobre el suelo EN un borde de celda, en metros. La
## cápsula del barrido ocupa 0-1.8 m sobre el suelo ahí; cualquier altura
## sobre cero sella, y esto deja margen para el ruido y la curvatura del
## terreno. El peor caso del perfil por defecto (margin_min, lift y crag en
## su mínimo) es ~0.95 m.
const SEAL_MIN_HEIGHT: float = 0.75
## Bandas de estratos por metro de altura (argumento del seno), para style.strata_strength.
const STRATA_FREQUENCY: float = 3.1
## Bajo esta normal Y una faceta es toda roca; sobre CAP_TO toma el tinte
## de cima completo: los flancos de la cresta suben a 20-35 grados (normal
## Y 0.82-0.94), el acantilado a 50-70 (0.34-0.64).
const CAP_FROM: float = 0.8
const CAP_TO: float = 0.94
## Brillo de una cara vertical frente a una plana (sombreado por pendiente).
const STEEP_SHADE: float = 0.58
## Brillo en el pie mismo, que vuelve a 1 a FOOT_HEIGHT metros de altura.
const FOOT_SHADE: float = 0.78
const FOOT_HEIGHT: float = 2.5
## Grano de brillo +- por faceta.
const GRAIN: float = 0.07
## Fracción de style.max_height donde el techo suave empieza a doblar las alturas.
const KNEE: float = 0.75

## Geometría de la máscara en metros; la pone el scatter antes de build().
var cell_size: float
var half_extent: float
## Aspecto del bioma (colores, acantilado, cresta, escalones). Lo pone el
## scatter antes de build(); vacío, build() usa los valores por defecto de
## RockFormationStyle.
var style: RockFormationStyle = null

## Estadísticas para el log de una línea del scatter, válidas tras build().
var face_count: int = 0
var prism_count: int = 0
## Vértices de borde que quedaron bajo SEAL_MIN_HEIGHT (debería ser 0).
var seal_low: int = 0
## Altura del vértice más alto sobre su propio suelo, en metros.
var tallest: float = 0.0

var _cells: Dictionary[Vector2i, bool] = {}
var _terrain: Terrain = null
var _step: float = 2.0
var _seed: int = 0
## La cuadrícula de facetas en construcción: superficie, suelo y altura de
## la roca sobre el suelo por punto (ver _sample_grid).
var _tops := PackedVector3Array()
var _grounds := PackedFloat32Array()
var _heights := PackedFloat32Array()
## La superficie en construcción: una entrada por esquina de faceta, sombreado plano.
var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _lift_noise := FastNoiseLite.new()
var _crag_noise := FastNoiseLite.new()
var _edge_noise := FastNoiseLite.new()
var _spire_noise := FastNoiseLite.new()


## Levanta la formación sobre `cells` (una región conexa, en coordenadas de
## la máscara del scatter). `noise_seed` es la semilla de la partida, así
## BONK_GAME_SEED y la Cacería diaria reproducen la misma roca y la misma máscara.
func build(cells: Dictionary[Vector2i, bool], terrain: Terrain, noise_seed: int) -> void:
	if style == null:
		style = RockFormationStyle.new()
	_cells = cells
	_terrain = terrain
	_seed = noise_seed
	_setup_noise(noise_seed)
	var per_cell := maxi(int(round(cell_size / maxf(style.mesh_step, 0.5))), 1)
	_step = cell_size / float(per_cell)
	# Límites de la huella, con el margen máximo más un paso, ajustados hacia
	# fuera a la cuadrícula global de facetas (comparte origen con la de
	# celdas: esa alineación es EL SELLO de arriba).
	var low := Vector2i(1 << 30, 1 << 30)
	var high := Vector2i(-(1 << 30), -(1 << 30))
	for cell: Vector2i in _cells:
		low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.y))
		high = Vector2i(maxi(high.x, cell.x), maxi(high.y, cell.y))
	var pad := style.margin_max + _step
	var first := Vector2i(
			floori((float(low.x) * cell_size - pad) / _step),
			floori((float(low.y) * cell_size - pad) / _step))
	var last := Vector2i(
			ceili((float(high.x + 1) * cell_size + pad) / _step),
			ceili((float(high.y + 1) * cell_size + pad) / _step))
	var columns := last.x - first.x + 1
	var rows := last.y - first.y + 1
	_sample_grid(first, columns, rows, per_cell)
	_emit_quads(first, columns, rows)
	_tops = PackedVector3Array()
	_grounds = PackedFloat32Array()
	_heights = PackedFloat32Array()
	if _vertices.is_empty():
		return
	_attach_mesh()


## Llena _tops, _grounds y _heights con un vértice por punto de la
## cuadrícula de facetas que cubre la huella, y mide tallest y seal_low.
func _sample_grid(first: Vector2i, columns: int, rows: int, per_cell: int) -> void:
	_tops.resize(columns * rows)
	_grounds.resize(columns * rows)
	_heights.resize(columns * rows)
	for row in rows:
		for column in columns:
			var gx := first.x + column
			var gz := first.y + row
			var at := _vertex_xz(gx, gz, per_cell)
			var signed := _signed_distance(at)
			var depth := signed + _margin(at)
			var height := _profile(depth, at)
			var ground := _ground(at)
			var index := row * columns + column
			_tops[index] = Vector3(at.x, ground + height, at.y)
			_grounds[index] = ground
			_heights[index] = height
			tallest = maxf(tallest, height)
			if absf(signed) < 0.001 and height < SEAL_MIN_HEIGHT:
				seal_low += 1


## Dos facetas y un prisma de colisión por cada cuadrado de la cuadrícula
## que asoma sobre el suelo.
func _emit_quads(first: Vector2i, columns: int, rows: int) -> void:
	var owner_id := create_shape_owner(self)
	for row in rows - 1:
		for column in columns - 1:
			var a := row * columns + column
			var b := a + 1
			var c := a + columns
			var d := c + 1
			if _heights[a] < 0.0 and _heights[b] < 0.0 and _heights[c] < 0.0 and _heights[d] < 0.0:
				continue
			var key := ((first.y + row) * 65536 + (first.x + column)) * 2
			# La diagonal MÁS ALTA: la envolvente superior de las cuatro
			# esquinas, así el prisma y las dos caras dibujadas son la misma superficie.
			if _tops[a].y + _tops[d].y >= _tops[b].y + _tops[c].y:
				_emit(_tops[a], _tops[b], _tops[d], _heights[a] + _heights[b] + _heights[d], key)
				_emit(_tops[a], _tops[d], _tops[c], _heights[a] + _heights[d] + _heights[c], key + 1)
			else:
				_emit(_tops[a], _tops[b], _tops[c], _heights[a] + _heights[b] + _heights[c], key)
				_emit(_tops[b], _tops[d], _tops[c], _heights[b] + _heights[d] + _heights[c], key + 1)
			var hull := PackedVector3Array()
			for corner: int in [a, b, c, d]:
				hull.append(_tops[corner])
				hull.append(Vector3(_tops[corner].x, _grounds[corner] - PRISM_DEPTH, _tops[corner].z))
			var prism := ConvexPolygonShape3D.new()
			prism.points = hull
			shape_owner_add_shape(owner_id, prism)
			prism_count += 1


## Arma la malla con las facetas emitidas y libera los búferes: la malla ya
## tiene su copia.
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
			else DEFAULT_MATERIAL
	add_child(view)
	_vertices = PackedVector3Array()
	_normals = PackedVector3Array()
	_colors = PackedColorArray()


func _setup_noise(noise_seed: int) -> void:
	# Cuatro campos de una semilla: la ondulación del perfil a decenas de
	# metros, la rugosidad a escala de faceta, el temblor del contorno de la
	# huella y las cumbres.
	_lift_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_lift_noise.seed = noise_seed
	_lift_noise.frequency = 1.0 / 28.0
	_lift_noise.fractal_octaves = 2
	_crag_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_crag_noise.seed = noise_seed + 1
	_crag_noise.frequency = 1.0 / 6.0
	_crag_noise.fractal_octaves = 2
	_edge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_edge_noise.seed = noise_seed + 2
	_edge_noise.frequency = 1.0 / 9.0
	_edge_noise.fractal_octaves = 2
	_spire_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_spire_noise.seed = noise_seed + 3
	_spire_noise.frequency = 1.0 / 16.0
	_spire_noise.fractal_octaves = 1


## XZ de mundo del vértice (gx, gz) de la cuadrícula de facetas, con jitter.
## Un vértice sobre una línea de borde de celda conserva esa coordenada
## exacta (ver EL SELLO).
func _vertex_xz(gx: int, gz: int, per_cell: int) -> Vector2:
	var x := -half_extent + float(gx) * _step
	var z := -half_extent + float(gz) * _step
	if posmod(gx, per_cell) != 0:
		x += (_hash01(gx, gz, _seed) - 0.5) * 2.0 * JITTER * _step
	if posmod(gz, per_cell) != 0:
		z += (_hash01(gx, gz, _seed + 17) - 0.5) * 2.0 * JITTER * _step
	return Vector2(x, z)


## Distancia de `at` al contorno de la región: positiva dentro (a la celda
## más cercana que NO es de la región, fuera de la cuadrícula incluida),
## negativa fuera.
func _signed_distance(at: Vector2) -> float:
	var cell := Vector2i(floori((at.x + half_extent) / cell_size),
			floori((at.y + half_extent) / cell_size))
	if _cells.has(cell):
		var best := INTERIOR_CAP
		var reach := ceili(INTERIOR_CAP / cell_size)
		for ring in range(1, reach + 1):
			for dz in range(-ring, ring + 1):
				for dx in range(-ring, ring + 1):
					if maxi(absi(dx), absi(dz)) != ring:
						continue
					var other := cell + Vector2i(dx, dz)
					if not _cells.has(other):
						best = minf(best, _distance_to_cell(at, other))
			# El anillo r+1 está a r celdas o más: nada más allá puede ganar.
			if best <= float(ring) * cell_size:
				break
		return best
	var nearest := INF
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var other := cell + Vector2i(dx, dz)
			if _cells.has(other):
				nearest = minf(nearest, _distance_to_cell(at, other))
	return -nearest


func _distance_to_cell(at: Vector2, cell: Vector2i) -> float:
	var half := cell_size * 0.5
	var center := Vector2(-half_extent + (float(cell.x) + 0.5) * cell_size,
			-half_extent + (float(cell.y) + 0.5) * cell_size)
	var dx := maxf(absf(at.x - center.x) - half, 0.0)
	var dz := maxf(absf(at.y - center.y) - half, 0.0)
	return sqrt(dx * dx + dz * dz)


## Cuánto llega la huella más allá de las celdas bloqueadas en `at`.
func _margin(at: Vector2) -> float:
	# El FBM simplex rara vez sale de +-0.7; se estira para usar todo el rango.
	var wobble := clampf(_edge_noise.get_noise_2d(at.x, at.y) * 0.7 + 0.5, 0.0, 1.0)
	return lerpf(style.margin_min, style.margin_max, wobble)


## Altura de la roca sobre el suelo a `depth` metros hacia dentro del borde
## de la huella (negativo = fuera de ella, o sea hundida).
func _profile(depth: float, at: Vector2) -> float:
	if depth <= 0.0:
		return -BURY_DEPTH
	var cliff_run := style.cliff_run
	var rise := 1.0 - minf(depth / cliff_run, 1.0)
	var cliff := style.cliff_height * (1.0 - rise * rise)
	var crest := style.peak_height * (1.0 - exp(-maxf(depth - cliff_run, 0.0) / style.peak_run))
	var lift := 1.0 + style.lift_variation * _lift_noise.get_noise_2d(at.x, at.y)
	var height := (cliff + crest) * lift
	var ridge := 1.0 - absf(_spire_noise.get_noise_2d(at.x, at.y))
	height += style.spire_height * ridge * ridge * ridge * smoothstep(3.0, 9.0, depth)
	height += style.crag_height * _crag_noise.get_noise_2d(at.x, at.y) \
			* smoothstep(0.0, cliff_run, depth)
	var terrace_step := style.terrace_step
	if style.terrace_strength > 0.0 and terrace_step > 0.0:
		var level := height / terrace_step
		var ledge := (floorf(level) + smoothstep(0.3, 0.7, level - floorf(level))) * terrace_step
		height = lerpf(height, ledge, style.terrace_strength)
	var max_height := style.max_height
	var knee := max_height * KNEE
	if height > knee:
		var room := max_height - knee
		height = knee + room * tanh((height - knee) / room)
	return maxf(height, 0.0)


func _ground(at: Vector2) -> float:
	return _terrain.height_at(at.x, at.y) if _terrain != null else 0.0


## Una faceta de sombreado plano. La cara frontal en Godot es la HORARIA
## vista de frente, así que una faceta vista desde arriba tiene su normal de
## mano derecha hacia ABAJO: la misma regla que el suelo del Terrain.
## `height_sum` es la suma de las alturas de las tres esquinas sobre el suelo.
func _emit(v0: Vector3, v1: Vector3, v2: Vector3, height_sum: float, key: int) -> void:
	var cross := (v1 - v0).cross(v2 - v0)
	if cross.y > 0.0:
		var swap := v1
		v1 = v2
		v2 = swap
		cross = -cross
	var normal := (-cross).normalized()
	var tint := _facet_color(normal, maxf(height_sum / 3.0, 0.0), key)
	for vertex: Vector3 in [v0, v1, v2]:
		_vertices.append(vertex)
		_normals.append(normal)
		_colors.append(tint)
	face_count += 1


## Roca en las caras, tinte de cima en las partes suaves, caras empinadas
## más oscuras que las suaves, más oscuro al pie, bandas por altura y grano
## por faceta. El sombreado por pendiente va HORNEADO a propósito: con el
## cielo claro y la niebla de las arenas el sol solo apenas separa un
## acantilado de una cresta, y la roca se leería como una maqueta de papel.
func _facet_color(normal: Vector3, height: float, key: int) -> Color:
	var cap := smoothstep(CAP_FROM, CAP_TO, normal.y) * style.cap_strength
	var base := style.rock_color.lerp(style.cap_color, cap)
	var slope := lerpf(1.1, STEEP_SHADE, smoothstep(0.35, 0.95, 1.0 - normal.y))
	var foot := lerpf(FOOT_SHADE, 1.0, clampf(height / FOOT_HEIGHT, 0.0, 1.0))
	var band := 1.0 + style.strata_strength * sin(height * STRATA_FREQUENCY)
	var grain := 1.0 + (_hash01(key, 7, _seed) - 0.5) * 2.0 * GRAIN
	var value := slope * foot * band * grain
	return Color(base.r * value, base.g * value, base.b * value, 1.0)


## Hash determinista de dos enteros y una sal a [0, 1]: el jitter de
## vértices y el grano de facetas no deben sacar números de ningún RNG, o dos
## construcciones con la misma semilla no coincidirían.
static func _hash01(x: int, z: int, salt: int) -> float:
	var h := (x * 374761393 + z * 668265263 + salt * 1442695041) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	h = h ^ (h >> 16)
	return float(h & 0xffff) / 65535.0
