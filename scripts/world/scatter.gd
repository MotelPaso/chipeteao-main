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

## Worst-case horizontal half-width of one mask rock, per unit of uniform
## scale: the smallest distance from the prop's origin to its own convex
## hull's footprint boundary, over every heading (Rock 0.944, DuneRock
## 0.992 — the smaller one is the safe assumption, since _spawn_prop
## rotates each prop at random around Y). Baked off the blob meshes; it
## moves only if the blob transforms in Rock.tscn/DuneRock.tscn do.
const MASK_ROCK_HALF_WIDTH: float = 0.94
## Radius of the player capsule (Player.tscn), which is also the capsule
## the ArenaProbe mask sweep pushes along every blocked-cell boundary: a
## rock this close to a sample still blocks it.
const PLAYER_CAPSULE_RADIUS: float = 0.4
## sqrt(2), as a compile-time constant: the fill lattice's budget is all
## about the DIAGONAL of a lattice square (the farthest a point of the cell
## can sit from the rock that has to cover it) and about the jitter, which
## can push that rock a diagonal further away.
const DIAGONAL: float = 1.4142136

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
@export var arena_half_extent: float = 120.0

@export_group("Prop Scenes")
@export var tree_scene: PackedScene
@export var rock_scene: PackedScene
@export var stump_scene: PackedScene

@export_group("Arena Mask")
## Iteration 44: the square arena gets an IRREGULAR walkable shape each
## run — a coarse cell grid where a few random blobs of cells are blocked
## and packed solid with oversized rocks (iteration 48: no invisible
## collider, the rocks ARE the wall). A flood fill from the spawn
## guarantees every open cell is reachable on foot; unreachable pockets
## are blocked too. Spawner, director and this scatter all ask
## is_walkable() before placing anything.
@export var mask_enabled: bool = true
@export var mask_cell_size: float = 10.0
@export var mask_blobs_min: int = 13
@export var mask_blobs_max: int = 22
## Cells per blob (random walk length).
@export var mask_blob_cells: int = 12
## Below this open fraction the mask is rebuilt with fewer blobs.
@export var mask_min_open_fraction: float = 0.62
## Mask rocks per axis inside a blocked cell: the fill is a jittered square
## lattice, so this is 3 x 3 = 9 rocks per blocked cell. Load bearing
## together with mask_rock_scale_min — see the budget in _fill_budget_gap();
## coarsening either one opens holes the ArenaProbe mask sweep reports.
@export var mask_rocks_per_side: int = 3
## How far a lattice rock may wander off its slot. Pure looks: without it
## the blocked regions read as a checkerboard of boulders.
@export var mask_rock_jitter: float = 0.3
## Uniform scale range of every mask rock.
@export var mask_rock_scale_min: float = 2.9
@export var mask_rock_scale_max: float = 3.6

## Blocked cells (grid coords -> true) and the grid size (cells per side).
var _blocked: Dictionary[Vector2i, bool] = {}
var _mask_cells_per_side: int = 0
## Frozen at _enter_tree (see run_seed).
var _run_seed: int = 0
## Flat centres of this stage's mesas (see mesa_sites).
var _mesa_sites: PackedVector2Array = PackedVector2Array()

@export_group("Mesas (iteration 51)")
## Raised platform+ramp clusters the terrain flattens a pad under. They
## are what makes a 240x240 arena readable: relief alone is too soft to
## navigate by, and a mesa is a landmark you can name.
@export var mesa_count: int = 5
## Minimum distance between two mesa centres, and from spawn/keepouts.
@export var mesa_min_spacing: float = 42.0
## Half-extent mesas are sampled in (inside the interior square).
@export var mesa_half_extent: float = 92.0
## Platform and ramp scenes for this biome's mesas. Left null the biome
## falls back to nothing (no mesas), which is a configuration error worth
## seeing rather than a silent flat map.
@export var mesa_platform_scene: PackedScene
@export var mesa_ramp_scene: PackedScene
## Uniform scale range of a mesa platform, and how far the ramp sits from
## the platform centre.
@export var mesa_scale_min: float = 1.0
@export var mesa_scale_max: float = 1.6
@export var mesa_ramp_offset: float = 5.5

@export_group("Interior Scatter")
## Props land in [-half_extent, half_extent] on X/Z; keep this inside the
## perimeter band so the tree line stays visually distinct.
@export var interior_half_extent: float = 108.0
@export var tree_count: int = 128
@export var rock_count: int = 54
@export var stump_count: int = 34
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
@export var perimeter_inner: float = 112.0
@export var perimeter_outer: float = 118.0
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
		# Drawn from the RUN's stream, not from _rng.randomize(): that call
		# reseeds from system entropy and is deaf to RunState.reset(), so
		# BONK_GAME_SEED (and any two-sided comparison built on it) never
		# actually reproduced the mask, the props or the relief standing on
		# them — two "identical" soaks came out with different arenas. A
		# normal run is unaffected: reset() randomize()s the same stream.
		_rng.seed = randi()
	else:
		_rng.seed = scatter_seed
	# Frozen here, before anything draws from the stream: the Terrain node
	# seeds its noise from this in ITS _ready, and a terrain that did not
	# match the props standing on it would be a different arena every time
	# the two were built in a different order.
	_run_seed = int(_rng.seed)
	# The mask must exist before the WorldDirector (later in tree order)
	# shuffles interactables in ITS _enter_tree.
	if mask_enabled:
		_build_mask()
	# Mesa sites right after the mask (iteration 51): the Terrain reads
	# them as flat pads in its _ready, and place_props() builds the
	# platform + ramp on each one later.
	_pick_mesa_sites()


## This run's seed, valid from _enter_tree onward. Read through the
## "arena_bounds" group by the Terrain, so relief and props always agree.
func run_seed() -> int:
	return _run_seed


## Flat XZ centres of this stage's mesas, for the Terrain's pads and for
## place_props(). Empty before _enter_tree.
func mesa_sites() -> PackedVector2Array:
	return _mesa_sites


## Dressing the arena is NOT done in _ready any more (iteration 49): the
## Arena root calls this AFTER the WorldDirector has shuffled the ground
## POIs, so the keepout list below reads the SHUFFLED positions. That
## ordering used to come from the director living in the arena and doing
## its shuffle in _enter_tree; with one persistent director for the whole
## run, the arena has to sequence it explicitly.
## Idempotent by construction: an arena is dressed exactly once, when it
## is built for its stage.
func place_props() -> void:
	if mask_enabled:
		_fill_blocked_cells()
	_build_mesas()
	for node: Node in get_tree().get_nodes_in_group("scatter_keepout"):
		var spot := node as Node3D
		if spot == null or not is_inside_tree() or not spot.is_inside_tree():
			continue
		# Only THIS arena's keepouts: during a stage swap the outgoing
		# arena can still be in the tree, and its POIs are not ours.
		if not owner_arena_contains(spot):
			continue
		_keepouts_xz.append(Vector2(spot.global_position.x, spot.global_position.z))
	_place_many(tree_scene, tree_count, 0.85, 1.25)
	_place_many(rock_scene, rock_count, 0.7, 1.1)
	_place_many(stump_scene, stump_count, 0.8, 1.2)
	_ring_perimeter()


## True when `node` belongs to the same arena scene as this scatter. The
## arena root is this node's nearest ancestor in group "arena_root".
## Found by TYPE, not by the "arena_root" group: Arena claims that group
## in its _ready, and this is also called from _enter_tree (mesa sites).
func owner_arena_contains(node: Node) -> bool:
	var arena: Node = self
	while arena != null and not (arena is Arena):
		arena = arena.get_parent()
	return arena == null or arena.is_ancestor_of(node)


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
## `pos.y` is IGNORED and replaced by the terrain height at that XZ
## (iteration 51): nothing in this project is placed at y = 0 any more, and
## a prop left there would float over a hill or sink into a hollow.
func _spawn_prop(scene: PackedScene, pos: Vector3, uniform_scale: float) -> void:
	var prop := scene.instantiate() as Node3D
	if prop == null:
		return
	add_child(prop)
	prop.position = Vector3(pos.x, ground_height(pos.x, pos.z), pos.z)
	prop.rotate_y(_rng.randf_range(0.0, TAU))
	prop.scale = Vector3.ONE * uniform_scale


## Terrain height at a flat position, or 0 where there is no terrain yet
## (a scene without one, or a consumer running before it built). Every
## placement in this file goes through here.
func ground_height(x: float, z: float) -> float:
	var terrain := Terrain.find(get_tree())
	if terrain == null:
		return 0.0
	terrain.ensure_built()
	return terrain.height_at(x, z)


## --- mesas (iteration 51) -------------------------------------------------

## Picks the stage's mesa centres: inside the sampling square, on walkable
## ground, clear of the spawn, of the authored keepouts and of each other.
## Runs in _enter_tree so the Terrain can flatten a pad under each one
## before anything is placed.
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
		if mask_enabled and not is_walkable(candidate):
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


## Builds a platform + ramp on each site. The pad under it is already flat
## (the Terrain read mesa_sites()), so the ramp meets level ground at both
## ends instead of floating at one.
func _build_mesas() -> void:
	if mesa_platform_scene == null:
		return
	for site: Vector2 in _mesa_sites:
		var scale := _rng.randf_range(mesa_scale_min, mesa_scale_max)
		_spawn_prop(mesa_platform_scene, Vector3(site.x, 0.0, site.y), scale)
		if mesa_ramp_scene == null:
			continue
		var angle := _rng.randf_range(0.0, TAU)
		var ramp_at := site + Vector2(cos(angle), sin(angle)) * mesa_ramp_offset * scale
		_spawn_prop(mesa_ramp_scene, Vector3(ramp_at.x, 0.0, ramp_at.y), scale)
		# The mesa counts as a keepout for the interior scatter, so trees
		# do not grow through the platform it stands on.
		_keepouts_xz.append(site)


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


## Grid coords of every blocked cell. Public for the soak harness, whose
## mask sweep walks each blocked cell's boundary hunting for a gap the
## player capsule fits through.
func blocked_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell: Vector2i in _blocked:
		cells.append(cell)
	return cells


## Flat center of a grid cell. Public alongside blocked_cells() so the
## harness rebuilds an edge with the scatter's own arithmetic and the two
## can never disagree about where a boundary is.
func cell_center(cell: Vector2i) -> Vector2:
	return _cell_center(cell)


## Grid cell a flat position falls in. Public so a warning about someone
## standing where they should not can name the cell, not just the metres.
func cell_of(xz: Vector2) -> Vector2i:
	return _cell_of(xz)


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
	var cells := _mask_cells_per_side * _mask_cells_per_side
	# The OPEN FRACTION is the number that matters (mask_min_open_fraction
	# is the gate the rebuild loop above is chasing), so the log states it
	# instead of leaving a reader to divide two counts.
	print("Arena mask: %d/%d cells blocked, open=%.2f" % [
			_blocked.size(), cells, float(open_cell_count()) / float(maxi(cells, 1))])


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


## Every blocked cell becomes a REAL rock field: a jittered square lattice
## of oversized rocks whose footprints overlap enough to cover the WHOLE
## cell, boundary included. Iteration 48 dropped the invisible 7 m box that
## used to stand here — the player bumped into nothing next to the rocks,
## and climbing enemies walked along its roof at y~7, which reads as flying.
## The fill covers the interior and not just the rim on purpose: a raider
## can jump onto the rocks and walk the ridge (a soak caught exactly that),
## and over a hollow cell it would drop into ground the mask calls
## unreachable and get stuck there. With no floor left inside a blocked
## cell, coming down means landing on rock the player can see.
func _fill_blocked_cells() -> void:
	if _blocked.is_empty() or rock_scene == null:
		return
	var gap := _fill_budget_gap()
	if gap > 0.0:
		push_warning("Arena mask fill is %.2f m short per rock: raise mask_rocks_per_side or mask_rock_scale_min"
				% gap)
	var span := mask_cell_size / float(maxi(mask_rocks_per_side, 1))
	for cell: Vector2i in _blocked:
		var center := _cell_center(cell)
		for ix in mask_rocks_per_side:
			for iz in mask_rocks_per_side:
				var slot := Vector2(
						(float(ix) + 0.5) * span - mask_cell_size * 0.5,
						(float(iz) + 0.5) * span - mask_cell_size * 0.5)
				var spot := center + slot + Vector2(
						_rng.randf_range(-mask_rock_jitter, mask_rock_jitter),
						_rng.randf_range(-mask_rock_jitter, mask_rock_jitter))
				_spawn_prop(rock_scene, Vector3(spot.x, 0.0, spot.y),
						_rng.randf_range(mask_rock_scale_min, mask_rock_scale_max))


## How many metres of reach the WORST mask rock is missing, or 0 when the
## lattice covers its cell. The farthest a point of the cell can sit from
## the rock responsible for it is half the diagonal of one lattice square,
## and the jitter can push that rock a full diagonal further away; a rock
## covers everything within its own footprint plus the player capsule's
## radius. Mask rocks are oversized so that footprint is the widest slice
## of the hull all along the capsule's height, instead of a sphere that
## thins out at the ankles.
func _fill_budget_gap() -> float:
	var reach := MASK_ROCK_HALF_WIDTH * mask_rock_scale_min + PLAYER_CAPSULE_RADIUS
	var span := mask_cell_size / float(maxi(mask_rocks_per_side, 1))
	var needed := span * DIAGONAL * 0.5 + mask_rock_jitter * DIAGONAL
	return maxf(needed - reach, 0.0)
