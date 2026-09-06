class_name Tome
extends RefCounted
## Static catalog of Tomes (GDD 3): stackable passive items whose stat
## effects feed the player's PlayerStats layer. Data-driven like
## UpgradePool.WEAPON_LIBRARY — adding a tome is one new row here.
## Row fields:
##   id/display_name: identity; the card title appends a stack numeral
##             ("Tomo de Furia II") when offering the next stack. Stacks
##             are UNCAPPED since iteration 46 (the 5-DISTINCT-tome cap
##             stays); see stack_label(). `id` is an
##             identifier and stays in English; display_name is player text.
##   glyph:    2-letter tile the HUD loadout strip draws while there is no
##             sprite. DECLARED, never derived from display_name: every row
##             shares the "Tomo de " prefix and the rest collapses too
##             (Persistencia/Peligro would both give "PE"). Unique across
##             this library, WEAPON_LIBRARY, EVOLUTION_LIBRARY and
##             ITEM_LIBRARY — the strip mixes all four.
##   description: card text; "%d" is filled with the rarity-scaled amount
##             of the PRIMARY (first) effect.
##   effects:  list of {stat, amount}. amount is per stack at Common
##             potency; the rolled rarity's potency scales it on pickup.
##             stat names map onto PlayerStats (see _apply_effect there).

## Roman-numeral table for stack_label(). Tomes stack WITHOUT a ceiling
## since iteration 46, so the numeral is built from these pairs instead of
## being indexed out of a fixed five-entry list; it stays a numeral rather
## than borrowing "Nv %d", which GLOSARIO rule 6 reserves for the run level.
const ROMAN_VALUES: Array[int] = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
const ROMAN_SYMBOLS: Array[String] = [
	"M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]

const TOME_LIBRARY: Array[Dictionary] = [
	{
		"id": "tome_fury", "display_name": "Tomo de Furia", "glyph": "FU",
		"description": "Daño de todas las armas +%d%%",
		"effects": [{"stat": "damage", "amount": 15.0}],
	},
	{
		"id": "tome_haste", "display_name": "Tomo de Celeridad", "glyph": "CE",
		"description": "Velocidad de ataque de todas las armas +%d%%",
		"effects": [{"stat": "cooldown", "amount": 8.0}],
	},
	{
		"id": "tome_reach", "display_name": "Tomo de Alcance", "glyph": "AL",
		"description": "Área de ataque +%d%%",
		"effects": [{"stat": "area", "amount": 12.0}],
	},
	{
		"id": "tome_swiftness", "display_name": "Tomo de Ligereza", "glyph": "LI",
		"description": "Velocidad de movimiento +%d%%",
		"effects": [{"stat": "move_speed", "amount": 8.0}],
	},
	{
		"id": "tome_precision", "display_name": "Tomo de Precisión", "glyph": "PR",
		"description": "Prob. de crítico +%d%%",
		"effects": [{"stat": "crit_chance", "amount": 6.0}],
	},
	{
		"id": "tome_ruin", "display_name": "Tomo de Ruina", "glyph": "RU",
		"description": "Daño crítico +%d%%",
		"effects": [{"stat": "crit_damage", "amount": 30.0}],
	},
	{
		"id": "tome_thirst", "display_name": "Tomo de Sed", "glyph": "SE",
		"description": "Robo de vida: te curas el %d%% del daño hecho",
		"effects": [{"stat": "lifesteal", "amount": 3.0}],
	},
	{
		"id": "tome_stone", "display_name": "Tomo de Piedra", "glyph": "PI",
		"description": "Armadura +%d (reducción fija de daño)",
		"effects": [{"stat": "armor", "amount": 2.0}],
	},
	{
		"id": "tome_mist", "display_name": "Tomo de Bruma", "glyph": "BR",
		"description": "Evasión: %d%% de probabilidad de esquivar golpes",
		"effects": [{"stat": "evasion", "amount": 4.0}],
	},
	# Iteration 39: the new stat layer (luck, projectiles, durations, XP,
	# gambling, difficulty).
	{
		"id": "tome_fortune", "display_name": "Tomo de Fortuna", "glyph": "FO",
		"description": "Suerte +%d (mejores rarezas de cartas y objetos)",
		"effects": [{"stat": "luck", "amount": 10.0}],
	},
	{
		"id": "tome_multitude", "display_name": "Tomo de Multitud", "glyph": "MU",
		"description": "+%d proyectil(es) en cada arma de andanada",
		"effects": [{"stat": "projectiles", "amount": 1.0}],
	},
	{
		"id": "tome_lingering", "display_name": "Tomo de Persistencia", "glyph": "PS",
		"description": "Duración de efectos +%d%% (ralentizaciones, charcos, veneno)",
		"effects": [{"stat": "duration", "amount": 20.0}],
	},
	{
		"id": "tome_wisdom", "display_name": "Tomo de Sabiduría", "glyph": "SA",
		"description": "XP ganada +%d%%",
		"effects": [{"stat": "xp_gain", "amount": 10.0}],
	},
	{
		# Gambling: each stack rolls random stat boons — more of them, and
		# bigger, at higher rarity (PlayerStats.add_tome handles the roll).
		"id": "tome_chance", "display_name": "Tomo del Azar", "glyph": "AZ",
		"description": "Apuesta: %d bonificación(es) de stat al azar, mayores a más rareza",
		"effects": [{"stat": "gambling", "amount": 1.0}],
		"gamble": true,
	},
	{
		# Difficulty is RUN-WIDE (shared in co-op): enemies get tougher and
		# pay more XP; PlayerStats forwards the total to RunState.
		"id": "tome_peril", "display_name": "Tomo del Peligro", "glyph": "PG",
		"description": "Dificultad +%d%%: enemigos más duros, más XP",
		"effects": [{"stat": "difficulty", "amount": 10.0}],
	},
]

## Stats a Tomo del Azar boon can land on: {stat, amount} at Common
## potency (the rolled rarity's potency scales it and adds more boons).
const GAMBLE_BOONS: Array[Dictionary] = [
	{"stat": "damage", "amount": 12.0},
	{"stat": "cooldown", "amount": 6.0},
	{"stat": "area", "amount": 10.0},
	{"stat": "move_speed", "amount": 6.0},
	{"stat": "crit_chance", "amount": 5.0},
	{"stat": "crit_damage", "amount": 25.0},
	{"stat": "lifesteal", "amount": 2.0},
	{"stat": "armor", "amount": 2.0},
	{"stat": "evasion", "amount": 3.0},
	{"stat": "luck", "amount": 8.0},
	{"stat": "max_hp", "amount": 15.0},
	{"stat": "xp_gain", "amount": 8.0},
	{"stat": "duration", "amount": 15.0},
]

## Lazily built id -> row index (see CatalogIndex): PlayerStats.recompute()
## resolves one row per carried stack, on every level-up and altar boon.
static var _by_id: Dictionary[String, Dictionary] = {}


static func by_id(tome_id: String) -> Dictionary:
	if _by_id.is_empty():
		_by_id = CatalogIndex.build(TOME_LIBRARY)
	return _by_id.get(tome_id, {})


## How many boons one Tomo del Azar stack grants at the given rarity
## potency: Common 1, Rare 2, Epic 3, Legendary 4.
## THE single source of that count — PlayerStats rolls exactly this many
## and UpgradePool prints exactly this many, so the card can never promise
## fewer boons than the tome hands out.
static func gamble_boon_count(potency: float) -> int:
	return 1 + clampi(UpgradePool.potency_rank(potency), 0, 3)


## Card title for offering the given stack (1-based): plain name for the
## first copy, "Nombre II", "Nombre VII", "Nombre XIV"... for later ones.
static func display_title(tome: Dictionary, stack: int) -> String:
	var title := String(tome.display_name)
	if stack <= 1:
		return title
	return title + " " + stack_label(stack)


## THE stack numeral, for the card title and the HUD loadout corner alike
## (iteration 46 removed the five-stack ceiling, so both had to stop
## indexing a fixed table). Any stack count from 1 up reads as a numeral.
static func stack_label(stack: int) -> String:
	var value := maxi(stack, 1)
	var label := ""
	for i: int in ROMAN_VALUES.size():
		while value >= ROMAN_VALUES[i]:
			value -= ROMAN_VALUES[i]
			label += ROMAN_SYMBOLS[i]
	return label
