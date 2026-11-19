extends RefCounted
## El reparto interior de una arena: árboles antiguos, hongos gigantes,
## árboles, rocas y tocones (o sus equivalentes del bioma) sorteados por
## rechazo en el cuadrado interior, lejos del spawn, de los keepouts (mesetas,
## POIs y spots de autor), de la roca, del relieve y de los props ya puestos.
## Los valores son exports del scatter (grupo «Reparto interior»): se cambian
## en la arena, no aquí. Ninguna escena usa este script; scatter.gd lo
## precarga como InteriorProps y lo usa una vez, en place_props().

const PlacementRules := preload("res://scripts/world/run/scatter/placement_rules.gd")

var _scatter: ArenaScatter = null
var _rng: RandomNumberGenerator = null
var _mask: ArenaMask = null
var _mesas: MesaBuilder.Plan = null
var _rules: PlacementRules = null
## Márgenes que _is_clear lee en cada intento: copias de los exports del
## scatter (grupos «Reparto interior», «Relieve por zonas», «Mesetas» y
## «Formaciones de roca»), tomadas al crearse, justo antes de plantar.
var _spawn_clear := 0.0
var _rock_clear := 0.0
var _relief_clear := 0.0
var _mesa_gap := 0.0
var _keepout_radius := 0.0
var _spacing := 0.0
## Posiciones planas de los props interiores ya puestos y de los keepouts.
var _placed := PackedVector2Array()
var _keepouts := PackedVector2Array()


func _init(scatter: ArenaScatter, rng: RandomNumberGenerator, mask: ArenaMask,
		mesas: MesaBuilder.Plan, rules: PlacementRules) -> void:
	_scatter = scatter
	_rng = rng
	_mask = mask
	_mesas = mesas
	_rules = rules
	_spawn_clear = scatter.spawn_clear_radius
	_rock_clear = scatter.formation_clearance
	_relief_clear = scatter.relief_prop_clearance
	_mesa_gap = scatter.mesa_footprint_gap
	_keepout_radius = scatter.keepout_radius
	_spacing = scatter.min_prop_spacing


## Anota los keepouts del reparto: los sitios de las mesetas ya levantadas
## (`mesa_sites`), para que no crezcan árboles a través de su plataforma, y
## cada nodo del grupo "scatter_keepout" de esta arena.
func collect_keepouts(mesa_sites: PackedVector2Array) -> void:
	_keepouts.append_array(mesa_sites)
	for node: Node in _scatter.get_tree().get_nodes_in_group("scatter_keepout"):
		var spot := node as Node3D
		if spot == null or not _scatter.is_inside_tree() or not spot.is_inside_tree():
			continue
		# Solo los keepouts de ESTA arena: durante un cambio de etapa la
		# arena saliente puede seguir en el árbol, y sus POIs no son nuestros.
		if not _scatter.owner_arena_contains(spot):
			continue
		_keepouts.append(Vector2(spot.global_position.x, spot.global_position.z))


## Una copia de los keepouts anotados.
func keepouts() -> PackedVector2Array:
	return _keepouts.duplicate()


## Planta los cinco props interiores, en este orden y con el RNG del
## scatter. Los árboles y los tocones no crecen en el agua del cañón; las
## rocas sí.
func plant() -> void:
	var scatter := _scatter
	_place_many(scatter.ancient_tree_scene, scatter.ancient_tree_count,
			scatter.ancient_tree_scale_min, scatter.ancient_tree_scale_max, true)
	_place_many(scatter.mushroom_scene, scatter.mushroom_count, scatter.mushroom_scale_min,
			scatter.mushroom_scale_max, true)
	_place_many(scatter.tree_scene, scatter.tree_count, scatter.tree_scale_min,
			scatter.tree_scale_max, true)
	_place_many(scatter.rock_scene, scatter.rock_count, scatter.rock_scale_min,
			scatter.rock_scale_max)
	_place_many(scatter.stump_scene, scatter.stump_count, scatter.stump_scale_min,
			scatter.stump_scale_max, true)


## Muestreo por rechazo de `count` posiciones en el cuadrado interior para
## props de `scene`. El tope de intentos evita un bucle infinito si la
## configuración no cabe. Con `dry`, ninguno cae dentro del cañón del relieve.
func _place_many(scene: PackedScene, count: int, min_scale: float, max_scale: float,
		dry: bool = false) -> void:
	if scene == null:
		return
	# Mitad del cuadrado donde caen los props interiores, en metros.
	var half := _scatter.arena_half_extent - _scatter.interior_edge_margin
	var placed := 0
	var attempts := 0
	while placed < count and attempts < count * 24:
		attempts += 1
		var pos := Vector3(_rng.randf_range(-half, half), 0.0, _rng.randf_range(-half, half))
		if not _is_clear(pos) or (dry and _rules.in_canyon(Vector2(pos.x, pos.z))):
			continue
		_scatter.spawn_prop(scene, pos, _rng.randf_range(min_scale, max_scale))
		_placed.append(Vector2(pos.x, pos.z))
		placed += 1


## True si un prop interior cabe en `pos`: lejos del spawn, de la roca, del
## relieve, de las estructuras, de las mesetas, de los keepouts y de los demás.
func _is_clear(pos: Vector3) -> bool:
	var flat := Vector2(pos.x, pos.z)
	if flat.length() < _spawn_clear:
		return false
	if not _mask.clear_of(flat, _rock_clear):
		return false
	if not _rules.relief_clear(flat, _relief_clear) or not _rules.structures_clear(flat):
		return false
	if not _mesas.is_clear(flat, _mesa_gap):
		return false
	for keepout in _keepouts:
		if keepout.distance_to(flat) < _keepout_radius:
			return false
	for other in _placed:
		if other.distance_to(flat) < _spacing:
			return false
	return true
