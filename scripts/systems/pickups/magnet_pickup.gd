class_name MagnetPickup
extends Area3D
## Shared chassis for the dropped pickups (XP gems, health orbs). Idles
## with a spin/bob, then homes to the nearest standing raider with
## accelerating speed once inside the magnet radius (scaled by
## RunState.pickup_radius_multiplier so pickup upgrades reach every drop),
## collects on contact, and despawns after `lifetime`.
## Pooled: spawn via Pools.acquire_scene, every despawn is a Pools.release,
## and pool_reset() restores the just-dropped state. Live pickups sit in
## their subclass's LIVE_GROUP (joined on acquire, left BEFORE the release,
## so the level-up vacuum and the health-orb soft cap never see a parked or
## outbound node).
##
## Subclasses supply three things — the live group, what collecting one
## does, and any extra idle flourish. Everything else used to live twice,
## which is why the same "never expires" bug had to be reported twice.

## Squared distance at which the fast final approach counts as a pickup: a
## max-speed last hop can cross the whole trigger area inside one physics
## frame and never emit body_entered.
const CATCH_RADIUS_SQ: float = 0.36
## Aim height on the target, so pickups fly at the chest instead of
## burrowing toward the feet.
const TARGET_HEIGHT: float = 0.9

## 4.0 (was 3.5, iteration-31 balance): +~15% base pickup reach offsets
## the extra roaming the enlarged 160x160 arenas ask for.
@export var magnet_radius: float = 4.0
@export var magnet_acceleration: float = 45.0
## Starting homing speed when the level-up vacuum grabs this pickup.
@export var vacuum_speed: float = 26.0
@export var lifetime: float = 60.0
@export var spin_speed: float = 2.5
@export var bob_amplitude: float = 0.12
@export var bob_speed: float = 3.0

@onready var _visual: Node3D = $Visual

var _age: float = 0.0
var _visual_rest_y: float = 0.0
var _homing: bool = false
var _speed: float = 0.0
var _collected: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_visual_rest_y = _visual.position.y


## Pooled-node contract: back to the just-dropped state on every acquire.
func pool_reset() -> void:
	_age = 0.0
	_homing = false
	_speed = 0.0
	_collected = false
	# The idle spin and the orb pulse accumulate on the Visual, so without
	# these three a recycled pickup came out of the pool wearing the
	# orientation and scale its previous life ended with — a boss ring of
	# gems used to land at random angles once the pool warmed up.
	_visual.position.y = _visual_rest_y
	_visual.rotation = Vector3.ZERO
	_visual.scale = Vector3.ONE
	_reset_extra()
	var group := live_group()
	if group != &"":
		add_to_group(group)


## Level-up vacuum (reached via the live group): force-enables homing at
## vacuum speed regardless of the pickup radius — the genre-staple
## "level-up hoovers the floor" moment.
func vacuum() -> void:
	if _collected:
		return
	_homing = true
	_speed = maxf(_speed, vacuum_speed)


func _physics_process(delta: float) -> void:
	_age += delta
	_visual.rotate_y(spin_speed * delta)
	_idle_visuals(delta)

	var player := Coop.nearest_player(get_tree(), global_position)
	# Expiry runs BEFORE the no-player early return and OUTSIDE the idle
	# branch. Both guards used to sit in front of it, so a pickup that had
	# already latched on — or any pickup at all while the whole party was
	# down — aged forever without ever coming back: a pool slot and, for
	# orbs, a permanent seat under the soft cap that blocked every later heal.
	if _age > lifetime and (player == null or not _homing):
		_release_to_pool()
		return
	if player == null:
		return
	var target := player.global_position + Vector3.UP * TARGET_HEIGHT

	if not _homing:
		_visual.position.y = _visual_rest_y + sin(_age * bob_speed) * bob_amplitude
		var radius := magnet_radius * RunState.pickup_radius_multiplier
		if global_position.distance_squared_to(target) <= radius * radius:
			_homing = true  # sticky: keeps chasing even if the player outruns it
		return

	_speed += magnet_acceleration * delta
	global_position = global_position.move_toward(target, _speed * delta)
	if global_position.distance_squared_to(target) < CATCH_RADIUS_SQ:
		collect(player)


## Collects once and only once, then parks the node back in its pool.
func collect(collector: Node3D) -> void:
	if _collected:
		return
	_collected = true
	_on_collected(collector)
	_release_to_pool()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		collect(body)


## Leaves the live group BEFORE the pooled release, so a vacuum or a soft-
## cap count firing in the deferred-release window (the node stays in-tree
## one more frame) never touches a pickup already on its way out.
func _release_to_pool() -> void:
	var group := live_group()
	if group != &"" and is_in_group(group):
		remove_from_group(group)
	Pools.release(self)


# --- subclass hooks ---------------------------------------------------------

## Group every live (dropped, uncollected) instance belongs to.
func live_group() -> StringName:
	return &""


## What picking this up does for `collector` (never null on the contact
## path; the fast-approach fallback passes the player it was flying to).
func _on_collected(_collector: Node3D) -> void:
	pass


## Extra per-frame idle flourish on top of the shared spin and bob.
func _idle_visuals(_delta: float) -> void:
	pass


## Extra state to restore on acquire (drop-scaled values the droppers
## overwrite AFTER the reset).
func _reset_extra() -> void:
	pass
