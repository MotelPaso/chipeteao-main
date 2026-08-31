class_name Skirmisher
extends EnemyBase
## Ranged skirmisher: holds a standoff band around the player — advances
## when too far, backs off when crowded, stands and casts inside it — and
## lobs slow, dodgeable bolts on a cadence. Always turns to face the
## player (even while retreating) so the silhouette reads as an aimer.

@export var band_inner: float = 8.0
@export var band_outer: float = 12.0
@export var fire_cooldown: float = 3.0
@export var fire_range: float = 18.0
## 6 (was 8, iteration-26 balance): once contact damage is kited well,
## bolts are the run's dominant chip — instrumented T1 soaks measured them
## at ~55% of all damage taken after minute 3, outpacing every recovery
## source. 6 keeps the poke meaningful against orb heals without making
## the skirmisher census a slow death sentence.
@export var bolt_damage: float = 6.0
@export var bolt_scene: PackedScene
## Bolts leave at hand height and fly at the player's chest.
@export var muzzle_height: float = 1.2
@export var target_height: float = 0.9

# Small grace period so a fresh spawn doesn't snipe the instant it lands.
var _fire_timer: float = 1.0


func _behavior_tick(delta: float) -> void:
	_fire_timer = maxf(_fire_timer - delta, 0.0)


func _movement_intent(seek: Vector3, distance: float) -> Vector3:
	if distance > band_outer:
		return seek
	if distance < band_inner:
		return -seek
	return Vector3.ZERO


func _facing_direction(steer: Vector3, seek: Vector3) -> Vector3:
	return seek if seek.length_squared() > 0.0001 else steer


func _combat_tick(player: Node3D, distance: float) -> void:
	# The lower bound also keeps look_at away from the degenerate
	# straight-up case when the player stands on this enemy's head.
	if _fire_timer > 0.0 or distance > fire_range or distance < 0.5:
		return
	if bolt_scene == null:
		return
	_fire_timer = fire_cooldown
	_fire_bolt(player)


func _fire_bolt(player: Node3D) -> void:
	# Pooled, parented to the scene root so the bolt outlives its caster.
	var bolt := Pools.acquire_scene(bolt_scene) as EnemyBolt
	if bolt == null:
		return
	bolt.damage = bolt_damage
	bolt.global_position = global_position + Vector3.UP * muzzle_height
	# The bolt flies at the true 3D aim; when that runs near-colinear with UP
	# (player jumping right overhead) look_at cannot build a basis, so swap
	# in a sideways up vector — same guard as BeamVisual.span().
	var aim := (player.global_position + Vector3.UP * target_height
			- bolt.global_position).normalized()
	var up := Vector3.UP if absf(aim.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	bolt.look_at(bolt.global_position + aim, up)


func _apply_elite_damage(multiplier: float) -> void:
	bolt_damage *= multiplier
