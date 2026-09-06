class_name CharacterCatalog
extends RefCounted
## Static catalog of playable characters (GDD 5): each pairs a starting
## weapon with a scaling per-level passive. Data-driven like TOME_LIBRARY
## and WEAPON_LIBRARY — a new playable character is one new row here (the
## select screen and player spawn read the rows; no per-character code).
## Row fields:
##   id/display_name/blurb: identity plus the select-card flavor line.
##   weapon_scene: starting weapon, instanced under the player's Weapons
##             mount at spawn.
##   weapon_node_name: instance name; must match the WEAPON_LIBRARY row's
##             node_name so the upgrade pool sees the weapon as owned.
##   weapon_display_name: weapon name shown on the select card.
##   passive_description: passive line shown on the select card.
##   passive_stat/passive_amount: passive effect as data — a PlayerStats
##             effect stat id (see _apply_effect there) and the amount
##             gained per level past 1 (percent for multiplier stats).
##   passive_kind (optional, default "per_level"): how PlayerStats applies
##             the passive — "per_level" scales with run level;
##             "speed_to_damage" converts bonus move speed into bonus
##             damage at the passive_amount ratio (stat id unused);
##             "evasion_execute" is per_level scaling plus every dodge
##             executing a weakened non-boss attacker.
##   passive_base (optional, default 0): amount already granted at level 1,
##             before any per-level increments (Doc's starting lifesteal).
##   unlock_cost: Shards to unlock on the select screen (GDD 5/8); 0 means
##             playable from the start. SaveData gates and persists the
##             actual unlocks — this is only the price data.
##   unlock_boss (optional): hidden-miniboss id whose kill grants this
##             character for free, bypassing Shards (GDD 5: skill unlocks).
##             SecretBossBase resolves the reward through by_unlock_boss on
##             the kill, so the mapping lives here, not in boss code.
##   unlock_hint (optional): vague select-screen clue for the boss path,
##             rendered on the locked card beside the Shard price.
##   tint:     placeholder capsule body color (also the card swatch).

##
## Player-facing text: display_name, blurb, weapon_display_name,
## passive_description and unlock_hint. Everything else (id, weapon_scene,
## weapon_node_name, passive_stat, passive_kind) is an identifier.

## Fallback character when no selection was made (Main booted directly).
const DEFAULT_ID: String = "rook"

const CHARACTER_LIBRARY: Array[Dictionary] = [
	{
		"id": "rook", "display_name": "Rook",
		"blurb": "Un muro con patas: sus golpes solo se ponen más feos.",
		"weapon_scene": "res://scenes/weapons/Shortsword.tscn",
		"weapon_node_name": "Shortsword",
		"weapon_display_name": "Espada corta",
		"passive_description": "+0.8% de daño por nivel",
		"passive_stat": "damage", "passive_amount": 0.8,
		"unlock_cost": 0,
		"tint": Color(0.35, 0.51, 0.74),
	},
	{
		"id": "vex", "display_name": "Vex",
		"blurb": "Un tirador nervioso que siempre encuentra el punto blando.",
		"weapon_scene": "res://scenes/weapons/DartPistol.tscn",
		"weapon_node_name": "DartPistol",
		"weapon_display_name": "Pistola de dardos",
		"passive_description": "+0.5% de prob. de crítico por nivel",
		"passive_stat": "crit_chance", "passive_amount": 0.5,
		"unlock_cost": 0,
		"tint": Color(0.58, 0.38, 0.82),
	},
	{
		"id": "ash", "display_name": "Ash",
		"blurb": "Un ermitaño cubierto de hollín cuyo fuego se abre más en cada nivel.",
		"weapon_scene": "res://scenes/weapons/EmberWand.tscn",
		"weapon_node_name": "EmberWand",
		"weapon_display_name": "Vara de brasas",
		"passive_description": "+0.7% de área por nivel",
		"passive_stat": "area", "passive_amount": 0.7,
		"unlock_cost": 50,
		"tint": Color(0.89, 0.45, 0.18),
	},
	{
		"id": "juno", "display_name": "Juno",
		"blurb": "Una acechadora de pies ligeros que convierte la velocidad en fuerza mortal.",
		"weapon_scene": "res://scenes/weapons/HuntingBow.tscn",
		"weapon_node_name": "HuntingBow",
		"weapon_display_name": "Arco de caza",
		"passive_description": "+0.6% de daño por cada 1% de velocidad extra",
		"passive_stat": "damage", "passive_amount": 0.6,
		"passive_kind": "speed_to_damage",
		"unlock_cost": 80,
		"tint": Color(0.24, 0.55, 0.32),
	},
	{
		"id": "bramble", "display_name": "Bramble",
		"blurb": "Un guardián erizado cuyo cuero castiga cada mordida descuidada.",
		"weapon_scene": "res://scenes/weapons/ThornWhip.tscn",
		"weapon_node_name": "ThornWhip",
		"weapon_display_name": "Látigo de espinas",
		"passive_description": "+1 de espinas por nivel",
		"passive_stat": "thorns", "passive_amount": 1.0,
		"unlock_cost": 80,
		"unlock_boss": "grubthing",
		"unlock_hint": "busca algo raro en el Bosque Hueco",
		"tint": Color(0.5, 0.58, 0.28),
	},
	{
		# GDD 5 also gives Otto wall-climb; that traversal mechanic is
		# deferred until a climbing system exists — HP growth ships now.
		"id": "otto", "display_name": "Otto",
		"blurb": "Un errante recio al que cada vez cuesta más tumbar.",
		"weapon_scene": "res://scenes/weapons/Boomerang.tscn",
		"weapon_node_name": "Boomerang",
		"weapon_display_name": "Bumerán",
		"passive_description": "+2 de HP máx. por nivel",
		"passive_stat": "max_hp", "passive_amount": 2.0,
		"unlock_cost": 100,
		"tint": Color(0.62, 0.44, 0.26),
	},
	{
		"id": "nyx", "display_name": "Nyx",
		"blurb": "Un borrón crepuscular que responde con acero a cada golpe fallado.",
		"weapon_scene": "res://scenes/weapons/TwinDaggers.tscn",
		"weapon_node_name": "TwinDaggers",
		"weapon_display_name": "Dagas gemelas",
		"passive_description": "+0.5% de evasión por nivel; al esquivar rematas a enemigos debilitados que no sean jefes",
		"passive_stat": "evasion", "passive_amount": 0.5,
		"passive_kind": "evasion_execute",
		"unlock_cost": 150,
		"unlock_boss": "coffer_mimic",
		"unlock_hint": "sigue un zumbido extraño en las Dunas de Ceniza",
		"tint": Color(0.42, 0.3, 0.58),
	},
	{
		"id": "wisp", "display_name": "Wisp",
		"blurb": "Un espíritu a medias, rodeado de luces que solo le obedecen a él.",
		"weapon_scene": "res://scenes/weapons/SpiritOrbs.tscn",
		"weapon_node_name": "SpiritOrbs",
		"weapon_display_name": "Orbes espirituales",
		"passive_description": "-0.5% de enfriamiento de armas por nivel",
		"passive_stat": "cooldown", "passive_amount": 0.5,
		"unlock_cost": 120,
		"tint": Color(0.55, 0.85, 0.95),
	},
	{
		"id": "torren", "display_name": "Torren",
		"blurb": "Un cazatormentas cuya suerte se lee como un parte del clima.",
		"weapon_scene": "res://scenes/weapons/StormRod.tscn",
		"weapon_node_name": "StormRod",
		"weapon_display_name": "Pararrayos",
		"passive_description": "+1 de suerte por nivel (cartas más raras)",
		"passive_stat": "luck", "passive_amount": 1.0,
		"unlock_cost": 130,
		"tint": Color(0.35, 0.45, 0.85),
	},
	{
		"id": "doc", "display_name": "Doc",
		"blurb": "Un cirujano de campaña muy alegre que le cobra a cada paciente en sangre.",
		"weapon_scene": "res://scenes/weapons/BloodVial.tscn",
		"weapon_node_name": "BloodVial",
		"weapon_display_name": "Vial de sangre",
		"passive_description": "+1% de robo de vida por nivel (base +5%)",
		"passive_stat": "lifesteal", "passive_amount": 1.0,
		"passive_base": 5.0,
		"unlock_cost": 150,
		"tint": Color(0.72, 0.16, 0.2),
	},
	# Iteration 43 roster: the slime, stench and beam starters.
	{
		"id": "miro", "display_name": "Miro",
		"blurb": "Una babosa babeante de raider que nunca está donde quedó el desastre.",
		"weapon_scene": "res://scenes/weapons/SlimeTrail.tscn",
		"weapon_node_name": "SlimeTrail",
		"weapon_display_name": "Rastro de baba",
		"passive_description": "+2% de duración de efectos por nivel",
		"passive_stat": "duration", "passive_amount": 2.0,
		"unlock_cost": 120,
		"tint": Color(0.45, 0.85, 0.35),
	},
	{
		"id": "bogg", "display_name": "Bogg",
		"blurb": "Nadie se sienta al lado de Bogg. Tampoco nadie sobrevive cerca de Bogg.",
		"weapon_scene": "res://scenes/weapons/Stench.tscn",
		"weapon_node_name": "Stench",
		"weapon_display_name": "Hedor",
		"passive_description": "+1% de área de ataque por nivel",
		"passive_stat": "area", "passive_amount": 1.0,
		"unlock_cost": 120,
		"tint": Color(0.6, 0.7, 0.3),
	},
	{
		"id": "kael", "display_name": "Kael",
		"blurb": "Carga seis segundos y después reescribe el mapa.",
		"weapon_scene": "res://scenes/weapons/Kamehameha.tscn",
		"weapon_node_name": "Kamehameha",
		"weapon_display_name": "Kamehameha",
		"passive_description": "+1% de daño por nivel",
		"passive_stat": "damage", "passive_amount": 1.0,
		"unlock_cost": 180,
		"tint": Color(0.4, 0.7, 1.0),
	},
]


## Lazily built lookups (see CatalogIndex): the select screen resolves a
## row per card per redraw, and the player spawn one per raider.
static var _by_id: Dictionary[String, Dictionary] = {}
static var _by_unlock_boss: Dictionary[String, Dictionary] = {}


## Row for the given id, or an empty Dictionary if unknown.
static func by_id(character_id: String) -> Dictionary:
	if _by_id.is_empty():
		_by_id = CatalogIndex.build(CHARACTER_LIBRARY)
	return _by_id.get(character_id, {})


## Row for the given id, falling back to the default character so spawn
## paths always get a valid loadout (e.g. a stale or mistyped saved id).
static func by_id_or_default(character_id: String) -> Dictionary:
	var row := by_id(character_id)
	return row if not row.is_empty() else by_id(DEFAULT_ID)


## Row whose unlock_boss names the given hidden-miniboss id, or an empty
## Dictionary when no character unlocks off that boss.
static func by_unlock_boss(boss_id: String) -> Dictionary:
	if boss_id.is_empty():
		return {}
	if _by_unlock_boss.is_empty():
		_by_unlock_boss = CatalogIndex.build(CHARACTER_LIBRARY, "unlock_boss")
	return _by_unlock_boss.get(boss_id, {})


## Ids playable from the start (unlock_cost 0) — GDD 5: Rook and Vex.
## SaveData seeds a fresh save's unlocked list from this.
static func starter_ids() -> Array[String]:
	var ids: Array[String] = []
	for row: Dictionary in CHARACTER_LIBRARY:
		if int(row.get("unlock_cost", 0)) == 0:
			ids.append(String(row.id))
	return ids
