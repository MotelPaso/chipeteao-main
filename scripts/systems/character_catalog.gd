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
##   passive_stat/passive_amount: per-level effect as data — a PlayerStats
##             effect stat id (see _apply_effect there) and the amount
##             gained per level past 1 (percent for multiplier stats).
##   tint:     placeholder capsule body color (also the card swatch).

## Fallback character when no selection was made (Main booted directly).
const DEFAULT_ID: String = "rook"
## Launch roster size (GDD 5): the select screen pads the missing
## characters with locked slots until their weapons exist.
const ROSTER_SIZE: int = 8

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
