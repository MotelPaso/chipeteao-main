class_name Minimap
extends Control
## North-up minimap (iteration 52), one per player view. Draws MapDraw's
## composite — the stage's relief, darkened where the arena mask blocks
## it, dimmed where the fog is still unexplored — plus the markers that
## the fog has revealed.
##
## Regular enemies are NEVER drawn. A minimap dotted with forty grunts is
## noise, and the horde is the thing the player is already looking at; what
## the map is for is what you CANNOT see from where you stand: the chest
## two hills over, the altar you have not charged, the way out.
##
## Rebuilt from WorldDirector.on_stage_started (relayed by the HUD), not
## from the stage_changed signal: that call is what stage 0 goes through
## too, so the first stage needs no special case.

## Side of the widget, in pixels.
const SIZE: float = 150.0
## Inset of the map inside its frame.
const FRAME_PAD: float = 3.0
## Markers are drawn smaller here than on the full-screen overlay.
const MARKER_SCALE: float = 0.75
## Seconds between marker collections and composite checks. The fog
## itself paints on its own slower tick; this is what turns it into a
## picture — when it changed (see _composite_if_changed).
const REFRESH: float = 0.1

var _map: MapDraw = null
var _refresh_left: float = 0.0
## composite_key() as of the last composite this widget ran. Empty means
## "unknown": the next refresh composites whatever the key says.
var _composited: Array = []


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	# Never eats a click meant for the world, and never takes focus (Tab
	# has to reach the overlay, not walk the focus chain).
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_map = MapDraw.new(get_tree())
	_map.build_background()


## Stage hook, relayed by the HUD from WorldDirector.on_stage_started.
func on_stage_started(_arena: Node3D = null) -> void:
	if _map == null:
		_map = MapDraw.new(get_tree())
	_map.build_background()
	# build_background rewrites the picture's pixels, and the key cannot see
	# an edit made inside an Image it already knows: forget it, so the next
	# refresh composites unconditionally.
	_composited = []
	_map.collect_markers()
	queue_redraw()


func _process(delta: float) -> void:
	if _map == null:
		return
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = REFRESH
	# Both are plain methods with no Control involved, so a headless soak
	# exercises the map even where _draw() is never dispatched. Markers move
	# every tick and are always collected; the composite only when its
	# inputs moved.
	_map.collect_markers()
	_composite_if_changed()
	queue_redraw()


## MapDraw.composite() is a pure function of the background Image and the
## fog image: a 14 400-pixel get_pixel/set_pixel loop (~1.5 ms of GDScript)
## that, run unconditionally, was most of this widget's cost and a spike
## every sixth frame. The fog only changes when a raider steps onto ground
## nobody has seen, so on most ticks the texture it would upload is the
## one already on screen.
func _composite_if_changed() -> void:
	var key := composite_key(_map, get_tree())
	if key == _composited:
		return
	_composited = key
	_map.composite()


## Everything MapDraw.composite() reads, as one comparable value: the
## background Image the map holds (build_background swaps in a new one per
## stage), the fog node, and that fog's revision (which moves exactly when
## its image does). Equal keys mean composite() would write the very pixels
## it wrote last time. Edits INSIDE the background are not visible here,
## which is why every build_background call also clears the caller's key.
## Static and shared with MapOverlay, so the two consumers cannot disagree
## about when their picture is stale.
static func composite_key(map: MapDraw, tree: SceneTree) -> Array:
	var fog := FogOfWar.find(tree)
	return [
		map.background.get_instance_id() if map.background != null else 0,
		fog.get_instance_id() if fog != null else 0,
		fog.revision if fog != null else -1,
	]


func marker_count() -> int:
	return _map.marker_count() if _map != null else 0


func _draw() -> void:
	if _map == null:
		return
	var frame := Rect2(Vector2.ZERO, size)
	draw_rect(frame, Color(0.05, 0.055, 0.08, 0.85), true)
	var inner := Rect2(Vector2(FRAME_PAD, FRAME_PAD),
			size - Vector2(FRAME_PAD, FRAME_PAD) * 2.0)
	_map.draw_into(self, inner, MARKER_SCALE)
	draw_rect(frame, UiTheme.ACCENT.darkened(0.2), false, 2.0)
