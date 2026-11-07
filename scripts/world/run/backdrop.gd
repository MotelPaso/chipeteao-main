extends Node3D
## Fondo de la arena: rodea el suelo jugable con decorado lejano y barato
## que la niebla del entorno funde con el horizonte, para que la arena no
## parezca una isla flotando en el cielo:
##
## - Un disco de suelo enorme y plano, apenas bajo la hondonada más honda,
##   con el tinte del bioma: más allá de los muros "la tierra sigue".
## - Dos anillos de colinas de silueta (esferas aplastadas) fuera del
##   perímetro, más oscuras con la distancia, para que el horizonte tenga
##   forma y no una costura recta.
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

@export_group("Colinas del horizonte")
## Color de las colinas del anillo cercano.
@export var hill_color: Color = Color(0.16, 0.26, 0.17)
## Color del anillo lejano: más hondo en la niebla y un tono más oscuro.
@export var far_hill_color: Color = Color(0.13, 0.21, 0.15)
## Colinas del anillo cercano y del lejano. Cambiar la cantidad mueve los
## POIs de la partida con la misma semilla (ver _build_hill_ring).
@export var hill_count: int = 22
@export var far_hill_count: int = 14
## Franjas de los anillos como MÚLTIPLOS de la mitad del lado de la arena,
## que el scatter publica por el grupo "arena_bounds" (la fuente única del
## tamaño de arena): así un cambio de tamaño no mete colinas en el campo.
@export var near_ring_min_factor: float = 1.6
@export var near_ring_max_factor: float = 2.1
@export var far_ring_min_factor: float = 2.6
@export var far_ring_max_factor: float = 3.4
## Rango de altura visible de una colina, en metros. Cada arena pone su
## máximo en la escena; el valor por defecto es el del bosque.
@export var hill_height_min: float = 6.0
@export var hill_height_max: float = 20.0
## Rango de media anchura de una colina, en metros.
@export var hill_width_min: float = 18.0
@export var hill_width_max: float = 46.0
## Profundidad de una colina como fracción de su media anchura (rango).
@export var hill_depth_ratio_min: float = 0.7
@export var hill_depth_ratio_max: float = 1.0
## Desvío al azar del ángulo de cada colina en su anillo, en radianes.
@export var hill_angle_jitter: float = 0.12
## Multiplicador de tamaño de las colinas lejanas, para que se lean a
## través de la niebla.
@export var far_hill_scale_boost: float = 1.6
## Metros extra que una colina guarda entre su borde y el muro de la arena.
@export var wall_clearance: float = 4.0

## Mitad del lado de la arena; 80 solo si no hay scatter.
var _half_extent: float = 80.0


func _ready() -> void:
	_half_extent = _arena_half_extent()
	_build_ground(_ground_depth())
	_build_hill_ring(hill_count, near_ring_min_factor, near_ring_max_factor,
			_hill_material(hill_color))
	_build_hill_ring(far_hill_count, far_ring_min_factor, far_ring_max_factor,
			_hill_material(far_hill_color), far_hill_scale_boost)


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


func _hill_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material
