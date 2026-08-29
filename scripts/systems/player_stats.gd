class_name PlayerStats
extends Node
## Player-wide derived-stats layer and tome holder in one node, mounted on
## the Player beside the Weapons mount. Owns the tome stacks collected this
## run and recomputes every derived stat FROM SCRATCH on each change, so
## stacking never drifts. Consumers stay loosely coupled: weapons read the
## multipliers through WeaponBase helpers, armor is pushed into the sibling
## Health, and UpgradePool reads luck when rolling card rarities.

## Crit damage multiplier before any Tome of Ruin bonuses.
@export var base_crit_damage: float = 2.0
## Baseline luck (rarity tilt points) before any bonuses.
@export var base_luck: float = 0.0
## Stacked haste can never push the global cooldown multiplier below this.
@export var min_cooldown_multiplier: float = 0.25

# Derived values — change them via add_tome()/recompute(), never directly.
var damage_multiplier: float = 1.0
var cooldown_multiplier: float = 1.0
var area_multiplier: float = 1.0
var move_speed_multiplier: float = 1.0
var crit_chance: float = 0.0
var crit_damage: float = 2.0
var lifesteal: float = 0.0
var armor: float = 0.0
var luck: float = 0.0

## tome id -> one rarity potency per collected stack. recompute() derives
## every stat from this, so it is the single source of truth.
var _tome_stacks: Dictionary[String, PackedFloat32Array] = {}


func _ready() -> void:
	recompute()


## Finds the PlayerStats component on a body, or null if it has none.
static func find_in(body: Node) -> PlayerStats:
	if body == null:
		return null
	for child in body.get_children():
		if child is PlayerStats:
			return child
	return null


func stack_count(tome_id: String) -> int:
	if not _tome_stacks.has(tome_id):
		return 0
	return _tome_stacks[tome_id].size()


## Grants one stack of a tome at the given rarity potency. Stacks past
## Tome.MAX_STACKS are ignored (the pool stops offering capped tomes; this
## guards a stale queued offer).
func add_tome(tome_id: String, potency: float) -> void:
	if stack_count(tome_id) >= Tome.MAX_STACKS:
		return
	# Packed arrays inside dictionaries are copy-on-write: mutate a copy,
	# then write it back.
	var stacks: PackedFloat32Array = _tome_stacks.get(tome_id, PackedFloat32Array())
	stacks.append(potency)
	_tome_stacks[tome_id] = stacks
	recompute()


## Rebuilds every derived stat from the stored tome stacks (recompute, not
## accumulate). Call after any change to the stacks.
func recompute() -> void:
	damage_multiplier = 1.0
	cooldown_multiplier = 1.0
	area_multiplier = 1.0
	move_speed_multiplier = 1.0
	crit_chance = 0.0
	crit_damage = base_crit_damage
	lifesteal = 0.0
	armor = 0.0
	luck = base_luck
	for tome_id: String in _tome_stacks:
		var tome := Tome.by_id(tome_id)
		if tome.is_empty():
			push_warning("PlayerStats: unknown tome '%s'" % tome_id)
			continue
		var effects: Array = tome.effects
		for potency: float in _tome_stacks[tome_id]:
			for effect: Dictionary in effects:
				# roundf matches the card text, so displayed == applied.
				_apply_effect(String(effect.stat), roundf(float(effect.amount) * potency))
	cooldown_multiplier = maxf(cooldown_multiplier, min_cooldown_multiplier)
	crit_chance = clampf(crit_chance, 0.0, 1.0)
	luck = maxf(luck, 0.0)
	_push_armor_to_health()


## One potency-scaled effect on top of the running totals. Percent-like
## stats stack additively (+15% twice = +30%); armor and luck are flat.
func _apply_effect(stat: String, amount: float) -> void:
	match stat:
		"damage":
			damage_multiplier += amount / 100.0
		"cooldown":
			cooldown_multiplier -= amount / 100.0
		"area":
			area_multiplier += amount / 100.0
		"move_speed":
			move_speed_multiplier += amount / 100.0
		"crit_chance":
			crit_chance += amount / 100.0
		"crit_damage":
			crit_damage += amount / 100.0
		"lifesteal":
			lifesteal += amount / 100.0
		"armor":
			armor += amount
		"luck":
			luck += amount
		_:
			push_warning("PlayerStats: unknown effect stat '%s'" % stat)


## Health applies armor itself in take_damage, so the reduction also covers
## damage sources that never touch a weapon (enemy contact hits).
func _push_armor_to_health() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var health := Health.find_in(parent)
	if health != null:
		health.armor = armor
