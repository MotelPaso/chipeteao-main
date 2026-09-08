class_name MapDraw
extends RefCounted
## The map both the minimap and the Tab overlay draw (iteration 52). One
## helper, two consumers: the picture, the fog compositing and the marker
## collection are identical for a 150 px corner widget and a half-screen
## overlay, and writing them twice is how the two would drift apart.
##
## Split of work, on purpose:
##   - build_background(arena)  once per stage: the terrain's own picture,
##     darkened where the arena mask blocks the ground.
##   - composite()              on the fog tick: background x fog into one
##     RGBA8 texture the consumer just blits.
##   - collect_markers()        on a 10 Hz timer: who is where, filtered
##     by what the fog has revealed.
## Every one of those is a plain method with no Control involved, so a
## headless soak exercises the whole thing whether or not _draw() is ever
## dispatched under the dummy renderer.

## THE marker table. A kind that is not here does not appear on the map,
## which is why `secret_trigger.gd` deliberately keeps an empty
## marker_kind: secrets stay secret.
##   color:          the dot's colour.
##   shape:          "dot" | "square" | "triangle" | "diamond".
##   size:           radius in map pixels at the overlay's scale.
##   always_visible: drawn even where the fog is still unexplored. Only
##                   the party and the way out: everything else is
##                   something you have to find.
## The last five rows are RESERVED for part C — power-ups, vendors, lucky
## blocks, the pet box and the event altar. C only has to set
## `marker_kind` on its node; nothing here changes.
const MARKER_STYLES: Dictionary[StringName, Dictionary] = {
	&"player": {"color": Color(0.45, 0.95, 1.0), "shape": "triangle",
		"size": 4.0, "always_visible": true},
	&"boss": {"color": Color(0.98, 0.35, 0.2), "shape": "diamond",
		"size": 5.0, "always_visible": false},
	&"chest": {"color": Color(1.0, 0.82, 0.35), "shape": "square",
		"size": 3.0, "always_visible": false},
	&"chest_free": {"color": Color(1.0, 0.93, 0.72), "shape": "square",
		"size": 3.0, "always_visible": false},
	&"altar": {"color": Color(0.4, 0.8, 1.0), "shape": "dot",
		"size": 3.5, "always_visible": false},
	&"altar_demonic": {"color": Color(1.0, 0.3, 0.25), "shape": "dot",
		"size": 3.5, "always_visible": false},
	&"altar_greed": {"color": Color(0.85, 0.55, 0.95), "shape": "dot",
		"size": 3.5, "always_visible": false},
	&"spring": {"color": Color(0.4, 0.9, 0.75), "shape": "dot",
		"size": 3.0, "always_visible": false},
	&"roulette": {"color": Color(0.95, 0.7, 0.3), "shape": "diamond",
		"size": 3.5, "always_visible": false},
	&"portal": {"color": Color(0.6, 0.85, 1.0), "shape": "diamond",
		"size": 3.0, "always_visible": false},
	&"exit": {"color": Color(1.0, 0.82, 0.35), "shape": "diamond",
		"size": 6.0, "always_visible": true},
	# Power-up on the ground (iteration 53). It draws in its own row's
	# colour through map_marker_color(), so a roaming star reads as a
	# different thing from a dropped Furia.
	&"powerup": {"color": Color(0.95, 0.95, 0.4), "shape": "dot",
		"size": 3.0, "always_visible": false},
	# Stalls and the pet box (iteration 54). A vendor draws in its own
	# kind's colour through map_marker_color() — but only once the fog has
	# found it, so the map never spoils which stall arrived.
	&"vendor": {"color": Color(0.9, 0.75, 0.5), "shape": "square",
		"size": 3.5, "always_visible": false},
	&"pet_box": {"color": Color(0.7, 0.95, 0.6), "shape": "square",
		"size": 3.5, "always_visible": false},
	# --- reserved for part C2 (see ARQUITECTURA, «Marcadores de mapa») ---
	&"lucky_block": {"color": Color(1.0, 0.6, 0.85), "shape": "square",
		"size": 3.0, "always_visible": false},
	&"event_altar": {"color": Color(0.8, 0.85, 1.0), "shape": "dot",
		"size": 3.5, "always_visible": false},
}

## Player-facing name per kind, for the overlay's legend. Kinds missing
## here simply do not get a legend row.
const MARKER_LABELS: Dictionary[StringName, String] = {
	&"player": "Jugadores",
	&"boss": "Jefe",
	&"chest": "Cofres",
	&"altar": "Altares",
	&"spring": "Manantial",
	&"roulette": "Ruleta",
	&"portal": "Portales",
	&"exit": "Salida",
	&"powerup": "Power-ups",
	&"vendor": "Vendedores",
	&"pet_box": "Caja de mascotas",
	&"event_altar": "Altar de eventos",
	&"lucky_block": "Bloque de la suerte",
}

## Alpha the unexplored ground is dimmed to in the composite. Not fully
## opaque: the shape of the map is a hint, what is ON it is the reward.
const FOG_ALPHA: float = 0.85
## Map pixels per metre of arena. 0.5 gives 240 px for a 240 m arena,
## which is plenty for a 150 px minimap and sharp enough at overlay size.
const PIXELS_PER_METER: float = 0.5
## Seconds between marker collections. Markers move (players, bosses); a
## 10 Hz refresh is invisible to the eye and free.
const MARKER_INTERVAL: float = 0.1

## Half-extent, in metres, of the arena this map covers.
var half_extent: float = 120.0
## The stage's ground picture, before fog.
var background: Image = null
## background x fog, ready to draw.
var texture: ImageTexture = null
## Latest marker snapshot: {position: Vector2 (world XZ), kind, color,
## heading (radians, players only)}.
var markers: Array[Dictionary] = []

var _composite: Image = null
var _tree: SceneTree = null


func _init(tree: SceneTree) -> void:
	_tree = tree


## Builds the stage's ground picture. Called once per stage, from whatever
## the consumer's stage hook is. A null terrain is not an error here —
## a HUD can be built before the first arena exists — it just yields a
## flat slate the composite still works on.
func build_background(_arena: Node3D = null) -> void:
	var terrain := Terrain.find(_tree)
	var bounds := _tree.get_first_node_in_group(&"arena_bounds")
	if bounds != null:
		var value: Variant = bounds.get("arena_half_extent")
		if value != null:
			half_extent = float(value)
	if terrain != null:
		terrain.ensure_built()
		half_extent = terrain.size * 0.5
		background = terrain.map_image(PIXELS_PER_METER)
	else:
		var pixels := maxi(int(round(half_extent * 2.0 * PIXELS_PER_METER)), 8)
		background = Image.create_empty(pixels, pixels, false, Image.FORMAT_RGBA8)
		background.fill(Color(0.16, 0.17, 0.2))
	_darken_blocked_cells(bounds)
	composite()


## Paints the arena mask's blocked cells darker, so the map shows the
## irregular shape of the stage instead of a clean square.
func _darken_blocked_cells(bounds: Node) -> void:
	if bounds == null or background == null or not bounds.has_method(&"blocked_cells"):
		return
	var cells: Variant = bounds.call(&"blocked_cells")
	if cells is not Array:
		return
	var cell_size := float(bounds.call(&"cell_size")) if bounds.has_method(&"cell_size") else 10.0
	var pixels := background.get_width()
	var scale := float(pixels) / maxf(half_extent * 2.0, 0.001)
	for cell: Vector2i in cells:
		var center: Vector2 = bounds.call(&"cell_center", cell)
		var origin := Vector2(center.x - cell_size * 0.5, center.y - cell_size * 0.5)
		var from := Vector2i(int(floor((origin.x + half_extent) * scale)),
				int(floor((origin.y + half_extent) * scale)))
		var span := maxi(int(round(cell_size * scale)), 1)
		for py in range(from.y, mini(from.y + span, pixels)):
			for px in range(from.x, mini(from.x + span, pixels)):
				if px < 0 or py < 0:
					continue
				background.set_pixel(px, py, background.get_pixel(px, py).darkened(0.55))


## background x fog into the drawable texture. Called on the fog's own
## tick by the consumer, never per frame.
func composite() -> void:
	if background == null:
		return
	var pixels := background.get_width()
	if _composite == null or _composite.get_width() != pixels:
		_composite = Image.create_empty(pixels, pixels, false, Image.FORMAT_RGBA8)
	var fog := FogOfWar.find(_tree)
	var fog_image: Image = fog.image if fog != null else null
	var fog_pixels := fog.pixels() if fog != null else 0
	for py in pixels:
		for px in pixels:
			var tint := background.get_pixel(px, py)
			if fog_image != null and fog_pixels > 0:
				# Nearest fog pixel: the fog grid is coarser than the map,
				# and interpolating a binary state only smears its edge.
				var fx := mini(px * fog_pixels / pixels, fog_pixels - 1)
				var fy := mini(py * fog_pixels / pixels, fog_pixels - 1)
				if fog_image.get_pixel(fx, fy).r < 0.5:
					tint = tint.darkened(FOG_ALPHA)
			_composite.set_pixel(px, py, tint)
	if texture == null:
		texture = ImageTexture.create_from_image(_composite)
	else:
		texture.update(_composite)


## Snapshot of every live marker, filtered by the fog. Players and the
## exit portal are always in; everything else has to have been found.
func collect_markers() -> void:
	markers = []
	var fog := FogOfWar.find(_tree)
	for node: Node in _tree.get_nodes_in_group(&"map_markers"):
		var body := node as Node3D
		if body == null or not body.is_inside_tree():
			continue
		if not body.has_method(&"map_marker_kind"):
			continue
		var kind: StringName = body.call(&"map_marker_kind")
		if kind.is_empty() or not MARKER_STYLES.has(kind):
			continue
		# A spent altar or an opened chest is not somewhere to walk to.
		var available: Variant = body.get("available")
		if available is bool and not bool(available):
			continue
		var at := Vector2(body.global_position.x, body.global_position.z)
		var style: Dictionary = MARKER_STYLES[kind]
		if not bool(style["always_visible"]) and fog != null and not fog.is_explored(at):
			continue
		var color: Color = style["color"]
		if body.has_method(&"map_marker_color"):
			color = body.call(&"map_marker_color")
		markers.append({
			"position": at,
			"kind": kind,
			"color": color,
			# Players draw as an arrow pointing where they face; everything
			# else ignores this.
			"heading": body.global_rotation.y,
		})


func marker_count() -> int:
	return markers.size()


## World XZ -> a point inside `rect`, north up. THE projection both
## consumers use, so a marker can never land somewhere the ground does
## not.
func to_screen(xz: Vector2, rect: Rect2) -> Vector2:
	var span := maxf(half_extent * 2.0, 0.001)
	return rect.position + Vector2(
			(xz.x + half_extent) / span * rect.size.x,
			(xz.y + half_extent) / span * rect.size.y)


## Draws the composite and every marker into `rect` of `canvas`. Both
## consumers call this from their own _draw; everything it needs was
## computed by the methods above.
func draw_into(canvas: CanvasItem, rect: Rect2, marker_scale: float = 1.0) -> void:
	if texture != null:
		canvas.draw_texture_rect(texture, rect, false)
	for marker: Dictionary in markers:
		var at := to_screen(marker["position"], rect)
		var style: Dictionary = MARKER_STYLES[marker["kind"] as StringName]
		var size: float = float(style["size"]) * marker_scale
		var color: Color = marker["color"]
		match String(style["shape"]):
			"square":
				canvas.draw_rect(Rect2(at - Vector2(size, size), Vector2(size, size) * 2.0),
						color, true)
			"diamond":
				canvas.draw_colored_polygon(PackedVector2Array([
						at + Vector2(0.0, -size), at + Vector2(size, 0.0),
						at + Vector2(0.0, size), at + Vector2(-size, 0.0)]), color)
			"triangle":
				var heading: float = marker["heading"]
				# The raider's arrow points where they are looking: on a
				# 240 m map, "which way am I facing" is most of the value.
				var tip := at + Vector2(sin(heading), -cos(heading)) * size * 1.6
				var left := at + Vector2(sin(heading + 2.4), -cos(heading + 2.4)) * size
				var right := at + Vector2(sin(heading - 2.4), -cos(heading - 2.4)) * size
				canvas.draw_colored_polygon(PackedVector2Array([tip, left, right]), color)
			_:
				canvas.draw_circle(at, size, color)
