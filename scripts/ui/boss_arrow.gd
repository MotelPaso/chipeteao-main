extends Node2D
## Screen-edge boss indicator: while any "boss"-group body is alive but
## off-screen (or behind the camera plane), an amber arrow clamped inside
## the screen edges points toward it, so players can re-find a fight they
## kited away from. Tracks the nearest live boss — dead bosses leave the
## group the moment they die, which hides the arrow with no extra wiring —
## and works for the hidden minibosses (same group). Lives inside the HUD
## layer; every camera/viewport lookup is guarded, so headless runs and
## camera-less scenes never crash.

## Distance (px) the arrow tip keeps from the screen edges.
@export var edge_margin: float = 56.0
## Inset (px) inside the viewport that still counts as "on-screen": keeps
## the arrow from flickering while a boss rides the exact frame edge.
@export var on_screen_inset: float = 24.0
## World-space aim height above the boss origin (chest, not feet).
@export var aim_height: float = 1.2


func _ready() -> void:
	visible = false


func _process(_delta: float) -> void:
	var boss := _nearest_live_boss()
	var viewport := get_viewport()
	var camera := viewport.get_camera_3d() if viewport != null else null
	if boss == null or camera == null:
		visible = false
		return
	var target := boss.global_position + Vector3.UP * aim_height
	var placement := compute_placement(camera.unproject_position(target),
			camera.is_position_behind(target), viewport.get_visible_rect().size)
	visible = bool(placement["visible"])
	if visible:
		position = placement["position"] as Vector2
		rotation = float(placement["angle"])


## Pure screen math, separated so a headless harness can verify it: given
## the camera-unprojected target, whether the target sits behind the
## camera plane, and the viewport size, returns {"visible": bool,
## "position": Vector2, "angle": float}. Off-screen targets clamp to the
## edge_margin rect along the ray from the screen center; the arrow's art
## points +X, so the angle of that ray is also the node rotation.
func compute_placement(unprojected: Vector2, behind: bool,
		viewport_size: Vector2) -> Dictionary:
	var center := viewport_size * 0.5
	var pos := unprojected
	if behind:
		# unproject mirrors targets behind the camera plane; mirror back
		# through the center so the arrow points the way you would turn.
		pos = center * 2.0 - pos
	if not behind and Rect2(Vector2.ZERO, viewport_size) \
			.grow(-on_screen_inset).has_point(pos):
		return {"visible": false, "position": Vector2.ZERO, "angle": 0.0}
	var dir := pos - center
	if dir.length_squared() < 0.0001:
		dir = Vector2.DOWN  # dead-center behind the camera: "it's behind you"
	dir = dir.normalized()
	# Scale the center ray to the first margin-rect edge it crosses.
	var half := center - Vector2(edge_margin, edge_margin)
	half.x = maxf(half.x, 4.0)
	half.y = maxf(half.y, 4.0)
	var t := INF
	if absf(dir.x) > 0.0001:
		t = minf(t, half.x / absf(dir.x))
	if absf(dir.y) > 0.0001:
		t = minf(t, half.y / absf(dir.y))
	return {"visible": true, "position": center + dir * t, "angle": dir.angle()}


## Nearest in-tree member of the "boss" group, measured from the player
## when one exists (two bosses alive is rare but possible: miniboss plus
## the timetable boss).
func _nearest_live_boss() -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
	var reference := tree.get_first_node_in_group(&"player") as Node3D
	var best: Node3D = null
	var best_distance := INF
	for node: Node in tree.get_nodes_in_group(&"boss"):
		var boss := node as Node3D
		if boss == null or not boss.is_inside_tree():
			continue
		var distance := 0.0
		if reference != null:
			distance = boss.global_position.distance_squared_to(reference.global_position)
		if distance < best_distance:
			best_distance = distance
			best = boss
	return best
