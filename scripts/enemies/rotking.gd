class_name Rotking
extends EnemyBase
## Hollow Woods boss: a hulking rotten treant-brute that slowly stalks the
## player and fights through a small state machine layered on the EnemyBase
## hooks. Moveset: a telegraphed close-range Smash (ground-shockwave AoE
## with a jump/slide dodge window), a mid-range Root Burst (three
## telegraphed ground spots that erupt into bark spikes), and a one-shot
## grunt Summon each time its HP falls through an exported threshold.
## The spawner sets boss_title and calls apply_tier() for the stronger
## Elder spawn; the HUD boss bar binds through the "boss_ui" group. Bosses
## never become elites (make_elite is a no-op) and never leave the arena.

enum State { ENTRANCE, PURSUE, SMASH, ROOT_BURST, SUMMON }

const TELEGRAPH_COLOR := Color(1.0, 0.55, 0.12)
const IMPACT_COLOR := Color(1.0, 0.8, 0.35)

@export var boss_title: String = "Rotking"
## Half-size of the arena floor minus a margin; position is clamped so the
## boss (and its root-burst spots) never leave the field.
@export var arena_half_extent: float = 46.0
@export var entrance_duration: float = 0.9

@export_group("Smash")
@export var smash_range: float = 3.5
@export var smash_radius: float = 4.0
@export var smash_damage: float = 25.0
@export var smash_windup: float = 0.7
@export var smash_recover: float = 0.8
@export var smash_cooldown: float = 3.0
## The slam is a ground shockwave: a player higher than this above the
## boss's footing (a well-timed jump, a ledge) is missed.
@export var smash_height_window: float = 1.2

@export_group("Root Burst")
@export var root_burst_interval: float = 6.0
@export var root_burst_windup: float = 0.9
@export var root_burst_radius: float = 1.5
@export var root_burst_damage: float = 15.0
## Distance of the two bracket spots from the player-centered one; they
## line up through the player, leaving a perpendicular escape lane.
@export var root_burst_spread: float = 2.6
@export var root_burst_min_range: float = 3.5
@export var root_burst_max_range: float = 16.0
@export var spike_height_window: float = 1.5

@export_group("Summon")
## HP ratios (descending) that each trigger exactly one summon wave as the
## boss drops through them.
@export var summon_thresholds: Array[float] = [0.75, 0.5, 0.25]
@export var summon_scene: PackedScene
@export var summon_count_min: int = 4
@export var summon_count_max: int = 6
@export var summon_ring_radius: float = 3.2
@export var summon_duration: float = 1.1

@export_group("Reward")
## Death payout: a ring of boss_gem_count gems worth boss_gem_value XP each.
@export var boss_gem_count: int = 8
@export var boss_gem_value: int = 5

@export_group("Tier")
## Extra body scale applied per apply_tier() call (Elder and beyond).
@export var tier_body_scale: float = 1.15

@export_group("Curse")
## Extra HP/damage fraction per curse stack (0.4 = +40% each).
@export var curse_stat_bonus_per_stack: float = 0.4
## Death-payout gem count is multiplied by this once per curse stack.
@export var curse_gem_factor_per_stack: int = 2

var _state: State = State.ENTRANCE
var _state_timer: float = 0.0
var _entrance_played: bool = false
var _smash_cooldown_timer: float = 0.0
var _smash_resolved: bool = false
var _root_burst_timer: float = 0.0
var _root_spots: Array[Vector3] = []
var _thresholds_remaining: Array[float] = []
var _pending_summons: int = 0
var _cue_tween: Tween


func _ready() -> void:
	super()
	_state_timer = entrance_duration
	_root_burst_timer = root_burst_interval
	_thresholds_remaining = summon_thresholds.duplicate()
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_boss_died)
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


## Stronger boss instance (Rotking Elder, future map tiers): multiplies
## survivability, damage, and payout, and bulks the body up slightly.
## Call after the boss is inside the tree.
func apply_tier(multiplier: float) -> void:
	_health.max_hp *= multiplier
	_health.heal_full()
	smash_damage *= multiplier
	root_burst_damage *= multiplier
	boss_gem_value = ceili(float(boss_gem_value) * multiplier)
	scale *= tier_body_scale


## Curse Shrine payoff, applied by the spawner right after any apply_tier:
## every consumed stack adds curse_stat_bonus_per_stack HP/damage, and the
## death gem payout doubles per stack. Call while the boss is in the tree.
func apply_curse(stacks: int) -> void:
	if stacks <= 0:
		return
	var multiplier := 1.0 + curse_stat_bonus_per_stack * float(stacks)
	_health.max_hp *= multiplier
	_health.heal_full()
	smash_damage *= multiplier
	root_burst_damage *= multiplier
	for i in stacks:
		boss_gem_count *= curse_gem_factor_per_stack


func _behavior_tick(delta: float) -> void:
	_smash_cooldown_timer = maxf(_smash_cooldown_timer - delta, 0.0)
	if _state == State.PURSUE:
		_root_burst_timer = maxf(_root_burst_timer - delta, 0.0)
		return
	if _state == State.ENTRANCE and not _entrance_played:
		# Deferred off _ready so the spawner has assigned the real spawn
		# position before the arrival ring appears.
		_entrance_played = true
		_play_entrance()
	_state_timer -= delta
	if _state_timer > 0.0:
		return
	match _state:
		State.ENTRANCE:
			_state = State.PURSUE
		State.SMASH:
			if _smash_resolved:
				_state = State.PURSUE
			else:
				_resolve_smash()
		State.ROOT_BURST:
			_resolve_root_burst()
		State.SUMMON:
			_resolve_summon()


func _movement_intent(seek: Vector3, _distance: float) -> Vector3:
	# Attacks (and the entrance) pause the pursuit.
	return seek if _state == State.PURSUE else Vector3.ZERO


func _facing_direction(steer: Vector3, seek: Vector3) -> Vector3:
	if _state == State.ENTRANCE:
		return Vector3.ZERO
	return seek if seek.length_squared() > 0.0001 else steer


func _combat_tick(player: Node3D, distance: float) -> void:
	if _state != State.PURSUE:
		return
	if _pending_summons > 0:
		_start_summon()
		return
	if _smash_cooldown_timer <= 0.0 and distance <= smash_range:
		_start_smash()
		return
	if _root_burst_timer <= 0.0 \
			and distance >= root_burst_min_range and distance <= root_burst_max_range:
		_start_root_burst(player)


## Ground-slam arrival: the silhouette pops out of a flash ring.
func _play_entrance() -> void:
	Telegraph.spawn_disc(self, global_position, smash_radius * 0.75, 0.45, IMPACT_COLOR)
	_visual.scale = Vector3.ONE * 0.15
	var tween := create_tween()
	tween.tween_property(_visual, "scale", Vector3.ONE, 0.55) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _start_smash() -> void:
	_state = State.SMASH
	_state_timer = smash_windup
	_smash_resolved = false
	Telegraph.spawn_disc(self, global_position, smash_radius, smash_windup, TELEGRAPH_COLOR)
	_play_cue_lean(-0.38, smash_windup)


func _resolve_smash() -> void:
	_smash_resolved = true
	_state_timer = smash_recover
	_smash_cooldown_timer = smash_cooldown
	Telegraph.spawn_disc(self, global_position, smash_radius, 0.2, IMPACT_COLOR)
	_play_cue_lean(0.0, 0.25)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var to_player := player.global_position - global_position
	var height := to_player.y
	to_player.y = 0.0
	if to_player.length() > smash_radius or absf(height) > smash_height_window:
		return
	var player_health := Health.find_in(player)
	if player_health != null and not player_health.is_dead:
		player_health.take_damage(smash_damage)


func _start_root_burst(player: Node3D) -> void:
	_state = State.ROOT_BURST
	_state_timer = root_burst_windup
	_root_burst_timer = root_burst_interval
	_root_spots.clear()
	var base := player.global_position
	_root_spots.append(base)
	var line_angle := randf() * TAU
	for i in 2:
		var spot_angle := line_angle + PI * float(i)
		var spot := base \
				+ Vector3(cos(spot_angle), 0.0, sin(spot_angle)) * root_burst_spread
		spot.x = clampf(spot.x, -arena_half_extent, arena_half_extent)
		spot.z = clampf(spot.z, -arena_half_extent, arena_half_extent)
		_root_spots.append(spot)
	for spot: Vector3 in _root_spots:
		Telegraph.spawn_disc(self, spot, root_burst_radius, root_burst_windup, TELEGRAPH_COLOR)


func _resolve_root_burst() -> void:
	_state = State.PURSUE
	for spot: Vector3 in _root_spots:
		_spawn_spikes(spot)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var player_health := Health.find_in(player)
	if player_health == null or player_health.is_dead:
		return
	for spot: Vector3 in _root_spots:
		var to_player := player.global_position - spot
		var height := absf(to_player.y)
		to_player.y = 0.0
		if to_player.length() <= root_burst_radius and height <= spike_height_window:
			# One hit max even where spot discs overlap.
			player_health.take_damage(root_burst_damage)
			return


func _start_summon() -> void:
	_state = State.SUMMON
	_state_timer = summon_duration
	_pending_summons -= 1
	# Roar cue: the whole silhouette flares up, then settles.
	if _cue_tween != null and _cue_tween.is_valid():
		_cue_tween.kill()
	_cue_tween = create_tween()
	_cue_tween.tween_property(_visual, "scale", Vector3.ONE * 1.14, summon_duration * 0.4) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_cue_tween.tween_property(_visual, "scale", Vector3.ONE, summon_duration * 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _resolve_summon() -> void:
	_state = State.PURSUE
	if summon_scene == null:
		return
	var parent := get_parent()
	if parent == null:
		return
	var count := randi_range(summon_count_min, summon_count_max)
	for i in count:
		var node := summon_scene.instantiate()
		var minion := node as EnemyBase
		if minion == null:
			node.free()
			return
		parent.add_child(minion)
		var ring_angle := TAU * float(i) / float(count)
		var pos := global_position \
				+ Vector3(cos(ring_angle), 0.0, sin(ring_angle)) * summon_ring_radius \
				+ Vector3.UP * 0.1
		pos.x = clampf(pos.x, -arena_half_extent, arena_half_extent)
		pos.z = clampf(pos.z, -arena_half_extent, arena_half_extent)
		minion.global_position = pos


func _on_damaged(_amount: float, current: float) -> void:
	var ratio := current / _health.max_hp
	# A big hit can drop through several thresholds at once; each one still
	# yields its own summon wave, chained one SUMMON state at a time.
	while not _thresholds_remaining.is_empty() and ratio <= _thresholds_remaining[0]:
		_thresholds_remaining.remove_at(0)
		_pending_summons += 1


func _on_boss_died() -> void:
	# The base death flow (kill credit, gems, squash-out) already runs off
	# this signal; the boss only has to stop reading as an active boss.
	remove_from_group("boss")


## Boss payout: a ring of high-value gems instead of the single base gem.
func _drop_xp_gem() -> void:
	if xp_gem_scene == null:
		return
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	for i in boss_gem_count:
		var drop := xp_gem_scene.instantiate()
		var gem := drop as XpGem
		if gem == null:
			drop.free()
			return
		gem.xp_value = boss_gem_value
		scene_root.add_child(gem)
		var gem_angle := TAU * float(i) / float(boss_gem_count)
		gem.global_position = global_position + Vector3.UP * 0.6 \
				+ Vector3(cos(gem_angle), 0.0, sin(gem_angle)) * 1.2


func _play_cue_lean(target_x: float, duration: float) -> void:
	if _cue_tween != null and _cue_tween.is_valid():
		_cue_tween.kill()
	_cue_tween = create_tween()
	_cue_tween.tween_property(_visual, "rotation:x", target_x, duration) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Quick eruption visual: a clutch of bark cones pops out of the ground and
## sinks back; self-frees via its tween.
func _spawn_spikes(center: Vector3) -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var cluster := Node3D.new()
	scene_root.add_child(cluster)
	var spike_mesh := CylinderMesh.new()
	spike_mesh.top_radius = 0.0
	spike_mesh.bottom_radius = 0.16
	spike_mesh.height = 1.1
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.36, 0.26, 0.16)
	material.roughness = 0.95
	spike_mesh.material = material
	for i in 5:
		var spike := MeshInstance3D.new()
		spike.mesh = spike_mesh
		var spike_angle := TAU * float(i) / 5.0
		spike.position = Vector3(cos(spike_angle), 0.0, sin(spike_angle)) \
				* root_burst_radius * 0.5
		spike.rotation = Vector3(randf_range(-0.2, 0.2), 0.0, randf_range(-0.2, 0.2))
		cluster.add_child(spike)
	# Starts buried inside the floor slab, pops up, sinks back.
	cluster.global_position = center - Vector3.UP * 1.2
	var tween := cluster.create_tween()
	tween.tween_property(cluster, "global_position:y", center.y + 0.05, 0.12) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.35)
	tween.tween_property(cluster, "global_position:y", center.y - 1.3, 0.25) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(cluster.queue_free)
