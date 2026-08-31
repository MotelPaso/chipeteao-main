extends Node3D
## Deterministic ready-time prop scatter for the arena maps (GDD 7).
## A seeded RandomNumberGenerator fills the field with three prop kinds
## (Hollow Woods: trees/rocks/stumps; Ash Dunes: cacti/boulders/bone
## piles) and rings the floor edge with a denser prop line so the bounds
## read as biome instead of void. Keeps a clear radius around the player
## spawn (origin) and around every node in the "scatter_keepout" group
## (hand-placed verticality spots, rock clusters, interactables), and
## enforces a minimum spacing between props so the no-navmesh grunt horde
## always has wide walkable lanes (canopies carry no collision, so only
## trunks/rocks actually block).

@export var scatter_seed: int = 71382

## Single source of truth for the arena's half-size (floor is a square of
## side 2x this). Consumers (BossBase clamp, EnemySpawner floor-plate
## clamp) read it at ready through the "arena_bounds" group and subtract
## their own margin, so resizing a map is this one number plus the floor/
## wall geometry in the scene.
@export var arena_half_extent: float = 80.0

@export_group("Prop Scenes")
@export var tree_scene: PackedScene
@export var rock_scene: PackedScene
@export var stump_scene: PackedScene

@export_group("Interior Scatter")
## Props land in [-half_extent, half_extent] on X/Z; keep this inside the
## perimeter band so the tree line stays visually distinct.
@export var interior_half_extent: float = 68.0
@export var tree_count: int = 57
@export var rock_count: int = 24
@export var stump_count: int = 15
## No props inside this radius around the origin: spawn/tutorial-dummy space.
@export var spawn_clear_radius: float = 9.0
## No props inside this radius around any "scatter_keepout" node (covers a
## platform plus its ramp at the largest placed scale).
@export var keepout_radius: float = 10.5
## Center-to-center minimum between scattered props: wide horde lanes.
@export var min_prop_spacing: float = 5.0

@export_group("Perimeter Line")
## Optional edge-line overrides for biomes whose rim should differ from
## the interior mix (dunes: boulder rim with obelisk accents). Left null,
## the rim falls back to tree_scene with rock_scene accents (forest).
@export var perimeter_scene: PackedScene
@export var perimeter_accent_scene: PackedScene
@export var perimeter_inner: float = 72.0
@export var perimeter_outer: float = 78.0
## Distance between slots along each edge; every Nth slot is an accent.
@export var perimeter_step: float = 9.0
@export var perimeter_rock_every: int = 5

var _rng := RandomNumberGenerator.new()
var _placed_xz: PackedVector2Array = PackedVector2Array()
var _keepouts_xz: PackedVector2Array = PackedVector2Array()

## Interior placements that hit the rejection-sampling attempt cap (kept
## at 0 by tuning counts/spacing; asserted by the resize test harness).
var failed_placements: int = 0


func _enter_tree() -> void:
	# Published before any sibling's _ready (tree order), so the spawner's
	# bounds lookup always finds it.
	add_to_group("arena_bounds")


func _ready() -> void:
	_rng.seed = scatter_seed
	for node in get_tree().get_nodes_in_group("scatter_keepout"):
		var spot := node as Node3D
		if spot != null:
			_keepouts_xz.append(Vector2(spot.global_position.x, spot.global_position.z))
	_place_many(tree_scene, tree_count, 0.85, 1.25)
	_place_many(rock_scene, rock_count, 0.7, 1.1)
	_place_many(stump_scene, stump_count, 0.8, 1.2)
	_ring_perimeter()


## Rejection-samples `count` positions inside the interior square, skipping
## anything too close to spawn, a keepout spot, or an already-placed prop.
## The attempt cap keeps a crowded/misconfigured setup from looping forever.
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
	for keepout in _keepouts_xz:
		if keepout.distance_to(flat) < keepout_radius:
			return false
	for other in _placed_xz:
		if other.distance_to(flat) < min_prop_spacing:
			return false
	return true


## Walks the four floor edges placing big rim props (and the odd accent)
## in a jittered band, so the map edge reads as biome instead of void. The
## band sits outside the interior square, so no spacing checks are needed.
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


## Uniform scale only: non-uniform scaling of collision shapes is not
## supported by Godot physics.
func _spawn_prop(scene: PackedScene, pos: Vector3, uniform_scale: float) -> void:
	var prop := scene.instantiate() as Node3D
	if prop == null:
		return
	add_child(prop)
	prop.position = pos
	prop.rotate_y(_rng.randf_range(0.0, TAU))
	prop.scale = Vector3.ONE * uniform_scale
