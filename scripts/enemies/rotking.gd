class_name Rotking
extends BossBase
## Hollow Woods boss: a hulking rotten treant-brute that slowly stalks the
## player and fights through a small state machine layered on the EnemyBase
## hooks. Moveset: a telegraphed close-range Smash (ground-shockwave AoE
## with a jump/slide dodge window), a mid-range Root Burst (three
## telegraphed ground spots that erupt into bark spikes), and a one-shot
## grunt Summon each time its HP falls through an exported threshold.
## Title/tier/curse/payout/arena-clamp plumbing lives on BossBase; the
## spawner promotes the Elder rematch through apply_tier().

enum State { ENTRANCE, PURSUE, SMASH, ROOT_BURST, SUMMON }

const TELEGRAPH_COLOR := Color(1.0, 0.55, 0.12)
const IMPACT_COLOR := Color(1.0, 0.8, 0.35)
## Bark-root skin for the shared spike-cluster cue.
const SPIKE_COLOR := Color(0.36, 0.26, 0.16)
const SPIKE_ROUGHNESS: float = 0.95
const SPIKE_BOTTOM_RADIUS: float = 0.16
const SPIKE_LENGTH: float = 1.1
const SPIKE_SINK_DEPTH: float = 1.2

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

var _state: State = State.ENTRANCE
var _state_timer: float = 0.0
var _entrance_played: bool = false
var _smash_cooldown_timer: float = 0.0
var _smash_resolved: bool = false
var _root_burst_timer: float = 0.0
var _root_spots: Array[Vector3] = []
var _thresholds_remaining: Array[float] = []
var _pending_summons: int = 0


func _ready() -> void:
	super()
	_state_timer = entrance_duration
	_root_burst_timer = root_burst_interval
	_thresholds_remaining = summon_thresholds.duplicate()
	_health.damaged.connect(_on_damaged)


func _scale_attack_damage(multiplier: float) -> void:
	smash_damage *= multiplier
	root_burst_damage *= multiplier


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
	Sfx.play(&"boss_roar")
	_play_boss_entrance(smash_radius * 0.75, IMPACT_COLOR)


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
	Juice.shake(0.2, 0.4)
	_play_cue_lean(0.0, 0.25)
	# The shockwave is drawn for the whole party, so it hits the whole
	# party; naming ourselves as the attacker lets thorns answer back.
	damage_players_in_disc(global_position, smash_radius, smash_height_window,
			smash_damage, self)


func _start_root_burst(player: Node3D) -> void:
	_state = State.ROOT_BURST
	_state_timer = root_burst_windup
	_root_burst_timer = root_burst_interval
	_root_spots.clear()
	var base := _clamp_to_arena(player.global_position)
	_root_spots.append(base)
	var line_angle := randf() * TAU
	for i in 2:
		var spot_angle := line_angle + PI * float(i)
		_root_spots.append(_clamp_to_arena(base
				+ Vector3(cos(spot_angle), 0.0, sin(spot_angle)) * root_burst_spread))
	for spot: Vector3 in _root_spots:
		Telegraph.spawn_disc(self, spot, root_burst_radius, root_burst_windup, TELEGRAPH_COLOR)


func _resolve_root_burst() -> void:
	_state = State.PURSUE
	Juice.shake(0.2, 0.4)
	for spot: Vector3 in _root_spots:
		_spawn_spikes(spot)
	# Resolved against the SPOTS, not against whoever is nearest now: the
	# discs were the promise, and one hit max per raider however many of
	# them overlap.
	damage_players_in_discs(_root_spots, root_burst_radius, spike_height_window,
			root_burst_damage, self)


func _start_summon() -> void:
	_state = State.SUMMON
	_state_timer = summon_duration
	# Consumed here, not at resolve: whatever happens to the wave, the
	# threshold must not be able to re-trigger forever.
	_pending_summons -= 1
	# Roar cue: the whole silhouette flares up, then settles.
	var cue := _begin_cue()
	cue.tween_property(_visual, "scale", Vector3.ONE * 1.14, summon_duration * 0.4) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	cue.tween_property(_visual, "scale", Vector3.ONE, summon_duration * 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _resolve_summon() -> void:
	_state = State.PURSUE
	if summon_scene == null:
		push_warning("Rotking: summon_scene is unset; the wave is lost.")
		return
	var parent := get_parent()
	if parent == null:
		return
	var count := randi_range(summon_count_min, summon_count_max)
	for i in count:
		var node := summon_scene.instantiate()
		var minion := node as EnemyBase
		if minion == null:
			# One bad instance must not eat the rest of the wave silently.
			node.free()
			push_warning("Rotking: summon scene root does not extend EnemyBase.")
			continue
		parent.add_child(minion)
		var ring_angle := TAU * float(i) / float(count)
		# Walkable-aware: a minion dropped inside a mask-wall cell would
		# spend the fight climbing back out of the rock.
		minion.global_position = _safe_arena_point(global_position
				+ Vector3(cos(ring_angle), 0.0, sin(ring_angle)) * summon_ring_radius
				+ Vector3.UP * 0.1)


func _on_damaged(_amount: float, current: float) -> void:
	var ratio := current / _health.max_hp
	# A big hit can drop through several thresholds at once; each one still
	# yields its own summon wave, chained one SUMMON state at a time.
	while not _thresholds_remaining.is_empty() and ratio <= _thresholds_remaining[0]:
		_thresholds_remaining.remove_at(0)
		_pending_summons += 1


func _play_cue_lean(target_x: float, duration: float) -> void:
	_play_cue(_visual, "rotation:x", target_x, duration)


## Quick eruption visual: a clutch of bark cones pops out of the ground and
## sinks back (BossBase owns the cue; these consts are the bark skin).
func _spawn_spikes(center: Vector3) -> void:
	_spawn_spike_cluster(center, root_burst_radius * 0.5, SPIKE_COLOR,
			SPIKE_ROUGHNESS, SPIKE_BOTTOM_RADIUS, SPIKE_LENGTH, SPIKE_SINK_DEPTH)
