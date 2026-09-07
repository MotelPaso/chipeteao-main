class_name FogOfWar
extends Node
## Fog of war (iteration 52): what the party has SEEN of the current stage.
## A child of RunSystems.tscn, so it survives the arena swap like the rest
## of the run block and is reset per stage by the WorldDirector.
##
## Shared by the whole party on purpose: in co-op, four raiders exploring
## four corners are exploring ONE map. Run-scoped only — nothing about it
## persists between runs.
##
## The authoritative state is a single-channel L8 Image: 255 explored,
## 0 unknown. Painting is a disc per live raider on a slow tick, which is
## cheap enough to leave running (a 121x121 image and a radius of 9 pixels
## is a few hundred set_pixel calls every fifth of a second) and precise
## enough that the map reads as "where we walked".
##
## MapDraw composites this into the picture the minimap and the overlay
## draw; nothing outside this node writes to the image.

## Metres per fog pixel. 2 m gives 121x121 for a 240 m arena: coarse
## enough to paint cheaply, fine enough that a corridor between two mask
## blobs reads as explored rather than as one fat blur.
@export var meters_per_pixel: float = 2.0
## How far a raider reveals around themselves, in metres.
@export var reveal_radius: float = 18.0
## Seconds between paint passes. Not per frame: at walking speed a raider
## covers under a metre in this time, which is a third of a fog pixel.
@export var paint_interval: float = 0.2

## The authoritative state. FORMAT_L8: one byte per pixel, no alpha —
## MapDraw is what turns it into something drawable.
var image: Image = null

var _pixels: int = 0
## Half-extent of the arena the current image covers, in metres.
var _half_extent: float = 120.0
var _paint_left: float = 0.0
## Explored pixels, kept as a running count so explored_fraction() is not
## a full scan of the image on every HUD refresh.
var _explored_pixels: int = 0


## THE accessor, like every other cross-scene lookup in this project.
static func find(tree: SceneTree) -> FogOfWar:
	if tree == null:
		return null
	return tree.get_first_node_in_group(&"fog") as FogOfWar


func _ready() -> void:
	add_to_group(&"fog")
	# A fog with no arena yet is a fog of nothing; reset_for_stage builds
	# the real one the moment the stage starts.
	_rebuild(_half_extent)


## Stage hook, called by WorldDirector.on_stage_started — NOT from the
## stage_changed signal: the signal fires after the arena is placed, and
## the minimap wants a clean fog the moment the map exists. Stage 0 goes
## through the same call, so there is no first-stage special case.
func reset_for_stage(arena: Node3D) -> void:
	var half := _half_extent
	var bounds := get_tree().get_first_node_in_group(&"arena_bounds")
	if bounds != null and (arena == null or arena.is_ancestor_of(bounds)):
		var value: Variant = bounds.get("arena_half_extent")
		if value != null:
			half = float(value)
	_rebuild(half)


func _rebuild(half_extent: float) -> void:
	_half_extent = half_extent
	_pixels = maxi(int(round(half_extent * 2.0 / maxf(meters_per_pixel, 0.5))), 8)
	image = Image.create_empty(_pixels, _pixels, false, Image.FORMAT_L8)
	image.fill(Color(0.0, 0.0, 0.0))
	_explored_pixels = 0
	_paint_left = 0.0


func _physics_process(delta: float) -> void:
	if image == null:
		return
	_paint_left -= delta
	if _paint_left > 0.0:
		return
	_paint_left = paint_interval
	# Downed raiders reveal too: their body is still lying there, and the
	# party can see the ground around a fallen teammate.
	for group: String in ["player", "downed_players"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body != null:
				reveal_at(Vector2(body.global_position.x, body.global_position.z))


## Paints one disc of explored ground. Public so a future power-up ("read
## the map") can reveal from somewhere nobody is standing.
func reveal_at(center_xz: Vector2) -> void:
	if image == null:
		return
	var center_px := _to_pixel(center_xz)
	var radius := int(ceil(reveal_radius / maxf(meters_per_pixel, 0.5)))
	var radius_sq := radius * radius
	for dy in range(-radius, radius + 1):
		var py := center_px.y + dy
		if py < 0 or py >= _pixels:
			continue
		for dx in range(-radius, radius + 1):
			var px := center_px.x + dx
			if px < 0 or px >= _pixels:
				continue
			if dx * dx + dy * dy > radius_sq:
				continue
			# Counted here, once per pixel, so explored_fraction() never
			# has to walk 14 641 pixels to answer.
			if image.get_pixel(px, py).r < 0.5:
				_explored_pixels += 1
				image.set_pixel(px, py, Color(1.0, 1.0, 1.0))


## True when the party has been near this flat position.
func is_explored(xz: Vector2) -> bool:
	if image == null:
		return false
	var px := _to_pixel(xz)
	if px.x < 0 or px.y < 0 or px.x >= _pixels or px.y >= _pixels:
		return false
	return image.get_pixel(px.x, px.y).r >= 0.5


## 0-1 share of the stage the party has uncovered. The soak reads it.
func explored_fraction() -> float:
	if image == null or _pixels <= 0:
		return 0.0
	return float(_explored_pixels) / float(_pixels * _pixels)


## Size of the fog image in pixels (MapDraw scales its composite to it).
func pixels() -> int:
	return _pixels


## Half-extent, in metres, of the arena this fog covers.
func half_extent() -> float:
	return _half_extent


func _to_pixel(xz: Vector2) -> Vector2i:
	var scale := float(_pixels) / maxf(_half_extent * 2.0, 0.001)
	return Vector2i(
			int(floor((xz.x + _half_extent) * scale)),
			int(floor((xz.y + _half_extent) * scale)))
