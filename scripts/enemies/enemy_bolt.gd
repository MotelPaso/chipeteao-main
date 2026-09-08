class_name EnemyBolt
extends Area3D
## Enemy projectile: flies straight along -Z at a strafe-dodgeable speed
## and hurts only the player. Its collision mask is world + player (layer
## 1), so bodies on the enemy layer are never even detected — an enemy
## bolt can never damage an enemy. Releases back to Pools on any body hit
## (player, floor, prop) or after max_distance so strays never linger.

@export var speed: float = 10.0
@export var damage: float = 8.0
@export var max_distance: float = 30.0

## The enemy that fired this bolt, so a reflected hit has somewhere to go
## back to (iteration 53). Cleared on every acquire: a pooled bolt that
## kept the previous caster would repay the wrong body — or a freed one.
var launcher: Node3D = null
## Set by EnemySpawner.freeze_enemies: a frozen bolt hangs in the air.
## A FLAG and not set_physics_process(false), because NodePool.release
## snapshots the processing state and acquire() restores it — a pooled
## node frozen that way comes back inert forever.
var frozen: bool = false

var _travelled: float = 0.0
## Scene-default damage, restored on reuse (casters override it per shot
## AFTER the pool's reset, so an elite's hot bolt never leaks to the next).
var _default_damage: float = 8.0
## Set the moment this bolt spends itself. Pools.release only DEFERS the
## reparent, so the Area3D keeps monitoring for the rest of the signal
## flush: without this flag two raiders entering on the same physics step
## would each eat a full hit from one bolt.
var _spent: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	# Group joined here AND re-joined in pool_reset: a released bolt is
	# reparented, not freed, and time_stop has to be able to find every
	# bolt in flight without walking the whole tree.
	add_to_group(&"enemy_projectiles")
	_default_damage = damage


## Pooled-node contract: fresh flight on every acquire.
func pool_reset() -> void:
	damage = _default_damage
	_travelled = 0.0
	_spent = false
	frozen = false
	launcher = null
	if not is_in_group(&"enemy_projectiles"):
		add_to_group(&"enemy_projectiles")


func _physics_process(delta: float) -> void:
	if _spent or frozen:
		return
	var step := speed * delta
	global_position += -global_transform.basis.z * step
	_travelled += step
	if _travelled >= max_distance:
		_spend()


func _on_body_entered(body: Node3D) -> void:
	# A frozen bolt hangs in stopped time: it must not spend itself, and it
	# must not hit the raider who walks past it. Its Area3D keeps monitoring
	# while frozen (that is the point of the flag over a processing toggle),
	# so without this the one thing time stop guarantees — nothing touches
	# you — would be broken by a bullet already in the air.
	if _spent or frozen:
		return
	if body.is_in_group("player"):
		var health := Health.find_in(body)
		if health != null:
			# The caster is named so Reflejo (and thorns) can repay it; a
			# bolt whose caster already died passes null and simply deals
			# its damage.
			health.take_damage(damage, false,
					launcher if is_instance_valid(launcher) else null)
	_spend()


func _spend() -> void:
	_spent = true
	Pools.release(self)
