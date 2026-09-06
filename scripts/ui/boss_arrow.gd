extends Node2D
## Screen-edge boss indicator: while any "boss"-group body is alive but
## off-screen (or behind the camera plane), an amber arrow clamped inside
## the screen edges points toward it, so players can re-find a fight they
## kited away from. Tracks the nearest live boss — dead bosses leave the
## group the moment they die, which hides the arrow with no extra wiring —
## and works for the hidden minibosses (same group). Lives inside the HUD
## layer; every camera/viewport lookup is guarded, so headless runs and
## camera-less scenes never crash.
##
## One arrow serves the whole window today. SplitScreen can instead give
## each cell its own with bind_view(camera, carrier); until it does, the
## co-op fallback aims through the first split-screen camera it finds and
## offsets the result by that cell's corner.

## Distance (px) the arrow tip keeps from the screen edges.
@export var edge_margin: float = 56.0
## Inset (px) inside the viewport that still counts as "on-screen": keeps
## the arrow from flickering while a boss rides the exact frame edge.
@export var on_screen_inset: float = 24.0
## World-space aim height above the boss origin (chest, not feet).
@export var aim_height: float = 1.2

## Seconds between attempts to find a split-screen camera while none is
## resolved. The scan walks the tree, so it never runs per frame — and
## never runs at all in solo, where the root viewport has its own camera.
const CAMERA_RESCAN := 0.5

## Injected view (see bind_view): the camera this arrow aims through and
## the raider it measures distances from. Both null = solo fallbacks.
var _camera: Camera3D = null
var _carrier: Node3D = null
## Cached co-op fallback camera, re-scanned at most every CAMERA_RESCAN.
var _fallback_camera: Camera3D = null
var _rescan_left: float = 0.0


func _ready() -> void:
	visible = false


## Split-screen entry point: one arrow per view, each aiming through THAT
## view's camera and measuring from THAT view's raider. Without it the
## arrow falls back to the root viewport's camera (solo) and to the lowest
## standing slot.
func bind_view(camera: Camera3D, carrier: Node3D) -> void:
	_camera = camera
	_carrier = carrier


func _process(delta: float) -> void:
	var camera := _resolve_camera(delta)
	if camera == null:
		visible = false
		return
	var view := camera.get_viewport()
	var boss := _nearest_live_boss(_resolve_reference())
	if boss == null or view == null:
		visible = false
		return
	var target := boss.global_position + Vector3.UP * aim_height
	var placement := compute_placement(camera.unproject_position(target),
			camera.is_position_behind(target), view.get_visible_rect().size)
	visible = bool(placement["visible"])
	if visible:
		# Placement is in the CAMERA's viewport space; in split-screen that
		# is one cell of the window, so it shifts by the cell's origin.
		position = (placement["position"] as Vector2) + _view_origin(view)
		rotation = float(placement["angle"])


## The camera to aim through: the injected one, else the root viewport's
## (solo), else the first live split-screen view. That last fallback is
## what keeps the arrow alive in co-op at all: every player camera is
## deactivated in favour of a per-SubViewport follow camera
## (player.gd/SplitScreen), so the root viewport has NO active camera and
## the plain get_camera_3d() answer is null for the whole run.
func _resolve_camera(delta: float) -> Camera3D:
	if is_instance_valid(_camera):
		return _camera
	var viewport := get_viewport()
	var camera := viewport.get_camera_3d() if viewport != null else null
	if camera != null:
		return camera
	if is_instance_valid(_fallback_camera) and _fallback_camera.is_inside_tree():
		return _fallback_camera
	_rescan_left -= delta
	if _rescan_left > 0.0:
		return null
	_rescan_left = CAMERA_RESCAN
	_fallback_camera = _find_split_view_camera()
	return _fallback_camera


func _find_split_view_camera() -> Camera3D:
	var tree := get_tree()
	if tree == null:
		return null
	for node: Node in tree.root.find_children("*", "SubViewport", true, false):
		var camera := (node as SubViewport).get_camera_3d()
		if camera != null:
			return camera
	return null


## Window-space origin of a viewport: zero for the root, the cell's own
## corner for a SubViewport hosted in a SubViewportContainer.
func _view_origin(view: Viewport) -> Vector2:
	var container := view.get_parent() as SubViewportContainer
	return container.global_position if container != null else Vector2.ZERO


## The body distances are measured from: the injected carrier, else the
## LOWEST STANDING SLOT. Never get_first_node_in_group("player") — a
## downed raider leaves the group and a revived one re-enters at the back,
## so that order changes mid-run and the arrow would jump between bosses
## for no reason the players can see.
func _resolve_reference() -> Node3D:
	if is_instance_valid(_carrier):
		return _carrier
	var tree := get_tree()
	if tree == null:
		return null
	var best: Node3D = null
	var best_slot := Coop.MAX_PLAYERS
	for node: Node in tree.get_nodes_in_group(&"player"):
		var body := node as Node3D
		if body == null:
			continue
		var slot := int(body.get("player_index"))
		if slot < best_slot:
			best_slot = slot
			best = body
	return best


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


## Nearest in-tree member of the "boss" group, measured from `reference`
## when there is one (two bosses alive is rare but possible: miniboss plus
## the timetable boss). A null reference keeps every boss at distance 0,
## so the first one in the group wins — enough for a camera-less harness.
func _nearest_live_boss(reference: Node3D) -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
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
