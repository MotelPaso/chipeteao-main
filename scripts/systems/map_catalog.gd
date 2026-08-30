class_name MapCatalog
extends RefCounted
## Static catalog of run maps/biomes (GDD 7). Data-driven like the other
## catalogs — a new biome is one row here plus its arena scene. The select
## screen builds the map row from these rows and SaveData.is_map_unlocked()
## evaluates the unlock rule.
## Row fields:
##   id/display_name/blurb: identity plus the select-card flavor line.
##   scene_path: arena scene Start Run loads. Every arena instances
##             RunSystems.tscn, which republishes the map id into
##             GameConfig so directly-booted arenas fold correctly.
##   unlock_stat/unlock_target: SaveData lifetime counter gate; an empty
##             stat means always playable (see the canonical counter id
##             list in save_data.gd).
##   locked_hint: select-card line telling the player how to unlock.
##   palette: swatch-strip colors on the select card (the biome's mood).

## Fallback map when no selection was made (an arena booted directly).
const DEFAULT_ID: String = "hollow_woods"

const MAP_LIBRARY: Array[Dictionary] = [
	{
		"id": "hollow_woods", "display_name": "Hollow Woods",
		"blurb": "Mossy glades under a patient green canopy.",
		"scene_path": "res://scenes/world/HollowWoods.tscn",
		"unlock_stat": "", "unlock_target": 0,
		"locked_hint": "",
		"palette": [Color(0.3, 0.56, 0.3), Color(0.15, 0.34, 0.19),
				Color(0.44, 0.3, 0.2), Color(0.79, 0.83, 0.72)],
	},
	{
		"id": "ash_dunes", "display_name": "Ash Dunes",
		"blurb": "Scorched sand, leaning monuments, a horizon that hums.",
		"scene_path": "res://scenes/world/AshDunes.tscn",
		"unlock_stat": "victories", "unlock_target": 1,
		"locked_hint": "Win a run in Hollow Woods",
		"palette": [Color(0.82, 0.66, 0.4), Color(0.68, 0.36, 0.26),
				Color(0.24, 0.55, 0.45), Color(0.94, 0.66, 0.42)],
	},
]


## Row for the given id, or an empty Dictionary if unknown.
static func by_id(map_id: String) -> Dictionary:
	for row: Dictionary in MAP_LIBRARY:
		if String(row.id) == map_id:
			return row
	return {}


## Row for the given id, or the default map's row when the id is unknown.
static func by_id_or_default(map_id: String) -> Dictionary:
	var row := by_id(map_id)
	return row if not row.is_empty() else by_id(DEFAULT_ID)
