class_name ForestEdge
extends Node3D
## El bosque de AFUERA del muro de una arena con relieve por zonas. Pasado el
## muro el suelo sigue (la franja de pasto del Terrain, ver OutsideRelief) y
## sube en lomas boscosas hasta el horizonte. Dos partes:
##
## - La FRANJA (EdgeFlora): árboles, rocas y matas sobre ese pasto, en mallas
##   por trozo hijas de este nodo. Este nodo es hijo del scatter de la arena,
##   así que la franja arde con el bosque en el infierno de Mythos
##   (HellDressing quema lo que cuelga de "arena_bounds") y en la marea se ve
##   como los árboles de adentro.
## - El BOSQUE PROFUNDO (EdgeCanopy): un manto de copas sobre las lomas, del
##   fondo de la franja al horizonte, en mallas por trozo colgadas del
##   Backdrop de la arena con un StandardMaterial3D propio: HellSky lo tiñe
##   con el horizonte en el infierno y en la marea.
##
## Se arma por frames desde que empieza la etapa, sin pasar de `slice_ms` por
## frame, y avisa cuando terminó (is_built, señal `built`, la línea `Forest
## edge:`). Cada trozo se siembra con la semilla de partida del scatter, esta
## sal y su lugar: la misma semilla da el mismo bosque, y no saca números de
## ningún otro RNG. No tiene colisión: los muros del Perimeter son lo único
## que frena. Sin suelo de afuera (Terrain.outside_relief() nulo) no arma nada.

## Avisa que el bosque de afuera terminó de armarse.
signal built

const EdgeFlora := preload("res://scripts/world/props/forest_edge/edge_flora.gd")
const EdgeCanopy := preload("res://scripts/world/props/forest_edge/edge_canopy.gd")
## Grupo de este nodo: el harness y las fotos esperan a que termine.
const GROUP: StringName = &"forest_edge"
## Sal que separa el azar del bosque de afuera de los otros sembrados con la
## misma semilla.
const SEED_SALT: int = 0x464F5245

@export_group("Ritmo")
## Milisegundos por frame que se gastan armando el bosque, como mucho (un
## trozo empezado se termina: el frame puede pasarse un poco).
@export var slice_ms: float = 3.0

@export_group("Franja: reparto")
## Largo de cada trozo de la franja a lo largo del muro, en metros.
@export var near_chunk: float = 20.0
## Metros desde el muro donde empiezan los árboles de la franja.
@export var near_from: float = 2.5
## Árboles por cada 100 m² de franja junto al muro.
@export var trees_at_wall: float = 1.4
## Árboles por cada 100 m² de franja en su fondo (más tupido hacia afuera).
@export var trees_at_back: float = 6.0
## Metros libres entre dos troncos de la franja.
@export var tree_spacing: float = 2.4
## Rocas por cada 100 m² de franja.
@export var rocks_per_100: float = 0.45
## Arbustos y helechos por cada 100 m² de franja.
@export var bushes_per_100: float = 2.6
## Troncos caídos por trozo de franja, como mucho.
@export var logs_per_chunk: int = 1

@export_group("Franja: árboles y rocas")
## Modelos de árbol de la franja: los mismos del reparto de adentro, así el
## bosque de afuera es el mismo bosque. Cada árbol toma uno al azar.
@export var tree_models: Array[PackedScene] = [
	preload("res://assets/models/survival/tree.glb"),
	preload("res://assets/models/survival/tree-tall.glb"),
]
## Modelo de roca de la franja.
@export var rock_model: PackedScene = preload("res://assets/models/survival/rock-a.glb")
## Escala base de un árbol de la franja, como la del árbol de adentro (Tree.tscn).
@export var tree_scale: float = 3.8
## Multiplicador mínimo de ancho de un árbol sobre tree_scale.
@export var tree_width_min: float = 1.0
## Multiplicador máximo de ancho de un árbol sobre tree_scale.
@export var tree_width_max: float = 2.3
## Multiplicador mínimo de alto de un árbol sobre tree_scale.
@export var tree_height_min: float = 0.85
## Multiplicador máximo de alto de un árbol sobre tree_scale.
@export var tree_height_max: float = 1.55
## Cuánto más altos son los árboles del fondo de la franja que los de junto
## al muro (0.5 = la mitad más): el bosque sube hacia afuera.
@export var back_height_boost: float = 0.8
## Escala mínima de una roca de la franja.
@export var rock_scale_min: float = 3.0
## Escala máxima de una roca de la franja.
@export var rock_scale_max: float = 7.5
## Verde oscuro y verde claro de los arbustos y helechos.
@export var bush_color: Color = Color(0.2, 0.55, 0.32)
@export var bush_bright: Color = Color(0.4, 0.72, 0.42)
## Color de los troncos caídos.
@export var log_color: Color = Color(0.5, 0.33, 0.22)
## Color de los peñascos que asoman del bosque profundo.
@export var crag_color: Color = Color(0.5, 0.52, 0.53)

@export_group("Bosque profundo")
## Lado de cada trozo del manto de copas, en metros.
@export var far_chunk: float = 80.0
## Paso de la malla del manto, en metros.
@export var canopy_step: float = 8.0
## Metros desde el muro donde empieza el manto, y cuánto varía ese borde.
@export var canopy_from: float = 16.0
@export var canopy_from_jitter: float = 4.0
## Metros que el manto tarda en llegar a su alto, desde su borde.
@export var canopy_rise: float = 7.0
## Metros entre dos entrantes del borde del manto, a lo largo del muro.
@export var canopy_edge_wave: float = 45.0
## Alto del manto sobre el suelo, en metros, y cuánto suben y bajan las copas.
@export var canopy_height: float = 10.0
@export var canopy_bumps: float = 5.0
## Ancho de cada bulto de copas del manto, en metros.
@export var canopy_bump_size: float = 11.0
## Metros desde el centro de la arena hasta donde llega el bosque.
@export var far_radius: float = 430.0
## Pinos que asoman sobre el manto, por trozo.
@export var spires_per_chunk: int = 16
## Peñascos de roca que asoman del manto, por trozo, como mucho.
@export var crags_per_chunk: int = 1
## Verde oscuro y verde claro del manto, y el de los pinos que asoman.
@export var canopy_dark: Color = Color(0.2, 0.45, 0.32)
@export var canopy_bright: Color = Color(0.32, 0.6, 0.42)
@export var spire_color: Color = Color(0.22, 0.5, 0.36)

var _terrain: Terrain = null
var _outside: OutsideRelief = null
var _backdrop: Node3D = null
var _seed: int = 0
var _jobs: Array[Dictionary] = []
var _next: int = 0
var _built: bool = false
var _spent_usec: int = 0
var _slice_max_usec: int = 0
var _far_material: StandardMaterial3D = null
var _tree_kits: Array = []
var _rock_kit: RefCounted = null
var _edge_noise := FastNoiseLite.new()
var _bump_noise := FastNoiseLite.new()
## Lo que se armó, para la línea de log: trozos de franja y de manto, árboles,
## rocas y caras.
var _counts: Dictionary[String, int] = {"near": 0, "far": 0, "trees": 0, "rocks": 0, "faces": 0}


func _ready() -> void:
	add_to_group(GROUP)
	set_process(false)
	# El scatter coloca sus props en Arena._ready, después de este _ready, y el
	# Backdrop ya está: se empieza un frame más tarde, como GroundCover.
	_begin.call_deferred()


## True cuando el bosque de afuera terminó de armarse (o no hay nada que armar).
func is_built() -> bool:
	return _built


## El suelo de afuera que viste este nodo.
func outside() -> OutsideRelief:
	return _outside


## La semilla de un trozo: la de partida, la sal y su lugar.
func chunk_seed(kind: int, a: int, b: int) -> int:
	return _seed ^ SEED_SALT ^ (kind * 83492791) ^ (a * 73856093) ^ (b * 19349663)


## Los modelos de árbol listos para copiar (EdgeFlora.Kit).
func tree_kits() -> Array:
	return _tree_kits


## El modelo de roca listo para copiar (EdgeFlora.Kit), o null.
func rock_kit() -> RefCounted:
	return _rock_kit


## El material propio del manto, el que tiñe HellSky.
func far_material() -> StandardMaterial3D:
	return _far_material


## El ruido del borde del manto (se lee a lo largo del contorno de la arena).
func edge_noise() -> FastNoiseLite:
	return _edge_noise


## El ruido de los bultos de copas del manto.
func bump_noise() -> FastNoiseLite:
	return _bump_noise


## Anota lo que armó un trozo, para la línea de log.
func tally(key: String, amount: int) -> void:
	_counts[key] = _counts.get(key, 0) + amount


func _begin() -> void:
	_terrain = Terrain.find(get_tree())
	if _terrain == null or _terrain.outside_relief() == null:
		_finish()
		return
	_outside = _terrain.outside_relief()
	if not _terrain.backdrop_path.is_empty():
		_backdrop = _terrain.get_node_or_null(_terrain.backdrop_path) as Node3D
	var bounds := get_parent()
	if bounds != null and bounds.has_method(&"run_seed"):
		_seed = int(bounds.call(&"run_seed"))
	_far_material = LowPolyMesh.MATERIAL.duplicate() as StandardMaterial3D
	_edge_noise.seed = _seed ^ SEED_SALT
	_edge_noise.frequency = 1.0 / maxf(canopy_edge_wave, 1.0)
	_bump_noise.seed = (_seed ^ SEED_SALT) + 7
	_bump_noise.frequency = 1.0 / maxf(canopy_bump_size, 1.0)
	for scene: PackedScene in tree_models:
		var kit := EdgeFlora.kit(scene)
		if kit != null:
			_tree_kits.append(kit)
	_rock_kit = EdgeFlora.kit(rock_model)
	_jobs = EdgeFlora.jobs(self)
	if _backdrop != null:
		_jobs.append_array(EdgeCanopy.jobs(self))
	set_process(true)


func _process(_delta: float) -> void:
	var started := Time.get_ticks_usec()
	var budget := int(slice_ms * 1000.0)
	while _next < _jobs.size() and Time.get_ticks_usec() - started < budget:
		var job := _jobs[_next]
		_next += 1
		if String(job["kind"]) == "far":
			EdgeCanopy.build(self, job, _backdrop)
		else:
			EdgeFlora.build(self, job)
	var spent := Time.get_ticks_usec() - started
	_spent_usec += spent
	_slice_max_usec = maxi(_slice_max_usec, spent)
	if _next >= _jobs.size():
		_finish()


func _finish() -> void:
	set_process(false)
	_built = true
	if _outside != null:
		print("Forest edge: near=%d far=%d trees=%d rocks=%d faces=%d in %d ms slice_max=%.1f ms" % [
				_counts["near"], _counts["far"], _counts["trees"], _counts["rocks"],
				_counts["faces"], _spent_usec / 1000, float(_slice_max_usec) / 1000.0])
	built.emit()
