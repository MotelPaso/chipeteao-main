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
##   tint:     placeholder capsule body color (also the card swatch).

## Fallback character when no selection was made (Main booted directly).
const DEFAULT_ID: String = "rook"

const CHARACTER_LIBRARY: Array[Dictionary] = [
	{
		"id": "rook", "display_name": "Rook",
		"blurb": "A patient wall of a raider whose swings only get meaner.",
		"weapon_scene": "res://scenes/weapons/Shortsword.tscn",
		"weapon_node_name": "Shortsword",
		"weapon_display_name": "Shortsword",
		"passive_description": "+0.8% damage per level",
		"passive_stat": "damage", "passive_amount": 0.8,
		"tint": Color(0.35, 0.51, 0.74),
	},
	{
		"id": "vex", "display_name": "Vex",
		"blurb": "A twitchy sharpshooter who always finds the soft spots.",
		"weapon_scene": "res://scenes/weapons/DartPistol.tscn",
		"weapon_node_name": "DartPistol",
		"weapon_display_name": "Dart Pistol",
		"passive_description": "+0.5% crit chance per level",
		"passive_stat": "crit_chance", "passive_amount": 0.5,
		"tint": Color(0.58, 0.38, 0.82),
	},
	{
		"id": "ash", "display_name": "Ash",
		"blurb": "A soot-caked hermit whose fire blooms wider every level.",
		"weapon_scene": "res://scenes/weapons/EmberWand.tscn",
		"weapon_node_name": "EmberWand",
		"weapon_display_name": "Ember Wand",
		"passive_description": "+0.7% area per level",
		"passive_stat": "area", "passive_amount": 0.7,
		"tint": Color(0.89, 0.45, 0.18),
	},
	{
		"id": "juno", "display_name": "Juno",
		"blurb": "A fleet-footed stalker who turns raw speed into killing force.",
		"weapon_scene": "res://scenes/weapons/HuntingBow.tscn",
		"weapon_node_name": "HuntingBow",
		"weapon_display_name": "Hunting Bow",
		"passive_description": "+0.6% damage per 1% bonus move speed",
		"passive_stat": "damage", "passive_amount": 0.6,
		"passive_kind": "speed_to_damage",
		"tint": Color(0.24, 0.55, 0.32),
	},
	{
		"id": "bramble", "display_name": "Bramble",
		"blurb": "A bristling warden whose hide punishes every careless bite.",
		"weapon_scene": "res://scenes/weapons/ThornWhip.tscn",
		"weapon_node_name": "ThornWhip",
		"weapon_display_name": "Thorn Whip",
		"passive_description": "+1 thorns per level",
		"passive_stat": "thorns", "passive_amount": 1.0,
		"tint": Color(0.5, 0.58, 0.28),
	},
	{
		# GDD 5 also gives Otto wall-climb; that traversal mechanic is
		# deferred until a climbing system exists — HP growth ships now.
		"id": "otto", "display_name": "Otto",
		"blurb": "A stout wanderer who only gets harder to put down.",
		"weapon_scene": "res://scenes/weapons/Boomerang.tscn",
		"weapon_node_name": "Boomerang",
		"weapon_display_name": "Boomerang",
		"passive_description": "+2 max HP per level",
		"passive_stat": "max_hp", "passive_amount": 2.0,
		"tint": Color(0.62, 0.44, 0.26),
	},
	{
		"id": "nyx", "display_name": "Nyx",
		"blurb": "A dusk-veiled blur who answers every whiffed swing with steel.",
		"weapon_scene": "res://scenes/weapons/TwinDaggers.tscn",
		"weapon_node_name": "TwinDaggers",
		"weapon_display_name": "Twin Daggers",
		"passive_description": "+0.5% evasion per level; dodges execute weakened non-boss enemies",
		"passive_stat": "evasion", "passive_amount": 0.5,
		"passive_kind": "evasion_execute",
		"tint": Color(0.42, 0.3, 0.58),
	},
	{
		"id": "doc", "display_name": "Doc",
		"blurb": "A cheery field surgeon who bills every patient in blood.",
		"weapon_scene": "res://scenes/weapons/BloodVial.tscn",
		"weapon_node_name": "BloodVial",
		"weapon_display_name": "Blood Vial",
		"passive_description": "+1% lifesteal per level (base +5%)",
		"passive_stat": "lifesteal", "passive_amount": 1.0,
		"passive_base": 5.0,
		"tint": Color(0.72, 0.16, 0.2),
	},
]


## Row for the given id, or an empty Dictionary if unknown.
static func by_id(character_id: String) -> Dictionary:
	for row: Dictionary in CHARACTER_LIBRARY:
		if String(row.id) == character_id:
			return row
	return {}


## Row for the given id, falling back to the default character so spawn
## paths always get a valid loadout (e.g. a stale or mistyped saved id).
static func by_id_or_default(character_id: String) -> Dictionary:
	var row := by_id(character_id)
	return row if not row.is_empty() else by_id(DEFAULT_ID)
