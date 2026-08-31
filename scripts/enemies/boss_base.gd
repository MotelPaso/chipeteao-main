class_name BossBase
extends EnemyBase
## Shared boss chassis on top of EnemyBase: everything every biome boss
## repeats — HUD boss-bar binding through the "boss_ui" group, the hard
## arena clamp, Elder tier and Curse Shrine scaling (both funnel the
## moveset's numbers through the _scale_attack_damage hook), the ring-of-
## gems death payout, and the boss-kill juice moment. Concrete bosses
## (Rotking, Sarcognath) keep their own state machines and movesets.
## Bosses never become elites (make_elite is a no-op); the spawner
## promotes rematches with apply_tier() instead.

@export var boss_title: String = "Boss"
## Half-size of the arena floor minus a margin; position is clamped so the
## boss (and its ground attacks) never leave the field.
@export var arena_half_extent: float = 46.0

@export_group("Reward")
## Death payout: a ring of boss_gem_count gems worth boss_gem_value XP each.
@export var boss_gem_count: int = 8
@export var boss_gem_value: int = 5

@export_group("Tier")
## Extra body scale applied per apply_tier() call (Elder and beyond).
@export var tier_body_scale: float = 1.15

@export_group("Curse")
## Extra HP/damage fraction per curse stack (0.4 = +40% each).
@export var curse_stat_bonus_per_stack: float = 0.4
## Death-payout gem count is multiplied by this once per curse stack.
@export var curse_gem_factor_per_stack: int = 2


func _ready() -> void:
	super()
	_health.died.connect(_on_boss_base_died)
	get_tree().call_group("boss_ui", "track_boss", self, boss_title)


func _physics_process(delta: float) -> void:
	super(delta)
	# Hard arena bound (also catches any future knockback effects).
	global_position.x = clampf(global_position.x, -arena_half_extent, arena_half_extent)
	global_position.z = clampf(global_position.z, -arena_half_extent, arena_half_extent)


## The spawner's elite roll must never touch a boss; tiering goes through
## apply_tier() instead.
func make_elite() -> void:
	pass


## Virtual: multiply every attack-damage number the concrete boss owns;
## called once per apply_tier()/apply_curse().
func _scale_attack_damage(_multiplier: float) -> void:
	pass


## Stronger boss instance (Elder rematches, future map tiers): multiplies
## survivability, damage, and payout, and bulks the body up slightly.
## Call after the boss is inside the tree.
func apply_tier(multiplier: float) -> void:
	_health.max_hp *= multiplier
	_health.heal_full()
	_scale_attack_damage(multiplier)
	boss_gem_value = ceili(float(boss_gem_value) * multiplier)
	scale *= tier_body_scale


## Curse Shrine payoff, applied by the spawner right after any apply_tier:
## every consumed stack adds curse_stat_bonus_per_stack HP/damage, and the
## death gem payout doubles per stack. Call while the boss is in the tree.
func apply_curse(stacks: int) -> void:
	if stacks <= 0:
		return
	var multiplier := 1.0 + curse_stat_bonus_per_stack * float(stacks)
	_health.max_hp *= multiplier
	_health.heal_full()
	_scale_attack_damage(multiplier)
	for i in stacks:
		boss_gem_count *= curse_gem_factor_per_stack


func _on_boss_base_died() -> void:
	# The base death flow (kill credit, gems, squash-out) already runs off
	# this signal; the boss only has to stop reading as an active boss.
	remove_from_group("boss")


## Boss kill moment: big shake, brief slow-mo, oversized shard burst.
func _death_feedback() -> void:
	Juice.boss_died(global_position + Vector3.UP * 1.5, death_burst_color())


## Boss payout: a ring of high-value gems instead of the single base gem.
func _drop_xp_gem() -> void:
	if xp_gem_scene == null:
		return
	for i in boss_gem_count:
		var gem := Pools.acquire_scene(xp_gem_scene) as XpGem
		if gem == null:
			return
		gem.xp_value = boss_gem_value
		var gem_angle := TAU * float(i) / float(boss_gem_count)
		gem.global_position = global_position + Vector3.UP * 0.6 \
				+ Vector3(cos(gem_angle), 0.0, sin(gem_angle)) * 1.2
