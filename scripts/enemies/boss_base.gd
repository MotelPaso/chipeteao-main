class_name BossBase
extends EnemyBase
## Shared boss chassis on top of EnemyBase: everything every biome boss
## repeats — HUD boss-bar binding through the "boss_ui" group, the hard
## arena clamp, Elder tier and Curse Shrine scaling (both funnel the
## moveset's numbers through the _scale_attack_damage hook), the ring-of-
## gems death payout, and the boss-kill juice moment. Concrete bosses
## (Rotking, Sarcognath) keep their own state machines and movesets.
## Bosses never become elites (make_elite is a no-op); the spawner
## promotes rematches with apply_tier() instead.

@export var boss_title: String = "Jefe"
## Half-size of the arena floor minus arena_clamp_margin; position is
## clamped so the boss (and its ground attacks) never leave the field.
## Fallback only: at ready it is re-derived from the map's "arena_bounds"
## node (the scatter node's arena_half_extent), so map resizes propagate.
@export var arena_half_extent: float = 76.0
## Kept between the boss and the wall so ground attacks stay on the floor.
@export var arena_clamp_margin: float = 4.0

@export_group("Reward")
## Death payout: a ring of boss_gem_count gems worth boss_gem_value XP each.
@export var boss_gem_count: int = 8
@export var boss_gem_value: int = 5
## Health orbs guaranteed on death (map bosses keep the default 2; the
## miniboss scenes set 1). Still subject to HealthOrb's global soft cap.
@export var health_orb_count: int = 2

@export_group("Tier")
## Extra body scale applied per apply_tier() call (Elder and beyond).
@export var tier_body_scale: float = 1.15

@export_group("Chests")
## Chests dropped on death: this many always, plus one per demonic altar
## used this run (RunState.demonic_uses). Rolled Rare+ with luck tilt.
@export var base_chest_drops: int = 1
@export var chest_min_rarity: String = "Rare"


## Bosses pay a flat bounty of run points (scenes may override).
@export var boss_points_value: int = 25

## Shared arrival cue: ring on the ground, silhouette popping to full size.
const ENTRANCE_RING_DURATION: float = 0.45
const ENTRANCE_POP_DURATION: float = 0.55
const ENTRANCE_START_SCALE: float = 0.15
## Ring the death chests are scattered on, and the extra luck each demonic
## altar used this run tilts their rarity roll by.
const CHEST_RING_RADIUS: float = 3.5
const CHEST_LUCK_PER_DEMONIC: float = 20.0
## Payout rings: gems land close, health orbs wider, so the two pickups
## read apart on the floor.
const GEM_RING_RADIUS: float = 1.2
const ORB_RING_RADIUS: float = 2.2

## Single tween slot for every attack/arrival cue. One slot per boss is the
## whole discipline: a new cue always kills the one it replaces, so cues can
## never fight each other (or the death squash-out) over _visual.
var _cue_tween: Tween
## Arena mask publisher ("arena_bounds"), when the map has one: the same
## node the spawner asks before placing a body (see _safe_arena_point).
var _bounds: Node3D = null
## How many times apply_tier ran on this instance. Diagnostics only — the
## call is meant to happen exactly once, and it compounds if it doesn't.
var _tier_stacks: int = 0


func _ready() -> void:
	super()
	# A scene-set bounty wins; boss_points_value only fills in the default.
	if points_value == DEFAULT_POINTS_VALUE:
		points_value = boss_points_value
	_bounds = get_tree().get_first_node_in_group("arena_bounds") as Node3D
	if _bounds != null:
		var extent: Variant = _bounds.get("arena_half_extent")
		if extent is float or extent is int:
			arena_half_extent = float(extent) - arena_clamp_margin
	_health.died.connect(_on_boss_base_died)
	get_tree().call_group("boss_ui", "track_boss", self, boss_title)


func _physics_process(delta: float) -> void:
	super(delta)
	# Hard arena bound (also catches any future knockback effects).
	global_position.x = clampf(global_position.x, -arena_half_extent, arena_half_extent)
	global_position.z = clampf(global_position.z, -arena_half_extent, arena_half_extent)


## The spawner's elite roll must never touch a boss; tiering goes through
## apply_tier() instead.
func make_elite() -> void:
	pass


## Virtual: multiply every attack-damage number the concrete boss owns;
## called once per apply_tier().
func _scale_attack_damage(_multiplier: float) -> void:
	pass


## EnemyBase's damage channel routes into the boss one, so a boss that ever
## goes through apply_tier_scaling (map tiers applied to bosses, a spawn
## table with a boss in it) scales its moveset instead of silently keeping
## baseline damage while its HP and payout grow.
func _apply_elite_damage(multiplier: float) -> void:
	_scale_attack_damage(multiplier)


## Stronger boss instance (Elder rematches, map tiers): multiplies
## survivability, damage, and payout, and bulks the body up slightly.
## The three channels are separate on purpose — the co-op party factor is
## an HP-only wall (see EnemySpawner's "damage is deliberately NOT scaled"),
## so folding it into one number would double every boss attack in a
## four-player run. `-1.0` means "same factor as HP", which is what a
## single-argument Elder/tier promotion wants.
## Call after the boss is inside the tree, once: it compounds.
func apply_tier(hp_mult: float, damage_mult: float = -1.0, payout_mult: float = -1.0) -> void:
	var damage_factor := hp_mult if damage_mult < 0.0 else damage_mult
	var payout_factor := hp_mult if payout_mult < 0.0 else payout_mult
	_tier_stacks += 1
	_health.max_hp *= hp_mult
	_health.heal_full()
	_scale_attack_damage(damage_factor)
	boss_gem_value = ceili(float(boss_gem_value) * payout_factor)
	# Points scale with the payout too, the way make_elite scales them for
	# regular enemies; without this an Elder paid the baseline bounty.
	points_value = maxi(roundi(float(points_value) * payout_factor), 1)
	scale *= tier_body_scale


func _on_boss_base_died() -> void:
	# The base death flow (kill credit, gems, squash-out) already runs off
	# this signal; the boss only has to stop reading as an active boss.
	# Killing the cue tween here lets the death squash-out own _visual: the
	# base handler ran first, so its tween is already the live one.
	_kill_cue()
	remove_from_group("boss")
	_drop_chests()


# --- shared cues ------------------------------------------------------------

## Plays a one-property cue on the single _cue_tween slot, killing whatever
## cue was running. Every boss animation goes through here (or _begin_cue
## for multi-step ones) so nothing ever animates _visual behind another
## tween's back.
func _play_cue(node: Node, property: String, target: Variant, duration: float,
		trans: Tween.TransitionType = Tween.TRANS_QUAD,
		ease_type: Tween.EaseType = Tween.EASE_OUT) -> void:
	_begin_cue().tween_property(node, property, target, duration) \
			.set_trans(trans).set_ease(ease_type)


## Fresh cue tween in the shared slot, for cues with more than one step.
func _begin_cue() -> Tween:
	_kill_cue()
	_cue_tween = create_tween()
	return _cue_tween


func _kill_cue() -> void:
	if _cue_tween != null and _cue_tween.is_valid():
		_cue_tween.kill()


## Shared boss arrival: a flash ring on the ground while the silhouette
## pops out of nothing. Concrete bosses only pick the ring size, its color
## and their roar voice.
func _play_boss_entrance(ring_radius: float, ring_color: Color) -> void:
	Telegraph.spawn_disc(self, global_position, ring_radius,
			ENTRANCE_RING_DURATION, ring_color)
	_visual.scale = Vector3.ONE * ENTRANCE_START_SCALE
	_play_cue(_visual, "scale", Vector3.ONE, ENTRANCE_POP_DURATION,
			Tween.TRANS_BACK, Tween.EASE_OUT)


# --- arena-safe positions ---------------------------------------------------

## Square clamp only: enough for a telegraph disc, which is allowed to
## overlap scenery.
func _clamp_to_arena(point: Vector3) -> Vector3:
	var clamped := point
	clamped.x = clampf(clamped.x, -arena_half_extent, arena_half_extent)
	clamped.z = clampf(clamped.z, -arena_half_extent, arena_half_extent)
	return clamped


## Clamp PLUS the arena's irregular walkable mask (iteration 44), for points
## a BODY is placed at. Teleporting onto a blocked cell drops the body
## inside a 7 m mask-wall collider, where melee can never reach it; the
## spawner already asks the same question before every ring spawn.
## Retries alternate bearings around the original point before giving up on
## the boss's current position, which is walkable by construction.
func _safe_arena_point(point: Vector3, tries: int = 6) -> Vector3:
	var clamped := _clamp_to_arena(point)
	if _is_walkable(clamped):
		return clamped
	var to_point := clamped - global_position
	to_point.y = 0.0
	var radius := to_point.length()
	if radius > 0.01:
		var base_angle := atan2(to_point.z, to_point.x)
		for i in tries:
			# Fan outward alternating sides, so the retry stays as close to
			# the intended spot (and the telegraphed disc) as possible.
			var offset := TAU * float((i / 2) + 1) / float(tries + 1)
			var angle := base_angle + (offset if i % 2 == 0 else -offset)
			var candidate := _clamp_to_arena(global_position
					+ Vector3(cos(angle), 0.0, sin(angle)) * radius)
			candidate.y = point.y
			if _is_walkable(candidate):
				return candidate
	return global_position


# --- shared ground-spike cue ------------------------------------------------

## Spikes per cluster and the beats of their pop-out, shared by every boss
## that erupts the ground.
const SPIKE_COUNT: int = 5
const SPIKE_RISE_TIME: float = 0.12
const SPIKE_HOLD_TIME: float = 0.35
const SPIKE_SINK_TIME: float = 0.25
## Extra depth the cluster sinks to, below where it started buried.
const SPIKE_EXTRA_SINK: float = 0.1


## A clutch of cones bursting out of the floor and sinking back, used by the
## Rotking's bark roots and the Sarcognath's sandstone slabs — same
## silhouette, different skin. Self-frees via its own tween, so it survives
## the boss dying mid-eruption.
func _spawn_spike_cluster(center: Vector3, spread_radius: float, color: Color,
		roughness: float, bottom_radius: float, spike_length: float,
		sink_depth: float) -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var cluster := Node3D.new()
	scene_root.add_child(cluster)
	var spike_mesh := CylinderMesh.new()
	spike_mesh.top_radius = 0.0
	spike_mesh.bottom_radius = bottom_radius
	spike_mesh.height = spike_length
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	spike_mesh.material = material
	for i in SPIKE_COUNT:
		var spike := MeshInstance3D.new()
		spike.mesh = spike_mesh
		var spike_angle := TAU * float(i) / float(SPIKE_COUNT)
		spike.position = Vector3(cos(spike_angle), 0.0, sin(spike_angle)) * spread_radius
		spike.rotation = Vector3(randf_range(-0.2, 0.2), 0.0, randf_range(-0.2, 0.2))
		cluster.add_child(spike)
	# Starts buried inside the floor slab, pops up, sinks back.
	cluster.global_position = center - Vector3.UP * sink_depth
	var tween := cluster.create_tween()
	tween.tween_property(cluster, "global_position:y", center.y + 0.05, SPIKE_RISE_TIME) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(SPIKE_HOLD_TIME)
	tween.tween_property(cluster, "global_position:y",
			center.y - sink_depth - SPIKE_EXTRA_SINK, SPIKE_SINK_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(cluster.queue_free)


func _is_walkable(point: Vector3) -> bool:
	if _bounds == null or not _bounds.has_method("is_walkable"):
		return true
	return bool(_bounds.call("is_walkable", Vector2(point.x, point.z)))


## Boss bounty chests (iteration 41): scattered on a ring; every demonic
## altar used this run adds one. Parented to the scene root so they
## outlive the corpse.
func _drop_chests() -> void:
	var count := base_chest_drops + RunState.demonic_uses
	var parent := get_tree().current_scene if get_tree().current_scene != null else get_parent()
	# Same guards EnemyBase._drop_chest already had: a boss dying during
	# teardown has no scene to parent to, and a bad cast must not crash the
	# death flow (the gems and the kill credit already went out).
	if parent == null or count <= 0:
		return
	var dropped := 0
	for i in count:
		var angle := TAU * float(i) / float(count)
		var at := global_position \
				+ Vector3(cos(angle), 0.0, sin(angle)) * CHEST_RING_RADIUS
		if spawn_chest(at, CHEST_LUCK_PER_DEMONIC * float(RunState.demonic_uses),
				chest_min_rarity) != null:
			dropped += 1
	print("Boss chests dropped: %d" % dropped)


## Boss kill moment: big shake, brief slow-mo, oversized shard burst.
func _death_feedback() -> void:
	Juice.boss_died(global_position + Vector3.UP * 1.5, death_burst_color())


## Boss payout: a ring of high-value gems instead of the single base gem.
func _drop_xp_gem() -> void:
	if xp_gem_scene == null:
		return
	# Same factors the base single-gem payout applies, so a boss that ever
	# goes through the regular scaling channels pays what they promise.
	# Both are 1 on a plain boss, leaving the exported value untouched.
	var value := maxi(roundi(float(boss_gem_value * _xp_multiplier) * _tier_xp_multiplier), 1)
	for i in boss_gem_count:
		var gem := Pools.acquire_scene(xp_gem_scene) as XpGem
		if gem == null:
			return
		gem.xp_value = value
		var gem_angle := TAU * float(i) / float(boss_gem_count)
		gem.global_position = global_position + Vector3.UP * 0.6 \
				+ Vector3(cos(gem_angle), 0.0, sin(gem_angle)) * GEM_RING_RADIUS


## Bosses always pay out heals: health_orb_count orbs on a wider ring than
## the gems, so the two pickups read apart on the floor.
func _drop_health_orbs() -> void:
	for i in health_orb_count:
		var orb_angle := TAU * (float(i) + 0.5) / float(maxi(health_orb_count, 1))
		_spawn_health_orb(global_position + Vector3.UP * 0.6
				+ Vector3(cos(orb_angle), 0.0, sin(orb_angle)) * ORB_RING_RADIUS)
