class_name WeaponBase
extends Node3D
## Base for auto-firing weapons: ticks a cooldown and calls fire() at the
## nearest body in the "enemies" group within attack_range.
## Subclasses override fire() with their attack behavior and funnel every
## hit through deal_damage(), so the player's global stats layer (damage
## multiplier, crit, lifesteal) applies in exactly one place. Cooldown and
## area-like reach respect the stats layer through the effective_* helpers.

## Effective cooldown can never drop below this many seconds.
const MIN_COOLDOWN: float = 0.05

@export var damage: float = 10.0
@export var cooldown: float = 1.0
@export var attack_range: float = 3.0
@export var projectile_count: int = 1
## Per-weapon cooldown multiplier ("Flurry"-style upgrades lower it); stacks
## multiplicatively with the player-wide cooldown multiplier, leaving the
## base cooldown untouched.
@export var cooldown_scale: float = 1.0

var _cooldown_left: float = 0.0

## The carrying player's stats layer; null means neutral multipliers (e.g.
## a weapon exercised outside a player rig in tests).
@onready var _stats: PlayerStats = PlayerStats.find_in(get_tree().get_first_node_in_group("player"))


func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if _cooldown_left > 0.0:
		return
	var target := acquire_target()
	if target == null:
		return
	_cooldown_left = effective_cooldown()
	fire(target)


func effective_damage() -> float:
	return damage * (_stats.damage_multiplier if _stats != null else 1.0)


func effective_cooldown() -> float:
	var multiplier := _stats.cooldown_multiplier if _stats != null else 1.0
	return maxf(cooldown * multiplier * cooldown_scale, MIN_COOLDOWN)


## Multiplier subclasses apply to their area-like reach (burst radius,
## melee arc range) — deliberately not to the targeting attack_range.
func area_scale() -> float:
	return _stats.area_multiplier if _stats != null else 1.0


## Shared damage funnel: applies effective damage, rolls crit, and heals
## the player for lifesteal. Every weapon hit goes through here. Returns
## the damage dealt so callers with damage-derived effects (Blood Vial's
## innate drain) can read it; most callers ignore it.
func deal_damage(target_health: Health) -> float:
	var amount := effective_damage()
	var is_crit := _stats != null and randf() < _stats.crit_chance
	if is_crit:
		amount *= _stats.crit_damage
		Juice.crit_punch()
	Sfx.play(&"hit_crit" if is_crit else &"hit_soft")
	target_health.take_damage(amount, is_crit)
	if _stats != null and _stats.lifesteal > 0.0:
		_lifesteal_heal(amount * _stats.lifesteal)
	return amount


func _lifesteal_heal(amount: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var player_health := Health.find_in(player)
	if player_health != null:
		player_health.heal(amount)


## Nearest body in the "enemies" group within attack_range, or null.
func acquire_target() -> Node3D:
	# Empty-horde fast path: while nothing is alive this runs every physics
	# frame, so skip the Array get_nodes_in_group would build.
	if get_tree().get_first_node_in_group("enemies") == null:
		return null
	var nearest: Node3D = null
	var nearest_dist_sq := attack_range * attack_range
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var body := enemy as Node3D
		if body == null or not body.is_inside_tree():
			continue
		var dist_sq := global_position.distance_squared_to(body.global_position)
		if dist_sq <= nearest_dist_sq:
			nearest_dist_sq = dist_sq
			nearest = body
	return nearest


## Virtual: perform the attack against the acquired target.
func fire(_target: Node3D) -> void:
	push_warning("%s: fire() not implemented" % name)
