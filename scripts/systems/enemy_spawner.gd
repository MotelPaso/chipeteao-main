extends Node3D
## Spawns enemies on a timer in a ring around the player, off-screen-ish.
## Difficulty ramps with elapsed run time: the interval shrinks and the
## per-tick count grows (GDD 6: swarms scale over the run timer), while
## the phase table selected by phase_preset only decides WHAT spawns per
## biome — the forest ramps grunts into skirmishers and tanks, the dunes
## mix in sunspitters and burrowers — and an elite roll (chance ramping
## from minute 3) can promote any spawn. Every clock here is RunState's,
## the same one the HUD timer and the victory check read, so the ramp, the
## hordes and the boss timetable can never drift apart. Spawned enemies
## are added as children, but the live count comes from the "enemies"
## group (corpses stay children for their death tween). Also owns the boss
## timetable: the biome boss at boss_spawn_minute and its Elder rematch at
## elder_spawn_minute, with eased regular spawns while a boss lives and a
## short relief window after one dies.

## Which time-phased spawn table this arena uses (see the tables below).
enum PhasePreset { FOREST, DUNES, MARSH }

## Time-phased spawn mixes. Each entry activates at from_minute and stays
## active until a later entry takes over; weights are relative within the
## phase. Kinds map to the exported scenes in _scene_for(). FOREST_PHASES
## is the original Hollow Woods table, unchanged.
const FOREST_PHASES: Array[Dictionary] = [
	{"from_minute": 0.0, "weights": {"grunt": 1.0}},
	{"from_minute": 2.0, "weights": {"grunt": 0.8, "skirmisher": 0.2}},
	{"from_minute": 5.0, "weights": {"grunt": 0.7, "skirmisher": 0.2, "tank": 0.1}},
	{"from_minute": 8.0, "weights": {"grunt": 0.55, "skirmisher": 0.25, "tank": 0.2}},
]

const DUNES_PHASES: Array[Dictionary] = [
	{"from_minute": 0.0, "weights": {"grunt": 0.7, "sunspitter": 0.3}},
	{"from_minute": 2.0, "weights": {"grunt": 0.55, "sunspitter": 0.3, "burrower": 0.15}},
	{"from_minute": 5.0,
			"weights": {"grunt": 0.45, "sunspitter": 0.25, "burrower": 0.15, "tank": 0.15}},
	{"from_minute": 8.0,
			"weights": {"grunt": 0.3, "sunspitter": 0.3, "burrower": 0.2, "tank": 0.2}},
]

## Gloomfen (iteration 37): the veteran-map mix — ranged-heavy from the
## start and every prior enemy kind in play by minute 5.
const MARSH_PHASES: Array[Dictionary] = [
	{"from_minute": 0.0, "weights": {"grunt": 0.6, "skirmisher": 0.4}},
	{"from_minute": 2.0,
			"weights": {"grunt": 0.45, "skirmisher": 0.3, "burrower": 0.25}},
	{"from_minute": 5.0,
			"weights": {"grunt": 0.35, "skirmisher": 0.25, "burrower": 0.2, "tank": 0.2}},
	{"from_minute": 8.0,
			"weights": {"grunt": 0.25, "skirmisher": 0.3, "burrower": 0.25, "tank": 0.2}},
]

## Tries a ring/band sample gets to find a walkable cell before the last
## candidate stands anyway (a spawn is never silently dropped).
const RING_ATTEMPTS: int = 8
## Enemies are placed this far above the ground the raycast found, so they
## settle onto it instead of starting a frame inside it.
const SPAWN_GROUND_OFFSET: float = 0.05
## The ground probe starts this high: above every arena platform and mesa,
## below the mask walls' ceiling.
const GROUND_PROBE_HEIGHT: float = 12.0
## With a terrain, the probe starts this far above its highest point and
## ends this far below its lowest (see _ground_height).
const PROBE_HEADROOM: float = 30.0
const PROBE_UNDERSHOOT: float = 2.0
## Radians a burst slot may wander off its even ring position, so a
## surround reads as organic instead of geometric.
const BURST_ANGLE_JITTER: float = 0.35
## Hard ceiling on the elite roll, however high run difficulty climbs:
## past this an "elite" stops being an event.
const ELITE_CHANCE_CAP: float = 0.6

@export var phase_preset: PhasePreset = PhasePreset.FOREST
@export var grunt_scene: PackedScene
@export var skirmisher_scene: PackedScene
@export var tank_scene: PackedScene
@export var sunspitter_scene: PackedScene
@export var burrower_scene: PackedScene
@export var max_active: int = 80
@export_group("Power-ups")
## Base chance ONE kill drops a temporary power-up. Tiny on purpose: a
## power-up has to read as an event. The raider's own powerup_drop_chance
## stat (percent) scales it, and a shiny body multiplies it again.
@export var base_powerup_drop_chance: float = 0.004
@export var shiny_powerup_drop_scale: float = 5.0
@export var powerup_pickup_scene: PackedScene = preload("res://scenes/systems/PowerUpPickup.tscn")
@export_group("Spawn Ring")
@export var min_radius: float = 18.0
@export var max_radius: float = 25.0
## Half-size of the floor plate, minus arena_edge_margin, so ring spawns
## near an arena edge still land on the floor. Fallback only: re-derived
## at ready from the map's "arena_bounds" node (the scatter node's
## arena_half_extent), so map resizes propagate automatically.
@export var arena_half_extent: float = 78.0
@export var arena_edge_margin: float = 2.0
## No spawn may land closer than this to ANY standing raider (iteration
## 48). Deliberately BELOW the 7-10 m surge band: a horde or a shiny pack
## centered on a raider is supposed to be uncomfortably close, and raising
## this above surge_min_radius would quietly gut both. What it stops is a
## body materializing inside you — in co-op the ring is drawn around ONE
## raider and used to appear on top of another.
@export var min_player_clearance: float = 5.0
@export_group("Difficulty Ramp")
## Ramp shape (retuned from instrumented T1 soaks, iteration 26): arrivals
## build ~20/min at the open and ~27/min by minute 4, then the count steps
## land AT the recovery beats — 2/tick at minute 5 (~60/min, the biome
## boss and its orb drops), 3/tick at minute 10 (~180/min, the run's "real
## danger" turn just before the Elder), 4/tick at 15 — saturating toward
## max_active around minute 10-11. The previous values (2.5 / 0.35 / 0.5)
## doubled the stream at minute TWO (28 -> 66/min, against a measured
## best-build kill capacity near 30/min) and pegged the arena at
## max_active by minute 4-5, so every soak died in minutes 2-3 instead of
## facing "real danger by minute 10+".
@export var start_interval: float = 3.0
@export var min_interval: float = 0.35
## 0.32 (was 0.25, iteration-48 balance): the whole ramp block below moves
## up ~25-35% because the run was still comfortable through minute 15 once
## builds got the uncapped levels of iteration 46. The steps are chosen so
## the FIRST minute barely moves (3.0 -> 2.16 s at minute 1.2 instead of
## 2.31, one arrival per tick either way): the opening is the part that
## already worked, and the non-godmode survival guard rail is measured
## there. The pressure lands from minute 3 on, where hordes, shinies and
## the late ramp live.
@export var interval_shrink_per_minute: float = 0.32
@export var base_count_per_tick: int = 1
## 0.45 (was 0.35, iteration-48): count steps land at minutes ~2.2/4.4/6.7
## instead of 2.9/5.7/8.6.
@export var extra_count_per_minute: float = 0.45
@export_group("Late Ramp")
## Open-ended time scaling on REGULAR spawns (bosses have their own
## ladder): from late_ramp_start_minute, every minute multiplies fresh
## spawns' HP/damage by another +N%. By minute 15 that is roughly +72% HP
## and +45% damage (iteration 48: was +54%/+36%) — the "you out-leveled the horde, now it catches back
## up" turn the idle late game was missing. Stacks with map tiers and
## elites through the same apply_tier_scaling channel.
@export var late_ramp_start_minute: float = 6.0
@export var late_hp_per_minute: float = 0.08
@export var late_damage_per_minute: float = 0.05
## Iteration 42: stronger late spawns also pay more XP per minute past the ramp.
@export var late_xp_per_minute: float = 0.065
@export_group("Hordes")
## Run minutes a horde arrives; after the last entry they repeat every
## horde_repeat_minutes. Size scales with the minute, the run-wide
## difficulty and the party; arrives in waves around a random raider.
@export var horde_minutes: Array[float] = [3.0, 7.0, 10.0, 13.0]
@export var horde_repeat_minutes: float = 3.0
@export var horde_base_size: int = 18
@export var horde_size_per_minute: float = 2.0
@export var horde_waves: int = 4
@export var horde_wave_gap: float = 1.6
## Hordes may push the live count this far past max_active.
@export var horde_overflow: int = 40
@export var horde_warning_text: String = "¡Se acerca una horda!"
@export_group("Co-op Scaling")
## Extra pressure per player beyond the first: HP so shared firepower
## doesn't melt the horde, spawn rate so four screens all stay busy.
## Damage is deliberately NOT scaled — four bodies already soak more hits.
@export var coop_hp_per_extra_player: float = 0.5
@export var coop_rate_per_extra_player: float = 0.3
@export var coop_boss_hp_per_extra_player: float = 0.5
@export_group("Elites")
@export var elite_start_minute: float = 3.0
@export var elite_full_minute: float = 12.0
## 0.05 (was 0.02, iteration-26 balance): elites are the run's only
## pre-boss health income (40% orb drop). At 2% the minutes 3-5 window
## produced ~1 elite total, so soak after soak bled out on chip damage
## 20-30s short of the first boss-orb payday at 5:00; 5% yields ~2-3
## pre-boss elites (~1 extra orb plus their 5x XP) while also seeding the
## midgame with minibosses worth focusing.
## 0.08/0.21 (was 0.06/0.16, iteration-48; 0.05/0.10 before iteration 33):
## more late shinies are the difficulty AND the health economy — the harder late ramp needs a bit
## more orb income to stay fair, and elite packs give focus targets.
@export var elite_start_chance: float = 0.08
@export var elite_full_chance: float = 0.21
@export_group("Laps and pseudo-infinite (iteration 50)")
## Multiplier per completed lap of the map list, applied to fresh spawns
## and to bosses. Replaces the map-tier ladder the select screen used to
## offer: the difficulty now comes from how far a run got, not from a
## menu pick made before it started.
@export var lap_hp_mult: float = 1.5
@export var lap_damage_mult: float = 1.3
@export var lap_xp_mult: float = 1.3
## Pseudo-infinite ramp, per minute past the stage gate.
@export var endless_hp_per_minute: float = 0.15
@export var endless_damage_per_minute: float = 0.10
@export var endless_speed_per_minute: float = 0.04
## Hard ceiling on the speed factor: past this the horde simply outruns
## the raider and the mode stops being playable.
@export var endless_speed_cap: float = 1.8
## Spawn interval multiplier per minute (compounding, floored by
## min_interval like every other interval factor).
@export var endless_interval_per_minute: float = 0.85
## Horde size multiplier while the ramp is running.
@export var endless_horde_mult: float = 1.5

@export_group("Boss")
@export var boss_scene: PackedScene
## Run minute the biome boss arrives, and the minute its stronger Elder
## rematch arrives (GDD 6: the biome boss line punctuates the run).
@export var boss_spawn_minute: float = 5.0
@export var elder_spawn_minute: float = 11.0
@export var elder_stat_multiplier: float = 1.8
@export var elder_title: String = "Rey Pútrido Ancestral"
## Iteration 42 (no run clock): after the Elder, a boss returns every
## boss_repeat_minutes, each boss_repeat_growth times stronger than the last.
@export var boss_repeat_minutes: float = 4.0
@export var boss_repeat_growth: float = 1.25
## How the recurring boss's title is built out of elder_title and its rank.
## Exported because the three pieces do not compose the same way in every
## language, and elder_title is itself overridden per arena.
@export var boss_repeat_title_template: String = "%s Ascendente %d"
## While a boss lives, regular spawns ease off by this interval factor so
## the fight reads...
@export var boss_alive_interval_multiplier: float = 1.3
## ...and a boss death buys a breather: interval multiplied by this for
## boss_relief_duration seconds.
@export var boss_relief_interval_multiplier: float = 2.0
@export var boss_relief_duration: float = 15.0
@export var boss_warning_text: String = "Una presencia monstruosa se acerca..."
@export_group("Pressure Surge")
## Ring band around a requesting shrine where surge enemies land
## (spawn_pressure_burst: hordes, the WorldDirector's shiny pack, the
## roulette frenzy — charge altars stopped calling surges in iteration 47).
@export var surge_min_radius: float = 7.0
@export var surge_max_radius: float = 10.0
## Headroom over max_active for shrine surges and elite packs. Without it
## a saturated late arena answers a charged altar (or an announced elite
## pack) with exactly zero enemies, so the promised threat — and its
## bounty — never shows up.
@export var pressure_overflow: int = 8
@export_group("Sky Events")
## Eclipse: the stream arrives this many times faster and its spawns carry
## this much more HP. Blood moon: spawns hit this much harder.
@export var eclipse_rate_multiplier: float = 1.8
@export var eclipse_hp_multiplier: float = 1.25
@export var blood_moon_damage_multiplier: float = 1.4
## Share of fresh spawns that arrive as the running event's variant.
@export var blood_moon_berserker_chance: float = 0.5
@export var eclipse_shade_chance: float = 0.4

var _spawn_timer: float = 0.0  # starts due, so the action begins immediately
var _boss_spawned: bool = false
var _elder_spawned: bool = false
var _repeat_bosses_spawned: int = 0
## Horde state.
var _hordes_fired: int = 0
var _horde_waves_left: int = 0
var _horde_wave_timer: float = 0.0
var _horde_wave_size: int = 0
## Sky event (WorldDirector): "" | "blood_moon" | "eclipse", seconds left.
var _sky_kind: String = ""
var _sky_left: float = 0.0
var _bosses_alive: int = 0
var _relief_timer: float = 0.0

## Map-tier factors (MapCatalog tier spec), pushed by the arena's
## RunSystems root at ready through the "enemy_spawner" group. All 1.0
## until then and at tier 1, so the baseline game is untouched.
## Highest pseudo-infinite minute already announced, so the log below
## prints once a minute instead of once a frame.
var _endless_minute_logged: int = -1


## Per-LAP scaling (iteration 50), replacing the map tiers: every complete
## loop of the map list multiplies fresh spawns. One lap is a whole run's
## worth of maps, so these are much larger steps than the per-minute ramp.
func lap_hp_factor() -> float:
	return pow(lap_hp_mult, float(RunState.lap))


func lap_damage_factor() -> float:
	return pow(lap_damage_mult, float(RunState.lap))


func lap_xp_factor() -> float:
	return pow(lap_xp_mult, float(RunState.lap))


## --- Pseudo-infinite ramp (iteration 50) --------------------------------
## Once a stage is cleared the party may stay as long as it likes, and the
## map answers: per minute of RunState.pseudo_infinite_time, fresh spawns
## get more HP, more damage and more speed, the spawn interval shrinks and
## hordes come bigger. Speed is capped because a body faster than the
## raider cannot be kited at all, which is not difficulty, it is a wall.
func endless_minutes() -> float:
	return RunState.pseudo_infinite_time / 60.0 if RunState.stage_cleared else 0.0


func endless_hp_factor() -> float:
	return 1.0 + endless_hp_per_minute * endless_minutes()


func endless_damage_factor() -> float:
	return 1.0 + endless_damage_per_minute * endless_minutes()


func endless_speed_factor() -> float:
	return minf(1.0 + endless_speed_per_minute * endless_minutes(), endless_speed_cap)


func endless_interval_factor() -> float:
	return pow(endless_interval_per_minute, endless_minutes())


## One line per minute while the ramp runs, so a soak can prove it moved.
func _tick_endless_log() -> void:
	if not RunState.stage_cleared:
		_endless_minute_logged = -1
		return
	var minute := floori(endless_minutes())
	if minute <= _endless_minute_logged:
		return
	_endless_minute_logged = minute
	print("Pseudo-infinite: minute %d hp x%.2f dmg x%.2f speed x%.2f" % [
			minute, endless_hp_factor(), endless_damage_factor(),
			endless_speed_factor()])


## The arena-bounds node (scatter): also answers is_walkable() for the
## irregular arena mask (iteration 44).
var _bounds: Node3D = null


func _ready() -> void:
	# Shrines reach the spawner through this group, never by node path.
	add_to_group("enemy_spawner")
	_bounds = get_tree().get_first_node_in_group("arena_bounds") as Node3D
	if _bounds != null:
		arena_half_extent = float(_bounds.get("arena_half_extent")) - arena_edge_margin
	if OS.get_environment(POWERUP_BOOST_ENV) == "1":
		_powerup_boost = POWERUP_BOOST_SCALE
		print("EnemySpawner: power-up drop boost x%.0f" % POWERUP_BOOST_SCALE)
	_validate_phase_scenes()


## Every kind this arena's phase table can draw needs a PackedScene, or
## that draw quietly degrades into a grunt (or into nothing) halfway
## through a run. Cheaper to catch the missing assignment at ready.
func _validate_phase_scenes() -> void:
	var missing: Array[String] = []
	for phase: Dictionary in active_phases():
		var weights: Dictionary = phase["weights"]
		for kind: String in weights:
			if _scene_for(kind) == null and not missing.has(kind):
				missing.append(kind)
	if not missing.is_empty():
		push_error("EnemySpawner: no scene assigned for spawn kind(s) %s." % [missing])


## Set only by the harness hook above.
var _force_elite_spawns: bool = false
## Spawns dropped this minute for want of clearance, and the minute they
## are being counted for. Printed once a minute while non-zero, so a soak
## shows whether the harder ramp is being silently eaten by the check
## instead of reaching the field.
var _clearance_skips: int = 0
var _clearance_report_minute: int = -1


## True when `pos` is far enough from every standing raider. Downed bodies
## do not count: they cannot be jumped on, and treating a corpse as a
## keep-out zone would carve dead holes out of the spawn ring.
func _has_player_clearance(pos: Vector3) -> bool:
	var clearance_sq := min_player_clearance * min_player_clearance
	for node: Node in Coop.alive_players(get_tree()):
		var body := node as Node3D
		if body == null:
			continue
		var away := pos - body.global_position
		away.y = 0.0
		if away.length_squared() < clearance_sq:
			return false
	return true


## Counts one dropped spawn and reports the total once per game minute.
func _register_clearance_skip() -> void:
	_clearance_skips += 1
	var minute := floori(_minutes())
	if minute == _clearance_report_minute:
		return
	_clearance_report_minute = minute
	# One-line log (RunManager convention) for headless soaks.
	print("Spawn skipped: no clearance x%d" % _clearance_skips)


func _walkable(pos: Vector3) -> bool:
	if _bounds == null or not _bounds.has_method("is_walkable"):
		return true
	return bool(_bounds.call("is_walkable", Vector2(pos.x, pos.z)))


## Bodies that are alive AND dangerous. Corpses stay children of this node
## for the 0.3 s of their death tween and bosses are children too, so
## get_child_count() silently ate a few slots of max_active on every tick;
## enemies leave the "enemies" group the instant they die.
func _live_enemy_count() -> int:
	return get_tree().get_node_count_in_group(&"enemies")


## The run clock in minutes. RunState owns the canonical clock (HUD timer,
## victory check, boss timetable); a second clock in this node started
## later — the arena loads after RunState.reset() — so the ramp the player
## faced never matched the minute the logs reported.
func _minutes() -> float:
	return RunState.run_time / 60.0


func _physics_process(delta: float) -> void:
	_tick_freeze(delta)
	_relief_timer = maxf(_relief_timer - delta, 0.0)
	_temp_buff_left = maxf(_temp_buff_left - delta, 0.0)
	_sky_left = maxf(_sky_left - delta, 0.0)
	if _sky_left <= 0.0 and not _sky_kind.is_empty():
		_sky_kind = ""
	_tick_endless_log()
	_tick_boss_schedule()
	_tick_hordes(delta)
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	# Carry the overshoot instead of resetting: divided by the party
	# multiplier the interval approaches one physics frame, and
	# throwing away the remainder made the real cadence measurably slower
	# than the tabulated one. Floored at zero so a frame hitch buys at
	# most one catch-up tick instead of a queued burst.
	_spawn_timer = maxf(_spawn_timer + current_interval(), 0.0)
	var budget := mini(current_count_per_tick(), max_active - _live_enemy_count())
	for i in budget:
		_spawn_one()


func current_interval() -> float:
	var interval := maxf(start_interval - interval_shrink_per_minute * _minutes(), min_interval)
	if _bosses_alive > 0:
		interval *= boss_alive_interval_multiplier
	elif _relief_timer > 0.0:
		interval *= boss_relief_interval_multiplier
	if _sky_kind == "eclipse":
		interval /= eclipse_rate_multiplier
	# The pseudo-infinite squeeze compounds on top, then the party pressure
	# divides last so a bigger co-op party stays proportionally faster.
	interval = maxf(interval * endless_interval_factor(), min_interval)
	return interval / (1.0 + coop_rate_per_extra_player * _coop_extra_alive())


## The party as configured in the lobby: what a whole run is sized for
## (boss HP), regardless of who happens to be down right now.
func _coop_extra() -> float:
	return float(maxi(Coop.player_count - 1, 0))


## The party actually on its feet. A downed raider leaves the "player"
## group until revived (see coop.gd), so per-tick pressure — stream rate,
## fresh-spawn HP, horde size — follows the fight instead of pinning the
## last survivor against four players' worth of horde while they revive.
func _coop_extra_alive() -> float:
	return float(maxi(Coop.alive_player_count(get_tree()) - 1, 0))


## Late-ramp factors for a spawn landing right now (1.0 before the ramp).
func late_hp_factor() -> float:
	return 1.0 + late_hp_per_minute * maxf(_minutes() - late_ramp_start_minute, 0.0)


func late_damage_factor() -> float:
	return 1.0 + late_damage_per_minute * maxf(_minutes() - late_ramp_start_minute, 0.0)


func late_xp_factor() -> float:
	return 1.0 + late_xp_per_minute * maxf(_minutes() - late_ramp_start_minute, 0.0)


## --- sky events (WorldDirector group hook) ----------------------------------

## Blood moon: spawns hit harder and half arrive as berserkers. Eclipse:
## faster stream, tougher spawns, some arrive as shades. "" clears.
func set_sky_event(kind: String, duration: float) -> void:
	_sky_kind = kind
	_sky_left = duration if not kind.is_empty() else 0.0


func _sky_hp_factor() -> float:
	return eclipse_hp_multiplier if _sky_kind == "eclipse" else 1.0


func _sky_damage_factor() -> float:
	return blood_moon_damage_multiplier if _sky_kind == "blood_moon" else 1.0


func _apply_sky_variant(enemy: EnemyBase) -> void:
	match _sky_kind:
		"blood_moon":
			if randf() < blood_moon_berserker_chance:
				enemy.apply_variant("berserker")
		"eclipse":
			if randf() < eclipse_shade_chance:
				enemy.apply_variant("shade")


## --- hordes -----------------------------------------------------------------

func _next_horde_time() -> float:
	if _hordes_fired < horde_minutes.size():
		return horde_minutes[_hordes_fired] * 60.0
	var last := horde_minutes[horde_minutes.size() - 1] if not horde_minutes.is_empty() else 0.0
	return (last + horde_repeat_minutes * float(_hordes_fired - horde_minutes.size() + 1)) * 60.0


func _tick_hordes(delta: float) -> void:
	if _horde_waves_left > 0:
		_horde_wave_timer -= delta
		if _horde_wave_timer <= 0.0:
			# Anchor FIRST: with the whole party downed there is nothing to
			# surround, and spending the wave anyway used to shrink an
			# announced horde behind the player's back. Retry next tick.
			var anchor := Coop.random_player(get_tree())
			if anchor == null:
				return
			_horde_wave_timer = horde_wave_gap
			_horde_waves_left -= 1
			spawn_pressure_burst(anchor.global_position, _horde_wave_size, false, true)
		return
	if RunState.stage_time < _next_horde_time():
		return
	_hordes_fired += 1
	var size := int((float(horde_base_size) + horde_size_per_minute * _minutes())
			* (1.0 + RunState.difficulty_bonus) * (1.0 + 0.3 * _coop_extra_alive())
			* (endless_horde_mult if RunState.stage_cleared else 1.0))
	_horde_wave_size = maxi(ceili(float(size) / float(maxi(horde_waves, 1))), 1)
	_horde_waves_left = horde_waves
	_horde_wave_timer = 0.0
	get_tree().call_group("boss_ui", "announce", horde_warning_text)
	# The waves are what actually gets requested: rounding the wave size up
	# means the total can exceed the raw `size` by up to horde_waves - 1,
	# and the log is the soaks' only view of the horde.
	print("Horde: %d enemies in %d waves at %.1fs" % [
			_horde_wave_size * horde_waves, horde_waves, RunState.stage_time])


func current_count_per_tick() -> int:
	return base_count_per_tick + int(_minutes() * extra_count_per_minute)


## The phase table this arena's preset selects.
func active_phases() -> Array[Dictionary]:
	match phase_preset:
		PhasePreset.DUNES:
			return DUNES_PHASES
		PhasePreset.MARSH:
			return MARSH_PHASES
		_:
			return FOREST_PHASES


## Weighted pick from the phase active at the current run minute.
func pick_spawn_scene() -> PackedScene:
	var minutes := _minutes()
	var phases := active_phases()
	var weights: Dictionary = phases[0]["weights"]
	for phase: Dictionary in phases:
		var from_minute: float = phase["from_minute"]
		if minutes >= from_minute:
			weights = phase["weights"]
	var total := 0.0
	for kind: String in weights:
		var weight: float = weights[kind]
		total += weight
	var roll := randf() * total
	for kind: String in weights:
		var weight: float = weights[kind]
		roll -= weight
		if roll <= 0.0:
			return _scene_for(kind)
	return grunt_scene


## Chance that a fresh spawn is promoted to an elite: zero before
## elite_start_minute, then a linear ramp that caps at elite_full_minute.
## Run-wide difficulty (demonic altars, Tome of Peril) multiplies it —
## more elites is both the threat and the reward (5x XP, orbs, points).
## --- time stop (iteration 53) -----------------------------------------------
## Tiempo detenido freezes the horde and leaves the party free. The
## spawner owns it because it is the one node that already knows about
## every enemy: bodies, bosses and the bolts in flight.
##
## A frozen body is PROCESS_MODE_DISABLED with its velocity stored and
## zeroed. Zeroing matters twice: a disabled CharacterBody3D keeps the
## velocity it had (so the probe's airborne detector would still read it
## rising), and restoring it on thaw is what keeps a charging enemy from
## teleporting the distance it "owed".
##
## It also goes NON-SOLID (collision_layer 0) for the length of the
## freeze. "Enemies frozen, players free" has to mean free to MOVE, and a
## disabled body cannot be pushed: eighty of them closed around a raider
## would be eighty statues welding it in place, turning the power-up that
## should rescue you into the one that traps you. Weapons find their
## targets through the "enemies" GROUP and a distance test, never through
## collision layers (see WeaponBase.enemies_in_disc), so a non-solid frozen
## enemy is still perfectly damageable: you walk through the horde and keep
## hitting it.
##
## Pooled enemy bolts get a FLAG instead (EnemyBolt.frozen): NodePool
## snapshots is_physics_processing() on release and restores it on
## acquire, so a bolt frozen with set_physics_process(false) would come
## back from the pool inert forever.

## Live freeze: instance id -> body, so a body freed mid-freeze is simply
## missing on thaw instead of being a dangling reference.
var _frozen: Dictionary[int, Node3D] = {}
var _frozen_velocity: Dictionary[int, Vector3] = {}
## Collision layer each frozen body had, restored on thaw (an enemy whose
## layer stayed 0 would be permanently walk-through).
var _frozen_layer: Dictionary[int, int] = {}
var _freeze_left: float = 0.0


## Group hook (PowerUps calls it through "enemy_spawner"). Refreshes to
## the longer of the two windows, like every other timed effect here.
func freeze_enemies(duration: float) -> void:
	_freeze_left = maxf(_freeze_left, duration)
	_freeze_new_bodies()


func is_frozen() -> bool:
	return _freeze_left > 0.0


## Bodies currently held frozen (the soak samples them).
func frozen_bodies() -> Array[Node3D]:
	var bodies: Array[Node3D] = []
	for id: int in _frozen:
		var body := _frozen[id]
		if is_instance_valid(body):
			bodies.append(body)
	return bodies


func _tick_freeze(delta: float) -> void:
	if _freeze_left <= 0.0:
		return
	_freeze_left -= delta
	if _freeze_left > 0.0:
		# Anything that spawned (or was summoned) during the freeze is
		# frozen too: a horde that keeps walking in through stopped time
		# is not stopped time.
		_freeze_new_bodies()
		return
	_thaw_all()


func _freeze_new_bodies() -> void:
	for group: StringName in [&"enemies", &"boss"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body == null or not body.is_inside_tree():
				continue
			var id := body.get_instance_id()
			if _frozen.has(id):
				continue
			_frozen[id] = body
			var character := body as CharacterBody3D
			if character != null:
				_frozen_velocity[id] = character.velocity
				character.velocity = Vector3.ZERO
			var collider := body as CollisionObject3D
			if collider != null:
				_frozen_layer[id] = collider.collision_layer
				collider.collision_layer = 0
			body.process_mode = Node.PROCESS_MODE_DISABLED
	for node: Node in get_tree().get_nodes_in_group(&"enemy_projectiles"):
		node.set("frozen", true)


func _thaw_all() -> void:
	for id: int in _frozen:
		var body := _frozen[id]
		if not is_instance_valid(body):
			continue
		body.process_mode = Node.PROCESS_MODE_INHERIT
		var character := body as CharacterBody3D
		if character != null:
			character.velocity = _frozen_velocity.get(id, Vector3.ZERO)
		var collider := body as CollisionObject3D
		if collider != null and _frozen_layer.has(id):
			collider.collision_layer = _frozen_layer[id]
	_frozen.clear()
	_frozen_velocity.clear()
	_frozen_layer.clear()
	for node: Node in get_tree().get_nodes_in_group(&"enemy_projectiles"):
		node.set("frozen", false)
	get_tree().call_group("hud", "announce", "El tiempo vuelve a correr.")


## --- power-up drops (iteration 53) ------------------------------------------

## True when this death should drop a power-up. `killer` is the raider the
## roll belongs to (nearest, like the points payout), so their «Fortuna
## menor» is what moves the odds. BONK_POWERUP_BOOST multiplies the whole
## thing for acceptance soaks — a 0.4% base needs thousands of kills to
## show up otherwise, which no soak has time for.
func roll_powerup_drop(killer: Node, shiny: bool) -> bool:
	var chance := base_powerup_drop_chance * _powerup_boost
	var stats := PlayerStats.find_in(killer) if killer != null else null
	if stats != null:
		chance *= 1.0 + stats.powerup_drop_chance / 100.0
	if shiny:
		chance *= shiny_powerup_drop_scale
	return randf() < chance


## Drops one pickup at `at`. THE spawn door for power-ups on the ground:
## the star sighting comes through here too, so the stage parenting and
## the group membership are written once.
func spawn_powerup_pickup(at: Vector3, powerup_id: String) -> Node3D:
	if powerup_id.is_empty() or powerup_pickup_scene == null:
		return null
	var pickup := powerup_pickup_scene.instantiate() as PowerUpPickup
	if pickup == null:
		return null
	pickup.setup(powerup_id)
	# Stage-scoped, like everything else dropped into the world: the swap
	# frees it with the rest of the stage instead of carrying it along.
	RunRoot.stage_parent(get_tree()).add_child(pickup)
	pickup.global_position = at
	print("Power-up dropped: %s" % powerup_id)
	return pickup


## Multiplier read once from BONK_POWERUP_BOOST (test switch; 1.0 in a
## normal run). Read at _ready, not per roll: this is on the death path.
var _powerup_boost: float = 1.0

const POWERUP_BOOST_ENV := "BONK_POWERUP_BOOST"
## What BONK_POWERUP_BOOST=1 is worth. Chosen so a 360 s soak reliably
## produces a handful of drops without burying the map in them.
const POWERUP_BOOST_SCALE: float = 50.0


## Harness hook, reached through the "enemy_spawner" group: makes EVERY
## spawn roll shiny. Test-only (ArenaProbe under BONK_ELITE_BOOST=1) — the
## shiny path and the body crowding it causes would otherwise need twelve
## minutes of ramp to show up in a soak, and elite_chance() is capped at
## ELITE_CHANCE_CAP by design so no export can reach 1.0. Nothing in the
## game calls this.
func force_elite_spawns(on: bool) -> void:
	_force_elite_spawns = on


func elite_chance() -> float:
	var minutes := _minutes()
	if minutes < elite_start_minute:
		return 0.0
	# Both ends are per-instance exports: an arena that sets them equal
	# would divide by zero and poison the whole ramp with NAN, which reads
	# as "elites never roll again" rather than as a configuration error.
	var span := maxf(elite_full_minute - elite_start_minute, 0.001)
	var ramp := clampf((minutes - elite_start_minute) / span, 0.0, 1.0)
	# Demonic pacts sell elite odds directly (iteration 47), on top of the
	# difficulty tilt every source already feeds.
	return minf(lerpf(elite_start_chance, elite_full_chance, ramp)
			* (1.0 + RunState.difficulty_bonus) + RunState.elite_chance_bonus,
			ELITE_CHANCE_CAP)


## Temporary enemy buff (roulette "frenzy"): fresh spawns scale HP/damage
## by `multiplier` for `duration` seconds. Group hook (enemy_spawner).
var _temp_buff_multiplier: float = 1.0
var _temp_buff_left: float = 0.0


func apply_temp_enemy_buff(multiplier: float, duration: float) -> void:
	# Refresh like EnemyBase.apply_poison: the strongest multiplier and the
	# longest timer both win. Overwriting the multiplier while keeping the
	# longer timer let a weak second roll defuse a strong first one.
	var live := _temp_buff_multiplier if _temp_buff_left > 0.0 else 1.0
	_temp_buff_multiplier = maxf(live, maxf(multiplier, 1.0))
	_temp_buff_left = maxf(_temp_buff_left, duration)
	get_tree().call_group("boss_ui", "announce", "¡La horda crece con una fuerza antinatural!")


func temp_enemy_buff() -> float:
	return _temp_buff_multiplier if _temp_buff_left > 0.0 else 1.0


func _scene_for(kind: String) -> PackedScene:
	match kind:
		"skirmisher":
			return skirmisher_scene
		"tank":
			return tank_scene
		"sunspitter":
			return sunspitter_scene
		"burrower":
			return burrower_scene
		_:
			return grunt_scene


func _spawn_one() -> void:
	# Co-op: ring around a RANDOM alive player, so the horde pressure
	# spreads across a split-up party instead of piling on one raider.
	var player := Coop.random_player(get_tree())
	if player == null:
		return
	_make_enemy_at(_ring_position(player))


## One enemy, placed, scaled and rolled for elite. `scene` overrides the
## phase-table draw (boss summons bring their own kind). Returns null when
## there is no scene or its root is not an EnemyBase, so a caller in a loop
## skips that unit instead of losing the rest.
func _make_enemy_at(pos: Vector3, force_elite: bool = false,
		scene_override: PackedScene = null) -> EnemyBase:
	# THE gate for every spawn path: ring spawns, hordes, surges, boss
	# summons and the WorldDirector's packs all land here, so the clearance
	# rule cannot be forgotten by a new caller. The position samplers below
	# already prefer clear points; this is what happens when none exists.
	if not _has_player_clearance(pos):
		_register_clearance_skip()
		return null
	var scene := scene_override if scene_override != null else pick_spawn_scene()
	if scene == null:
		return null
	var node := scene.instantiate()
	var enemy := node as EnemyBase
	if enemy == null:
		node.free()
		push_warning("EnemySpawner: spawn scene root does not extend EnemyBase.")
		return null
	add_child(enemy)
	enemy.global_position = pos
	_scale_fresh_spawn(enemy)
	if force_elite or _force_elite_spawns or randf() < elite_chance():
		enemy.make_elite()
	return enemy


## Every regular spawn's stat scaling in one place: map tier x late ramp x
## co-op HP x run-wide difficulty (iteration 39: Tome of Peril / demonic
## altars — tougher AND richer, the XP side via RunState's share).
func _scale_fresh_spawn(enemy: EnemyBase) -> void:
	var difficulty := (1.0 + RunState.difficulty_bonus) * temp_enemy_buff()
	enemy.apply_tier_scaling(
			lap_hp_factor() * endless_hp_factor() * late_hp_factor() * difficulty
					* _sky_hp_factor()
					* (1.0 + coop_hp_per_extra_player * _coop_extra_alive()),
			lap_damage_factor() * endless_damage_factor() * late_damage_factor()
					* difficulty * _sky_damage_factor(),
			lap_xp_factor() * late_xp_factor())
	# Speed is the pseudo-infinite ramp's own channel: apply_tier_scaling
	# deliberately covers HP, damage and payout only, and a body that also
	# gets faster is what makes "stayed too long" read as a mistake.
	enemy.move_speed *= endless_speed_factor()
	_apply_sky_variant(enemy)


## Summon hook for anything that calls in bodies of its OWN kind (the
## Rotking's waves), reached through the "enemy_spawner" group so the
## summoner never holds a reference to this node. Places one `scene` at
## each of `positions` and runs every one of them through the SAME scaling
## a ring spawn gets — map tier, late ramp, run difficulty, temporary buff,
## co-op HP, sky variant — plus the usual elite roll. Summoning by hand
## skipped all of that, so a tier-3 minute-15 boss called in tier-1
## minute-0 minions. Returns the bodies that actually arrived.
func spawn_minions(scene: PackedScene, positions: Array[Vector3],
		force_elites: bool = false) -> Array[EnemyBase]:
	var spawned: Array[EnemyBase] = []
	if scene == null:
		return spawned
	for pos: Vector3 in positions:
		var minion := _make_enemy_at(pos, force_elites, scene)
		if minion != null:
			spawned.append(minion)
	return spawned


## Charge Shrine pressure hook (called via the "enemy_spawner" group): an
## immediate burst of current-phase enemies in a ring around `center`, on
## top of the normal cadence but still respecting max_active (plus the
## pressure_overflow headroom, or horde_overflow for hordes). The usual
## elite roll applies, so late-run surges stay threatening.
## force_elites (WorldDirector's elite-pack event): every burst spawn is
## promoted, instead of rolling the usual chance.
## Returns how many bodies actually arrived, so a caller can keep quiet
## about a bounty the cap swallowed.
func spawn_pressure_burst(center: Vector3, count: int, force_elites: bool = false,
		horde: bool = false) -> int:
	if Coop.alive_player_count(get_tree()) <= 0:
		return 0
	var cap := max_active + (horde_overflow if horde else pressure_overflow)
	var budget := mini(count, cap - _live_enemy_count())
	var spawned := 0
	for i in budget:
		# Even ring slots with jitter, so a burst surrounds instead of clumping.
		var angle := TAU * float(i) / float(budget) \
				+ randf_range(-BURST_ANGLE_JITTER, BURST_ANGLE_JITTER)
		# Blocked slots rotate around the SURGE band, never out to the
		# player's far ring: an altar next to a mask wall must still feel
		# like "hold this spot under pressure".
		var pos := _band_position(center, surge_min_radius, surge_max_radius, angle)
		pos.y = _ground_height(pos) + SPAWN_GROUND_OFFSET
		if _make_enemy_at(pos, force_elites) != null:
			spawned += 1
	return spawned


## Boss timetable, read off RunState.stage_time (iteration 50): a fresh
## spawner arrives with every arena, so its _boss_spawned / _elder_spawned
## / _repeat_bosses_spawned flags start clean per stage, and the clock they
## compare against has to be the stage's, not the run's. Each entry fires once per run.
func _tick_boss_schedule() -> void:
	if boss_scene == null:
		return
	# Flag only on a boss that actually arrived: _spawn_boss aborts when
	# the whole party is downed (no ring anchor), and a slot marked as
	# spent would silently drop that boss for the rest of the run.
	# Keyed to the STAGE clock (iteration 50), not the run clock: every map
	# of a run gets its own boss at minute 5 and its own Elder at 11. On
	# the run clock, stage 2 would have been born with both slots expired.
	if not _boss_spawned and RunState.stage_time >= boss_spawn_minute * 60.0:
		_boss_spawned = _spawn_boss(1.0) != null
	if not _elder_spawned and RunState.stage_time >= elder_spawn_minute * 60.0:
		var elder := _spawn_boss(elder_stat_multiplier, elder_title)
		_elder_spawned = elder != null
		if elder != null:
			_watch_stage_boss(elder)
	# Endless clock (iteration 42): bosses keep returning, each stronger.
	if _elder_spawned and boss_repeat_minutes > 0.0:
		var due := (elder_spawn_minute
				+ boss_repeat_minutes * float(_repeat_bosses_spawned + 1)) * 60.0
		if RunState.stage_time >= due:
			var rank := _repeat_bosses_spawned + 1
			if _spawn_boss(elder_stat_multiplier * pow(boss_repeat_growth, float(rank)),
					boss_repeat_title_template % [elder_title, rank]) != null:
				_repeat_bosses_spawned = rank


## The Elder is THE stage boss: its death is half of the stage gate.
## Bound to that one instance rather than to the "boss died" counter,
## because the recurring bosses after it must not re-open a gate.
func _watch_stage_boss(boss: BossBase) -> void:
	var health := Health.find_in(boss)
	if health == null:
		RunState.stage_boss_dead = true
		return
	health.died.connect(_on_stage_boss_died, CONNECT_ONE_SHOT)


func _on_stage_boss_died() -> void:
	RunState.stage_boss_dead = true
	# One-line log (RunManager convention) for headless soaks.
	print("Stage boss slain: %s at %.1fs" % [elder_title, RunState.stage_time])


## The boss that entered the arena, or null on every abort, so the caller
## can retry the slot on a later tick. Returns the instance (iteration 50)
## because the Elder's death is what opens the stage gate, and the caller
## has to be able to hook that one body's Health.
func _spawn_boss(stat_multiplier: float, title_override: String = "") -> BossBase:
	var player := Coop.random_player(get_tree())
	if player == null:
		return null
	# Placed BEFORE the boss exists: the schedule only marks a slot spent on
	# a boss that actually arrived, so a ring with no clear point retries on
	# the next tick instead of announcing a boss that never came.
	var at := _ring_position(player)
	if not _has_player_clearance(at):
		_register_clearance_skip()
		return null
	var node := boss_scene.instantiate()
	var boss := node as BossBase
	if boss == null:
		node.free()
		push_warning("EnemySpawner: boss scene root does not extend BossBase.")
		return null
	if not title_override.is_empty():
		# Before add_child: the boss announces its title to the HUD in _ready.
		boss.boss_title = title_override
	add_child(boss)
	boss.global_position = at
	# Elder rematch factor and map-tier factor land in ONE apply_tier call, so
	# tier_body_scale applies once per boss and a baseline boss (every factor
	# 1.0) stays exactly baseline. The three channels are deliberately
	# different — folding them into a single number let the co-op HP factor
	# scale the boss's DAMAGE too, against this spawner's own co-op contract
	# ("Damage is deliberately NOT scaled"), and paid the difficulty share of
	# XP twice:
	#   HP     — rematch x tier x difficulty x party size. A boss is one long
	#            fight, sized for the party that queued for it, not for
	#            whoever happens to be standing at the second it spawns.
	#   damage — the same WITHOUT the party factor: four bodies already soak
	#            more hits, so scaling the hits as well double-charges them.
	#   payout — rematch x tier only: RunState.difficulty_xp_multiplier()
	#            already pays the difficulty share when the gems are collected.
	var payout_multiplier := stat_multiplier * lap_xp_factor()
	var damage_multiplier := stat_multiplier * lap_damage_factor() \
			* (1.0 + RunState.difficulty_bonus)
	var hp_multiplier := stat_multiplier * lap_hp_factor() \
			* (1.0 + RunState.difficulty_bonus) \
			* (1.0 + coop_boss_hp_per_extra_player * _coop_extra())
	# is_equal_approx, not "> 1.0": a factor can legitimately land below 1.0
	# and a plain greater-than dropped that silently.
	if not (is_equal_approx(hp_multiplier, 1.0) and is_equal_approx(damage_multiplier, 1.0)
			and is_equal_approx(payout_multiplier, 1.0)):
		boss.apply_tier(hp_multiplier, damage_multiplier, payout_multiplier)
	_bosses_alive += 1
	var health := Health.find_in(boss)
	if health != null:
		health.died.connect(_on_boss_died)
	get_tree().call_group("boss_ui", "announce", boss_warning_text)
	# One-line log (RunManager convention) so headless soaks can confirm
	# the boss timetable fired.
	print("Boss spawned: %s at %.1fs" % [boss.boss_title, RunState.stage_time])
	return boss


func _on_boss_died() -> void:
	_bosses_alive = maxi(_bosses_alive - 1, 0)
	_relief_timer = boss_relief_duration
	# Meta counter for boss-kill quests; persisted at the run-end save.
	SaveData.bump("bosses_killed")


## Ring position around the player at spawn distance, dropped onto the ground.
func _ring_position(player: Node3D) -> Vector3:
	var pos := _band_position(player.global_position, min_radius, max_radius, randf() * TAU)
	pos.y = _ground_height(pos) + SPAWN_GROUND_OFFSET
	return pos


## A walkable point in the [min_r, max_r] band around `center`, starting
## from `angle` and rotating a further RING_ATTEMPTS-th of a turn per try.
## Candidates that fall off the arena plate are RETRIED, not clamped:
## clamping X and Z independently collapsed every angle onto the same
## corner whenever the anchor hugged an edge, so all tries checked the one
## cell. The last try stands even if blocked (climbers get out), so a
## spawn is never silently dropped.
func _band_position(center: Vector3, min_r: float, max_r: float, angle: float) -> Vector3:
	var pos := center
	for attempt in RING_ATTEMPTS:
		var heading := angle + TAU * float(attempt) / float(RING_ATTEMPTS)
		pos = center + Vector3(cos(heading), 0.0, sin(heading)) * randf_range(min_r, max_r)
		if absf(pos.x) > arena_half_extent or absf(pos.z) > arena_half_extent:
			continue
		# Clearance is part of "is this a usable point", not a separate
		# pass: rotating around the band is exactly how a blocked slot gets
		# resolved, and a raider standing in the band is a blocked slot.
		if _walkable(pos) and _has_player_clearance(pos):
			break
	pos.x = clampf(pos.x, -arena_half_extent, arena_half_extent)
	pos.z = clampf(pos.z, -arena_half_extent, arena_half_extent)
	return pos


## Drops the spawn point onto whatever world geometry (layer 1) is below it —
## forest floor, boulder, platform deck — so a ring position that lands on a
## Hollow Woods prop never embeds an enemy inside it. Tree canopies carry no
## collision, so under-canopy spawns still hit the floor. Falls back to the
## flat-floor height if the ray somehow misses everything.
func _ground_height(pos: Vector3) -> float:
	# Spans the whole relief (iteration 51): the old 12 m start sat under
	# a mesa on a hill, and the -1 end above a hollow's floor.
	var terrain := Terrain.find(get_tree())
	var top := GROUND_PROBE_HEIGHT
	var bottom := -1.0
	if terrain != null:
		top = terrain.max_height + PROBE_HEADROOM
		bottom = terrain.min_height - PROBE_UNDERSHOOT
	var ray := PhysicsRayQueryParameters3D.create(
			Vector3(pos.x, top, pos.z), Vector3(pos.x, bottom, pos.z), 1)
	# Raiders share layer 1 with the world, so the WHOLE party is excluded:
	# with only the ring anchor excluded, a spawn drawn over a co-op
	# partner used their head as "ground" and dropped onto them.
	var excluded: Array[RID] = []
	for node: Node in Coop.alive_players(get_tree()):
		var body := node as CollisionObject3D
		if body != null:
			excluded.append(body.get_rid())
	ray.exclude = excluded
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		# The TERRAIN height, not 0: zero is a real height on a heightmap,
		# so the old fallback spawned bodies inside a hill or under one.
		return terrain.height_at(pos.x, pos.z) if terrain != null else 0.0
	var hit_position: Vector3 = hit["position"]
	return hit_position.y
