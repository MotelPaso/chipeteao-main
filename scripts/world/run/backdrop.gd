extends Node3D
## Arena backdrop (iteration 34): kills the floating-island look. The
## floor plate used to end in a hard edge with nothing but procedural sky
## beyond it; this node surrounds it with cheap distant dressing that the
## existing environment fog already blends into the horizon:
##
## - A huge flat ground disc a hair below the play floor, in the biome's
##   ground tint, so looking past the walls reads as "the land continues".
## - A ring of low-poly silhouette hills (squashed spheres) outside the
##   perimeter at two depths, tinted darker with distance, so the horizon
##   has a shape instead of a straight seam.
##
## Everything is built in code at ready (no collision, one material per
## ring), tinted via exports so each biome instance colors its own world.
## Seeded from the run's randomized scatter? No — hills are far enough
## that a fresh random ring each run is free variety.

@export_group("Distant Ground")
@export var ground_color: Color = Color(0.22, 0.33, 0.2)
@export var ground_size: float = 1000.0
## Just below the play floor so the edges never z-fight.
@export var ground_drop: float = 0.35

@export_group("Horizon Hills")
@export var hill_color: Color = Color(0.16, 0.26, 0.17)
## The far ring sits deeper in the fog and a shade darker.
@export var far_hill_color: Color = Color(0.13, 0.21, 0.15)
@export var hill_count: int = 22
@export var far_hill_count: int = 14
## Ring bands as MULTIPLES of the arena half-extent, which the scatter
## node publishes through the "arena_bounds" group (the project's single
## source of arena size). Absolute metres used to live here, and the
## resize to 160x160 left the near ring biting 20 m into the play field.
@export var near_ring_min_factor: float = 1.6
@export var near_ring_max_factor: float = 2.1
@export var far_ring_min_factor: float = 2.6
@export var far_ring_max_factor: float = 3.4
@export var hill_height_min: float = 6.0
@export var hill_height_max: float = 20.0
@export var hill_width_min: float = 18.0
@export var hill_width_max: float = 46.0

## Far-ring hills are inflated so they still read through the fog.
const FAR_RING_SCALE_BOOST: float = 1.6
## Extra metres a dome keeps between its own edge and the arena wall.
const WALL_CLEARANCE: float = 4.0

var _half_extent: float = 80.0


func _ready() -> void:
	_half_extent = _arena_half_extent()
	_settle_ground_drop()
	_build_ground()
	_build_hill_ring(hill_count, near_ring_min_factor, near_ring_max_factor,
			_hill_material(hill_color))
	_build_hill_ring(far_hill_count, far_ring_min_factor, far_ring_max_factor,
			_hill_material(far_hill_color), FAR_RING_SCALE_BOOST)


## Arena half-size from the "arena_bounds" node (scatter), the same way
## BossBase and EnemySpawner read it. Every sibling has joined its groups
## by now: groups are claimed in _enter_tree, which runs for the whole
## scene before any _ready.
func _arena_half_extent() -> float:
	var bounds := get_tree().get_first_node_in_group("arena_bounds")
	if bounds == null:
		return _half_extent
	var value: Variant = bounds.get("arena_half_extent")
	return float(value) if value != null else _half_extent


## The distant disc has to clear the DEEPEST hollow, not the old flat
## floor (iteration 51). Terrain.ensure_built() is called explicitly:
## this node is child #2 of the arena and its _ready runs long before the
## terrain's, so min_height would otherwise still be 0.
func _settle_ground_drop() -> void:
	var terrain := Terrain.find(get_tree())
	if terrain == null:
		return
	terrain.ensure_built()
	ground_drop = -terrain.min_height + ground_drop


func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(ground_size, ground_size)
	ground.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = ground_color
	material.roughness = 1.0
	ground.material_override = material
	ground.position.y = -ground_drop
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)


## One ring of randomly sized squashed-sphere hills between the radii
## (given as multiples of the arena half-extent). scale_boost inflates the
## far ring so it still reads through the fog.
func _build_hill_ring(count: int, min_factor: float, max_factor: float,
		material: StandardMaterial3D, scale_boost: float = 1.0) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	for i in count:
		var hill := MeshInstance3D.new()
		hill.mesh = mesh
		hill.material_override = material
		hill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var angle := TAU * float(i) / float(count) + randf_range(-0.12, 0.12)
		var width := randf_range(hill_width_min, hill_width_max) * scale_boost
		var height := randf_range(hill_height_min, hill_height_max) * scale_boost
		var depth := width * randf_range(0.7, 1.0)
		var distance := maxf(randf_range(min_factor, max_factor) * _half_extent,
				_clear_distance(angle, width, depth))
		hill.position = Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
		# Sphere center at ground level: only the top half shows, so each
		# hill is a clean dome without a visible underside.
		hill.scale = Vector3(width, height, depth)
		hill.rotation.y = randf() * TAU
		add_child(hill)


## Nearest distance along `angle` at which a dome of these half-widths
## still sits fully outside the play square. The scale is applied to a
## unit-RADIUS sphere, so `width` is the dome's half-width in metres, not
## its diameter — reading it as a diameter is what put 46 m domes on top
## of the arena corners.
func _clear_distance(angle: float, width: float, depth: float) -> float:
	var cos_a := absf(cos(angle))
	var sin_a := absf(sin(angle))
	var limit := _half_extent + WALL_CLEARANCE
	# Clearing EITHER axis puts the dome's bounding box outside the
	# square, so the cheaper of the two wins.
	var by_x := (limit + width) / cos_a if cos_a > 0.001 else INF
	var by_z := (limit + depth) / sin_a if sin_a > 0.001 else INF
	return minf(by_x, by_z)


func _hill_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material
