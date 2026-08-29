class_name PlayerStats
extends Node
## Player-wide derived-stats layer and tome holder in one node, mounted on
## the Player beside the Weapons mount. Owns the tome stacks collected this
## run plus the character's per-level passive, and recomputes every derived
## stat FROM SCRATCH on each change (tome pickup or level-up), so stacking
## never drifts. Consumers stay loosely coupled: weapons read the
## multipliers through WeaponBase helpers, armor is pushed into the sibling
## Health, and UpgradePool reads luck when rolling card rarities.

## Crit damage multiplier before any Tome of Ruin bonuses.
@export var base_crit_damage: float = 2.0
## Baseline luck (rarity tilt points) before any bonuses.
@export var base_luck: float = 0.0
## Stacked haste can never push the global cooldown multiplier below this.
@export var min_cooldown_multiplier: float = 0.25
## Evasion can never exceed this dodge chance, however many sources stack.
@export var max_evasion: float = 0.6
## Dodge-execute passives kill a non-boss attacker whose HP ratio is
## strictly below this when the dodge lands.
@export var execute_threshold: float = 0.25

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
## Chance (0-1, capped at max_evasion) to fully dodge incoming damage; the
## sibling Health rolls it per hit.
var evasion: float = 0.0
## Flat damage reflected to a contact attacker whenever the player is hit.
var thorns: float = 0.0
## Max-HP granted on top of the Health node's own max_hp (which generic
## Stout Heart cards also raise); pushed into Health as a DELTA.
var bonus_max_hp: float = 0.0

## tome id -> one rarity potency per collected stack. recompute() derives
## every stat from this, so it is the single source of truth.
var _tome_stacks: Dictionary[String, PackedFloat32Array] = {}

## Character passive (CharacterCatalog row data). Kinds:
##   "per_level":       _passive_stat gains _passive_base plus
##                      _passive_amount per level past 1.
##   "speed_to_damage": bonus move speed converts to bonus damage at the
##                      _passive_amount ratio (0.6 = +0.6% dmg per +1% speed).
##   "evasion_execute": per_level scaling, plus every successful dodge
##                      executes a weakened non-boss attacker (_on_dodged).
## Empty stat id with a per-level kind = no passive.
var _passive_kind: String = "per_level"
var _passive_stat: String = ""
var _passive_amount: float = 0.0
var _passive_base: float = 0.0

## Portion of bonus_max_hp already applied to Health, so recomputes adjust
## by the difference instead of re-adding the whole bonus.
var _applied_bonus_max_hp: float = 0.0


func _ready() -> void:
	# Character passives scale with the run level, so every level-up
	# re-derives the stats (recompute-from-scratch, same as tome pickups).
	RunState.leveled_up.connect(_on_leveled_up)
	# Thorns retaliation: the sibling Health names contact attackers.
	var health := Health.find_in(get_parent())
	if health != null:
		health.damaged_by.connect(_on_damaged_by)
		# Dodge-execute passives resolve off the dodge that Health rolled.
		health.dodged.connect(_on_dodged)
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


## Registers the selected character's passive (stat ids match _apply_effect;
## kinds are documented on _passive_kind). base_amount is granted already at
## level 1 (Doc's starting lifesteal). Called by the player at spawn with
## catalog row data.
func set_character_passive(stat: String, amount: float, kind: String = "per_level",
		base_amount: float = 0.0) -> void:
	_passive_kind = kind
	_passive_stat = stat
	_passive_amount = amount
	_passive_base = base_amount
	recompute()


## Rebuilds every derived stat from the stored tome stacks and the
## character passive (recompute, not accumulate). Call after any change.
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
	evasion = 0.0
	thorns = 0.0
	bonus_max_hp = 0.0
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
	# Passives run AFTER tomes so conversion kinds see the tome totals.
	_apply_character_passive()
	cooldown_multiplier = maxf(cooldown_multiplier, min_cooldown_multiplier)
	crit_chance = clampf(crit_chance, 0.0, 1.0)
	evasion = clampf(evasion, 0.0, max_evasion)
	luck = maxf(luck, 0.0)
	_push_armor_to_health()
	_push_bonus_max_hp_to_health()


## Applies the character passive by kind (data-driven from the catalog row;
## no per-character branches).
func _apply_character_passive() -> void:
	match _passive_kind:
		"per_level", "evasion_execute":
			# Level 1 contributes only the base amount, each level gained
			# adds one increment (no roundf — sub-percent steps must
			# accumulate). "evasion_execute" also kills on dodge; that part
			# lives in _on_dodged, not here.
			if not _passive_stat.is_empty():
				_apply_effect(_passive_stat, _passive_base
						+ _passive_amount * float(maxi(RunState.level - 1, 0)))
		"speed_to_damage":
			# Bonus move speed (multiplier above 1) converts into a direct
			# damage-multiplier bonus at the configured ratio.
			damage_multiplier += maxf(move_speed_multiplier - 1.0, 0.0) * _passive_amount
		_:
			push_warning("PlayerStats: unknown passive kind '%s'" % _passive_kind)


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
		"evasion":
			evasion += amount / 100.0
		"armor":
			armor += amount
		"luck":
			luck += amount
		"thorns":
			thorns += amount
		"max_hp":
			bonus_max_hp += amount
		_:
			push_warning("PlayerStats: unknown effect stat '%s'" % stat)


func _on_leveled_up(_new_level: int) -> void:
	recompute()


## Health applies armor itself in take_damage, so the reduction also covers
## damage sources that never touch a weapon (enemy contact hits).
func _push_armor_to_health() -> void:
	var health := _sibling_health()
	if health != null:
		health.armor = armor


## Health.max_hp is shared state (Stout Heart cards add to it directly), so
## the passive's bonus is applied as a delta from what was already pushed.
## A raise also heals by the delta — clamped by heal(), never an overheal.
func _push_bonus_max_hp_to_health() -> void:
	var health := _sibling_health()
	if health == null:
		return
	var delta := bonus_max_hp - _applied_bonus_max_hp
	if is_zero_approx(delta):
		return
	_applied_bonus_max_hp = bonus_max_hp
	health.max_hp += delta
	if delta > 0.0:
		health.heal(delta)
	else:
		health.current_hp = minf(health.current_hp, health.max_hp)


## Dodge-execute ("evasion_execute" kind): a successful dodge instantly
## kills the attacker when it is a non-boss enemy below the execute
## threshold — through take_damage, so the normal death flow (kill credit,
## XP gem, squash-out) runs unchanged.
func _on_dodged(attacker: Node3D) -> void:
	if _passive_kind != "evasion_execute":
		return
	if attacker == null or not is_instance_valid(attacker) \
			or attacker.is_in_group("boss"):
		return
	var attacker_health := Health.find_in(attacker)
	if attacker_health == null or attacker_health.is_dead:
		return
	if attacker_health.current_hp >= attacker_health.max_hp * execute_threshold:
		return
	# current_hp plus armor guarantees the post-armor amount is lethal.
	attacker_health.take_damage(attacker_health.current_hp + attacker_health.armor)


## Thorns retaliation: reflect flat damage to whoever just struck the
## player by contact. Reflected hits name no attacker, so two thorny
## parties could never ping-pong.
func _on_damaged_by(attacker: Node3D) -> void:
	if thorns <= 0.0 or attacker == null or not is_instance_valid(attacker):
		return
	var attacker_health := Health.find_in(attacker)
	if attacker_health != null:
		attacker_health.take_damage(thorns)


func _sibling_health() -> Health:
	var parent := get_parent()
	return Health.find_in(parent) if parent != null else null
