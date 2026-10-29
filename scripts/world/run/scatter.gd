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

## The four steps of the mask's 4-neighbourhood: blob growth, the notch
## fill, the flood fill and the region split all walk the same one.
const STEPS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
## "No cell found", for the formation seed picker.
const NO_CELL := Vector2i(-1, -1)
## Pull toward cells already touching the formation on two or more sides
## while it grows: what makes a formation a solid mass instead of a
## scribble of one-cell arms.
const FORMATION_COMPACTNESS: float = 1.0

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
## run — a coarse cell grid where a few regions of cells are blocked by
## rock (iteration 48: no invisible collider, the rock IS the wall;
## iteration 63: one sculpted RockFormation per region instead of a lattice
## of boulders). A flood fill from the spawn guarantees every open cell is
## reachable on foot; unreachable pockets are blocked too. Spawner, director
## and this scatter all ask is_walkable() before placing anything.
@export var mask_enabled: bool = true
## 5 m since iteration 63 (it was 10). A formation can only be as round as
## the grid it is drawn on: at 10 m every formation came out a Tetris piece
## of 2-4 squares with dead-straight cliffs, and no margin noise hides that.
@export var mask_cell_size: float = 5.0
## Rock formations seeded per stage. Iteration 63 cut this from 13-22
## random-walk blobs, which buried a fifth to a third of every arena under
## rock (120-133 of 576 cells on the seed-7 soaks, up to 38% by the old
## open-fraction gate).
@export var mask_blobs_min: int = 5
@export var mask_blobs_max: int = 8
## Cells each formation grows to from its seed (25 m² each at 5 m cells).
@export var mask_blob_cells_min: int = 20
@export var mask_blob_cells_max: int = 50
## How hard a formation stretches along its own random axis while it
## grows: 0 grows round massifs, ~3 grows ridges. Each formation rolls its
## own stretch in [0, this], so a stage gets both.
@export var mask_ridge_bias: float = 3.0
## Minimum Chebyshev distance between two formation seeds, in cells, so
## the formations stay distinct landmarks instead of fusing into one plate.
@export var mask_blob_spacing: int = 10
## Open cells always left between two different formations. Each one
## reaches up to RockFormation.margin_max past its cells, so a one-cell gap
## would close to a slot barely wider than a raider.
@export var mask_formation_gap: int = 2
## Width of the outer ring of cells where rock never seeds or grows. With
## the perimeter band always open a formation cannot cut a corner off, and
## cutting corners off is what made the flood fill seal whole corners of
## the map into the giant plates iterations 51-62 shipped.
@export var mask_border_cells: int = 2
## Radius around the spawn and each authored verticality spot that never
## gets rock. In metres, so it survives a change of mask_cell_size (it used
## to be "the cell and its neighbours", i.e. 10-20 m at 10 m cells).
@export var mask_protect_radius: float = 15.0
## Below this open fraction the mask is rebuilt with fewer formations.
@export var mask_min_open_fraction: float = 0.84

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
## Radius around a mesa site that must be free of blocked cells: the
## platform at its largest plus the ramp's reach, so neither one is ever
## built into the side of a rock formation.
@export var mesa_clearance: float = 12.0

@export_group("Rock Formations (iteration 63)")
## Every connected region of blocked cells becomes ONE RockFormation (see
## rock_formation.gd): a faceted massif whose collision is its own mesh.
## Colours are sRGB, like any albedo picked in the inspector.
@export var formation_rock_color: Color = Color(0.31, 0.32, 0.35)
@export var formation_cap_color: Color = Color(0.25, 0.39, 0.2)
## How much of the cap tint the gentle tops take (0 = bare rock).
@export var formation_cap_strength: float = 0.65
## +- brightness of horizontal strata bands (0 = none).
@export var formation_strata: float = 0.05
## How hard heights snap to ledges (0 = crags, 1 = stepped mesas).
@export var formation_terrace: float = 0.0
## Cliff skirt height, and the extra rise toward a formation's crest.
## Together (plus noise) they stay under RockFormation.max_height, which
## stays under what one enemy climb can scale.
@export var formation_cliff_height: float = 2.6
@export var formation_peak_height: float = 4.0
## Facet size in metres (rounded so it divides mask_cell_size exactly).
@export var formation_step: float = 2.0
## Interior props keep this far from any blocked cell. A formation reaches
## up to RockFormation.margin_max past its cells, and a tree growing out of
## a cliff face reads as a bug.
@export var formation_clearance: float = 2.5

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
		_raise_formations()
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
	if not _clear_of_mask(flat, formation_clearance):
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


## Builds a platform + ramp on each site. The pad under it is already flat
## (the Terrain read mesa_sites()), so the ramp meets level ground at both
## ends instead of floating at one.
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
			# Alinear la rampa exactamente con una de las 4 caras planas de la plataforma
			var side_idx := _rng.randi_range(0, 3)
			var local_offsets := [
				Vector3(4.95, 0.0, 0.0),
				Vector3(0.0, 0.0, 4.95),
				Vector3(-4.95, 0.0, 0.0),
				Vector3(0.0, 0.0, -4.95)
			]
			var local_rot_y := [PI, PI * 0.5, 0.0, -PI * 0.5]
			var world_pos := plat.transform * (local_offsets[side_idx] * scale)
			ramp.position = Vector3(world_pos.x, ground_height(world_pos.x, world_pos.z), world_pos.z)
			ramp.rotation.y = plat_angle + local_rot_y[side_idx]
			ramp.scale = Vector3.ONE * scale

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


## Cells that must stay open: every cell within mask_protect_radius of the
## spawn or of a hand-placed keepout (verticality spots, rock clusters).
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
				# Distance from the seed to the cell's SQUARE, not its centre:
				# a cell the circle merely clips is still ground the spot needs.
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
		# Which formation grew each blocked cell, so the next one can keep
		# mask_formation_gap away from it.
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
	# The OPEN FRACTION is the number that matters (mask_min_open_fraction
	# is the gate the rebuild loop above is chasing), so the log states it
	# instead of leaving a reader to divide two counts.
	print("Arena mask: %d/%d cells blocked, open=%.2f" % [
			_blocked.size(), cells, float(open_cell_count()) / float(maxi(cells, 1))])


## True where rock may seed or grow: inside the grid, off the open border
## ring, and not a protected cell (spawn, authored verticality).
func _rock_may_grow(cell: Vector2i, protected: Dictionary[Vector2i, bool]) -> bool:
	var last := _mask_cells_per_side - 1 - mask_border_cells
	return cell.x >= mask_border_cells and cell.y >= mask_border_cells \
			and cell.x <= last and cell.y <= last and not protected.has(cell)


## A seed cell for the next formation, at least mask_blob_spacing cells
## (Chebyshev) from every seed so far and clear of every formation grown so
## far, or NO_CELL when the stage is full.
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


## True when `cell` is within mask_formation_gap cells (Chebyshev) of a cell
## grown by any formation other than `index`.
func _crowds_formation(cell: Vector2i, index: int, owners: Dictionary[Vector2i, int]) -> bool:
	for dx in range(-mask_formation_gap, mask_formation_gap + 1):
		for dy in range(-mask_formation_gap, mask_formation_gap + 1):
			var owner_index: int = owners.get(cell + Vector2i(dx, dy), index)
			if owner_index != index:
				return true
	return false


## Grows one formation from `start` to `size` cells by accretion: every
## step adds one cell of the frontier (the free 4-neighbours of what has
## grown so far), weighted toward the formation's own random axis (ridges)
## and toward cells already walled on two or more sides (solid masses). The
## random walk it replaces drew one-cell scribbles and crosses that no rock
## could be made to look like.
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


## Open cells walled by rock on three or four sides become rock too. A 10 m
## alcove closed on three sides is space nobody fights in, and its square
## outline is the one thing a formation's margin cannot hide.
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


## Flood fill from the spawn cell; open cells it cannot reach are sealed
## so "walk anywhere" holds for every remaining open cell. PROTECTED cells
## (the spawn and the hand-placed verticality spots) are never sealed:
## if a blob ring cut one off, a corridor is carved back to reached ground
## and the fill re-run, so both invariants survive — everything open is
## reachable AND no authored spot is ever buried under a rock formation.
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
		for step: Vector2i in STEPS:
			var next := cell + step
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


## Every connected region of blocked cells becomes ONE RockFormation
## (iteration 63) that covers the WHOLE region, boundary included, with
## solid rock — rock_formation.gd says why the seal is structural rather
## than likely. Iteration 48 dropped the invisible 7 m box that used to
## stand here (the player bumped into nothing next to the rocks, and
## climbing enemies walked along its roof at y~7, which reads as flying);
## iterations 48-62 then packed every blocked cell with a 3x3 lattice of
## oversized sphere rocks, ~1,200 props a stage that read as grey bubble
## wrap over a square grid. The interior is rock and not just the rim, on
## purpose: a raider can jump onto a formation and walk its crest (a soak
## caught exactly that), and over a hollow region it would drop into ground
## the mask calls unreachable and get stuck there.
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


## The blocked cells split into 4-connected regions, each one a set
## (cell -> true) in the shape RockFormation.build() takes.
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


## True when `center` and the eight points `radius` away around it are all
## walkable: the cheap test for "no formation reaches here".
func _clear_of_mask(center: Vector2, radius: float) -> bool:
	if not is_walkable(center):
		return false
	if not mask_enabled or radius <= 0.0:
		return true
	for index in 8:
		if not is_walkable(center + Vector2.from_angle(float(index) * TAU / 8.0) * radius):
			return false
	return true
