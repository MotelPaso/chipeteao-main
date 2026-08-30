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
