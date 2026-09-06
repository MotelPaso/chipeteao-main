class_name Health
extends Node
## Reusable health component. Attach as a child of any body; bodies in the
## "enemies" group with a Health child are damageable by weapons.
## Emits died once when HP reaches zero; heal_full() re-arms it.

signal damaged(amount: float, current: float)
## Emitted alongside `damaged` when the hit named its attacker (enemy
## contact damage does); thorns-style retaliation hooks onto this.
signal damaged_by(attacker: Node3D)
## Emitted instead of `damaged` when the owner fully evaded the hit (the
## player's evasion roll); dodge-execute passives hook onto this. The
## attacker is whatever the dodged hit named, possibly null.
signal dodged(attacker: Node3D)
## Non-damage HP changes (max_hp raises, full heals) so health bars can
## re-read both values; damage keeps the dedicated signal above.
signal hp_changed(current: float, max_hp: float)
signal died

## Max HP. The setter owns the "current_hp never exceeds max_hp" invariant
## so no call site has to remember it: a body that was at FULL HP stays
## full (every "scale this enemy up" site — tiers, elites, sky variants —
## gets the tank it asked for), a wounded one keeps its HP clamped down,
## and either way hp_changed reports both values so bars never paint a
## current above the maximum.
@export var max_hp: float = 50.0:
	set(value):
		var was_full := _initialized and is_equal_approx(current_hp, max_hp)
		max_hp = value
		# Scene instantiation writes this export BEFORE _ready seeds
		# current_hp: there is no invariant to keep yet (and nothing is
		# connected to hp_changed either), so don't fake one.
		if not _initialized:
			return
		current_hp = max_hp if was_full else minf(current_hp, max_hp)
		hp_changed.emit(current_hp, max_hp)
@export var show_damage_popups: bool = true
## Flat damage reduction applied before HP loss; the player's PlayerStats
## layer writes this from Tome of Stone stacks. A hit always chips at least
## MIN_CHIP_DAMAGE (or the raw amount when it was already below it).
@export var armor: float = 0.0
## Floating text on a fully evaded hit (the player's evasion roll). An
## @export so it travels with the rest of the player-facing strings.
@export var dodge_text: String = "¡Esquiva!"

const DODGE_POPUP_COLOR := Color(0.5, 0.88, 1.0)
## Armor can never fully negate a hit: every landed blow chips this much,
## so a stacked-armor build still has to dodge instead of going immortal.
const MIN_CHIP_DAMAGE: float = 1.0

var current_hp: float
var is_dead: bool = false
## True once _ready seeded current_hp; before that the max_hp setter has
## no current_hp to keep coherent.
var _initialized: bool = false


func _ready() -> void:
	current_hp = max_hp
	_initialized = true


## Finds the Health component on a body, or null if it has none.
static func find_in(body: Node) -> Health:
	for child in body.get_children():
		if child is Health:
			return child
	return null


## `attacker` (optional) is the body that dealt the hit; contact attackers
## pass themselves so thorns can retaliate through damaged_by.
## RETURNS the HP this hit actually removed: 0.0 when it was refused (dead
## body, non-positive amount) or fully evaded, the armor-reduced amount
## otherwise, and only the HP that was LEFT on a killing blow. Callers that
## pay out on damage dealt (weapon lifesteal, the Blood Vial's drain) read
## this instead of sampling current_hp before and after — sampling credited
## an overkill hit for the sliver it happened to find, and could not tell a
## dodge from a hit that landed for zero.
func take_damage(amount: float, is_crit: bool = false, attacker: Node3D = null) -> float:
	if is_dead or amount <= 0.0:
		return 0.0
	var evade_chance := _evasion_chance()
	if evade_chance > 0.0 and randf() < evade_chance:
		if show_damage_popups:
			_spawn_popup(dodge_text, 64, DODGE_POPUP_COLOR)
		Sfx.play(&"dodge")
		dodged.emit(attacker)
		return 0.0
	var final_amount := minf(amount, maxf(amount - armor, MIN_CHIP_DAMAGE))
	# What the body could still lose: an overkill blow is credited for the
	# HP it removed, never for the raw roll.
	var applied := minf(final_amount, current_hp)
	current_hp = maxf(current_hp - final_amount, 0.0)
	if show_damage_popups:
		_spawn_damage_popup(final_amount, is_crit)
	damaged.emit(final_amount, current_hp)
	# Before the death check so even a lethal blow is repaid.
	if attacker != null:
		damaged_by.emit(attacker)
	if current_hp <= 0.0:
		is_dead = true
		died.emit()
	return applied


## Voluntary HP payment (Greed Shrine): unlike take_damage it ignores
## armor, spawns no popup, and can never kill — the cost is clamped so at
## least min_remaining HP stays. Returns the HP actually paid.
func pay(amount: float, min_remaining: float = 1.0) -> float:
	if is_dead or amount <= 0.0:
		return 0.0
	var paid := minf(amount, maxf(current_hp - min_remaining, 0.0))
	current_hp -= paid
	hp_changed.emit(current_hp, max_hp)
	return paid


## Partial heal (lifesteal etc.): clamped to max_hp, no-op once dead.
func heal(amount: float) -> void:
	if is_dead or amount <= 0.0:
		return
	current_hp = minf(current_hp + amount, max_hp)
	hp_changed.emit(current_hp, max_hp)


func heal_full() -> void:
	current_hp = max_hp
	is_dead = false
	hp_changed.emit(current_hp, max_hp)


## Co-op revive: re-arms a dead Health at `fraction` of max HP (died can
## fire again on the next fatal hit). No-op on a body that isn't dead.
func revive(fraction: float) -> void:
	if not is_dead:
		return
	is_dead = false
	current_hp = clampf(max_hp * fraction, 1.0, max_hp)
	hp_changed.emit(current_hp, max_hp)


## Chance (0-1) this body fully evades a hit: only the player evades, read
## from its PlayerStats layer (which caps the stat); enemies never roll.
func _evasion_chance() -> float:
	var body := get_parent()
	if body == null or not body.is_in_group("player"):
		return 0.0
	var stats := PlayerStats.find_in(body)
	return stats.evasion if stats != null else 0.0


func _spawn_damage_popup(amount: float, is_crit: bool) -> void:
	_spawn_popup(str(roundi(amount)), 88 if is_crit else 64,
			Color(1.0, 0.3, 0.15) if is_crit else Color(1.0, 0.85, 0.25))


func _spawn_popup(popup_text: String, popup_font_size: int, color: Color) -> void:
	var body := get_parent() as Node3D
	if body == null:
		return
	# Pooled Label3D with the same look/motion as the old code-built one;
	# Pools parents it to the scene root so it survives the body dying.
	var popup := Pools.acquire_scene(Pools.DAMAGE_POPUP_SCENE) as DamagePopup
	if popup == null:
		return
	popup.show_popup(popup_text, popup_font_size, color, body.global_position
			+ Vector3(randf_range(-0.3, 0.3), 2.0, randf_range(-0.3, 0.3)))
