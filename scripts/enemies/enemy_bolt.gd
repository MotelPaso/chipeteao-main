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
	_default_damage = damage


## Pooled-node contract: fresh flight on every acquire.
func pool_reset() -> void:
	damage = _default_damage
	_travelled = 0.0
	_spent = false


func _physics_process(delta: float) -> void:
	if _spent:
		return
	var step := speed * delta
	global_position += -global_transform.basis.z * step
	_travelled += step
	if _travelled >= max_distance:
		_spend()


func _on_body_entered(body: Node3D) -> void:
	if _spent:
		return
	if body.is_in_group("player"):
		var health := Health.find_in(body)
		if health != null:
			health.take_damage(damage)
	_spend()


func _spend() -> void:
	_spent = true
	Pools.release(self)
