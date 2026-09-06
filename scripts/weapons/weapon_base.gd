class_name WeaponBase
extends Node3D
## Base for auto-firing weapons: ticks a cooldown and calls fire() at the
## nearest body in the "enemies" group within targeting_range().
## Subclasses override fire() with their attack behavior and funnel every
## hit through deal_damage(), so the player's global stats layer (damage
## multiplier, crit, lifesteal) applies in exactly one place. Cooldown and
## area-like reach respect the stats layer through the effective_* helpers.
## Area weapons scan the horde through the enemies_in_* helpers below: that
## loop used to be copied into eight weapons, with the height and liveness
## filters quietly drifting apart between the copies.

## Effective cooldown can never drop below this many seconds.
const MIN_COOLDOWN: float = 0.05
## Below this squared length an aim vector carries no usable direction (the
## target sits exactly on the muzzle); weapons fall back to their facing.
const DEGENERATE_LENGTH_SQ: float = 0.0001
## Past this |dot| with UP a direction is colinear with the world up axis,
## where look_at / Basis.looking_at cannot build a basis from UP.
const UP_COLINEAR_DOT: float = 0.99

@export var damage: float = 10.0
@export var cooldown: float = 1.0
@export var attack_range: float = 3.0
@export var projectile_count: int = 1
## Per-weapon cooldown multiplier ("Flurry"-style upgrades lower it); stacks
## multiplicatively with the player-wide cooldown multiplier, leaving the
## base cooldown untouched.
@export var cooldown_scale: float = 1.0

## Upgrade cards this weapon has received this run (bumped by
## UpgradePool.apply); the evolution/ascension gate (EvolutionCatalog).
var upgrade_level: int = 0
## True once evolve() ran; an evolved weapon never evolves again.
var evolved: bool = false
## The evolved form's display name ("" until evolved).
var evolved_name: String = ""
## Milestones of EvolutionCatalog.EVOLVE_AT_LEVEL this weapon has passed
## (iteration 46): tier 1 is level 10 — the evolution for weapons with a
## recipe, a plain ascension for the rest — then one per further multiple.
var ascension_tier: int = 0

## Flat ascension step, applied ON TOP of whatever the weapon already is,
## at every EvolutionCatalog.EVOLVE_AT_LEVEL milestone past the first.
## It lives here, not in the catalog, because it needs no recipe row: a
## weapon nobody wrote an evolution for still improves every ten levels.
const ASCEND_MULTS: Dictionary[String, float] = {
	"damage": 1.15, "cooldown_scale": 0.9, "attack_range": 1.1}
## Extra projectile granted on EVEN tiers only (20, 40, ...): one per tier
## would double a volley weapon's output far faster than the flat mults.
const ASCEND_PROJECTILE_TIER_STEP: int = 2
const ASCEND_PROJECTILE_ADD: int = 1

var _cooldown_left: float = 0.0

## The carrying player's stats layer; null means neutral multipliers (e.g.
## a weapon exercised outside a player rig in tests). Always read through
## _stats_or_null(), never directly: a weapon can outlive its carrier.
@onready var _stats: PlayerStats = _find_carrier_stats()
## The carrier's item bag (iteration 40): hit/kill hooks for on-hit items.
@onready var _bag: ItemBag = ItemBag.find_in(carrier_player())


# --- carrier ---------------------------------------------------------------

## The player body carrying this weapon (walks up the ancestry, so each
## co-op raider's weapons read THEIR stats); test rigs without a Player
## ancestor fall back to the first player in the scene, as before.
func carrier_player() -> Node3D:
	var node: Node = self
	while node != null:
		if node is Player:
			return node
		node = node.get_parent()
	return get_tree().get_first_node_in_group("player") as Node3D


## The rig this weapon is mounted on: the Pet companion when one carries it,
## otherwise the raider. Carrier-anchored effects (the slime trail's drop
## point, the spirit ring's center) follow THIS so a pet's weapon acts around
## the pet; stats, lifesteal and item hooks keep reading carrier_player().
func carrier_node() -> Node3D:
	var node: Node = self
	while node != null:
		if node is Pet or node is Player:
			return node as Node3D
		node = node.get_parent()
	return carrier_player()


func _find_carrier_stats() -> PlayerStats:
	var carrier := carrier_player()
	return PlayerStats.find_in(carrier) if carrier != null else null


## The carrier's stats, or null when there are none to read. Drops a stale
## reference instead of touching a freed object, the same guard deal_damage
## already applied to _bag — every multiplier below has a neutral null path.
func _stats_or_null() -> PlayerStats:
	if _stats != null and not is_instance_valid(_stats):
		_stats = null
	return _stats


# --- firing cycle ----------------------------------------------------------

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
	var stats := _stats_or_null()
	return damage * (stats.damage_multiplier if stats != null else 1.0)


func effective_cooldown() -> float:
	var stats := _stats_or_null()
	var multiplier := stats.cooldown_multiplier if stats != null else 1.0
	return maxf(cooldown * multiplier * cooldown_scale, MIN_COOLDOWN)


## Multiplier subclasses apply to their area-like reach (burst radius,
## melee arc range) — deliberately not to the targeting attack_range, except
## where a weapon widens its targeting to match (see targeting_range()).
func area_scale() -> float:
	var stats := _stats_or_null()
	return stats.area_multiplier if stats != null else 1.0


## Shots/orbs/arrows per volley: the weapon's own count plus the carrier's
## flat projectile bonus (Tome of Multitude, iteration 39). Weapons that
## fan projectiles read this instead of projectile_count.
func effective_projectile_count() -> int:
	var stats := _stats_or_null()
	return projectile_count + (stats.projectile_bonus if stats != null else 0)


## Multiplier for timed effects a weapon leaves behind (slows, pools,
## poison): Tome of Lingering stretches them (iteration 39).
func duration_scale() -> float:
	var stats := _stats_or_null()
	return stats.duration_multiplier if stats != null else 1.0


## Distance acquire_target() searches. Aimed weapons keep the raw
## attack_range; weapons whose hit area IS attack_range * area_scale()
## (Aura, Stench) widen this to match, or the outer band of their own ring
## becomes decorative and they never pulse at enemies standing in it.
func targeting_range() -> float:
	return attack_range


## Nearest body in the "enemies" group within targeting_range(), or null.
func acquire_target() -> Node3D:
	# Empty-horde fast path: while nothing is alive this runs every physics
	# frame, so skip the Array get_nodes_in_group would build.
	if get_tree().get_first_node_in_group("enemies") == null:
		return null
	var nearest: Node3D = null
	var search_range := targeting_range()
	var nearest_dist_sq := search_range * search_range
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


# --- damage funnel ---------------------------------------------------------

## Shared damage funnel: applies effective damage, rolls crit, and heals the
## player for lifesteal. Every weapon hit goes through here.
## Returns the damage ACTUALLY applied, not the raw roll: Health subtracts
## armor, ignores hits on an already dead body, and a killing blow only
## removes the HP that was left. Damage-derived effects (lifesteal, Blood
## Vial's innate drain) pay out on that, so armored targets no longer heal
## the player as if their armor did not exist.
## `allow_kill_hooks` is false for hits that came FROM an item-spawned
## projectile (ItemBag's spiders): letting their kills spawn more spiders
## turns one kill into an exponential cascade that drains the dart pool.
func deal_damage(target_health: Health, allow_kill_hooks: bool = true) -> float:
	var stats := _stats_or_null()
	var amount := effective_damage()
	var is_crit := stats != null and randf() < stats.crit_chance
	if is_crit:
		amount *= stats.crit_damage
		Juice.crit_punch()
	Sfx.play(&"hit_crit" if is_crit else &"hit_soft")
	# Health reports nothing back, so read the HP it actually removed.
	var hp_before := target_health.current_hp
	target_health.take_damage(amount, is_crit)
	var applied := maxf(hp_before - target_health.current_hp, 0.0)
	if applied <= 0.0:
		# Dodged, or the body was already dead when this hit landed. Firing
		# the item hooks here used to poison corpses and — worse — run
		# on_weapon_kill a second time for a body someone else already killed.
		return 0.0
	if stats != null and stats.lifesteal > 0.0:
		_lifesteal_heal(applied * stats.lifesteal)
	# Item hooks (iteration 40): on-hit poison, on-kill spiders.
	if _bag != null and is_instance_valid(_bag):
		var body := target_health.get_parent() as Node3D
		if body != null:
			_bag.on_weapon_hit(body)
			if allow_kill_hooks and target_health.is_dead:
				_bag.on_weapon_kill(body.global_position, self)
	return applied


func _lifesteal_heal(amount: float) -> void:
	var player := carrier_player()
	if player == null:
		return
	var player_health := Health.find_in(player)
	if player_health != null:
		player_health.heal(amount)


## Damages every body in `bodies` through the funnel above; returns the
## total damage actually applied (Blood Vial's innate drain reads it).
func damage_all(bodies: Array[Node3D]) -> float:
	var total := 0.0
	for body: Node3D in bodies:
		var health := Health.find_in(body)
		if health != null:
			total += deal_damage(health)
	return total


# --- horde scans -----------------------------------------------------------
# One home for "walk the enemies group, keep the live bodies, test a shape".
# Each helper returns the bodies it found; callers hand them to damage_all()
# and add their own per-enemy effects (poison, slow, sparks).

## Live enemies inside a flat disc: within `radius` of `center` on the XZ
## plane and no farther than `height_window` above or below it. The height
## filter is what keeps a ground pool from reaching bodies on a ledge.
func enemies_in_disc(center: Vector3, radius: float, height_window: float) -> Array[Node3D]:
	var found: Array[Node3D] = []
	var radius_sq := radius * radius
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var body := node as Node3D
		if body == null or not body.is_inside_tree():
			continue
		var to_body := body.global_position - center
		if absf(to_body.y) > height_window:
			continue
		to_body.y = 0.0
		if to_body.length_squared() <= radius_sq:
			found.append(body)
	return found


## Live enemies inside a full sphere of `radius` around `center` — bursts
## that should also catch bodies well above or below their center.
func enemies_in_sphere(center: Vector3, radius: float) -> Array[Node3D]:
	var found: Array[Node3D] = []
	var radius_sq := radius * radius
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var body := node as Node3D
		if body == null or not body.is_inside_tree():
			continue
		if center.distance_squared_to(body.global_position) <= radius_sq:
			found.append(body)
	return found


## Live enemies inside a flat lane from `origin`: between 0 and `length`
## along `direction` (which must be flat and normalized) and at most
## `half_width` off its axis.
func enemies_in_lane(origin: Vector3, direction: Vector3, length: float,
		half_width: float) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var body := node as Node3D
		if body == null or not body.is_inside_tree():
			continue
		var to_body := body.global_position - origin
		to_body.y = 0.0
		var along := to_body.dot(direction)
		if along < 0.0 or along > length:
			continue
		if (to_body - direction * along).length() <= half_width:
			found.append(body)
	return found


## Live enemies inside a flat cone of `arc_deg` around `center_dir`, out to
## `reach` (measured in 3D from `center`). A body standing on top of the
## caster carries no usable direction, so it always counts as inside.
func enemies_in_arc(center: Vector3, center_dir: Vector3, reach: float,
		arc_deg: float) -> Array[Node3D]:
	var found: Array[Node3D] = []
	var reach_sq := reach * reach
	var half_arc := deg_to_rad(arc_deg * 0.5)
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var body := node as Node3D
		if body == null or not body.is_inside_tree():
			continue
		if center.distance_squared_to(body.global_position) > reach_sq:
			continue
		var to_body := body.global_position - center
		to_body.y = 0.0
		if to_body.length_squared() > DEGENERATE_LENGTH_SQ \
				and center_dir.angle_to(to_body) > half_arc:
			continue
		found.append(body)
	return found


# --- aim helpers -----------------------------------------------------------

## `vector` normalized, or `fallback` when it is too short to carry a
## direction (the target is sitting exactly on the muzzle).
static func aim_dir_or(vector: Vector3, fallback: Vector3) -> Vector3:
	return vector.normalized() if vector.length_squared() > DEGENERATE_LENGTH_SQ \
			else fallback


## `vector` flattened onto the XZ plane and normalized, or `fallback` when
## nothing is left of it (target directly above or below us).
static func flat_dir_or(vector: Vector3, fallback: Vector3) -> Vector3:
	vector.y = 0.0
	return vector.normalized() if vector.length_squared() > DEGENERATE_LENGTH_SQ \
			else fallback


## Up vector safe to build a basis with for `direction`: near-vertical aim
## (shooting at something straight below a ledge) runs colinear with UP,
## which leaves look_at / Basis.looking_at without a basis to build.
static func safe_up(direction: Vector3) -> Vector3:
	return Vector3.UP if absf(direction.dot(Vector3.UP)) < UP_COLINEAR_DOT \
			else Vector3.RIGHT


# --- throwaway FX ----------------------------------------------------------

## Parents a one-shot FX mesh under the current scene (tree root as the
## headless fallback) so it plays out where it was born while the carrier
## walks on. The caller owns placement, scaling and the fade that frees it.
## Shared `mesh` resources are the point: building a Mesh per effect is the
## per-spawn churn Pools exists to avoid.
func spawn_fx_mesh(mesh: Mesh) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var parent_node: Node = get_tree().current_scene
	if parent_node == null:
		parent_node = get_tree().root
	parent_node.add_child(node)
	return node


# --- evolution -------------------------------------------------------------

## Applies an EvolutionCatalog row to this live weapon: every "mults" entry
## multiplies the named property, every "adds" entry adds to it.
## Idempotent: a second call is a no-op.
func evolve(row: Dictionary) -> void:
	if evolved:
		return
	evolved = true
	evolved_name = String(row.get("evolved_name", name))
	_apply_stat_tables(row.get("mults", {}), row.get("adds", {}), "evolve")


## Ascension step (iteration 46): the flat, recipe-free upgrade a weapon
## takes at every EvolutionCatalog.EVOLVE_AT_LEVEL milestone past the
## first, so weapons without an evolution row keep improving too.
## `tier` is the milestone number (1 = level 10, 2 = level 20, ...).
func ascend(tier: int) -> void:
	ascension_tier = tier
	var adds: Dictionary[String, int] = {}
	if tier % ASCEND_PROJECTILE_TIER_STEP == 0:
		adds["projectile_count"] = ASCEND_PROJECTILE_ADD
	_apply_stat_tables(ASCEND_MULTS, adds, "ascend")


## Applies a {property: factor} multiply table and a {property: amount}
## add table onto this weapon's own properties, generically through
## get()/set() so subclass-only knobs (burst_radius, pierce_count) need no
## per-weapon code. Shared by evolve() and ascend(); `what` only names the
## caller in the warning a mistyped table would raise.
func _apply_stat_tables(mults: Dictionary, adds: Dictionary, what: String) -> void:
	for property: Variant in mults:
		var current: Variant = get(String(property))
		if current == null:
			push_warning("%s: %s mult on unknown property '%s'" % [name, what, property])
			continue
		# Int knobs (projectile_count, pierce_count, chain_count) round to the
		# nearest whole step instead of taking GDScript's truncation, so a
		# "x1.5" on 3 reads as the 5 the card promises, not 4.
		if current is int:
			set(String(property), roundi(float(current) * float(mults[property])))
		else:
			set(String(property), float(current) * float(mults[property]))
	for property: Variant in adds:
		var current: Variant = get(String(property))
		if current == null:
			push_warning("%s: %s add on unknown property '%s'" % [name, what, property])
			continue
		if current is int:
			set(String(property), int(current) + int(adds[property]))
		else:
			set(String(property), float(current) + float(adds[property]))
