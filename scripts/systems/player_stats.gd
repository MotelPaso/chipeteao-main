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

## Floors for the multipliers a debuff could otherwise drive to zero (or
## below): a cursed raider still hits, moves, gains XP and keeps its
## effects running, however many negative boons pile up.
const MIN_DAMAGE_MULTIPLIER: float = 0.1
const MIN_MOVE_MULTIPLIER: float = 0.2
const MIN_DURATION_MULTIPLIER: float = 0.1
const MIN_XP_MULTIPLIER: float = 0.1

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
## Iteration 39 stat layer:
## Flat extra projectiles on every volley weapon (WeaponBase.effective_projectile_count).
var projectile_bonus: int = 0
## Multiplier on timed weapon effects — slows, pools, poison (WeaponBase.duration_scale).
var duration_multiplier: float = 1.0
## Multiplier on XP this raider collects (XpGem applies it at pickup).
var xp_multiplier: float = 1.0
## This raider's contribution to the RUN-WIDE difficulty (fraction);
## published to RunState under a per-player source key on every recompute.
var difficulty_share: float = 0.0
## Gambling stacks taken (Tome of Chance); the rolled boons live in
## _gamble_boons and replay on every recompute.
var gambling_stacks: int = 0
## Iteration 48 stat layer:
## Extra mid-air jumps before touching the floor again (Player._try_jump).
var extra_jumps: int = 0
## Chance bonus, in percent, on power-up drops. NO CONSUMER YET: this is
## the forward hook for the power-ups of part C, the way demonic_uses was
## the hook for iteration 42. Altars already sell it, so the stat has to
## exist and survive recompute; deleting it as "dead data" would break the
## altar pool. Documented in docs/ARQUITECTURA.md.
var powerup_drop_chance: float = 0.0

## Ceiling on extra jumps. Not taste: the raider has no air control budget
## beyond air_acceleration, and past this an arena's verticality (mesas,
## platforms, the perimeter band) stops being a constraint at all.
const MAX_EXTRA_JUMPS: int = 5

## tome id -> one rarity potency per collected stack. recompute() derives
## every stat from this, so it is the single source of truth.
var _tome_stacks: Dictionary[String, PackedFloat32Array] = {}
## Tome of Chance outcomes, rolled ONCE at pickup and replayed by
## recompute(): [{stat, amount}] already potency-scaled.
var _gamble_boons: Array[Dictionary] = []
## Altar boons (iteration 41): permanent flat effects granted by charge /
## demonic altars and the roulette — independent of cards and tomes.
var _altar_boons: Array[Dictionary] = []
## Timed boons (springs, roulette curses): {stat, amount, expires_at}
## in RunState.run_time seconds; dropped (with a recompute) on expiry.
## Zenkai: percent per stack per copy, and the stats it lifts. max_hp and
## luck are flat channels, so the same number reads as +8 HP and +8 luck
## per stack rather than a percentage — accepted, because the alternative
## is a second table for two fields.
const ZENKAI_PERCENT_PER_STACK: float = 8.0
const ZENKAI_STATS: Array[String] = [
	"damage", "cooldown", "area", "move_speed", "crit_chance", "max_hp", "luck"]


var _timed_boons: Array[Dictionary] = []

## Character passive (CharacterCatalog row data). Kinds:
##   "per_level":       _passive_stat gains _passive_base plus
##                      _passive_amount per level past 1.
##   "speed_to_damage": bonus move speed converts to bonus damage at the
##                      _passive_amount ratio (0.6 = +0.6% dmg per +1% speed).
##   "evasion_execute": per_level scaling, plus every successful dodge
##                      executes a weakened non-boss attacker (_on_dodged).
## Empty stat id with a per-level kind = no passive.
## Every kind _apply_character_passive knows how to run; a catalog row
## outside this list is rejected at set time, not once per recompute.
const PASSIVE_KINDS: Array[String] = ["per_level", "evasion_execute", "speed_to_damage"]
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


## Number of DIFFERENT tomes carried (the 5-tome loadout cap counts these).
func distinct_tome_count() -> int:
	var count := 0
	for tome_id: String in _tome_stacks:
		if _tome_stacks[tome_id].size() > 0:
			count += 1
	return count


## Ids of every carried tome, in pickup order (HUD loadout strip).
func carried_tome_ids() -> Array[String]:
	var ids: Array[String] = []
	for tome_id: String in _tome_stacks:
		if _tome_stacks[tome_id].size() > 0:
			ids.append(tome_id)
	return ids


## Grants one stack of a tome at the given rarity potency. Stacks are
## UNCAPPED since iteration 46 — only the number of DISTINCT tomes is
## limited (Player.max_tomes, enforced by the offer pool).
## Returns the boons a gambling tome (Tomo del Azar) just rolled, so the
## card UI can toast what the bet paid; empty for every other tome.
func add_tome(tome_id: String, potency: float) -> Array[Dictionary]:
	# Packed arrays inside dictionaries are copy-on-write: mutate a copy,
	# then write it back.
	var stacks: PackedFloat32Array = _tome_stacks.get(tome_id, PackedFloat32Array())
	stacks.append(potency)
	_tome_stacks[tome_id] = stacks
	# Gambling tomes roll their boons right here, once, so the outcome is
	# fixed for the run and recompute() only replays it.
	var tome := Tome.by_id(tome_id)
	var rolled: Array[Dictionary] = []
	if bool(tome.get("gamble", false)):
		rolled = roll_gamble_boons(potency)
		_gamble_boons.append_array(rolled)
	recompute()
	return rolled


## Tome of Chance roll: potency 1 (Common) gives one boon at base size;
## each higher rarity adds a boon and scales every boon by the potency
## (Rare 1.5x/2 boons, Epic 2x/3, Legendary 3x/4). Distinct stats per roll.
## Static and pure so a harness can verify the distribution.
static func roll_gamble_boons(potency: float) -> Array[Dictionary]:
	var count := 1 + clampi(UpgradePool.potency_rank(potency), 0, 3)
	var pool := Tome.GAMBLE_BOONS.duplicate()
	pool.shuffle()
	var boons: Array[Dictionary] = []
	for i in mini(count, pool.size()):
		var boon: Dictionary = pool[i]
		boons.append({
			"stat": String(boon.stat),
			"amount": roundf(float(boon.amount) * potency),
			# Carried along so the HUD toast can read the roll (iteration 47).
			"label": String(boon.get("label", "")),
		})
	return boons


## The boons rolled so far (HUD/tests), in pickup order.
func gamble_boons() -> Array[Dictionary]:
	return _gamble_boons


## Permanent flat boon outside the card/tome economy (altars, roulette).
func add_altar_boon(stat: String, amount: float) -> void:
	_altar_boons.append({"stat": stat, "amount": amount})
	recompute()


func altar_boons() -> Array[Dictionary]:
	return _altar_boons


## Temporary boon for `duration` seconds of run time (negative amounts
## are debuffs). Expiry is polled in _physics_process.
##
## `tag` groups boons that belong to ONE re-issuable source (a power-up
## being picked up again while it is still running). Without it a refresh
## stacks with itself: the second Furia would add a second +100% damage and
## the first one's expiry would take only half of it away again.
func add_timed_boon(stat: String, amount: float, duration: float, tag: String = "") -> void:
	if duration <= 0.0:
		return
	_timed_boons.append({
		"stat": stat, "amount": amount, "expires_at": RunState.run_time + duration,
		"tag": tag})
	recompute()


## Drops every live boon carrying `tag` (an empty tag matches nothing, so
## untagged boons can never be cleared by accident). Returns true when
## something was actually removed.
func clear_timed_boons(tag: String) -> bool:
	if tag.is_empty():
		return false
	var removed := false
	for i in range(_timed_boons.size() - 1, -1, -1):
		if String(_timed_boons[i].get("tag", "")) == tag:
			_timed_boons.remove_at(i)
			removed = true
	if removed:
		recompute()
	return removed


func timed_boon_count() -> int:
	return _timed_boons.size()


func _physics_process(_delta: float) -> void:
	if _timed_boons.is_empty():
		return
	var expired := false
	for i in range(_timed_boons.size() - 1, -1, -1):
		if RunState.run_time >= float(_timed_boons[i].expires_at):
			_timed_boons.remove_at(i)
			expired = true
	if expired:
		recompute()


## Registers the selected character's passive (stat ids match _apply_effect;
## kinds are documented on _passive_kind). base_amount is granted already at
## level 1 (Doc's starting lifesteal). Called by the player at spawn with
## catalog row data.
func set_character_passive(stat: String, amount: float, kind: String = "per_level",
		base_amount: float = 0.0) -> void:
	if not PASSIVE_KINDS.has(kind):
		# Validated ONCE, here. The old check lived in the recompute path,
		# so a typo'd catalog row warned several times a second all run.
		push_warning("PlayerStats: unknown passive kind '%s'" % kind)
		kind = "per_level"
	_passive_kind = kind
	_passive_stat = stat
	_passive_amount = amount
	_passive_base = base_amount
	recompute()


## Rebuilds every derived stat from the stored tome stacks and the
## character passive (recompute, not accumulate). Call after any change.
## Four phases, in this order and no other: everything back to baseline,
## every source applied, the caps, then the push to outside consumers.
## True while recompute() is running. _push_bonus_max_hp_to_health writes
## max_hp and heals INSIDE that body, and both emit hp_changed — so any
## listener that can ask for another recompute (Zenkai does) has to be able
## to tell "the raider healed" from "the stat layer rebuilt itself".
func is_recomputing() -> bool:
	return _recomputing


var _recomputing: bool = false


func recompute() -> void:
	_recomputing = true
	_reset_derived()
	_apply_sources()
	_clamp_derived()
	_publish_derived()
	_recomputing = false


## Every derived field back to its baseline (the value with zero sources).
func _reset_derived() -> void:
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
	projectile_bonus = 0
	duration_multiplier = 1.0
	xp_multiplier = 1.0
	difficulty_share = 0.0
	gambling_stacks = 0
	extra_jumps = 0
	powerup_drop_chance = 0.0


## Every source, in the ONE order that matters: the character passive runs
## last because conversion kinds (speed_to_damage) read the totals the
## other sources built.
func _apply_sources() -> void:
	_apply_tomes()
	# Gambling boons replay in pickup order (already potency-scaled).
	_apply_boons(_gamble_boons)
	# Items (iteration 40): every copy of a stat item contributes its row
	# effects through the same channel.
	_apply_items()
	# The companion's stat (iteration 54): one slot, one row, level-scaled.
	_apply_pet_stat()
	# Altar boons and live timed boons (iteration 41).
	_apply_boons(_altar_boons)
	_apply_boons(_timed_boons)
	# Zenkai (iteration 56): a permanent all-stat channel, read from the
	# stacks the bag banked. Same shape as the power-up total below — a
	# stored count re-applied on every rebuild, never accumulated onto a
	# derived value that _reset_derived would wipe.
	_apply_zenkai()
	# Power-ups (iteration 53): the vampire's permanent max HP is a STORED
	# TOTAL on the component, re-added here on every recompute — never
	# accumulated onto bonus_max_hp, which _reset_derived wipes.
	_apply_powerups()
	# Armory relics (iteration 36): permanent meta ranks, applied through
	# the same effect channel as tomes so stacking rules stay identical.
	_apply_relics()
	_apply_character_passive()


func _apply_tomes() -> void:
	for tome_id: String in _tome_stacks:
		var tome := Tome.by_id(tome_id)
		if tome.is_empty():
			push_warning("PlayerStats: unknown tome '%s'" % tome_id)
			continue
		# Counted from the stacks themselves, not from the effect amount:
		# the effect is potency-scaled, the stack count must not be.
		if bool(tome.get("gamble", false)):
			gambling_stacks += _tome_stacks[tome_id].size()
		var effects: Array = tome.effects
		for potency: float in _tome_stacks[tome_id]:
			for effect: Dictionary in effects:
				# roundf matches the card text, so displayed == applied.
				_apply_effect(String(effect.stat), roundf(float(effect.amount) * potency))


## One list of {stat, amount} boons through the effect channel. Gamble,
## altar and timed boons all share this shape, so they share the loop.
func _apply_boons(boons: Array[Dictionary]) -> void:
	for boon: Dictionary in boons:
		_apply_effect(String(boon.stat), float(boon.amount))


## The caps, after every source: stacking is additive, so without these a
## deep enough build reaches zero cooldowns or 100% dodge.
func _clamp_derived() -> void:
	cooldown_multiplier = maxf(cooldown_multiplier, min_cooldown_multiplier)
	damage_multiplier = maxf(damage_multiplier, MIN_DAMAGE_MULTIPLIER)
	move_speed_multiplier = maxf(move_speed_multiplier, MIN_MOVE_MULTIPLIER)
	crit_chance = clampf(crit_chance, 0.0, 1.0)
	evasion = clampf(evasion, 0.0, max_evasion)
	luck = maxf(luck, 0.0)
	duration_multiplier = maxf(duration_multiplier, MIN_DURATION_MULTIPLIER)
	xp_multiplier = maxf(xp_multiplier, MIN_XP_MULTIPLIER)
	projectile_bonus = maxi(projectile_bonus, 0)


## Pushes the finished totals to the consumers that cannot read them
## themselves: the sibling Health (armor, bonus max HP) and the run-wide
## difficulty pool.
func _publish_derived() -> void:
	_push_armor_to_health()
	_push_bonus_max_hp_to_health()
	_publish_difficulty()


## Run-wide difficulty is shared, so each raider publishes its own total
## under a per-slot key; RunState sums the sources (recompute-safe).
func _publish_difficulty() -> void:
	var parent := get_parent()
	var slot := int(parent.get("player_index")) if parent != null and parent.get("player_index") != null else 0
	RunState.set_difficulty_source("tomes_p%d" % slot, difficulty_share)


## Sibling ItemBag counts x catalog effects (no bag = no items). One pass
## over the bag: a row's own effects scale with the copies carried, and a
## pet row also grants its per-level stat (iteration 43).
func _apply_items() -> void:
	var bag := ItemBag.find_in(get_parent())
	if bag == null:
		return
	for item_id: String in bag.carried_ids():
		var row := ItemCatalog.by_id(item_id)
		var copies := bag.count(item_id)
		for effect: Dictionary in row.get("effects", [] as Array):
			_apply_effect(String(effect.stat), float(effect.amount) * float(copies))


## The companion's stat, scaling with the run level like a character
## passive. Read off the raider's single pet slot (iteration 54): pets are
## no longer items, there are no copies to scale by, and the slot holds
## exactly one id or none.
func _apply_pet_stat() -> void:
	var body := get_parent()
	if body == null:
		return
	var pet_id: Variant = body.get("pet_id")
	if pet_id == null or String(pet_id).is_empty():
		return
	var pet := PetCatalog.by_id(String(pet_id))
	var stat := String(pet.get("stat", ""))
	if stat.is_empty():
		return
	_apply_effect(stat, float(pet.get("amount_per_level", 0.0)) * float(RunState.level))


## Zenkai stacks lift EVERY stat that matters by a flat percentage each.
## Deliberately broad: the item is Legendary, it only pays when the raider
## came back from under 10% HP, and a narrow bonus would be invisible next
## to the tomes already stacked by the time it triggers.
func _apply_zenkai() -> void:
	var bag := ItemBag.find_in(get_parent())
	if bag == null:
		return
	var stacks := bag.zenkai_stacks
	if stacks <= 0:
		return
	var percent := float(stacks) * ZENKAI_PERCENT_PER_STACK
	for stat: String in ZENKAI_STATS:
		_apply_effect(stat, percent)


## Permanent totals banked by power-ups (Modo vampiro raises max HP per
## kill). The component owns the number; this only re-applies it.
func _apply_powerups() -> void:
	var powerups := PowerUps.find_in(get_parent())
	if powerups == null or is_zero_approx(powerups.permanent_max_hp):
		return
	_apply_effect("max_hp", powerups.permanent_max_hp)


## Every owned Armory rank contributes its catalog effect (SaveData holds
## the ranks; a fresh save contributes nothing).
func _apply_relics() -> void:
	for relic: Dictionary in RelicCatalog.RELIC_LIBRARY:
		var rank := SaveData.relic_rank(String(relic.id))
		if rank > 0:
			_apply_effect(String(relic.stat), float(relic.amount) * float(rank))


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
		"projectiles":
			projectile_bonus += roundi(amount)
		"duration":
			duration_multiplier += amount / 100.0
		"xp_gain":
			xp_multiplier += amount / 100.0
		"difficulty":
			difficulty_share += amount / 100.0
		"jumps":
			extra_jumps = mini(extra_jumps + roundi(amount), MAX_EXTRA_JUMPS)
		"powerup_chance":
			powerup_drop_chance += amount
		"gambling":
			# No-op by design: the boons were rolled at pickup and replay
			# from _gamble_boons, and gambling_stacks counts STACKS, which
			# _apply_tomes reads from the stack list (this amount is
			# potency-scaled, so it would count 3 for one Legendary stack).
			pass
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
## A raise also heals by the delta — clamped by heal(), never an overheal;
## a drop needs nothing here, because Health.max_hp's setter clamps
## current_hp itself and signals the change (a downed body is left at 0 and
## revives at a fraction of the max it now has).
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
