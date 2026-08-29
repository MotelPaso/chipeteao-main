class_name UpgradePool
extends RefCounted
## Data-driven pool of level-up upgrades with rarity weighting (GDD 4).
## Each POOL entry describes one stat tweak:
##   target:   "player" | "health" | "run_state" | "weapon/<NodeName>"
##             (weapons are looked up under the player's Weapons mount)
##   op:       "mul_percent" (amount = +/- percent) | "add" (flat amount)
##   description: "%d" slot filled with the rarity-scaled amount.
## Rarity multiplies the base amount (an Epic +25% card rolls +50%), so
## future weapons/tomes just append entries — the card UI never changes.

const POOL: Array[Dictionary] = [
	{
		"id": "sword_damage", "title": "Honed Edge",
		"description": "Shortsword damage +%d%%",
		"target": "weapon/Shortsword", "property": "damage",
		"op": "mul_percent", "amount": 25.0,
	},
	{
		"id": "sword_cooldown", "title": "Quick Grip",
		"description": "Shortsword cooldown -%d%%",
		"target": "weapon/Shortsword", "property": "cooldown",
		"op": "mul_percent", "amount": -10.0,
	},
	{
		"id": "sword_range", "title": "Long Reach",
		"description": "Shortsword range +%d%%",
		"target": "weapon/Shortsword", "property": "attack_range",
		"op": "mul_percent", "amount": 15.0,
	},
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


## Rolls `count` distinct upgrades, each with an independently weighted
## rarity. Returns display-ready dicts: entry, rarity, amount, title,
## description.
static func roll_offer(count: int = 3) -> Array[Dictionary]:
	var entries := POOL.duplicate()
	entries.shuffle()
	var offer: Array[Dictionary] = []
	for entry: Dictionary in entries.slice(0, mini(count, entries.size())):
		var rarity := _roll_rarity()
		var amount: float = roundf(entry.amount * rarity.potency)
		offer.append({
			"entry": entry,
			"rarity": rarity,
			"amount": amount,
			"title": entry.title,
			"description": entry.description % absi(roundi(amount)),
		})
	return offer


## Applies one rolled offer to the live nodes reachable from `player`.
static func apply(offer: Dictionary, player: Node) -> void:
	var entry: Dictionary = offer.entry
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
