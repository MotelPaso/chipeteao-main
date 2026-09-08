extends WeaponBase
## Doc's starting weapon: lobs a crimson flask at the densest enemy cluster
## in range; where it lands it shatters into a lingering blood pool that
## pulses damage ticks (`damage` is per tick, through the shared funnel)
## and returns heal_fraction of the damage the pool dealt to the player as
## healing — innate drain, on top of any regular lifesteal.
## Pools are BloodPoolEntry records ticked by this weapon each physics frame
## (no pool scene); a pool lives pool_ticks * tick_interval seconds.

## Neighborhood radius used to score cluster density around each candidate.
@export var cluster_radius: float = 3.0
## Density scoring stops collecting candidates past this many, bounding the
## O(n^2) neighbor count on huge hordes.
@export var max_cluster_candidates: int = 24
## Blood pool radius (area tomes scale it at throw time).
@export var pool_radius: float = 2.2
## Damage pulses per pool. Lifetime is pool_ticks * tick_interval, so
## "Coagulate" (+1 pulse) also lengthens the pool by one interval.
@export var pool_ticks: int = 6
@export var tick_interval: float = 0.5
## Fraction of pool damage dealt returned to the player as healing.
@export var heal_fraction: float = 0.15
## Enemies farther than this above/below the pool's plane are unaffected.
@export var pool_height_window: float = 1.6
## Flask flight time from hand to impact point.
@export var lob_time: float = 0.5
## Peak height of the flask arc above the straight throw line.
@export var arc_height: float = 3.0
## How far above the impact point the pool visual sits. Enemy origins are
## already at ground level, so this only has to clear the arena floor's top
## face; going below it buries the disc and the rim inside the opaque floor.
@export var pool_ground_offset: float = 0.03

## Floor on tick_interval when advancing a pool. A designer (or a future
## evolution row, which WeaponBase.evolve applies generically) setting it to
## zero would otherwise leave _tick_pools spinning its whole tick budget in
## one frame, sweeping the horde once per pending tick.
const MIN_TICK_INTERVAL: float = 0.01

## Seconds between the flasks a Tome of Multitude adds. Thrown one after
## the other: flasks lobbed together share one arc and shatter into pools
## sitting on the exact same ground, which is a single pool that ticks
## twice rather than a wider wet floor.
const EXTRA_FLASK_STAGGER: float = 0.12
## Yaw between neighboring flasks, swung around the THROWER, so the extra
## pools land beside the cluster instead of inside the first one.
const EXTRA_FLASK_FAN_DEG: float = 22.0
## The whole staggered chain has to end inside this fraction of one
## cooldown, or a volley would still be leaving the hand at the next throw.
const FLASK_CHAIN_WINDOW: float = 0.6


## One live blood pool. A record instead of a loose Dictionary because its
## `visual` is a POOLED node crossing frames: with fields the compiler
## catches a mistyped name, and every read has one obvious home.
class BloodPoolEntry extends RefCounted:
	var center: Vector3 = Vector3.ZERO
	var radius: float = 0.0
	var ticks_left: int = 0
	var tick_timer: float = 0.0
	var visual: BloodPoolFx = null


var _pools: Array[BloodPoolEntry] = []
## Flask visuals still in the air, so a weapon that dies mid-throw takes its
## flasks with it instead of leaving them frozen on the arc.
var _flasks_in_flight: Array[MeshInstance3D] = []

var _flask_mesh: SphereMesh


func _ready() -> void:
	# Same reason as SlimeTrail's: the pool visuals are stage-scoped and
	# these records are not, so the map change is what drops them.
	RunState.stage_changed.connect(
			func(_index: int, _map_id: String) -> void: clear_weapon_fields())
	# The lobbed flask stays a visible projectile — one shared mesh for
	# every throw. The landing pool visual is the pooled BloodPool scene
	# (darker rim + slow bubbles).
	_flask_mesh = SphereMesh.new()
	_flask_mesh.radius = 0.14
	_flask_mesh.height = 0.24
	var flask_material := StandardMaterial3D.new()
	flask_material.albedo_color = Color(0.5, 0.06, 0.1)
	flask_material.emission_enabled = true
	flask_material.emission = Color(0.7, 0.08, 0.1)
	flask_material.emission_energy_multiplier = 1.2
	_flask_mesh.material = flask_material


func _physics_process(delta: float) -> void:
	super(delta)
	_tick_pools(delta)


## Pools and flasks live under the scene root, not under this weapon, so
## nothing frees them when the weapon goes: hand them back by hand or the
## BloodPoolFx instances throb on forever and never park back in Pools.
## Parked straight away rather than faded — expire()'s fade tween would have
## to be created on a node that may already be leaving the tree with us.
func _exit_tree() -> void:
	clear_weapon_fields()
	# Flasks belong to the WEAPON, not to a stage: they are in flight for
	# a fraction of a second and a swap frees them with the arena anyway.
	for flask: MeshInstance3D in _flasks_in_flight:
		if is_instance_valid(flask):
			flask.queue_free()
	_flasks_in_flight.clear()


## The optional half of Player's downed contract, and the stage hook: the
## pool VISUALS are stage-scoped since iteration 49 while these records
## ride across on the raider, so without this _tick_pools kept damaging at
## the old arena's coordinates after a swap, with nothing on screen.
func clear_weapon_fields() -> void:
	for pool: BloodPoolEntry in _pools:
		if pool.visual != null and is_instance_valid(pool.visual):
			Pools.release(pool.visual)
		pool.visual = null
	_pools.clear()


## The in-range enemy with the most neighbors within cluster_radius (among
## the first max_cluster_candidates found) — the flask lands on packs, not
## the nearest straggler. Ties keep the earliest candidate.
func acquire_target() -> Node3D:
	# Empty-horde fast path (see WeaponBase.acquire_target).
	if get_tree().get_first_node_in_group("enemies") == null:
		return null
	var candidates := enemies_in_sphere(global_position, attack_range)
	if candidates.size() > max_cluster_candidates:
		candidates.resize(max_cluster_candidates)
	var best: Node3D = null
	var best_neighbors := -1
	var cluster_sq := cluster_radius * cluster_radius
	for body: Node3D in candidates:
		var neighbors := 0
		for other: Node3D in candidates:
			if other != body and body.global_position \
					.distance_squared_to(other.global_position) <= cluster_sq:
				neighbors += 1
		if neighbors > best_neighbors:
			best_neighbors = neighbors
			best = body
	return best


func fire(target: Node3D) -> void:
	var impact := target.global_position
	var count := maxi(effective_projectile_count(), 1)
	var step := minf(EXTRA_FLASK_STAGGER,
			effective_cooldown() * FLASK_CHAIN_WINDOW / float(maxi(count - 1, 1)))
	for i: int in count:
		var yaw := deg_to_rad(EXTRA_FLASK_FAN_DEG) * (float(i) - float(count - 1) * 0.5)
		# Fanned around the thrower, so the lateral spread grows with the
		# throw distance and the pools stay a lane rather than a stack.
		var spot := global_position + (impact - global_position).rotated(Vector3.UP, yaw)
		if i == 0:
			_throw_at(spot)
		else:
			# Pausable and stepped in physics: an extra flask must not leave
			# while the upgrade UI holds the tree, and the throw belongs on
			# the same tick the rest of the combat runs on.
			get_tree().create_timer(step * float(i), false, true).timeout \
					.connect(_throw_at.bind(spot))


## Throws one flask at `impact`. The staggered extras land here a beat
## later, when this weapon may already have left the tree with a removed
## raider — and a flask thrown from outside the tree has no hand to leave.
func _throw_at(impact: Vector3) -> void:
	if not is_inside_tree():
		return
	_lob_flask(impact)


## Throws the flask visual along a parabolic arc; the pool spawns where it
## lands (the target's position at throw time), lob_time later.
func _lob_flask(impact: Vector3) -> void:
	var flask := spawn_fx_mesh(_flask_mesh)
	var start := global_position + Vector3.UP * 1.2
	flask.global_position = start
	_flasks_in_flight.append(flask)
	# The tween is OURS, not the flask's: its steps call back into this
	# weapon, so binding it to the flask (which lives under the scene root)
	# left it running against a freed weapon if the weapon went first.
	var tween := create_tween()
	# Bound as an INSTANCE ID, never as the node itself: the flask is
	# parented into the arena and a stage swap frees it mid-flight, while
	# this tween — owned by the weapon, which rides the persistent Player
	# across the swap — is still running. Godot cannot marshal a freed
	# Object into a bound argument, so the call fails at the argument
	# BEFORE the is_instance_valid() guard inside the method can run
	# ("Cannot convert argument from Object to Object"). An int always
	# marshals, and the lookup below answers null for a dead one.
	var flask_id := flask.get_instance_id()
	tween.tween_method(_arc_flask.bind(flask_id, start, impact), 0.0, 1.0, lob_time)
	tween.tween_callback(_shatter.bind(flask_id, impact))


## Flight sampler: linear lerp plus an arc lift that peaks mid-flight.
func _arc_flask(progress: float, flask_id: int, start: Vector3, impact: Vector3) -> void:
	var flask := _live_flask(flask_id)
	if flask == null:
		return
	var pos := start.lerp(impact, progress)
	pos.y += arc_height * 4.0 * progress * (1.0 - progress)
	flask.global_position = pos


func _shatter(flask_id: int, impact: Vector3) -> void:
	var flask := _live_flask(flask_id)
	if flask != null:
		flask.queue_free()
	# Rebuilt instead of erased by reference: a flask the stage swap took
	# is already gone, and erase() cannot find a freed entry — the array
	# would grow one dead slot per interrupted throw.
	var kept: Array[MeshInstance3D] = []
	for other: MeshInstance3D in _flasks_in_flight:
		if is_instance_valid(other) and other != flask:
			kept.append(other)
	_flasks_in_flight = kept
	_spawn_pool(impact)


## The flask behind an id, or null once it has been freed.
func _live_flask(flask_id: int) -> MeshInstance3D:
	if not is_instance_id_valid(flask_id):
		return null
	return instance_from_id(flask_id) as MeshInstance3D


func _spawn_pool(center: Vector3) -> void:
	# Pooled visual (disc + darker rim + slow bubbles), scene-root parented.
	var visual := Pools.acquire_scene(Pools.BLOOD_POOL_SCENE) as BloodPoolFx
	var radius := pool_radius * area_scale()
	if visual != null:
		# Just above the floor: the struck body's origin already sits ON the
		# ground, so anything below it renders inside the opaque floor slab.
		visual.play(center + Vector3.UP * pool_ground_offset, radius)
	var pool := BloodPoolEntry.new()
	pool.center = center
	pool.radius = radius
	pool.ticks_left = maxi(roundi(float(pool_ticks) * duration_scale()), 1)
	pool.tick_timer = 0.0
	pool.visual = visual
	_pools.append(pool)


## Advances every pool: pulses come due every tick_interval (the first one
## right after landing); the pool expires one interval after its last
## pulse, so lifetime is exactly ticks * interval.
func _tick_pools(delta: float) -> void:
	var step := maxf(tick_interval, MIN_TICK_INTERVAL)
	# Backward so finished pools can be removed in place.
	for i in range(_pools.size() - 1, -1, -1):
		var pool := _pools[i]
		pool.tick_timer -= delta
		while pool.tick_timer <= 0.0 and pool.ticks_left > 0:
			_pulse_pool(pool)
			pool.ticks_left -= 1
			pool.tick_timer += step
		if pool.ticks_left <= 0 and pool.tick_timer <= 0.0:
			_expire_pool(pool)
			_pools.remove_at(i)


## One damage pulse: every enemy standing in the pool takes a tick through
## the shared funnel, then the player drinks a fraction of the total.
func _pulse_pool(pool: BloodPoolEntry) -> void:
	var dealt_total := damage_all(
			enemies_in_disc(pool.center, pool.radius, pool_height_window))
	if dealt_total > 0.0:
		# Innate drain: same player-heal path lifesteal uses, now paid on
		# the damage that actually landed rather than on the raw roll.
		_lifesteal_heal(dealt_total * heal_fraction)


func _expire_pool(pool: BloodPoolEntry) -> void:
	if pool.visual == null or not is_instance_valid(pool.visual):
		return
	# Fades out, then parks itself back in the Pools.
	pool.visual.expire()
	pool.visual = null
