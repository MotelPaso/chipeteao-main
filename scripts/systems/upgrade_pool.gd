class_name UpgradePool
extends RefCounted
## Data-driven pool of level-up upgrades with rarity weighting (GDD 3/4).
## Since iteration 46 a LEVEL pick rolls one SIDE of the pool, never a
## mix: either weapons (owned-weapon stat cards + new_weapon cards) or
## tomes/stats (tome cards + GENERIC_POOL). roll_side() picks the side,
## weighted by how many entries each currently has, and never returns an
## empty one; the card UI names it in the title. Bonus picks (chests,
## shrines) pass no side and keep mixing everything.
## The offer pool is rebuilt per roll from:
##   - GENERIC_POOL: player/health/run_state tweaks, always available.
##   - Tome cards (Tome.TOME_LIBRARY): the next stack of every tome the
##     player has not capped yet; applying adds a stack to PlayerStats.
##   - Per-OWNED-weapon stat entries (damage/cooldown/range, plus extras
##     declared in WEAPON_LIBRARY), so every carried weapon keeps scaling.
##   - "new_weapon" cards for library weapons the player does NOT own yet,
##     hidden entirely once the player's max_weapons cap is reached.
## Entry fields:
##   kind:     "stat" (default, omitted), "new_weapon", or "tome"
##   target:   "player" | "health" | "run_state" | "weapon/<NodeName>"
##             (weapons are looked up under the player's Weapons mount)
##   op:       "mul_percent" (amount = +/- percent) | "add" (flat amount)
##   effects:  OPTIONAL multi-stat form (iteration 38): a list of
##             {property, op, amount} applied together on the same target,
##             replacing the single property/op/amount trio. The card's
##             description then carries one "%d" per effect, in order.
##   description: "%d" slot(s) filled with the rarity-scaled amount(s);
##             new_weapon descriptions are shown verbatim.
##   offer_weight: relative chance of appearing in an offer (default 1.0).
##   rarity:   fixes the card's rarity tier by name instead of rolling one.
## Rarity multiplies the base amount (an Epic +25% card rolls +50%), so
## future weapons/tomes just append entries — the card UI never changes.
## Rolled rarity weights are tilted by the player's luck stat (PlayerStats):
## luck moves a fraction of Common's weight up the tiers.
##
## Player-facing text lives in `display_name`, `flavor`, `title` and
## `description`; `id`, `node_name`, `scene` and every rarity name are
## identifiers and stay in English.

## Every equippable weapon: new_weapon cards and per-owned-weapon stat
## entries are generated from this, so adding a weapon is one new row.
## `glyph` is the 2-letter tile the HUD loadout strip draws while there is
## no sprite (same field ItemCatalog rows carry). It is DECLARED, never
## derived from display_name: Spanish weapon names nearly all read
## "Sustantivo de Complemento", so initials collapse ("Vara de brasas" and
## "Vial de sangre" both give "VD"). Keep every glyph unique across
## WEAPON_LIBRARY, EvolutionCatalog.EVOLUTION_LIBRARY, Tome.TOME_LIBRARY
## and ItemCatalog.ITEM_LIBRARY — the strip mixes all four.
const WEAPON_LIBRARY: Array[Dictionary] = [
	{
		"id": "shortsword", "display_name": "Espada corta", "glyph": "EC",
		"node_name": "Shortsword", "scene": "res://scenes/weapons/Shortsword.tscn",
		"flavor": "barre un arco cuerpo a cuerpo entre los enemigos cercanos",
	},
	{
		"id": "dart_pistol", "display_name": "Pistola de dardos", "glyph": "PD",
		"node_name": "DartPistol", "scene": "res://scenes/weapons/DartPistol.tscn",
		"flavor": "castiga al enemigo más cercano con dardos rápidos que persiguen",
		"extra_entries": [
			{
				"id": "dart_pistol_projectiles", "title": "Dardos divididos",
				"description": "La Pistola de dardos dispara %d dardo(s) más",
				"target": "weapon/DartPistol", "property": "projectile_count",
				"op": "add", "amount": 1.0,
			},
		],
	},
	{
		"id": "ember_wand", "display_name": "Vara de brasas", "glyph": "VB",
		"node_name": "EmberWand", "scene": "res://scenes/weapons/EmberWand.tscn",
		"flavor": "detona estallidos de fuego sobre grupos lejanos",
	},
	{
		"id": "hunting_bow", "display_name": "Arco de caza", "glyph": "AR",
		"node_name": "HuntingBow", "scene": "res://scenes/weapons/HuntingBow.tscn",
		"flavor": "suelta flechas rectas que ensartan filas enteras",
		"extra_entries": [
			{
				"id": "hunting_bow_pierce", "title": "Puntas con púas",
				"description": "Las flechas del Arco de caza perforan %d enemigos más",
				"target": "weapon/HuntingBow", "property": "pierce_count",
				"op": "add", "amount": 1.0,
			},
		],
	},
	{
		"id": "thorn_whip", "display_name": "Látigo de espinas", "glyph": "LE",
		"node_name": "ThornWhip", "scene": "res://scenes/weapons/ThornWhip.tscn",
		"flavor": "traza una línea de zarzas que engancha y ralentiza",
		"extra_entries": [
			{
				"id": "thorn_whip_slow", "title": "Espinas aferradas",
				"description": "La ralentización del Látigo de espinas es %d%% más fuerte",
				"target": "weapon/ThornWhip", "property": "slow_percent",
				"op": "add", "amount": 8.0,
			},
		],
	},
	{
		"id": "boomerang", "display_name": "Bumerán", "glyph": "BM",
		"node_name": "Boomerang", "scene": "res://scenes/weapons/Boomerang.tscn",
		"flavor": "lanza una hoja que corta al ir y al volver",
		"extra_entries": [
			{
				"id": "boomerang_travel", "title": "Vuelo lejano",
				"description": "Distancia de vuelo del Bumerán +%d%%",
				"target": "weapon/Boomerang", "property": "travel_scale",
				"op": "mul_percent", "amount": 20.0,
			},
		],
	},
	{
		"id": "twin_daggers", "display_name": "Dagas gemelas", "glyph": "DG",
		"node_name": "TwinDaggers", "scene": "res://scenes/weapons/TwinDaggers.tscn",
		"flavor": "destroza al enemigo más cercano con estocadas rapidísimas",
		"extra_entries": [
			{
				# Attack-speed flavor on its own knob (cooldown_scale), so it
				# stacks with "Mano rápida" without touching the base cooldown.
				"id": "twin_daggers_flurry", "title": "Ráfaga",
				"description": "Velocidad de ataque de las Dagas gemelas +%d%%",
				"target": "weapon/TwinDaggers", "property": "cooldown_scale",
				"op": "mul_percent", "amount": -15.0,
			},
		],
	},
	{
		"id": "spirit_orbs", "display_name": "Orbes espirituales", "glyph": "OE",
		"node_name": "SpiritOrbs", "scene": "res://scenes/weapons/SpiritOrbs.tscn",
		"flavor": "espíritus en órbita que queman todo lo que rozan",
		"extra_entries": [
			{
				"id": "spirit_orbs_count", "title": "Otro espíritu",
				"description": "Los Orbes espirituales suman %d orbe(s) más",
				"target": "weapon/SpiritOrbs", "property": "projectile_count",
				"op": "add", "amount": 1.0,
			},
		],
	},
	{
		"id": "storm_rod", "display_name": "Pararrayos", "glyph": "PY",
		"node_name": "StormRod", "scene": "res://scenes/weapons/StormRod.tscn",
		"flavor": "rayos que se bifurcan entre enemigos apretados",
		"extra_entries": [
			{
				"id": "storm_rod_chain", "title": "Cielo bifurcado",
				"description": "El Pararrayos encadena a %d enemigos más",
				"target": "weapon/StormRod", "property": "chain_count",
				"op": "add", "amount": 1.0,
			},
		],
	},
	{
		"id": "blood_vial", "display_name": "Vial de sangre", "glyph": "VS",
		"node_name": "BloodVial", "scene": "res://scenes/weapons/BloodVial.tscn",
		"flavor": "arroja frascos que encharcan sangre bajo los grupos más densos",
		"extra_entries": [
			{
				# One extra pulse = one extra tick_interval of pool lifetime.
				"id": "blood_vial_coagulate", "title": "Coagular",
				"description": "Los charcos del Vial de sangre pulsan %d vez(ces) más",
				"target": "weapon/BloodVial", "property": "pool_ticks",
				"op": "add", "amount": 1.0,
			},
		],
	},
	# Iteration 43 wave.
	{
		"id": "slime_trail", "display_name": "Rastro de baba", "glyph": "RB",
		"node_name": "SlimeTrail", "scene": "res://scenes/weapons/SlimeTrail.tscn",
		"flavor": "deja baba cáustica por donde camines",
		"extra_entries": [
			{
				"id": "slime_trail_life", "title": "Baba más espesa",
				"description": "Los charcos del Rastro de baba duran %d%% más",
				"target": "weapon/SlimeTrail", "property": "puddle_life",
				"op": "mul_percent", "amount": 25.0,
			},
		],
	},
	{
		"id": "aura", "display_name": "Aura", "glyph": "AU",
		"node_name": "Aura", "scene": "res://scenes/weapons/Aura.tscn",
		"flavor": "un anillo de luz que quema todo a tu alrededor",
	},
	{
		"id": "stench", "display_name": "Hedor", "glyph": "HE",
		"node_name": "Stench", "scene": "res://scenes/weapons/Stench.tscn",
		"flavor": "pulsos flatulentos que envenenan y ralentizan a la jauría",
		"extra_entries": [
			{
				"id": "stench_linger", "title": "Hedor más rancio",
				"description": "El veneno del Hedor dura %d%% más",
				"target": "weapon/Stench", "property": "poison_duration",
				"op": "mul_percent", "amount": 30.0,
			},
		],
	},
	{
		"id": "kamehameha", "display_name": "Kamehameha", "glyph": "KH",
		"node_name": "Kamehameha", "scene": "res://scenes/weapons/Kamehameha.tscn",
		"flavor": "un rayo devastador que borra un carril entero",
		"extra_entries": [
			{
				"id": "kamehameha_length", "title": "Rayo más largo",
				"description": "El rayo del Kamehameha llega %d%% más lejos",
				"target": "weapon/Kamehameha", "property": "beam_length",
				"op": "mul_percent", "amount": 25.0,
			},
		],
	},
]

## The two sides of the pool (iteration 46). Identifiers, not display
## text — SIDE_LABELS translates them for the card title.
const SIDE_WEAPONS: String = "weapons"
const SIDE_TOMES: String = "tomes"
const SIDE_LABELS: Dictionary[String, String] = {
	SIDE_WEAPONS: "Armas", SIDE_TOMES: "Tomos"}

## Fallback weapon cap when the player script doesn't export max_weapons.
const DEFAULT_MAX_WEAPONS: int = 5
## Fallback cap on DISTINCT tomes when the player doesn't export max_tomes
## (iteration 38): past it the pool only offers deeper stacks of owned tomes.
const DEFAULT_MAX_TOMES: int = 5
## Two-stat weapon cards show up a little less often than single-stat ones.
const MULTI_STAT_OFFER_WEIGHT: float = 0.7
## New-weapon cards show up meaningfully but less often than stat cards.
const NEW_WEAPON_OFFER_WEIGHT: float = 0.6
## Nine tome entries would otherwise crowd the pool; damp each a little.
const TOME_OFFER_WEIGHT: float = 0.8
## Luck's slope at zero: each luck point moves this fraction of Common's
## rarity weight upward. The curve in _rarity_weights bends away from it as
## luck grows, but never flattens.
const LUCK_TILT_PER_POINT: float = 0.01
## Asymptote of that curve: at most this fraction of Common's weight ever
## moves up. It is approached, never reached, so stacking luck past the old
## hard clamp (50 points) is no longer a silent no-op.
const MAX_LUCK_TILT: float = 0.5

## Balance steps of the cards every weapon generates, at Common potency
## (the rolled rarity scales them). These are the most-retuned numbers in
## the game, so they sit up here with their cousins instead of buried
## inside the generator's dictionaries.
const WEAPON_DAMAGE_STEP: float = 25.0
const WEAPON_COOLDOWN_STEP: float = -10.0
const WEAPON_RANGE_STEP: float = 15.0
## Two-stat cards: x is the first effect's step, y the second's.
const TEMPERED_STEPS: Vector2 = Vector2(15.0, 10.0)
const RHYTHM_STEPS: Vector2 = Vector2(-6.0, 10.0)

## Stats with a tome equivalent (move speed -> Tomo de Ligereza) live only
## in the tome catalog; entries here have no tome counterpart.
const GENERIC_POOL: Array[Dictionary] = [
	{
		# Iteration 38: raises the cap and heals ONLY the gained amount (no
		# more free full heal on every "Corazón recio" card).
		"id": "max_hp", "title": "Corazón recio",
		"description": "HP máx. +%d (te cura lo que ganas)",
		"target": "health", "property": "max_hp",
		"op": "add", "amount": 20.0,
	},
	{
		"id": "pickup_radius", "title": "Aura de codicia",
		"description": "Radio de recolección +%d%%",
		"target": "run_state", "property": "pickup_radius_multiplier",
		"op": "mul_percent", "amount": 25.0,
	},
]

## Rarity tiers. `name` is an IDENTIFIER, not display text: it keys chest
## prices (RunState.CHEST_BASE_PRICES), the `rarity` field of every
## ItemCatalog row, and the min_rarity floors passed around by chests,
## shrines and the world director. It stays in English forever — screens
## call rarity_display() to show it.
const RARITIES: Array[Dictionary] = [
	{"name": "Common", "color": Color(0.62, 0.65, 0.68), "weight": 60.0, "potency": 1.0},
	{"name": "Rare", "color": Color(0.3, 0.55, 1.0), "weight": 25.0, "potency": 1.5},
	{"name": "Epic", "color": Color(0.68, 0.32, 0.95), "weight": 12.0, "potency": 2.0},
	{"name": "Legendary", "color": Color(1.0, 0.78, 0.2), "weight": 3.0, "potency": 3.0},
]

## Player-facing name per rarity id. The only place a rarity is translated.
const RARITY_DISPLAY: Dictionary[String, String] = {
	"Common": "Común",
	"Rare": "Raro",
	"Epic": "Épico",
	"Legendary": "Legendario",
}

## Lazily built node_name -> WEAPON_LIBRARY row index (see CatalogIndex).
static var _weapons_by_node: Dictionary[String, Dictionary] = {}


## Translates a rarity id for display. Every screen that prints a rarity
## goes through here; nothing compares against the result.
static func rarity_display(rarity_name: String) -> String:
	return RARITY_DISPLAY.get(rarity_name, rarity_name)


## Rolls `count` distinct upgrades from the pool valid for this player's
## loadout, each with an independently weighted rarity. Returns
## display-ready dicts: entry, rarity, amount, title, description.
## Shrine/chest picks pass luck_bonus (temporary rarity-tilt luck on top
## of PlayerStats) and/or min_rarity (a tier name every rarity is floored
## to, fixed ones included). `side` restricts the pool to SIDE_WEAPONS or
## SIDE_TOMES; "" (the default, and what every bonus pick passes) mixes.
static func roll_offer(player: Node, count: int = 3, luck_bonus: float = 0.0,
		min_rarity: String = "", side: String = "") -> Array[Dictionary]:
	var offer: Array[Dictionary] = []
	var stats := PlayerStats.find_in(player)
	var luck := (stats.luck if stats != null else 0.0) + luck_bonus
	var floor_index := rarity_index(min_rarity)
	for entry: Dictionary in _weighted_pick(build_pool(player, side), count):
		var rarity := _rarity_for(entry, luck, floor_index)
		if String(entry.get("kind", "stat")) == "new_weapon":
			offer.append({
				"entry": entry,
				"rarity": rarity,
				"amount": 0.0,
				"title": entry.title,
				"description": entry.description,
			})
			continue
		if entry.has("effects"):
			# Multi-stat card: one rarity-scaled amount per effect, in order.
			var amounts: Array[float] = []
			var shown: Array[int] = []
			for effect: Dictionary in entry.effects as Array:
				var scaled: float = roundf(float(effect.amount) * float(rarity.potency))
				amounts.append(scaled)
				shown.append(absi(roundi(scaled)))
			offer.append({
				"entry": entry,
				"rarity": rarity,
				"amount": amounts[0] if not amounts.is_empty() else 0.0,
				"amounts": amounts,
				"title": entry.title,
				"description": String(entry.description) % shown,
			})
			continue
		var amount: float = roundf(float(entry.amount) * float(rarity.potency))
		if bool(entry.get("gamble", false)):
			# Tomo del Azar: the number of boons is a step function of the
			# rarity rank, not amount x potency (which under-counted Epic and
			# Legendary). Both sides now read the same pure function, so the
			# card can never promise fewer boons than PlayerStats rolls.
			amount = float(Tome.gamble_boon_count(float(rarity.potency)))
		offer.append({
			"entry": entry,
			"rarity": rarity,
			"amount": amount,
			"title": entry.title,
			"description": entry.description % absi(roundi(amount)),
		})
	return offer


## The pool the player can currently roll from. `side` restricts it to one
## half (SIDE_WEAPONS / SIDE_TOMES); "" returns both, which is what bonus
## picks want.
static func build_pool(player: Node, side: String = "") -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	if side != SIDE_WEAPONS:
		pool.append_array(_tome_side(player))
	if side != SIDE_TOMES:
		pool.append_array(_weapon_side(player))
	return pool


## Tomes/stats half: the generic stat cards, always available, plus the
## next stack of every tome the player may still take.
static func _tome_side(player: Node) -> Array[Dictionary]:
	var pool: Array[Dictionary] = GENERIC_POOL.duplicate()
	if player == null:
		return pool
	pool.append_array(_tome_entries(player))
	return pool


## Weapons half: stat entries for each owned weapon plus new_weapon cards
## for the unowned ones (none once the weapon cap is reached).
static func _weapon_side(player: Node) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	if player == null:
		return pool
	var mount := player.get_node_or_null("Weapons")
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


## Which side a level pick offers: random, weighted by how many entries
## each side actually has right now, so a raider with five maxed weapons
## and nine open tomes mostly sees tomes. Never returns an empty side —
## a pick with nothing to show is a wedge over a paused tree.
## Both halves are built to count them: this runs once per level-up, not
## per frame, and counting them any other way would duplicate the rules
## about caps that _tome_side / _weapon_side already own.
static func roll_side(player: Node) -> String:
	var weapons := _weapon_side(player).size()
	var tomes := _tome_side(player).size()
	if weapons <= 0:
		return SIDE_TOMES
	if tomes <= 0:
		return SIDE_WEAPONS
	return SIDE_WEAPONS if randf() * float(weapons + tomes) < float(weapons) \
			else SIDE_TOMES


## Player-facing name of a side, for the card-picker title.
static func side_label(side: String) -> String:
	return SIDE_LABELS.get(side, "")


## Applies one rolled offer to the live nodes reachable from `player`.
static func apply(offer: Dictionary, player: Node) -> void:
	var entry: Dictionary = offer.entry
	match String(entry.get("kind", "stat")):
		"new_weapon":
			_grant_weapon(entry, player)
			return
		"tome":
			_grant_tome(entry, offer, player)
			return
	var target := _resolve_target(entry.target, player)
	if target == null:
		push_warning("UpgradePool: target '%s' not found for '%s'" % [entry.target, entry.id])
		return
	if entry.has("effects"):
		var amounts: Array[float] = offer.get("amounts", [] as Array[float])
		var effects: Array = entry.effects
		for i in effects.size():
			var effect: Dictionary = effects[i]
			_apply_property(target, String(effect.property), String(effect.op),
					amounts[i] if i < amounts.size() else float(effect.amount), entry)
	else:
		_apply_property(target, String(entry.property), String(entry.op),
				float(offer.amount), entry)
	# Weapon level bookkeeping (iteration 38): every card invested in a
	# weapon is one weapon level, and reaching the catalog's threshold
	# evolves it on the spot — no chest, no tome pairing.
	if target is WeaponBase:
		var weapon := target as WeaponBase
		weapon.upgrade_level += 1
		EvolutionCatalog.try_advance_by_level(weapon, player)


## One property change on a live target. A max_hp raise on a Health also
## heals by the gained amount (never a full heal — iteration 38 rule).
static func _apply_property(target: Object, property: String, op: String,
		amount: float, entry: Dictionary) -> void:
	# Object.get() answers null for a property that does not exist, and a
	# typed `float` assignment turns that into a hard error mid-card, with
	# the tree paused by the card UI. A mistyped catalog row must degrade to
	# a warning instead of freezing the run (WeaponBase.evolve does the same).
	var raw: Variant = target.get(property)
	if raw == null:
		push_warning("UpgradePool: no property '%s' on target for '%s'"
				% [property, entry.get("id", "?")])
		return
	var current := float(raw)
	match op:
		"mul_percent":
			target.set(property, current * (1.0 + amount / 100.0))
		"add":
			target.set(property, current + amount)
		_:
			push_warning("UpgradePool: unknown op '%s' in '%s'" % [op, entry.id])
	if target is Health and property == "max_hp" and amount > 0.0:
		(target as Health).heal(amount)


## Stat entries every owned weapon contributes (same scaling for all
## weapons; per-weapon extras ride along from the library row).
## The descriptions concatenate the weapon's display name on purpose: in
## Spanish the stat noun leads ("Daño de la Espada corta +25%"), so the
## name sits in the middle and the "%d" count per card never changes.
static func _entries_for_weapon(weapon: Dictionary) -> Array[Dictionary]:
	var display: String = weapon.display_name
	var target: String = "weapon/" + String(weapon.node_name)
	var entries: Array[Dictionary] = [
		{
			"id": String(weapon.id) + "_damage", "title": "Filo aguzado",
			"description": "Daño de " + display + " +%d%%",
			"target": target, "property": "damage",
			"op": "mul_percent", "amount": WEAPON_DAMAGE_STEP,
		},
		{
			"id": String(weapon.id) + "_cooldown", "title": "Mano rápida",
			"description": "Velocidad de ataque de " + display + " +%d%%",
			"target": target, "property": "cooldown",
			"op": "mul_percent", "amount": WEAPON_COOLDOWN_STEP,
		},
		{
			"id": String(weapon.id) + "_range", "title": "Largo alcance",
			"description": "Alcance de " + display + " +%d%%",
			"target": target, "property": "attack_range",
			"op": "mul_percent", "amount": WEAPON_RANGE_STEP,
		},
		# Two-stat cards (iteration 38): one level, two knobs.
		{
			"id": String(weapon.id) + "_tempered", "title": "Temple",
			"description": "Daño de " + display + " +%d%%, alcance +%d%%",
			"target": target,
			"effects": [
				{"property": "damage", "op": "mul_percent", "amount": TEMPERED_STEPS.x},
				{"property": "attack_range", "op": "mul_percent", "amount": TEMPERED_STEPS.y},
			],
			"offer_weight": MULTI_STAT_OFFER_WEIGHT,
		},
		{
			"id": String(weapon.id) + "_rhythm", "title": "Ritmo de batalla",
			"description": "Velocidad de ataque de " + display + " +%d%%, daño +%d%%",
			"target": target,
			"effects": [
				{"property": "cooldown", "op": "mul_percent", "amount": RHYTHM_STEPS.x},
				{"property": "damage", "op": "mul_percent", "amount": RHYTHM_STEPS.y},
			],
			"offer_weight": MULTI_STAT_OFFER_WEIGHT,
		},
	]
	for extra: Dictionary in weapon.get("extra_entries", [] as Array[Dictionary]):
		entries.append(extra)
	return entries


## One card per available tome, offering the NEXT stack (the title carries
## the stack numeral, e.g. "Tomo de Furia II" — Tome.stack_label builds it
## for any count). The rolled rarity's potency scales the granted amounts
## exactly like stat cards.
static func _tome_entries(player: Node) -> Array[Dictionary]:
	var stats := PlayerStats.find_in(player)
	var entries: Array[Dictionary] = []
	# Distinct-tome cap (iteration 38): once the player carries max_tomes
	# different tomes, only deeper stacks of those are offered.
	var owned_distinct := stats.distinct_tome_count() if stats != null else 0
	var at_cap := owned_distinct >= _player_cap(player, "max_tomes", DEFAULT_MAX_TOMES)
	for tome: Dictionary in Tome.TOME_LIBRARY:
		var tome_id := String(tome.id)
		var owned_stacks := stats.stack_count(tome_id) if stats != null else 0
		if at_cap and owned_stacks == 0:
			continue
		# No stack ceiling since iteration 46: only the number of DISTINCT
		# tomes is capped, so a favourite tome keeps deepening all run.
		var next_stack := owned_stacks + 1
		var effects: Array = tome.effects
		var primary: Dictionary = effects[0]
		entries.append({
			"id": tome_id,
			"kind": "tome",
			"tome_id": tome_id,
			"title": Tome.display_title(tome, next_stack),
			"description": String(tome.description),
			# The primary effect drives the number shown on the card.
			"amount": float(primary.amount),
			# Gambling tomes count boons instead (see roll_offer).
			"gamble": bool(tome.get("gamble", false)),
			"offer_weight": TOME_OFFER_WEIGHT,
		})
	return entries


static func _new_weapon_entry(weapon: Dictionary) -> Dictionary:
	return {
		"id": "gain_" + String(weapon.id),
		"kind": "new_weapon",
		"title": String(weapon.display_name),
		"description": "Arma nueva: " + String(weapon.flavor),
		"scene": String(weapon.scene),
		"weapon_name": String(weapon.node_name),
		"weapon_id": String(weapon.id),
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
	# Collection discovery: "has ever carried this weapon" (persists at the
	# run-end fold like every other counter).
	var weapon_id := String(entry.get("weapon_id", ""))
	if not weapon_id.is_empty():
		var save_data := autoload_node(&"SaveData")
		if save_data != null:
			save_data.bump("used_weapon_" + weapon_id)


## An autoload node reached through the main loop: static functions cannot
## see autoload names directly, and a `-s` harness has no autoloads at all,
## so every static autoload use in this domain funnels through here and
## degrades to null instead of crashing.
static func autoload_node(node_name: StringName) -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return null
	return loop.root.get_node_or_null(NodePath(node_name))


## WEAPON_LIBRARY row for a mount node name (empty when unknown).
static func weapon_by_node(node_name: String) -> Dictionary:
	if _weapons_by_node.is_empty():
		_weapons_by_node = CatalogIndex.build(WEAPON_LIBRARY, "node_name")
	return _weapons_by_node.get(node_name, {})


## WEAPON_LIBRARY id for a mount node name ("" when unknown) — lets the
## player spawn and the Collection screen key discovery counters by id.
static func weapon_id_for_node(node_name: String) -> String:
	return String(weapon_by_node(node_name).get("id", ""))


## Player-facing weapon name for a mount node name, falling back to the
## node name. Screens (HUD loadout strip, evolution banner) resolve names
## through the catalog instead of prettifying an internal id.
static func weapon_display_name(node_name: String) -> String:
	return String(weapon_by_node(node_name).get("display_name", node_name))


## Adds one stack at the rolled rarity's potency; PlayerStats recomputes
## every derived stat from scratch, so displayed amounts match applied.
static func _grant_tome(entry: Dictionary, offer: Dictionary, player: Node) -> void:
	var stats := PlayerStats.find_in(player)
	if stats == null:
		push_warning("UpgradePool: no PlayerStats on player for '%s'" % entry.id)
		return
	var rarity: Dictionary = offer.rarity
	stats.add_tome(String(entry.tome_id), float(rarity.potency))


static func _max_weapons(player: Node) -> int:
	return _player_cap(player, "max_weapons", DEFAULT_MAX_WEAPONS)


## An exported cap on the player script, or the fallback when absent.
static func _player_cap(player: Node, property: String, fallback: int) -> int:
	if player == null:
		return fallback
	var value: Variant = player.get(property)
	return int(value) if value != null else fallback


static func _resolve_target(target_path: String, player: Node) -> Object:
	match target_path:
		"player":
			return player
		"health":
			return Health.find_in(player)
		"run_state":
			return autoload_node(&"RunState")
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


## Rarity tier index for a potency value (Common 1.0 -> 0 ... Legendary
## 3.0 -> 3); the nearest tier wins for off-table values.
static func potency_rank(potency: float) -> int:
	var best := 0
	var best_gap := INF
	for i: int in RARITIES.size():
		var gap := absf(float(RARITIES[i].potency) - potency)
		if gap < best_gap:
			best_gap = gap
			best = i
	return best


## Index of a rarity tier by name; unknown or empty names map to the base
## tier (index 0), which floors nothing.
static func rarity_index(rarity_name: String) -> int:
	for i: int in RARITIES.size():
		if String(RARITIES[i].name) == rarity_name:
			return i
	return 0


static func _rarity_for(entry: Dictionary, luck: float, floor_index: int = 0) -> Dictionary:
	var fixed_name: String = String(entry.get("rarity", ""))
	if not fixed_name.is_empty():
		for i: int in RARITIES.size():
			if String(RARITIES[i].name) == fixed_name:
				# A bonus pick's min_rarity floor lifts fixed rarities too,
				# so an "Epic+" pick can never show a card sealed RARE.
				return RARITIES[maxi(i, floor_index)]
	return roll_rarity(luck, floor_index)


## Rolls one rarity tier, luck-tilted and floored to `floor_index`.
## Public because chests roll their own tier at ready (chest.gd) and the
## luck curve — with its exponential tilt toward MAX_LUCK_TILT — must have
## exactly one implementation.
static func roll_rarity(luck: float, floor_index: int = 0) -> Dictionary:
	var weights := _rarity_weights(luck)
	var total := 0.0
	for weight: float in weights:
		total += weight
	var pick := randf() * total
	var index := 0
	for i: int in RARITIES.size():
		pick -= weights[i]
		if pick <= 0.0:
			index = i
			break
	return RARITIES[maxi(index, floor_index)]


## Roll-time rarity weights: luck moves a fraction of the base tier's
## (RARITIES[0], Common) weight onto the higher tiers, distributed
## proportionally to their base weights.
## The fraction saturates toward MAX_LUCK_TILT instead of clamping at it:
## the old hard clamp went flat at 50 luck, and the game hands out far more
## than that (Tomo de Fortuna alone can reach 150), so every point past the
## cap used to buy literally nothing while the cards kept advertising it.
static func _rarity_weights(luck: float) -> PackedFloat32Array:
	var weights := PackedFloat32Array()
	var upper_total := 0.0
	for i: int in RARITIES.size():
		weights.append(float(RARITIES[i].weight))
		if i > 0:
			upper_total += float(RARITIES[i].weight)
	var tilt := MAX_LUCK_TILT * (1.0 - exp(-maxf(luck, 0.0) * LUCK_TILT_PER_POINT / MAX_LUCK_TILT))
	if tilt <= 0.0 or upper_total <= 0.0:
		return weights
	var moved := weights[0] * tilt
	weights[0] -= moved
	for i: int in range(1, weights.size()):
		weights[i] += moved * float(RARITIES[i].weight) / upper_total
	return weights
