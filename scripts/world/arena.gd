class_name Arena
extends Node3D
## Root of a biome scene (Hollow Woods, Ash Dunes, Gloomfen). Since
## iteration 49 an arena is ONLY the world: floor, perimeter, backdrop,
## light, verticality, scene-placed interactables, scatter, spawner and
## ambience. The run block (Player, RunManager, WorldDirector, HUD, the
## card picker) no longer lives here — it lives in Run.tscn, above the
## ArenaHost this scene is instanced under, and survives every stage
## change. An arena is therefore disposable: it is built for a stage and
## freed when the party leaves through the exit portal.
##
## Because of that, an arena scene is NOT bootable on its own any more
## (F6, a direct `--quit-after` on the .tscn): with no run root there is
## no player, no HUD and no director. Boot `res://scenes/world/Run.tscn`
## and pick the biome with GameConfig.start_map_id (the soak harness does
## exactly that through BONK_ARENA).
##
## Stage lifecycle, in the order it MUST happen (RunRoot drives it):
##   1. RunRoot instantiates this scene under ArenaHost. Children enter
##      the tree, so the scatter's _enter_tree builds this stage's mask.
##   2. Children run their _ready (spawner, ambience, interactables).
##   3. This _ready hands the arena to the WorldDirector, which caches the
##      bounds, shuffles the ground POIs and places the run-start fixtures.
##   4. This _ready then lets the scatter dress the arena, so its keepout
##      list sees the SHUFFLED positions — the same order the old
##      _enter_tree/_ready split produced when every arena owned its own
##      director.

## MapCatalog id of this biome. Overridden per arena scene; it is what
## RunRoot and the meta fold key their per-map counters on.
@export var map_id: String = MapCatalog.DEFAULT_ID

## Where slot 0 lands when the party arrives. A Marker3D child, so a biome
## can move its landing spot without code; the scene origin is a fine
## default for all three shipped arenas.
const SPAWN_POINT_NAME: String = "SpawnPoint"


func _ready() -> void:
	# The run root finds the live arena through this group, never by path:
	# ArenaHost's child changes name every stage.
	add_to_group("arena_root")
	get_tree().call_group("world_director", "on_stage_started", self)
	_dress_arena()


## Step 4 above. The scatter is found through "arena_bounds" (its own
## group) and filtered to THIS arena: with a swap in flight there can be
## an outgoing arena still in the tree, and dressing it would place props
## into a scene about to be freed.
func _dress_arena() -> void:
	for node: Node in get_tree().get_nodes_in_group("arena_bounds"):
		if node.has_method("place_props") and is_ancestor_of(node):
			node.call("place_props")


## World position slot 0 spawns at. Falls back to the arena's own origin,
## which is where every raider used to appear before this marker existed.
func spawn_origin() -> Vector3:
	var marker := get_node_or_null(SPAWN_POINT_NAME) as Node3D
	return marker.global_position if marker != null else global_position
