extends Node3D
## Spawns grunts on a timer in a ring around the player, off-screen-ish.
## Difficulty ramps with elapsed run time: the interval shrinks and the
## per-tick count grows (GDD 6: swarms scale over the run timer). Spawned
## grunts are added as children, so the active count is just child count.

@export var grunt_scene: PackedScene
@export var max_active: int = 80
@export_group("Spawn Ring")
@export var min_radius: float = 18.0
@export var max_radius: float = 25.0
## Half-size of the floor plate, minus a margin, so ring spawns near an
## arena edge still land on the floor.
@export var arena_half_extent: float = 48.0
@export_group("Difficulty Ramp")
@export var start_interval: float = 2.5
@export var min_interval: float = 0.4
@export var interval_shrink_per_minute: float = 0.35
@export var base_count_per_tick: int = 1
@export var extra_count_per_minute: float = 0.5

## Elapsed run time in seconds; the HUD run timer will read this later.
var run_time: float = 0.0

var _spawn_timer: float = 0.0  # starts due, so the action begins immediately


func _physics_process(delta: float) -> void:
	run_time += delta
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = current_interval()
	var budget := mini(current_count_per_tick(), max_active - get_child_count())
	for i in budget:
		_spawn_one()


func current_interval() -> float:
	var minutes := run_time / 60.0
	return maxf(start_interval - interval_shrink_per_minute * minutes, min_interval)


func current_count_per_tick() -> int:
	var minutes := run_time / 60.0
	return base_count_per_tick + int(minutes * extra_count_per_minute)


func _spawn_one() -> void:
	if grunt_scene == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var angle := randf() * TAU
	var pos := player.global_position \
			+ Vector3(cos(angle), 0.0, sin(angle)) * randf_range(min_radius, max_radius)
	pos.x = clampf(pos.x, -arena_half_extent, arena_half_extent)
	pos.z = clampf(pos.z, -arena_half_extent, arena_half_extent)
	pos.y = _ground_height(pos, player) + 0.05
	var grunt := grunt_scene.instantiate() as Node3D
	add_child(grunt)
	grunt.global_position = pos


## Drops the spawn point onto whatever world geometry (layer 1) is below it —
## forest floor, boulder, platform deck — so a ring position that lands on a
## Hollow Woods prop never embeds a grunt inside it. Tree canopies carry no
## collision, so under-canopy spawns still hit the floor. Falls back to the
## flat-floor height if the ray somehow misses everything.
func _ground_height(pos: Vector3, player: Node3D) -> float:
	var ray := PhysicsRayQueryParameters3D.create(
			Vector3(pos.x, 12.0, pos.z), Vector3(pos.x, -1.0, pos.z), 1)
	var player_body := player as CollisionObject3D
	if player_body != null:
		# The player is also on layer 1; never spawn a grunt on their head.
		var excluded: Array[RID] = [player_body.get_rid()]
		ray.exclude = excluded
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return 0.0
	var hit_position: Vector3 = hit["position"]
	return hit_position.y
