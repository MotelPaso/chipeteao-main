class_name Terrain
extends StaticBody3D
## The ground of an arena (iteration 51), replacing the flat 160x160 box
## every biome used to stand on. A soft heightmap of low amplitude — hills
## you walk over, hollows you drop into — plus the flat pads the authored
## verticality groups and the mesas sit on.
##
## Deliberately LOW relief. This is a bullet-heaven: the horde has no
## navmesh, it seeks in a straight line and climbs what blocks it, so
## terrain that can hide a raider or wall off a chase would break the
## chase, not enrich it. Amplitude is 1.5-3.0 m per biome; what the relief
## buys is readability (you can see where you are) and silhouette.
##
## Seeded from the SCATTER's per-run seed (`run_seed()`, valid from its
## _enter_tree onward), so BONK_SEED, BONK_GAME_SEED and the Daily Hunt all
## reproduce the same relief as the props standing on it.
##
## Lifecycle: built in _ready, which runs BEFORE Arena._ready (children
## first) and AFTER the scatter's _enter_tree, so the mask and the mesa
## sites already exist. Anything whose own _ready may run before this one
## (Backdrop is child #2, the arena's perimeter setup) calls ensure_built()
## first — it is idempotent.
##
## Null rule: consumers running from on_stage_started onward treat a null
## find() as a one-time push_error (the terrain should exist by then);
## construction-time consumers (Backdrop, HUD, the map overlay) tolerate
## null silently and (re)build when the stage starts.
##
## THE snapping rule for the whole project: nothing is placed at y = 0 any
## more. Every world placement goes through height_at().

@export var size: float = 240.0
## Peak-to-trough scale of the noise, per biome (forest 2.5, dunes 3.0,
## marsh 1.5). Overridden on the arena instances.
@export var amplitude: float = 2.5
## Wavelength of the main noise feature, in metres: how far apart hills
## are. Bigger = broader, lazier relief.
@export var feature_size: float = 45.0
@export var octaves: int = 3
## Lattice the noise is sampled on, then bilinearly interpolated up to the
## collider grid. Sampling all 241x241 collider points through
## FastNoiseLite from GDScript is the dominant cost of this node; a 2 m
## lattice cuts it to a quarter and the difference is invisible at this
## amplitude.
@export var noise_step: float = 2.0
## Flat disc under the party spawn, so nobody lands on a slope.
@export var spawn_flat_radius: float = 14.0
## Flat pad under each authored verticality group and each mesa site: a
## ramp has to meet level ground or it floats at one end.
@export var pad_radius: float = 8.0
## The noise fades to zero within this many metres of the edge, so the
## perimeter walls and the backdrop disc meet a flat rim.
@export var rim_flat_band: float = 10.0
## Render grid step. Coarser than the collider on purpose: at this
## amplitude the silhouette is identical and the mesh is a quarter of the
## triangles.
@export var mesh_step: float = 2.0
## The biome's ground material — the same ShaderMaterial the old flat
## floor box carried, moved onto this node in the arena scene. The floor
## shaders read WORLD XZ, and the mesh below carries world-XZ UVs, so they
## work here unchanged.
@export var surface_material: Material

## HeightMapShape3D is fixed at ONE WORLD UNIT PER SAMPLE and the node is
## kept unscaled, so the collider grid is 1 m and this is not tunable.
const SAMPLE_METERS: float = 1.0
## Blend distance around a flat pad: the pad is level inside its radius and
## eases back into the noise over this band.
const PAD_BLEND: float = 6.0
## Height shading of map_image(): how many metres of relief take the tint
## from darkest to brightest.
const MAP_SHADE_RANGE: float = 6.0

## Collider samples per side (241 for a 240 m arena at 1 m).
var _samples: int = 0
var _heights: PackedFloat32Array = PackedFloat32Array()
var min_height: float = 0.0
var max_height: float = 0.0
var _built: bool = false
## Flat discs applied after the noise: {center_xz, radius}. Filled from the
## spawn, the authored keepouts and the scatter's mesa sites.
var _pads: Array[Dictionary] = []
var _mesh_instance: MeshInstance3D = null
var _collision: CollisionShape3D = null


## THE accessor. Never a node path: an arena is swapped every stage.
static func find(tree: SceneTree) -> Terrain:
	if tree == null:
		return null
	return tree.get_first_node_in_group(&"terrain") as Terrain


func _enter_tree() -> void:
	# Claimed here, not in _ready: consumers that call ensure_built() from
	# their own _ready have to be able to FIND this node first.
	add_to_group(&"terrain")


func _ready() -> void:
	ensure_built()


## Builds the terrain exactly once. Public and idempotent because the
## build order across an arena scene is not something a consumer can
## assume: Backdrop is child #2 and reads min_height in its own _ready.
func ensure_built() -> void:
	if _built:
		return
	_built = true
	var started := Time.get_ticks_msec()
	_samples = int(round(size / SAMPLE_METERS)) + 1
	_collect_pads()
	_build_heights()
	_build_mesh()
	_build_collider()
	# One-line log (RunManager convention) for headless soaks: the relief
	# is invisible in a log otherwise, and a build that silently produced a
	# flat plate would look exactly like a healthy one.
	print("Terrain built: %s samples=%dx%d mesh_step=%.0f min=%.1f max=%.1f in %d ms" % [
			_biome_name(), _samples, _samples, mesh_step, min_height, max_height,
			Time.get_ticks_msec() - started])


## Height of the ground at a world XZ, bilinearly interpolated off the
## collider grid — the same numbers the physics body has, so a snapped
## prop can never hover or sink.
func height_at(x: float, z: float) -> float:
	if not _built or _samples <= 1:
		return 0.0
	var half := size * 0.5
	var fx := clampf((x + half) / SAMPLE_METERS, 0.0, float(_samples - 1))
	var fz := clampf((z + half) / SAMPLE_METERS, 0.0, float(_samples - 1))
	var ix := int(fx)
	var iz := int(fz)
	var nx := mini(ix + 1, _samples - 1)
	var nz := mini(iz + 1, _samples - 1)
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var h00 := _heights[iz * _samples + ix]
	var h10 := _heights[iz * _samples + nx]
	var h01 := _heights[nz * _samples + ix]
	var h11 := _heights[nz * _samples + nx]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## Convenience for the many callers holding a flat position.
func height_at_xz(xz: Vector2) -> float:
	return height_at(xz.x, xz.y)


## `position` dropped onto the ground.
func snap(position: Vector3) -> Vector3:
	return Vector3(position.x, height_at(position.x, position.z), position.z)


## Top-down picture of the relief for the minimap and the map overlay:
## the biome tint, shaded by height. `px_per_meter` is usually well below
## 1 (a 121 px map of 240 m is 0.5).
func map_image(px_per_meter: float) -> Image:
	var pixels := maxi(int(round(size * px_per_meter)), 8)
	var image := Image.create_empty(pixels, pixels, false, Image.FORMAT_RGBA8)
	var base := _biome_tint()
	var span := maxf(max_height - min_height, 0.001)
	for py in pixels:
		var z := (float(py) + 0.5) / float(pixels) * size - size * 0.5
		for px in pixels:
			var x := (float(px) + 0.5) / float(pixels) * size - size * 0.5
			# Height shading: -0.35 in the hollows, +0.35 on the peaks, so
			# the relief reads even on a 121 px map.
			var shade := clampf((height_at(x, z) - min_height) / span, 0.0, 1.0)
			var tint := base.lerp(base.lightened(0.45), shade)
			tint = tint.darkened(0.35 * (1.0 - shade))
			image.set_pixel(px, py, tint)
	return image


## Registers one more flat pad. Called by the scatter for its mesa sites
## BEFORE this node's _ready (the scatter picks them in _enter_tree).
func add_pad(center_xz: Vector2, radius: float) -> void:
	_pads.append({"center": center_xz, "radius": radius})


## --- build ---------------------------------------------------------------

## The spawn disc, plus one pad per authored verticality group. Deliberately
## NOT the shuffled POIs: the WorldDirector moves those to fresh XZ after
## this node is built, so a pad under their authored spot would be flat
## ground in the wrong place. They are snapped to the relief instead
## (world_director._shuffle_ground_interactables).
func _collect_pads() -> void:
	_pads.append({"center": Vector2.ZERO, "radius": spawn_flat_radius})
	for node: Node in get_tree().get_nodes_in_group(&"scatter_keepout"):
		var spot := node as Node3D
		if spot == null or spot is Interactable:
			continue
		if not _in_same_arena(spot):
			continue
		# In THIS node's space, which is the space the height grid is in:
		# an authored group is nested under Verticality, so its own
		# `position` is not arena-relative.
		var local := to_local(spot.global_position)
		_pads.append({"center": Vector2(local.x, local.z), "radius": pad_radius})
	# The scatter picked its mesa sites in _enter_tree, before this build.
	var bounds := get_tree().get_first_node_in_group(&"arena_bounds")
	if bounds != null and bounds.has_method(&"mesa_sites"):
		var sites: Variant = bounds.call(&"mesa_sites")
		if sites is PackedVector2Array:
			for site: Vector2 in sites:
				_pads.append({"center": site, "radius": pad_radius})


## True when `node` belongs to the same arena scene as this terrain: a
## stage swap can leave the outgoing arena in the tree for a frame, and
## its keepouts are not ours.
func _in_same_arena(node: Node) -> bool:
	var arena := _own_arena()
	return arena == null or arena.is_ancestor_of(node)


## The arena this terrain belongs to. Found by TYPE, not by the
## "arena_root" group: Arena claims that group in its _ready, which runs
## after this node's (children first), so during the build the group is
## still empty.
func _own_arena() -> Node:
	var node: Node = self
	while node != null and not (node is Arena):
		node = node.get_parent()
	return node


func _build_heights() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = _run_seed()
	noise.frequency = 1.0 / maxf(feature_size, 1.0)
	noise.fractal_octaves = maxi(octaves, 1)
	# Coarse lattice first (see noise_step), then bilinear up to 1 m.
	var lattice := maxi(int(ceil(size / maxf(noise_step, 0.5))) + 1, 2)
	var coarse := PackedFloat32Array()
	coarse.resize(lattice * lattice)
	var half := size * 0.5
	for lz in lattice:
		var z := -half + float(lz) * noise_step
		for lx in lattice:
			var x := -half + float(lx) * noise_step
			coarse[lz * lattice + lx] = noise.get_noise_2d(x, z) * amplitude
	_heights.resize(_samples * _samples)
	min_height = INF
	max_height = -INF
	for iz in _samples:
		var z := -half + float(iz) * SAMPLE_METERS
		for ix in _samples:
			var x := -half + float(ix) * SAMPLE_METERS
			var h := _sample_coarse(coarse, lattice, x, z)
			h *= _rim_falloff(x, z)
			h = _apply_pads(x, z, h)
			_heights[iz * _samples + ix] = h
			min_height = minf(min_height, h)
			max_height = maxf(max_height, h)
	if min_height == INF:
		min_height = 0.0
		max_height = 0.0


## Bilinear read of the coarse noise lattice at a world XZ.
func _sample_coarse(coarse: PackedFloat32Array, lattice: int, x: float, z: float) -> float:
	var half := size * 0.5
	var fx := clampf((x + half) / noise_step, 0.0, float(lattice - 1))
	var fz := clampf((z + half) / noise_step, 0.0, float(lattice - 1))
	var ix := int(fx)
	var iz := int(fz)
	var nx := mini(ix + 1, lattice - 1)
	var nz := mini(iz + 1, lattice - 1)
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var h00 := coarse[iz * lattice + ix]
	var h10 := coarse[iz * lattice + nx]
	var h01 := coarse[nz * lattice + ix]
	var h11 := coarse[nz * lattice + nx]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## 1 in the middle, easing to 0 inside rim_flat_band of the edge: the
## perimeter walls are authored statically and the backdrop disc is flat,
## so the ground has to be flat where they meet it.
func _rim_falloff(x: float, z: float) -> float:
	var half := size * 0.5
	var edge := minf(half - absf(x), half - absf(z))
	if edge >= rim_flat_band:
		return 1.0
	return smoothstep(0.0, 1.0, maxf(edge, 0.0) / maxf(rim_flat_band, 0.001))


## Flattens `h` toward 0 inside a pad, easing back to the noise over
## PAD_BLEND. The strongest pad wins, so overlapping pads do not stack.
func _apply_pads(x: float, z: float, h: float) -> float:
	var flat := 0.0
	for pad: Dictionary in _pads:
		var center: Vector2 = pad["center"]
		var radius: float = pad["radius"]
		var distance := Vector2(x, z).distance_to(center)
		if distance >= radius + PAD_BLEND:
			continue
		var strength := 1.0 if distance <= radius \
				else 1.0 - smoothstep(0.0, 1.0, (distance - radius) / PAD_BLEND)
		flat = maxf(flat, strength)
	return lerpf(h, 0.0, flat)


## Render mesh from packed arrays. SurfaceTool over a grid this size is
## hundreds of thousands of GDScript calls and takes seconds; this is one
## add_surface_from_arrays.
func _build_mesh() -> void:
	var cells := maxi(int(round(size / maxf(mesh_step, 0.5))), 2)
	var verts := cells + 1
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	vertices.resize(verts * verts)
	normals.resize(verts * verts)
	uvs.resize(verts * verts)
	var half := size * 0.5
	for iz in verts:
		var z := -half + float(iz) * mesh_step
		for ix in verts:
			var x := -half + float(ix) * mesh_step
			var index := iz * verts + ix
			vertices[index] = Vector3(x, height_at(x, z), z)
			# Analytic normal from the height differences either side: a
			# central difference over one mesh step, which is exactly the
			# slope the collider has.
			var dx := height_at(x + mesh_step, z) - height_at(x - mesh_step, z)
			var dz := height_at(x, z + mesh_step) - height_at(x, z - mesh_step)
			normals[index] = Vector3(-dx, 2.0 * mesh_step, -dz).normalized()
			# World-XZ UVs: the biome floor shaders read world position, so
			# the same material works unchanged on this mesh.
			uvs[index] = Vector2(x, z)
	var indices := PackedInt32Array()
	indices.resize(cells * cells * 6)
	var cursor := 0
	# WINDING. Godot's front face is the CLOCKWISE one seen from the front,
	# so a ground meant to be walked on has to be clockwise seen from +Y —
	# which is the same as saying cross(v1 - v0, v2 - v0) points DOWN.
	# Emitted the other way round (iterations 51-59) the whole terrain is
	# back-face culled from every camera above it: you fall onto a collider
	# you cannot see, the arena reads as a floating set of props over the
	# backdrop, and NOTHING says so in a log. That is exactly what shipped,
	# because every gate this project has runs --headless and the dummy
	# renderer rasterises nothing. _assert_winding below is the guard that
	# makes the mistake fail a headless soak from now on.
	for iz in cells:
		for ix in cells:
			var top_left := iz * verts + ix
			var top_right := top_left + 1
			var bottom_left := top_left + verts
			var bottom_right := bottom_left + 1
			indices[cursor] = top_left
			indices[cursor + 1] = top_right
			indices[cursor + 2] = bottom_left
			indices[cursor + 3] = top_right
			indices[cursor + 4] = bottom_right
			indices[cursor + 5] = bottom_left
			cursor += 6
	_assert_winding(vertices, indices)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh_instance = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "MeshInstance3D"
		add_child(_mesh_instance)
	_mesh_instance.mesh = mesh
	if surface_material != null:
		_mesh_instance.material_override = surface_material


## The one thing about this mesh a headless soak could not see until it
## was asserted: which way its triangles face. Checked on the FIRST
## triangle only — every cell is emitted by the same three lines, so one
## of them being upside down means all of them are.
##
## `up` here is the RIGHT-HAND normal of the triangle as listed. Godot
## culls the counter-clockwise side, so a face that is front-facing from
## above lists its vertices clockwise seen from +Y, and its right-hand
## normal therefore points DOWN. A positive Y is the bug.
func _assert_winding(vertices: PackedVector3Array, indices: PackedInt32Array) -> void:
	if indices.size() < 3:
		return
	var v0 := vertices[indices[0]]
	var v1 := vertices[indices[1]]
	var v2 := vertices[indices[2]]
	var up := (v1 - v0).cross(v2 - v0)
	if up.y >= 0.0:
		push_error("Terrain: ground triangles wound the wrong way — "
				+ "the whole surface is back-face culled from above")


## HeightMapShape3D on layer 1, one sample per world unit, node unscaled.
func _build_collider() -> void:
	var shape := HeightMapShape3D.new()
	shape.map_width = _samples
	shape.map_depth = _samples
	shape.map_data = _heights
	_collision = get_node_or_null("CollisionShape3D") as CollisionShape3D
	if _collision == null:
		_collision = CollisionShape3D.new()
		_collision.name = "CollisionShape3D"
		add_child(_collision)
	_collision.shape = shape


## The scatter's per-run seed, so the relief matches the props standing on
## it under BONK_SEED / BONK_GAME_SEED / the Daily Hunt. Falls back to a
## fixed number rather than a random one: a terrain that changed between
## two otherwise identical runs would make every soak comparison a lie.
func _run_seed() -> int:
	var bounds := get_tree().get_first_node_in_group(&"arena_bounds")
	if bounds != null and bounds.has_method(&"run_seed"):
		return int(bounds.call(&"run_seed"))
	return 0


## Ground tint for map_image(), taken from the biome's own backdrop so the
## map reads as the same place. Falls back to a neutral slate.
func _biome_tint() -> Color:
	var backdrop := _find_backdrop()
	if backdrop != null:
		var value: Variant = backdrop.get("ground_color")
		if value is Color:
			return value
	return Color(0.25, 0.27, 0.3)


func _find_backdrop() -> Node:
	var arena := _own_arena()
	return arena.get_node_or_null("Backdrop") if arena != null else null


## Name of the arena this terrain belongs to, for the build log.
func _biome_name() -> String:
	var arena := _own_arena() as Arena
	return arena.map_id if arena != null else name
