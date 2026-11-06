class_name Terrain
extends StaticBody3D
## El suelo de una arena: un heightmap suave de baja amplitud (lomas que se
## caminan, hondonadas a las que se baja) más los claros planos donde se
## apoyan los grupos de verticalidad de autor y las mesetas.
##
## Relieve BAJO a propósito: la horda no tiene navmesh, persigue en línea
## recta y trepa lo que la bloquea, así que un terreno que esconda a un
## raider o corte una persecución rompería el juego. La amplitud es de
## 1.5-3.0 m según el bioma; el relieve da lectura (sabes dónde estás) y silueta.
##
## Se siembra con la semilla de partida del SCATTER (`run_seed()`, válida
## desde su _enter_tree), así BONK_SEED, BONK_GAME_SEED y la Cacería diaria
## reproducen el mismo relieve que los props que tiene encima.
##
## Ciclo de vida: se construye en _ready, que corre ANTES de Arena._ready
## (hijos primero) y DESPUÉS del _enter_tree del scatter, así la máscara y
## los sitios de meseta ya existen. Quien pueda correr su _ready antes
## (Backdrop es el hijo #2) llama primero a ensure_built(), que es idempotente.
##
## Regla del null: quien consulta desde on_stage_started en adelante trata
## un find() nulo como un push_error único (el terreno ya debería existir);
## quien consulta al construirse (Backdrop, HUD, el mapa) lo tolera en
## silencio y se (re)construye cuando empieza la etapa.
##
## LA regla de colocación del proyecto: nada va a y = 0. Toda colocación en
## el mundo pasa por height_at().

@export var size: float = 240.0
## Escala del ruido de cima a fondo, en metros, por bioma (bosque 2.5,
## dunas 3.0, ciénaga 1.5). Cada escena de arena pone la suya.
@export var amplitude: float = 2.5
## Longitud de onda del rasgo principal del ruido, en metros: cuán
## separadas están las lomas. Más grande = relieve más ancho y suave.
@export var feature_size: float = 45.0
@export var octaves: int = 3
## Paso en metros de la retícula donde se muestrea el ruido, que luego se
## interpola a la cuadrícula del colisionador. Muestrear los 241x241 puntos
## con FastNoiseLite desde GDScript es el costo dominante del nodo; a 2 m
## cuesta un cuarto y a esta amplitud no se nota la diferencia.
@export var noise_step: float = 2.0
## Radio en metros del disco plano bajo el spawn del equipo, para que nadie caiga en una pendiente.
@export var spawn_flat_radius: float = 14.0
## Radio en metros del claro plano bajo cada grupo de verticalidad de
## autor y cada meseta: una rampa tiene que tocar suelo parejo o flota en un extremo.
@export var pad_radius: float = 8.0
## El ruido baja a cero dentro de estos metros desde el borde, para que
## los muros del perímetro y el disco del backdrop encuentren un borde plano.
@export var rim_flat_band: float = 10.0
## Paso en metros de la malla de render. Más grueso que el colisionador a
## propósito: a esta amplitud la silueta es igual con un cuarto de triángulos.
@export var mesh_step: float = 2.0
## Material del suelo del bioma. Los shaders de suelo leen el XZ de MUNDO,
## y la malla lleva UVs en XZ de mundo.
@export var surface_material: Material

## HeightMapShape3D va fijo a UNA UNIDAD DE MUNDO POR MUESTRA y el nodo no
## se escala, así que la cuadrícula del colisionador es de 1 m y esto no se ajusta.
const SAMPLE_METERS: float = 1.0
## Franja de mezcla en metros alrededor de un claro: el claro es plano
## dentro de su radio y vuelve al ruido en esta franja.
const PAD_BLEND: float = 6.0
## Sin uso: map_image() reparte el sombreado entre min_height y max_height.
const MAP_SHADE_RANGE: float = 6.0

## Muestras del colisionador por lado (241 para una arena de 240 m a 1 m).
var _samples: int = 0
var _heights: PackedFloat32Array = PackedFloat32Array()
var min_height: float = 0.0
var max_height: float = 0.0
var _built: bool = false
## Discos planos aplicados tras el ruido: {center, radius}. Vienen del
## spawn, de los keepouts de autor y de los sitios de meseta del scatter.
var _pads: Array[Dictionary] = []
var _mesh_instance: MeshInstance3D = null
var _collision: CollisionShape3D = null


## EL acceso. Nunca por ruta de nodo: la arena cambia en cada etapa.
static func find(tree: SceneTree) -> Terrain:
	if tree == null:
		return null
	return tree.get_first_node_in_group(&"terrain") as Terrain


func _enter_tree() -> void:
	# Se une aquí y no en _ready: quien llama a ensure_built() desde su propio
	# _ready tiene que poder ENCONTRAR este nodo antes.
	add_to_group(&"terrain")


func _ready() -> void:
	ensure_built()


## Construye el terreno una sola vez. Público e idempotente porque ningún
## consumidor puede suponer el orden de construcción de la escena: Backdrop
## es el hijo #2 y lee min_height en su propio _ready.
func ensure_built() -> void:
	if _built:
		return
	_built = true
	var started := Time.get_ticks_msec()
	_samples = int(round(size / SAMPLE_METERS)) + 1
	_collect_pads()
	_build_heights()
	_build_mesh()
	_build_collider()
	# Log de una línea para los soaks headless: sin él, un terreno que salió
	# plano por error se vería igual que uno sano.
	print("Terrain built: %s samples=%dx%d mesh_step=%.0f min=%.1f max=%.1f in %d ms" % [
			_biome_name(), _samples, _samples, mesh_step, min_height, max_height,
			Time.get_ticks_msec() - started])


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
	var h00 := _heights[iz * _samples + ix]
	var h10 := _heights[iz * _samples + nx]
	var h01 := _heights[nz * _samples + ix]
	var h11 := _heights[nz * _samples + nx]
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
			var tint := base.lerp(base.lightened(0.45), shade)
			tint = tint.darkened(0.35 * (1.0 - shade))
			image.set_pixel(px, py, tint)
	return image


## Registra un claro plano más. Sin uso: _collect_pads() lee los sitios de
## meseta del scatter por su cuenta.
func add_pad(center_xz: Vector2, radius: float) -> void:
	_pads.append({"center": center_xz, "radius": radius})


## --- construcción --------------------------------------------------------

## El disco del spawn, un claro por grupo de verticalidad de autor y uno por
## sitio de meseta. NO los POIs barajables: el WorldDirector los mueve a otro
## XZ después de construir esto, así que un claro en su lugar de autor sería
## suelo plano en el sitio equivocado; ellos se ajustan al relieve
## (world_director._shuffle_ground_interactables).
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


## Aplana `h` hacia 0 dentro de un claro y vuelve al ruido en PAD_BLEND.
## Gana el claro más fuerte, así dos claros superpuestos no se suman.
func _apply_pads(x: float, z: float, h: float) -> float:
	var flat := 0.0
	for pad: Dictionary in _pads:
		var center: Vector2 = pad["center"]
		var radius: float = pad["radius"]
		var distance := Vector2(x, z).distance_to(center)
		if distance >= radius + PAD_BLEND:
			continue
		var strength := 1.0 if distance <= radius \
				else 1.0 - smoothstep(0.0, 1.0, (distance - radius) / PAD_BLEND)
		flat = maxf(flat, strength)
	return lerpf(h, 0.0, flat)


## Malla de render desde arreglos empaquetados: SurfaceTool sobre una
## cuadrícula de este tamaño son cientos de miles de llamadas de GDScript y
## tarda segundos; esto es una sola add_surface_from_arrays.
func _build_mesh() -> void:
	var cells := maxi(int(round(size / maxf(mesh_step, 0.5))), 2)
	var verts := cells + 1
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize(verts * verts)
	normals.resize(verts * verts)
	uvs.resize(verts * verts)
	var half := size * 0.5
	for iz in verts:
		var z := -half + float(iz) * mesh_step
		for ix in verts:
			var x := -half + float(ix) * mesh_step
			var index := iz * verts + ix
			vertices[index] = Vector3(x, height_at(x, z), z)
			# Normal analítica desde las diferencias de altura a cada lado:
			# diferencia central sobre un paso de malla, la misma pendiente
			# que tiene el colisionador.
			var dx := height_at(x + mesh_step, z) - height_at(x - mesh_step, z)
			var dz := height_at(x, z + mesh_step) - height_at(x, z - mesh_step)
			normals[index] = Vector3(-dx, 2.0 * mesh_step, -dz).normalized()
			# UVs en XZ de mundo: los shaders de suelo del bioma leen la
			# posición de mundo.
			uvs[index] = Vector2(x, z)
	var indices := PackedInt32Array()
	indices.resize(cells * cells * 6)
	var cursor := 0
	# ORIENTACIÓN. La cara frontal en Godot es la HORARIA vista de frente,
	# así que un suelo para caminar debe ser horario visto desde +Y, o sea
	# cross(v1 - v0, v2 - v0) apunta hacia ABAJO. Al revés, todo el terreno
	# se descarta por cara trasera desde cualquier cámara de arriba y ningún
	# log lo dice: los soaks corren headless y no rasterizan nada.
	# _assert_winding hace que ese error falle un soak headless.
	for iz in cells:
		for ix in cells:
			var top_left := iz * verts + ix
			var top_right := top_left + 1
			var bottom_left := top_left + verts
			var bottom_right := bottom_left + 1
			indices[cursor] = top_left
			indices[cursor + 1] = top_right
			indices[cursor + 2] = bottom_left
			indices[cursor + 3] = top_right
			indices[cursor + 4] = bottom_right
			indices[cursor + 5] = bottom_left
			cursor += 6
	_assert_winding(vertices, indices)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
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


## Comprueba hacia dónde miran los triángulos, lo único de esta malla que
## un soak headless no ve. Revisa solo el PRIMER triángulo: todas las celdas
## salen de las mismas tres líneas, así que si uno está al revés lo están todos.
##
## `up` es la normal de MANO DERECHA del triángulo tal como está listado.
## Godot descarta el lado antihorario, así que una cara visible desde arriba
## lista sus vértices en sentido horario visto desde +Y y su normal de mano
## derecha apunta ABAJO. Una Y positiva es el error.
func _assert_winding(vertices: PackedVector3Array, indices: PackedInt32Array) -> void:
	if indices.size() < 3:
		return
	var v0 := vertices[indices[0]]
	var v1 := vertices[indices[1]]
	var v2 := vertices[indices[2]]
	var up := (v1 - v0).cross(v2 - v0)
	if up.y >= 0.0:
		push_error("Terrain: ground triangles wound the wrong way — "
				+ "the whole surface is back-face culled from above")


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


## La semilla de partida del scatter, para que el relieve coincida con los
## props bajo BONK_SEED, BONK_GAME_SEED o la Cacería diaria. Sin scatter usa
## un número fijo y no uno al azar: un terreno que cambiara entre dos
## corridas iguales arruinaría toda comparación de soaks.
func _run_seed() -> int:
	var bounds := get_tree().get_first_node_in_group(&"arena_bounds")
	if bounds != null and bounds.has_method(&"run_seed"):
		return int(bounds.call(&"run_seed"))
	return 0


## Tinte del suelo para map_image(), tomado del ground_color del nodo
## hermano llamado "Backdrop" para que el mapa se lea como el mismo lugar.
## Sin él, un gris pizarra neutro.
func _biome_tint() -> Color:
	var backdrop := _find_backdrop()
	if backdrop != null:
		var value: Variant = backdrop.get("ground_color")
		if value is Color:
			return value
	return Color(0.25, 0.27, 0.3)


func _find_backdrop() -> Node:
	var arena := _own_arena()
	return arena.get_node_or_null("Backdrop") if arena != null else null


## Nombre de la arena de este terreno, para el log de construcción.
func _biome_name() -> String:
	var arena := _own_arena() as Arena
	return arena.map_id if arena != null else name
