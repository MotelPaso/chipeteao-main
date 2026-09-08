extends Node
## WorldDirector (iteration 33): keeps the arena ALIVE for the whole run.
## Lives in RunSystems.tscn, so every map gets it for free. Two jobs:
##
## 1. Layout shuffle (at _enter_tree, BEFORE the scatter's _ready uses
##    interactable positions as keepouts): every ground-level interactable
##    tagged "scatter_keepout" (shrines, the ground chest, the buried
##    secrets) moves to a fresh random spot each run, so exploration can't
##    be memorized. Chests placed on verticality spots stay put — climbing
##    for them is the point.
##
## 2. Timed world events, announced on the HUD banner, from ~75s until the
##    run ends — the answer to "explored everything by minute 2, nothing
##    left to do": every 50-75s one row of EVENT_LIBRARY fires (supply
##    chest, elite pack, essence rift, charge altar, demonic obelisk,
##    spring), and a sky event may roll on top of it.
## Every point these place goes through the arena's walkable mask and a
## ground probe, so an announced POI is always something the player can
## actually walk to and stand on.
## Default pausable process mode: events freeze under card picks/pause.

const CHEST_SCENE := preload("res://scenes/world/chests/Chest.tscn")
const XP_GEM_SCENE := preload("res://scenes/systems/XpGem.tscn")
const CHARGE_SHRINE_SCENE := preload("res://scenes/world/shrines/ChargeShrine.tscn")
const CURSE_SHRINE_SCENE := preload("res://scenes/world/shrines/CurseShrine.tscn")
const SPRING_SHRINE_SCENE := preload("res://scenes/world/shrines/SpringShrine.tscn")
const ROULETTE_SHRINE_SCENE := preload("res://scenes/world/shrines/RouletteShrine.tscn")
const EVENT_ALTAR_SCENE := preload("res://scenes/world/shrines/EventAltar.tscn")
const PET_BOX_SCENE := preload("res://scenes/world/PetBox.tscn")
const VENDOR_SCENE := preload("res://scenes/world/Vendor.tscn")
const PortalShrineScript := preload("res://scripts/world/portal_shrine.gd")

## Timed world events as catalog rows (project convention: content is
## data). `weight` is relative; `method` runs the event. A new event is
## one row plus its method — no index arithmetic to keep in sync.
const EVENT_LIBRARY: Array[Dictionary] = [
	{"id": "supply_chest", "weight": 1.0, "method": &"_event_supply_chest"},
	{"id": "elite_pack", "weight": 1.0, "method": &"_event_elite_pack"},
	{"id": "essence_rift", "weight": 1.0, "method": &"_event_essence_rift"},
	# `altar` marks the rows the altar cadence rules apply to (weight rising
	# with the minute, capped by how many unspent altars already stand).
	{"id": "charge_altar", "weight": 1.6, "method": &"_event_charge_altar", "altar": true},
	{"id": "demonic_altar", "weight": 0.5, "method": &"_event_demonic_altar", "altar": true},
	{"id": "spring", "weight": 0.7, "method": &"_event_spring"},
	# The star is the only power-up nobody can farm: it is not a kill drop
	# and no vendor sells it, so this row is the entire supply.
	{"id": "star_sighting", "weight": 0.15, "method": &"_event_star"},
	# Vendors and the pet box (iteration 54). No `altar` flag: the altar
	# cadence and its cap are about altars, and a stall counted there would
	# starve them.
	{"id": "vendor", "weight": 0.8, "method": &"_event_vendor"},
	{"id": "pet_box", "weight": 0.35, "method": &"_event_pet_box"},
	# The event altar (iteration 55). No `altar` flag: that flag drives the
	# charge/demonic cadence and its unspent cap, and this one is neither.
	{"id": "event_altar", "weight": 0.4, "method": &"_event_event_altar"},
]

## Rejection-sampling budget for a clear POI spot, and for the ring sample
## an event point gets before it falls back to the run-start sampler.
## How long the star's beacon burns. It marks WHERE it was seen, not where
## it is: the star moves, and a beacon that tracked it would turn the one
## thing you are supposed to chase into a thing you follow.
const STAR_BEACON_TIME: float = 12.0
const CLEAR_POINT_ATTEMPTS: int = 60
const EVENT_POINT_ATTEMPTS: int = 24
## Fallback probe span used when there is no terrain to measure against.
const GROUND_PROBE_HEIGHT: float = 20.0
## With a terrain, the probe starts this far above its highest point (room
## for a mesa standing on a hill) and ends this far below its lowest.
const PROBE_HEADROOM: float = 30.0
const PROBE_UNDERSHOOT: float = 2.0
## Used only if portal_pair_colors is emptied in the inspector.
const DEFAULT_PORTAL_COLORS: Array[Color] = [Color(0.5, 0.9, 1.0)]


## One live light beacon: the pillar node, the POI it advertises and the
## seconds it has left. The beacon dies WITH its owner — an altar charged
## three seconds after it rose used to leave a 22 m pillar burning over
## empty ground for the remaining 42 s, pulling players across the arena
## toward nothing.
class TimedBeacon:
	var node: Node3D
	## The POI this beacon points at; null for the essence rift, whose gems
	## carry their own lifetime and leave nothing behind to watch.
	var poi: Node = null
	var time_left: float = 0.0
	## Supply chests are missable on purpose: when the window closes the
	## chest sinks away with its beacon. Altars and springs own their own
	## idle_lifetime, so only the light goes out.
	var sink_poi: bool = false

	func _init(p_node: Node3D, p_poi: Node, p_time_left: float,
			p_sink_poi: bool = false) -> void:
		node = p_node
		poi = p_poi
		time_left = p_time_left
		sink_poi = p_sink_poi

	## True while the thing this beacon advertises is still worth the walk.
	func poi_worth_showing() -> bool:
		if poi == null:
			return true
		if not is_instance_valid(poi) or poi.is_queued_for_deletion():
			return false
		var available: Variant = poi.get("available")
		return not (available is bool) or bool(available)


## A shuffled POI authored above this height is standing on a verticality
## platform and keeps its y; anything at or below it is ground furniture
## and gets dropped onto the relief.
const POI_PLATFORM_Y: float = 0.5

@export_group("Layout Shuffle")
@export var shuffle_layout: bool = true
## Repositioned POIs keep at least these distances (meters) from the
## spawn, each other, and the hand-placed verticality spots.
@export var min_distance_from_spawn: float = 16.0
@export var min_distance_between: float = 18.0
@export var min_distance_from_keepouts: float = 12.0
## Margin off arena_half_extent POIs must stay inside (perimeter band).
@export var bounds_margin: float = 14.0

@export_group("Events")
@export var events_enabled: bool = true
## Run seconds before the first event, and the min/max gap between events.
@export var first_event_at: float = 75.0
@export var event_gap_min: float = 50.0
@export var event_gap_max: float = 75.0
## The gap shrinks as the run goes on (iteration 47) — a map that stops
## producing anything new is the whole complaint the events answer — but
## never below the floor, which is the shortest window a raider can
## actually cross the arena in.
@export var event_gap_floor: float = 20.0
@export var event_gap_decay_per_minute: float = 0.18
## Event points land this far from a random alive player.
@export var event_min_distance: float = 25.0
@export var event_max_distance: float = 45.0
@export var chest_lifetime: float = 40.0
@export var chest_luck_bonus: float = 0.4
@export var elite_pack_size: int = 3
@export var rift_gem_count: int = 10
## Each rift gem is worth this many XP (scene default is 1).
@export var rift_gem_value: int = 3
## Seconds the essence rift's beacon burns; the gems' own lifetime is the
## real pickup window, so the light fades sooner on purpose.
@export var rift_beacon_lifetime: float = 30.0
## Per-arena weight overrides for EVENT_LIBRARY, keyed by event id. An id
## left out keeps the library weight; a weight of 0 drops that event from
## the rotation for this map.
@export var event_weight_overrides: Dictionary[String, float] = {}
@export_group("Altars (iteration 47)")
## Altars get commoner as the run goes on: their EVENT_LIBRARY weight is
## multiplied by (1 + this x minutes), capped by altar_weight_max_scale.
@export var altar_weight_per_minute: float = 0.25
@export var altar_weight_max_scale: float = 3.0
## Cap on UNSPENT altars standing at once (scene-placed ones included),
## itself growing with the minute: altar_cap_base + minutes / cap_minutes.
## Altars no longer time out (iteration 47), so without a cap they would
## accumulate for the whole run.
## Stalls alive at once. Two is a choice between shops; three is clutter.
@export var max_vendors: int = 2
## Chance a stage opens with a pet box already standing.
@export var start_pet_box_chance: float = 0.5
## Chance a stage opens with an event altar already standing.
@export var start_event_altar_chance: float = 0.5
@export var altar_cap_base: int = 3
@export var altar_cap_minutes: float = 3.0
## Share of the run-start chests (scene-placed and the extras below) that
## costs nothing. Free chests roll their rarity when opened, so an early
## one is a real chance at a Legendary before any points exist.
@export var free_start_chest_chance: float = 0.15
@export_group("Exit portal (iteration 49)")
## How far the stage's exit portal lands from the nearest raider. Far
## enough to be a trip across the map, which is the point of a portal that
## opens when you have already won the stage.
@export var exit_portal_min_distance: float = 40.0
## Portals dropped at run start (paired: keep it even) and roulette wheels.
@export var portal_count: int = 4
@export var roulette_count: int = 1
@export var portal_pair_colors: Array[Color] = [
	Color(0.5, 0.9, 1.0), Color(0.95, 0.6, 1.0), Color(0.6, 1.0, 0.55), Color(1.0, 0.85, 0.4)]
@export_group("Sky events (iteration 42)")
## Rolled on every event tick once sky_event_min_gap passed; each demonic
## altar use makes them likelier. A negative moon is always followed by a
## full moon that buffs the party.
@export var sky_event_chance: float = 0.18
@export var sky_event_chance_per_demonic: float = 0.08
## The gap applies to EVERY weather group, not just the moons: exclusivity
## is about "one at a time", this is about "not back to back".
@export var sky_event_min_gap: float = 150.0
@export var full_moon_xp_bonus: float = 50.0
@export var full_moon_luck_bonus: float = 30.0
## Rolled BEFORE the rain and the moon on an event tick, so the rarest
## group gets first refusal. Demonic pacts sell this directly.
@export var disaster_chance: float = 0.08
## Rolled after the disaster, before the moon.
@export var rain_chance: float = 0.12
## Per-arena duration overrides for WEATHER_CATALOG, keyed by weather id,
## in seconds. Mirrors event_weight_overrides: an id left out keeps the
## catalog duration. (This replaced the old sky_event_duration and
## full_moon_duration exports, which could not live in a const catalog.)
@export var weather_duration_overrides: Dictionary[String, float] = {}
@export_group("Rains (iteration 55)")
@export var enemy_rain_interval: float = 1.5
@export var enemy_rain_min_drops: int = 3
@export var enemy_rain_max_drops: int = 6
@export var enemy_rain_min_distance: float = 12.0
@export var enemy_rain_max_distance: float = 25.0
@export var acid_pool_interval: float = 2.0
@export var acid_pool_radius: float = 2.0
@export var acid_pool_lifetime: float = 6.0
@export var acid_pool_spawn_range: float = 20.0
## Points multiplier and price discount while the golden rain falls.
@export var golden_points_multiplier: float = 2.0
@export var golden_price_discount: float = 0.5
@export_group("Disasters (iteration 55)")
@export var tsunami_base: int = 40
@export var tsunami_per_minute: int = 4
@export var tsunami_arc_min: float = 40.0
@export var tsunami_arc_max: float = 60.0
@export var earthquake_shake_interval: float = 0.5
@export var earthquake_shake_strength: float = 0.25
@export var earthquake_hud_amplitude: float = 14.0
@export var earthquake_hud_hz: float = 20.0
@export var earthquake_dust_interval: float = 3.0
@export var meteor_interval: float = 0.8
@export var meteor_range: float = 20.0
@export var meteor_radius: float = 3.0
@export var meteor_telegraph: float = 1.2
@export var meteor_damage: float = 40.0
@export var meteor_enemy_scale: float = 3.0

## RAW half-extent of the arena plate, as published by the "arena_bounds"
## node (scatter.gd's own default is 80.0); bounds_margin is subtracted at
## each use, so this must not be a pre-margined number.
var _arena_half_extent: float = 80.0
## The arena-bounds node: the single source of arena size AND of the
## irregular walkable mask (iteration 44).
var _bounds: Node3D = null
## The arena of the current stage; everything this director spawns is
## parented to it (see _stage_parent).
var _arena: Node3D = null
## One exit portal per stage (iteration 49).
var _exit_portal_spawned: bool = false
var _event_timer: float = 0.0
## Every point already occupied by a POI (shuffled or spawned), so later
## placements keep their distance.
var _placed_points: Array[Vector2] = []
var _anchor_points: Array[Vector2] = []
## The shuffled POIs themselves, parallel to _placed_points, so the
## irregular start can release the points of the ones it culls.
var _placed_pois: Array[Node3D] = []
## Live beacons (supply chests, altars, springs, rifts).
var _beacons: Array[TimedBeacon] = []
## Sky event state: current kind, seconds left, gap timer, cached lights.
## THE live weather, or empty: {id, group, time_left}. One at a time
## across all three groups — that exclusivity is the whole point of having
## one channel instead of three timers that could overlap.
var active_weather: Dictionary = {}
## Scratch owned by the running row's start/tick/stop, cleared on start so
## a row never reads the previous one's leftovers.
var _weather_state: Dictionary = {}
var _sky_gap_left: float = 0.0
var _sun: DirectionalLight3D = null
var _sun_color: Color = Color.WHITE
var _sun_energy: float = 1.0
var _environment: Environment = null
var _ambient_color: Color = Color.WHITE
var _ambient_energy: float = 1.0
## The ONE tween allowed to write sun/ambient. Two of them — an expiring
## dark moon restoring while the full moon tints — write the same
## properties every frame and the longer one lands last, which is why the
## announced FULL MOON never showed on screen.
var _sky_tween: Tween = null


func _ready() -> void:
	add_to_group("world_director")


## Stage hook (iteration 49), called by Arena._ready through the
## "world_director" group. This director is now PERSISTENT — one per run,
## not one per arena — so everything it used to do in _enter_tree/_ready
## happens here instead, once per stage, and every cached arena reference
## has to be dropped first.
## Order inside a stage: the scatter's _enter_tree already built the mask;
## this claims the arena, shuffles the ground POIs and places the
## run-start fixtures; the Arena then calls scatter.place_props(), whose
## keepouts therefore see the shuffled positions — the exact sequence the
## old per-arena director produced.
func on_stage_started(arena: Node3D) -> void:
	set_physics_process(true)
	_arena = arena
	# Re-cache the arena's lights from scratch. _cache_lights() returns
	# early while _sun is set, and _exit_tree (which used to restore them)
	# never fires now that this node outlives the arena: without these four
	# lines the second stage would tint stage 1's freed Sun and every sky
	# event after the first would be invisible.
	_kill_sky_tween()
	_sun = null
	_environment = null
	_sun_color = Color.WHITE
	_sun_energy = 1.0
	_ambient_color = Color.WHITE
	_ambient_energy = 1.0
	active_weather = {}
	_weather_state = {}
	_sky_gap_left = 0.0
	_bounds = null
	for node: Node in get_tree().get_nodes_in_group("arena_bounds"):
		var bounds := node as Node3D
		if bounds != null and arena.is_ancestor_of(bounds):
			_bounds = bounds
			_arena_half_extent = float(bounds.get("arena_half_extent"))
			break
	_placed_points.clear()
	_anchor_points.clear()
	_placed_pois.clear()
	_beacons.clear()
	_event_timer = first_event_at
	# Fog and map are per STAGE. Reset from HERE and not from the
	# stage_changed signal: this call is what stage 0 goes through too, so
	# there is no first-stage special case to forget.
	var fog := FogOfWar.find(get_tree())
	if fog != null:
		fog.reset_for_stage(arena)
	get_tree().call_group("hud", "on_stage_started", arena)
	_exit_portal_spawned = false
	if shuffle_layout:
		_shuffle_ground_interactables()
	# Irregular start (iteration 44) FIRST: it culls scene-placed POIs, and
	# the spots they were holding have to be released before the run-start
	# fixtures pick theirs — otherwise portals and the roulette keep their
	# 18 m distance from POIs that no longer exist.
	_randomize_starting_pois()
	# Run-start fixtures (iteration 41): paired portals and the roulette.
	_spawn_portals()
	_spawn_roulettes()
	_spawn_start_pet_boxes()
	_spawn_start_event_altars()


## 0-1 pet boxes at stage start (iteration 54). Zero is a real outcome:
## a companion should feel like something the map offered, not something
## every stage hands out.
func _spawn_start_pet_boxes() -> void:
	if randf() >= start_pet_box_chance:
		return
	_spawn_pet_box(_claim_clear_point())


## 0-1 event altars at stage start, like the pet box: a stage that always
## opened with one would make the weather feel scheduled rather than found.
func _spawn_start_event_altars() -> void:
	# Short-circuited, like the weather roll: a chance of zero must draw NO
	# random number. The game RNG is one shared stream and this runs at
	# stage start, so a die rolled here shifts where the portals, the
	# roulettes and every shuffled POI land.
	if start_event_altar_chance <= 0.0 or randf() >= start_event_altar_chance:
		return
	_spawn_event_altar(_claim_clear_point())


## Stage teardown (RunRoot, before the arena is freed): restore the sky the
## event tint borrowed and drop the beacon bookkeeping. The beacon NODES
## are parented to the arena and die with it; this only clears the list so
## the sweep can report zero.
func on_stage_ended() -> void:
	# Stop ticking for the length of the swap: this node OUTLIVES the
	# arena, and a director still firing events between the teardown and
	# the next map drops chests and altars into a scene about to be freed
	# (see the note in RunRoot._swap_stage about inherited process modes).
	set_physics_process(false)
	# The row's own stop() FIRST: a golden rain that ended with the stage
	# would otherwise leave a x2 points source on every raider and a 0.5
	# price discount in RunState, both of which outlive the arena.
	_stop_weather(false)
	_snap_sky_back()
	_beacons.clear()
	_placed_points.clear()
	_anchor_points.clear()
	_placed_pois.clear()
	_arena = null
	_bounds = null


## Live beacons, for the stage sweep.
func beacon_count() -> int:
	return _beacons.size()


## Where every world object this director spawns is parented: the arena of
## the moment, so a stage change takes them all with it. Falls back to
## this node only when there is no arena (teardown races), which keeps the
## spawn from erroring instead of silently leaking into the next stage.
func _stage_parent() -> Node:
	if _arena != null and is_instance_valid(_arena):
		return _arena
	var root := get_tree().get_first_node_in_group("run_root")
	if root != null and root.has_method("arena_root"):
		var arena: Variant = root.call("arena_root")
		if arena is Node3D and is_instance_valid(arena):
			return arena
	return self


## The run can end — or the scene reload — mid sky event, which kills the
## tint tween halfway. Snap the cached lighting back on the way out so a
## blood moon cannot bleed into the next run through a shared resource.
func _exit_tree() -> void:
	_stop_weather(false)
	_snap_sky_back()


## Restores the arena's own lighting IMMEDIATELY (no tween). Used when the
## arena is about to go — run teardown, or a stage swap: _restore_sky()
## eases over two seconds, and a tween writing into a freed Sun is an
## error, not a fade.
func _snap_sky_back() -> void:
	_kill_sky_tween()
	if _sun != null and is_instance_valid(_sun):
		_sun.light_color = _sun_color
		_sun.light_energy = _sun_energy
	if _environment != null:
		_environment.ambient_light_color = _ambient_color
		_environment.ambient_light_energy = _ambient_energy


@export_group("Irregular start (iteration 44)")
## Chance each scene-placed chest or altar is removed for this run.
@export var poi_skip_chance: float = 0.3
## Extra chests dropped at run start: random in [min, max].
@export var extra_start_chests_min: int = 0
@export var extra_start_chests_max: int = 2


func _randomize_starting_pois() -> void:
	var removed := 0
	var chests_kept := 0
	var freebies := 0
	for node: Node in get_tree().get_nodes_in_group("scatter_keepout"):
		if node is Chest or node is ChargeShrine or node is GreedShrine:
			if node is Chest and chests_kept == 0:
				chests_kept += 1  # always keep the first ground chest
				if _make_start_chest_free(node as Chest):
					freebies += 1
				continue
			if randf() < poi_skip_chance:
				node.queue_free()
				removed += 1
			elif node is Chest:
				chests_kept += 1
				if _make_start_chest_free(node as Chest):
					freebies += 1
	_refresh_placed_points()
	var extra := randi_range(extra_start_chests_min, extra_start_chests_max)
	for i in extra:
		var chest := CHEST_SCENE.instantiate() as Chest
		# Set BEFORE add_child: a chest decides its tint and its prompt in
		# _ready, and one flipped afterwards has to repaint itself.
		if randf() < free_start_chest_chance:
			chest.free_open = true
			freebies += 1
		_stage_parent().add_child(chest)
		chest.global_position = _claim_clear_point()
	print("Start layout: %d POI(s) skipped, %d extra chest(s), %d free" % [
			removed, extra, freebies])


## Rolls one already-ready scene chest free. Returns true when it flipped.
func _make_start_chest_free(chest: Chest) -> bool:
	if chest == null or randf() >= free_start_chest_chance:
		return false
	chest.make_free()
	return true


func _physics_process(delta: float) -> void:
	if not RunState.run_active:
		return
	_tick_exit_portal()
	_tick_beacons(delta)
	if not events_enabled:
		return
	_tick_weather(delta)
	_event_timer -= delta
	if _event_timer > 0.0:
		return
	_event_timer = _next_event_gap()
	_fire_random_event()
	_maybe_weather()


## Raises the stage's exit portal the first frame the stage counts as
## cleared. Polled rather than signalled: the gate is a poll too
## (RunManager), and one flag read per frame is cheaper than keeping two
## systems' signal wiring in sync across a stage swap.
func _tick_exit_portal() -> void:
	if _exit_portal_spawned or not RunState.stage_cleared:
		return
	_exit_portal_spawned = true
	var portal := ExitPortal.new()
	portal.name = "ExitPortal"
	_stage_parent().add_child(portal)
	portal.global_position = _exit_portal_point()
	# Burns until the party takes it: an exit with no deadline still needs
	# to be findable, and poi_worth_showing() puts the light out when the
	# portal is consumed.
	_beacons.append(TimedBeacon.new(
			_spawn_beacon(portal.global_position, portal.portal_color), portal, INF))
	get_tree().call_group("boss_ui", "track_objective", portal)
	_announce("Se abrió el portal de salida — crúzalo cuando quieras")
	# One-line log (RunManager convention) for headless soaks.
	print("Exit portal opened at %.1fs" % RunState.run_time)


## Somewhere clear, walkable and at least exit_portal_min_distance from
## every raider: the exit is a destination, not a thing you trip over the
## second the stage ends.
func _exit_portal_point() -> Vector3:
	var limit := _arena_half_extent - bounds_margin
	var best := Vector3.ZERO
	var best_distance := -1.0
	for attempt in CLEAR_POINT_ATTEMPTS:
		var candidate := Vector3(randf_range(-limit, limit), 0.0, randf_range(-limit, limit))
		if not _walkable(candidate):
			continue
		var nearest := _distance_to_nearest_player(candidate)
		if nearest > best_distance:
			best_distance = nearest
			best = candidate
		if nearest >= exit_portal_min_distance:
			break
	if best_distance < 0.0:
		# Every sample landed in a mask wall: fall back to the sampler that
		# knows where the open cells actually are.
		var point := _random_walkable_point()
		best = Vector3(point.x, 0.0, point.y)
	best.y = _ground_height(best)
	return best


func _distance_to_nearest_player(at: Vector3) -> float:
	var nearest := INF
	for node: Node in Coop.alive_players(get_tree()):
		var body := node as Node3D
		if body != null:
			nearest = minf(nearest, at.distance_to(body.global_position))
	return 0.0 if nearest == INF else nearest


## Run minutes elapsed; the altar cadence and the event gap both ride it.
func _minutes() -> float:
	return RunState.run_time / 60.0


## Seconds until the next event: the authored window, compressed by the
## minute, never below event_gap_floor.
func _next_event_gap() -> float:
	var raw := randf_range(event_gap_min, event_gap_max)
	return maxf(raw / (1.0 + event_gap_decay_per_minute * _minutes()), event_gap_floor)


## Unspent altars standing right now, wherever they came from — the arena's
## own fixtures and the ones this director raised are the same thing since
## iteration 47, so the cap has to see both. Group, not node paths.
func _unspent_altars() -> int:
	var count := 0
	for node: Node in get_tree().get_nodes_in_group("altars"):
		var available: Variant = node.get("available")
		if (available is bool and bool(available)) and not node.is_queued_for_deletion():
			count += 1
	return count


func _altar_cap() -> int:
	return altar_cap_base + floori(_minutes() / maxf(altar_cap_minutes, 0.001))


## --- arena mask -------------------------------------------------------------

func _walkable_xz(xz: Vector2) -> bool:
	if _bounds == null or not _bounds.has_method("is_walkable"):
		return true
	return bool(_bounds.call("is_walkable", xz))


func _walkable(pos: Vector3) -> bool:
	return _walkable_xz(Vector2(pos.x, pos.z))


## Last resort when rejection sampling finds nothing: the mask's own
## sampler, which knows where the open cells actually are.
func _random_walkable_point() -> Vector2:
	if _bounds != null and _bounds.has_method("random_walkable_point"):
		var point: Variant = _bounds.call("random_walkable_point", bounds_margin)
		if point is Vector2:
			return point
	return Vector2.ZERO


## Drops a POI onto whatever world geometry (layer 1) is under it. The
## arenas have real verticality — Ash Dunes' two-tier mesas, the forest
## platforms — well inside event_min_distance..event_max_distance, and a
## chest or altar left at y=0 under a mesa is buried: its Area3D never
## sees the player who climbed up following the beacon.
func _ground_height(pos: Vector3) -> float:
	var space := get_tree().root.world_3d.direct_space_state
	# The ray has to span the WHOLE relief (iteration 51): a mesa standing
	# on a hill is above the old 20 m start, and a hollow is below the old
	# -1 end, so either one used to escape the cast and fall back to 0.
	var terrain := Terrain.find(get_tree())
	var top := GROUND_PROBE_HEIGHT
	var bottom := -1.0
	if terrain != null:
		top = terrain.max_height + PROBE_HEADROOM
		bottom = terrain.min_height - PROBE_UNDERSHOOT
	var ray := PhysicsRayQueryParameters3D.create(
			Vector3(pos.x, top, pos.z), Vector3(pos.x, bottom, pos.z), 1)
	# Raiders share layer 1 with the world; never mistake a head for ground.
	var excluded: Array[RID] = []
	for node: Node in Coop.alive_players(get_tree()):
		var body := node as CollisionObject3D
		if body != null:
			excluded.append(body.get_rid())
	ray.exclude = excluded
	var hit := space.intersect_ray(ray)
	if hit.is_empty():
		# Nothing under the point: the TERRAIN height, not 0. Zero is a
		# real height somewhere on a heightmap, so falling back to it used
		# to bury or float a POI by whatever the relief happened to be.
		return terrain.height_at(pos.x, pos.z) if terrain != null else 0.0
	var hit_position: Vector3 = hit["position"]
	return hit_position.y


## --- layout shuffle ---------------------------------------------------------

func _shuffle_ground_interactables() -> void:
	var movable: Array[Node3D] = []
	var anchors: Array[Vector2] = []
	for node: Node in get_tree().get_nodes_in_group("scatter_keepout"):
		var spot := node as Node3D
		if spot == null:
			continue
		if spot is Interactable:
			movable.append(spot)
		else:
			# Verticality spots and rock clusters: fixed obstacles to avoid.
			anchors.append(Vector2(spot.global_position.x, spot.global_position.z))
	var placed: Array[Vector2] = []
	var limit := _arena_half_extent - bounds_margin
	for poi: Node3D in movable:
		var spot_xz := _find_clear_point(limit, placed, anchors)
		placed.append(spot_xz)
		# Ground-level POIs land ON the relief at their new spot; ones
		# authored on a platform (y above POI_PLATFORM_Y) keep their height,
		# because the platform they stand on is not moving with them and the
		# terrain under it is flat anyway (the Terrain pads it).
		var authored_y := poi.global_position.y
		var new_y := authored_y if authored_y > POI_PLATFORM_Y else _terrain_height(spot_xz)
		poi.global_position = Vector3(spot_xz.x, new_y, spot_xz.y)
	_placed_points = placed
	_placed_pois = movable
	_anchor_points = anchors


## Rebuilds _placed_points from the POIs still standing, so a spot freed
## by the irregular start stops reserving min_distance_between meters of
## arena around nothing.
func _refresh_placed_points() -> void:
	var points: Array[Vector2] = []
	for poi: Node3D in _placed_pois:
		if is_instance_valid(poi) and not poi.is_queued_for_deletion():
			points.append(Vector2(poi.global_position.x, poi.global_position.z))
	_placed_points = points


## A fresh clear spot for a run-time spawn, remembered for later ones.
func _claim_clear_point() -> Vector3:
	var spot := _find_clear_point(_arena_half_extent - bounds_margin, _placed_points, _anchor_points)
	_placed_points.append(spot)
	return Vector3(spot.x, _terrain_height(spot), spot.y)


## Terrain height at a flat point, or 0 without a terrain. Placement code
## in this file goes through here rather than through the raycast when it
## only needs the ground and not whatever prop is standing on it.
func _terrain_height(xz: Vector2) -> float:
	var terrain := Terrain.find(get_tree())
	return terrain.height_at(xz.x, xz.y) if terrain != null else 0.0


## --- run-start fixtures -----------------------------------------------------

## Portals in random pairs, each pair sharing a color.
func _spawn_portals() -> void:
	var count := portal_count - (portal_count % 2)
	# An emptied color list would make the pair index a modulo by zero — a
	# runtime error that aborts _ready and takes the roulette and the
	# irregular start down with the portals.
	var colors := portal_pair_colors if not portal_pair_colors.is_empty() \
			else DEFAULT_PORTAL_COLORS
	var portals: Array = []
	for i in count:
		var portal: Interactable = PortalShrineScript.new()
		portal.name = "Portal%d" % (i + 1)
		portal.set("pair_color", colors[(i / 2) % colors.size()])
		_stage_parent().add_child(portal)
		portal.global_position = _claim_clear_point()
		portals.append(portal)
	portals.shuffle()
	for i in range(0, portals.size() - 1, 2):
		portals[i].set("twin", portals[i + 1])
		portals[i + 1].set("twin", portals[i])
	if count > 0:
		print("Portals placed: %d (%d pairs)" % [count, count / 2])


func _spawn_roulettes() -> void:
	for i in roulette_count:
		var wheel := ROULETTE_SHRINE_SCENE.instantiate() as Node3D
		_stage_parent().add_child(wheel)
		wheel.global_position = _claim_clear_point()


## Rejection-samples a point inside +-limit respecting every distance rule;
## after the attempt cap it returns the best (farthest-from-everything)
## candidate seen, so a crowded setup degrades instead of hanging.
func _find_clear_point(limit: float, placed: Array[Vector2],
		anchors: Array[Vector2]) -> Vector2:
	var best := Vector2.ZERO
	var best_score := -INF
	for attempt in CLEAR_POINT_ATTEMPTS:
		var candidate := Vector2(randf_range(-limit, limit), randf_range(-limit, limit))
		# Irregular arena (iteration 44): never place a POI in a blocked cell.
		if not _walkable_xz(candidate):
			continue
		var clearance := candidate.length() - min_distance_from_spawn
		for other: Vector2 in placed:
			clearance = minf(clearance, candidate.distance_to(other) - min_distance_between)
		for anchor: Vector2 in anchors:
			clearance = minf(clearance,
					candidate.distance_to(anchor) - min_distance_from_keepouts)
		if clearance >= 0.0:
			return candidate
		if clearance > best_score:
			best_score = clearance
			best = candidate
	if best_score == -INF:
		# Not one candidate was even walkable, so `best` is still (0,0) —
		# the spawn point, the one cell the mask guarantees open and the
		# worst possible place to drop a portal or the roulette on top of
		# the player. Ask the mask for a real open cell instead.
		return _random_walkable_point()
	return best


## --- events -----------------------------------------------------------------

## This map's weight for an EVENT_LIBRARY row. Altar rows carry the
## iteration-47 cadence: heavier by the minute, and zero (i.e. rerolled
## into another event) while the field already holds its cap of unspent
## altars — which is what keeps "more altars" from becoming "an arena
## paved with altars nobody walks to".
func _event_weight(row: Dictionary) -> float:
	var weight := float(event_weight_overrides.get(row["id"], row["weight"]))
	# Exactly one spring on the field (iteration 53). Weighted to zero
	# rather than no-op'd inside _event_spring: a row that fires and does
	# nothing burns the whole event window, which is the same reason the
	# altar cap works this way.
	if String(row["id"]) == "spring" \
			and get_tree().get_node_count_in_group(&"springs") > 0:
		return 0.0
	# Two stalls at most (iteration 54), same mechanism: a third would just
	# be a third walk nobody takes before one of them sells.
	if String(row["id"]) == "vendor" \
			and get_tree().get_node_count_in_group(&"vendors") >= max_vendors:
		return 0.0
	if not bool(row.get("altar", false)) or weight <= 0.0:
		return weight
	if _unspent_altars() >= _altar_cap():
		return 0.0
	return weight * minf(1.0 + altar_weight_per_minute * _minutes(), altar_weight_max_scale)


func _fire_random_event() -> void:
	var total := 0.0
	for row: Dictionary in EVENT_LIBRARY:
		total += maxf(_event_weight(row), 0.0)
	if total <= 0.0:
		return
	var roll := randf() * total
	var chosen: StringName = &""
	for row: Dictionary in EVENT_LIBRARY:
		var weight := _event_weight(row)
		# Rows weighted out are skipped outright: subtracting zero used to
		# let a roll that landed exactly on a boundary pick a dead event.
		if weight <= 0.0:
			continue
		chosen = row["method"]
		roll -= weight
		if roll <= 0.0:
			break
	if chosen.is_empty():
		return
	call(chosen)


func _event_charge_altar() -> void:
	_event_altar(CHARGE_SHRINE_SCENE, "Se alza un altar de carga — párate en su anillo")


func _event_demonic_altar() -> void:
	_event_altar(CURSE_SHRINE_SCENE, "Un obelisco demoníaco sale del suelo a zarpazos...")


## Recurring altar (charge or demonic): far from a player, and it STAYS.
## Since iteration 47 an altar never times out, so its beacon has no
## deadline either — it burns until the altar is spent, which the
## TimedBeacon's own poi_worth_showing() check reports.
func _event_altar(scene: PackedScene, message: String) -> void:
	var altar := scene.instantiate() as Node3D
	_stage_parent().add_child(altar)
	altar.global_position = _event_point()
	var color := Color(1.0, 0.35, 0.3) if scene == CURSE_SHRINE_SCENE \
			else Color(0.45, 0.85, 1.0)
	_beacons.append(TimedBeacon.new(
			_spawn_beacon(altar.global_position, color), altar, INF))
	_announce(message)
	# One-line log (RunManager convention) for headless soaks.
	print("Altar placed: %s" % ("demonic" if scene == CURSE_SHRINE_SCENE else "charge"))


## The one spring. Like an altar since iteration 53: it stays until it is
## drunk, so its beacon has no deadline either (the TimedBeacon's own
## poi_worth_showing() check puts it out when the spring is spent).
func _event_spring() -> void:
	var spring := SPRING_SHRINE_SCENE.instantiate() as Node3D
	_stage_parent().add_child(spring)
	spring.global_position = _event_point()
	_beacons.append(TimedBeacon.new(
			_spawn_beacon(spring.global_position, Color(0.4, 0.8, 1.0)),
			spring, INF))
	_announce("Un manantial brota en algún lugar del campo...")


## A stall arrives. The KIND is rolled here and deliberately not named in
## the announce or the beacon: walking over to find out which one it is is
## the whole event, and a beacon that said "animals" would answer it from
## across the map.
func _event_vendor() -> void:
	var vendor := VENDOR_SCENE.instantiate() as Node3D
	var row: Dictionary = Vendor.VENDOR_LIBRARY[randi() % Vendor.VENDOR_LIBRARY.size()]
	# Set BEFORE the node enters the tree: Vendor._ready reads it to pick
	# its prompt, its colour and the figure behind the counter.
	vendor.set("kind", String(row.id))
	_stage_parent().add_child(vendor)
	vendor.global_position = _event_point()
	# Like an altar, the beacon burns until the stall is gone.
	_beacons.append(TimedBeacon.new(
			_spawn_beacon(vendor.global_position, row.get("color", Color.WHITE)),
			vendor, INF))
	_announce("¡Llega un vendedor!")
	print("Vendor arrived: %s" % String(row.id))


## The event altar: free, one use, and whatever it summons is a surprise.
func _event_event_altar() -> void:
	_spawn_event_altar(_event_point())
	_announce("Un cristal de tormenta se alza en el campo...")


func _spawn_event_altar(at: Vector3) -> Node3D:
	var altar := EVENT_ALTAR_SCENE.instantiate() as Node3D
	_stage_parent().add_child(altar)
	altar.global_position = at
	return altar


## A pet box, free and one-use. Rarer than a vendor because a companion is
## a bigger swing than a purchase and the player pays nothing for it.
func _event_pet_box() -> void:
	_spawn_pet_box(_event_point())
	_announce("Una caja con una huella aparece en el campo...")


func _spawn_pet_box(at: Vector3) -> Node3D:
	var box := PET_BOX_SCENE.instantiate() as Node3D
	_stage_parent().add_child(box)
	box.global_position = at
	return box


## Star sighting: the rarest thing on the map walks across it. Spawned
## through the spawner's own pickup door, so the stage parenting, the
## group and the "Power-up dropped:" line are written once.
func _event_star() -> void:
	var spawner := get_tree().get_first_node_in_group("enemy_spawner")
	if spawner == null or not spawner.has_method("spawn_powerup_pickup"):
		return
	var at := _event_point()
	if spawner.call("spawn_powerup_pickup", at + Vector3.UP * 0.6, "star") == null:
		return
	_beacons.append(TimedBeacon.new(
			_spawn_beacon(at, Color(1.0, 0.9, 0.35)), null, STAR_BEACON_TIME))
	_announce("Algo brillante cruza el campo...")


## A far point from a random alive player: inside the arena band, on a
## WALKABLE cell, and standing on whatever geometry is there. The
## irregular-arena mask can wall off up to ~38% of the plate, and an event
## announced inside a mask wall burns its whole window unreachable.
func _event_point() -> Vector3:
	var anchor := Coop.random_player(get_tree())
	var origin := anchor.global_position if anchor != null else Vector3.ZERO
	var limit := _arena_half_extent - bounds_margin
	var pos := Vector3.ZERO
	var found := false
	for attempt in EVENT_POINT_ATTEMPTS:
		var angle := randf() * TAU
		pos = origin + Vector3(cos(angle), 0.0, sin(angle)) \
				* randf_range(event_min_distance, event_max_distance)
		pos.x = clampf(pos.x, -limit, limit)
		pos.z = clampf(pos.z, -limit, limit)
		if _walkable(pos):
			found = true
			break
	if not found:
		# The whole ring around this player is walled in: fall back to the
		# run-start sampler, which is mask-aware by construction.
		pos = _claim_clear_point()
	pos.y = _ground_height(pos)
	return pos


func _event_supply_chest() -> void:
	var chest := CHEST_SCENE.instantiate() as Chest
	# Supply chests are never Common: floored to Rare and luck-tilted up.
	chest.min_rarity = "Rare"
	chest.luck_bonus = chest_luck_bonus
	_stage_parent().add_child(chest)
	chest.global_position = _event_point()
	_beacons.append(TimedBeacon.new(
			_spawn_beacon(chest.global_position, Color(1.0, 0.82, 0.3)),
			chest, chest_lifetime, true))
	_announce("Un cofre de suministros zumba en algún lugar del campo...")


func _event_elite_pack() -> void:
	var anchor := Coop.random_player(get_tree())
	if anchor == null:
		return
	# Resolved through the group (never by path) instead of call_group,
	# because the answer matters: the banner promises a bounty, so it only
	# goes out if the spawner actually had room under its live cap.
	var spawner := get_tree().get_first_node_in_group("enemy_spawner")
	if spawner == null or not spawner.has_method("spawn_pressure_burst"):
		return
	var spawned: int = spawner.call(
			"spawn_pressure_burst", anchor.global_position, elite_pack_size, true)
	if spawned <= 0:
		return
	_announce("¡Una jauría shiny te huele el rastro!")


func _event_essence_rift() -> void:
	var center := _event_point()
	for i in rift_gem_count:
		var gem := Pools.acquire_scene(XP_GEM_SCENE) as XpGem
		if gem == null:
			break
		gem.xp_value = rift_gem_value
		var angle := TAU * float(i) / float(rift_gem_count)
		gem.global_position = center + Vector3(cos(angle), 0.0, sin(angle)) \
				* randf_range(0.6, 2.6) + Vector3.UP * 0.6
	if not HealthOrb.at_soft_cap(get_tree()):
		var orb := Pools.acquire_scene(Pools.HEALTH_ORB_SCENE) as HealthOrb
		if orb != null:
			orb.global_position = center + Vector3.UP * 0.6
	# The gems' own lifetime is the pickup window; the beacon fades sooner
	# and has no POI to outlive.
	_beacons.append(TimedBeacon.new(
			_spawn_beacon(center, Color(0.35, 0.95, 0.6)), null, rift_beacon_lifetime))
	_announce("Se abre una grieta de esencia...")


## One pass over every live beacon: a beacon goes out when its POI is
## taken, spent or gone, or when its own window closes. Supply chests are
## the only owner that sinks with the light (missable on purpose — that
## urgency is what pulls players across the map).
func _tick_beacons(delta: float) -> void:
	for i in range(_beacons.size() - 1, -1, -1):
		var entry := _beacons[i]
		if not entry.poi_worth_showing():
			_free_beacon(entry.node)
			_beacons.remove_at(i)
			continue
		entry.time_left -= delta
		if entry.time_left > 0.0:
			continue
		_free_beacon(entry.node)
		if entry.sink_poi and entry.poi is Chest:
			_despawn_chest(entry.poi as Chest)
		_beacons.remove_at(i)


## Unclaimed supply chest sinks away. Guarded: a chest that was opened
## sinks and frees itself (iteration 47), so by the time a stale beacon
## entry gets here the box may already be gone.
func _despawn_chest(chest: Chest) -> void:
	if chest == null or not is_instance_valid(chest) or chest.is_queued_for_deletion():
		return
	# A missed chest must not credit the chests_opened quest counter.
	chest.meta_stat_id = ""
	chest.consume()
	var tween := create_tween()
	tween.tween_property(chest, "scale", Vector3.ONE * 0.05, 0.4) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(chest.queue_free)


## Tall unshaded light pillar visible across the arena, with a soft pulse
## so it reads as an invitation rather than a threat.
func _spawn_beacon(at: Vector3, color: Color) -> Node3D:
	var beacon := Node3D.new()
	_stage_parent().add_child(beacon)
	beacon.global_position = at
	var pillar := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.55
	mesh.bottom_radius = 0.25
	mesh.height = 22.0
	pillar.mesh = mesh
	pillar.position.y = 11.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(color.r, color.g, color.b, 0.35)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.6
	pillar.material_override = material
	beacon.add_child(pillar)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 2.4
	light.omni_range = 9.0
	light.position.y = 1.6
	beacon.add_child(light)
	var pulse := beacon.create_tween().set_loops()
	pulse.tween_property(pillar, "scale", Vector3(1.25, 1.0, 1.25), 0.8) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(pillar, "scale", Vector3.ONE, 0.8) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return beacon


## --- weather ----------------------------------------------------------------
## ONE channel for moons, rains and disasters (iteration 55). They are
## independent kinds but never overlap: `active_weather` holds at most one
## row, so "only one moon, rain or disaster at a time" is a property of the
## data structure rather than three timers that have to agree.
##
## In code this is WEATHER, never "event": EVENT_LIBRARY above is the
## POI/event-tick table and the two meanings would collide on every read.
## The player-facing word stays «evento» (the altar summons one).
##
## Row fields:
##   id/group:   identifier and one of moon | rain | disaster.
##   weight:     roll weight WITHIN its group.
##   duration:   seconds, before weather_duration_overrides and, for moons
##               and rains, RunState.sky_duration_multiplier. Disasters are
##               fixed: a pact that sells "longer moons" must not also sell
##               a longer meteor shower.
##   start/tick/stop: method names, called through call(). tick and stop
##               may be empty.
##   follow_up:  the row that starts the instant this one ends, with no
##               gap (blood_moon/eclipse -> full_moon, and the two rains ->
##               golden_rain: the reward for having survived the bad one).
##   follow_up_only: never rolled directly; only reachable as a follow_up.
const WEATHER_CATALOG: Array[Dictionary] = [
	{
		"id": "blood_moon", "group": "moon", "weight": 1.0, "duration": 45.0,
		"start": &"_weather_start_blood_moon", "tick": &"", "stop": &"",
		"follow_up": "full_moon",
	},
	{
		"id": "eclipse", "group": "moon", "weight": 1.0, "duration": 45.0,
		"start": &"_weather_start_eclipse", "tick": &"", "stop": &"",
		"follow_up": "full_moon",
	},
	{
		"id": "full_moon", "group": "moon", "weight": 1.0, "duration": 40.0,
		"start": &"_weather_start_full_moon", "tick": &"", "stop": &"",
		"follow_up_only": true,
	},
	{
		"id": "enemy_rain", "group": "rain", "weight": 1.0, "duration": 35.0,
		"start": &"_weather_start_enemy_rain", "tick": &"_weather_tick_enemy_rain",
		"stop": &"", "follow_up": "golden_rain",
	},
	{
		"id": "radioactive_rain", "group": "rain", "weight": 1.0, "duration": 40.0,
		"start": &"_weather_start_radioactive_rain",
		"tick": &"_weather_tick_radioactive_rain",
		"stop": &"_weather_stop_radioactive_rain", "follow_up": "golden_rain",
	},
	{
		"id": "golden_rain", "group": "rain", "weight": 1.0, "duration": 40.0,
		"start": &"_weather_start_golden_rain", "tick": &"",
		"stop": &"_weather_stop_golden_rain", "follow_up_only": true,
	},
	{
		# One wave, not a window: its tick spends three seconds pouring the
		# wave in and then ends the disaster itself. It can roll again later.
		"id": "enemy_tsunami", "group": "disaster", "weight": 1.0, "duration": 3.0,
		"start": &"_weather_start_tsunami", "tick": &"_weather_tick_tsunami",
		"stop": &"",
	},
	{
		"id": "earthquake", "group": "disaster", "weight": 1.0, "duration": 25.0,
		"start": &"_weather_start_earthquake", "tick": &"_weather_tick_earthquake",
		"stop": &"_weather_stop_earthquake",
	},
	{
		"id": "meteor_shower", "group": "disaster", "weight": 1.0, "duration": 30.0,
		"start": &"_weather_start_meteors", "tick": &"_weather_tick_meteors",
		"stop": &"",
	},
]

## Groups whose length a demonic pact can stretch (RunState.sky_duration_multiplier).
const STRETCHABLE_GROUPS: Array[String] = ["moon", "rain"]
## Weather ids the event altar refuses to summon: the two rewards. An altar
## that could hand out a golden rain outright would make the rains that earn
## it pointless.
const ALTAR_EXCLUDED: Array[String] = ["golden_rain", "full_moon"]
## Cap on live acid pools and the spacing between them. A cap that is
## RAISED to fit more pools is not a fix; spawns past it are skipped.
const MAX_LIVE_ACID_POOLS: int = 24
const ACID_POOL_SPACING: float = 3.0
## Cap on live meteor telegraphs, for the same reason (the pool of discs is
## 32 and the rest of the game uses it too).
const MAX_LIVE_TELEGRAPHS: int = 16
## Bodies the tsunami pours in per physics frame. Forty in one frame is a
## visible hitch; spread over the row's three seconds nobody notices.
const TSUNAMI_PER_FRAME: int = 6
## Half-width of the arc the wave comes from, in radians (~60 degrees wide).
const TSUNAMI_ARC_SPREAD: float = 0.52
## Acid damage per second to a raider standing in a pool.
const ACID_DAMAGE_PER_SECOND: float = 4.0


static func weather_row(id: String) -> Dictionary:
	for row: Dictionary in WEATHER_CATALOG:
		if String(row.id) == id:
			return row
	return {}


## Seconds this row runs for, with the arena override and — for moons and
## rains only — the pact multiplier.
func _weather_duration(row: Dictionary) -> float:
	var seconds := float(weather_duration_overrides.get(String(row.id), row.duration))
	if STRETCHABLE_GROUPS.has(String(row.group)):
		seconds *= RunState.sky_duration_multiplier
	return seconds


## The event-tick roll: rarest group first, so a disaster is not crowded
## out by the commoner rains and moons.
func _maybe_weather() -> void:
	if not active_weather.is_empty() or _sky_gap_left > 0.0:
		return
	# Short-circuited so a group whose chance is ZERO draws NO random
	# number. Not a micro-optimisation: the game RNG is one shared stream,
	# and a die rolled for a disabled group shifts every later draw in the
	# run — which is how disabling a group "changed" the arena layout.
	var disaster_odds := disaster_chance + RunState.disaster_chance_bonus
	if disaster_odds > 0.0 and randf() < disaster_odds:
		_start_weather(_roll_group("disaster"))
		return
	var rain_odds := rain_chance + RunState.event_chance_bonus
	if rain_odds > 0.0 and randf() < rain_odds:
		_start_weather(_roll_group("rain"))
		return
	# Demonic pacts can sell sky-event odds outright (iteration 47), on top
	# of the per-use tilt every demonic completion already adds.
	var chance := sky_event_chance + RunState.event_chance_bonus \
			+ sky_event_chance_per_demonic * float(RunState.demonic_uses)
	if randf() >= chance:
		return
	_start_weather(_roll_group("moon"))


## A weighted id from one group, skipping the follow-up-only rows.
func _roll_group(group: String) -> String:
	var total := 0.0
	for row: Dictionary in WEATHER_CATALOG:
		if String(row.group) == group and not bool(row.get("follow_up_only", false)):
			total += float(row.weight)
	if total <= 0.0:
		return ""
	var roll := randf() * total
	for row: Dictionary in WEATHER_CATALOG:
		if String(row.group) != group or bool(row.get("follow_up_only", false)):
			continue
		roll -= float(row.weight)
		if roll <= 0.0:
			return String(row.id)
	return ""


## PUBLIC group hook (the probe, BONK_WEATHER_NOW, the event altar): FORCES
## a row. It stops whatever is running and starts even inside the gap —
## exclusivity is a rule, the gap is only a cadence, and a forced summon
## that silently did nothing would make the altar feel broken and would
## break verificar.sh's CIELO_TRAS_AVANCE gate.
func start_sky_event(kind: String) -> void:
	_start_weather(kind, true)


## The event altar's roll: any row except the two rewards.
func random_altar_weather() -> String:
	var total := 0.0
	for row: Dictionary in WEATHER_CATALOG:
		if not ALTAR_EXCLUDED.has(String(row.id)):
			total += float(row.weight)
	if total <= 0.0:
		return ""
	var roll := randf() * total
	for row: Dictionary in WEATHER_CATALOG:
		if ALTAR_EXCLUDED.has(String(row.id)):
			continue
		roll -= float(row.weight)
		if roll <= 0.0:
			return String(row.id)
	return ""


func _start_weather(id: String, forced: bool = false) -> void:
	if id.is_empty():
		return
	var row := weather_row(id)
	if row.is_empty():
		push_warning("WorldDirector: unknown weather '%s'" % id)
		return
	if not active_weather.is_empty():
		if not forced:
			return
		# Forced: the running row is stopped properly, never just dropped —
		# its stop() is what releases the tint, the points source and the
		# HUD offset.
		_stop_weather(false)
	_cache_lights()
	_weather_state = {}
	var seconds := _weather_duration(row)
	active_weather = {"id": id, "group": String(row.group), "time_left": seconds}
	call(row.start)
	if String(row.group) == "disaster":
		# Extra line so a soak can grep disasters apart from the weather
		# they share a channel with.
		print("Disaster: %s" % id)
	print("Weather started: %s" % id)


func _tick_weather(delta: float) -> void:
	_sky_gap_left = maxf(_sky_gap_left - delta, 0.0)
	if active_weather.is_empty():
		return
	var row := weather_row(String(active_weather.id))
	var tick: StringName = row.get("tick", &"")
	if not tick.is_empty():
		call(tick, delta)
	# The tick can end the weather itself (the tsunami does once its wave
	# is in), and then there is nothing left to count down.
	if active_weather.is_empty():
		return
	active_weather.time_left = float(active_weather.time_left) - delta
	if float(active_weather.time_left) > 0.0:
		return
	_stop_weather(true)


## Ends the live row. `chain` is false for teardown (stage swap, run exit):
## the follow-up must not start into an arena that is going away.
func _stop_weather(chain: bool) -> void:
	if active_weather.is_empty():
		return
	var id := String(active_weather.id)
	var row := weather_row(id)
	var stop: StringName = row.get("stop", &"")
	active_weather = {}
	if not stop.is_empty():
		call(stop)
	_weather_state = {}
	print("Weather ended: %s" % id)
	if not chain:
		return
	var follow_up := String(row.get("follow_up", ""))
	if not follow_up.is_empty():
		# Straight into it, no restore first: restoring spawned a 2 s tween
		# racing the follow-up's 1.5 s one over the same properties, and the
		# longer restore won.
		_start_weather(follow_up)
		return
	_restore_sky()
	_sky_gap_left = sky_event_min_gap


## --- moons ------------------------------------------------------------------

func _weather_start_blood_moon() -> void:
	var seconds := float(active_weather.time_left)
	get_tree().call_group("enemy_spawner", "set_sky_event", "blood_moon", seconds)
	_tint_sky(Color(1.0, 0.25, 0.2), 0.9, Color(0.5, 0.1, 0.1))
	_announce("LUNA DE SANGRE — ¡la horda enloquece!")
	_print_sky_event("blood_moon", seconds)


func _weather_start_eclipse() -> void:
	var seconds := float(active_weather.time_left)
	get_tree().call_group("enemy_spawner", "set_sky_event", "eclipse", seconds)
	_tint_sky(Color(0.35, 0.3, 0.5), 0.35, Color(0.12, 0.1, 0.2))
	_announce("ECLIPSE — las sombras entran por todos lados")
	_print_sky_event("eclipse", seconds)


func _weather_start_full_moon() -> void:
	# The pact sells "the moons last longer", so the good one grows too — a
	# cost that only stretched the bad half would read as a straight
	# penalty rather than a bargain.
	var seconds := float(active_weather.time_left)
	for node: Node in get_tree().get_nodes_in_group("player"):
		var stats := PlayerStats.find_in(node)
		if stats != null:
			stats.add_timed_boon("xp_gain", full_moon_xp_bonus, seconds)
			stats.add_timed_boon("luck", full_moon_luck_bonus, seconds)
	_tint_sky(Color(0.85, 0.9, 1.0), 1.3, Color(0.6, 0.65, 0.9))
	_announce("LUNA LLENA — la fortuna y la sabiduría te sonríen")
	_print_sky_event("full_moon", seconds)


## The moons keep their original log line VERBATIM: tools/verificar.sh's
## CIELO_TRAS_AVANCE gate counts it after every stage change to prove the
## director re-cached the new map's lights. Rains and disasters do not
## print it — they tint nothing that gate is about.
func _print_sky_event(kind: String, seconds: float) -> void:
	print("Sky event: %s for %.0fs" % [kind, seconds])


## --- rains ------------------------------------------------------------------

func _weather_start_enemy_rain() -> void:
	_weather_state["drop_left"] = 0.0
	_tint_sky(Color(0.6, 0.8, 1.0), 0.8, Color(0.35, 0.45, 0.6))
	_announce("LLUVIA DE ENEMIGOS — ¡caen del cielo!")


## Enemies "fall" as a telegraph plus a downward streak, and then simply
## appear on the ground. They are NOT dropped from a height: a body falling
## in is a body with upward-then-downward velocity off the floor, which is
## exactly what the harness's airborne detector exists to catch — and that
## detector is deliberately narrow and must not be widened for scenery.
func _weather_tick_enemy_rain(delta: float) -> void:
	_weather_state["drop_left"] = float(_weather_state.get("drop_left", 0.0)) - delta
	if float(_weather_state["drop_left"]) > 0.0:
		return
	_weather_state["drop_left"] = enemy_rain_interval
	var anchor_body := Coop.random_player(get_tree())
	if anchor_body == null:
		return
	var wanted := randi_range(enemy_rain_min_drops, enemy_rain_max_drops)
	var points: Array[Vector3] = []
	for i in wanted:
		var point := _rain_point(anchor_body.global_position,
				enemy_rain_min_distance, enemy_rain_max_distance)
		if point == Vector3.INF:
			continue
		points.append(point)
		Telegraph.spawn_disc(self, point, 1.4, 1.0, Color(0.6, 0.85, 1.0))
		Juice.burst(point + Vector3.UP * 3.0, Color(0.6, 0.85, 1.0), 6)
	if not points.is_empty():
		# NOT the horde budget: a rain is ambient weather that runs for 35
		# seconds, and the extra 40 bodies of horde headroom kept the arena
		# pinned at its cap for the whole window — a wall the party cannot
		# push through, which stopped a stage soak from ever reaching its
		# exit portal. The tsunami below is the one that IS a wave.
		get_tree().call_group("enemy_spawner", "spawn_at_points", points, false)


func _weather_start_radioactive_rain() -> void:
	_weather_state["pool_left"] = 0.0
	_tint_sky(Color(0.5, 1.0, 0.4), 0.85, Color(0.2, 0.4, 0.15))
	_announce("LLUVIA RADIACTIVA — el suelo se vuelve ácido")


func _weather_tick_radioactive_rain(delta: float) -> void:
	_weather_state["pool_left"] = float(_weather_state.get("pool_left", 0.0)) - delta
	if float(_weather_state["pool_left"]) > 0.0:
		return
	_weather_state["pool_left"] = acid_pool_interval
	var anchor_body := Coop.random_player(get_tree())
	if anchor_body == null:
		return
	var point := _rain_point(anchor_body.global_position, 2.0, acid_pool_spawn_range)
	if point != Vector3.INF:
		spawn_acid_pool(point)


func _weather_stop_radioactive_rain() -> void:
	# The pools outlive the rain by design (they are already on the ground
	# and lethal); each one expires on its own clock, and the stage swap
	# reclaims any that are still live through Pools.release_all_live.
	pass


## PUBLIC (EnemyBase calls it on death while the radioactive rain runs):
## one acid puddle, subject to the live cap and the spacing rule. Skipped
## silently past either — a warning here would fail a soak for working as
## designed, and raising the cap to fit more is not a fix.
func spawn_acid_pool(at: Vector3) -> void:
	if not is_weather_active("radioactive_rain"):
		return
	var live := get_tree().get_nodes_in_group(&"acid_pools")
	if live.size() >= MAX_LIVE_ACID_POOLS:
		return
	var spacing_sq := ACID_POOL_SPACING * ACID_POOL_SPACING
	for node: Node in live:
		var pool := node as Node3D
		if pool != null and pool.global_position.distance_squared_to(at) < spacing_sq:
			return
	var fresh := Pools.acquire_scene(Pools.ACID_POOL_SCENE) as AcidPool
	if fresh == null:
		return
	fresh.play(at, acid_pool_radius, acid_pool_lifetime, ACID_DAMAGE_PER_SECOND)


## True while `id` is the live weather. THE public read for anything that
## has to behave differently under one (EnemyBase's acid drop, the HUD).
func is_weather_active(id: String) -> bool:
	return not active_weather.is_empty() and String(active_weather.id) == id


func _weather_start_golden_rain() -> void:
	_tint_sky(Color(1.0, 0.85, 0.4), 1.2, Color(0.6, 0.5, 0.2))
	# BOTH groups: a downed raider still earns the points their teammates
	# bank on their behalf, and the source has to come off them too.
	for body: Node3D in _all_raiders():
		if body.has_method("set_points_source"):
			body.call("set_points_source", "golden_rain", golden_points_multiplier)
	RunState.price_discount = golden_price_discount
	_announce("LLUVIA DORADA — todo brilla y todo vale la mitad")


func _weather_stop_golden_rain() -> void:
	for body: Node3D in _all_raiders():
		if body.has_method("clear_points_source"):
			body.call("clear_points_source", "golden_rain")
	RunState.price_discount = 1.0


## Every raider, standing or downed. Party-wide effects have to reach both
## groups: a downed body leaves "player" and joins "downed_players".
func _all_raiders() -> Array[Node3D]:
	var bodies: Array[Node3D] = []
	for group: String in ["player", "downed_players"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body != null and is_instance_valid(body):
				bodies.append(body)
	return bodies


## A walkable, grounded point in a ring around `origin`, or Vector3.INF
## when the mask offers none. Rain and meteors both land through here, so
## nothing weather drops can end up inside the arena's rocks.
func _rain_point(origin: Vector3, min_distance: float, max_distance: float) -> Vector3:
	for attempt in EVENT_POINT_ATTEMPTS:
		var angle := randf() * TAU
		var pos := origin + Vector3(cos(angle), 0.0, sin(angle)) \
				* randf_range(min_distance, max_distance)
		var limit := _arena_half_extent - bounds_margin
		pos.x = clampf(pos.x, -limit, limit)
		pos.z = clampf(pos.z, -limit, limit)
		if _walkable(pos):
			pos.y = _ground_height(pos)
			return pos
	return Vector3.INF


## --- disasters --------------------------------------------------------------

func _weather_start_tsunami() -> void:
	var anchor_body := Coop.random_player(get_tree())
	var origin := anchor_body.global_position if anchor_body != null else Vector3.ZERO
	var angle := randf() * TAU
	_weather_state["angle"] = angle
	_weather_state["origin"] = origin
	var wanted := tsunami_base + tsunami_per_minute * int(_minutes())
	_weather_state["left"] = wanted
	_announce("¡TSUNAMI DE ENEMIGOS! %s" % _compass_word(angle))


## Poured in over the row's three seconds, in per-frame chunks: forty-plus
## bodies made in one frame is a visible hitch, and the horde cap inside
## spawn_at_points bounds the total anyway.
func _weather_tick_tsunami(_delta: float) -> void:
	var left := int(_weather_state.get("left", 0))
	if left <= 0:
		return
	var chunk := mini(left, TSUNAMI_PER_FRAME)
	var origin: Vector3 = _weather_state.get("origin", Vector3.ZERO)
	var angle := float(_weather_state.get("angle", 0.0))
	var points: Array[Vector3] = []
	for i in chunk:
		# A 60 degree arc on ONE side: a tsunami is a wall coming from
		# somewhere, not a ring closing in (that is what a horde is).
		var spread := angle + randf_range(-TSUNAMI_ARC_SPREAD, TSUNAMI_ARC_SPREAD)
		var pos := origin + Vector3(cos(spread), 0.0, sin(spread)) \
				* randf_range(tsunami_arc_min, tsunami_arc_max)
		var limit := _arena_half_extent - bounds_margin
		pos.x = clampf(pos.x, -limit, limit)
		pos.z = clampf(pos.z, -limit, limit)
		if _walkable(pos):
			points.append(pos)
	if not points.is_empty():
		get_tree().call_group("enemy_spawner", "spawn_at_points", points, true)
	_weather_state["left"] = left - chunk


func _weather_start_earthquake() -> void:
	_weather_state["shake_left"] = 0.0
	_weather_state["dust_left"] = 0.0
	_weather_state["hud_time"] = 0.0
	_announce("¡TERREMOTO! El suelo no se queda quieto")


func _weather_tick_earthquake(delta: float) -> void:
	_weather_state["shake_left"] = float(_weather_state.get("shake_left", 0.0)) - delta
	if float(_weather_state["shake_left"]) <= 0.0:
		_weather_state["shake_left"] = earthquake_shake_interval
		Juice.shake(earthquake_shake_strength)
	_weather_state["dust_left"] = float(_weather_state.get("dust_left", 0.0)) - delta
	if float(_weather_state["dust_left"]) <= 0.0:
		_weather_state["dust_left"] = earthquake_dust_interval
		for body: Node3D in _all_raiders():
			Juice.burst(body.global_position, Color(0.6, 0.55, 0.45), 8)
	# The HUD is a CanvasLayer, so ONE offset moves every element it owns —
	# bars, timer, loadout strips and the per-view minimaps — which is what
	# "the sprites move around" means. The Tab map is a different layer and
	# deliberately stays still: a map that shook would be unreadable.
	var hud_time := float(_weather_state.get("hud_time", 0.0)) + delta
	_weather_state["hud_time"] = hud_time
	var phase := hud_time * earthquake_hud_hz * TAU
	get_tree().call_group("hud", "set_quake_offset", Vector2(
			sin(phase) * earthquake_hud_amplitude,
			cos(phase * 1.3) * earthquake_hud_amplitude))


func _weather_stop_earthquake() -> void:
	get_tree().call_group("hud", "set_quake_offset", Vector2.ZERO)


func _weather_start_meteors() -> void:
	_weather_state["meteor_left"] = 0.0
	_weather_state["pending"] = []
	_tint_sky(Color(1.0, 0.6, 0.35), 0.95, Color(0.4, 0.25, 0.15))
	_announce("¡LLUVIA DE METEORITOS! Sal de los círculos")


func _weather_tick_meteors(delta: float) -> void:
	var pending: Array = _weather_state.get("pending", [])
	for i in range(pending.size() - 1, -1, -1):
		var strike: Dictionary = pending[i]
		strike["left"] = float(strike["left"]) - delta
		if float(strike["left"]) > 0.0:
			pending[i] = strike
			continue
		pending.remove_at(i)
		_meteor_impact(strike["at"])
	_weather_state["pending"] = pending
	_weather_state["meteor_left"] = float(_weather_state.get("meteor_left", 0.0)) - delta
	if float(_weather_state["meteor_left"]) > 0.0:
		return
	_weather_state["meteor_left"] = meteor_interval
	if pending.size() >= MAX_LIVE_TELEGRAPHS:
		return
	var anchor_body := Coop.random_player(get_tree())
	if anchor_body == null:
		return
	var at := _rain_point(anchor_body.global_position, 3.0, meteor_range)
	if at == Vector3.INF:
		return
	Telegraph.spawn_disc(self, at, meteor_radius, meteor_telegraph,
			Color(1.0, 0.55, 0.2))
	pending.append({"at": at, "left": meteor_telegraph})
	_weather_state["pending"] = pending


## One meteor lands. Enemies take the brunt: a disaster that only hurt the
## party would be a pure tax, and one that only hurt the horde would be a
## gift — this is both, which is what makes standing still the mistake.
func _meteor_impact(at: Vector3) -> void:
	Juice.burst(at + Vector3.UP * 0.5, Color(1.0, 0.6, 0.25), 26)
	Juice.shake(0.35)
	Telegraph.spawn_disc(self, at, meteor_radius * 0.8, 0.5, Color(0.35, 0.2, 0.15))
	var damage := meteor_damage * (1.0 + _minutes() * 0.05)
	var radius_sq := meteor_radius * meteor_radius
	for body: Node3D in _all_raiders():
		if _flat_distance_sq(body.global_position, at) <= radius_sq:
			var health := Health.find_in(body)
			if health != null and not health.is_dead:
				health.take_damage(damage)
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node3D
		if enemy == null or not enemy.is_inside_tree():
			continue
		if _flat_distance_sq(enemy.global_position, at) > radius_sq:
			continue
		var enemy_health := Health.find_in(enemy)
		if enemy_health != null and not enemy_health.is_dead:
			enemy_health.take_damage(damage * meteor_enemy_scale)


static func _flat_distance_sq(a: Vector3, b: Vector3) -> float:
	var span := a - b
	span.y = 0.0
	return span.length_squared()


## Which way the tsunami comes from, for the announce. Four words is
## enough: the player needs a direction to run, not a bearing.
static func _compass_word(angle: float) -> String:
	var turns := fposmod(angle / TAU, 1.0)
	if turns < 0.125 or turns >= 0.875:
		return "desde el este"
	if turns < 0.375:
		return "desde el sur"
	if turns < 0.625:
		return "desde el oeste"
	return "desde el norte"


func _cache_lights() -> void:
	if _sun != null:
		return
	# The ARENA, not current_scene: current_scene is the persistent run
	# root now, and its lights are whatever arena happens to be under it.
	var scene := _stage_parent()
	if scene == null or scene == self:
		return
	for node: Node in scene.find_children("*", "DirectionalLight3D", true, false):
		_sun = node as DirectionalLight3D
		_sun_color = _sun.light_color
		_sun_energy = _sun.light_energy
		break
	for node: Node in scene.find_children("*", "WorldEnvironment", true, false):
		var world_environment := node as WorldEnvironment
		if world_environment == null or world_environment.environment == null:
			break
		# The arenas' Environment is a plain sub_resource: every instance of
		# the PackedScene shares the SAME resource for as long as it stays
		# cached, so tinting it bled into the next run — and Retry then
		# re-cached the blood-red ambient as the "original" color. Work on
		# a copy that belongs to this arena instance.
		_environment = world_environment.environment.duplicate()
		world_environment.environment = _environment
		_ambient_color = _environment.ambient_light_color
		_ambient_energy = _environment.ambient_light_energy
		break


func _tint_sky(sun_color: Color, sun_energy: float, ambient: Color) -> void:
	_kill_sky_tween()
	_sky_tween = create_tween().set_parallel()
	if _sun != null:
		_sky_tween.tween_property(_sun, "light_color", sun_color, 1.5)
		_sky_tween.tween_property(_sun, "light_energy", _sun_energy * sun_energy, 1.5)
	if _environment != null:
		_sky_tween.tween_property(_environment, "ambient_light_color", ambient, 1.5)


func _restore_sky() -> void:
	_kill_sky_tween()
	_sky_tween = create_tween().set_parallel()
	if _sun != null:
		_sky_tween.tween_property(_sun, "light_color", _sun_color, 2.0)
		_sky_tween.tween_property(_sun, "light_energy", _sun_energy, 2.0)
	if _environment != null:
		_sky_tween.tween_property(_environment, "ambient_light_color", _ambient_color, 2.0)


func _kill_sky_tween() -> void:
	if _sky_tween != null and _sky_tween.is_valid():
		_sky_tween.kill()
	_sky_tween = null


func _free_beacon(beacon: Node3D) -> void:
	if beacon != null and is_instance_valid(beacon):
		beacon.queue_free()


func _announce(message: String) -> void:
	get_tree().call_group("boss_ui", "announce", message)
