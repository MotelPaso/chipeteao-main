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

## Radius of the ring co-op slots 1..N-1 spawn on, around the scene's
## slot-0 spawn point. Generated instead of tabulated: a fixed table of
## three offsets indexed with a modulo silently sat two raiders on the
## same point the moment the party grew past it.
@export var coop_spawn_radius: float = 1.8

## Preloaded (not the bare class_name) so headless runs that never built
## the editor's class cache still resolve it.
const SplitScreenView := preload("res://scripts/systems/split_screen.gd")
const PLAYER_SCENE := preload("res://scenes/player/Player.tscn")


## The run block owns the run reset (it is the one node every arena
## instances, and it enters the tree BEFORE the WorldDirector child that
## shuffles the layout). That makes a directly booted arena — F6, headless
## soaks — start from zero like a real run, and re-seeds the Daily Hunt
## stream at a fixed point instead of however many frames earlier the
## menu happened to call it. reset() is idempotent, so the select screen's
## own call stays harmless.
func _enter_tree() -> void:
	RunState.reset()


func _ready() -> void:
	# Items and altars reach the run block through this group (vacuum_pickups).
	add_to_group("run_systems")
	GameConfig.selected_map_id = map_id
	if Coop.is_coop():
		_spawn_party()
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
	# Iteration 38: leveling no longer vacuums the floor. The gem/orb
	# vacuum() hooks stay for the Magnet item, which fires them on its own
	# timer (see vacuum_pickups).


## Magnet-item hook (and any future "hoover the floor" effect): every live
## XP gem and health orb force-homes to the nearest player at once,
## regardless of pickup radius. Idempotent on gems already homing.
func vacuum_pickups() -> void:
	get_tree().call_group(XpGem.LIVE_GROUP, "vacuum")
	get_tree().call_group(HealthOrb.LIVE_GROUP, "vacuum")


## Co-op boot: the scene's Player becomes slot 0; slots 1..N-1 are extra
## Player.tscn instances offset around the same spawn, then the whole
## screen becomes a SplitScreen of per-player views. Runs inside this
## _ready (parent readies after children), so RunManager's and the HUD's
## deferred party binds see the full roster on the same frame.
func _spawn_party() -> void:
	var first := get_node("Player") as Player
	var players: Array = [first]
	for slot in range(1, Coop.player_count):
		var extra := PLAYER_SCENE.instantiate() as Player
		extra.name = "Player%d" % (slot + 1)
		extra.player_index = slot
		# Position BEFORE add_child: Player._ready records its spawn point
		# (void-rescue anchor) the moment it enters the tree.
		extra.position = first.position + _coop_spawn_offset(slot)
		add_child(extra)
		players.append(extra)
	add_child(SplitScreenView.build(players))


## Slot `slot`'s offset on the spawn ring: one even share of the circle
## per party member, so no two slots can land on the same point.
func _coop_spawn_offset(slot: int) -> Vector3:
	var angle := TAU * float(slot) / float(maxi(Coop.player_count, 1))
	return Vector3(cos(angle), 0.0, sin(angle)) * coop_spawn_radius
