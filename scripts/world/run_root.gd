class_name RunRoot
extends Node3D
## Persistent root of a run (iteration 49). Everything that must SURVIVE a
## map change lives under here: the run block (RunSystems — Player,
## RunManager, WorldDirector, HUD, card picker, run-end screen, pause
## menu) and nothing else. The biome of the moment is instanced under
## ArenaHost and thrown away when the party leaves through the exit
## portal, so a run is now a sequence of STAGES instead of one arena.
##
## What carries across a stage: the raiders themselves and therefore their
## level, weapons, tomes, items, pets, points, altar boons, timed boons,
## the run-wide difficulty and the chest/roulette inflation — none of it is
## copied, because none of it is re-created. What resets: the map and
## everything parented to it (chests, altars, portals, roulettes, beacons,
## enemies, props), the stage clock and the boss schedule.
##
## Stage order is MapCatalog.MAP_LIBRARY order, wrapping to the first map
## with lap + 1. RunState holds the counters; this node owns the swap.
##
## Reached through the "run_root" group, never by path — arena_root() in
## particular is what every stage-scoped spawn parents to, so nothing from
## stage N can outlive stage N.

## Node the stage's arena scene is instanced under.
const ARENA_HOST_NAME: String = "ArenaHost"
## Beat between freeing the old arena and building the next one, so the
## engine actually reclaims the freed nodes before the sweep counts them.
const SWAP_SETTLE_FRAMES: int = 1

@onready var _arena_host: Node3D = get_node(ARENA_HOST_NAME)

## The arena of the current stage. Cached because Pools and every world
## spawn ask for it constantly; refreshed on every swap.
var _arena: Node3D = null
## True from the moment a swap starts until the new stage is live: a
## second raider pressing the portal mid-fade must not start a second one.
var _swapping: bool = false


func _enter_tree() -> void:
	add_to_group("run_root")


func _ready() -> void:
	# RunSystems (a child) already called RunState.reset() in its
	# _enter_tree, so the stage counters are clean here; this only decides
	# WHICH stage the run opens on. Normal play and the daily always start
	# in the forest; the soak harness points BONK_ARENA at a biome, which
	# becomes GameConfig.start_map_id.
	RunState.stage_index = MapCatalog.index_of(GameConfig.start_map_id)
	RunState.lap = 0
	_load_stage()


## The live arena, or null between stages. THE accessor for stage-scoped
## parenting (Pools, dropped chests, FX): everything that used to reach
## for get_tree().current_scene now asks here, because current_scene is
## the run root and never changes any more.
func arena_root() -> Node3D:
	if _arena != null and not is_instance_valid(_arena):
		_arena = null
	return _arena


## Public alias with the name the rest of the codebase reads better with.
func current_arena() -> Node3D:
	return arena_root()


## THE parent for anything spawned INTO THE WORLD from anywhere in the
## codebase (pooled FX, dropped chests, boss spikes, weapon projectiles,
## the roulette's blocking UI). Static and tree-taking so scripts without
## an autoload of their own can reach it in one line.
## Before iteration 49 every one of those call sites used
## get_tree().current_scene, which WAS the arena. It is now the persistent
## run root, so spawning there would carry stage 1's darts, chests and
## puddles into stage 2. Falls back to current_scene outside a run (menus)
## and to the tree root as a last resort.
static func stage_parent(tree: SceneTree) -> Node:
	if tree == null:
		return null
	var root := tree.get_first_node_in_group("run_root")
	if root != null and root.has_method("arena_root"):
		var arena: Variant = root.call("arena_root")
		if arena is Node3D and is_instance_valid(arena):
			return arena
	return tree.current_scene if tree.current_scene != null else tree.root


## Builds the stage RunState.stage_index points at: instantiate, publish
## the map id, place the party, announce. The arena's own _ready drives
## the director/scatter handshake (see arena.gd).
func _load_stage() -> void:
	var row := MapCatalog.MAP_LIBRARY[RunState.stage_index % MapCatalog.MAP_LIBRARY.size()]
	var map_id := String(row.id)
	var packed := load(String(row.scene_path)) as PackedScene
	if packed == null:
		push_error("RunRoot: cannot load arena '%s'" % row.scene_path)
		return
	var arena := packed.instantiate() as Node3D
	if arena == null:
		push_error("RunRoot: arena root of '%s' is not a Node3D" % row.scene_path)
		return
	# Cached BEFORE add_child: the scatter's _enter_tree and the arena's
	# _ready both run inside add_child, and both reach back through
	# arena_root() (directly, or through Pools).
	_arena = arena
	GameConfig.selected_map_id = map_id
	if not RunState.visited_map_ids.has(map_id):
		RunState.visited_map_ids.append(map_id)
	_arena_host.add_child(arena)
	_place_party()
	RunState.stage_changed.emit(RunState.stage_index, map_id)


## Puts every raider (standing or downed) at the stage's spawn point.
## Delegated to the run block, which owns the co-op ring geometry.
func _place_party() -> void:
	var origin := Vector3.ZERO
	var arena := _arena as Arena
	if arena != null:
		origin = arena.spawn_origin()
	get_tree().call_group("run_systems", "place_party", origin)


## Public (exit portal, through the "run_root" group): tears the current
## stage down and builds the next one behind a fade. Ignored while a swap
## is already running.
## Whether a swap can START right now. Synchronous on purpose: a caller
## that spends itself to take the portal has to know BEFORE it does,
## and advance_stage is a coroutine whose answer only comes back after
## the whole swap — by which time the portal has been freed with its
## own arena.
func can_advance_stage() -> bool:
	return not _swapping and RunState.run_active and not ScreenFade.is_busy()


func advance_stage() -> void:
	# A run that already ended must not build another stage: the fold has
	# read stages_cleared_total, laps_completed and visited_map_ids, and a
	# swap landing after it would move all three behind the ledger's back
	# and run the next stage's fixtures under the run-end screen.
	if _swapping or not RunState.run_active:
		return
	_swapping = true
	# Awaited, so this method is a coroutine too — callers fire it and
	# forget (the exit portal does), and the flag below is what makes a
	# second press during the fade a no-op.
	if not await ScreenFade.transition_async(_swap_stage):
		# A fade was already running (a run ending, a menu leaving): the
		# stage stands, and the portal can be pressed again.
		_swapping = false


## The swap itself, awaited by ScreenFade between the fade-in and the
## fade-out. Every step is ordered on purpose; see the section comments.
func _swap_stage() -> void:
	var from_index := RunState.stage_index
	var from_id := String(MapCatalog.MAP_LIBRARY[from_index % MapCatalog.MAP_LIBRARY.size()].id)
	# 1. Freeze the world. The pause also stops player input, which is what
	#    keeps a raider from walking into a scene being freed.
	# 0. Close every blocking menu that CAN be closed, and do it before
	#    anything here reads the pause. Those layers (VendorUi, RouletteUi)
	#    hang off the ARENA, so step 5 frees them without ever running
	#    their _close() — the only place either one hands the pause back —
	#    and a `was_paused` read while one of them still held it would be
	#    true, so step 7 would decline to unpause as well. A swap landing
	#    on an open stall left the tree paused for the rest of the process,
	#    with Esc refused (PauseMenu._open returns on an already-paused
	#    tree) and nothing alive left to press Salir. `dismiss()` is
	#    exactly the hook the "blocking_ui_closable" group was declared for.
	#    Menus that are NOT closable (the card picker) keep their pause and
	#    are handled by _other_blocking_ui_open() at the end.
	get_tree().call_group(&"blocking_ui_closable", "dismiss")
	var was_paused := get_tree().paused
	get_tree().paused = true
	# The pause is NOT enough on its own: process_mode INHERITS, and the
	# soak harness roots the whole run under an always-processing node, so
	# a "paused" tree there still ticks the spawner and the director. Both
	# are stopped explicitly — a spawner still working while its arena is
	# torn down put six enemies into the first Stage sweep, and the
	# director would drop a chest into a map nobody will ever see.
	get_tree().call_group("enemy_spawner", "set_physics_process", false)
	# 2. What the party is carrying, read off the live nodes.
	_print_carry()
	# 3. Tear the stage down.
	_free_enemies()
	Pools.release_all_live()
	get_tree().call_group("world_director", "on_stage_ended")
	_free_stage_props()
	# 4. Let the engine settle the frees before counting them.
	for i in SWAP_SETTLE_FRAMES:
		await get_tree().process_frame
	_print_sweep()
	# 5. Free the arena itself. free(), not queue_free(): the next stage is
	#    built on the very next line and two live arenas would both answer
	#    the "arena_bounds" and "enemy_spawner" group lookups.
	if _arena != null and is_instance_valid(_arena):
		_arena_host.remove_child(_arena)
		_arena.free()
	_arena = null
	# 6. Advance the counters and build the next stage.
	var next_index := (from_index + 1) % MapCatalog.MAP_LIBRARY.size()
	if next_index == 0:
		RunState.lap += 1
		RunState.laps_completed += 1
	RunState.stage_index = next_index
	RunState.begin_stage()
	_load_stage()
	# 7. Announce. 1-based everywhere the player (or a soak log) can see it.
	var to_id := String(MapCatalog.MAP_LIBRARY[next_index].id)
	get_tree().call_group("boss_ui", "announce_major", "Etapa %d — %s" % [
			RunState.stage_index + 1,
			String(MapCatalog.by_id_or_default(to_id).display_name)])
	get_tree().call_group("hud", "show_stage_tag", RunState.stage_index, RunState.lap)
	# One-line log (RunManager convention) for headless soaks.
	print("Stage advanced: %d -> %d (%s) at %.1fs" % [
			from_index + 1, next_index + 1, to_id, RunState.run_time])
	_print_carry()
	if not was_paused and not _other_blocking_ui_open():
		get_tree().paused = false
	_swapping = false
	# from_id is only read by the debug narration below, but keeping it in
	# one place beats recomputing the outgoing name in two prints.
	if OS.get_environment("BONK_PROBE_DEBUG") == "1":
		print("RunRoot: left %s" % from_id)


## Every enemy body, freed immediately. free() and not queue_free() so the
## sweep two lines later counts what is REALLY gone: a queued free lands at
## the end of the frame, after the count.
func _free_enemies() -> void:
	for group: StringName in [&"enemies", &"boss"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			if is_instance_valid(node) and not node.is_queued_for_deletion():
				node.get_parent().remove_child(node)
				node.free()


## Stage-scoped world objects that are NOT children of the arena scene
## file: everything the director and the world dropped during the stage.
## They are parented to the arena root (world_director._stage_parent), so
## most of them would die with it anyway — but the sweep runs BEFORE the
## arena is freed, and a stage that leaks one of these is exactly what the
## sweep exists to catch. Later prompts append their own kinds here.
func _free_stage_props() -> void:
	var kinds: Array[StringName] = [&"altars", XpGem.LIVE_GROUP, HealthOrb.LIVE_GROUP,
			&"powerup_pickups", &"pet_boxes", &"vendors", &"possessed", &"lucky_blocks"]
	for group: StringName in kinds:
		for node: Node in get_tree().get_nodes_in_group(group):
			if is_instance_valid(node) and not node.is_queued_for_deletion():
				var parent := node.get_parent()
				if parent != null:
					parent.remove_child(node)
				node.free()
	# Chests, portals, roulettes, springs and beacons carry no group of
	# their own; they are all Interactables or plain Node3Ds parented to
	# the arena, so the arena walk below catches every one of them.
	var arena := arena_root()
	if arena != null:
		for node: Node in _stage_leftovers(arena):
			if is_instance_valid(node) and not node.is_queued_for_deletion():
				node.get_parent().remove_child(node)
				node.free()


## Interactables and beacons still standing in `root`. Recursive because
## an arena keeps its scene-placed shrines under an "Interactables" node
## while the director parents its own spawns directly to the arena root.
func _stage_leftovers(root: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in root.get_children():
		if child is Interactable:
			found.append(child)
			continue
		found.append_array(_stage_leftovers(child))
	return found


## What is still alive right before the arena goes. Every counter must be
## zero: a non-zero one is a leak that would follow the party into the
## next stage. Later prompts append their own fields.
func _print_sweep() -> void:
	var chests := 0
	var arena := arena_root()
	if arena != null:
		for node: Node in _stage_leftovers(arena):
			if node is Chest:
				chests += 1
	var beacons := 0
	var director := get_tree().get_first_node_in_group("world_director")
	if director != null and director.has_method("beacon_count"):
		beacons = int(director.call("beacon_count"))
	print(("Stage sweep: enemies=%d gems=%d orbs=%d chests=%d altars=%d beacons=%d"
			+ " pickups=%d boxes=%d vendors=%d possessed=%d") % [
			get_tree().get_node_count_in_group(&"enemies"),
			get_tree().get_node_count_in_group(XpGem.LIVE_GROUP),
			get_tree().get_node_count_in_group(HealthOrb.LIVE_GROUP),
			chests,
			get_tree().get_node_count_in_group(&"altars"),
			beacons,
			get_tree().get_node_count_in_group(&"powerup_pickups"),
			get_tree().get_node_count_in_group(&"pet_boxes"),
			get_tree().get_node_count_in_group(&"vendors"),
			get_tree().get_node_count_in_group(&"possessed")])


## The party's progress, computed from the LIVE nodes on both sides of the
## swap. Printed twice on purpose: two identical lines are the proof that
## a stage change costs the party nothing. Never cached — a cached copy
## would report what we meant to carry, not what actually crossed.
func _print_carry() -> void:
	var weapons := 0
	var tomes := 0
	var items := 0
	var points := 0
	for group: String in ["player", "downed_players"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var mount := node.get_node_or_null("Weapons")
			if mount != null:
				for child: Node in mount.get_children():
					if child is WeaponBase:
						weapons += 1
			var stats := PlayerStats.find_in(node)
			if stats != null:
				tomes += stats.distinct_tome_count()
			var bag := ItemBag.find_in(node)
			if bag != null:
				items += bag.carried_ids().size()
			var purse: Variant = node.get("points")
			if purse != null:
				points += int(purse)
	print("Stage carry: level=%d weapons=%d tomes=%d items=%d points=%d" % [
			RunState.level, weapons, tomes, items, points])


## Any member of "ui_blocking" holding the pause right now (the card
## picker, the run-end screen). The swap must not hand the world back to a
## screen that took the pause for itself.
func _other_blocking_ui_open() -> bool:
	for node: Node in get_tree().get_nodes_in_group("ui_blocking"):
		if not node.has_method(&"is_blocking"):
			continue
		if node.call(&"is_blocking") == true:
			return true
	return false
