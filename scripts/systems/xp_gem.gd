class_name XpGem
extends Area3D
## XP gem dropped by enemies. Idles with a spin/bob, then homes to the
## player with accelerating speed once inside the magnet radius (scaled by
## RunState.pickup_radius_multiplier so pickup upgrades affect every gem).
## Collects on player contact -> RunState.add_xp. Despawns after lifetime
## if never magnetized, to keep long runs from littering the arena.
## Pooled: spawn via Pools.acquire_scene; every despawn is a Pools.release
## and pool_reset() restores the just-dropped state (including xp_value,
## which droppers scale per gem on top of the scene default). Live gems
## sit in LIVE_GROUP (joined on acquire, left on release) so the level-up
## vacuum can force-home every gem on the map at once.

## Group every live (dropped, uncollected) gem belongs to; the vacuum
## reaches gems through it. Distinct from the scene's persistent
## "xp_gems" group, which the perf probe counts.
const LIVE_GROUP: StringName = &"gems"

@export var xp_value: int = 1
## 4.0 (was 3.5, iteration-31 balance): +~15% base pickup reach offsets
## the extra roaming the enlarged 160x160 arenas ask for.
@export var magnet_radius: float = 4.0
@export var magnet_acceleration: float = 45.0
## Starting homing speed when the level-up vacuum grabs this gem.
@export var vacuum_speed: float = 26.0
@export var lifetime: float = 60.0
@export var spin_speed: float = 2.5
@export var bob_amplitude: float = 0.12

@onready var _visual: Node3D = $Visual

var _age: float = 0.0
var _visual_rest_y: float = 0.0
var _homing: bool = false
var _speed: float = 0.0
var _collected: bool = false
var _default_xp_value: int = 1


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_visual_rest_y = _visual.position.y
	_default_xp_value = xp_value


## Pooled-node contract: back to the just-dropped state on every acquire.
func pool_reset() -> void:
	xp_value = _default_xp_value
	_age = 0.0
	_homing = false
	_speed = 0.0
	_collected = false
	_visual.position.y = _visual_rest_y
	add_to_group(LIVE_GROUP)


## Level-up vacuum (reached via LIVE_GROUP): force-enables homing at
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

	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	# Aim at chest height so gems don't burrow toward the feet.
	var target := player.global_position + Vector3.UP * 0.9

	if not _homing:
		_visual.position.y = _visual_rest_y + sin(_age * 3.0) * bob_amplitude
		var radius := magnet_radius * RunState.pickup_radius_multiplier
		if global_position.distance_squared_to(target) <= radius * radius:
			_homing = true  # sticky: keeps chasing even if the player outruns it
		elif _age > lifetime:
			_release_to_pool()
		return

	_speed += magnet_acceleration * delta
	global_position = global_position.move_toward(target, _speed * delta)
	# Fallback for very fast final approach, where the one-physics-frame
	# overlap can slip past the area signal.
	if global_position.distance_squared_to(target) < 0.36:
		_collect()


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_collect()


func _collect() -> void:
	if _collected:
		return
	_collected = true
	Sfx.play(&"gem_pickup")
	RunState.add_xp(xp_value)
	_release_to_pool()


## Leaves the live group BEFORE the pooled release, so a vacuum firing in
## the deferred-release window (the node stays in-tree one more frame)
## never touches a gem already on its way out.
func _release_to_pool() -> void:
	if is_in_group(LIVE_GROUP):
		remove_from_group(LIVE_GROUP)
	Pools.release(self)
