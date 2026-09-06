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
const PortalShrineScript := preload("res://scripts/world/portal_shrine.gd")

## Timed world events as catalog rows (project convention: content is
## data). `weight` is relative; `method` runs the event. A new event is
## one row plus its method — no index arithmetic to keep in sync.
const EVENT_LIBRARY: Array[Dictionary] = [
	{"id": "supply_chest", "weight": 1.0, "method": &"_event_supply_chest"},
	{"id": "elite_pack", "weight": 1.0, "method": &"_event_elite_pack"},
	{"id": "essence_rift", "weight": 1.0, "method": &"_event_essence_rift"},
	{"id": "charge_altar", "weight": 1.6, "method": &"_event_charge_altar"},
	{"id": "demonic_altar", "weight": 0.5, "method": &"_event_demonic_altar"},
	{"id": "spring", "weight": 0.7, "method": &"_event_spring"},
]

## Rejection-sampling budget for a clear POI spot, and for the ring sample
## an event point gets before it falls back to the run-start sampler.
const CLEAR_POINT_ATTEMPTS: int = 60
const EVENT_POINT_ATTEMPTS: int = 24
## The event ground probe starts this high — above every arena platform
## and mesa — and ends just below the floor plate.
const GROUND_PROBE_HEIGHT: float = 20.0
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
@export_group("Altars (iteration 41)")
## Recurring altars: seconds an untouched spawned altar/spring waits before leaving.
@export var altar_idle_lifetime: float = 45.0
@export var spring_idle_lifetime: float = 60.0
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
@export var sky_event_min_gap: float = 150.0
@export var sky_event_duration: float = 45.0
@export var full_moon_duration: float = 40.0
@export var full_moon_xp_bonus: float = 50.0
@export var full_moon_luck_bonus: float = 30.0

## RAW half-extent of the arena plate, as published by the "arena_bounds"
## node (scatter.gd's own default is 80.0); bounds_margin is subtracted at
## each use, so this must not be a pre-margined number.
var _arena_half_extent: float = 80.0
## The arena-bounds node: the single source of arena size AND of the
## irregular walkable mask (iteration 44).
var _bounds: Node3D = null
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
var _sky_kind: String = ""
var _sky_left: float = 0.0
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


func _enter_tree() -> void:
	# All scene nodes are in-tree here but NO _ready ran yet — the scatter
	# will therefore build its keepout list from the SHUFFLED positions.
	_bounds = get_tree().get_first_node_in_group("arena_bounds") as Node3D
	if _bounds != null:
		_arena_half_extent = float(_bounds.get("arena_half_extent"))
	if shuffle_layout:
		_shuffle_ground_interactables()


func _ready() -> void:
	add_to_group("world_director")
	_event_timer = first_event_at
	# Irregular start (iteration 44) FIRST: it culls scene-placed POIs, and
	# the spots they were holding have to be released before the run-start
	# fixtures pick theirs — otherwise portals and the roulette keep their
	# 18 m distance from POIs that no longer exist.
	_randomize_starting_pois()
	# Run-start fixtures (iteration 41): paired portals and the roulette.
	_spawn_portals()
	_spawn_roulettes()


## The run can end — or the scene reload — mid sky event, which kills the
## tint tween halfway. Snap the cached lighting back on the way out so a
## blood moon cannot bleed into the next run through a shared resource.
func _exit_tree() -> void:
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
	for node: Node in get_tree().get_nodes_in_group("scatter_keepout"):
		if node is Chest or node is ChargeShrine or node is GreedShrine:
			if node is Chest and chests_kept == 0:
				chests_kept += 1  # always keep the first ground chest
				continue
			if randf() < poi_skip_chance:
				node.queue_free()
				removed += 1
			elif node is Chest:
				chests_kept += 1
	_refresh_placed_points()
	var extra := randi_range(extra_start_chests_min, extra_start_chests_max)
	for i in extra:
		var chest := CHEST_SCENE.instantiate() as Chest
		add_child(chest)
		chest.global_position = _claim_clear_point()
	print("Start layout: %d POI(s) skipped, %d extra chest(s)" % [removed, extra])


func _physics_process(delta: float) -> void:
	if not RunState.run_active:
		return
	_tick_beacons(delta)
	if not events_enabled:
		return
	_tick_sky(delta)
	_event_timer -= delta
	if _event_timer > 0.0:
		return
	_event_timer = randf_range(event_gap_min, event_gap_max)
	_fire_random_event()
	_maybe_sky_event()


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
	var ray := PhysicsRayQueryParameters3D.create(
			Vector3(pos.x, GROUND_PROBE_HEIGHT, pos.z), Vector3(pos.x, -1.0, pos.z), 1)
	# Raiders share layer 1 with the world; never mistake a head for ground.
	var excluded: Array[RID] = []
	for node: Node in Coop.alive_players(get_tree()):
		var body := node as CollisionObject3D
		if body != null:
			excluded.append(body.get_rid())
	ray.exclude = excluded
	var hit := space.intersect_ray(ray)
	if hit.is_empty():
		return 0.0
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
		# Only X/Z move; the scene's Y (ground offset) is kept as authored.
		poi.global_position = Vector3(spot_xz.x, poi.global_position.y, spot_xz.y)
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
	return Vector3(spot.x, 0.0, spot.y)


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
		add_child(portal)
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
		add_child(wheel)
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

## This map's weight for an EVENT_LIBRARY row.
func _event_weight(row: Dictionary) -> float:
	return float(event_weight_overrides.get(row["id"], row["weight"]))


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


## Recurring altar (charge or demonic): far from a player, leaves on its
## own after altar_idle_lifetime if nobody comes.
func _event_altar(scene: PackedScene, message: String) -> void:
	var altar := scene.instantiate() as Node3D
	altar.set("idle_lifetime", altar_idle_lifetime)
	add_child(altar)
	altar.global_position = _event_point()
	var color := Color(1.0, 0.35, 0.3) if scene == CURSE_SHRINE_SCENE \
			else Color(0.45, 0.85, 1.0)
	_beacons.append(TimedBeacon.new(
			_spawn_beacon(altar.global_position, color), altar, altar_idle_lifetime))
	_announce(message)


func _event_spring() -> void:
	var spring := SPRING_SHRINE_SCENE.instantiate() as Node3D
	spring.set("idle_lifetime", spring_idle_lifetime)
	add_child(spring)
	spring.global_position = _event_point()
	_beacons.append(TimedBeacon.new(
			_spawn_beacon(spring.global_position, Color(0.4, 0.8, 1.0)),
			spring, spring_idle_lifetime))
	_announce("Un manantial brota en algún lugar del campo...")


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
	add_child(chest)
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
	_announce("¡Una jauría élite te huele el rastro!")


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


## Unclaimed supply chest sinks away.
func _despawn_chest(chest: Chest) -> void:
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
	add_child(beacon)
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


## --- sky events -------------------------------------------------------------

func _maybe_sky_event() -> void:
	if not _sky_kind.is_empty() or _sky_gap_left > 0.0:
		return
	var chance := sky_event_chance + sky_event_chance_per_demonic * float(RunState.demonic_uses)
	if randf() >= chance:
		return
	start_sky_event("blood_moon" if randf() < 0.5 else "eclipse")


## Group hook too (tests / future altars): starts a sky event by name.
func start_sky_event(kind: String) -> void:
	_cache_lights()
	_sky_kind = kind
	match kind:
		"blood_moon":
			_sky_left = sky_event_duration
			get_tree().call_group("enemy_spawner", "set_sky_event", kind, sky_event_duration)
			_tint_sky(Color(1.0, 0.25, 0.2), 0.9, Color(0.5, 0.1, 0.1))
			_announce("LUNA DE SANGRE — ¡la horda enloquece!")
		"eclipse":
			_sky_left = sky_event_duration
			get_tree().call_group("enemy_spawner", "set_sky_event", kind, sky_event_duration)
			_tint_sky(Color(0.35, 0.3, 0.5), 0.35, Color(0.12, 0.1, 0.2))
			_announce("ECLIPSE — las sombras entran por todos lados")
		"full_moon":
			_sky_left = full_moon_duration
			for node: Node in get_tree().get_nodes_in_group("player"):
				var stats := PlayerStats.find_in(node)
				if stats != null:
					stats.add_timed_boon("xp_gain", full_moon_xp_bonus, full_moon_duration)
					stats.add_timed_boon("luck", full_moon_luck_bonus, full_moon_duration)
			_tint_sky(Color(0.85, 0.9, 1.0), 1.3, Color(0.6, 0.65, 0.9))
			_announce("LUNA LLENA — la fortuna y la sabiduría te sonríen")
		_:
			push_warning("WorldDirector: unknown sky event '%s'" % kind)
			_sky_kind = ""
			return
	print("Sky event: %s for %.0fs" % [kind, _sky_left])


func _tick_sky(delta: float) -> void:
	_sky_gap_left = maxf(_sky_gap_left - delta, 0.0)
	if _sky_kind.is_empty():
		return
	_sky_left -= delta
	if _sky_left > 0.0:
		return
	var ended := _sky_kind
	_sky_kind = ""
	if ended == "full_moon":
		_restore_sky()
		_sky_gap_left = sky_event_min_gap
	else:
		# Every dark moon is followed by a bright one. Tint STRAIGHT into
		# it: restoring first spawned a 2 s tween racing the full moon's
		# 1.5 s one over the same properties, and the longer restore won.
		start_sky_event("full_moon")


func _cache_lights() -> void:
	if _sun != null:
		return
	var scene := get_tree().current_scene
	if scene == null:
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
