class_name MapCatalog
extends RefCounted
## Static catalog of run maps/biomes (GDD 7). Data-driven like the other
## catalogs — a new biome is one row here plus its arena scene. The select
## screen builds the map row from these rows and SaveData.is_map_unlocked()
## evaluates the unlock rule.
## Row fields:
##   id:     identifier (English, keys SaveData counters) — never shown.
##   display_name/blurb/locked_hint: player text on the select card.
##   scene_path: arena scene Start Run loads. Every arena instances
##             RunSystems.tscn, which republishes the map id into
##             GameConfig so directly-booted arenas fold correctly.
##   unlock_stat/unlock_target: SaveData lifetime counter gate; an empty
##             stat means always playable (see the canonical counter id
##             list in save_data.gd).
##   locked_hint: select-card line telling the player how to unlock.
##   palette: swatch-strip colors on the select card (the biome's mood).
##   tiers: this map's difficulty ladder (see DEFAULT_TIERS). Tier N+1
##             unlocks by winning tier N on that same map
##             (SaveData.is_tier_unlocked).

## Fallback map when no selection was made (an arena booted directly).
const DEFAULT_ID: String = "hollow_woods"

const TIER_COUNT: int = 3

## The 3-tier difficulty ladder every map ships with (GDD 6: the boss line
## gets harder per map tier). Tier 1 is the exact baseline game — every
## multiplier 1.0, no bonus — so a legacy save or a direct boot changes
## nothing. Per-tier fields:
##   enemy_hp_mult/enemy_damage_mult: regular-spawn scaling, applied by the
##             spawner via EnemyBase.apply_tier_scaling (stacks with elites).
##   spawn_rate_mult: spawns-per-second factor (divides the interval).
##   boss_mult: fed into BossBase.apply_tier (multiplies with the Elder
##             rematch factor, stacks with curse as today).
##   xp_value_mult: regular XP-gem value factor (rounded, min 1).
##   shard_bonus: Shards credited outright on a victory at this tier.
const DEFAULT_TIERS: Array[Dictionary] = [
	{"tier": 1, "enemy_hp_mult": 1.0, "enemy_damage_mult": 1.0,
			"spawn_rate_mult": 1.0, "boss_mult": 1.0,
			"xp_value_mult": 1.0, "shard_bonus": 0},
	{"tier": 2, "enemy_hp_mult": 1.6, "enemy_damage_mult": 1.35,
			"spawn_rate_mult": 1.25, "boss_mult": 1.5,
			"xp_value_mult": 1.3, "shard_bonus": 20},
	{"tier": 3, "enemy_hp_mult": 2.4, "enemy_damage_mult": 1.7,
			"spawn_rate_mult": 1.5, "boss_mult": 2.0,
			"xp_value_mult": 1.6, "shard_bonus": 50},
]

const MAP_LIBRARY: Array[Dictionary] = [
	{
		"id": "hollow_woods", "display_name": "Bosque Hueco",
		"blurb": "Claros musgosos bajo un dosel verde y paciente.",
		"scene_path": "res://scenes/world/HollowWoods.tscn",
		"unlock_stat": "", "unlock_target": 0,
		"locked_hint": "",
		"palette": [Color(0.3, 0.56, 0.3), Color(0.15, 0.34, 0.19),
				Color(0.44, 0.3, 0.2), Color(0.79, 0.83, 0.72)],
		"tiers": DEFAULT_TIERS,
	},
	{
		"id": "ash_dunes", "display_name": "Dunas de Ceniza",
		"blurb": "Arena calcinada, monumentos inclinados, un horizonte que zumba.",
		"scene_path": "res://scenes/world/AshDunes.tscn",
		"unlock_stat": "victories", "unlock_target": 1,
		"locked_hint": "Gana una incursión en el Bosque Hueco",
		"palette": [Color(0.82, 0.66, 0.4), Color(0.68, 0.36, 0.26),
				Color(0.24, 0.55, 0.45), Color(0.94, 0.66, 0.42)],
		"tiers": DEFAULT_TIERS,
	},
	{
		"id": "gloomfen", "display_name": "Ciénaga Lóbrega",
		"blurb": "Islas de musgo anegado bajo un cielo que nunca termina de aclarar.",
		"scene_path": "res://scenes/world/Gloomfen.tscn",
		"unlock_stat": "victories_ash_dunes", "unlock_target": 1,
		"locked_hint": "Gana una incursión en las Dunas de Ceniza",
		"palette": [Color(0.16, 0.28, 0.19), Color(0.1, 0.17, 0.14),
				Color(0.35, 0.85, 0.6), Color(0.42, 0.55, 0.46)],
		"tiers": DEFAULT_TIERS,
	},
]


## Lazily built id -> row index (see CatalogIndex): the select screen and
## every tier_spec() call resolve a row.
static var _by_id: Dictionary[String, Dictionary] = {}


## Row for the given id, or an empty Dictionary if unknown.
static func by_id(map_id: String) -> Dictionary:
	if _by_id.is_empty():
		_by_id = CatalogIndex.build(MAP_LIBRARY)
	return _by_id.get(map_id, {})


## Position of a map in the progression order, or 0 (the first stage) for
## an unknown id. THE stage-order accessor: RunRoot advances by index and
## wraps on MAP_LIBRARY.size(), so the library's order IS the run's order.
static func index_of(map_id: String) -> int:
	for i: int in MAP_LIBRARY.size():
		if String(MAP_LIBRARY[i].id) == map_id:
			return i
	return 0


## Row for the given id, or the default map's row when the id is unknown.
static func by_id_or_default(map_id: String) -> Dictionary:
	var row := by_id(map_id)
	return row if not row.is_empty() else by_id(DEFAULT_ID)


## The map's spec for the given tier; an unknown tier (or map) falls back
## to the baseline tier-1 spec, so bad input can only mean "current game".
static func tier_spec(map_id: String, tier: int) -> Dictionary:
	var tiers: Array = by_id_or_default(map_id).get("tiers", DEFAULT_TIERS)
	for entry: Variant in tiers:
		var spec := entry as Dictionary
		if int(spec.get("tier", 0)) == tier:
			return spec
	# A row that declares an empty (or malformed) ladder must still boot the
	# arena at the baseline instead of dying on tiers[0].
	if tiers.is_empty():
		return DEFAULT_TIERS[0]
	return tiers[0] as Dictionary


static func tier_shard_bonus(map_id: String, tier: int) -> int:
	return int(tier_spec(map_id, tier).shard_bonus)


## One-line description of a tier for the select screen.
static func tier_summary(map_id: String, tier: int) -> String:
	var spec := tier_spec(map_id, tier)
	if int(spec.tier) <= 1:
		return "Grado 1 — la cacería estándar"
	return "Grado %d — enemigos +%d%% HP, +%d%% daño · +%d esquirlas extra" % [
			int(spec.tier),
			roundi((float(spec.enemy_hp_mult) - 1.0) * 100.0),
			roundi((float(spec.enemy_damage_mult) - 1.0) * 100.0),
			int(spec.shard_bonus)]
