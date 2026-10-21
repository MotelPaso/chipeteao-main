class_name PowerUpPickup
extends Area3D
## A power-up lying on the ground (iteration 53): a bobbing coloured gem
## with the row's two-letter glyph over it, collected by walking into it.
## Dropped by kills, or — for the star only — sent roaming by the
## WorldDirector's star sighting.
##
## Stage-scoped: parented through RunRoot.stage_parent, in group
## `powerup_pickups` so the stage swap can free it and Stage sweep can
## count it. It is NOT pooled: a handful exist at once, they live seconds,
## and pooling one would buy nothing but a reset contract to get wrong.
##
## Lifetime is short by design. The map already carries dozens of markers
## late in a stage; a pickup that waited forever would add to that pile
## without ever being walked to.

## Seconds before an uncollected pickup fades out. The star gets its own,
## longer one: it is moving, so it needs time to be intercepted.
@export var lifetime: float = 45.0
@export var star_lifetime: float = 60.0
## Roam speed of the star. Zero for every other row, which just sits.
@export var roam_speed: float = 6.0
## Height of the roaming hop and how fast it cycles.
@export var hop_height: float = 0.9
@export var hop_hz: float = 1.6
## Bob of a resting pickup.
@export var bob_height: float = 0.22
@export var bob_hz: float = 1.4
@export var spin_speed: float = 1.8
## Distance the roamer looks ahead when testing for a wall to bounce off.
@export var roam_probe: float = 3.0

## Ring the raider has to step into. Generous: this is a reward, not a
## precision test, and the raider is usually sprinting past it.
const PICKUP_RADIUS: float = 1.6
const GEM_SIZE: float = 0.42
const GLYPH_FONT_SIZE: int = 48
const GLYPH_HEIGHT: float = 1.15
## Seconds of the fade-out before the node frees itself.
const FADE_TIME: float = 0.45
## Rainbow cycle of the star's tint, in full turns per second.
const STAR_HUE_HZ: float = 0.55

var powerup_id: String = ""
## True for the star row: it roams, hops and bounces instead of resting.
var roaming: bool = false

var _row: Dictionary = {}
var _color: Color = Color.WHITE
var _gem: MeshInstance3D = null
var _glyph: Label3D = null
var _light: OmniLight3D = null
var _material: StandardMaterial3D = null
var _time: float = 0.0
var _left: float = 0.0
var _ground_y: float = 0.0
## False until the drop has been placed and _ground_y is worth reading.
var _ground_captured: bool = false
var _heading: Vector2 = Vector2.RIGHT
var _bounces: int = 0
var _taken: bool = false
var _bounds: Node = null


## MUST run before the node enters the tree: everything below is built
## from the row.
func setup(id: String) -> void:
	powerup_id = id
	_row = PowerUpCatalog.by_id(id)
	roaming = String(_row.get("kind", "")) == "star"


func _ready() -> void:
	add_to_group(&"powerup_pickups")
	add_to_group(&"map_markers")
	if _row.is_empty():
		_row = PowerUpCatalog.by_id(powerup_id)
	if _row.is_empty():
		push_warning("PowerUpPickup: unknown power-up '%s'" % powerup_id)
		queue_free()
		return
	_color = _row.get("color", Color.WHITE)
	_left = star_lifetime if roaming else lifetime
	# NOT captured here: every spawn path sets the position AFTER
	# add_child, so at _ready this read the PARENT's origin instead of the
	# drop point. Taken on the first physics frame instead, when the drop
	# has been placed. It is only the fallback for a scene with no
	# Terrain, but a fallback that is wrong is worse than one that is
	# missing — a star in such a scene hopped around y = 0.
	_ground_captured = false
	# The layers and `monitorable` are set in PowerUpPickup.tscn, NOT here:
	# a drop is spawned from EnemyBase._on_died, which itself runs inside a
	# Health.died emitted from take_damage — often mid-dispatch of some
	# Area3D's body_entered. Godot refuses a direct write to those while a
	# signal is in flight, and the scene has already applied them by the
	# time _ready runs. (Collides with nothing, detects only the player
	# layer: a pickup must never push a raider or block a shot.)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = PICKUP_RADIUS
	shape.shape = sphere
	shape.position.y = 0.6
	add_child(shape)
	_build_visual()
	_heading = Vector2(randf() * 2.0 - 1.0, randf() * 2.0 - 1.0).normalized()
	if _heading.length_squared() < 0.01:
		_heading = Vector2.RIGHT
	_bounds = get_tree().get_first_node_in_group("arena_bounds")
	body_entered.connect(_on_body_entered)


func _build_visual() -> void:
	_gem = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = GEM_SIZE
	mesh.height = GEM_SIZE * 2.4
	mesh.radial_segments = 6
	mesh.rings = 3
	_gem.mesh = mesh
	# Per-instance material: the star animates its albedo, and a shared
	# resource would tint every other pickup on the map with it.
	_material = StandardMaterial3D.new()
	_material.albedo_color = _color
	_material.emission_enabled = true
	_material.emission = _color
	_material.emission_energy_multiplier = 2.2
	_gem.material_override = _material
	_gem.position.y = 0.75
	add_child(_gem)
	_glyph = Label3D.new()
	_glyph.text = String(_row.get("glyph", "?"))
	_glyph.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_glyph.no_depth_test = true
	_glyph.font_size = GLYPH_FONT_SIZE
	_glyph.outline_size = 12
	_glyph.modulate = Color(1.0, 1.0, 1.0)
	_glyph.position.y = GLYPH_HEIGHT
	add_child(_glyph)
	_light = OmniLight3D.new()
	_light.light_color = _color
	_light.light_energy = 1.6
	_light.omni_range = 5.0
	_light.position.y = 0.8
	add_child(_light)


func _physics_process(delta: float) -> void:
	if _taken:
		return
	_capture_ground()
	_time += delta
	_left -= delta
	if _left <= 0.0:
		_expire()
		return
	if _gem != null:
		_gem.rotate_y(spin_speed * delta)
	if roaming:
		_tick_roam(delta)
		_tick_star_tint()
	elif _gem != null:
		_gem.position.y = 0.75 + sin(_time * TAU * bob_hz) * bob_height


## The star crosses the map instead of waiting to be found. It bounces off
## anything the arena mask calls unwalkable and off the arena edge, which
## is the same test every other spawn uses — so it can never end up inside
## the rocks it is supposed to be skirting.
func _tick_roam(delta: float) -> void:
	var step := roam_speed * delta
	var here := Vector2(global_position.x, global_position.z)
	var ahead := here + _heading * maxf(roam_probe, step)
	if not _walkable(ahead):
		# Reflect off whichever axis is blocked; if both are, turn around.
		var flip_x := not _walkable(Vector2(ahead.x, here.y))
		var flip_z := not _walkable(Vector2(here.x, ahead.y))
		if not flip_x and not flip_z:
			flip_x = true
			flip_z = true
		if flip_x:
			_heading.x = -_heading.x
		if flip_z:
			_heading.y = -_heading.y
		_bounces += 1
		here += _heading * step
	else:
		here += _heading * step
	global_position.x = here.x
	global_position.z = here.y
	var ground := _ground_height(here)
	_ground_y = ground
	global_position.y = ground + absf(sin(_time * PI * hop_hz)) * hop_height


func _tick_star_tint() -> void:
	if _material == null:
		return
	var tint := Color.from_hsv(fmod(_time * STAR_HUE_HZ, 1.0), 0.75, 1.0)
	_material.albedo_color = tint
	_material.emission = tint
	if _light != null:
		_light.light_color = tint


func _walkable(xz: Vector2) -> bool:
	if _bounds == null or not _bounds.has_method("is_walkable"):
		return true
	return bool(_bounds.call("is_walkable", xz))


## Ground level under the drop, captured once the spawn has been placed.
## Only read when there is no Terrain to ask.
func _capture_ground() -> void:
	if _ground_captured:
		return
	_ground_captured = true
	_ground_y = global_position.y


func _ground_height(xz: Vector2) -> float:
	var terrain := Terrain.find(get_tree())
	return terrain.height_at(xz.x, xz.y) if terrain != null else _ground_y


func _on_body_entered(body: Node3D) -> void:
	if _taken or not body.is_in_group("player"):
		return
	var powerups := PowerUps.find_in(body)
	if powerups == null:
		return
	_taken = true
	powerups.apply(powerup_id)
	Juice.sparkle(global_position + Vector3.UP * 0.8)
	Sfx.play(&"gem_pickup")
	if roaming:
		print("Star roam: bounces=%d" % _bounces)
	_vanish()


## Timed out: same fade, and the star reports the trip it made.
func _expire() -> void:
	_taken = true
	if roaming:
		print("Star roam: bounces=%d" % _bounces)
	_vanish()


func _vanish() -> void:
	set_physics_process(false)
	# DEFERRED: _vanish runs from inside body_entered, and Godot refuses a
	# direct write to monitoring while the area is dispatching that signal.
	set_deferred("monitoring", false)
	remove_from_group(&"map_markers")
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.05, FADE_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)


## Map marker contract (group "map_markers"): power-ups are worth walking
## to, so they show — but only where the fog has been lifted, like every
## other found thing.
func map_marker_kind() -> StringName:
	return &"powerup"


## Its own colour on the map, so a star reads differently from a drop.
func map_marker_color() -> Color:
	return _color
