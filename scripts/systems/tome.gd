class_name Tome
extends RefCounted
## Static catalog of Tomes (GDD 3): stackable passive items whose stat
## effects feed the player's PlayerStats layer. Data-driven like
## UpgradePool.WEAPON_LIBRARY — adding a tome is one new row here.
## Row fields:
##   id/display_name: identity; the card title appends a stack numeral
##             ("Tome of Fury II") when offering the next stack.
##   description: card text; "%d" is filled with the rarity-scaled amount
##             of the PRIMARY (first) effect.
##   effects:  list of {stat, amount}. amount is per stack at Common
##             potency; the rolled rarity's potency scales it on pickup.
##             stat names map onto PlayerStats (see _apply_effect there).

const MAX_STACKS: int = 5
const STACK_NUMERALS: Array[String] = ["I", "II", "III", "IV", "V"]

const TOME_LIBRARY: Array[Dictionary] = [
	{
		"id": "tome_fury", "display_name": "Tome of Fury",
		"description": "All weapon damage +%d%%",
		"effects": [{"stat": "damage", "amount": 15.0}],
	},
	{
		"id": "tome_haste", "display_name": "Tome of Haste",
		"description": "All weapon cooldowns -%d%%",
		"effects": [{"stat": "cooldown", "amount": 8.0}],
	},
	{
		"id": "tome_reach", "display_name": "Tome of Reach",
		"description": "Attack area +%d%%",
		"effects": [{"stat": "area", "amount": 12.0}],
	},
	{
		"id": "tome_swiftness", "display_name": "Tome of Swiftness",
		"description": "Move speed +%d%%",
		"effects": [{"stat": "move_speed", "amount": 8.0}],
	},
	{
		"id": "tome_precision", "display_name": "Tome of Precision",
		"description": "Crit chance +%d%%",
		"effects": [{"stat": "crit_chance", "amount": 6.0}],
	},
	{
		"id": "tome_ruin", "display_name": "Tome of Ruin",
		"description": "Crit damage +%d%%",
		"effects": [{"stat": "crit_damage", "amount": 30.0}],
	},
	{
		"id": "tome_thirst", "display_name": "Tome of Thirst",
		"description": "Lifesteal: heal %d%% of damage dealt",
		"effects": [{"stat": "lifesteal", "amount": 3.0}],
	},
	{
		"id": "tome_stone", "display_name": "Tome of Stone",
		"description": "Armor +%d (flat damage reduction)",
		"effects": [{"stat": "armor", "amount": 2.0}],
	},
	{
		"id": "tome_mist", "display_name": "Tome of Mist",
		"description": "Evasion: %d%% chance to dodge hits",
		"effects": [{"stat": "evasion", "amount": 4.0}],
	},
]


static func by_id(tome_id: String) -> Dictionary:
	for tome: Dictionary in TOME_LIBRARY:
		if String(tome.id) == tome_id:
			return tome
	return {}


## Card title for offering the given stack (1-based): plain name for the
## first copy, "Name II".."Name V" for later stacks.
static func display_title(tome: Dictionary, stack: int) -> String:
	var title := String(tome.display_name)
	if stack <= 1:
		return title
	return title + " " + STACK_NUMERALS[clampi(stack, 1, MAX_STACKS) - 1]
