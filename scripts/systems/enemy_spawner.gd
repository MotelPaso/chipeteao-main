extends Node3D
## Spawns enemies on a timer in a ring around the player, off-screen-ish.
## Difficulty ramps with elapsed run time: the interval shrinks and the
## per-tick count grows (GDD 6: swarms scale over the run timer), while
## SPAWN_PHASES only decides WHAT spawns — grunts first, skirmishers from
## minute 2, tanks from minute 5 — and an elite roll (chance ramping from
## minute 3) can promote any spawn. Spawned enemies are added as children,
## so the active count is just child count. Also owns the boss timetable:
## the Rotking at boss_spawn_minute and its Elder at elder_spawn_minute,
## with eased regular spawns while a boss lives and a short relief window
## after one dies.

## Time-phased spawn mix. Each entry activates at from_minute and stays
## active until a later entry takes over; weights are relative within the
## phase. Kinds map to the exported scenes in _scene_for().
const SPAWN_PHASES: Array[Dictionary] = [
	{"from_minute": 0.0, "weights": {"grunt": 1.0}},
	{"from_minute": 2.0, "weights": {"grunt": 0.8, "skirmisher": 0.2}},
	{"from_minute": 5.0, "weights": {"grunt": 0.7, "skirmisher": 0.2, "tank": 0.1}},
	{"from_minute": 8.0, "weights": {"grunt": 0.55, "skirmisher": 0.25, "tank": 0.2}},
]

@export var grunt_scene: PackedScene
@export var skirmisher_scene: PackedScene
@export var tank_scene: PackedScene
@export var max_active: int = 80
@export_group("Spawn Ring")
@export var min_radius: float = 18.0
@export var max_radius: float = 25.0
## Half-size of the floor plate, minus a margin, so ring spawns near an
## arena edge still land on the floor.
@export var arena_half_extent: float = 48.0
@export_group("Difficulty Ramp")
@export var start_interval: float = 2.5
@export var min_interval: float = 0.4
@export var interval_shrink_per_minute: float = 0.35
@export var base_count_per_tick: int = 1
@export var extra_count_per_minute: float = 0.5
@export_group("Elites")
@export var elite_start_minute: float = 3.0
@export var elite_full_minute: float = 12.0
@export var elite_start_chance: float = 0.02
@export var elite_full_chance: float = 0.10
@export_group("Boss")
@export var boss_scene: PackedScene
## Run minute the Rotking arrives, and the minute its stronger Elder
## rematch arrives (GDD 6: the biome boss line punctuates the run).
@export var boss_spawn_minute: float = 5.0
@export var elder_spawn_minute: float = 11.0
@export var elder_stat_multiplier: float = 1.8
@export var elder_title: String = "Rotking Elder"
## While a boss lives, regular spawns ease off by this interval factor so
## the fight reads...
@export var boss_alive_interval_multiplier: float = 1.3
## ...and a boss death buys a breather: interval multiplied by this for
## boss_relief_duration seconds.
@export var boss_relief_interval_multiplier: float = 2.0
@export var boss_relief_duration: float = 15.0
@export var boss_warning_text: String = "A monstrous presence approaches..."
@export_group("Pressure Surge")
## Ring band around a requesting shrine where surge enemies land
## (spawn_pressure_burst, called by the Charge Shrine via group).
@export var surge_min_radius: float = 7.0
@export var surge_max_radius: float = 10.0

## Elapsed run time in seconds; the HUD run timer will read this later.
var run_time: float = 0.0

var _spawn_timer: float = 0.0  # starts due, so the action begins immediately
var _boss_spawned: bool = false
var _elder_spawned: bool = false
var _bosses_alive: int = 0
var _relief_timer: float = 0.0


func _ready() -> void:
	# Shrines reach the spawner through this group, never by node path.
	add_to_group("enemy_spawner")


func _physics_process(delta: float) -> void:
	run_time += delta
	_relief_timer = maxf(_relief_timer - delta, 0.0)
	_tick_boss_schedule()
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = current_interval()
	var budget := mini(current_count_per_tick(), max_active - get_child_count())
	for i in budget:
		_spawn_one()


func current_interval() -> float:
	var minutes := run_time / 60.0
	var interval := maxf(start_interval - interval_shrink_per_minute * minutes, min_interval)
	if _bosses_alive > 0:
		interval *= boss_alive_interval_multiplier
	elif _relief_timer > 0.0:
		interval *= boss_relief_interval_multiplier
	return interval


func current_count_per_tick() -> int:
	var minutes := run_time / 60.0
	return base_count_per_tick + int(minutes * extra_count_per_minute)


## Weighted pick from the phase active at the current run_time.
func pick_spawn_scene() -> PackedScene:
	var minutes := run_time / 60.0
	var weights: Dictionary = SPAWN_PHASES[0]["weights"]
	for phase: Dictionary in SPAWN_PHASES:
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
func elite_chance() -> float:
	var minutes := run_time / 60.0
	if minutes < elite_start_minute:
		return 0.0
	var ramp := clampf(
			(minutes - elite_start_minute) / (elite_full_minute - elite_start_minute),
			0.0, 1.0)
	return lerpf(elite_start_chance, elite_full_chance, ramp)


func _scene_for(kind: String) -> PackedScene:
	match kind:
		"skirmisher":
			return skirmisher_scene
		"tank":
			return tank_scene
		_:
			return grunt_scene


func _spawn_one() -> void:
	var scene := pick_spawn_scene()
	if scene == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var node := scene.instantiate()
	var enemy := node as EnemyBase
	if enemy == null:
		node.free()
		push_warning("EnemySpawner: spawn scene root does not extend EnemyBase.")
		return
	add_child(enemy)
	enemy.global_position = _ring_position(player)
	if randf() < elite_chance():
		enemy.make_elite()


## Charge Shrine pressure hook (called via the "enemy_spawner" group): an
## immediate burst of current-phase enemies in a ring around `center`, on
## top of the normal cadence but still respecting max_active. The usual
## elite roll applies, so late-run surges stay threatening.
func spawn_pressure_burst(center: Vector3, count: int) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var budget := mini(count, max_active - get_child_count())
	for i in budget:
		var scene := pick_spawn_scene()
		if scene == null:
			return
		var node := scene.instantiate()
		var enemy := node as EnemyBase
		if enemy == null:
			node.free()
			return
		add_child(enemy)
		# Even ring slots with jitter, so a burst surrounds instead of clumping.
		var angle := TAU * float(i) / float(budget) + randf_range(-0.35, 0.35)
		var pos := center + Vector3(cos(angle), 0.0, sin(angle)) \
				* randf_range(surge_min_radius, surge_max_radius)
		pos.x = clampf(pos.x, -arena_half_extent, arena_half_extent)
		pos.z = clampf(pos.z, -arena_half_extent, arena_half_extent)
		pos.y = _ground_height(pos, player) + 0.05
		enemy.global_position = pos
		if randf() < elite_chance():
			enemy.make_elite()


## Boss timetable, read off RunState.run_time — the canonical run clock the
## HUD timer and victory check already use — so the schedule can never
## drift from what the player sees. Each entry fires once per run.
func _tick_boss_schedule() -> void:
	if boss_scene == null:
		return
	if not _boss_spawned and RunState.run_time >= boss_spawn_minute * 60.0:
		_boss_spawned = true
		_spawn_boss(1.0)
	if not _elder_spawned and RunState.run_time >= elder_spawn_minute * 60.0:
		_elder_spawned = true
		_spawn_boss(elder_stat_multiplier, elder_title)


func _spawn_boss(stat_multiplier: float, title_override: String = "") -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var node := boss_scene.instantiate()
	var boss := node as Rotking
	if boss == null:
		node.free()
		push_warning("EnemySpawner: boss scene root does not extend Rotking.")
		return
	if not title_override.is_empty():
		# Before add_child: the boss announces its title to the HUD in _ready.
		boss.boss_title = title_override
	add_child(boss)
	boss.global_position = _ring_position(player)
	if stat_multiplier > 1.0:
		boss.apply_tier(stat_multiplier)
	# Curse Shrine payoff: the next boss consumes every banked stack and
	# spawns harder but richer (multipliers exported on the boss).
	var curse_stacks := RunState.consume_curses()
	if curse_stacks > 0:
		boss.apply_curse(curse_stacks)
		print("Boss cursed: %d stack(s)" % curse_stacks)
	_bosses_alive += 1
	var health := Health.find_in(boss)
	if health != null:
		health.died.connect(_on_boss_died)
	get_tree().call_group("boss_ui", "announce", boss_warning_text)
	# One-line log (RunManager convention) so headless soaks can confirm
	# the boss timetable fired.
	print("Boss spawned: %s at %.1fs" % [boss.boss_title, RunState.run_time])


func _on_boss_died() -> void:
	_bosses_alive = maxi(_bosses_alive - 1, 0)
	_relief_timer = boss_relief_duration
	# Meta counter for boss-kill quests; persisted at the run-end save.
	SaveData.bump("bosses_killed")


## Ring position around the player at spawn distance, clamped to the arena
## and dropped onto the ground.
func _ring_position(player: Node3D) -> Vector3:
	var angle := randf() * TAU
	var pos := player.global_position \
			+ Vector3(cos(angle), 0.0, sin(angle)) * randf_range(min_radius, max_radius)
	pos.x = clampf(pos.x, -arena_half_extent, arena_half_extent)
	pos.z = clampf(pos.z, -arena_half_extent, arena_half_extent)
	pos.y = _ground_height(pos, player) + 0.05
	return pos


## Drops the spawn point onto whatever world geometry (layer 1) is below it —
## forest floor, boulder, platform deck — so a ring position that lands on a
## Hollow Woods prop never embeds an enemy inside it. Tree canopies carry no
## collision, so under-canopy spawns still hit the floor. Falls back to the
## flat-floor height if the ray somehow misses everything.
func _ground_height(pos: Vector3, player: Node3D) -> float:
	var ray := PhysicsRayQueryParameters3D.create(
			Vector3(pos.x, 12.0, pos.z), Vector3(pos.x, -1.0, pos.z), 1)
	var player_body := player as CollisionObject3D
	if player_body != null:
		# The player is also on layer 1; never spawn an enemy on their head.
		var excluded: Array[RID] = [player_body.get_rid()]
		ray.exclude = excluded
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return 0.0
	var hit_position: Vector3 = hit["position"]
	return hit_position.y
