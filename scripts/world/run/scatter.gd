extends Node3D
## Reparto determinista de la arena: props interiores (árboles, rocas y
## tocones o sus equivalentes del bioma), una franja más densa en el borde
## para que el límite se lea como paisaje y no como vacío, mesetas, y la
## máscara de celdas caminables con sus formaciones de roca.
## Deja libre un radio alrededor del spawn (origen) y de cada nodo del grupo
## "scatter_keepout", y una distancia mínima entre props para que la horda
## (sin navmesh) siempre tenga pasillos anchos. Las copas no tienen
## colisión: solo bloquean troncos y rocas.

@export_group("Arena")
## Mitad del lado de la arena, en metros (el suelo es un cuadrado de 2x
## esto). Fuente única del tamaño: de aquí salen la máscara, las mesetas, el
## reparto, el borde, el Terrain y el Backdrop, y lo leen por el grupo
## "arena_bounds" BossBase, EnemySpawner, WorldDirector y el mapa. Si lo
## cambias, mueve también los muros de Perimeter en la escena (a ±esto + 0.5).
@export var arena_half_extent: float = 120.0

@export_group("Semilla (solo pruebas)")
## Encendido (lo normal), cada partida siembra el reparto desde el RNG de la
## partida, que BONK_GAME_SEED reproduce. Apagado (solo pruebas), usa
## scatter_seed: el mismo mapa en cada partida.
@export var randomize_per_run: bool = true
## Semilla fija del reparto cuando randomize_per_run está apagado. El juego
## y los soaks no la usan.
@export var scatter_seed: int = 71382

@export_group("Escenas de props")
## Prop interior principal (árbol en el bosque, cactus en las dunas).
@export var tree_scene: PackedScene
## Segundo prop interior; también es el acento del borde si
## perimeter_accent_scene está vacío.
@export var rock_scene: PackedScene
## Tercer prop interior.
@export var stump_scene: PackedScene

@export_group("Reparto interior")
## Cantidad de props de tree_scene. Cada arena pone la suya en su escena; el
## valor por defecto es el del bosque.
@export var tree_count: int = 128
## Cantidad de props de rock_scene (por defecto, la del bosque).
@export var rock_count: int = 54
## Cantidad de props de stump_scene (por defecto, la del bosque).
@export var stump_count: int = 34
## Rango de escala uniforme de cada prop de tree_scene.
@export var tree_scale_min: float = 0.85
@export var tree_scale_max: float = 1.25
## Rango de escala uniforme de cada prop de rock_scene.
@export var rock_scale_min: float = 0.7
@export var rock_scale_max: float = 1.1
## Rango de escala uniforme de cada prop de stump_scene.
@export var stump_scale_min: float = 0.8
@export var stump_scale_max: float = 1.2
## Distancia mínima entre centros de props, en metros: pasillos anchos para
## la horda (por defecto, la del bosque).
@export var min_prop_spacing: float = 5.0
## Metros desde el borde de la arena que los props interiores nunca
## cruzan (caen en ±(arena_half_extent - esto)); mayor que el margen del
## borde para que la franja del perímetro se distinga.
@export var interior_edge_margin: float = 12.0
## Radio libre de props alrededor del origen (spawn), en metros.
@export var spawn_clear_radius: float = 9.0
## Radio libre de props alrededor de cada nodo "scatter_keepout", en metros
## (cubre una plataforma con su rampa a la escala máxima).
@export var keepout_radius: float = 10.5

@export_group("Borde")
## Prop del borde. Vacío, usa tree_scene.
@export var perimeter_scene: PackedScene
## Prop de acento del borde (dunas: obeliscos). Vacío, usa rock_scene.
@export var perimeter_accent_scene: PackedScene
## Distancia en metros entre ranuras a lo largo de cada lado (por defecto,
## la del bosque).
@export var perimeter_step: float = 9.0
## Cada cuántas ranuras va un acento (0 = nunca; por defecto, el del bosque).
@export var perimeter_rock_every: int = 5
## Franja del borde: los props caen entre estos metros hacia dentro del
## borde de la arena (máximo = lado interior de la franja).
@export var perimeter_edge_margin_min: float = 2.0
@export var perimeter_edge_margin_max: float = 8.0
## Desvío al azar, en metros, de cada prop del borde a lo largo de su lado.
@export var perimeter_jitter: float = 2.0
## Rango de escala uniforme de los props del borde.
@export var perimeter_scale_min: float = 1.0
@export var perimeter_scale_max: float = 1.4
## Rango de escala uniforme de los acentos del borde.
@export var perimeter_accent_scale_min: float = 1.2
@export var perimeter_accent_scale_max: float = 1.7

@export_group("Mesetas")
## Mesetas (plataforma + rampa) por etapa; el Terrain aplana un claro bajo
## cada una. Son los hitos con nombre que vuelven legible una arena grande.
@export var mesa_count: int = 5
## Escenas de plataforma y rampa del bioma. Sin plataforma no hay mesetas:
## es un error de configuración que se ve, no un mapa plano en silencio.
@export var mesa_platform_scene: PackedScene
@export var mesa_ramp_scene: PackedScene
## Rango de escala uniforme de una meseta (plataforma y rampa).
@export var mesa_scale_min: float = 1.0
@export var mesa_scale_max: float = 1.6
## Distancia en metros del centro de la plataforma al de su rampa, a
## escala 1 (se multiplica por la escala de la meseta). 4.95 deja la rampa
## pegada a una cara de la plataforma de 6 m.
@export var mesa_ramp_offset: float = 4.95
## Distancia mínima en metros entre centros de meseta, y al spawn y a los
## keepouts.
@export var mesa_min_spacing: float = 42.0
## Metros desde el borde de la arena que los centros de meseta nunca
## cruzan (se sortean en ±(arena_half_extent - esto)).
@export var mesa_edge_margin: float = 28.0
## Radio en metros alrededor de una meseta que debe quedar libre de celdas
## bloqueadas: la plataforma más grande más el alcance de la rampa.
@export var mesa_clearance: float = 12.0

@export_group("Formaciones de roca")
## Aspecto de las formaciones de roca de este bioma (un .tres en
## assets/world/). Cada región conexa de celdas bloqueadas se vuelve UNA
## RockFormation: un macizo facetado cuya colisión es su propia malla. Vacío,
## usa los valores por defecto de RockFormationStyle.
@export var formation_style: RockFormationStyle
## Distancia en metros que los props interiores guardan a cualquier celda
## bloqueada: una formación llega hasta margin_max (del estilo) más allá de
## sus celdas, y un árbol saliendo de un acantilado parece un error.
@export var formation_clearance: float = 2.5

@export_group("Máscara de la arena")
## Encendida, la arena cuadrada recibe en cada partida una forma caminable
## irregular: una cuadrícula gruesa donde algunas regiones de celdas quedan
## tapadas por formaciones de roca (la roca es el muro; no hay colisión
## invisible). Un flood fill desde el spawn garantiza que toda celda
## abierta se alcanza a pie. Spawner, director y este scatter preguntan
## is_walkable() antes de colocar nada.
@export var mask_enabled: bool = true
## Lado de una celda de la máscara, en metros. Una formación solo es tan
## redonda como la cuadrícula: con celdas grandes salen piezas cuadradas.
@export var mask_cell_size: float = 5.0
## Formaciones de roca sembradas por etapa (mínimo y máximo).
@export var mask_blobs_min: int = 5
@export var mask_blobs_max: int = 8
## Celdas que crece cada formación desde su semilla (25 m² por celda de 5 m).
@export var mask_blob_cells_min: int = 20
@export var mask_blob_cells_max: int = 50
## Cuánto se estira una formación a lo largo de su propio eje al crecer:
## 0 da macizos redondos, ~3 da crestas. Cada formación sortea su
## estiramiento en [0, esto], así una etapa tiene de ambos.
@export var mask_ridge_bias: float = 3.0
## Distancia mínima (Chebyshev, en celdas) entre semillas de formación,
## para que sigan siendo hitos distintos y no se fundan en una placa.
@export var mask_blob_spacing: int = 10
## Celdas abiertas que siempre quedan entre dos formaciones distintas. Cada
## una llega hasta margin_max (de formation_style) más allá de sus celdas, así
## que un hueco de una celda se cerraría a una ranura apenas más ancha que un raider.
@export var mask_formation_gap: int = 2
## Ancho, en celdas, del anillo exterior donde la roca nunca siembra ni
## crece. Con el borde siempre abierto una formación no corta una esquina
## del mapa, y el flood fill no sella esquinas enteras.
@export var mask_border_cells: int = 2
## Radio en metros alrededor del spawn y de cada spot de verticalidad de
## autor donde nunca hay roca.
@export var mask_protect_radius: float = 15.0
## Si la fracción abierta (0-1) queda bajo esto, la máscara se reconstruye
## con menos formaciones.
@export var mask_min_open_fraction: float = 0.84

## RNG del reparto. La máscara saca números de este mismo objeto.
var _rng := RandomNumberGenerator.new()
## Máscara de celdas caminables (arena_mask.gd); se arma en _enter_tree.
var _mask: ArenaMask = null
## Se fija en _enter_tree (ver run_seed).
var _run_seed: int = 0
## Centros planos de las mesetas de esta etapa (ver mesa_sites).
var _mesa_sites: PackedVector2Array = PackedVector2Array()
## Posiciones planas de los props interiores ya puestos y de los keepouts.
var _placed_xz: PackedVector2Array = PackedVector2Array()
var _keepouts_xz: PackedVector2Array = PackedVector2Array()


func _enter_tree() -> void:
	# Se publica antes del _ready de cualquier hermano (orden del árbol): el
	# spawner y el Terrain siempre lo encuentran.
	add_to_group("arena_bounds")
	if GameConfig.daily_mode and GameConfig.daily_seed != 0:
		# Cacería diaria: todos juegan el mismo campo ese día.
		_rng.seed = GameConfig.daily_seed
	elif randomize_per_run:
		# Del RNG global de la partida y no de _rng.randomize(), que usa
		# entropía del sistema: así RunState.reset() y BONK_GAME_SEED
		# reproducen la máscara, los props y el relieve.
		_rng.seed = randi()
	else:
		_rng.seed = scatter_seed
	# Se fija aquí, antes de cualquier sorteo: el Terrain siembra su ruido
	# con esto en SU _ready, y el relieve tiene que coincidir con los props
	# sea cual sea el orden en que se construyen.
	_run_seed = int(_rng.seed)
	# La máscara debe existir antes del _ready del Terrain y antes de que el
	# WorldDirector baraje los interactuables (desde Arena._ready).
	_mask = _new_mask()
	if mask_enabled:
		_mask.build(_protected_seeds())
	# Sitios de meseta justo después de la máscara: el Terrain los lee como
	# claros planos en su _ready, y place_props() construye cada meseta.
	_pick_mesa_sites()


## Semilla de esta partida, válida desde _enter_tree. El Terrain la lee por
## el grupo "arena_bounds", así relieve y props siempre coinciden.
func run_seed() -> int:
	return _run_seed


## Centros XZ de las mesetas de esta etapa, para los claros del Terrain y
## para place_props(). Vacío antes de _enter_tree.
func mesa_sites() -> PackedVector2Array:
	return _mesa_sites


## Viste la arena. No corre en _ready: Arena._ready lo llama DESPUÉS de que
## el WorldDirector baraja los POIs del suelo, así la lista de keepouts lee
## las posiciones ya barajadas. Una arena se viste una sola vez, al
## construirse para su etapa.
func place_props() -> void:
	if mask_enabled:
		_raise_formations()
	_build_mesas()
	for node: Node in get_tree().get_nodes_in_group("scatter_keepout"):
		var spot := node as Node3D
		if spot == null or not is_inside_tree() or not spot.is_inside_tree():
			continue
		# Solo los keepouts de ESTA arena: durante un cambio de etapa la
		# arena saliente puede seguir en el árbol, y sus POIs no son nuestros.
		if not owner_arena_contains(spot):
			continue
		_keepouts_xz.append(Vector2(spot.global_position.x, spot.global_position.z))
	_place_many(tree_scene, tree_count, tree_scale_min, tree_scale_max)
	_place_many(rock_scene, rock_count, rock_scale_min, rock_scale_max)
	_place_many(stump_scene, stump_count, stump_scale_min, stump_scale_max)
	_ring_perimeter()


## True si `node` pertenece a la misma escena de arena que este scatter (la
## Arena ancestro más cercana). Se busca por TIPO y no por el grupo
## "arena_root": Arena entra a ese grupo en su _ready, y esto también se
## llama desde _enter_tree (sitios de meseta).
func owner_arena_contains(node: Node) -> bool:
	var arena: Node = self
	while arena != null and not (arena is Arena):
		arena = arena.get_parent()
	return arena == null or arena.is_ancestor_of(node)


## Altura del terreno en una posición plana, o 0 donde aún no hay terreno
## (una escena sin él, o un consumidor que corre antes de que se construya).
## Toda colocación de este archivo pasa por aquí.
func ground_height(x: float, z: float) -> float:
	var terrain := Terrain.find(get_tree())
	if terrain == null:
		return 0.0
	terrain.ensure_built()
	return terrain.height_at(x, z)


# --- Fachada de la máscara: otros nodos llaman estos métodos por el grupo
# "arena_bounds" (spawner, director, jefes, jugador, mapa, harness).
# Conservar nombres y firmas.

## True si una posición plana está dentro de la arena y no cae en una celda
## bloqueada. Todo lo que coloca cuerpos o POIs pregunta esto primero.
func is_walkable(xz: Vector2) -> bool:
	return _mask.is_walkable(xz)


func blocked_cell_count() -> int:
	return _mask.blocked_cell_count()


func open_cell_count() -> int:
	return _mask.open_cell_count()


func cell_size() -> float:
	return mask_cell_size


## Coordenadas de cada celda bloqueada. Pública para el barrido de máscara
## del harness, que recorre el borde de cada celda bloqueada buscando un
## hueco por donde quepa la cápsula del jugador.
func blocked_cells() -> Array[Vector2i]:
	return _mask.blocked_cells()


## Centro plano de una celda. Público junto a blocked_cells() para que el
## harness use la misma aritmética que la máscara y nunca discrepen sobre
## dónde está un borde.
func cell_center(cell: Vector2i) -> Vector2:
	return _mask.cell_center(cell)


## Celda donde cae una posición plana. Pública para que un aviso nombre la
## celda y no solo los metros.
func cell_of(xz: Vector2) -> Vector2i:
	return _mask.cell_of(xz)


## Un punto plano caminable al azar (uniforme sobre el área abierta), o el
## origen si 64 intentos fallan. Saca números del RNG del reparto.
func random_walkable_point(margin: float = 4.0) -> Vector2:
	return _mask.random_walkable_point(margin)


## Arma la máscara con los exports de este nodo y el RNG del reparto.
func _new_mask() -> ArenaMask:
	var mask := ArenaMask.new(_rng)
	mask.enabled = mask_enabled
	mask.half_extent = arena_half_extent
	mask.cell_size = mask_cell_size
	mask.blobs_min = mask_blobs_min
	mask.blobs_max = mask_blobs_max
	mask.blob_cells_min = mask_blob_cells_min
	mask.blob_cells_max = mask_blob_cells_max
	mask.ridge_bias = mask_ridge_bias
	mask.blob_spacing = mask_blob_spacing
	mask.formation_gap = mask_formation_gap
	mask.border_cells = mask_border_cells
	mask.protect_radius = mask_protect_radius
	mask.min_open_fraction = mask_min_open_fraction
	return mask


## Puntos planos donde nunca hay roca: el spawn y cada keepout de autor
## (spots de verticalidad, grupos de rocas), en orden de grupo.
func _protected_seeds() -> Array[Vector2]:
	var seeds: Array[Vector2] = [Vector2.ZERO]
	for node: Node in get_tree().get_nodes_in_group("scatter_keepout"):
		var spot := node as Node3D
		if spot != null and not (spot is Interactable):
			seeds.append(Vector2(spot.global_position.x, spot.global_position.z))
	return seeds


## Elige los centros de meseta de la etapa: dentro del cuadrado de muestreo,
## en suelo caminable, lejos del spawn, de los keepouts de autor y entre sí.
## Corre en _enter_tree para que el Terrain aplane un claro bajo cada una
## antes de colocar nada.
func _pick_mesa_sites() -> void:
	_mesa_sites = PackedVector2Array()
	if mesa_count <= 0 or mesa_platform_scene == null:
		return
	var authored: Array[Vector2] = []
	for node: Node in get_tree().get_nodes_in_group("scatter_keepout"):
		var spot := node as Node3D
		if spot != null and not (spot is Interactable) and owner_arena_contains(spot):
			authored.append(Vector2(spot.position.x, spot.position.z))
	var half := _mesa_half_extent()
	for attempt in mesa_count * 40:
		if _mesa_sites.size() >= mesa_count:
			break
		var candidate := Vector2(_rng.randf_range(-half, half), _rng.randf_range(-half, half))
		if candidate.length() < mesa_min_spacing:
			continue
		if mask_enabled and not (_mask.clear_of(candidate, mesa_clearance)
				and _mask.clear_of(candidate, mesa_clearance * 0.5)):
			continue
		var clear := true
		for other: Vector2 in authored:
			if other.distance_to(candidate) < mesa_min_spacing:
				clear = false
				break
		if clear:
			for other: Vector2 in _mesa_sites:
				if other.distance_to(candidate) < mesa_min_spacing:
					clear = false
					break
		if clear:
			_mesa_sites.append(candidate)


## Mitad del cuadrado donde se sortean los centros de meseta, en metros.
func _mesa_half_extent() -> float:
	return arena_half_extent - mesa_edge_margin


## Construye plataforma + rampa en cada sitio. El claro ya es plano (el
## Terrain leyó mesa_sites()), así la rampa toca suelo parejo en sus dos
## extremos en vez de flotar en uno.
func _build_mesas() -> void:
	if mesa_platform_scene == null:
		return
	for site: Vector2 in _mesa_sites:
		var mesa_scale := _rng.randf_range(mesa_scale_min, mesa_scale_max)
		var plat := mesa_platform_scene.instantiate() as Node3D
		if plat == null:
			continue
		add_child(plat)
		var plat_angle := _rng.randf_range(0.0, TAU)
		plat.position = Vector3(site.x, ground_height(site.x, site.y), site.y)
		plat.rotation.y = plat_angle
		plat.scale = Vector3.ONE * mesa_scale

		if mesa_ramp_scene == null:
			_keepouts_xz.append(site)
			continue

		var ramp := mesa_ramp_scene.instantiate() as Node3D
		if ramp != null:
			add_child(ramp)
			# Alinea la rampa con una de las 4 caras planas de la plataforma.
			var side_idx := _rng.randi_range(0, 3)
			var local_offsets: Array[Vector3] = [
				Vector3(mesa_ramp_offset, 0.0, 0.0),
				Vector3(0.0, 0.0, mesa_ramp_offset),
				Vector3(-mesa_ramp_offset, 0.0, 0.0),
				Vector3(0.0, 0.0, -mesa_ramp_offset)
			]
			var local_rot_y: Array[float] = [PI, PI * 0.5, 0.0, -PI * 0.5]
			var world_pos: Vector3 = plat.transform * (local_offsets[side_idx] * mesa_scale)
			ramp.position = Vector3(world_pos.x, ground_height(world_pos.x, world_pos.z), world_pos.z)
			ramp.rotation.y = plat_angle + local_rot_y[side_idx]
			ramp.scale = Vector3.ONE * mesa_scale

		# La meseta cuenta como keepout del reparto interior, para que no
		# crezcan árboles a través de su plataforma.
		_keepouts_xz.append(site)


## Cada región conexa de celdas bloqueadas se vuelve UNA RockFormation que
## cubre toda la región, borde incluido, con roca sólida (rock_formation.gd
## explica por qué el sello es estructural y no probable). El interior
## también es roca a propósito: un raider puede saltar a una formación y
## caminar su cresta, y sobre una región hueca caería a suelo que la máscara
## llama inalcanzable y quedaría atrapado.
func _raise_formations() -> void:
	if _mask.blocked_cell_count() == 0:
		return
	var started := Time.get_ticks_msec()
	var terrain := Terrain.find(get_tree())
	if terrain != null:
		terrain.ensure_built()
	var regions := _mask.blocked_regions()
	var faces := 0
	var shapes := 0
	var seal_low := 0
	var tallest := 0.0
	for index in regions.size():
		var formation := RockFormation.new()
		formation.name = "RockFormation%d" % index
		formation.cell_size = mask_cell_size
		formation.half_extent = arena_half_extent
		formation.style = formation_style
		add_child(formation)
		formation.build(regions[index], terrain, _run_seed)
		faces += formation.face_count
		shapes += formation.prism_count
		seal_low += formation.seal_low
		tallest = maxf(tallest, formation.tallest)
	print("Rock formations: %d regions, %d faces, %d shapes, tallest=%.1f in %d ms" % [
			regions.size(), faces, shapes, tallest, Time.get_ticks_msec() - started])
	if seal_low > 0:
		push_warning("Rock formations: %d boundary vertices under %.1f m — the mask seal is thin there"
				% [seal_low, RockFormation.SEAL_MIN_HEIGHT])


## Muestreo por rechazo de `count` posiciones en el cuadrado interior, lejos
## del spawn, de los keepouts y de los props ya puestos. El tope de intentos
## evita un bucle infinito si la configuración no cabe.
func _place_many(scene: PackedScene, count: int, min_scale: float, max_scale: float) -> void:
	if scene == null:
		return
	var half := _interior_half_extent()
	var placed := 0
	var attempts := 0
	while placed < count and attempts < count * 24:
		attempts += 1
		var pos := Vector3(_rng.randf_range(-half, half), 0.0, _rng.randf_range(-half, half))
		if not _is_clear(pos):
			continue
		_spawn_prop(scene, pos, _rng.randf_range(min_scale, max_scale))
		_placed_xz.append(Vector2(pos.x, pos.z))
		placed += 1


## Mitad del cuadrado donde caen los props interiores, en metros.
func _interior_half_extent() -> float:
	return arena_half_extent - interior_edge_margin


func _is_clear(pos: Vector3) -> bool:
	var flat := Vector2(pos.x, pos.z)
	if flat.length() < spawn_clear_radius:
		return false
	if not _mask.clear_of(flat, formation_clearance):
		return false
	for keepout in _keepouts_xz:
		if keepout.distance_to(flat) < keepout_radius:
			return false
	for other in _placed_xz:
		if other.distance_to(flat) < min_prop_spacing:
			return false
	return true


## Recorre los cuatro lados del suelo plantando props grandes (y algún
## acento) en una franja con jitter. La franja queda fuera del cuadrado
## interior, así que no revisa distancias.
func _ring_perimeter() -> void:
	if _perimeter_main() == null:
		return
	var slot := 0
	var outer := arena_half_extent - perimeter_edge_margin_min
	var t := -outer + 1.0
	while t <= outer - 1.0:
		_plant_edge_prop(Vector3(t + _jitter(), 0.0, -_band_depth()), slot)
		_plant_edge_prop(Vector3(t + _jitter(), 0.0, _band_depth()), slot + 1)
		_plant_edge_prop(Vector3(-_band_depth(), 0.0, t + _jitter()), slot + 2)
		_plant_edge_prop(Vector3(_band_depth(), 0.0, t + _jitter()), slot + 3)
		slot += 4
		t += perimeter_step


## Desvío al azar de un prop del borde a lo largo de su lado.
func _jitter() -> float:
	return _rng.randf_range(-perimeter_jitter, perimeter_jitter)


## Distancia al centro, en metros, de un prop del borde (dentro de la franja).
func _band_depth() -> float:
	return _rng.randf_range(arena_half_extent - perimeter_edge_margin_max,
			arena_half_extent - perimeter_edge_margin_min)


func _plant_edge_prop(pos: Vector3, slot: int) -> void:
	var accent := _perimeter_accent()
	if accent != null and perimeter_rock_every > 0 and slot % perimeter_rock_every == 0:
		_spawn_prop(accent, pos, _rng.randf_range(perimeter_accent_scale_min, perimeter_accent_scale_max))
	else:
		_spawn_prop(_perimeter_main(), pos, _rng.randf_range(perimeter_scale_min, perimeter_scale_max))


func _perimeter_main() -> PackedScene:
	return perimeter_scene if perimeter_scene != null else tree_scene


func _perimeter_accent() -> PackedScene:
	return perimeter_accent_scene if perimeter_accent_scene != null else rock_scene


## Solo escala uniforme: Godot no soporta escalar formas de colisión de
## forma no uniforme. `pos.y` se IGNORA y se usa la altura del terreno en
## ese XZ: un prop a y = 0 flotaría sobre una loma o se hundiría en una
## hondonada.
func _spawn_prop(scene: PackedScene, pos: Vector3, uniform_scale: float) -> void:
	var prop := scene.instantiate() as Node3D
	if prop == null:
		return
	add_child(prop)
	prop.position = Vector3(pos.x, ground_height(pos.x, pos.z), pos.z)
	prop.rotate_y(_rng.randf_range(0.0, TAU))
	prop.scale = Vector3.ONE * uniform_scale
