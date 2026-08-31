extends Node3D
## Root of RunSystems.tscn: the map-independent run block every arena
## scene instances — Player, RunManager, upgrade-card UI, HUD, and the
## run-end screen, with run_ended already wired to the end screen inside
## this scene. Arenas keep their own EnemySpawner and AmbientBed (the
## boss timetable and the wind differ per biome) and override map_id on
## the instance.

## MapCatalog id of the arena this instance sits in. Republished to
## GameConfig at ready so a directly-booted arena (headless soaks, F6)
## still folds per-map counters correctly and Retry resolves to the same
## map; via the select screen this is an idempotent re-set.
@export var map_id: String = MapCatalog.DEFAULT_ID


func _ready() -> void:
	GameConfig.selected_map_id = map_id
	# Settle the run's map tier: a pick this map hasn't earned (stale
	# cross-map selection, edited config) falls back to the baseline.
	if not SaveData.is_tier_unlocked(map_id, GameConfig.selected_tier):
		GameConfig.selected_tier = 1
	# Push the tier out through groups, never node paths. Works because the
	# arena's EnemySpawner and this RunSystems' HUD sit earlier in tree
	# order, so both joined their groups before this _ready runs.
	var spec := MapCatalog.tier_spec(map_id, GameConfig.selected_tier)
	get_tree().call_group("enemy_spawner", "apply_tier_spec", spec)
	get_tree().call_group("hud", "show_tier_tag", GameConfig.selected_tier)
