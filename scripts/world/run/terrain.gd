class_name Terrain
extends StaticBody3D
## El suelo de una arena. Dos formas, según el export `relief`:
##
## - Sin `relief` (Dunas de Ceniza, Ciénaga Lóbrega): un heightmap suave de
##   baja amplitud (lomas que se caminan, hondonadas a las que se baja) más
##   los claros planos donde se apoyan los grupos de verticalidad de autor y
##   las mesetas. La amplitud es de 1.5-3.0 m según el bioma.
## - Con `relief` (Bosque Hueco): RELIEVE POR ZONAS. Sobre ese mismo suelo
##   suave va una montaña escalonada (un macizo, un segundo nivel y una
##   cumbre, apilados), un cañón con sus puentes, cerros sueltos y las
##   rampas que entran a cada zona. La altura va en los cortes y en las
##   pendientes largas; dentro de cada zona el suelo sigue igual de suave.
##
## La regla que el relieve por zonas no puede romper: la horda no tiene
## navmesh, persigue en línea recta y trepa lo que la bloquea. Por eso todo
## corte mide menos de lo que un enemigo trepa de una vez, toda cara es
## claramente caminable o claramente pared (nunca entre 45 y 60 grados), y a
## toda zona se entra caminando por alguna rampa. El trazado lo sortea
## ReliefPlanner y vive en scripts/world/run/terrain/.
##
## Se siembra con la semilla de partida del SCATTER (`run_seed()`, válida
## desde su _enter_tree), así BONK_GAME_SEED y la Cacería diaria
## reproducen el mismo relieve que los props que tiene encima.
##
## Ciclo de vida: se construye en _ready, que corre ANTES de Arena._ready
## (hijos primero) y DESPUÉS del _enter_tree del scatter, así la máscara y
## los sitios de meseta ya existen. Quien pueda correr su _ready antes
## (Backdrop es el hijo #2) llama primero a ensure_built(), que es idempotente.
## El trazado del relieve por zonas se decide ANTES que la máscara: el
## scatter llama a plan_relief() en su _enter_tree.
##
## Regla del null: quien consulta desde on_stage_started en adelante trata
## un find() nulo como un push_error único (el terreno ya debería existir);
## quien consulta al construirse (Backdrop, HUD, el mapa) lo tolera en
## silencio y se (re)construye cuando empieza la etapa.
##
## LA regla de colocación del proyecto: nada va a y = 0. Toda colocación en
## el mundo pasa por height_at(), que responde la superficie DONDE SE PISA
## (cornisas de roca incluidas). Y nada se coloca sobre un corte, una rampa o
## un puente: eso se pregunta con arena_bounds.can_place().

## Lado del terreno en metros cuando no hay scatter en la escena (una escena
## de prueba); en una arena el lado sale de arena_half_extent del scatter.
const FALLBACK_SIZE: float = 240.0
## HeightMapShape3D va fijo a UNA UNIDAD DE MUNDO POR MUESTRA y el nodo no
## se escala, así que la cuadrícula del colisionador es de 1 m y esto no se ajusta.
const SAMPLE_METERS: float = 1.0
## Tinte del minimapa cuando no se encuentra el nodo de backdrop_path.
const FALLBACK_MAP_TINT := Color(0.25, 0.27, 0.3)

@export_group("Relieve")
## Escala del ruido de cima a fondo, en metros, por bioma (bosque 2.5,
## dunas 3.0, ciénaga 1.5). Cada escena de arena pone la suya.
@export var amplitude: float = 2.5
## Longitud de onda del rasgo principal del ruido, en metros: cuán
## separadas están las lomas. Más grande = relieve más ancho y suave.
@export var feature_size: float = 45.0
## Octavas del ruido fractal: más octavas, más detalle chico sobre las lomas.
@export var octaves: int = 3
## Paso en metros de la retícula donde se muestrea el ruido, que luego se
## interpola a la cuadrícula del colisionador. Muestrear los 241x241 puntos
## con FastNoiseLite desde GDScript es el costo dominante del nodo; a 2 m
## cuesta un cuarto y a esta amplitud no se nota la diferencia.
@export var noise_step: float = 2.0
## Relieve por zonas de esta arena: zonas apiladas, cañón, rampas y puentes
## (un .tres de assets/world/, ver ReliefSettings). Vacío = el suelo suave de
## siempre. Con él, `amplitude` es la ondulación DENTRO de cada zona, y la
## malla va a 2 m con parches de 1 m junto a los cortes (mesh_step no se usa).
@export var relief: ReliefSettings

@export_group("Claros planos")
## Radio en metros del disco plano bajo el spawn del equipo, para que nadie caiga en una pendiente.
@export var spawn_flat_radius: float = 14.0
## Radio en metros del claro plano bajo cada grupo de verticalidad de
## autor y cada meseta: una rampa tiene que tocar suelo parejo o flota en un extremo.
@export var pad_radius: float = 8.0
## Franja de mezcla en metros alrededor de cada claro: el claro es plano
## dentro de su radio y vuelve al relieve en esta franja.
@export var pad_blend: float = 6.0
## El ruido baja a cero dentro de estos metros desde el borde, para que
## los muros del perímetro y el disco del backdrop encuentren un borde plano.
@export var rim_flat_band: float = 10.0

@export_group("Malla")
## Paso en metros de la malla de render. Más grueso que el colisionador a
## propósito: a esta amplitud la silueta es igual con un cuarto de triángulos.
@export var mesh_step: float = 2.0
## Material del suelo del bioma. Los shaders de suelo leen el XZ de MUNDO,
## y la malla lleva UVs en XZ de mundo.
@export var surface_material: Material

@export_group("Minimapa")
## Nodo cuyo ground_color tiñe el minimapa: el Backdrop de la arena. Si lo
## renombras o lo mueves, actualiza esta ruta; sin él, el mapa sale gris.
@export_node_path("Node3D") var backdrop_path: NodePath = ^"../Backdrop"
## Cuánto se aclaran las cimas en el minimapa (0-1).
@export_range(0.0, 1.0) var map_peak_lighten: float = 0.45
## Cuánto se oscurecen las hondonadas en el minimapa (0-1).
@export_range(0.0, 1.0) var map_hollow_darken: float = 0.35

## Lado del terreno en metros: el doble de arena_half_extent del scatter, que
## se lee al construir. Lo leen el mapa y TerrainShots.
var size: float = FALLBACK_SIZE
## Alturas mínima y máxima del suelo en metros, válidas tras ensure_built().
var min_height: float = 0.0
var max_height: float = 0.0

## Muestras del colisionador por lado (241 para una arena de 240 m a 1 m).
var _samples: int = 0
var _heights: PackedFloat32Array = PackedFloat32Array()
## Alturas donde se pisa, que es lo que responde height_at(). Sin relieve por
## zonas es el mismo arreglo que _heights; con él, _heights lleva el escalón
## de cada corte escondido bajo su cornisa de roca (ver ReliefField).
var _surface: PackedFloat32Array = PackedFloat32Array()
## Trazado y rejillas del relieve por zonas; null sin `relief`.
var _layout: ReliefLayout = null
var _field: ReliefField = null
var _built: bool = false
## Discos planos aplicados tras el ruido: {center, radius}. Vienen del
## spawn, de los keepouts de autor y de los sitios de meseta del scatter.
var _pads: Array[Dictionary] = []
var _mesh_instance: MeshInstance3D = null
var _collision: CollisionShape3D = null


func _enter_tree() -> void:
	# Se une aquí y no en _ready: quien llama a ensure_built() desde su propio
	# _ready tiene que poder ENCONTRAR este nodo antes.
	add_to_group(&"terrain")


func _ready() -> void:
	ensure_built()


## EL acceso. Nunca por ruta de nodo: la arena cambia en cada etapa.
static func find(tree: SceneTree) -> Terrain:
	if tree == null:
		return null
	return tree.get_first_node_in_group(&"terrain") as Terrain


## Construye el terreno una sola vez. Público e idempotente porque ningún
## consumidor puede suponer el orden de construcción de la escena: Backdrop
## es el hijo #2 y lee min_height en su propio _ready.
func ensure_built() -> void:
	if _built:
		return
	_built = true
	var started := Time.get_ticks_msec()
	size = _arena_size()
	_samples = int(round(size / SAMPLE_METERS)) + 1
	plan_relief(_run_seed(), size * 0.5)
	_collect_pads()
	if _layout != null:
		_build_relief()
	else:
		_build_heights()
		_surface = _heights
	_build_mesh()
	_build_collider()
	# Log de una línea para los soaks headless: sin él, un terreno que salió
	# plano por error se vería igual que uno sano.
	print("Terrain built: %s samples=%dx%d mesh_step=%.0f min=%.1f max=%.1f in %d ms" % [
			_biome_name(), _samples, _samples, mesh_step, min_height, max_height,
			Time.get_ticks_msec() - started])
	if _layout != null:
		print(ReliefQueries.summary(_layout, _biome_name()))


## Decide el trazado del relieve por zonas de la etapa; null (y no hace nada)
## si la arena no tiene `relief`. Idempotente. Es puro cálculo y no necesita
## el árbol: el scatter lo llama en su _enter_tree, antes de armar su máscara
## y elegir sus mesetas, cuando este nodo todavía no entró.
func plan_relief(run_seed: int, half_extent: float) -> ReliefLayout:
	if relief != null and _layout == null:
		_layout = ReliefPlanner.plan(relief, run_seed, half_extent)
	return _layout


## El trazado del relieve por zonas, o null si la arena no lo tiene.
func relief_layout() -> ReliefLayout:
	return _layout


## True si esta arena tiene relieve por zonas (cortes, rampas, puente).
func has_relief() -> bool:
	return _layout != null


## Metros de `xz` al corte, rampa o puente más cercano (0 encima de uno);
## INF sin relieve por zonas o si no hay nada dentro de `limit` metros.
func relief_distance(xz: Vector2, limit: float) -> float:
	return ReliefQueries.distance(_layout, xz, limit) if _layout != null else INF


## LA consulta de solo lectura del relieve de la etapa: cruces, cortes,
## fondos, rampas y sitios planos donde cabe una estructura. Vacío sin
## relieve por zonas. El formato está en ReliefQueries.features().
func relief_features() -> Dictionary:
	if _layout == null:
		return {}
	ensure_built()
	return ReliefQueries.features(_layout, self)


## Altura del suelo SIN zonas en un XZ: lo que habría bajo una zona elevada
## o sobre el cañón. La usa la roca de los cortes para apoyar cada lado.
func base_height_at(x: float, z: float) -> float:
	return _field.base_at(x, z) if _field != null else height_at(x, z)


## Altura del suelo en un XZ de mundo, interpolada sobre la cuadrícula del
## colisionador: los mismos números del cuerpo físico, así un prop ajustado
## nunca flota ni se hunde.
func height_at(x: float, z: float) -> float:
	if not _built or _samples <= 1:
		return 0.0
	var half := size * 0.5
	var fx := clampf((x + half) / SAMPLE_METERS, 0.0, float(_samples - 1))
	var fz := clampf((z + half) / SAMPLE_METERS, 0.0, float(_samples - 1))
	var ix := int(fx)
	var iz := int(fz)
	var nx := mini(ix + 1, _samples - 1)
	var nz := mini(iz + 1, _samples - 1)
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var h00 := _surface[iz * _samples + ix]
	var h10 := _surface[iz * _samples + nx]
	var h01 := _surface[nz * _samples + ix]
	var h11 := _surface[nz * _samples + nx]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## Atajo para quien tiene una posición plana.
func height_at_xz(xz: Vector2) -> float:
	return height_at(xz.x, xz.y)


## `position` bajada al suelo.
func snap(position: Vector3) -> Vector3:
	return Vector3(position.x, height_at(position.x, position.z), position.z)


## Imagen cenital del relieve para el minimapa y el mapa: el tinte del
## bioma, sombreado por altura. `px_per_meter` suele ser bastante menor que 1
## (un mapa de 121 px para 240 m es 0.5).
func map_image(px_per_meter: float) -> Image:
	var pixels := maxi(int(round(size * px_per_meter)), 8)
	var image := Image.create_empty(pixels, pixels, false, Image.FORMAT_RGBA8)
	var base := _biome_tint()
	var span := maxf(max_height - min_height, 0.001)
	for py in pixels:
		var z := (float(py) + 0.5) / float(pixels) * size - size * 0.5
		for px in pixels:
			var x := (float(px) + 0.5) / float(pixels) * size - size * 0.5
			# Sombreado por altura: más oscuro en las hondonadas y más claro
			# en las cimas, para que el relieve se lea hasta en 121 px.
			var shade := clampf((height_at(x, z) - min_height) / span, 0.0, 1.0)
			var tint := base.lerp(base.lightened(map_peak_lighten), shade)
			tint = tint.darkened(map_hollow_darken * (1.0 - shade))
			image.set_pixel(px, py, tint)
	return image


## Lado de la arena en metros según el scatter (grupo "arena_bounds"): el
## doble de su arena_half_extent, la fuente única del tamaño.
func _arena_size() -> float:
	var bounds := get_tree().get_first_node_in_group(&"arena_bounds")
	if bounds != null:
		var value: Variant = bounds.get("arena_half_extent")
		if value != null:
			return float(value) * 2.0
	return FALLBACK_SIZE


## La semilla de partida del scatter, para que el relieve coincida con los
## props bajo BONK_GAME_SEED o la Cacería diaria. Sin scatter usa
## un número fijo y no uno al azar: un terreno que cambiara entre dos
## corridas iguales arruinaría toda comparación de soaks.
func _run_seed() -> int:
	var bounds := get_tree().get_first_node_in_group(&"arena_bounds")
	if bounds != null and bounds.has_method(&"run_seed"):
		return int(bounds.call(&"run_seed"))
	return 0


## El disco del spawn, un claro por grupo de verticalidad de autor y uno por
## sitio de meseta. NO los POIs barajables: el WorldDirector los mueve a otro
## XZ después de construir esto, así que un claro en su lugar de autor sería
## suelo plano en el sitio equivocado; ellos se ajustan al relieve
## (StageLayout.shuffle_ground_interactables).
func _collect_pads() -> void:
	_pads.append({"center": Vector2.ZERO, "radius": spawn_flat_radius})
	for node: Node in get_tree().get_nodes_in_group(&"scatter_keepout"):
		var spot := node as Node3D
		if spot == null or spot is Interactable:
			continue
		if not _in_same_arena(spot):
			continue
		# En el espacio de ESTE nodo, que es el de la cuadrícula de alturas:
		# un grupo de autor cuelga de Verticality, así que su propia
		# `position` no es relativa a la arena.
		var local := to_local(spot.global_position)
		_pads.append({"center": Vector2(local.x, local.z), "radius": pad_radius})
	# El scatter eligió sus sitios de meseta en _enter_tree, antes de esto.
	var bounds := get_tree().get_first_node_in_group(&"arena_bounds")
	if bounds != null and bounds.has_method(&"mesa_sites"):
		var sites: Variant = bounds.call(&"mesa_sites")
		if sites is PackedVector2Array:
			for site: Vector2 in sites:
				_pads.append({"center": site, "radius": pad_radius})


## True si `node` pertenece a la misma escena de arena que este terreno: un
## cambio de etapa puede dejar la arena saliente en el árbol un cuadro, y
## sus keepouts no son nuestros.
func _in_same_arena(node: Node) -> bool:
	var arena := _own_arena()
	return arena == null or arena.is_ancestor_of(node)


## La arena a la que pertenece este terreno. Se busca por TIPO y no por el
## grupo "arena_root": Arena entra a ese grupo en su _ready, que corre
## después del de este nodo (hijos primero), así que durante la
## construcción el grupo sigue vacío.
func _own_arena() -> Node:
	var node: Node = self
	while node != null and not (node is Arena):
		node = node.get_parent()
	return node


## Las alturas del relieve por zonas (ver ReliefField): los claros se aplanan
## al nivel de SU suelo, no a 0, y las zonas van encima.
func _build_relief() -> void:
	_field = ReliefField.new()
	_field.build(_layout, self, _run_seed(), _samples, _pads)
	_heights = _field.heights
	_surface = _field.surface
	min_height = _field.min_height
	max_height = _field.max_height


func _build_heights() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = _run_seed()
	noise.frequency = 1.0 / maxf(feature_size, 1.0)
	noise.fractal_octaves = maxi(octaves, 1)
	# Primero la retícula gruesa (ver noise_step), luego bilineal a 1 m.
	var lattice := maxi(int(ceil(size / maxf(noise_step, 0.5))) + 1, 2)
	var coarse := PackedFloat32Array()
	coarse.resize(lattice * lattice)
	var half := size * 0.5
	for lz in lattice:
		var z := -half + float(lz) * noise_step
		for lx in lattice:
			var x := -half + float(lx) * noise_step
			coarse[lz * lattice + lx] = noise.get_noise_2d(x, z) * amplitude
	_heights.resize(_samples * _samples)
	min_height = INF
	max_height = -INF
	for iz in _samples:
		var z := -half + float(iz) * SAMPLE_METERS
		for ix in _samples:
			var x := -half + float(ix) * SAMPLE_METERS
			var h := _sample_coarse(coarse, lattice, x, z)
			h *= _rim_falloff(x, z)
			h = _apply_pads(x, z, h)
			_heights[iz * _samples + ix] = h
			min_height = minf(min_height, h)
			max_height = maxf(max_height, h)
	if min_height == INF:
		min_height = 0.0
		max_height = 0.0


## Lectura bilineal de la retícula gruesa de ruido en un XZ de mundo.
func _sample_coarse(coarse: PackedFloat32Array, lattice: int, x: float, z: float) -> float:
	var half := size * 0.5
	var fx := clampf((x + half) / noise_step, 0.0, float(lattice - 1))
	var fz := clampf((z + half) / noise_step, 0.0, float(lattice - 1))
	var ix := int(fx)
	var iz := int(fz)
	var nx := mini(ix + 1, lattice - 1)
	var nz := mini(iz + 1, lattice - 1)
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var h00 := coarse[iz * lattice + ix]
	var h10 := coarse[iz * lattice + nx]
	var h01 := coarse[nz * lattice + ix]
	var h11 := coarse[nz * lattice + nx]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## 1 en el centro, bajando a 0 dentro de rim_flat_band del borde: los muros
## del perímetro son estáticos y el disco del backdrop es plano, así que el
## suelo tiene que ser plano donde se encuentran.
func _rim_falloff(x: float, z: float) -> float:
	var half := size * 0.5
	var edge := minf(half - absf(x), half - absf(z))
	if edge >= rim_flat_band:
		return 1.0
	return smoothstep(0.0, 1.0, maxf(edge, 0.0) / maxf(rim_flat_band, 0.001))


## Aplana `h` hacia 0 dentro de un claro y vuelve al ruido en pad_blend.
## Gana el claro más fuerte, así dos claros superpuestos no se suman.
func _apply_pads(x: float, z: float, h: float) -> float:
	var flat := 0.0
	for pad: Dictionary in _pads:
		var center: Vector2 = pad["center"]
		var radius: float = pad["radius"]
		var distance := Vector2(x, z).distance_to(center)
		if distance >= radius + pad_blend:
			continue
		var strength := 1.0 if distance <= radius \
				else 1.0 - smoothstep(0.0, 1.0, (distance - radius) / pad_blend)
		flat = maxf(flat, strength)
	return lerpf(h, 0.0, flat)


## Malla de render desde arreglos empaquetados (TerrainMesh): la cuadrícula
## de mesh_step metros, o la del relieve por zonas, con parches de 1 m junto
## a los cortes (ReliefMesh).
func _build_mesh() -> void:
	var arrays: Array
	if _field != null:
		arrays = ReliefMesh.arrays(_field, _samples, size)
	else:
		arrays = TerrainMesh.grid(self)
	TerrainMesh.assert_winding(arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_INDEX])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_instance = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "MeshInstance3D"
		add_child(_mesh_instance)
	_mesh_instance.mesh = mesh
	if surface_material != null:
		_mesh_instance.material_override = surface_material


## HeightMapShape3D en la capa 1, una muestra por unidad de mundo, nodo sin escalar.
func _build_collider() -> void:
	var shape := HeightMapShape3D.new()
	shape.map_width = _samples
	shape.map_depth = _samples
	shape.map_data = _heights
	_collision = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _collision == null:
		_collision = CollisionShape3D.new()
		_collision.name = "CollisionShape3D"
		add_child(_collision)
	_collision.shape = shape


## Tinte del suelo para map_image(): el ground_color del nodo de
## backdrop_path, para que el mapa se lea como el mismo lugar.
func _biome_tint() -> Color:
	var backdrop := get_node_or_null(backdrop_path) if not backdrop_path.is_empty() else null
	if backdrop != null:
		var value: Variant = backdrop.get("ground_color")
		if value is Color:
			return value
	return FALLBACK_MAP_TINT


## Nombre de la arena de este terreno, para el log de construcción.
func _biome_name() -> String:
	var arena := _own_arena() as Arena
	return arena.map_id if arena != null else name
