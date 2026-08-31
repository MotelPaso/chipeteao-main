class_name HealthOrb
extends Area3D
## Health pickup dropped by elites (chance) and bosses (guaranteed count):
## heals a flat fraction of the player's max HP on contact — deliberately
## NOT scaled by map-tier XP factors — with the same magnet rules as XP
## gems (radius x RunState.pickup_radius_multiplier, sticky accelerating
## homing) plus the level-up vacuum hook. Pooled via Pools ("health_orb"):
## pool_reset restores just-dropped state INCLUDING live-group membership,
## and every release leaves the group first, so the soft cap and the
## vacuum never see parked or outbound orbs.

## Every live (dropped, uncollected) orb is in this group: drop sites
## count it for the soft cap and the level-up vacuum reaches orbs by it.
const LIVE_GROUP: StringName = &"health_orbs"
## Global cap on live orbs; drop sites skip the drop at the cap so
## generous boss fights cannot carpet the arena with heals.
const SOFT_CAP: int = 6

## Fraction of the player's max HP restored on pickup (flat: tiers and
## elites never scale it).
@export var heal_fraction: float = 0.15
@export var magnet_radius: float = 3.5
@export var magnet_acceleration: float = 45.0
## Starting homing speed when the level-up vacuum grabs this orb.
@export var vacuum_speed: float = 26.0
@export var lifetime: float = 45.0
@export var spin_speed: float = 1.8
@export var bob_amplitude: float = 0.1
## Idle scale-pulse swing (0.08 = ±8%) — the "alive" heartbeat read.
@export var pulse_amount: float = 0.08
@export var pulse_speed: float = 5.0

@onready var _visual: Node3D = $Visual

var _age: float = 0.0
var _visual_rest_y: float = 0.0
var _homing: bool = false
var _speed: float = 0.0
var _consumed: bool = false


## True when the arena already holds SOFT_CAP live orbs. Drop sites check
## this before acquiring another (parked/releasing orbs left the group, so
## they are never counted against the cap).
static func at_soft_cap(tree: SceneTree) -> bool:
	return tree.get_node_count_in_group(LIVE_GROUP) >= SOFT_CAP


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_visual_rest_y = _visual.position.y


## Pooled-node contract: back to the just-dropped state on every acquire.
func pool_reset() -> void:
	_age = 0.0
	_homing = false
	_speed = 0.0
	_consumed = false
	_visual.position.y = _visual_rest_y
	_visual.scale = Vector3.ONE
	add_to_group(LIVE_GROUP)


## Level-up vacuum (reached via LIVE_GROUP): force-enables homing at
## vacuum speed regardless of the pickup radius. Vacuuming a heal is fine.
func vacuum() -> void:
	if _consumed:
		return
	_homing = true
	_speed = maxf(_speed, vacuum_speed)


func _physics_process(delta: float) -> void:
	_age += delta
	_visual.rotate_y(spin_speed * delta)
	_visual.scale = Vector3.ONE * (1.0 + pulse_amount * sin(_age * pulse_speed))

	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	# Chest height, like the gems, so orbs don't burrow toward the feet.
	var target := player.global_position + Vector3.UP * 0.9

	if not _homing:
		_visual.position.y = _visual_rest_y + sin(_age * 3.0) * bob_amplitude
		var radius := magnet_radius * RunState.pickup_radius_multiplier
		if global_position.distance_squared_to(target) <= radius * radius:
			_homing = true  # sticky, exactly like the gem magnet
		elif _age > lifetime:
			_release_to_pool()
		return

	_speed += magnet_acceleration * delta
	global_position = global_position.move_toward(target, _speed * delta)
	# Same fast-approach fallback as XpGem: a max-speed final hop can cross
	# the whole pickup area within one physics frame and miss the signal.
	if global_position.distance_squared_to(target) < 0.36:
		_collect(player)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_collect(body)


func _collect(player: Node3D) -> void:
	if _consumed:
		return
	_consumed = true
	var health := Health.find_in(player)
	if health != null:
		# Health.heal clamps to max_hp (no overheal) and no-ops once dead.
		health.heal(health.max_hp * heal_fraction)
	Sfx.play(&"heal")
	_release_to_pool()


## Leaves the live group BEFORE the pooled release, so the soft cap and
## the vacuum never touch an orb already on its way out (release's
## reparent is deferred, so the node stays in-tree one more frame).
func _release_to_pool() -> void:
	if is_in_group(LIVE_GROUP):
		remove_from_group(LIVE_GROUP)
	Pools.release(self)
