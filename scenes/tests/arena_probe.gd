extends Node
## Headless soak harness (iteration 38): boots an arena as a CHILD of an
## always-processing root, prints a status line every 2 s of run time and
## auto-picks the first upgrade card whenever the card UI opens (a soak has
## nobody at the mouse). Run with:
##   godot --headless --fixed-fps 60 --quit-after 36000 res://scenes/tests/ArenaProbe.tscn
##
## Env switches:
##   BONK_ARENA=res://...   arena scene (default: Hollow Woods)
##   BONK_CHARACTER=<id>    raider from CharacterCatalog
##   BONK_GODMODE=1         unkillable raider, so late systems get exercised
##   BONK_WALK=0            hold the raider still (default: it walks, see below)
##   BONK_SEED=<int>        deterministic walk, for reproducing a soak
##   BONK_ELITE_BOOST=1     every spawn rolls shiny (crowding stress test)
##   BONK_STAGE_FAST=1      stages clear at 60 s with no boss, so one soak
##                          crosses a stage change (RunManager reads it)
##   BONK_GAME_SEED=<int>   seeds the GAME's RNG (RunState.reset), which is
##                          what makes a whole soak reproducible
##   BONK_POWERUP_NOW=<id>  grants that power-up to slot 0 at 20 s and
##                          RE-GRANTS it on every expiry, so a 120 s soak
##                          spends its whole clock inside the effect
##   BONK_STAR_NOW=1        drops a STATIONARY star at the raider's feet
##                          at 30 s (the roaming one is hard to intercept
##                          on purpose, and a soak has to be able to)
##   BONK_POWERUP_BOOST=1   multiplies the kill drop chance (read by
##                          EnemySpawner), so drops show up inside a soak
##   BONK_POI_NOW=a,b,c     spawns those POIs 8 m from the raider at 20 s
##                          (vendor_items, vendor_powerups, vendor_animals,
##                          pet_box) — the director's own cadence would
##                          take many minutes to offer all four
##   BONK_POINTS=<n>        grants slot 0 that many run points at start, so
##                          a vendor soak can actually afford the shelf
##   BONK_WEATHER_NOW=<id>  forces that weather at 30 s (the director's own
##                          cadence needs many minutes to offer all nine)
##
## The raider WALKS AND INTERACTS by default (iteration 45). A parked raider
## silently skips every movement-gated system — Slime Trail only drops
## puddles while moving, altars only charge while a player stands in the
## ring, chests and portals need someone to reach them AND press interact —
## so a still soak reports "no errors" about code it never ran. The walk
## tours available Interactables first (lingering on arrival so Charge
## altars can finish their channel and the interact action lands) and falls
## back to random walkable points when none are left.
##
## Three checks run unconditionally in every soak and warn (which fails
## tools/verificar.sh) when they trip: the airborne detector, the one-shot
## arena MASK SWEEP and the continuous BLOCKED-CELL WATCH. None of them has
## an env switch — a guard that can be turned off is a guard nobody sees
## fail. See the two blocks of constants below.

const DEFAULT_ARENA := "res://scenes/world/HollowWoods.tscn"
## The one scene a run boots into since iteration 49. BONK_ARENA no longer
## names the scene to instance — it names the BIOME to soak, which becomes
## GameConfig.start_map_id and therefore stage 1.
const RUN_SCENE := "res://scenes/world/Run.tscn"
## Seconds the tour lingers after the exit portal opens before taking it,
## under BONK_STAGE_FAST. Long enough for at least one full minute of the
## pseudo-infinite ramp to be logged, which is what proves it runs at all.
const PSEUDO_INFINITE_DWELL: float = 70.0
## Delay after a stage change before the probe fires a sky event at the
## new arena. The lights are re-cached during the swap; a blood moon that
## tints nothing is how a stale Sun reference shows up in a log.
const STAGE_SKY_DELAY: float = 5.0

## Radius of the square the walk picks waypoints in, when the arena does not
## publish its own bounds through the "arena_bounds" group.
const FALLBACK_HALF_EXTENT: float = 60.0
## A leg ends when the raider gets this close to its waypoint...
## Arrival radius, measured on XZ ONLY (iteration 51): with terrain, a
## waypoint on a hollow floor and a raider on its rim are metres apart in
## Y while standing on the same spot, and a 3D check never converged.
const WAYPOINT_REACHED: float = 2.5
## ...or after this long, so geometry it cannot walk around never wedges it.
## Generous: a 160x160 arena with mask walls needs detours.
## A 240x240 arena is 1.5x the old crossing and the relief adds detours:
## 16 s timed out most legs, which turned the tour into a random walk.
const LEG_TIMEOUT: float = 40.0
## Seconds before the tour will head back to an interactable it already
## tried. Keeps a spent-but-still-available altar from pinning the walk.
const REVISIT_COOLDOWN: float = 45.0
## How far the tour will detour for a power-up on the ground. Short: a
## pickup is a bonus on the way, not a destination worth crossing a
## 240 m arena for.
const PICKUP_DETOUR: float = 20.0
## Progress is sampled this often; moving less than STALL_DISTANCE in that
## window counts as stuck and earns a jump.
const STALL_WINDOW: float = 1.0
const STALL_DISTANCE: float = 1.5
## On reaching an interactable the raider stands still this long. It has to
## exceed ChargeShrine.channel_time (8 s): "arrived" is the game's own
## player_in_range, which since the ring got three times wider triggers at
## the ring EDGE, so a linger shorter than the channel walks away from
## every altar at 75% and the soak never exercises a completion.
const LINGER_TIME: float = 10.0
## While lingering, fire the interact action this often (chests answer on
## the first press; a spent one just ignores the rest).
const INTERACT_INTERVAL: float = 0.75
## A paused tree with no upgrade card UI open for this long means some
## blocking UI wedged the soak — worth a log line, since a wedged run looks
## exactly like a clean one in the frame counter.
const PAUSE_WEDGE_WARN: float = 20.0

var _frames: int = 0
var _walking: bool = true
var _waypoint: Vector3 = Vector3.ZERO
var _leg_time_left: float = 0.0
var _linger_left: float = 0.0
var _interact_timer: float = 0.0
var _paused_for: float = 0.0
var _wedge_reported: bool = false
## BONK_PROBE_DEBUG=1 narrates the tour (waypoints, arrivals, interact
## presses) so a soak that never reaches an interactable is diagnosable.
var _debug: bool = false
## Interactable instance id -> run_time when the tour last headed for it.
var _visited: Dictionary[int, float] = {}
## The interactable this leg is walking to (null when just roaming).
var _target: Interactable = null
## Leg accounting, summarised at the end of every soak (Probe legs:): a
## tour whose legs all time out looks identical to a healthy one in the
## frame counter, and that is exactly what a too-small arrival radius or
## an unreachable waypoint produces.
var _legs_reached: int = 0
var _legs_timed_out: int = 0
var _stall_check: float = 0.0
var _last_position: Vector3 = Vector3.ZERO
var _rng := RandomNumberGenerator.new()

## --- airborne detector (iteration 48) ---------------------------------------
## Enemies were reported "flying" when the horde crowds. The rule is fixed
## and deliberately narrow so it cannot be tuned into silence: a body counts
## as airborne once it has been RISING (velocity.y above AIRBORNE_RISE_SPEED)
## while NOT on the floor, continuously, for AIRBORNE_TIME seconds.
## Exactly two exclusions, both of them bodies that rise on purpose:
## an enemy whose own climb state is on, and a Duneburrower mid-eruption.
## Every new occurrence pushes ONE warning (once per body) — and every
## warning fails tools/verificar.sh, which is the point.
const AIRBORNE_RISE_SPEED: float = 0.5
const AIRBORNE_TIME: float = 0.5
## Duneburrower.State.ERUPTING, by value: the probe cannot name the enum
## without hard-coupling to that script, and the order is stable
## (SURFACED, BURROWED, ERUPTING).
const BURROWER_ERUPTING: int = 2
## instance id -> seconds it has been rising off the floor.
var _rising_for: Dictionary[int, float] = {}
## instance ids already reported, so one body warns once.
var _airborne_seen: Dictionary[int, bool] = {}
## Cumulative count of DISTINCT airborne bodies; printed on every frame line.
var _airborne_total: int = 0

## --- arena mask guards (iteration 48) ---------------------------------------
## The irregular-arena mask used to be enforced by an invisible 7 m box per
## blocked cell. Now the only thing standing there is the rocks you can see,
## so two checks run in EVERY soak — no env switch, because both of them
## exist precisely to be able to fail:
##  (a) MASK SWEEP, once: pushes a player-sized capsule along every boundary
##      a blocked cell shares with a walkable one and reports every sample
##      that touches nothing. A gap the capsule fits through is a hole in
##      the arena.
##  (b) BLOCKED-CELL WATCH, continuous: the lead raider standing on the
##      arena FLOOR inside a blocked cell means it got through one.
## Sampling step along a boundary edge. Well under the capsule diameter, so
## a gap cannot hide between two samples.
const SWEEP_STEP: float = 0.2
## The player capsule, verbatim from Player.tscn (radius/height and the
## 0.9 m the CollisionShape3D sits above the body origin, i.e. above the
## arena floor plate).
const SWEEP_CAPSULE_RADIUS: float = 0.4
const SWEEP_CAPSULE_HEIGHT: float = 1.8
## Capsule centre ABOVE THE GROUND at each sample (iteration 51: it used
## to be an absolute height, which only worked on a flat floor).
const SWEEP_CAPSULE_CENTER_Y: float = 0.9
## World geometry (floor, perimeter, props) is layer 1; enemies are layer 2
## and never count as "this boundary is sealed".
const WORLD_COLLISION_LAYER: int = 1
## The sweep runs on this physics frame: late enough that every prop the
## scatter added in _ready has had its transform flushed to the physics
## server, early enough that the tour has not moved anywhere yet.
const SWEEP_FRAME: int = 10
## Openings named one by one before the log falls back to the summary line.
const SWEEP_REPORT_LIMIT: int = 6
## A raider higher than this above the floor plate (y = 0) is standing on a
## rock, a platform or a mesa — above a blocked cell, not inside it.
## How far ABOVE THE TERRAIN a raider can be and still count as standing
## on the ground rather than on a rock or a platform (iteration 51: this
## used to be an absolute Y, which read every hill as "on a prop").
const FLOOR_STAND_MAX_Y: float = 0.6
## Continuous seconds inside a blocked cell before it counts as "got in".
## Long enough that a jump arc or a knockback cannot trip it.
const BLOCKED_CELL_GRACE: float = 2.0

var _swept: bool = false
## Physics frame the (next) mask sweep is due on. Re-armed on every stage
## change, since each stage builds its own mask.
var _sweep_at_frame: int = SWEEP_FRAME
## Stage the tour believes it is in (only for the debug narration).
var _seen_stage_index: int = 0
## Countdown to the post-swap sky event (see STAGE_SKY_DELAY); <= 0 idle.
var _sky_probe_left: float = 0.0
## Seconds left of the deliberate dwell before taking the exit portal.
var _dwell_left: float = 0.0
## True while RunState.stage_cleared has already been acted on.
var _stage_cleared_seen: bool = false
## True while BONK_STAGE_FAST is set (read once, at ready).
var _stage_fast: bool = false
## Fog gate. A soak that explores almost nothing is a soak whose raider
## never went anywhere, and that is exactly the failure the walk exists to
## catch — the fog is the only signal that reports it directly.
##
## Calibrated ONCE (iteration 52) against three 360 s biome soaks with
## BONK_SEED=4242 BONK_GAME_SEED=4242: Hollow Woods 0.15, Ash Dunes 0.32,
## Gloomfen 0.16. The gate is 60% of the WORST of those.
##
## The 60% is not slack for a lazy tour, it is measured variance: the world
## is reproducible (same mask, same relief, frame-identical for the first
## ~38 s) but the run is not — physics contact order diverges and the same
## seed lands anywhere in 0.13-0.24 on the same map. A gate pinned to the
## observed minimum would be flaky; this one still catches the failure it
## exists for, a raider that stops walking, which measured 0.08.
##
## It is a floor on coverage: raise it if the tour gets better, never lower
## it because a run came up short.
const FOG_MIN_EXPLORED: float = 0.09
## Hits refused by Inmortalidad, cached while the run is alive for the
## same reason the fog reading is: _exit_tree runs after the raider is
## gone.
var _blocked_hits_seen: int = 0
## Last fog reading taken while the run was alive. _exit_tree runs during
## teardown, when the RunSystems that owns the fog is already gone, so the
## summary has to report what was measured, not what is left.
var _explored_seen: float = 0.0
## Seconds between Tab presses, and how long the overlay stays open.
const MAP_OVERLAY_INTERVAL: float = 60.0
const MAP_OVERLAY_HOLD: float = 2.0
var _map_overlay_left: float = MAP_OVERLAY_INTERVAL
var _map_overlay_close_left: float = 0.0
## The overlay refreshes on its own _process, which lands in an idle frame
## AFTER this physics one; reading the count immediately reported the map
## as it was before it opened.
const MAP_OVERLAY_REPORT_DELAY: float = 0.5
var _map_overlay_report_left: float = 0.0
var _map_overlay_open: bool = false

## True once the tour has been told to drop everything and head for the
## exit portal (see _tick_stage_flow); re-armed on every stage change.
var _exit_rush: bool = false
## --- power-up switches and instrumentation (iteration 53) -------------------
## BONK_POWERUP_NOW=<id>: granted at this run time and re-granted the
## moment it lapses. Not a loop of pickups: the point is to hold ONE
## effect on for a whole short soak so its edge cases get exercised.
const POWERUP_NOW_AT: float = 20.0
## BONK_STAR_NOW=1 drops its star at this run time.
const STAR_NOW_AT: float = 30.0
## Enemies sampled per frame during a freeze. Three is enough to catch a
## body that moved without walking the whole horde every frame.
const TIME_STOP_SAMPLE: int = 3
## How far a frozen body may drift and still count as still. Nothing
## should move at all; this is float noise, not a tolerance to tune.
const TIME_STOP_EPSILON: float = 0.01

## Flight soak: hold jump this long, this often. Long enough to actually
## climb to the ceiling and drift over the blocked cells the landing rule
## exists for.
const FLIGHT_HOLD_PERIOD: float = 15.0
const FLIGHT_HOLD_TIME: float = 5.0
var _flight_holding: bool = false

## BONK_WEATHER_NOW: forced once, at this run time. Late enough that the
## arena and its lights are cached, early enough that even a 240 s soak
## sees the whole row plus its follow-up.
## Preloaded, not the bare class name: world_director.gd declares no
## class_name, so its static weather_row() is only reachable through the
## script resource.
const WEATHER_DIRECTOR := preload("res://scripts/world/world_director.gd")
const WEATHER_NOW_AT: float = 30.0
var _weather_now: String = ""
var _weather_forced: bool = false
## Last weather id seen live, so the frame the channel empties can be
## caught without the director having to signal it.
var _weather_seen: String = ""

## BONK_POI_NOW: POIs to drop next to the raider once, at POI_NOW_AT.
const POI_NOW_AT: float = 20.0
## Placed this far from the raider: outside the interact ring so the tour
## has to walk the last step, close enough that it does within one leg.
const POI_NOW_RADIUS: float = 8.0
var _poi_now: Array[String] = []
var _poi_spawned: bool = false

var _powerup_now: String = ""
var _star_now: bool = false
var _star_dropped: bool = false
## Freeze accounting for one time_stop window, printed at the thaw.
var _freeze_active: bool = false
var _freeze_sampled: int = 0
var _freeze_moved: int = 0
var _freeze_damage_events: int = 0
## instance id -> position when this body was last sampled frozen.
var _freeze_positions: Dictionary[int, Vector3] = {}
## Health of the lead raider, connected once so enemy damage during a
## freeze can be counted.
var _lead_health: Health = null

var _bounds: Node3D = null
var _in_blocked_cell: bool = false
var _blocked_cell: Vector2i = Vector2i.ZERO
var _blocked_stay: float = 0.0
var _blocked_reported: bool = false


func _ready() -> void:
	# Never fold a soak into the real save: re-point SaveData at a scratch
	# file (fresh defaults) before the arena boots.
	SaveData.save_path = "user://soak_save.json"
	SaveData.load_from_disk()
	# BONK_CHARACTER=<id> picks the raider (default: the config's choice).
	# An unknown id is an ERROR, not a shrug: a soak meant to exercise one
	# raider silently running the default one reports a green run about
	# code it never touched.
	var character := OS.get_environment("BONK_CHARACTER")
	if not character.is_empty():
		if CharacterCatalog.by_id(character).is_empty():
			push_error("ArenaProbe: unknown BONK_CHARACTER '%s'" % character)
		else:
			GameConfig.selected_character_id = character
	print("ArenaProbe: character=%s" % GameConfig.selected_character_id)
	# BONK_ARENA is a SCENE PATH for backwards compatibility, but what it
	# selects now is the starting biome: the probe always boots Run.tscn,
	# which owns the run and swaps arenas per stage.
	var path := OS.get_environment("BONK_ARENA")
	if path.is_empty():
		path = DEFAULT_ARENA
	GameConfig.start_map_id = _map_id_for_scene(path)
	var scene := load(RUN_SCENE) as PackedScene
	if scene == null:
		push_error("ArenaProbe: cannot load '%s'" % RUN_SCENE)
		get_tree().quit(1)
		return
	RunState.stage_changed.connect(_on_stage_changed)
	add_child(scene.instantiate())
	_walking = OS.get_environment("BONK_WALK") != "0"
	_debug = OS.get_environment("BONK_PROBE_DEBUG") == "1"
	var seed_text := OS.get_environment("BONK_SEED")
	if seed_text.is_valid_int():
		_rng.seed = int(seed_text)
	else:
		_rng.randomize()
	# BONK_GODMODE=1: an idle raider dies inside a minute, which hides every
	# late system (bosses, hordes, altars); a huge HP pool lets a soak run
	# the full clock. Purely a harness switch — never shipped behavior.
	if OS.get_environment("BONK_GODMODE") == "1":
		_apply_godmode.call_deferred()
	if OS.get_environment("BONK_ELITE_BOOST") == "1":
		_apply_elite_boost.call_deferred()
	_stage_fast = OS.get_environment("BONK_STAGE_FAST") == "1"
	_powerup_now = OS.get_environment("BONK_POWERUP_NOW")
	if not _powerup_now.is_empty() and PowerUpCatalog.by_id(_powerup_now).is_empty():
		push_error("ArenaProbe: unknown BONK_POWERUP_NOW '%s'" % _powerup_now)
		_powerup_now = ""
	_star_now = OS.get_environment("BONK_STAR_NOW") == "1"
	_weather_now = OS.get_environment("BONK_WEATHER_NOW")
	if not _weather_now.is_empty() \
			and WEATHER_DIRECTOR.weather_row(_weather_now).is_empty():
		push_error("ArenaProbe: unknown BONK_WEATHER_NOW '%s'" % _weather_now)
		_weather_now = ""
	var poi_list := OS.get_environment("BONK_POI_NOW")
	if not poi_list.is_empty():
		for entry: String in poi_list.split(",", false):
			_poi_now.append(entry.strip_edges())
	var points_text := OS.get_environment("BONK_POINTS")
	if points_text.is_valid_int():
		_grant_points.call_deferred(int(points_text))
	print("ArenaProbe: arena=%s walk=%s" % [path.get_file(), _walking])


## Stage bookkeeping the tour needs: the dwell that lets the
## pseudo-infinite ramp log a minute before the party leaves, and the sky
## event fired a beat after every stage change. That sky event is a TEST,
## not scenery: the WorldDirector survives the swap and re-caches the new
## arena's Sun in on_stage_started, and a blood moon that tints nothing is
## how a stale light reference would show up in a soak log.
func _tick_stage_flow(delta: float) -> void:
	if RunState.stage_cleared and not _stage_cleared_seen:
		_stage_cleared_seen = true
		_dwell_left = PSEUDO_INFINITE_DWELL if _stage_fast else 0.0
	elif not RunState.stage_cleared:
		_stage_cleared_seen = false
	_dwell_left = maxf(_dwell_left - delta, 0.0)
	if RunState.stage_cleared and _dwell_left <= 0.0 and not _exit_rush:
		_exit_rush = true
		# Abandon whatever the tour was doing. The exit portal lands at
		# least 40 m away and the soak has a fixed clock; finishing the
		# current linger and leg first can burn 25 s of it on a chest.
		_linger_left = 0.0
		_leg_time_left = 0.0
	if _sky_probe_left > 0.0:
		_sky_probe_left = maxf(_sky_probe_left - delta, 0.0)
		if _sky_probe_left <= 0.0:
			get_tree().call_group("world_director", "start_sky_event", "blood_moon")


## MapCatalog id whose arena scene is `scene_path`; the default map when
## the path is unknown, so a typo soaks the forest instead of crashing.
func _map_id_for_scene(scene_path: String) -> String:
	for row: Dictionary in MapCatalog.MAP_LIBRARY:
		if String(row.scene_path) == scene_path:
			return String(row.id)
	return MapCatalog.DEFAULT_ID


## A stage change replaces the whole arena: every id-keyed piece of state
## in this harness now points at freed nodes, and the new map has its own
## mask, so the sweep has to run again against it.
func _on_stage_changed(stage_index: int, map_id: String) -> void:
	_target = null
	_visited.clear()
	_seen_stage_index = stage_index
	_swept = false
	_sweep_at_frame = _frames + SWEEP_FRAME
	_blocked_stay = 0.0
	_blocked_reported = false
	_rising_for.clear()
	_sky_probe_left = STAGE_SKY_DELAY
	_dwell_left = 0.0
	_exit_rush = false
	print("ArenaProbe: stage %d is %s" % [stage_index + 1, map_id])


## BONK_ELITE_BOOST=1: every spawn rolls shiny. Through the group, like
## every other cross-scene call in this project.
func _apply_elite_boost() -> void:
	get_tree().call_group("enemy_spawner", "force_elite_spawns", true)
	print("ArenaProbe: elite boost on")


func _apply_godmode() -> void:
	for node: Node in get_tree().get_nodes_in_group("player"):
		var health := Health.find_in(node)
		if health != null:
			health.max_hp = 10000000.0
			health.heal_full()
	print("ArenaProbe: godmode on")


## Printed once, on the way out: a summary the soak script can read.
func _exit_tree() -> void:
	# One-line log (RunManager convention) for headless soaks.
	print("Probe legs: reached=%d timed_out=%d" % [_legs_reached, _legs_timed_out])
	var explored := _explored_seen
	print("Probe fog: explored=%.2f" % explored)
	# Inmortalidad is only proved by an enemy having TRIED: the counter
	# lives on Health, so a soak that never got hit reports 0 and the
	# acceptance check fails, which is the point.
	print("Immortal blocked: %d" % _blocked_hits_seen)
	# Skipped under BONK_STAGE_FAST: that soak resets the fog every minute
	# when it crosses a stage, so its coverage says nothing about the walk.
	# Skipped under BONK_POWERUP_NOW for the same reason: that switch holds
	# ONE power-up on for the whole soak, which is a state no real run ever
	# reaches. Under time_stop the horde never walks into weapon range, so
	# nothing dies, no XP drops and the tour crawls (measured: level 2 and
	# 107 live bodies at 360 s). Coverage there measures the switch, not the
	# walk. The gate keeps its full force where it was calibrated: every
	# soak tools/verificar.sh runs, none of which sets either switch.
	if not _stage_fast and _powerup_now.is_empty() and explored < FOG_MIN_EXPLORED:
		push_warning("ArenaProbe: fog barely explored — %.2f < %.2f"
				% [explored, FOG_MIN_EXPLORED])



func _sample_blocked_hits() -> void:
	var lead := _lead_player()
	if lead == null:
		return
	var health := Health.find_in(lead)
	if health != null:
		_blocked_hits_seen = health.blocked_hits


func _explored_fraction() -> float:
	var fog := FogOfWar.find(get_tree())
	if fog != null:
		_explored_seen = fog.explored_fraction()
	return _explored_seen


## Opens the Tab map every MAP_OVERLAY_INTERVAL seconds and closes it
## MAP_OVERLAY_HOLD later. Not decoration: the overlay is a Control that
## composites an image and walks the marker group, and this is the only
## thing that ever exercises that path in a soak.
func _tick_map_overlay(delta: float) -> void:
	if _map_overlay_open:
		if _map_overlay_report_left > 0.0:
			_map_overlay_report_left -= delta
			if _map_overlay_report_left <= 0.0:
				_report_map_markers()
		_map_overlay_close_left -= delta
		if _map_overlay_close_left <= 0.0:
			_map_overlay_open = false
			_send_action(&"map_overlay", true)
			_release_map_overlay.call_deferred()
			print("Map overlay: closed")
		return
	_map_overlay_left -= delta
	if _map_overlay_left > 0.0:
		return
	_map_overlay_left = MAP_OVERLAY_INTERVAL
	_map_overlay_open = true
	_map_overlay_close_left = MAP_OVERLAY_HOLD
	_map_overlay_report_left = MAP_OVERLAY_REPORT_DELAY
	_send_action(&"map_overlay", true)
	_release_map_overlay.call_deferred()


func _release_map_overlay() -> void:
	_send_action(&"map_overlay", false)


## Marker count of slot 0's overlay, MAP_OVERLAY_REPORT_DELAY after the
## press: the overlay refreshes in its own idle _process, which lands
## after this physics frame, so reading it sooner reported the map as it
## was before it opened (markers=0).
func _report_map_markers() -> void:
	var markers := 0
	for node: Node in get_tree().get_nodes_in_group(&"map_overlay"):
		if int(node.get("slot")) == 0 and node.has_method(&"marker_count"):
			markers = int(node.call(&"marker_count"))
			break
	print("Map overlay: open markers=%d" % markers)


func _physics_process(delta: float) -> void:
	_frames += 1
	if not _swept and _frames >= _sweep_at_frame:
		_swept = true
		_run_mask_sweep()
	_tick_stage_flow(delta)
	_tick_map_overlay(delta)
	_tick_powerup_switches()
	_watch_time_stop()
	_watch_airborne(delta)
	_watch_blocked_cell(delta)
	if _frames % 120 == 0:
		print("frame %d paused=%s run_time=%.1f active=%s enemies=%d level=%d airborne=%d explored=%.2f" % [
				_frames, get_tree().paused, RunState.run_time, RunState.run_active,
				get_tree().get_node_count_in_group("enemies"), RunState.level,
				_airborne_total, _explored_fraction()])
		_sample_blocked_hits()
	var card_ui_open := false
	for node: Node in get_tree().get_nodes_in_group("upgrade_ui"):
		var ui := node as CanvasLayer
		if ui != null and ui.visible and ui.has_method("_on_card_pressed"):
			card_ui_open = true
			ui.call("_on_card_pressed", 0)
	_watch_for_wedge(delta, card_ui_open)
	if _walking and not get_tree().paused:
		_drive_walk(delta)


## --- power-up switches (iteration 53) ---------------------------------------

## BONK_POWERUP_NOW / BONK_STAR_NOW. The re-grant is what makes a short
## soak useful: one twenty-second window would leave a 120 s soak running
## eighty seconds of ordinary play, and the acceptance checks below only
## mean something while the effect is on.
func _tick_powerup_switches() -> void:
	if RunState.run_time < POWERUP_NOW_AT:
		return
	var lead := _lead_player()
	if lead == null:
		return
	if not _powerup_now.is_empty():
		var powerups := PowerUps.find_in(lead)
		if powerups != null and not powerups.is_active(_powerup_now):
			powerups.apply(_powerup_now)
	_tick_flight_hold()
	_tick_poi_now()
	_tick_weather_now()
	_watch_weather_end()
	if _star_now and not _star_dropped and RunState.run_time >= STAR_NOW_AT:
		_star_dropped = true
		var spawner := get_tree().get_first_node_in_group("enemy_spawner")
		if spawner != null and spawner.has_method("spawn_powerup_pickup"):
			# At the raider's feet and STATIONARY: the roaming star is
			# deliberately hard to intercept, and this switch exists to
			# prove the pickup and its effect work, not the chase.
			var star := spawner.call("spawn_powerup_pickup",
					lead.global_position + Vector3.UP * 0.6, "star") as Node3D
			if star != null:
				star.set("roaming", false)


## Vuelo has to be FLOWN to be tested: the power-up only does anything
## while the jump action is held. Gated on the switch that granted it —
## every other soak keeps the ordinary walk, because a tour that hopped
## every fifteen seconds would be a different tour.
func _tick_flight_hold() -> void:
	if _powerup_now != "flight":
		return
	var cycle := fmod(RunState.run_time, FLIGHT_HOLD_PERIOD)
	var want_hold := cycle < FLIGHT_HOLD_TIME
	if want_hold == _flight_holding:
		return
	_flight_holding = want_hold
	_send_action(&"jump", want_hold)


## BONK_WEATHER_NOW: one forced summon. Through start_sky_event, which is
## the same forced entry the event altar uses — it stops whatever is
## running and ignores the cadence gap.
## Watches the director's one weather slot and reports the HUD offset the
## moment it empties.
func _watch_weather_end() -> void:
	var director := get_tree().get_first_node_in_group("world_director")
	if director == null:
		return
	var live: Variant = director.get("active_weather")
	var weather := live as Dictionary if live is Dictionary else {}
	var now := String(weather.get("id", "")) if not weather.is_empty() else ""
	if now == _weather_seen:
		return
	if not _weather_seen.is_empty():
		_report_hud_offset()
	_weather_seen = now


## The earthquake shifts the HUD CanvasLayer and has to put it back. Read
## at every "Weather ended:" so a soak can prove it, and printed even when
## the weather was not the quake: a non-zero offset after ANY weather is a
## leak, and only checking after the quake would miss it.
func _report_hud_offset() -> void:
	for node: Node in get_tree().get_nodes_in_group("hud"):
		var hud := node as CanvasLayer
		if hud != null:
			print("HUD offset: %s" % hud.offset)
			return


func _tick_weather_now() -> void:
	if _weather_forced or _weather_now.is_empty() or RunState.run_time < WEATHER_NOW_AT:
		return
	_weather_forced = true
	get_tree().call_group("world_director", "start_sky_event", _weather_now)


## BONK_POI_NOW: one ring of requested POIs beside the raider. The
## director offers these on its own cadence, which needs many minutes to
## produce all four — this exists so one short soak can prove every stall
## and the box actually work end to end.
func _tick_poi_now() -> void:
	if _poi_spawned or _poi_now.is_empty() or RunState.run_time < POI_NOW_AT:
		return
	var lead := _lead_player()
	if lead == null:
		return
	_poi_spawned = true
	var terrain := Terrain.find(get_tree())
	for i in _poi_now.size():
		var angle := TAU * float(i) / float(_poi_now.size())
		var at := lead.global_position \
				+ Vector3(cos(angle), 0.0, sin(angle)) * POI_NOW_RADIUS
		if terrain != null:
			at.y = terrain.height_at(at.x, at.z)
		var node := _build_poi(_poi_now[i])
		if node == null:
			push_error("ArenaProbe: unknown BONK_POI_NOW entry '%s'" % _poi_now[i])
			continue
		RunRoot.stage_parent(get_tree()).add_child(node)
		node.global_position = at
		print("ArenaProbe: placed POI %s" % _poi_now[i])


## One POI by name, or null when the name is not one this switch knows.
func _build_poi(poi: String) -> Node3D:
	match poi:
		"pet_box":
			return load("res://scenes/world/PetBox.tscn").instantiate() as Node3D
		"event_altar":
			return load("res://scenes/world/shrines/EventAltar.tscn").instantiate() as Node3D
		"vendor_items", "vendor_powerups", "vendor_animals":
			var vendor := load("res://scenes/world/Vendor.tscn").instantiate() as Node3D
			# Set before it enters the tree: Vendor._ready reads it.
			vendor.set("kind", poi.trim_prefix("vendor_"))
			return vendor
	return null


## BONK_POINTS: a starting purse for slot 0. Deferred so the Player exists.
func _grant_points(amount: int) -> void:
	var lead := _lead_player()
	if lead != null and lead.has_method("add_points"):
		lead.call("add_points", amount)
		print("ArenaProbe: granted %d points" % amount)


## Time stop: while the spawner holds a freeze, sample a few frozen bodies
## every frame and report at the thaw. `moved` and `damage_events` are the
## two ways a freeze can be a lie — a body that kept walking, or one that
## still landed a hit — and both must come out zero.
func _watch_time_stop() -> void:
	var spawner := get_tree().get_first_node_in_group("enemy_spawner")
	var frozen := spawner != null and spawner.has_method("is_frozen") \
			and bool(spawner.call("is_frozen"))
	if frozen and not _freeze_active:
		_freeze_active = true
		_freeze_sampled = 0
		_freeze_moved = 0
		_freeze_damage_events = 0
		_freeze_positions.clear()
		_connect_lead_health()
	elif not frozen and _freeze_active:
		_freeze_active = false
		print("Time stop: sampled=%d moved=%d damage_events=%d"
				% [_freeze_sampled, _freeze_moved, _freeze_damage_events])
		return
	if not frozen:
		return
	var bodies: Array = spawner.call("frozen_bodies")
	for i in mini(TIME_STOP_SAMPLE, bodies.size()):
		var body := bodies[i] as Node3D
		if body == null or not body.is_inside_tree():
			continue
		var id := body.get_instance_id()
		if _freeze_positions.has(id):
			if body.global_position.distance_to(_freeze_positions[id]) > TIME_STOP_EPSILON:
				_freeze_moved += 1
			_freeze_sampled += 1
		_freeze_positions[id] = body.global_position


## Counts enemy-sourced damage on the lead raider while a freeze runs.
## Connected once and left connected: the raider's Health outlives every
## freeze, and reconnecting per window would double-count.
func _connect_lead_health() -> void:
	if _lead_health != null and is_instance_valid(_lead_health):
		return
	var lead := _lead_player()
	if lead == null:
		return
	_lead_health = Health.find_in(lead)
	if _lead_health != null and not _lead_health.damaged.is_connected(_on_lead_damaged):
		_lead_health.damaged.connect(_on_lead_damaged)


func _on_lead_damaged(_amount: float, _current: float) -> void:
	if _freeze_active:
		_freeze_damage_events += 1


func _lead_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	return players[0] as Node3D if not players.is_empty() else null


## One pass over the live horde: bodies that have been rising off the floor
## long enough are the "flying enemies" bug, and each one warns once.
## Runs even while the tree is paused (the counters simply stop moving,
## because nothing moves), and prunes itself against the live group so a
## freed body cannot keep a stale timer alive.
func _watch_airborne(delta: float) -> void:
	if get_tree().paused:
		return
	var live: Dictionary[int, bool] = {}
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var body := node as CharacterBody3D
		if body == null or not body.is_inside_tree():
			continue
		var id := body.get_instance_id()
		live[id] = true
		if _airborne_seen.has(id):
			continue
		if not _is_rising(body):
			_rising_for.erase(id)
			continue
		var elapsed := float(_rising_for.get(id, 0.0)) + delta
		_rising_for[id] = elapsed
		if elapsed < AIRBORNE_TIME:
			continue
		_airborne_seen[id] = true
		_airborne_total += 1
		push_warning("ArenaProbe: enemy airborne — %s rose %.1f m/s for %.1fs off the floor"
				% [body.name, body.velocity.y, elapsed])
	for id: int in _rising_for.keys():
		if not live.has(id):
			_rising_for.erase(id)


## True while this body is climbing the air under its own upward velocity
## and is NOT one of the two bodies allowed to: an enemy in its climb state
## (scrambling up a wall or a prop) or a Duneburrower mid-eruption.
func _is_rising(body: CharacterBody3D) -> bool:
	if body.is_on_floor() or body.velocity.y <= AIRBORNE_RISE_SPEED:
		return false
	if bool(body.get("_climbing")):
		return false
	var state: Variant = body.get("_state")
	if state != null and int(state) == BURROWER_ERUPTING and body.has_method("_erupt"):
		return false
	return true


## Metres between a body and the ground under it.
func _height_above_ground(at: Vector3) -> float:
	var terrain := Terrain.find(get_tree())
	return at.y - (terrain.height_at(at.x, at.z) if terrain != null else 0.0)


## (a) Walks every boundary a blocked cell shares with a WALKABLE one in
## SWEEP_STEP increments, straddling the boundary line with the player
## capsule. A sample that touches no world geometry is an opening: a hole
## the raider can walk through into ground the mask calls unreachable.
## Never loosen this — the rock placement in scatter.gd is what has to give.
func _run_mask_sweep() -> void:
	var bounds := _arena_bounds()
	if bounds == null:
		push_warning("ArenaProbe: mask sweep skipped — no arena_bounds node with blocked_cells()")
		return
	var cells := _blocked_cells(bounds)
	var cell_size := float(bounds.call("cell_size"))
	var steps := maxi(int(round(cell_size / SWEEP_STEP)), 1)
	var capsule := CapsuleShape3D.new()
	capsule.radius = SWEEP_CAPSULE_RADIUS
	capsule.height = SWEEP_CAPSULE_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = WORLD_COLLISION_LAYER
	# Raiders share layer 1 with the world; a body standing on a boundary
	# would otherwise answer for the rock that is missing there.
	# Raiders AND the terrain: the ground is layer-1 geometry, so with a
	# heightmap under it every sample would touch something and the sweep
	# would report a perfect map it never actually tested. Rocks, props and
	# walls still count, which is what the sweep is for.
	var excluded := _raider_rids()
	var terrain := Terrain.find(get_tree())
	if terrain != null:
		excluded.append(terrain.get_rid())
	query.exclude = excluded
	var space := bounds.get_world_3d().direct_space_state
	var samples := 0
	var openings := 0
	var named := 0
	for cell: Vector2i in cells:
		var center: Vector2 = bounds.call("cell_center", cell)
		for dir: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if not bool(bounds.call("is_walkable", bounds.call("cell_center", cell + dir))):
				continue
			var normal := Vector2(float(dir.x), float(dir.y))
			var along := Vector2(-normal.y, normal.x)
			var edge := center + normal * (cell_size * 0.5)
			for i in steps + 1:
				var spot := edge + along * ((float(i) / float(steps) - 0.5) * cell_size)
				samples += 1
				# Centred over the GROUND at that spot, not at an absolute
				# height: on a hill the old fixed 0.9 m sat inside the
				# terrain, on a hollow floor it floated over the rocks.
				var ground := terrain.height_at(spot.x, spot.y) if terrain != null else 0.0
				query.transform = Transform3D(Basis(),
						Vector3(spot.x, ground + SWEEP_CAPSULE_CENTER_Y, spot.y))
				if not space.intersect_shape(query, 1).is_empty():
					continue
				openings += 1
				if named < SWEEP_REPORT_LIMIT:
					named += 1
					push_warning("ArenaProbe: mask opening at (%.1f, %.1f) — cell (%d, %d), edge (%d, %d)"
							% [spot.x, spot.y, cell.x, cell.y, dir.x, dir.y])
	print("Mask sweep: blocked=%d samples=%d openings=%d" % [cells.size(), samples, openings])
	if openings > 0:
		push_warning("ArenaProbe: mask sweep found %d opening(s) in %d samples over %d blocked cells"
				% [openings, samples, cells.size()])


## (b) The lead raider standing ON THE FLOOR PLATE inside a blocked cell for
## BLOCKED_CELL_GRACE seconds straight. Height is what separates "walked in
## through a gap" from "is on top of a rock, a platform or a mesa that sits
## in a blocked cell", which is fine — the timer only runs at floor level,
## while the right to report belongs to the ENTRY, so a stuck raider that
## keeps hopping still warns once and not once per landing.
func _watch_blocked_cell(delta: float) -> void:
	if get_tree().paused:
		return
	var bounds := _arena_bounds()
	var lead := _lead_raider()
	if bounds == null or lead == null:
		_leave_blocked_cell()
		return
	var flat := Vector2(lead.global_position.x, lead.global_position.z)
	if bool(bounds.call("is_walkable", flat)):
		_leave_blocked_cell()
		return
	var cell: Vector2i = bounds.call("cell_of", flat)
	if not _in_blocked_cell or cell != _blocked_cell:
		_in_blocked_cell = true
		_blocked_cell = cell
		_blocked_stay = 0.0
		_blocked_reported = false
	if _height_above_ground(lead.global_position) > FLOOR_STAND_MAX_Y:
		_blocked_stay = 0.0
		return
	_blocked_stay += delta
	if _blocked_stay < BLOCKED_CELL_GRACE or _blocked_reported:
		return
	_blocked_reported = true
	push_warning("ArenaProbe: raider inside blocked cell (%d, %d) — stood at (%.1f, %.1f, %.1f) for %.1fs"
			% [_blocked_cell.x, _blocked_cell.y, lead.global_position.x,
			lead.global_position.y, lead.global_position.z, _blocked_stay])


func _leave_blocked_cell() -> void:
	_in_blocked_cell = false
	_blocked_stay = 0.0
	_blocked_reported = false


## The arena's own bounds node (scatter.gd), through the group like every
## other cross-scene lookup here. Cached: both mask guards ask every frame.
func _arena_bounds() -> Node3D:
	if is_instance_valid(_bounds):
		return _bounds
	for node: Node in get_tree().get_nodes_in_group("arena_bounds"):
		var bounds := node as Node3D
		if bounds != null and bounds.has_method("blocked_cells"):
			_bounds = bounds
			return bounds
	return null


## Duck-typed on purpose: scatter.gd has no class_name, so the return
## crosses as a Variant and every element is re-checked before it lands in
## a typed array.
func _blocked_cells(bounds: Node3D) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var raw: Variant = bounds.call("blocked_cells")
	if not (raw is Array):
		return cells
	for item: Variant in (raw as Array):
		if item is Vector2i:
			cells.append(item)
	return cells


## Physics RIDs of every raider, standing or downed: the sweep asks about
## world geometry, and a raider is on the same collision layer as it.
func _raider_rids() -> Array[RID]:
	var rids: Array[RID] = []
	var groups: Array[StringName] = [&"player", &"downed_players"]
	for group: StringName in groups:
		for node: Node in get_tree().get_nodes_in_group(group):
			var body := node as CollisionObject3D
			if body != null and body.is_inside_tree():
				rids.append(body.get_rid())
	return rids


func _lead_raider() -> CharacterBody3D:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return null
	var lead := players[0] as CharacterBody3D
	if lead == null or not lead.is_inside_tree():
		return null
	return lead


## A blocking UI that never closes (roulette, run end) freezes run_time while
## the frame counter keeps climbing, so the soak looks healthy while running
## nothing. Report it once, loudly enough for a grep.
func _watch_for_wedge(delta: float, card_ui_open: bool) -> void:
	if not get_tree().paused or card_ui_open:
		_paused_for = 0.0
		return
	_paused_for += delta
	if _paused_for >= PAUSE_WEDGE_WARN and not _wedge_reported:
		_wedge_reported = true
		# Only the VISIBLE blockers: every screen in the group is a member
		# whether or not it is on screen, so listing all of them points at
		# the wrong culprit.
		var blockers: Array[String] = []
		for node: Node in get_tree().get_nodes_in_group("ui_blocking"):
			var shown: Variant = node.get("visible")
			if shown == null or bool(shown):
				blockers.append(node.name)
		push_warning("ArenaProbe: WEDGE — tree paused %.0fs with no card UI; blocking=%s"
				% [_paused_for, blockers])


## XZ of a world position. Every distance this tour measures is flat:
## with relief, height differences are not travel.
func _flat(at: Vector3) -> Vector2:
	return Vector2(at.x, at.z)


## Steers the lead raider toward the current waypoint by HOLDING THE REAL
## MOVE ACTIONS. Writing velocity directly does not work: Player rebuilds it
## from Input.get_vector() every physics frame and then calls
## move_and_slide(), so a written velocity is overwritten before it moves
## anything. Pressing the actions also means the soak exercises the real
## input path (slide, sprint gating, free-orbit basis) instead of bypassing it.
func _drive_walk(delta: float) -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		_release_move()
		return
	var lead := players[0] as CharacterBody3D
	if lead == null or not lead.is_inside_tree():
		_release_move()
		return
	if _linger_left > 0.0:
		_linger_left -= delta
		_release_move()
		_interact_timer -= delta
		if _interact_timer <= 0.0:
			_interact_timer = INTERACT_INTERVAL
			_press_interact()
		return
	_leg_time_left -= delta
	# "Arrived" means the game's own condition — inside the target's Area3D,
	# which is what gates the prompt and the interact — not a fixed radius.
	# A chest on a rise sits 4-5 m away horizontally and would never satisfy
	# a distance test while being perfectly interactable.
	var reached := _flat(lead.global_position).distance_to(_flat(_waypoint)) <= WAYPOINT_REACHED
	if is_instance_valid(_target) and _target.player_in_range:
		reached = true
	if _waypoint == Vector3.ZERO or _leg_time_left <= 0.0 or reached:
		if reached:
			_legs_reached += 1
			# Stand still on arrival: Charge altars need an uninterrupted
			# channel and chests need the interact press to land.
			_linger_left = LINGER_TIME
			_interact_timer = 0.0
			_release_move()
			_pick_waypoint(lead.global_position)
			return
		_legs_timed_out += 1
		if _debug:
			print("ArenaProbe: leg timed out %.1fm short of %v"
					% [_flat(lead.global_position).distance_to(_flat(_waypoint)), _waypoint])
		_pick_waypoint(lead.global_position)
	_hold_move_toward(lead, _waypoint)
	_unstick(lead, delta)


## Hops when horizontal progress stalls. Ledges, ramps and the mask walls
## all read as "walking into something"; without a jump the tour can never
## reach the chests parked on verticality spots.
func _unstick(lead: CharacterBody3D, delta: float) -> void:
	_stall_check -= delta
	if _stall_check > 0.0:
		return
	_stall_check = STALL_WINDOW
	var moved := lead.global_position.distance_to(_last_position)
	_last_position = lead.global_position
	if moved > STALL_DISTANCE:
		return
	var jump := Coop.action(0, &"jump")
	Input.action_press(jump)
	Input.action_release.bind(jump).call_deferred()


## Converts a world-space heading into held move actions. Player builds its
## wish direction as `transform.basis * Vector3(input.x, 0, input.y)`, so the
## heading has to come back through the body's own basis.
func _hold_move_toward(body: CharacterBody3D, to: Vector3) -> void:
	var heading := to - body.global_position
	heading.y = 0.0
	if heading.length_squared() < 0.01:
		_release_move()
		return
	var local := body.transform.basis.inverse() * heading.normalized()
	_hold_axis(&"move_right", &"move_left", local.x)
	_hold_axis(&"move_back", &"move_forward", local.z)


func _hold_axis(positive: StringName, negative: StringName, amount: float) -> void:
	var forward := Coop.action(0, positive)
	var backward := Coop.action(0, negative)
	if amount >= 0.0:
		Input.action_press(forward, absf(amount))
		Input.action_release(backward)
	else:
		Input.action_press(backward, absf(amount))
		Input.action_release(forward)


func _release_move() -> void:
	for base: StringName in [&"move_left", &"move_right", &"move_forward", &"move_back"]:
		Input.action_release(Coop.action(0, base))


## Synthesizes a real "interact" press so shrines, chests, portals and
## secret triggers resolve through their own _unhandled_input path.
## The release has to land on a LATER frame than the press: both parsed in
## one flush and the action never reads as "just pressed", which is exactly
## what Interactable._unhandled_input tests for.
func _press_interact() -> void:
	if _debug:
		var touching: Array[String] = []
		for node: Node in _all_interactables(get_tree().current_scene):
			var spot := node as Interactable
			if spot != null and spot.player_in_range:
				touching.append("%s(available=%s)" % [spot.name, spot.available])
		print("ArenaProbe: interact press; in range: %s" % [touching])
	_send_interact(true)
	_release_interact.call_deferred()


func _release_interact() -> void:
	_send_interact(false)


func _send_interact(pressed: bool) -> void:
	_send_action(&"interact", pressed)


## One synthesized action press for slot 0. A PARSED InputEventAction, not
## Input.action_press: an _unhandled_input handler only ever sees the
## parsed kind, and Input.is_action_just_pressed sees both.
func _send_action(base: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = Coop.action(0, base)
	event.pressed = pressed
	Input.parse_input_event(event)


## Next destination: the nearest still-available Interactable that this tour
## has not just visited, so a soak actually spends points on chests and
## charges altars; a random walkable point once they are all spent or all
## recently tried.
func _pick_waypoint(from: Vector3) -> void:
	_leg_time_left = LEG_TIMEOUT
	# A power-up on the ground outranks everything nearby (iteration 53):
	# it is free, it expires in 45 s, and walking into it is the whole
	# interaction — no press, no linger. Only if one is CLOSE, though: a
	# tour that crossed the map for every drop would stop touring.
	var pickup := _nearest_pickup(from)
	if pickup != null:
		_target = null
		_waypoint = pickup.global_position
		if _debug:
			print("ArenaProbe: heading to power-up %s at %.1fm"
					% [pickup.get("powerup_id"), _flat(from).distance_to(_flat(_waypoint))])
		return
	var target := _nearest_interactable(from)
	_target = target
	if target != null:
		_visited[target.get_instance_id()] = RunState.run_time
		_waypoint = target.global_position
		if _debug:
			print("ArenaProbe: heading to %s at %.1fm (available=%s)"
					% [target.name, _flat(from).distance_to(_flat(_waypoint)), target.available])
		return
	# Prefer the arena's own walkable mask so waypoints never sit inside the
	# blocked cells the irregular-arena mask carves out (iteration 44).
	for node: Node in get_tree().get_nodes_in_group("arena_bounds"):
		if node.has_method("random_walkable_point"):
			var point: Variant = node.call("random_walkable_point")
			if point is Vector2:
				_waypoint = Vector3(point.x, from.y, point.y)
				if _debug:
					print("ArenaProbe: no fresh interactable, roaming to %v" % _waypoint)
				return
	var half := FALLBACK_HALF_EXTENT
	_waypoint = Vector3(_rng.randf_range(-half, half), from.y, _rng.randf_range(-half, half))


## Nearest live power-up pickup within PICKUP_DETOUR of `from`, or null.
func _nearest_pickup(from: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance := PICKUP_DETOUR * PICKUP_DETOUR
	var flat_from := _flat(from)
	for node: Node in get_tree().get_nodes_in_group(&"powerup_pickups"):
		var body := node as Node3D
		if body == null or not body.is_inside_tree() or body.is_queued_for_deletion():
			continue
		var distance := flat_from.distance_squared_to(_flat(body.global_position))
		if distance < best_distance:
			best_distance = distance
			best = body
	return best


## Nearest available interactable not tried within REVISIT_COOLDOWN. Without
## that cooldown the tour ping-pongs between the two closest points forever
## (a spent-but-still-`available` altar stays the nearest thing on the map).
func _nearest_interactable(from: Vector3) -> Interactable:
	# Once the stage is cleared (and the dwell is over) the exit portal
	# outranks everything: a tour that keeps shopping for chests never
	# crosses a stage, and crossing is what this harness has to prove.
	# Distance and the revisit cooldown are deliberately ignored.
	if RunState.stage_cleared and _dwell_left <= 0.0:
		for node: Node in _all_interactables(get_tree().current_scene):
			var way_out := node as ExitPortal
			if way_out != null and way_out.available and way_out.is_inside_tree():
				return way_out
	var nearest: Interactable = null
	var nearest_dist := INF
	for node: Node in _all_interactables(get_tree().current_scene):
		var spot := node as Interactable
		if spot == null or not spot.available or not spot.is_inside_tree():
			continue
		var tried_at: float = _visited.get(spot.get_instance_id(), -INF)
		if RunState.run_time - tried_at < REVISIT_COOLDOWN:
			continue
		var dist := from.distance_to(spot.global_position)
		if dist <= WAYPOINT_REACHED or dist >= nearest_dist:
			continue
		nearest_dist = dist
		nearest = spot
	return nearest


func _all_interactables(root: Node) -> Array[Node]:
	var found: Array[Node] = []
	if root == null:
		return found
	for child: Node in root.get_children():
		if child is Interactable:
			found.append(child)
		found.append_array(_all_interactables(child))
	return found
