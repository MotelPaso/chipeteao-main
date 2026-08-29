class_name UpgradePool
extends RefCounted
## Data-driven pool of level-up upgrades with rarity weighting (GDD 3/4).
## The offer pool is rebuilt per roll from:
##   - GENERIC_POOL: player/health/run_state tweaks, always available.
##   - Per-OWNED-weapon stat entries (damage/cooldown/range, plus extras
##     declared in WEAPON_LIBRARY), so every carried weapon keeps scaling.
##   - "new_weapon" cards for library weapons the player does NOT own yet,
##     hidden entirely once the player's max_weapons cap is reached.
## Entry fields:
##   kind:     "stat" (default, omitted) or "new_weapon"
##   target:   "player" | "health" | "run_state" | "weapon/<NodeName>"
##             (weapons are looked up under the player's Weapons mount)
##   op:       "mul_percent" (amount = +/- percent) | "add" (flat amount)
##   description: "%d" slot filled with the rarity-scaled amount;
##             new_weapon descriptions are shown verbatim.
##   offer_weight: relative chance of appearing in an offer (default 1.0).
##   rarity:   fixes the card's rarity tier by name instead of rolling one.
## Rarity multiplies the base amount (an Epic +25% card rolls +50%), so
## future weapons/tomes just append entries — the card UI never changes.

## Every equippable weapon: new_weapon cards and per-owned-weapon stat
## entries are generated from this, so adding a weapon is one new row.
const WEAPON_LIBRARY: Array[Dictionary] = [
	{
		"id": "shortsword", "display_name": "Shortsword",
		"node_name": "Shortsword", "scene": "res://scenes/weapons/Shortsword.tscn",
		"flavor": "sweeps a melee arc through nearby foes",
	},
	{
		"id": "dart_pistol", "display_name": "Dart Pistol",
		"node_name": "DartPistol", "scene": "res://scenes/weapons/DartPistol.tscn",
		"flavor": "snipes the nearest foe with fast homing darts",
		"extra_entries": [
			{
				"id": "dart_pistol_projectiles", "title": "Split Darts",
				"description": "Dart Pistol fires %d extra dart(s)",
				"target": "weapon/DartPistol", "property": "projectile_count",
				"op": "add", "amount": 1.0,
			},
		],
	},
	{
		"id": "ember_wand", "display_name": "Ember Wand",
		"node_name": "EmberWand", "scene": "res://scenes/weapons/EmberWand.tscn",
		"flavor": "detonates fire bursts on distant packs",
	},
]

## Fallback weapon cap when the player script doesn't export max_weapons.
const DEFAULT_MAX_WEAPONS: int = 4
## New-weapon cards show up meaningfully but less often than stat cards.
const NEW_WEAPON_OFFER_WEIGHT: float = 0.6

const GENERIC_POOL: Array[Dictionary] = [
	{
		"id": "max_hp", "title": "Stout Heart",
		"description": "Max HP +%d and heal to full",
		"target": "health", "property": "max_hp",
		"op": "add", "amount": 20.0, "full_heal": true,
	},
	{
		"id": "move_speed", "title": "Fleet Feet",
		"description": "Move speed +%d%%",
		"target": "player", "property": "move_speed",
		"op": "mul_percent", "amount": 8.0,
	},
	{
		"id": "pickup_radius", "title": "Greed Aura",
		"description": "Pickup radius +%d%%",
		"target": "run_state", "property": "pickup_radius_multiplier",
		"op": "mul_percent", "amount": 25.0,
	},
]

const RARITIES: Array[Dictionary] = [
	{"name": "Common", "color": Color(0.62, 0.65, 0.68), "weight": 60.0, "potency": 1.0},
	{"name": "Rare", "color": Color(0.3, 0.55, 1.0), "weight": 25.0, "potency": 1.5},
	{"name": "Epic", "color": Color(0.68, 0.32, 0.95), "weight": 12.0, "potency": 2.0},
	{"name": "Legendary", "color": Color(1.0, 0.78, 0.2), "weight": 3.0, "potency": 3.0},
]


## Rolls `count` distinct upgrades from the pool valid for this player's
## loadout, each with an independently weighted rarity. Returns
## display-ready dicts: entry, rarity, amount, title, description.
static func roll_offer(player: Node, count: int = 3) -> Array[Dictionary]:
	var offer: Array[Dictionary] = []
	for entry: Dictionary in _weighted_pick(build_pool(player), count):
		var rarity := _rarity_for(entry)
		if String(entry.get("kind", "stat")) == "new_weapon":
			offer.append({
				"entry": entry,
				"rarity": rarity,
				"amount": 0.0,
				"title": entry.title,
				"description": entry.description,
			})
			continue
		var amount: float = roundf(entry.amount * rarity.potency)
		offer.append({
			"entry": entry,
			"rarity": rarity,
			"amount": amount,
			"title": entry.title,
			"description": entry.description % absi(roundi(amount)),
		})
	return offer


## The full pool the player can currently roll from: generic entries, stat
## entries for each owned weapon, and new_weapon cards for unowned ones
## (none once the weapon cap is reached).
static func build_pool(player: Node) -> Array[Dictionary]:
	var pool := GENERIC_POOL.duplicate()
	var mount := player.get_node_or_null("Weapons") if player != null else null
	if mount == null:
		return pool
	var owned := 0
	for weapon: Dictionary in WEAPON_LIBRARY:
		if mount.has_node(String(weapon.node_name)):
			owned += 1
			pool.append_array(_entries_for_weapon(weapon))
	if owned < _max_weapons(player):
		for weapon: Dictionary in WEAPON_LIBRARY:
			if not mount.has_node(String(weapon.node_name)):
				pool.append(_new_weapon_entry(weapon))
	return pool


## Applies one rolled offer to the live nodes reachable from `player`.
static func apply(offer: Dictionary, player: Node) -> void:
	var entry: Dictionary = offer.entry
	if String(entry.get("kind", "stat")) == "new_weapon":
		_grant_weapon(entry, player)
		return
	var target := _resolve_target(entry.target, player)
	if target == null:
		push_warning("UpgradePool: target '%s' not found for '%s'" % [entry.target, entry.id])
		return
	var amount: float = offer.amount
	var current: float = target.get(entry.property)
	match entry.op:
		"mul_percent":
			target.set(entry.property, current * (1.0 + amount / 100.0))
		"add":
			target.set(entry.property, current + amount)
		_:
			push_warning("UpgradePool: unknown op '%s' in '%s'" % [entry.op, entry.id])
	if entry.get("full_heal", false) and target is Health:
		target.heal_full()


## Stat entries every owned weapon contributes (same scaling for all
## weapons; per-weapon extras ride along from the library row).
static func _entries_for_weapon(weapon: Dictionary) -> Array[Dictionary]:
	var display: String = weapon.display_name
	var target: String = "weapon/" + String(weapon.node_name)
	var entries: Array[Dictionary] = [
		{
			"id": String(weapon.id) + "_damage", "title": "Honed Edge",
			"description": display + " damage +%d%%",
			"target": target, "property": "damage",
			"op": "mul_percent", "amount": 25.0,
		},
		{
			"id": String(weapon.id) + "_cooldown", "title": "Quick Grip",
			"description": display + " cooldown -%d%%",
			"target": target, "property": "cooldown",
			"op": "mul_percent", "amount": -10.0,
		},
		{
			"id": String(weapon.id) + "_range", "title": "Long Reach",
			"description": display + " range +%d%%",
			"target": target, "property": "attack_range",
			"op": "mul_percent", "amount": 15.0,
		},
	]
	for extra: Dictionary in weapon.get("extra_entries", [] as Array[Dictionary]):
		entries.append(extra)
	return entries


static func _new_weapon_entry(weapon: Dictionary) -> Dictionary:
	return {
		"id": "gain_" + String(weapon.id),
		"kind": "new_weapon",
		"title": String(weapon.display_name),
		"description": "New weapon: " + String(weapon.flavor),
		"scene": String(weapon.scene),
		"weapon_name": String(weapon.node_name),
		"rarity": "Rare",
		"offer_weight": NEW_WEAPON_OFFER_WEIGHT,
	}


static func _grant_weapon(entry: Dictionary, player: Node) -> void:
	var mount := player.get_node_or_null("Weapons")
	if mount == null:
		push_warning("UpgradePool: no Weapons mount on player for '%s'" % entry.id)
		return
	# Offers filter owned weapons, but a stale queued reroll could race.
	if mount.has_node(String(entry.weapon_name)):
		return
	var scene := load(String(entry.scene)) as PackedScene
	if scene == null:
		push_warning("UpgradePool: bad weapon scene '%s' in '%s'" % [entry.scene, entry.id])
		return
	var weapon := scene.instantiate() as Node3D
	weapon.name = String(entry.weapon_name)
	mount.add_child(weapon)


static func _max_weapons(player: Node) -> int:
	if player == null:
		return DEFAULT_MAX_WEAPONS
	var value: Variant = player.get("max_weapons")
	return int(value) if value != null else DEFAULT_MAX_WEAPONS


static func _resolve_target(target_path: String, player: Node) -> Object:
	match target_path:
		"player":
			return player
		"health":
			return Health.find_in(player)
		"run_state":
			# Autoload fetched via the main loop, which statics can reach
			# no matter where the caller sits.
			var loop := Engine.get_main_loop() as SceneTree
			return loop.root.get_node_or_null("RunState") if loop != null else null
	if target_path.begins_with("weapon/"):
		var mount := player.get_node_or_null("Weapons")
		if mount != null:
			return mount.get_node_or_null(target_path.get_slice("/", 1))
	return null


## Picks up to `count` distinct entries, weighted by offer_weight.
static func _weighted_pick(entries: Array[Dictionary], count: int) -> Array[Dictionary]:
	var remaining := entries.duplicate()
	var picked: Array[Dictionary] = []
	while picked.size() < count and not remaining.is_empty():
		var total := 0.0
		for entry: Dictionary in remaining:
			total += float(entry.get("offer_weight", 1.0))
		var roll := randf() * total
		var chosen := remaining.size() - 1
		for i in remaining.size():
			roll -= float(remaining[i].get("offer_weight", 1.0))
			if roll <= 0.0:
				chosen = i
				break
		picked.append(remaining[chosen])
		remaining.remove_at(chosen)
	return picked


static func _rarity_for(entry: Dictionary) -> Dictionary:
	var fixed_name: String = String(entry.get("rarity", ""))
	if not fixed_name.is_empty():
		for rarity: Dictionary in RARITIES:
			if String(rarity.name) == fixed_name:
				return rarity
	return _roll_rarity()


static func _roll_rarity() -> Dictionary:
	var total := 0.0
	for rarity in RARITIES:
		total += rarity.weight
	var pick := randf() * total
	for rarity in RARITIES:
		pick -= rarity.weight
		if pick <= 0.0:
			return rarity
	return RARITIES[0]
