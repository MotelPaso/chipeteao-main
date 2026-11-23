class_name ArenaScatter
extends Node3D
## Reparto determinista de la arena: props interiores (árboles, rocas y
## tocones o sus equivalentes del bioma), una franja más densa en el borde
## para que el límite se lea como paisaje y no como vacío, mesetas, y la
## máscara de celdas caminables con sus formaciones de roca.
## Deja libre un radio alrededor del spawn (origen) y de cada nodo del grupo
## "scatter_keepout", y una distancia mínima entre props para que la horda
## (sin navmesh) siempre tenga pasillos anchos. Las copas no tienen
## colisión: solo bloquean troncos y rocas.
## Aquí quedan los exports, el orden de construcción y la fachada del grupo
## "arena_bounds"; el trabajo lo hacen ScatterMask (máscara y roca), MesaBuilder,
## InteriorProps, PerimeterRing y PlacementRules (can_place y compañía), en scatter/.

const ScatterMask := preload("res://scripts/world/run/scatter/scatter_mask.gd")
const InteriorProps := preload("res://scripts/world/run/scatter/interior_props.gd")
const PlacementRules := preload("res://scripts/world/run/scatter/placement_rules.gd")

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
## Árbol antiguo: mucho más alto que los demás, pocos por etapa. Vacío, no hay.
@export var ancient_tree_scene: PackedScene
## Hongo gigante (scenes/world/props/GiantMushroom.tscn). Vacío, no hay.
@export var mushroom_scene: PackedScene

@export_group("Reparto interior")
## Cantidad de props de tree_scene. Cada arena pone la suya en su escena; el
## valor por defecto es el del bosque.
@export var tree_count: int = 128
## Cantidad de props de rock_scene (por defecto, la del bosque).
@export var rock_count: int = 54
## Cantidad de props de stump_scene (por defecto, la del bosque).
@export var stump_count: int = 34
## Cantidad de árboles antiguos (ancient_tree_scene).
@export var ancient_tree_count: int = 0
## Cantidad de hongos gigantes (mushroom_scene).
@export var mushroom_count: int = 0
## Escala uniforme mínima de un hongo gigante.
@export var mushroom_scale_min: float = 0.8
## Escala uniforme máxima de un hongo gigante.
@export var mushroom_scale_max: float = 1.45
## Escala uniforme mínima de cada árbol antiguo (1 = tamaño de la escena).
@export var ancient_tree_scale_min: float = 0.85
## Escala uniforme máxima de cada árbol antiguo (1 = tamaño de la escena).
@export var ancient_tree_scale_max: float = 1.2
## Escala uniforme mínima de cada prop de tree_scene (1 = tamaño del modelo).
@export var tree_scale_min: float = 0.85
## Escala uniforme máxima de cada prop de tree_scene (1 = tamaño del modelo).
@export var tree_scale_max: float = 1.25
## Escala uniforme mínima de cada prop de rock_scene (1 = tamaño del modelo).
@export var rock_scale_min: float = 0.7
## Escala uniforme máxima de cada prop de rock_scene (1 = tamaño del modelo).
@export var rock_scale_max: float = 1.1
## Escala uniforme mínima de cada prop de stump_scene (1 = tamaño del modelo).
@export var stump_scale_min: float = 0.8
## Escala uniforme máxima de cada prop de stump_scene (1 = tamaño del modelo).
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
## Radio libre de props alrededor de cada nodo "scatter_keepout" (POIs, objetos
## de inicio de etapa y spots de autor), en metros; cubre un spot de autor con su rampa.
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
## Lado exterior de la franja del borde: metros hacia dentro del borde de la arena donde empiezan los props del borde.
@export var perimeter_edge_margin_min: float = 2.0
## Lado interior de la franja del borde: metros hacia dentro del borde de la arena donde terminan los props del borde.
@export var perimeter_edge_margin_max: float = 8.0
## Desvío al azar, en metros, de cada prop del borde a lo largo de su lado.
@export var perimeter_jitter: float = 2.0
## Escala uniforme mínima de los props del borde (1 = tamaño del modelo).
@export var perimeter_scale_min: float = 1.0
## Escala uniforme máxima de los props del borde (1 = tamaño del modelo).
@export var perimeter_scale_max: float = 1.4
## Escala uniforme mínima de los acentos del borde (1 = tamaño del modelo).
@export var perimeter_accent_scale_min: float = 1.2
## Escala uniforme máxima de los acentos del borde (1 = tamaño del modelo).
@export var perimeter_accent_scale_max: float = 1.7
## Metros desde cada esquina de la arena donde el borde no planta nada (0 =
## planta hasta la esquina). Los props de dos lados pueden encerrar la celda
## de la esquina: un rincón de suelo abierto al que nadie llega.
@export var perimeter_corner_gap: float = 0.0

@export_group("Mesetas")
## Mesetas (plataforma + rampa) por etapa; el Terrain aplana un claro bajo
## cada una. Son los hitos con nombre que vuelven legible una arena grande.
@export var mesa_count: int = 5
## Escena de plataforma del bioma. Sin plataforma no hay mesetas: es un error de configuración que se ve, no un mapa plano en silencio.
@export var mesa_platform_scene: PackedScene
## Escena de la rampa que sube a cada plataforma del bioma.
@export var mesa_ramp_scene: PackedScene
## Escala uniforme mínima de una meseta, plataforma y rampa (1 = tamaño del modelo).
@export var mesa_scale_min: float = 1.0
## Escala uniforme máxima de una meseta, plataforma y rampa (1 = tamaño del modelo).
@export var mesa_scale_max: float = 1.6
## Distancia en metros del centro de la plataforma al de su rampa, a
## escala 1 (se multiplica por la escala de la meseta). 4.95 deja la rampa
## pegada a una cara de la plataforma de 6 m.
@export var mesa_ramp_offset: float = 4.95
## Encendido, la rampa queda pegada a su plataforma a cualquier escala.
## Apagado, mesa_ramp_offset se multiplica dos veces por la escala: una
## meseta más grande que el modelo queda con la rampa separada unos metros y
## a su plataforma se llega saltando (el reparto de Dunas y Ciénaga).
@export var mesa_ramp_attached: bool = false
## Distancia mínima en metros entre centros de meseta, y al spawn y a los
## keepouts.
@export var mesa_min_spacing: float = 42.0
## Metros desde el borde de la arena que los centros de meseta nunca
## cruzan (se sortean en ±(arena_half_extent - esto)).
@export var mesa_edge_margin: float = 28.0
## Metros entre la huella de cada meseta (plataforma y rampa, a su escala) y toda celda de roca: la roca asoma ~3 m y queda paso para un raider.
@export var mesa_clearance: float = 4.0
## Cofre que llevan encima las primeras mesetas de la etapa (vacío = ninguna).
@export var mesa_chest_scene: PackedScene
## Cuántas mesetas llevan un cofre encima.
@export var mesa_chest_count: int = 0
## Altura del tablero de la plataforma a escala 1, en metros: ahí se apoya
## el cofre de una meseta.
@export var mesa_deck_height: float = 2.0
## Metros libres alrededor de la plataforma y la rampa de cada meseta (a su escala) donde no se coloca nada ni crece pasto.
@export var mesa_footprint_gap: float = 2.0

@export_group("Relieve por zonas")
## Solo cuenta si el Terrain de la arena tiene `relief`. Metros que los props
## interiores guardan a cualquier corte, rampa o puente.
@export var relief_prop_clearance: float = 5.0
## Metros que el centro de una meseta guarda a cualquier corte, rampa o
## puente: su claro plano (pad_radius + pad_blend del Terrain) no puede pisarlos.
@export var relief_mesa_clearance: float = 18.0
## Metros alrededor del centro de una meseta donde can_place() dice que no.
@export var relief_mesa_keepout: float = 9.0

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
## Formaciones de roca sembradas por etapa, como mínimo.
@export var mask_blobs_min: int = 5
## Formaciones de roca sembradas por etapa, como máximo.
@export var mask_blobs_max: int = 8
## Celdas mínimas que crece cada formación desde su semilla (25 m² por celda de 5 m).
@export var mask_blob_cells_min: int = 20
## Celdas máximas que crece cada formación desde su semilla (25 m² por celda de 5 m).
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
## Escala, giro, rampa y huella de cada meseta, desde _enter_tree (MesaBuilder.plan).
var _mesas := MesaBuilder.Plan.new()
## Las preguntas can_place y compañía (placement_rules.gd); se conecta en _enter_tree.
var _rules := PlacementRules.new()
## Los puentes de arcos abiertos de la arena como los ve la horda, o null.
var _lanes: ReliefLanes = null
## El Terrain de esta arena (ver _arena_terrain); se busca una sola vez.
var _terrain: Terrain = null
var _terrain_sought: bool = false


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
	# El relieve por zonas se decide ANTES que la máscara y las mesetas: las
	# dos tienen que rodear sus cortes. Sin relieve, layout es null y nada cambia.
	var terrain := _arena_terrain()
	var layout := terrain.plan_relief(_run_seed, arena_half_extent) if terrain != null else null
	# La máscara debe existir antes del _ready del Terrain y antes de que el
	# WorldDirector baraje los interactuables (desde Arena._ready).
	_mask = ScatterMask.build(self, _rng, layout)
	# Mesetas justo después de la máscara (su huella esquiva la roca): el
	# Terrain lee los sitios como claros planos en su _ready, y place_props()
	# construye cada meseta. Su escala, giro y rampa salen ya: el director
	# coloca sus POI antes de que se levanten y tiene que esquivar su huella.
	_mesas = MesaBuilder.plan(self, _rng, _mask, terrain)
	_mesa_sites = _mesas.sites()
	_rules.setup(self, _mask, _mesas, terrain)


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
		ScatterMask.raise_formations(self, _mask, _run_seed)
	# Lo que cada consumidor del relieve arma, para la línea `Relief pieces:`.
	var pieces := {}
	_lanes = ReliefDressing.raise(self, _arena_terrain(), formation_style, _run_seed, pieces)
	var interior := InteriorProps.new(self, _rng, _mask, _mesas, _rules)
	interior.collect_keepouts(MesaBuilder.build(self, _mesas))
	# Las estructuras del relieve van después de los POIs y las mesetas (los
	# esquivan) y antes de los props (que las esquivan a ellas).
	var taken := interior.keepouts()
	taken.append_array(_mesa_sites)
	_rules.structure_sites = ReliefStructures.raise(self, _arena_terrain(), _run_seed, taken,
			pieces)
	ReliefPieces.report(_arena_terrain(), pieces)
	var relief := _arena_terrain() != null and _arena_terrain().has_relief()
	if relief:
		_rules.footprints.setup(arena_half_extent)
	interior.plant()
	PerimeterRing.new(self, _rng, _mask, relief).plant()


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
## Toda colocación del scatter y sus ayudantes pasa por aquí.
func ground_height(x: float, z: float) -> float:
	var terrain := Terrain.find(get_tree())
	if terrain == null:
		return 0.0
	terrain.ensure_built()
	return terrain.height_at(x, z)


## Planta un prop de `scene` en `pos`, girado al azar. Solo escala
## uniforme: Godot no soporta escalar formas de colisión de forma no
## uniforme. `pos.y` se IGNORA y se usa la altura del terreno en ese XZ: un
## prop a y = 0 flotaría sobre una loma o se hundiría en una hondonada.
## Pública para el reparto interior (InteriorProps) y el borde (PerimeterRing).
func spawn_prop(scene: PackedScene, pos: Vector3, uniform_scale: float) -> void:
	var prop := scene.instantiate() as Node3D
	if prop == null:
		return
	add_child(prop)
	prop.position = Vector3(pos.x, ground_height(pos.x, pos.z), pos.z)
	prop.rotate_y(_rng.randf_range(0.0, TAU))
	prop.scale = Vector3.ONE * uniform_scale
	_rules.footprints.add(prop)


# --- Fachada del grupo "arena_bounds": otros nodos llaman estos métodos por
# nombre (spawner, director, jefes, jugador, mapa, harness). Reenvían a la
# máscara o a PlacementRules. Conservar nombres y firmas.

## True si una posición plana está dentro de la arena y no cae en una celda
## bloqueada. Todo lo que coloca cuerpos o POIs pregunta esto primero.
func is_walkable(xz: Vector2) -> bool:
	return _mask.is_walkable(xz)


## True si en `xz` se puede COLOCAR algo (un POI, un spawn, un cofre, un
## jefe), a `margin` metros del relieve. Reglas: PlacementRules.can_place.
func can_place(xz: Vector2, margin: float = 0.0) -> bool:
	return _rules.can_place(xz, margin)


## True si en `xz` se puede levantar una ESTRUCTURA del director (un POI, un
## portal, un evento). Reglas: PlacementRules.can_build.
func can_build(xz: Vector2, margin: float = 0.0) -> bool:
	return _rules.can_build(xz, margin)


## True si en `xz` puede crecer la vegetación del suelo (PlacementRules.can_grow).
func can_grow(xz: Vector2, margin: float = 0.0) -> bool:
	return _rules.can_grow(xz, margin)


## Los puentes de esta arena bajo los que se pasa caminando, como los ve la
## horda (ReliefLanes), o null si no tiene. EnemyBase lo pide al nacer.
func horde_lanes() -> ReliefLanes:
	return _lanes


## El punto más cercano a `xz` donde can_place dice que sí, para lo que cae
## donde murió alguien. Reglas: PlacementRules.nearest_place.
func nearest_place(xz: Vector2, margin: float = 0.0, also: Callable = Callable()) -> Vector2:
	return _rules.nearest_place(xz, margin, also)


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


## El Terrain de esta arena, o null. Entre los hermanos y no por el grupo
## "terrain": en _enter_tree el Terrain, que va después en el árbol, todavía
## no entró.
func _arena_terrain() -> Terrain:
	if _terrain_sought:
		return _terrain
	_terrain_sought = true
	var parent := get_parent()
	if parent != null:
		for sibling: Node in parent.get_children():
			if sibling is Terrain:
				_terrain = sibling as Terrain
	return _terrain
