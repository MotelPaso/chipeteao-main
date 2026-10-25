extends Node
## Still camera for the arena's GROUND (iteration 63): boots a run, freezes
## it on its first frames, hides every CanvasLayer and photographs the
## terrain and the mask rock formations from fixed vantage points. Exists
## because the soak camera (BONK_SHOT_DIR on ArenaProbe) sees only what the
## walking raider happens to face, and a change to how the blocked regions
## LOOK needs the same formations shot from the same spots before and after.
##
##   BONK_ARENA=res://scenes/world/AshDunes.tscn BONK_GAME_SEED=7 \
##   BONK_SHOT_DIR="$TMPDIR/terrain/dunes" \
##   godot --path . --resolution 1280x720 res://scenes/tests/TerrainShots.tscn
##
## Env switches:
##   BONK_ARENA=res://...   biome (default: Hollow Woods), as in ArenaProbe
##   BONK_GAME_SEED=<int>   the run's stream, which seeds mask and relief —
##                          the switch that makes two shots comparable
##   BONK_SHOT_DIR=<dir>    where the PNGs go (REQUIRED; nothing is saved
##                          inside the project)
##   BONK_SAVE_PATH=<path>  scratch save, as in every harness
##
## Shots, in order:
##   map.png               orthographic, straight down, fog off: the layout
##   aerial.png            3/4 view of the whole arena, fog off
##   spawn.png             eye level from the party spawn, fog ON
##   formation_<n>.png     eye level, 26 m off one of the blocked regions
##                         nearest the spawn, fog ON — what a raider walking
##                         up to it sees
##   drone_<n>.png         the same region from 18 m up, fog ON
##
## Prints `Terrain shots: <map> formations=<n> props=<n> meshes=<n> blocked=<n>` and
## quits. Headless it saves nothing and says so, like ShotCamera.

const DEFAULT_ARENA := "res://scenes/world/HollowWoods.tscn"
const DEFAULT_SAVE_PATH := "user://terrain_shots_save.json"
const RUN_SCENE := "res://scenes/world/Run.tscn"
## Frames the run gets before it is frozen: the arena is dressed inside
## the add_child, but shadows and the first fade need a few drawn frames.
const WARMUP_FRAMES: int = 20
## Drawn frames between moving the camera and saving: the directional
## shadow cascades are fitted to the camera and lag it by a frame or two.
const SETTLE_FRAMES: int = 4
## Formations photographed at eye level, nearest the spawn first.
const FORMATION_SHOTS: int = 4
## Eye-level shots stand this far off the region's nearest cell centre.
const FORMATION_STANDOFF: float = 26.0
## Camera height above the ground at eye level: the player's spring arm
## (1.75 m pivot, 5 m arm) puts its lens roughly here.
const EYE_HEIGHT: float = 3.2
const DRONE_HEIGHT: float = 18.0
const PLAYER_FOV: float = 70.0

var _dir: String = ""
var _camera: Camera3D = null
var _environment: Environment = null


func _ready() -> void:
	_dir = OS.get_environment("BONK_SHOT_DIR").strip_edges()
	if _dir.is_empty():
		push_error("TerrainShots: BONK_SHOT_DIR is required")
		get_tree().quit(1)
		return
	if DisplayServer.get_name() == "headless":
		print("Shots skipped: headless")
		get_tree().quit(0)
		return
	DirAccess.make_dir_recursive_absolute(_dir)
	var save_override := OS.get_environment(SaveData.SAVE_PATH_ENV)
	SaveData.save_path = save_override if not save_override.is_empty() \
			else DEFAULT_SAVE_PATH
	SaveData.load_from_disk()
	var arena_path := OS.get_environment("BONK_ARENA")
	if arena_path.is_empty():
		arena_path = DEFAULT_ARENA
	GameConfig.start_map_id = _map_id_for_scene(arena_path)
	var scene := load(RUN_SCENE) as PackedScene
	if scene == null:
		push_error("TerrainShots: cannot load '%s'" % RUN_SCENE)
		get_tree().quit(1)
		return
	add_child(scene.instantiate())
	_shoot.call_deferred()


func _shoot() -> void:
	for frame in WARMUP_FRAMES:
		await get_tree().process_frame
	# Frozen: nothing spawns, nothing walks into the frame. Rendering goes
	# on while paused, and this node is PROCESS_MODE_ALWAYS in its scene.
	get_tree().paused = true
	_hide_canvas_layers(get_tree().root)
	var bounds := get_tree().get_first_node_in_group(&"arena_bounds") as Node3D
	var terrain := Terrain.find(get_tree())
	if bounds == null or terrain == null:
		push_error("TerrainShots: no arena_bounds or terrain in the run")
		get_tree().quit(1)
		return
	var world_environment := _find_world_environment(get_tree().root)
	if world_environment != null:
		_environment = world_environment.environment
	_camera = Camera3D.new()
	_camera.fov = PLAYER_FOV
	_camera.far = 900.0
	bounds.add_child(_camera)
	_camera.make_current()

	_set_fog(false)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = terrain.size + 10.0
	# North (-Z) up, the same orientation as the minimap.
	_camera.look_at_from_position(Vector3(0.0, 160.0, 0.0), Vector3.ZERO, Vector3.FORWARD)
	await _save("map")
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.look_at_from_position(Vector3(0.0, 120.0, 175.0), Vector3(0.0, 0.0, 12.0))
	await _save("aerial")
	_set_fog(true)

	var spawn_ground := terrain.height_at(0.0, 0.0)
	_camera.look_at_from_position(Vector3(0.0, spawn_ground + EYE_HEIGHT, 6.0),
			Vector3(0.0, spawn_ground + 2.0, -30.0))
	await _save("spawn")

	var formations := _formations(bounds)
	var shot := 0
	for formation: Dictionary in formations:
		if shot >= FORMATION_SHOTS:
			break
		var near: Vector2 = formation["near"]
		var centroid: Vector2 = formation["centroid"]
		var stand := _standoff(bounds, near)
		if stand == Vector2.INF:
			continue
		shot += 1
		var look_at := Vector3(centroid.x, terrain.height_at_xz(centroid) + 2.5, centroid.y)
		_camera.look_at_from_position(
				Vector3(stand.x, terrain.height_at_xz(stand) + EYE_HEIGHT, stand.y), look_at)
		await _save("formation_%d" % shot)
		var away := (stand - near).normalized()
		var drone := near + away * (FORMATION_STANDOFF * 0.8)
		_camera.look_at_from_position(
				Vector3(drone.x, terrain.height_at_xz(drone) + DRONE_HEIGHT, drone.y), look_at)
		await _save("drone_%d" % shot)

	print("Terrain shots: %s formations=%d props=%d meshes=%d blocked=%d" % [
			GameConfig.start_map_id, formations.size(), bounds.get_child_count() - 1,
			_count_meshes(bounds), int(bounds.call(&"blocked_cell_count"))])
	get_tree().quit(0)


## Connected regions of blocked cells (4-neighbour), nearest the spawn
## first: {centroid, near (the cell centre closest to the spawn), cells}.
func _formations(bounds: Node3D) -> Array[Dictionary]:
	var raw: Variant = bounds.call(&"blocked_cells")
	var blocked: Dictionary[Vector2i, bool] = {}
	if raw is Array:
		for cell: Vector2i in raw:
			blocked[cell] = true
	var seen: Dictionary[Vector2i, bool] = {}
	var out: Array[Dictionary] = []
	for start: Vector2i in blocked:
		if seen.has(start):
			continue
		var members: Array[Vector2i] = []
		var frontier: Array[Vector2i] = [start]
		seen[start] = true
		while not frontier.is_empty():
			var cell: Vector2i = frontier.pop_back()
			members.append(cell)
			for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var next := cell + dir
				if blocked.has(next) and not seen.has(next):
					seen[next] = true
					frontier.append(next)
		var sum := Vector2.ZERO
		var near := Vector2.INF
		for cell: Vector2i in members:
			var center: Vector2 = bounds.call(&"cell_center", cell)
			sum += center
			if center.length() < near.length():
				near = center
		out.append({"centroid": sum / float(members.size()), "near": near,
				"cells": members.size()})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return (a["near"] as Vector2).length() < (b["near"] as Vector2).length())
	return out


## A walkable spot FORMATION_STANDOFF off `near`, toward the spawn first and
## then around the compass. INF when the region is boxed in.
func _standoff(bounds: Node3D, near: Vector2) -> Vector2:
	var toward := (-near).normalized() if near.length() > 0.1 else Vector2.UP
	for turn in 8:
		var heading := toward.rotated(float(turn) * TAU / 8.0)
		var spot := near + heading * FORMATION_STANDOFF
		if bool(bounds.call(&"is_walkable", spot)):
			return spot
	return Vector2.INF


func _save(stem: String) -> void:
	for frame in SETTLE_FRAMES:
		await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := _dir.path_join(stem + ".png")
	var error := image.save_png(path)
	if error != OK:
		push_warning("TerrainShots: cannot save '%s' (%d)" % [path, error])


func _set_fog(on: bool) -> void:
	if _environment != null:
		_environment.fog_enabled = on


func _hide_canvas_layers(node: Node) -> void:
	if node is CanvasLayer:
		(node as CanvasLayer).visible = false
	for child: Node in node.get_children():
		_hide_canvas_layers(child)


func _find_world_environment(node: Node) -> WorldEnvironment:
	if node is WorldEnvironment:
		return node as WorldEnvironment
	for child: Node in node.get_children():
		var found := _find_world_environment(child)
		if found != null:
			return found
	return null


## MeshInstance3D nodes under the scatter (interior props, rock formations, the
## perimeter line, the mesas): the before/after of "not so many", and a
## fair proxy for what the scatter costs the renderer.
func _count_meshes(node: Node) -> int:
	var count := 1 if node is MeshInstance3D else 0
	for child: Node in node.get_children():
		count += _count_meshes(child)
	return count


func _map_id_for_scene(scene_path: String) -> String:
	for row: Dictionary in MapCatalog.MAP_LIBRARY:
		if String(row.scene_path) == scene_path:
			return String(row.id)
	return MapCatalog.DEFAULT_ID
