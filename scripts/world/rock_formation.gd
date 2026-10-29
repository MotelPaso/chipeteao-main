class_name RockFormation
extends StaticBody3D
## One rock massif raised over a connected region of blocked arena-mask
## cells (iteration 63). It replaces the lattice of nine identical sphere
## rocks per blocked cell that iterations 48-62 packed the mask with: from
## any distance that fill read as grey bubble wrap laid over a square grid,
## with every cell outline in plain view and the same height everywhere.
##
## WHAT IT IS. A faceted heightfield over the region's footprint: a steep
## cliff skirt that starts a noisy margin OUTSIDE the blocked cells, then a
## slower rise toward a crest whose height follows how deep inside the
## region a point is — a two-cell ridge reads as a ridge, a compact massif
## gets a summit. Flat-shaded, one colour per facet: biome rock on the
## faces, a cap tint on the near-flat tops, strata bands by height.
##
## COLLISION IS THE MESH. Every grid quad that shows above the ground is
## also one convex prism: its four surface corners plus the same four sunk
## under the terrain. The quad is split along whichever diagonal is HIGHER,
## which is exactly the upper hull of those four corners, so the prism's top
## is the two triangles you see — nothing invisible to bump into, nothing
## visible to walk through. Convex prisms rather than one trimesh on
## purpose: a trimesh has no inside, and the ArenaProbe mask sweep stands a
## capsule INSIDE the rock at every cell boundary; against a convex solid
## that is a hit, against a trimesh it is an "opening".
##
## THE SEAL. The mask is enforced by this geometry alone (there are no
## invisible walls since iteration 48), so every boundary a blocked cell
## shares with an open one must be solid at capsule height. Two choices
## make that structural instead of likely: the facet step divides the cell
## size exactly, so every cell boundary is a row of mesh edges (a vertex on
## a boundary line is only ever jittered ALONG it); and the footprint always
## starts at least margin_min outside the boundary, where the cliff profile
## is already well above the ground. build() measures the second one on
## every boundary vertex and warns below SEAL_MIN_HEIGHT, which fails
## tools/verificar.sh.
##
## Built once, by the scatter's place_props(), after the terrain: every
## height here is relative to Terrain.height_at, so a formation sits on the
## relief instead of floating over a hollow.

## What the faces are drawn with when the scatter hands none over: white
## albedo multiplied by the per-facet vertex colours built below.
const DEFAULT_MATERIAL: Material = preload("res://assets/materials/rock_formation.tres")
## Sunk depth of the footprint's outer vertices, so the rock meets the
## relief with no visible seam.
const BURY_DEPTH: float = 0.8
## Floor of every collision prism under the ground: deep enough that no
## body standing on the terrain can slip under a prism's bottom face.
const PRISM_DEPTH: float = 1.6
## Jitter of a vertex off its grid slot, as a fraction of the step. Under
## 0.25 every quad stays convex in plan, which the prism hull relies on.
const JITTER: float = 0.22
## Interior distance stops being measured past this: the profile has
## flattened out long before.
const INTERIOR_CAP: float = 24.0
## Minimum rock height over the ground ON a cell boundary. The mask sweep's
## capsule spans 0-1.8 m above the ground there; anything above zero seals,
## and this keeps a margin over the noise and the terrain's curvature. The
## worst case of the default profile (margin_min, lift and crag both at
## their floor) is ~0.95 m.
const SEAL_MIN_HEIGHT: float = 0.75
## Strata bands per metre of height (sin argument), for strata_strength.
const STRATA_FREQUENCY: float = 3.1
## Below this face normal Y a facet is all rock; above CAP_TO it takes the
## full cap tint: the crest flanks rise at 20-35 degrees (normal Y
## 0.82-0.94), the cliff skirt at 50-70 (0.34-0.64).
const CAP_FROM: float = 0.8
const CAP_TO: float = 0.94
## Brightness of a vertical face against a flat one (slope shading).
const STEEP_SHADE: float = 0.58
## Brightness at the very foot, recovering to 1 by FOOT_HEIGHT metres up.
const FOOT_SHADE: float = 0.78
const FOOT_HEIGHT: float = 2.5
## +- per-facet brightness grain.
const GRAIN: float = 0.07
## Fraction of max_height where the soft ceiling starts to bend heights.
const KNEE: float = 0.75

## Mask geometry, copied from the scatter before build().
var cell_size: float = 10.0
var half_extent: float = 120.0
## Target facet size in metres; build() rounds it so it divides cell_size.
var mesh_step: float = 2.0
## Noisy distance the footprint reaches past the blocked cells.
var margin_min: float = 1.0
var margin_max: float = 2.0
## The cliff skirt: height reached over cliff_run metres inward of the
## footprint's edge, steepest at the foot.
var cliff_height: float = 2.6
var cliff_run: float = 2.0
## Extra height toward the crest: 1 - e^(-d / peak_run) of it, d being the
## depth past the cliff. Depth is distance to the region's outline, so the
## crest runs along the formation's spine — a ridge reads as a ridge.
var peak_height: float = 4.0
var peak_run: float = 7.0
## Summits: a ridged noise field that only grows where the rock is already
## deep, so peaks break the crest line instead of the cliff skirt.
var spire_height: float = 2.4
## Ceiling above the ground. EnemyBase.max_climb_height (10 m) caps a
## single scramble, and a face taller than that is one the horde gives up
## on halfway, so this stays under it. Approached through a soft knee from
## KNEE of it upward: a hard clamp sliced every summit that reached it into
## a flat table at exactly this height.
var max_height: float = 8.0
## +- fraction the whole profile swells or sags across the formation.
var lift_variation: float = 0.35
## Amplitude of the facet-scale noise that makes the surface craggy.
var crag_height: float = 0.6
## Ledges: their height, and how hard heights snap to them (0 = off).
var terrace_step: float = 1.6
var terrace_strength: float = 0.0
var rock_color: Color = Color(0.31, 0.32, 0.35)
var cap_color: Color = Color(0.25, 0.39, 0.2)
## How much of the cap tint a flat top takes (0 = bare rock everywhere).
var cap_strength: float = 0.65
## +- brightness of the horizontal bands (0 = none).
var strata_strength: float = 0.05
## Left null, DEFAULT_MATERIAL.
var surface_material: Material = null

## Stats for the scatter's one-line log, valid after build().
var face_count: int = 0
var prism_count: int = 0
## Boundary vertices that came out under SEAL_MIN_HEIGHT (should be 0).
var seal_low: int = 0
## Height of the tallest vertex over its own ground.
var tallest: float = 0.0

var _cells: Dictionary[Vector2i, bool] = {}
var _terrain: Terrain = null
var _step: float = 2.0
var _seed: int = 0
## The surface being assembled: one entry per facet corner, flat-shaded.
var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _lift_noise := FastNoiseLite.new()
var _crag_noise := FastNoiseLite.new()
var _edge_noise := FastNoiseLite.new()
var _spire_noise := FastNoiseLite.new()


## Raises the formation over `cells` (one connected region, grid coords of
## the scatter's mask). `noise_seed` is the run's seed, so BONK_GAME_SEED and
## the Daily Hunt reproduce the same rock as well as the same mask.
func build(cells: Dictionary[Vector2i, bool], terrain: Terrain, noise_seed: int) -> void:
	_cells = cells
	_terrain = terrain
	_seed = noise_seed
	_setup_noise(noise_seed)
	var per_cell := maxi(int(round(cell_size / maxf(mesh_step, 0.5))), 1)
	_step = cell_size / float(per_cell)
	# Footprint bounds, padded by the widest margin plus one step, snapped
	# outward to the global facet grid (which shares its origin with the
	# cell grid — that alignment is THE SEAL above).
	var low := Vector2i(1 << 30, 1 << 30)
	var high := Vector2i(-(1 << 30), -(1 << 30))
	for cell: Vector2i in _cells:
		low = Vector2i(mini(low.x, cell.x), mini(low.y, cell.y))
		high = Vector2i(maxi(high.x, cell.x), maxi(high.y, cell.y))
	var pad := margin_max + _step
	var first := Vector2i(
			floori((float(low.x) * cell_size - pad) / _step),
			floori((float(low.y) * cell_size - pad) / _step))
	var last := Vector2i(
			ceili((float(high.x + 1) * cell_size + pad) / _step),
			ceili((float(high.y + 1) * cell_size + pad) / _step))
	var columns := last.x - first.x + 1
	var rows := last.y - first.y + 1

	var tops := PackedVector3Array()
	var grounds := PackedFloat32Array()
	var heights := PackedFloat32Array()
	tops.resize(columns * rows)
	grounds.resize(columns * rows)
	heights.resize(columns * rows)
	for row in rows:
		for column in columns:
			var gx := first.x + column
			var gz := first.y + row
			var at := _vertex_xz(gx, gz, per_cell)
			var signed := _signed_distance(at)
			var depth := signed + _margin(at)
			var height := _profile(depth, at)
			var ground := _ground(at)
			var index := row * columns + column
			tops[index] = Vector3(at.x, ground + height, at.y)
			grounds[index] = ground
			heights[index] = height
			tallest = maxf(tallest, height)
			if absf(signed) < 0.001 and height < SEAL_MIN_HEIGHT:
				seal_low += 1

	var owner_id := create_shape_owner(self)
	for row in rows - 1:
		for column in columns - 1:
			var a := row * columns + column
			var b := a + 1
			var c := a + columns
			var d := c + 1
			if heights[a] < 0.0 and heights[b] < 0.0 and heights[c] < 0.0 and heights[d] < 0.0:
				continue
			var key := ((first.y + row) * 65536 + (first.x + column)) * 2
			# The HIGHER diagonal: the upper hull of the four corners, so the
			# prism below and the two faces drawn are the same surface.
			if tops[a].y + tops[d].y >= tops[b].y + tops[c].y:
				_emit(tops[a], tops[b], tops[d], heights[a] + heights[b] + heights[d], key)
				_emit(tops[a], tops[d], tops[c], heights[a] + heights[d] + heights[c], key + 1)
			else:
				_emit(tops[a], tops[b], tops[c], heights[a] + heights[b] + heights[c], key)
				_emit(tops[b], tops[d], tops[c], heights[b] + heights[d] + heights[c], key + 1)
			var hull := PackedVector3Array()
			for corner: int in [a, b, c, d]:
				hull.append(tops[corner])
				hull.append(Vector3(tops[corner].x, grounds[corner] - PRISM_DEPTH, tops[corner].z))
			var prism := ConvexPolygonShape3D.new()
			prism.points = hull
			shape_owner_add_shape(owner_id, prism)
			prism_count += 1
	if _vertices.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var view := MeshInstance3D.new()
	view.name = "Mesh"
	view.mesh = mesh
	view.material_override = surface_material if surface_material != null else DEFAULT_MATERIAL
	add_child(view)
	# The build buffers are dead weight once the mesh owns its copy.
	_vertices = PackedVector3Array()
	_normals = PackedVector3Array()
	_colors = PackedColorArray()


func _setup_noise(noise_seed: int) -> void:
	# Four fields from one seed: the profile's swell over tens of metres,
	# the facet-scale crags, the wobble of the footprint's outline and the
	# summits.
	_lift_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_lift_noise.seed = noise_seed
	_lift_noise.frequency = 1.0 / 28.0
	_lift_noise.fractal_octaves = 2
	_crag_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_crag_noise.seed = noise_seed + 1
	_crag_noise.frequency = 1.0 / 6.0
	_crag_noise.fractal_octaves = 2
	_edge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_edge_noise.seed = noise_seed + 2
	_edge_noise.frequency = 1.0 / 9.0
	_edge_noise.fractal_octaves = 2
	_spire_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_spire_noise.seed = noise_seed + 3
	_spire_noise.frequency = 1.0 / 16.0
	_spire_noise.fractal_octaves = 1


## World XZ of facet-grid vertex (gx, gz), jittered. A vertex sitting on a
## cell boundary line keeps that coordinate exactly (see THE SEAL).
func _vertex_xz(gx: int, gz: int, per_cell: int) -> Vector2:
	var x := -half_extent + float(gx) * _step
	var z := -half_extent + float(gz) * _step
	if posmod(gx, per_cell) != 0:
		x += (_hash01(gx, gz, _seed) - 0.5) * 2.0 * JITTER * _step
	if posmod(gz, per_cell) != 0:
		z += (_hash01(gx, gz, _seed + 17) - 0.5) * 2.0 * JITTER * _step
	return Vector2(x, z)


## Distance from `at` to the region's outline: positive inside (to the
## nearest cell NOT in this region, off-grid included), negative outside.
func _signed_distance(at: Vector2) -> float:
	var cell := Vector2i(floori((at.x + half_extent) / cell_size),
			floori((at.y + half_extent) / cell_size))
	if _cells.has(cell):
		var best := INTERIOR_CAP
		var reach := ceili(INTERIOR_CAP / cell_size)
		for ring in range(1, reach + 1):
			for dz in range(-ring, ring + 1):
				for dx in range(-ring, ring + 1):
					if maxi(absi(dx), absi(dz)) != ring:
						continue
					var other := cell + Vector2i(dx, dz)
					if not _cells.has(other):
						best = minf(best, _distance_to_cell(at, other))
			# Ring r+1 is at least r cells away: nothing past here can win.
			if best <= float(ring) * cell_size:
				break
		return best
	var nearest := INF
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var other := cell + Vector2i(dx, dz)
			if _cells.has(other):
				nearest = minf(nearest, _distance_to_cell(at, other))
	return -nearest


func _distance_to_cell(at: Vector2, cell: Vector2i) -> float:
	var half := cell_size * 0.5
	var center := Vector2(-half_extent + (float(cell.x) + 0.5) * cell_size,
			-half_extent + (float(cell.y) + 0.5) * cell_size)
	var dx := maxf(absf(at.x - center.x) - half, 0.0)
	var dz := maxf(absf(at.y - center.y) - half, 0.0)
	return sqrt(dx * dx + dz * dz)


## How far past the blocked cells the footprint reaches at `at`.
func _margin(at: Vector2) -> float:
	# FBM simplex rarely leaves +-0.7; stretched so the whole range is used.
	var wobble := clampf(_edge_noise.get_noise_2d(at.x, at.y) * 0.7 + 0.5, 0.0, 1.0)
	return lerpf(margin_min, margin_max, wobble)


## Rock height over the ground at `depth` metres inward of the footprint's
## edge (negative = outside it, i.e. sunk).
func _profile(depth: float, at: Vector2) -> float:
	if depth <= 0.0:
		return -BURY_DEPTH
	var rise := 1.0 - minf(depth / cliff_run, 1.0)
	var cliff := cliff_height * (1.0 - rise * rise)
	var crest := peak_height * (1.0 - exp(-maxf(depth - cliff_run, 0.0) / peak_run))
	var lift := 1.0 + lift_variation * _lift_noise.get_noise_2d(at.x, at.y)
	var height := (cliff + crest) * lift
	var ridge := 1.0 - absf(_spire_noise.get_noise_2d(at.x, at.y))
	height += spire_height * ridge * ridge * ridge * smoothstep(3.0, 9.0, depth)
	height += crag_height * _crag_noise.get_noise_2d(at.x, at.y) \
			* smoothstep(0.0, cliff_run, depth)
	if terrace_strength > 0.0 and terrace_step > 0.0:
		var level := height / terrace_step
		var ledge := (floorf(level) + smoothstep(0.3, 0.7, level - floorf(level))) * terrace_step
		height = lerpf(height, ledge, terrace_strength)
	var knee := max_height * KNEE
	if height > knee:
		var room := max_height - knee
		height = knee + room * tanh((height - knee) / room)
	return maxf(height, 0.0)


func _ground(at: Vector2) -> float:
	return _terrain.height_at(at.x, at.y) if _terrain != null else 0.0


## One flat-shaded facet. Godot's front face is CLOCKWISE seen from the
## front, so a facet seen from above must have its right-hand normal
## pointing DOWN — the same rule, and the same reason, as Terrain's ground.
## `height_sum` is the three corners' heights over the ground, summed.
func _emit(v0: Vector3, v1: Vector3, v2: Vector3, height_sum: float, key: int) -> void:
	var cross := (v1 - v0).cross(v2 - v0)
	if cross.y > 0.0:
		var swap := v1
		v1 = v2
		v2 = swap
		cross = -cross
	var normal := (-cross).normalized()
	var tint := _facet_color(normal, maxf(height_sum / 3.0, 0.0), key)
	for vertex: Vector3 in [v0, v1, v2]:
		_vertices.append(vertex)
		_normals.append(normal)
		_colors.append(tint)
	face_count += 1


## Rock on the faces, the cap tint on the gentle tops, steep faces darker
## than shallow ones, darker at the foot, banded by height and grained per
## facet. The slope shading is BAKED on purpose: under the arenas' bright
## sky ambient and fog the sun alone barely separates a cliff from a crest,
## and the first build read as one pale paper model.
func _facet_color(normal: Vector3, height: float, key: int) -> Color:
	var cap := smoothstep(CAP_FROM, CAP_TO, normal.y) * cap_strength
	var base := rock_color.lerp(cap_color, cap)
	var slope := lerpf(1.1, STEEP_SHADE, smoothstep(0.35, 0.95, 1.0 - normal.y))
	var foot := lerpf(FOOT_SHADE, 1.0, clampf(height / FOOT_HEIGHT, 0.0, 1.0))
	var band := 1.0 + strata_strength * sin(height * STRATA_FREQUENCY)
	var grain := 1.0 + (_hash01(key, 7, _seed) - 0.5) * 2.0 * GRAIN
	var value := slope * foot * band * grain
	return Color(base.r * value, base.g * value, base.b * value, 1.0)


## Deterministic hash of two ints and a salt into [0, 1]: vertex jitter and
## facet grain must not draw from any RNG stream, or two builds of the same
## seed would disagree.
static func _hash01(x: int, z: int, salt: int) -> float:
	var h := (x * 374761393 + z * 668265263 + salt * 1442695041) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	h = h ^ (h >> 16)
	return float(h & 0xffff) / 65535.0
