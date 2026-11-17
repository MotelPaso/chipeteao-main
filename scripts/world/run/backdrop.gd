extends Node3D
## Fondo de la arena: rodea el suelo jugable con decorado lejano y barato
## que la niebla del entorno funde con el horizonte, para que la arena no
## parezca una isla flotando en el cielo:
##
## - Un disco de suelo enorme y plano, apenas bajo la hondonada más honda,
##   con el tinte del bioma: más allá de los muros "la tierra sigue". En una
##   arena con relieve por zonas (Terrain.has_relief) el disco pasa a ser un
##   MARCO alrededor de la arena, al nivel de su borde: un plano entero bajo
##   el fondo del cañón dejaría un escalón de metros en el borde, y a
##   nivel del borde taparía el cañón.
## - Dos anillos de colinas de silueta (esferas aplastadas) fuera del
##   perímetro, más oscuras con la distancia, para que el horizonte tenga
##   forma y no una costura recta.
## - Opcional (peak_count): una cordillera de picos facetados más lejos y
##   mucho más altos que las colinas, que asoma sobre los árboles. Es una
##   sola malla con color de vértice y su propio RNG (la semilla del
##   scatter): no saca nada del RNG de la partida.
##
## Todo se construye en código en _ready (sin colisión, un material por
## anillo), con colores por export para que cada bioma tiña su mundo.
## Las colinas sacan números del RNG global de la partida (ver _build_hill_ring).

@export_group("Suelo lejano")
## Color del disco de suelo lejano. También tiñe el minimapa (el Terrain lo
## lee por su backdrop_path).
@export var ground_color: Color = Color(0.22, 0.33, 0.2)
## Lado del disco de suelo lejano, en metros.
@export var ground_size: float = 1000.0
## Metros bajo la hondonada más honda del terreno donde queda el disco, para
## que los bordes nunca parpadeen (z-fighting).
@export var ground_drop: float = 0.35
## Con relieve por zonas: metros bajo el borde de la arena donde queda el
## marco de suelo lejano, y metros que se mete bajo ese borde para no dejar
## una rendija.
@export var rim_drop: float = 0.05
@export var rim_overlap: float = 0.5

@export_group("Colinas del horizonte")
## Color de las colinas del anillo cercano.
@export var hill_color: Color = Color(0.16, 0.26, 0.17)
## Color del anillo lejano: más hondo en la niebla y un tono más oscuro.
@export var far_hill_color: Color = Color(0.13, 0.21, 0.15)
# Franjas de los anillos: MÚLTIPLOS de la mitad del lado de la arena, que
# el scatter publica por el grupo "arena_bounds" (la fuente única del tamaño
# de arena), así un cambio de tamaño no mete colinas en el campo. Cambiar la
# cantidad de colinas mueve los POIs de la partida con la misma semilla (ver
# _build_hill_ring).
## Colinas del anillo cercano (cambiarlo mueve los POIs de la misma semilla).
@export var hill_count: int = 22
## Colinas del anillo lejano (cambiarlo mueve los POIs de la misma semilla).
@export var far_hill_count: int = 14
## Borde interior del anillo cercano, en mitades del lado de la arena.
@export var near_ring_min_factor: float = 1.6
## Borde exterior del anillo cercano, en mitades del lado de la arena.
@export var near_ring_max_factor: float = 2.1
## Borde interior del anillo lejano, en mitades del lado de la arena.
@export var far_ring_min_factor: float = 2.6
## Borde exterior del anillo lejano, en mitades del lado de la arena.
@export var far_ring_max_factor: float = 3.4
## Altura visible mínima de una colina, en metros.
@export var hill_height_min: float = 6.0
## Altura visible máxima de una colina, en metros; cada arena pone la suya en la escena (el valor por defecto es el del bosque).
@export var hill_height_max: float = 20.0
## Media anchura mínima de una colina, en metros.
@export var hill_width_min: float = 18.0
## Media anchura máxima de una colina, en metros.
@export var hill_width_max: float = 46.0
## Profundidad mínima de una colina, como fracción de su media anchura (0-1).
@export var hill_depth_ratio_min: float = 0.7
## Profundidad máxima de una colina, como fracción de su media anchura (0-1).
@export var hill_depth_ratio_max: float = 1.0
## Desvío al azar del ángulo de cada colina en su anillo, en radianes.
@export var hill_angle_jitter: float = 0.12
## Multiplicador de tamaño de las colinas lejanas, para que se lean a
## través de la niebla.
@export var far_hill_scale_boost: float = 1.6
## Metros extra que una colina guarda entre su borde y el muro de la arena.
@export var wall_clearance: float = 4.0

@export_group("Cordillera")
## Picos de la cordillera del horizonte (0 = sin cordillera). Cada arena pone
## el suyo en su escena.
@export var peak_count: int = 0
## Color de la falda de los picos.
@export var peak_base_color: Color = Color(0.15, 0.23, 0.22)
## Color de las cumbres (la niebla las aclara todavía más).
@export var peak_top_color: Color = Color(0.56, 0.63, 0.64)
## Borde interior del anillo de picos, en mitades del lado de la arena.
@export var peak_ring_min_factor: float = 2.1
## Borde exterior del anillo de picos, en mitades del lado de la arena.
@export var peak_ring_max_factor: float = 3.0
## Altura mínima de un pico, en metros.
@export var peak_height_min: float = 55.0
## Altura máxima de un pico, en metros.
@export var peak_height_max: float = 130.0
## Media anchura mínima de la falda de un pico, en metros.
@export var peak_width_min: float = 45.0
## Media anchura máxima de la falda de un pico, en metros.
@export var peak_width_max: float = 85.0
## Lados de la falda de cada pico: pocos = picos más angulosos.
@export_range(4, 10) var peak_sides: int = 6

## Mitad del lado de la arena; 80 solo si no hay scatter.
var _half_extent: float = 80.0


func _ready() -> void:
	_half_extent = _arena_half_extent()
	var terrain := Terrain.find(get_tree())
	if terrain != null:
		terrain.ensure_built()
	if terrain != null and terrain.has_relief():
		_build_ground_frame()
	else:
		_build_ground(_ground_depth())
	_build_hill_ring(hill_count, near_ring_min_factor, near_ring_max_factor,
			_hill_material(hill_color))
	_build_hill_ring(far_hill_count, far_ring_min_factor, far_ring_max_factor,
			_hill_material(far_hill_color), far_hill_scale_boost)
	if peak_count > 0:
		_build_peaks()


## Mitad del lado de la arena desde el nodo "arena_bounds" (el scatter),
## como la leen BossBase y EnemySpawner. Todos los hermanos ya entraron a sus
## grupos: los grupos se toman en _enter_tree, que corre para toda la escena
## antes de cualquier _ready.
func _arena_half_extent() -> float:
	var bounds := get_tree().get_first_node_in_group("arena_bounds")
	if bounds == null:
		return _half_extent
	var value: Variant = bounds.get("arena_half_extent")
	return float(value) if value != null else _half_extent


## Profundidad en metros del disco lejano: ground_drop bajo la hondonada
## MÁS honda. Llama a Terrain.ensure_built() explícitamente: este nodo es el
## hijo #2 de la arena y su _ready corre mucho antes que el del terreno, así
## que min_height seguiría en 0.
func _ground_depth() -> float:
	var terrain := Terrain.find(get_tree())
	if terrain == null:
		return ground_drop
	terrain.ensure_built()
	return -terrain.min_height + ground_drop


func _build_ground(depth: float) -> void:
	var ground := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(ground_size, ground_size)
	ground.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = ground_color
	material.roughness = 1.0
	ground.material_override = material
	ground.position.y = -depth
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)


## El suelo lejano como un marco de cuatro planos alrededor de la arena, a
## rim_drop bajo su borde (que el Terrain deja a 0). PlaneMesh a propósito:
## HellSky reconoce el suelo lejano por ese tipo de malla al teñirlo.
func _build_ground_frame() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = ground_color
	material.roughness = 1.0
	var inner := _half_extent - rim_overlap
	var outer := maxf(ground_size * 0.5, inner + 1.0)
	var band := outer - inner
	var middle := (outer + inner) * 0.5
	# Norte y sur de lado a lado; este y oeste, lo que queda entre los dos.
	var pieces: Array[Rect2] = [
		Rect2(0.0, -middle, outer * 2.0, band), Rect2(0.0, middle, outer * 2.0, band),
		Rect2(-middle, 0.0, band, inner * 2.0), Rect2(middle, 0.0, band, inner * 2.0),
	]
	for piece: Rect2 in pieces:
		var ground := MeshInstance3D.new()
		var mesh := PlaneMesh.new()
		mesh.size = piece.size
		ground.mesh = mesh
		ground.material_override = material
		ground.position = Vector3(piece.position.x, -rim_drop, piece.position.y)
		ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ground)


## Un anillo de colinas (esferas aplastadas) de tamaño aleatorio entre los
## radios, dados como múltiplos de la mitad del lado de la arena. scale_boost
## agranda el anillo lejano para que se lea a través de la niebla.
## Usa el RNG GLOBAL de la partida y corre antes de que el WorldDirector
## baraje los POIs: cambiar hill_count o far_hill_count cambia cuántos
## números se sacan y, con la misma semilla, mueve todos los POIs. No
## agregues, quites ni reordenes sorteos aquí.
func _build_hill_ring(count: int, min_factor: float, max_factor: float,
		material: StandardMaterial3D, scale_boost: float = 1.0) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	for i in count:
		var hill := MeshInstance3D.new()
		hill.mesh = mesh
		hill.material_override = material
		hill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var angle := TAU * float(i) / float(count) + randf_range(-hill_angle_jitter, hill_angle_jitter)
		var width := randf_range(hill_width_min, hill_width_max) * scale_boost
		var height := randf_range(hill_height_min, hill_height_max) * scale_boost
		var depth := width * randf_range(hill_depth_ratio_min, hill_depth_ratio_max)
		var distance := maxf(randf_range(min_factor, max_factor) * _half_extent,
				_clear_distance(angle, width, depth))
		hill.position = Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
		# Centro de la esfera a nivel del suelo: solo asoma la mitad de
		# arriba, así cada colina es una cúpula limpia sin panza visible.
		hill.scale = Vector3(width, height, depth)
		hill.rotation.y = randf() * TAU
		add_child(hill)


## Distancia mínima a lo largo de `angle` a la que una cúpula de estas
## medias anchuras queda entera fuera del cuadrado jugable. La escala se
## aplica a una esfera de RADIO 1, así que `width` es la media anchura de la
## cúpula en metros, no su diámetro.
func _clear_distance(angle: float, width: float, depth: float) -> float:
	var cos_a := absf(cos(angle))
	var sin_a := absf(sin(angle))
	var limit := _half_extent + wall_clearance
	# Basta con salir por UN eje para que la caja de la cúpula quede fuera
	# del cuadrado, así gana el más barato de los dos.
	var by_x := (limit + width) / cos_a if cos_a > 0.001 else INF
	var by_z := (limit + depth) / sin_a if sin_a > 0.001 else INF
	return minf(by_x, by_z)


## La cordillera: peak_count picos en un anillo lejano, cada uno una pirámide
## irregular con un hombro al lado, todos en UNA malla. Blanco por color de
## vértice: HellSky tiñe el horizonte cambiando el albedo del material.
func _build_peaks() -> void:
	var rng := RandomNumberGenerator.new()
	var bounds := get_tree().get_first_node_in_group("arena_bounds")
	rng.seed = (int(bounds.call("run_seed")) if bounds != null and bounds.has_method("run_seed")
			else 0) ^ 0x5045414B
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for index in peak_count:
		var angle := TAU * (float(index) + rng.randf_range(-0.35, 0.35)) / float(peak_count)
		var distance := rng.randf_range(peak_ring_min_factor, peak_ring_max_factor) * _half_extent
		var center := Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
		var width := rng.randf_range(peak_width_min, peak_width_max)
		var height := rng.randf_range(peak_height_min, peak_height_max)
		_add_peak(rng, center, width, height, vertices, normals, colors)
		# El hombro: un pico más bajo pegado a un costado, para que la
		# silueta no sea una fila de conos.
		var side := angle + PI * 0.5 * (1.0 if rng.randf() < 0.5 else -1.0)
		_add_peak(rng, center + Vector3(cos(side), 0.0, sin(side)) * width * 0.75,
				width * rng.randf_range(0.55, 0.8), height * rng.randf_range(0.5, 0.75),
				vertices, normals, colors)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 1.0
	var range_view := MeshInstance3D.new()
	range_view.name = "Peaks"
	range_view.mesh = mesh
	range_view.material_override = material
	range_view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(range_view)


## Un pico: una pirámide de peak_sides lados con la falda irregular y la
## cumbre corrida del centro. Caras planas, horarias vistas desde fuera.
func _add_peak(rng: RandomNumberGenerator, center: Vector3, width: float, height: float,
		vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray) -> void:
	var apex := center + Vector3(rng.randf_range(-0.2, 0.2) * width, height,
			rng.randf_range(-0.2, 0.2) * width)
	var turn := rng.randf() * TAU
	var rim := PackedVector3Array()
	for side in peak_sides:
		var angle := turn + TAU * float(side) / float(peak_sides)
		var reach := width * rng.randf_range(0.75, 1.25)
		# La falda baja unos metros del suelo lejano: nunca asoma su borde.
		rim.append(center + Vector3(cos(angle) * reach, -4.0, sin(angle) * reach))
	for side in peak_sides:
		var a := rim[side]
		var b := rim[(side + 1) % peak_sides]
		var outward := ((a + b) * 0.5 - center)
		outward.y = 0.0
		var normal := (b - apex).cross(a - apex).normalized()
		var first := b
		var second := a
		if normal.dot(outward) < 0.0:
			normal = -normal
			first = a
			second = b
		# Horario visto desde fuera: cross(v1 - v0, v2 - v0) mira hacia dentro.
		for vertex: Vector3 in [apex, second, first]:
			vertices.append(vertex)
			normals.append(normal)
		# Cada cara con un brillo algo distinto, para que se lean las aristas.
		var shade := rng.randf_range(0.86, 1.1)
		colors.append(peak_top_color * shade)
		colors.append(peak_base_color * shade)
		colors.append(peak_base_color * shade)


func _hill_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material
