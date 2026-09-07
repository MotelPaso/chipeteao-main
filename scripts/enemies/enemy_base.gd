class_name EnemyBase
extends CharacterBody3D
## Shared enemy chassis (flat arena, no navmesh yet): gravity, seek-the-
## player steering with a light separation push from nearby enemies so
## hordes spread into a mob instead of stacking, facing, and the death flow
## via the Health child (kill credit, XP gem drop, squash-out tween).
## Subclasses shape behavior through the virtual hooks below.
## make_elite() upgrades any enemy into a glowing elite variant.

@export var move_speed: float = 4.0
@export var turn_speed: float = 10.0
@export var separation_radius: float = 1.2
@export var separation_strength: float = 1.5
@export var xp_gem_scene: PackedScene
## Run points paid to the nearest raider on death (iteration 40); elites
## multiply it like XP, bosses set their own.
@export var points_value: int = DEFAULT_POINTS_VALUE
## Shiny shimmer (iteration 47). Turns of the hue wheel per second, how
## many brightness beats fit in one full turn, and the energy/alpha bounds.
## Slow enough to read as a sheen rather than a strobe.
const SHINY_HUE_SPEED: float = 0.28
const SHINY_PULSE_CYCLES: float = 4.0
const SHINY_ENERGY_MIN: float = 1.3
const SHINY_ENERGY_MAX: float = 2.8
const SHINY_SATURATION: float = 0.85
const SHINY_ALPHA: float = 0.3
## Distinct starting phases handed out by instance id.
const SHINY_PHASE_BUCKETS: int = 997

@export_group("Elite")
@export var elite_hp_multiplier: float = 3.0
@export var elite_speed_multiplier: float = 1.3
@export var elite_damage_multiplier: float = 1.5
@export var elite_body_scale: float = 1.35
@export var elite_xp_multiplier: int = 5
@export_group("Health Orb")
## Chance an ELITE death also drops a health orb (regular enemies never
## drop one; bosses override _drop_health_orbs with guaranteed counts).
@export var elite_health_orb_chance: float = 0.4
## Chance an ELITE death drops a chest (iteration 42; scaled up by the
## run-wide difficulty, so demonic bargains pay in loot).
@export var elite_chest_chance: float = 0.3
@export_group("Climbing")
## Iteration 42: a body pushing against a wall or prop scrambles UP it at
## this speed, so verticality never walls the horde off. Perimeter walls
## are still uncrossable (position is clamped to the arena bounds).
@export var can_climb: bool = true
@export var climb_speed: float = 5.5
## Ceiling on ONE climb, measured from the height the body started
## scrambling at. Without it a body wedged against geometry keeps pushing
## up forever and ends up perched on a prop out of everyone's reach.
## Comfortably above the arena mask walls (7 m, see scatter.gd) so
## climbers still cross those exactly as before.
@export var max_climb_height: float = 10.0

const CHEST_SCENE := preload("res://scenes/world/chests/Chest.tscn")
## EnemyBase's own baseline bounty; BossBase only overrides points_value
## when the scene left it at this value (a scene-set number always wins).
const DEFAULT_POINTS_VALUE: int = 1
## Gap kept between a climber and the arena edge, so a body that scrambled
## onto the perimeter can never be clamped into the wall itself. Bosses
## keep their own, wider margin (BossBase.arena_clamp_margin).
const ARENA_CLAMP_MARGIN: float = 1.5
## Luck added to an elite's bounty chest per point of run-wide difficulty.
const ELITE_CHEST_LUCK_PER_DIFFICULTY: float = 15.0

var is_elite: bool = false
## Sky-event variant applied by the spawner ("" | "berserker" | "shade").
var variant: String = ""
## Arena clamp for climbers (from the "arena_bounds" node; INF = none).
var _arena_limit: float = INF

@onready var _health: Health = $Health
@onready var _visual: Node3D = $Visual
@onready var _collision: CollisionShape3D = $CollisionShape3D

## One shared per-physics-tick snapshot of the "enemies" group, so a horde
## of n enemies costs one group query per tick instead of n (the arrays
## get_nodes_in_group builds were the hottest allocation in late-run T3).
## Entries stay valid instances for the whole tick (frees are deferred);
## consumers still skip off-group/off-tree bodies like before.
static var _enemies_snapshot: Array[Node] = []
static var _enemies_snapshot_frame: int = -1

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _xp_multiplier: int = 1
## Map-tier XP gem value factor (see apply_tier_scaling); 1.0 = baseline.
var _tier_xp_multiplier: float = 1.0
# Timed slow (Thorn Whip etc.): a speed multiplier active while the timer
# runs; expiry restores full speed. See apply_slow for the refresh rules.
var _slow_multiplier: float = 1.0
var _slow_time_left: float = 0.0
## Poison (iteration 40): damage over time ticking every POISON_TICK
## seconds; re-application keeps the STRONGER dps and the LONGER timer.
const POISON_TICK: float = 0.5
var _poison_dps: float = 0.0
var _poison_time_left: float = 0.0
var _poison_tick_timer: float = 0.0
var _poison_overlay: StandardMaterial3D = null
## Last computed separation push, reused on this enemy's off ticks.
var _separation_cache: Vector3 = Vector3.ZERO
## Overlay slots in priority order: the elite glow outranks a sky variant,
## which outranks the poison tint. Every applier writes ITS OWN slot and
## calls _refresh_overlay(), so a temporary effect can never erase a
## permanent one (an elite berserker keeps reading as both, and poison
## wearing off restores the variant instead of clearing to bare skin).
## Typed narrower than its siblings on purpose: the shiny shimmer writes
## albedo/emission on it every frame (_tick_shiny), which Material alone
## does not expose.
var _overlay_elite: StandardMaterial3D = null
var _overlay_variant: Material = null
var _overlay_status: Material = null
## Meshes of the visual rig, resolved once at ready: the four overlay
## appliers used to walk find_children on every application.
var _meshes: Array[MeshInstance3D] = []
## Height the current climb started at, and whether one is in progress —
## together they cap a single scramble at max_climb_height.
var _climb_start_y: float = 0.0
var _climbing: bool = false


func _ready() -> void:
	_health.died.connect(_on_died)
	_health.damaged.connect(_on_damaged_flash)
	_cache_meshes()
	var bounds := get_tree().get_first_node_in_group("arena_bounds") as Node3D
	if bounds != null:
		# Guarded: a bounds node without the property yields null, and
		# float(null) is a hard script error.
		var extent: Variant = bounds.get("arena_half_extent")
		if extent is float or extent is int:
			_arena_limit = float(extent) - ARENA_CLAMP_MARGIN


func _physics_process(delta: float) -> void:
	if _overlay_elite != null:
		_tick_shiny(delta)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_slow_time_left = maxf(_slow_time_left - delta, 0.0)
	if _poison_time_left > 0.0:
		_tick_poison(delta)
	# A poison tick can KILL from inside this frame. set_physics_process(false)
	# only takes effect next tick, so without this guard the corpse would
	# still run its behaviour: a dead burrower erupting, a dead grunt
	# landing a contact hit, a dead skirmisher firing one last bolt.
	if _health.is_dead:
		return
	_behavior_tick(delta)

	var steer := Vector3.ZERO
	var seek := Vector3.ZERO
	var player := Coop.nearest_player(get_tree(), global_position)
	if player != null:
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		var distance := to_player.length()
		if distance > 0.001:
			seek = to_player / distance
		steer = _movement_intent(seek, distance)
		_combat_tick(player, distance)

	# O(n^2) trim: each enemy recomputes separation every 2nd physics tick
	# (staggered by instance id parity, so half the horde computes per tick)
	# and reuses its cached push in between — indistinguishable at 60fps.
	if (Engine.get_physics_frames() + get_instance_id()) & 1 == 0:
		_separation_cache = _separation_push()
	steer += _separation_cache * separation_strength
	steer.y = 0.0
	if steer.length_squared() > 1.0:
		steer = steer.normalized()
	var slowed_speed := move_speed * active_slow_multiplier()
	velocity.x = steer.x * slowed_speed
	velocity.z = steer.z * slowed_speed

	var face := _facing_direction(steer, seek)
	if face.length_squared() > 0.0001:
		# Face the chosen direction (-Z forward).
		var target_yaw := atan2(-face.x, -face.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, minf(turn_speed * delta, 1.0))

	_tick_climb(steer)
	move_and_slide()
	if _arena_limit != INF:
		global_position.x = clampf(global_position.x, -_arena_limit, _arena_limit)
		global_position.z = clampf(global_position.z, -_arena_limit, _arena_limit)


## Wall climbing: blocked by geometry while trying to move -> go up, but
## only up to max_climb_height above where this scramble began. Landing on
## anything walkable re-arms the next climb from the new footing.
func _tick_climb(steer: Vector3) -> void:
	if not (can_climb and steer.length_squared() > 0.01 and _blocked_by_geometry()):
		if _climbing and is_on_floor():
			_climbing = false
		return
	if not _climbing:
		_climbing = true
		_climb_start_y = global_position.y
	if global_position.y - _climb_start_y < max_climb_height:
		velocity.y = climb_speed


## True when a wall contact this frame came from LEVEL GEOMETRY. is_on_wall()
## alone is not enough: enemies collide with the player and with each other
## (collision_mask 3), and any near-vertical contact sets it — so a packed
## horde would read its own neighbours, or the raider it is chewing on, as a
## wall and scramble up on top of them, out of melee reach. Climbing is about
## walls and ledges, so only non-character colliders count.
func _blocked_by_geometry() -> bool:
	if not is_on_wall():
		return false
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		# Floors and shallow ramps are walked, not climbed.
		if collision.get_normal().y > 0.5:
			continue
		if collision.get_collider() is CharacterBody3D:
			continue
		return true
	return false


## Virtual: per-frame housekeeping (attack cooldowns etc.) before steering.
func _behavior_tick(_delta: float) -> void:
	pass


## Virtual: where to steer given the flat unit direction to the player and
## the flat distance. Default chases straight in.
func _movement_intent(seek: Vector3, _distance: float) -> Vector3:
	return seek


## Virtual: attack opportunity for this frame; distance is flat.
func _combat_tick(_player: Node3D, _distance: float) -> void:
	pass


## Virtual: direction the body turns toward. Default faces its steering.
func _facing_direction(steer: Vector3, _seek: Vector3) -> Vector3:
	return steer


## Virtual: scale whatever damage number(s) the subclass owns; called once
## by make_elite().
func _apply_elite_damage(_multiplier: float) -> void:
	pass


# --- telegraphed area damage (the party-aware front door) -------------------

## Resolves ONE telegraphed ground disc against the whole party. A disc is
## drawn for everybody, so it has to hurt everybody standing on it: this is
## the single resolver every AoE moveset calls, instead of each one asking
## for the nearest raider and quietly missing the rest of the party.
## Returns the bodies actually hit, so callers can layer extra effects
## (the Sarcognath's root) on exactly those players.
func damage_players_in_disc(center: Vector3, radius: float, height_window: float,
		amount: float, attacker: Node3D = null) -> Array[Node3D]:
	var spots: Array[Vector3] = [center]
	return damage_players_in_discs(spots, radius, height_window, amount, attacker)


## Multi-disc version (root bursts, coffin rings, glob volleys): each player
## takes AT MOST one hit however many discs cover them — the old
## "one hit max even where discs overlap" rule, now per player instead of
## per attack.
## Only players the hit actually LANDED on come back: take_damage reports
## the HP it removed, so a raider who evaded the disc is left out of the
## list and the follow-up effect callers layer on it (the Sarcognath's root)
## misses them too — which is what dodging the attack should mean.
func damage_players_in_discs(spots: Array[Vector3], radius: float,
		height_window: float, amount: float, attacker: Node3D = null) -> Array[Node3D]:
	var hit: Array[Node3D] = []
	if spots.is_empty():
		return hit
	for player: Node3D in Coop.alive_players(get_tree()):
		if not _covered_by_any(player, spots, radius, height_window):
			continue
		var player_health := Health.find_in(player)
		if player_health == null or player_health.is_dead:
			continue
		if player_health.take_damage(amount, false, attacker) > 0.0:
			hit.append(player)
	return hit


## Flat distance inside `radius` of any spot, and no higher above it than
## `height_window` — a well-timed jump or a ledge still clears the attack.
func _covered_by_any(player: Node3D, spots: Array[Vector3], radius: float,
		height_window: float) -> bool:
	for spot: Vector3 in spots:
		var to_player := player.global_position - spot
		if absf(to_player.y) > height_window:
			continue
		to_player.y = 0.0
		if to_player.length() <= radius:
			return true
	return false


## Applies a timed slow: this enemy moves at speed_multiplier of its normal
## speed for `duration` seconds. Re-application REFRESHES rather than
## stacking, so repeated whip lashes can never compound a slow toward zero —
## but, like apply_poison, the STRONGER slow and the LONGER timer win, so a
## weak source can neither undo nor cut short a strong one.
func apply_slow(speed_multiplier: float, duration: float) -> void:
	if duration <= 0.0:
		return
	var incoming := clampf(speed_multiplier, 0.05, 1.0)
	_slow_multiplier = minf(active_slow_multiplier(), incoming)
	_slow_time_left = maxf(_slow_time_left, duration)


## Current external speed multiplier: 1.0 whenever no slow is active.
func active_slow_multiplier() -> float:
	return _slow_multiplier if _slow_time_left > 0.0 else 1.0


## Applies a poison of `dps` for `duration` seconds (Fart Bag, spiders,
## Stench). Refresh rule: the stronger dps wins, the longer timer wins —
## so spamming weak poison never overwrites a strong one.
func apply_poison(dps: float, duration: float) -> void:
	if dps <= 0.0 or duration <= 0.0 or _health.is_dead:
		return
	if _poison_time_left <= 0.0:
		_poison_tick_timer = POISON_TICK
		_apply_poison_tint(true)
	_poison_dps = maxf(_poison_dps, dps)
	_poison_time_left = maxf(_poison_time_left, duration)


func is_poisoned() -> bool:
	return _poison_time_left > 0.0


func _tick_poison(delta: float) -> void:
	_poison_time_left = maxf(_poison_time_left - delta, 0.0)
	_poison_tick_timer -= delta
	if _poison_tick_timer <= 0.0:
		_poison_tick_timer += POISON_TICK
		# Through take_damage so armor, popups and the death flow all apply.
		_health.take_damage(_poison_dps * POISON_TICK)
	if _poison_time_left <= 0.0:
		_poison_dps = 0.0
		_apply_poison_tint(false)


## Sickly green overlay while poisoned. It is the LOWEST-priority slot, so
## elites and sky variants keep their own tint and only show poison through
## the damage popups — exactly as before, but now the poison wearing off
## restores their overlay instead of wiping it.
func _apply_poison_tint(on: bool) -> void:
	if on and _poison_overlay == null:
		_poison_overlay = StandardMaterial3D.new()
		_poison_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_poison_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_poison_overlay.albedo_color = Color(0.35, 0.9, 0.3, 0.35)
	_overlay_status = _poison_overlay if on else null
	_refresh_overlay()


## The overlay this body should be wearing right now, or null for none.
## Public so effects that borrow material_overlay for a moment (Juice.flash)
## can restore the COMPOSED state instead of whatever happened to be in the
## slot when they started.
func current_overlay() -> Material:
	if _overlay_elite != null:
		return _overlay_elite
	if _overlay_variant != null:
		return _overlay_variant
	return _overlay_status


func _refresh_overlay() -> void:
	var overlay := current_overlay()
	for mesh: MeshInstance3D in _meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = overlay


func _cache_meshes() -> void:
	_meshes.clear()
	if _visual == null:
		return
	for node: Node in _visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance != null:
			_meshes.append(mesh_instance)


## Map-tier difficulty hook (GDD 6/7), applied by the spawner right after
## a spawn: multiplies max HP (healed to the new max), attack damage
## (through the same virtual elites use), and the XP gem payout. Distinct
## from make_elite() and stacks multiplicatively with it in either order.
## Every factor at 1.0 (tier 1) is an exact no-op. Call after the enemy is
## inside the tree (relies on the onready Health child).
func apply_tier_scaling(hp_mult: float, dmg_mult: float, xp_value_mult: float = 1.0) -> void:
	if not is_equal_approx(hp_mult, 1.0):
		_health.max_hp *= hp_mult
		_health.heal_full()
	if not is_equal_approx(dmg_mult, 1.0):
		_apply_elite_damage(dmg_mult)
	# Composes like every other spawn modifier (a second pass multiplies
	# instead of replacing), so the XP channel cannot be silently reset.
	_tier_xp_multiplier *= xp_value_mult


## Promotes this enemy to an elite: more HP (healed to the new max), speed,
## damage, and XP, bigger body, and an emissive glow overlay. Call after
## the enemy is inside the tree (relies on onready children). Idempotent.
func make_elite() -> void:
	if is_elite:
		return
	is_elite = true
	_health.max_hp *= elite_hp_multiplier
	_health.heal_full()
	move_speed *= elite_speed_multiplier
	_apply_elite_damage(elite_damage_multiplier)
	# Multiplies (like points_value right below) instead of assigning: the
	# spawner applies the sky variant FIRST, and an elite berserker must
	# still pay the variant's doubled XP on top of the elite factor.
	_xp_multiplier *= elite_xp_multiplier
	points_value *= elite_xp_multiplier
	_grow_body(elite_body_scale)
	_apply_elite_glow()


## Sky-event variants (iteration 42), applied by the spawner on fresh
## spawns while an event runs. Idempotent per body.
##   "berserker" (blood moon): faster, harder-hitting, ignores the crowd
##                             (no separation), red-lit; pays double.
##   "shade"     (eclipse):    much tougher, near-black; pays double.
func apply_variant(kind: String) -> void:
	if not variant.is_empty() or kind.is_empty():
		return
	variant = kind
	match kind:
		"berserker":
			move_speed *= 1.4
			_apply_elite_damage(1.3)
			separation_strength *= 0.2
			_apply_overlay(Color(1.0, 0.15, 0.1, 0.45), Color(1.0, 0.2, 0.1), 2.0)
		"shade":
			_health.max_hp *= 1.6
			_health.heal_full()
			_apply_overlay(Color(0.05, 0.02, 0.1, 0.8), Color(0.3, 0.1, 0.5), 0.6)
		_:
			push_warning("EnemyBase: unknown variant '%s'" % kind)
			variant = ""
			return
	_xp_multiplier *= 2
	points_value *= 2


## Where this body sits in the shiny hue cycle (0-1); unused until
## _apply_elite_glow seeds it.
var _shiny_phase: float = 0.0


## Grows this body by `factor`: the VISUAL rig is scaled, and the collision
## shape is RESIZED on a per-instance duplicate.
## Never `scale *= factor` on the CharacterBody3D itself, which is what
## this replaced (iteration 48): Godot does not support scaling a physics
## body — the scaled shape produces unstable contacts and depenetration
## pops, worst exactly where bodies press against each other, which is the
## crowded horde where "enemies fly" was reported.
## The shape is duplicated because a .tscn [sub_resource] is ONE object
## shared by every instance of the scene (project convention): resizing the
## scene's own CapsuleShape3D would grow every grunt in the arena, and the
## next run too.
func _grow_body(factor: float) -> void:
	if is_equal_approx(factor, 1.0) or factor <= 0.0:
		return
	if _visual != null:
		_visual.scale *= factor
		# Positions scale too, so a rig authored with its parts offset from
		# the origin keeps its proportions — the old node-wide scale did.
		_visual.position *= factor
	for child: Node in get_children():
		var shape_node := child as CollisionShape3D
		if shape_node == null or shape_node.shape == null:
			continue
		var shape := shape_node.shape.duplicate() as Shape3D
		if not _resize_shape(shape, factor):
			continue
		shape_node.shape = shape
		# Keeps the feet where they were: the old node-wide scale moved the
		# shape's offset as well, and a capsule grown in place would sink
		# half a body into the floor and be shoved back out on the next tick.
		shape_node.position *= factor


## Resizes one shape in place by `factor`. Returns false for a shape kind
## this does not know how to grow, so the caller leaves the original alone
## instead of silently shipping a body whose collider stopped matching it.
func _resize_shape(shape: Shape3D, factor: float) -> bool:
	var capsule := shape as CapsuleShape3D
	if capsule != null:
		capsule.radius *= factor
		capsule.height *= factor
		return true
	var sphere := shape as SphereShape3D
	if sphere != null:
		sphere.radius *= factor
		return true
	var cylinder := shape as CylinderShape3D
	if cylinder != null:
		cylinder.radius *= factor
		cylinder.height *= factor
		return true
	var box := shape as BoxShape3D
	if box != null:
		box.size *= factor
		return true
	push_warning("%s: cannot grow collision shape of type %s"
			% [name, shape.get_class()])
	return false


func _apply_overlay(albedo: Color, emission: Color, energy: float) -> void:
	_overlay_variant = _build_overlay(albedo, emission, energy)
	_refresh_overlay()


## The SHINY look (iteration 47, replacing the flat amber tint): a
## self-illuminated overlay whose hue cycles and whose brightness breathes,
## so a shiny reads at a glance even inside a horde and even when the horde
## is entirely shiny. Material only, on purpose — no particles and no
## pooled FX: the elite-boost soak makes every body shiny at once, and one
## emitter per body would drain the pools and drown the log in warnings.
## The overlay is built per body (_build_overlay news one every call), so
## animating it here can never bleed into another enemy.
func _apply_elite_glow() -> void:
	_overlay_elite = _build_overlay(
			Color(1.0, 0.62, 0.12, SHINY_ALPHA), Color(1.0, 0.55, 0.1), SHINY_ENERGY_MIN)
	# Each body starts somewhere else in the cycle: a horde pulsing in
	# lockstep reads as one flashing object, not as many shiny ones.
	_shiny_phase = float(get_instance_id() % SHINY_PHASE_BUCKETS) \
			/ float(SHINY_PHASE_BUCKETS)
	_refresh_overlay()


## One frame of the shimmer. Cheap on purpose: two writes on one material
## this body owns, no allocation, no group walk.
func _tick_shiny(delta: float) -> void:
	_shiny_phase = fmod(_shiny_phase + delta * SHINY_HUE_SPEED, 1.0)
	var tint := Color.from_hsv(_shiny_phase, SHINY_SATURATION, 1.0)
	_overlay_elite.albedo_color = Color(tint.r, tint.g, tint.b, SHINY_ALPHA)
	_overlay_elite.emission = tint
	var beat := 0.5 + 0.5 * sin(_shiny_phase * TAU * SHINY_PULSE_CYCLES)
	_overlay_elite.emission_energy_multiplier = lerpf(
			SHINY_ENERGY_MIN, SHINY_ENERGY_MAX, beat)


func _build_overlay(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var overlay := StandardMaterial3D.new()
	overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	overlay.albedo_color = albedo
	overlay.emission_enabled = true
	overlay.emission = emission
	overlay.emission_energy_multiplier = energy
	return overlay


func _on_damaged_flash(_amount: float, _current: float) -> void:
	Juice.flash(_visual)


## Virtual: death juice (tiny shake + shard burst tinted like the body);
## the boss overrides this with its bigger moment.
func _death_feedback() -> void:
	Juice.enemy_died(global_position + Vector3.UP * 0.8, death_burst_color())


## Tint for this enemy's death burst: the first visual mesh's albedo, so
## the shards read as pieces of the body. Elites keep their base skin color
## (the glow is an overlay, which get_active_material ignores).
func death_burst_color() -> Color:
	for mesh_instance: MeshInstance3D in _meshes:
		if not is_instance_valid(mesh_instance) or mesh_instance.mesh == null \
				or mesh_instance.mesh.get_surface_count() == 0:
			continue
		var material := mesh_instance.get_active_material(0) as StandardMaterial3D
		if material != null:
			return material.albedo_color
	return Color(0.75, 0.75, 0.78)


## Sums push-away vectors from living "enemies" within separation_radius,
## with falloff (strongest when overlapping, zero at the edge). O(n^2) over
## the horde, halved by the caller's tick stagger and served from the
## shared per-tick group snapshot.
func _separation_push() -> Vector3:
	var push := Vector3.ZERO
	for enemy: Node in _enemies_this_tick(get_tree()):
		var other := enemy as Node3D
		if other == null or other == self or not other.is_inside_tree():
			continue
		var away := global_position - other.global_position
		away.y = 0.0
		var dist := away.length()
		if dist >= separation_radius:
			continue
		# Checked only for actual neighbours (the snapshot is taken once per
		# tick, so a body that died EARLIER this tick is still in it and
		# would keep shoving the horde around as a corpse).
		if not other.is_in_group(&"enemies"):
			continue
		if dist < 0.01:
			# Perfectly stacked bodies: nudge apart in a stable per-instance direction.
			away = Vector3.RIGHT.rotated(Vector3.UP, float(get_instance_id() % 64) * TAU / 64.0)
			dist = 0.01
		push += (away / dist) * (1.0 - dist / separation_radius)
	return push


static func _enemies_this_tick(tree: SceneTree) -> Array[Node]:
	var frame := Engine.get_physics_frames()
	if frame != _enemies_snapshot_frame:
		_enemies_snapshot_frame = frame
		_enemies_snapshot = tree.get_nodes_in_group(&"enemies")
	return _enemies_snapshot


func _on_died() -> void:
	# Leave the group first so weapons and separation ignore the corpse.
	remove_from_group("enemies")
	set_physics_process(false)
	_collision.set_deferred("disabled", true)
	RunState.add_kill()
	# Bestiary counter (Collection screen): keyed by the script's file name
	# ("kills_grunt", "kills_rotking", ...), so no per-enemy code or export.
	var script_path := (get_script() as Script).resource_path
	if not script_path.is_empty():
		SaveData.bump("kills_" + script_path.get_file().get_basename())
	_drop_xp_gem()
	_drop_health_orbs()
	_award_points()
	_death_feedback()
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_visual, "rotation:x", -TAU * 0.25, 0.3) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_visual, "scale", Vector3.ONE * 0.05, 0.3) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)


## Run points go to the NEAREST standing raider (co-op: whoever was in
## the thick of it), never shared — the economy is per player by design.
func _award_points() -> void:
	if points_value <= 0:
		return
	var player := Coop.nearest_player(get_tree(), global_position)
	if player != null and player.has_method("add_points"):
		player.call("add_points", points_value)


func _drop_xp_gem() -> void:
	if xp_gem_scene == null:
		return
	# Pooled, parented to the scene root (not this enemy) so it outlives
	# the corpse; pool_reset restored the scene-default xp_value.
	var gem := Pools.acquire_scene(xp_gem_scene) as XpGem
	if gem == null:
		return
	# Elite factor first (int), then the map-tier value factor (min 1 XP);
	# both 1 on a baseline spawn, leaving the scene value untouched.
	gem.xp_value = maxi(roundi(float(gem.xp_value * _xp_multiplier) * _tier_xp_multiplier), 1)
	gem.global_position = global_position + Vector3.UP * 0.6


## Virtual-ish health-orb payout for this death. Base rule: only elites
## roll (elite_health_orb_chance for one orb); BossBase overrides with
## guaranteed drops. Heal size is the orb's own flat max-HP fraction —
## tier XP factors never touch it.
func _drop_health_orbs() -> void:
	if is_elite and randf() < elite_health_orb_chance:
		_spawn_health_orb(global_position + Vector3.UP * 0.6)
	if is_elite and randf() < elite_chest_chance * (1.0 + RunState.difficulty_bonus):
		_drop_chest()


## Elite bounty chest (iteration 42): rarity rolled with a luck tilt that
## grows with the run-wide difficulty.
func _drop_chest() -> void:
	var chest := spawn_chest(
			global_position + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)),
			ELITE_CHEST_LUCK_PER_DIFFICULTY * RunState.difficulty_bonus)
	if chest != null:
		# A free chest has no rarity yet (it rolls when opened), so the log
		# reports what it IS instead of an empty string.
		print("Elite chest dropped: free")


## Drops one chest at `at`, parented to the scene ROOT so it outlives the
## corpse, or null when there is no scene to drop into (run teardown) or the
## scene root is not a Chest. The single place both the shiny bounty and the
## boss ring go through, so the guards can only be written once.
## Every chest dropped by a BODY is free (iteration 47): you already paid
## for it by killing the thing, and charging points for a boss reward on
## top of the run economy is what made the rings go unopened.
func spawn_chest(at: Vector3, luck_bonus: float, min_rarity: String = "") -> Chest:
	var parent := get_tree().current_scene if get_tree().current_scene != null else get_parent()
	if parent == null:
		return null
	var chest := CHEST_SCENE.instantiate() as Chest
	if chest == null:
		push_warning("EnemyBase: Chest scene root is not a Chest.")
		return null
	# Empty keeps whatever floor the scene set (the elite chest's roll is
	# unbounded; boss chests force Rare+).
	if not min_rarity.is_empty():
		chest.min_rarity = min_rarity
	chest.luck_bonus = luck_bonus
	chest.free_open = true
	parent.add_child(chest)
	chest.global_position = at
	return chest


## One pooled health orb at `at`, skipped at the global live-orb soft cap.
## Re-checked per orb, so a boss's multi-drop fills exactly up to the cap.
func _spawn_health_orb(at: Vector3) -> void:
	if HealthOrb.at_soft_cap(get_tree()):
		return
	var orb := Pools.acquire_scene(Pools.HEALTH_ORB_SCENE) as HealthOrb
	if orb == null:
		return
	orb.global_position = at
