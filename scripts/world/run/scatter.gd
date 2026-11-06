extends Node3D
## Reparto determinista de la arena: props interiores (árboles, rocas y
## tocones o sus equivalentes del bioma), una franja más densa en el borde
## para que el límite se lea como paisaje y no como vacío, mesetas, y la
## máscara de celdas caminables con sus formaciones de roca.
## Deja libre un radio alrededor del spawn (origen) y de cada nodo del grupo
## "scatter_keepout", y una distancia mínima entre props para que la horda
## (sin navmesh) siempre tenga pasillos anchos. Las copas no tienen
## colisión: solo bloquean troncos y rocas.

## Los cuatro pasos de la vecindad-4 de la máscara: crecimiento, relleno de
## muescas, flood fill y división en regiones usan la misma.
const STEPS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
## "Ninguna celda", para el selector de semillas de formación.
const NO_CELL := Vector2i(-1, -1)
## Atracción hacia celdas ya rodeadas por dos o más lados mientras la
## formación crece: da masas sólidas en vez de brazos de una celda.
const FORMATION_COMPACTNESS: float = 1.0

## Semilla fija del reparto. Solo se usa con randomize_per_run apagado.
@export var scatter_seed: int = 71382

## Encendido, cada partida siembra el reparto desde el RNG de la partida
## (BONK_GAME_SEED lo reproduce). Apagado, usa scatter_seed: el mismo mapa
## en cada partida.
@export var randomize_per_run: bool = true

## Mitad del lado de la arena, en metros (el suelo es un cuadrado de 2x
## esto). BossBase, EnemySpawner, WorldDirector, el mapa y el Backdrop lo
## leen por el grupo "arena_bounds" y le restan su propio margen.
@export var arena_half_extent: float = 120.0

@export_group("Prop Scenes")
## Prop interior principal (árbol en el bosque, cactus en las dunas).
@export var tree_scene: PackedScene
## Segundo prop interior; también es el acento del borde si
## perimeter_accent_scene está vacío.
@export var rock_scene: PackedScene
## Tercer prop interior.
@export var stump_scene: PackedScene

@export_group("Arena Mask")
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
## una llega hasta RockFormation.margin_max más allá de sus celdas, así que
## un hueco de una celda se cerraría a una ranura apenas más ancha que un raider.
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

## Celdas bloqueadas (coordenadas de cuadrícula -> true) y celdas por lado.
var _blocked: Dictionary[Vector2i, bool] = {}
var _mask_cells_per_side: int = 0
## Se fija en _enter_tree (ver run_seed).
var _run_seed: int = 0
## Centros planos de las mesetas de esta etapa (ver mesa_sites).
var _mesa_sites: PackedVector2Array = PackedVector2Array()

@export_group("Mesas (iteration 51)")
## Mesetas (plataforma + rampa) por etapa; el Terrain aplana un claro bajo
## cada una. Son los hitos con nombre que vuelven legible una arena grande.
@export var mesa_count: int = 5
## Distancia mínima en metros entre centros de meseta, y al spawn y a los
## keepouts.
@export var mesa_min_spacing: float = 42.0
## Mitad del cuadrado donde se sortean los centros de meseta, en metros.
@export var mesa_half_extent: float = 92.0
## Escenas de plataforma y rampa del bioma. Sin plataforma no hay mesetas:
## es un error de configuración que se ve, no un mapa plano en silencio.
@export var mesa_platform_scene: PackedScene
@export var mesa_ramp_scene: PackedScene
## Rango de escala uniforme de la plataforma de una meseta.
@export var mesa_scale_min: float = 1.0
@export var mesa_scale_max: float = 1.6
## Sin uso: la rampa se coloca a 4.95 m del centro (ver _build_mesas).
@export var mesa_ramp_offset: float = 5.5
## Radio en metros alrededor de una meseta que debe quedar libre de celdas
## bloqueadas: la plataforma más grande más el alcance de la rampa.
@export var mesa_clearance: float = 12.0

@export_group("Rock Formations (iteration 63)")
## Cada región conexa de celdas bloqueadas se vuelve UNA RockFormation
## (rock_formation.gd): un macizo facetado cuya colisión es su propia malla.
## Colores en sRGB, como cualquier albedo del inspector.
@export var formation_rock_color: Color = Color(0.31, 0.32, 0.35)
@export var formation_cap_color: Color = Color(0.25, 0.39, 0.2)
## Cuánto tinte de cima toman las partes casi planas (0 = roca desnuda).
@export var formation_cap_strength: float = 0.65
## Variación de brillo +- de las bandas de estratos (0 = sin bandas).
@export var formation_strata: float = 0.05
## Cuánto se ajustan las alturas a escalones (0 = riscos, 1 = mesetas escalonadas).
@export var formation_terrace: float = 0.0
## Altura del acantilado y altura extra hacia la cresta, en metros. Juntas
## (más el ruido) quedan bajo RockFormation.max_height, que queda bajo lo
## que un enemigo trepa de una vez.
@export var formation_cliff_height: float = 2.6
@export var formation_peak_height: float = 4.0
## Tamaño de faceta en metros (se redondea para que divida mask_cell_size).
@export var formation_step: float = 2.0
## Distancia en metros que los props interiores guardan a cualquier celda
## bloqueada: una formación llega hasta RockFormation.margin_max más allá
## de sus celdas, y un árbol saliendo de un acantilado parece un error.
@export var formation_clearance: float = 2.5

@export_group("Interior Scatter")
## Los props caen en [-esto, esto] en X/Z, en metros; queda dentro de la
## franja del perímetro para que el borde se distinga.
@export var interior_half_extent: float = 108.0
## Cantidad de cada prop interior.
@export var tree_count: int = 128
@export var rock_count: int = 54
@export var stump_count: int = 34
## Radio libre de props alrededor del origen (spawn), en metros.
@export var spawn_clear_radius: float = 9.0
## Radio libre de props alrededor de cada nodo "scatter_keepout", en metros
## (cubre una plataforma con su rampa a la escala máxima).
@export var keepout_radius: float = 10.5
## Distancia mínima entre centros de props, en metros: pasillos anchos para la horda.
@export var min_prop_spacing: float = 5.0

@export_group("Perimeter Line")
## Prop del borde y su acento, para biomas cuyo borde difiere del interior
## (dunas: rocas con obeliscos). Vacíos, el borde usa tree_scene con
## acentos de rock_scene.
@export var perimeter_scene: PackedScene
@export var perimeter_accent_scene: PackedScene
## Franja del borde: distancias al centro, en metros, entre las que caen los props.
@export var perimeter_inner: float = 112.0
@export var perimeter_outer: float = 118.0
## Distancia en metros entre ranuras a lo largo de cada lado; cada N-ésima
## ranura es un acento.
@export var perimeter_step: float = 9.0
@export var perimeter_rock_every: int = 5

var _rng := RandomNumberGenerator.new()
var _placed_xz: PackedVector2Array = PackedVector2Array()
var _keepouts_xz: PackedVector2Array = PackedVector2Array()

## Colocaciones interiores que agotaron sus intentos de muestreo.
var failed_placements: int = 0


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
	if mask_enabled:
		_build_mask()
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
	_place_many(tree_scene, tree_count, 0.85, 1.25)
	_place_many(rock_scene, rock_count, 0.7, 1.1)
	_place_many(stump_scene, stump_count, 0.8, 1.2)
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


## Muestreo por rechazo de `count` posiciones en el cuadrado interior, lejos
## del spawn, de los keepouts y de los props ya puestos. El tope de intentos
## evita un bucle infinito si la configuración no cabe.
func _place_many(scene: PackedScene, count: int, min_scale: float, max_scale: float) -> void:
	if scene == null:
		return
	var placed := 0
	var attempts := 0
	while placed < count and attempts < count * 24:
		attempts += 1
		var pos := Vector3(
				_rng.randf_range(-interior_half_extent, interior_half_extent),
				0.0,
				_rng.randf_range(-interior_half_extent, interior_half_extent))
		if not _is_clear(pos):
			continue
		_spawn_prop(scene, pos, _rng.randf_range(min_scale, max_scale))
		_placed_xz.append(Vector2(pos.x, pos.z))
		placed += 1
	failed_placements += count - placed


func _is_clear(pos: Vector3) -> bool:
	var flat := Vector2(pos.x, pos.z)
	if flat.length() < spawn_clear_radius:
		return false
	if not _clear_of_mask(flat, formation_clearance):
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
	var t := -perimeter_outer + 1.0
	while t <= perimeter_outer - 1.0:
		_plant_edge_prop(Vector3(t + _rng.randf_range(-2.0, 2.0), 0.0, -_band_depth()), slot)
		_plant_edge_prop(Vector3(t + _rng.randf_range(-2.0, 2.0), 0.0, _band_depth()), slot + 1)
		_plant_edge_prop(Vector3(-_band_depth(), 0.0, t + _rng.randf_range(-2.0, 2.0)), slot + 2)
		_plant_edge_prop(Vector3(_band_depth(), 0.0, t + _rng.randf_range(-2.0, 2.0)), slot + 3)
		slot += 4
		t += perimeter_step


func _band_depth() -> float:
	return _rng.randf_range(perimeter_inner, perimeter_outer)


func _plant_edge_prop(pos: Vector3, slot: int) -> void:
	var accent := _perimeter_accent()
	if accent != null and perimeter_rock_every > 0 and slot % perimeter_rock_every == 0:
		_spawn_prop(accent, pos, _rng.randf_range(1.2, 1.7))
	else:
		_spawn_prop(_perimeter_main(), pos, _rng.randf_range(1.0, 1.4))


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


## Altura del terreno en una posición plana, o 0 donde aún no hay terreno
## (una escena sin él, o un consumidor que corre antes de que se construya).
## Toda colocación de este archivo pasa por aquí.
func ground_height(x: float, z: float) -> float:
	var terrain := Terrain.find(get_tree())
	if terrain == null:
		return 0.0
	terrain.ensure_built()
	return terrain.height_at(x, z)


## --- mesetas --------------------------------------------------------------

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
	for attempt in mesa_count * 40:
		if _mesa_sites.size() >= mesa_count:
			break
		var candidate := Vector2(
				_rng.randf_range(-mesa_half_extent, mesa_half_extent),
				_rng.randf_range(-mesa_half_extent, mesa_half_extent))
		if candidate.length() < mesa_min_spacing:
			continue
		if mask_enabled and not (_clear_of_mask(candidate, mesa_clearance)
				and _clear_of_mask(candidate, mesa_clearance * 0.5)):
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


## Construye plataforma + rampa en cada sitio. El claro ya es plano (el
## Terrain leyó mesa_sites()), así la rampa toca suelo parejo en sus dos
## extremos en vez de flotar en uno.
func _build_mesas() -> void:
	if mesa_platform_scene == null:
		return
	for site: Vector2 in _mesa_sites:
		var scale := _rng.randf_range(mesa_scale_min, mesa_scale_max)
		var plat := mesa_platform_scene.instantiate() as Node3D
		if plat == null:
			continue
		add_child(plat)
		var plat_angle := _rng.randf_range(0.0, TAU)
		plat.position = Vector3(site.x, ground_height(site.x, site.y), site.y)
		plat.rotation.y = plat_angle
		plat.scale = Vector3.ONE * scale

		if mesa_ramp_scene == null:
			_keepouts_xz.append(site)
			continue

		var ramp := mesa_ramp_scene.instantiate() as Node3D
		if ramp != null:
			add_child(ramp)
			# Alinea la rampa con una de las 4 caras planas de la plataforma.
			var side_idx := _rng.randi_range(0, 3)
			var local_offsets: Array[Vector3] = [
				Vector3(4.95, 0.0, 0.0),
				Vector3(0.0, 0.0, 4.95),
				Vector3(-4.95, 0.0, 0.0),
				Vector3(0.0, 0.0, -4.95)
			]
			var local_rot_y: Array[float] = [PI, PI * 0.5, 0.0, -PI * 0.5]
			var world_pos: Vector3 = plat.transform * (local_offsets[side_idx] * scale)
			ramp.position = Vector3(world_pos.x, ground_height(world_pos.x, world_pos.z), world_pos.z)
			ramp.rotation.y = plat_angle + local_rot_y[side_idx]
			ramp.scale = Vector3.ONE * scale

		# La meseta cuenta como keepout del reparto interior, para que no
		# crezcan árboles a través de su plataforma.
		_keepouts_xz.append(site)


## --- máscara de la arena --------------------------------------------------

func _cell_of(xz: Vector2) -> Vector2i:
	return Vector2i(
			floori((xz.x + arena_half_extent) / mask_cell_size),
			floori((xz.y + arena_half_extent) / mask_cell_size))


func _cell_center(cell: Vector2i) -> Vector2:
	return Vector2(
			-arena_half_extent + (float(cell.x) + 0.5) * mask_cell_size,
			-arena_half_extent + (float(cell.y) + 0.5) * mask_cell_size)


func _in_grid(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 \
			and cell.x < _mask_cells_per_side and cell.y < _mask_cells_per_side


## True si una posición plana está dentro de la arena y no cae en una celda
## bloqueada. Todo lo que coloca cuerpos o POIs pregunta esto primero.
func is_walkable(xz: Vector2) -> bool:
	if absf(xz.x) > arena_half_extent or absf(xz.y) > arena_half_extent:
		return false
	if not mask_enabled or _mask_cells_per_side == 0:
		return true
	# La cuadrícula, no solo el cuadrado: un punto en exactamente
	# +-half_extent cae una celda FUERA de la última fila, y una celda fuera
	# de la cuadrícula nunca está en _blocked.
	var cell := _cell_of(xz)
	return _in_grid(cell) and not _blocked.has(cell)


func blocked_cell_count() -> int:
	return _blocked.size()


func open_cell_count() -> int:
	return _mask_cells_per_side * _mask_cells_per_side - _blocked.size()


func cell_size() -> float:
	return mask_cell_size


## Coordenadas de cada celda bloqueada. Pública para el barrido de máscara
## del harness, que recorre el borde de cada celda bloqueada buscando un
## hueco por donde quepa la cápsula del jugador.
func blocked_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell: Vector2i in _blocked:
		cells.append(cell)
	return cells


## Centro plano de una celda. Público junto a blocked_cells() para que el
## harness use la misma aritmética que el scatter y nunca discrepen sobre
## dónde está un borde.
func cell_center(cell: Vector2i) -> Vector2:
	return _cell_center(cell)


## Celda donde cae una posición plana. Pública para que un aviso nombre la
## celda y no solo los metros.
func cell_of(xz: Vector2) -> Vector2i:
	return _cell_of(xz)


## Un punto plano caminable al azar (uniforme sobre el área abierta), o el
## origen si 64 intentos fallan.
func random_walkable_point(margin: float = 4.0) -> Vector2:
	for attempt in 64:
		var candidate := Vector2(
				_rng.randf_range(-arena_half_extent + margin, arena_half_extent - margin),
				_rng.randf_range(-arena_half_extent + margin, arena_half_extent - margin))
		if is_walkable(candidate):
			return candidate
	return Vector2.ZERO


## Celdas que deben quedar abiertas: toda celda a menos de
## mask_protect_radius del spawn o de un keepout de autor (spots de
## verticalidad, grupos de rocas).
func _protected_cells() -> Dictionary[Vector2i, bool]:
	var protected: Dictionary[Vector2i, bool] = {}
	var seeds: Array[Vector2] = [Vector2.ZERO]
	for node: Node in get_tree().get_nodes_in_group("scatter_keepout"):
		var spot := node as Node3D
		if spot != null and not (spot is Interactable):
			seeds.append(Vector2(spot.global_position.x, spot.global_position.z))
	var reach := ceili(mask_protect_radius / mask_cell_size) + 1
	var half := mask_cell_size * 0.5
	for seed_xz: Vector2 in seeds:
		var home := _cell_of(seed_xz)
		for dx in range(-reach, reach + 1):
			for dy in range(-reach, reach + 1):
				var cell := home + Vector2i(dx, dy)
				# Distancia de la semilla al CUADRADO de la celda, no a su
				# centro: una celda que el círculo apenas toca sigue siendo
				# suelo que el spot necesita.
				var center := _cell_center(cell)
				var gap := Vector2(maxf(absf(seed_xz.x - center.x) - half, 0.0),
						maxf(absf(seed_xz.y - center.y) - half, 0.0))
				if gap.length() <= mask_protect_radius:
					protected[cell] = true
	return protected


func _build_mask() -> void:
	_mask_cells_per_side = maxi(ceili(arena_half_extent * 2.0 / mask_cell_size), 3)
	var protected := _protected_cells()
	var formations := _rng.randi_range(mask_blobs_min, mask_blobs_max)
	for attempt in 4:
		_blocked.clear()
		var seeds: Array[Vector2i] = []
		# Qué formación creció cada celda bloqueada, para que la siguiente
		# guarde mask_formation_gap respecto de ella.
		var owners: Dictionary[Vector2i, int] = {}
		for formation in formations:
			var seed_cell := _pick_formation_seed(seeds, protected, owners)
			if seed_cell == NO_CELL:
				continue
			seeds.append(seed_cell)
			_grow_formation(seed_cell,
					_rng.randi_range(mask_blob_cells_min, mask_blob_cells_max),
					protected, owners, seeds.size())
		_fill_notches(protected)
		_seal_unreachable(protected)
		if float(open_cell_count()) / float(_mask_cells_per_side * _mask_cells_per_side) \
				>= mask_min_open_fraction:
			break
		formations = maxi(formations - 1, 1)
	var cells := _mask_cells_per_side * _mask_cells_per_side
	# El log da la FRACCIÓN ABIERTA, la cifra que persigue el bucle de
	# reconstrucción de arriba (mask_min_open_fraction).
	print("Arena mask: %d/%d cells blocked, open=%.2f" % [
			_blocked.size(), cells, float(open_cell_count()) / float(maxi(cells, 1))])


## True donde la roca puede sembrar o crecer: dentro de la cuadrícula,
## fuera del anillo de borde abierto y fuera de las celdas protegidas
## (spawn, verticalidad de autor).
func _rock_may_grow(cell: Vector2i, protected: Dictionary[Vector2i, bool]) -> bool:
	var last := _mask_cells_per_side - 1 - mask_border_cells
	return cell.x >= mask_border_cells and cell.y >= mask_border_cells \
			and cell.x <= last and cell.y <= last and not protected.has(cell)


## Celda semilla para la siguiente formación: a mask_blob_spacing celdas o
## más (Chebyshev) de cada semilla previa y libre de las formaciones ya
## crecidas, o NO_CELL si la etapa está llena.
func _pick_formation_seed(seeds: Array[Vector2i], protected: Dictionary[Vector2i, bool],
		owners: Dictionary[Vector2i, int]) -> Vector2i:
	for attempt in 32:
		var cell := Vector2i(
				_rng.randi_range(mask_border_cells, _mask_cells_per_side - 1 - mask_border_cells),
				_rng.randi_range(mask_border_cells, _mask_cells_per_side - 1 - mask_border_cells))
		if _blocked.has(cell) or not _rock_may_grow(cell, protected):
			continue
		if _crowds_formation(cell, -1, owners):
			continue
		var crowded := false
		for other: Vector2i in seeds:
			if maxi(absi(other.x - cell.x), absi(other.y - cell.y)) < mask_blob_spacing:
				crowded = true
				break
		if not crowded:
			return cell
	return NO_CELL


## True si `cell` está a mask_formation_gap celdas o menos (Chebyshev) de
## una celda crecida por cualquier formación distinta de `index`.
func _crowds_formation(cell: Vector2i, index: int, owners: Dictionary[Vector2i, int]) -> bool:
	for dx in range(-mask_formation_gap, mask_formation_gap + 1):
		for dy in range(-mask_formation_gap, mask_formation_gap + 1):
			var owner_index: int = owners.get(cell + Vector2i(dx, dy), index)
			if owner_index != index:
				return true
	return false


## Hace crecer una formación desde `start` hasta `size` celdas por
## acreción: cada paso añade una celda de la frontera (los vecinos-4 libres
## de lo ya crecido), con peso hacia el eje propio de la formación (crestas)
## y hacia celdas ya rodeadas por dos o más lados (masas sólidas).
func _grow_formation(start: Vector2i, size: int, protected: Dictionary[Vector2i, bool],
		owners: Dictionary[Vector2i, int], index: int) -> void:
	var axis := Vector2.from_angle(_rng.randf_range(0.0, TAU))
	var stretch := _rng.randf_range(0.0, mask_ridge_bias)
	var grown: Dictionary[Vector2i, bool] = {}
	var frontier: Dictionary[Vector2i, bool] = {}
	var next_cell := start
	while true:
		grown[next_cell] = true
		frontier.erase(next_cell)
		_blocked[next_cell] = true
		owners[next_cell] = index
		if grown.size() >= size:
			return
		for step: Vector2i in STEPS:
			var next := next_cell + step
			if not grown.has(next) and _rock_may_grow(next, protected) \
					and not _crowds_formation(next, index, owners):
				frontier[next] = true
		if frontier.is_empty():
			return
		var options: Array[Vector2i] = []
		var weights: Array[float] = []
		var total := 0.0
		for cell: Vector2i in frontier:
			var along := absf(Vector2(cell - start).normalized().dot(axis))
			var walls := 0
			for side: Vector2i in STEPS:
				if grown.has(cell + side):
					walls += 1
			var weight := 1.0 + stretch * along * along \
					+ FORMATION_COMPACTNESS * float(walls - 1)
			options.append(cell)
			weights.append(weight)
			total += weight
		var pick := _rng.randf() * total
		next_cell = options[options.size() - 1]
		for option in options.size():
			pick -= weights[option]
			if pick <= 0.0:
				next_cell = options[option]
				break


## Las celdas abiertas rodeadas de roca por tres o cuatro lados se vuelven
## roca: una muesca cerrada por tres lados no sirve para pelear, y su
## contorno cuadrado es lo único que el margen de la formación no esconde.
func _fill_notches(protected: Dictionary[Vector2i, bool]) -> void:
	for sweep in 3:
		var notches: Array[Vector2i] = []
		for x in _mask_cells_per_side:
			for y in _mask_cells_per_side:
				var cell := Vector2i(x, y)
				if _blocked.has(cell) or not _rock_may_grow(cell, protected):
					continue
				var walls := 0
				for step: Vector2i in STEPS:
					if _blocked.has(cell + step):
						walls += 1
				if walls >= 3:
					notches.append(cell)
		if notches.is_empty():
			return
		for cell: Vector2i in notches:
			_blocked[cell] = true


## Flood fill desde la celda del spawn; las celdas abiertas que no alcanza
## se sellan, así toda celda abierta que queda se alcanza a pie. Las celdas
## PROTEGIDAS (spawn y spots de verticalidad) nunca se sellan: si una quedó
## aislada, se abre un pasillo hasta suelo alcanzado y se repite el relleno.
## Así se cumplen las dos cosas: todo lo abierto es alcanzable y ningún spot
## de autor queda bajo una formación.
func _seal_unreachable(protected: Dictionary[Vector2i, bool]) -> void:
	var reached := _reachable_cells()
	var carved := false
	for cell: Vector2i in protected:
		if not _in_grid(cell) or reached.has(cell):
			continue
		if _carve_corridor(cell, reached):
			carved = true
	if carved:
		reached = _reachable_cells()
	for x in _mask_cells_per_side:
		for y in _mask_cells_per_side:
			var cell := Vector2i(x, y)
			if not reached.has(cell):
				_blocked[cell] = true


## Flood fill vecindad-4 desde la celda del spawn sobre las celdas abiertas.
func _reachable_cells() -> Dictionary[Vector2i, bool]:
	var start := _cell_of(Vector2.ZERO)
	var reached: Dictionary[Vector2i, bool] = {start: true}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		for step: Vector2i in STEPS:
			var next := cell + step
			if not _in_grid(next) or reached.has(next) or _blocked.has(next):
				continue
			reached[next] = true
			frontier.append(next)
	return reached


## Desbloquea una escalera de celdas desde `from` hasta la celda alcanzada
## más cercana. Conexa-4 a propósito (un eje por paso), para que el pasillo
## se camine con la misma vecindad del flood fill. True si abrió algo.
func _carve_corridor(from: Vector2i, reached: Dictionary[Vector2i, bool]) -> bool:
	var target := from
	var best := INF
	for cell: Vector2i in reached:
		var distance := Vector2(cell - from).length_squared()
		if distance < best:
			best = distance
			target = cell
	if target == from:
		return false
	var carved := false
	var cursor := from
	_blocked.erase(cursor)
	while cursor != target:
		var delta := target - cursor
		if absi(delta.x) >= absi(delta.y):
			cursor.x += signi(delta.x)
		else:
			cursor.y += signi(delta.y)
		if _blocked.erase(cursor):
			carved = true
	return carved


## Cada región conexa de celdas bloqueadas se vuelve UNA RockFormation que
## cubre toda la región, borde incluido, con roca sólida (rock_formation.gd
## explica por qué el sello es estructural y no probable). El interior
## también es roca a propósito: un raider puede saltar a una formación y
## caminar su cresta, y sobre una región hueca caería a suelo que la máscara
## llama inalcanzable y quedaría atrapado.
func _raise_formations() -> void:
	if _blocked.is_empty():
		return
	var started := Time.get_ticks_msec()
	var terrain := Terrain.find(get_tree())
	if terrain != null:
		terrain.ensure_built()
	var regions := _blocked_regions()
	var faces := 0
	var shapes := 0
	var seal_low := 0
	var tallest := 0.0
	for index in regions.size():
		var formation := RockFormation.new()
		formation.name = "RockFormation%d" % index
		formation.cell_size = mask_cell_size
		formation.half_extent = arena_half_extent
		formation.mesh_step = formation_step
		formation.cliff_height = formation_cliff_height
		formation.peak_height = formation_peak_height
		formation.terrace_strength = formation_terrace
		formation.rock_color = formation_rock_color
		formation.cap_color = formation_cap_color
		formation.cap_strength = formation_cap_strength
		formation.strata_strength = formation_strata
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


## Las celdas bloqueadas divididas en regiones conexas-4, cada una un
## conjunto (celda -> true) con la forma que recibe RockFormation.build().
func _blocked_regions() -> Array[Dictionary]:
	var regions: Array[Dictionary] = []
	var seen: Dictionary[Vector2i, bool] = {}
	for start: Vector2i in _blocked:
		if seen.has(start):
			continue
		var region: Dictionary[Vector2i, bool] = {start: true}
		seen[start] = true
		var frontier: Array[Vector2i] = [start]
		while not frontier.is_empty():
			var cell: Vector2i = frontier.pop_back()
			for step: Vector2i in STEPS:
				var next := cell + step
				if _blocked.has(next) and not seen.has(next):
					seen[next] = true
					region[next] = true
					frontier.append(next)
		regions.append(region)
	return regions


## True si `center` y los ocho puntos a `radius` a su alrededor son
## caminables: la prueba barata de "ninguna formación llega aquí".
func _clear_of_mask(center: Vector2, radius: float) -> bool:
	if not is_walkable(center):
		return false
	if not mask_enabled or radius <= 0.0:
		return true
	for index in 8:
		if not is_walkable(center + Vector2.from_angle(float(index) * TAU / 8.0) * radius):
			return false
	return true
