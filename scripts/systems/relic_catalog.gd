class_name RelicCatalog
extends RefCounted
## Static catalog of Relics (iteration 36): permanent between-run stat
## upgrades bought with Shards in the Armory screen — the "every defeat
## still funds the next attempt" retention layer. Data-driven like the
## other catalogs; a new relic is one row here.
##
## Design note: this deliberately amends GDD 8's "Shards only buy
## characters" rule — amounts are small (a maxed armory is ~+10% power,
## nowhere near a tome build), so mastery stays the real curve while every
## run still banks visible progress.
##
## Row fields:
##   id: identifier (English, keys SaveData.relic_ranks) — never shown.
##   display_name/description: player text; the description's "%s" is
##             filled with the per-rank amount text.
##   stat:     PlayerStats effect stat id (see _apply_effect there);
##             applied every recompute at amount * owned rank.
##   amount:   effect per rank (percent for multiplier stats, flat for
##             armor/luck/max_hp).
##   amount_text: how one rank reads on the row ("+2% damage").
##   max_ranks / base_cost / cost_growth: rank cap and the Shard price
##             ladder — rank N costs base_cost * cost_growth^N (rounded).
## Persistence: SaveData.relic_ranks (purchase_relic / relic_rank).

const RELIC_LIBRARY: Array[Dictionary] = [
	{
		"id": "relic_fury", "display_name": "Sello de brasas",
		"description": "Todo el daño %s por rango.",
		"stat": "damage", "amount": 2.0, "amount_text": "+2%",
		"max_ranks": 5, "base_cost": 40, "cost_growth": 1.6,
	},
	{
		"id": "relic_vitality", "display_name": "Amuleto de roble",
		"description": "HP máx. %s por rango.",
		"stat": "max_hp", "amount": 6.0, "amount_text": "+6",
		"max_ranks": 5, "base_cost": 40, "cost_growth": 1.6,
	},
	{
		"id": "relic_haste", "display_name": "Colmillo silbante",
		"description": "Velocidad de ataque %s por rango.",
		"stat": "cooldown", "amount": 1.5, "amount_text": "+1.5%",
		"max_ranks": 5, "base_cost": 50, "cost_growth": 1.6,
	},
	{
		"id": "relic_fortune", "display_name": "Bigote dorado",
		"description": "Suerte %s por rango (cartas de mejora más raras).",
		"stat": "luck", "amount": 3.0, "amount_text": "+3",
		"max_ranks": 4, "base_cost": 45, "cost_growth": 1.6,
	},
	{
		"id": "relic_stride", "display_name": "Tobillera de marea",
		"description": "Velocidad de movimiento %s por rango.",
		"stat": "move_speed", "amount": 1.5, "amount_text": "+1.5%",
		"max_ranks": 4, "base_cost": 35, "cost_growth": 1.6,
	},
	{
		"id": "relic_hide", "display_name": "Coraza de percebes",
		"description": "Armadura %s por rango (reducción fija de daño).",
		"stat": "armor", "amount": 1.0, "amount_text": "+1",
		"max_ranks": 4, "base_cost": 50, "cost_growth": 1.7,
	},
]


## Lazily built id -> row index (see CatalogIndex): PlayerStats._apply_relics
## walks the whole library on every recompute.
static var _by_id: Dictionary[String, Dictionary] = {}


## Row for the given id, or an empty Dictionary if unknown.
static func by_id(relic_id: String) -> Dictionary:
	if _by_id.is_empty():
		_by_id = CatalogIndex.build(RELIC_LIBRARY)
	return _by_id.get(relic_id, {})


## Shard cost of buying rank `owned_ranks + 1` (0-based owned count), or -1
## when the relic is unknown or already at its cap.
static func next_rank_cost(relic_id: String, owned_ranks: int) -> int:
	var row := by_id(relic_id)
	if row.is_empty() or owned_ranks >= int(row.max_ranks):
		return -1
	return roundi(float(row.base_cost) * pow(float(row.cost_growth), float(owned_ranks)))
