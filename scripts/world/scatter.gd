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

## True (the shipping default) re-seeds the scatter every run, so each
## hunt reads as a fresh clearing instead of the same memorized forest.
## Flip off (or in a harness, set a seed and this to false) to get the
## old deterministic layout back for reproducible tests.
@export var randomize_per_run: bool = true

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

@export_group("Arena Mask")
## Iteration 44: the square arena gets an IRREGULAR walkable shape each
## run — a coarse cell grid where a few random blobs of cells are blocked
## (filled with oversized rock clusters over a tall collider). A flood
## fill from the spawn guarantees every open cell is reachable on foot;
## unreachable pockets are blocked too. Spawner, director and this
## scatter all ask is_walkable() before placing anything.
@export var mask_enabled: bool = true
@export var mask_cell_size: float = 10.0
@export var mask_blobs_min: int = 6
@export var mask_blobs_max: int = 10
## Cells per blob (random walk length).
@export var mask_blob_cells: int = 12
## Below this open fraction the mask is rebuilt with fewer blobs.
@export var mask_min_open_fraction: float = 0.62
@export var mask_rocks_per_cell: int = 4
@export var mask_wall_height: float = 7.0

## Blocked cells (grid coords -> true) and the grid size (cells per side).
var _blocked: Dictionary[Vector2i, bool] = {}
var _mask_cells_per_side: int = 0

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
	if GameConfig.daily_mode and GameConfig.daily_seed != 0:
		# Daily Hunt: every player walks the same field that day.
		_rng.seed = GameConfig.daily_seed
	elif randomize_per_run:
		_rng.randomize()
	else:
		_rng.seed = scatter_seed
	# The mask must exist before the WorldDirector (later in tree order)
	# shuffles interactables in ITS _enter_tree.
	if mask_enabled:
		_build_mask()


func _ready() -> void:
	if mask_enabled:
		_fill_blocked_cells()
	for node: Node in get_tree().get_nodes_in_group("scatter_keepout"):
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
	if not is_walkable(flat):
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


## --- arena mask (iteration 44) ------------------------------------------------

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


## True when a flat position is inside the arena and not in a blocked
## cell. Everything that places bodies or POIs asks this first.
func is_walkable(xz: Vector2) -> bool:
	if absf(xz.x) > arena_half_extent or absf(xz.y) > arena_half_extent:
		return false
	if not mask_enabled or _mask_cells_per_side == 0:
		return true
	# The grid, not just the box: a point clamped to exactly +-half_extent
	# lands one cell PAST the last row, and an off-grid cell is never in
	# _blocked, so the whole rim used to answer "walkable" no matter what
	# the mask says there.
	var cell := _cell_of(xz)
	return _in_grid(cell) and not _blocked.has(cell)


func blocked_cell_count() -> int:
	return _blocked.size()


func open_cell_count() -> int:
	return _mask_cells_per_side * _mask_cells_per_side - _blocked.size()


func cell_size() -> float:
	return mask_cell_size


## A random walkable flat point (uniform over open cells, jittered).
func random_walkable_point(margin: float = 4.0) -> Vector2:
	for attempt in 64:
		var candidate := Vector2(
				_rng.randf_range(-arena_half_extent + margin, arena_half_extent - margin),
				_rng.randf_range(-arena_half_extent + margin, arena_half_extent - margin))
		if is_walkable(candidate):
			return candidate
	return Vector2.ZERO


## Cells that must stay open: the spawn and every hand-placed keepout
## (verticality spots, rock clusters) plus their 4-neighbors.
func _protected_cells() -> Dictionary[Vector2i, bool]:
	var protected: Dictionary[Vector2i, bool] = {}
	var seeds: Array[Vector2] = [Vector2.ZERO]
	for node: Node in get_tree().get_nodes_in_group("scatter_keepout"):
		var spot := node as Node3D
		if spot != null and not (spot is Interactable):
			seeds.append(Vector2(spot.global_position.x, spot.global_position.z))
	for seed_xz: Vector2 in seeds:
		var cell := _cell_of(seed_xz)
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				protected[cell + Vector2i(dx, dy)] = true
	return protected


func _build_mask() -> void:
	_mask_cells_per_side = maxi(ceili(arena_half_extent * 2.0 / mask_cell_size), 3)
	var protected := _protected_cells()
	var blobs := _rng.randi_range(mask_blobs_min, mask_blobs_max)
	for attempt in 4:
		_blocked.clear()
		for blob in blobs:
			var cell := Vector2i(_rng.randi_range(0, _mask_cells_per_side - 1),
					_rng.randi_range(0, _mask_cells_per_side - 1))
			var steps: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
			for step in mask_blob_cells:
				# Block the cell and one side neighbor, so blobs come out
				# two cells thick instead of thin scribbles.
				var thick := cell + steps[_rng.randi_range(0, 3)]
				for c: Vector2i in [cell, thick]:
					if _in_grid(c) and not protected.has(c):
						_blocked[c] = true
				cell += steps[_rng.randi_range(0, 3)]
		_seal_unreachable(protected)
		if float(open_cell_count()) / float(_mask_cells_per_side * _mask_cells_per_side) \
				>= mask_min_open_fraction:
			break
		blobs = maxi(blobs - 1, 1)
	print("Arena mask: %d/%d cells blocked" % [
			_blocked.size(), _mask_cells_per_side * _mask_cells_per_side])


## Flood fill from the spawn cell; open cells it cannot reach are sealed
## so "walk anywhere" holds for every remaining open cell. PROTECTED cells
## (the spawn and the hand-placed verticality spots) are never sealed:
## if a blob ring cut one off, a corridor is carved back to reached ground
## and the fill re-run, so both invariants survive — everything open is
## reachable AND no authored spot is ever buried under mask rocks.
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


## 4-neighbor flood fill from the spawn cell over the open cells.
func _reachable_cells() -> Dictionary[Vector2i, bool]:
	var start := _cell_of(Vector2.ZERO)
	var reached: Dictionary[Vector2i, bool] = {start: true}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := cell + dir
			if not _in_grid(next) or reached.has(next) or _blocked.has(next):
				continue
			reached[next] = true
			frontier.append(next)
	return reached


## Unblocks a staircase line of cells from `from` to the nearest reached
## cell. 4-connected on purpose (one axis per step), so the corridor is
## walkable by the same neighborhood the flood fill uses. True when it
## actually opened something.
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


## Every blocked cell becomes a tall invisible collider (players can't
## cross; climbing enemies can, slowly) dressed with oversized rocks.
func _fill_blocked_cells() -> void:
	if _blocked.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "MaskWalls"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	for cell: Vector2i in _blocked:
		var center := _cell_center(cell)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(mask_cell_size, mask_wall_height, mask_cell_size)
		shape.shape = box
		shape.position = Vector3(center.x, mask_wall_height * 0.5, center.y)
		body.add_child(shape)
		if rock_scene == null:
			continue
		for i in mask_rocks_per_cell:
			var pos := Vector3(
					center.x + _rng.randf_range(-mask_cell_size * 0.35, mask_cell_size * 0.35),
					0.0,
					center.y + _rng.randf_range(-mask_cell_size * 0.35, mask_cell_size * 0.35))
			_spawn_prop(rock_scene, pos, _rng.randf_range(2.2, 3.4))
