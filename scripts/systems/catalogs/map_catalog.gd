class_name MapCatalog
extends RefCounted
## Static catalog of run maps/biomes (GDD 7). Data-driven like the other
## catalogs — a new biome is one row here plus its arena scene (root
## script arena.gd; it does NOT instance RunSystems any more).
##
## THE ORDER OF THIS LIST IS THE ORDER OF A RUN (iteration 50): every run
## opens on the first row and walks down it, wrapping to the top with
## lap + 1. There is no map picker and no unlock gate — a biome is reached
## by getting there, not by choosing it — so a new biome inserted here
## changes the progression for everyone immediately.
## Row fields:
##   id:     identifier (English, keys SaveData counters) — never shown.
##   display_name/blurb: player text (the stage banner, the end screen).
##   scene_path: arena scene RunRoot instantiates for that stage.
##   palette: swatch colors for the biome's mood (used by the UI).

## First stage of every run, and the fallback for an unknown id.
const DEFAULT_ID: String = "hollow_woods"

const MAP_LIBRARY: Array[Dictionary] = [
	{
		"id": "hollow_woods", "display_name": "Bosque Hueco",
		"blurb": "Claros musgosos bajo un dosel verde y paciente.",
		"scene_path": "res://scenes/world/HollowWoods.tscn",
		"palette": [Color(0.3, 0.56, 0.3), Color(0.15, 0.34, 0.19),
				Color(0.44, 0.3, 0.2), Color(0.79, 0.83, 0.72)],
	},
	{
		"id": "ash_dunes", "display_name": "Dunas de Ceniza",
		"blurb": "Arena calcinada, monumentos inclinados, un horizonte que zumba.",
		"scene_path": "res://scenes/world/AshDunes.tscn",
		"palette": [Color(0.82, 0.66, 0.4), Color(0.68, 0.36, 0.26),
				Color(0.24, 0.55, 0.45), Color(0.94, 0.66, 0.42)],
	},
	{
		"id": "gloomfen", "display_name": "Ciénaga Lóbrega",
		"blurb": "Islas de musgo anegado bajo un cielo que nunca termina de aclarar.",
		"scene_path": "res://scenes/world/Gloomfen.tscn",
		"palette": [Color(0.16, 0.28, 0.19), Color(0.1, 0.17, 0.14),
				Color(0.35, 0.85, 0.6), Color(0.42, 0.55, 0.46)],
	},
]


## Lazily built id -> row index (see CatalogIndex): RunRoot resolves a row
## on every stage, the end screen on every map it names.
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
