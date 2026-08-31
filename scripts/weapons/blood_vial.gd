extends WeaponBase
## Doc's starting weapon: lobs a crimson flask at the densest enemy cluster
## in range; where it lands it shatters into a lingering blood pool that
## pulses damage ticks (`damage` is per tick, through the shared funnel)
## and returns heal_fraction of the damage the pool dealt to the player as
## healing — innate drain, on top of any regular lifesteal.
## Pools are plain dicts ticked by this weapon each physics frame (no pool
## scene); a pool lives pool_ticks * tick_interval seconds.

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

## Active pools: {center: Vector3, radius: float, ticks_left: int,
## tick_timer: float, visual: BloodPoolFx}.
var _pools: Array[Dictionary] = []

var _flask_mesh: SphereMesh


func _ready() -> void:
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


## The in-range enemy with the most neighbors within cluster_radius (among
## the first max_cluster_candidates found) — the flask lands on packs, not
## the nearest straggler. Ties keep the earliest candidate.
func acquire_target() -> Node3D:
	# Empty-horde fast path (see WeaponBase.acquire_target).
	if get_tree().get_first_node_in_group("enemies") == null:
		return null
	var candidates: Array[Node3D] = []
	var range_sq := attack_range * attack_range
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var body := node as Node3D
		if body == null or not body.is_inside_tree():
			continue
		if global_position.distance_squared_to(body.global_position) > range_sq:
			continue
		candidates.append(body)
		if candidates.size() >= max_cluster_candidates:
			break
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
	_lob_flask(target.global_position)


## Throws the flask visual along a parabolic arc; the pool spawns where it
## lands (the target's position at throw time), lob_time later.
func _lob_flask(impact: Vector3) -> void:
	var flask := MeshInstance3D.new()
	flask.mesh = _flask_mesh
	flask.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var parent_node: Node = get_tree().current_scene
	if parent_node == null:
		parent_node = get_tree().root
	# Scene-root parent so the flask keeps flying while the player moves on.
	parent_node.add_child(flask)
	var start := global_position + Vector3.UP * 1.2
	flask.global_position = start
	var tween := flask.create_tween()
	tween.tween_method(_arc_flask.bind(flask, start, impact), 0.0, 1.0, lob_time)
	tween.tween_callback(_shatter.bind(flask, impact))


## Flight sampler: linear lerp plus an arc lift that peaks mid-flight.
func _arc_flask(progress: float, flask: MeshInstance3D, start: Vector3, impact: Vector3) -> void:
	var pos := start.lerp(impact, progress)
	pos.y += arc_height * 4.0 * progress * (1.0 - progress)
	flask.global_position = pos


func _shatter(flask: MeshInstance3D, impact: Vector3) -> void:
	flask.queue_free()
	_spawn_pool(impact)


func _spawn_pool(center: Vector3) -> void:
	# Pooled visual (disc + darker rim + slow bubbles), scene-root parented.
	var visual := Pools.acquire_scene(Pools.BLOOD_POOL_SCENE) as BloodPoolFx
	var radius := pool_radius * area_scale()
	if visual != null:
		# The disc sits near the floor below the struck body's origin.
		visual.play(center + Vector3.DOWN * 0.75, radius)
	_pools.append({
		"center": center,
		"radius": radius,
		"ticks_left": pool_ticks,
		"tick_timer": 0.0,
		"visual": visual,
	})


## Advances every pool: pulses come due every tick_interval (the first one
## right after landing); the pool expires one interval after its last
## pulse, so lifetime is exactly ticks * interval.
func _tick_pools(delta: float) -> void:
	# Backward so finished pools can be removed in place.
	for i in range(_pools.size() - 1, -1, -1):
		var pool: Dictionary = _pools[i]
		var timer := float(pool.tick_timer) - delta
		var ticks_left := int(pool.ticks_left)
		while timer <= 0.0 and ticks_left > 0:
			_pulse_pool(pool)
			ticks_left -= 1
			timer += tick_interval
		pool.tick_timer = timer
		pool.ticks_left = ticks_left
		if ticks_left <= 0 and timer <= 0.0:
			_expire_pool(pool)
			_pools.remove_at(i)


## One damage pulse: every enemy standing in the pool takes a tick through
## the shared funnel, then the player drinks a fraction of the total.
func _pulse_pool(pool: Dictionary) -> void:
	var center: Vector3 = pool.center
	var radius := float(pool.radius)
	var radius_sq := radius * radius
	var dealt_total := 0.0
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var body := node as Node3D
		if body == null or not body.is_inside_tree():
			continue
		var to_body := body.global_position - center
		if absf(to_body.y) > pool_height_window:
			continue
		to_body.y = 0.0
		if to_body.length_squared() > radius_sq:
			continue
		var health := Health.find_in(body)
		if health != null:
			dealt_total += deal_damage(health)
	if dealt_total > 0.0:
		# Innate drain: same player-heal path lifesteal uses.
		_lifesteal_heal(dealt_total * heal_fraction)


func _expire_pool(pool: Dictionary) -> void:
	var visual := pool.visual as BloodPoolFx
	if visual == null or not is_instance_valid(visual):
		return
	# Fades out, then parks itself back in the Pools.
	visual.expire()
