class_name CofferMimic
extends SecretBossBase
## Hidden Ash Dunes miniboss (GDD 6), lured out by the Humming Skull: a
## sandstone coffer on crab legs with a golden-toothed maw. Moves in fast
## scuttle bursts with short rests, Snaps at melee range (brief telegraphed
## wind-up on the bite spot), and periodically Buries itself — only the lid
## above the sand, bonus armor while dug in — before popping out with a
## telegraphed shockwave. Payout, HP-bar binding, and the character-unlock
## death flow live on SecretBossBase.

enum State { ENTRANCE, PURSUE, SNAP_WINDUP, SNAP_RECOVER, BURIED }

const TELEGRAPH_COLOR := Color(0.98, 0.75, 0.25)
const IMPACT_COLOR := Color(1.0, 0.88, 0.5)

@export var entrance_duration: float = 0.8

@export_group("Scuttle")
## The chassis move_speed is the burst speed; rests stand still.
@export var scuttle_burst_time: float = 0.8
@export var scuttle_rest_time: float = 0.6

@export_group("Snap")
## Player distance that triggers a bite.
@export var snap_range: float = 2.4
## Bite disc radius around the spot the maw locks onto.
@export var snap_radius: float = 1.8
@export var snap_damage: float = 14.0
@export var snap_windup: float = 0.45
@export var snap_recover: float = 0.55
@export var snap_cooldown: float = 2.2
@export var snap_height_window: float = 1.3

@export_group("Bury")
@export var bury_interval: float = 8.0
## Seconds dug in (also the pop-out shockwave's telegraph time).
@export var bury_duration: float = 2.0
## Flat armor added to the Health component while buried.
@export var bury_armor_bonus: float = 6.0
## How far the body sinks: tuned so only the lid clears the sand.
@export var bury_sink_depth: float = 0.85
@export var shockwave_radius: float = 3.0
@export var shockwave_damage: float = 10.0
@export var shockwave_height_window: float = 1.5

var _state: State = State.ENTRANCE
var _state_timer: float = 0.0
var _entrance_played: bool = false
var _scuttle_timer: float = 0.0
var _scuttle_resting: bool = false
var _snap_cooldown_timer: float = 0.0
var _snap_point: Vector3 = Vector3.ZERO
var _bury_timer: float = 0.0
var _buried_armor_applied: bool = false
var _cue_tween: Tween

@onready var _lid_pivot: Node3D = $Visual/LidPivot
@onready var _lid_rest_angle: float = _lid_pivot.rotation.x


func _ready() -> void:
	super()
	_state_timer = entrance_duration
	_scuttle_timer = scuttle_burst_time
	_bury_timer = bury_interval


func _scale_attack_damage(multiplier: float) -> void:
	snap_damage *= multiplier
	shockwave_damage *= multiplier


func _behavior_tick(delta: float) -> void:
	_snap_cooldown_timer = maxf(_snap_cooldown_timer - delta, 0.0)
	if _state == State.PURSUE:
		_bury_timer = maxf(_bury_timer - delta, 0.0)
		_scuttle_timer -= delta
		if _scuttle_timer <= 0.0:
			_scuttle_resting = not _scuttle_resting
			_scuttle_timer = scuttle_rest_time if _scuttle_resting else scuttle_burst_time
		return
	if _state == State.ENTRANCE and not _entrance_played:
		# Deferred off _ready so the trigger has assigned the real spawn
		# position before the arrival ring appears.
		_entrance_played = true
		_play_entrance()
	_state_timer -= delta
	if _state_timer > 0.0:
		return
	match _state:
		State.ENTRANCE:
			_state = State.PURSUE
		State.SNAP_WINDUP:
			_resolve_snap()
		State.SNAP_RECOVER:
			_state = State.PURSUE
		State.BURIED:
			_resolve_bury()


func _movement_intent(seek: Vector3, _distance: float) -> Vector3:
	if _state != State.PURSUE or _scuttle_resting:
		return Vector3.ZERO
	return seek


func _facing_direction(steer: Vector3, seek: Vector3) -> Vector3:
	if _state == State.ENTRANCE or _state == State.BURIED:
		return Vector3.ZERO
	return seek if seek.length_squared() > 0.0001 else steer


func _combat_tick(player: Node3D, distance: float) -> void:
	if _state != State.PURSUE:
		return
	if _bury_timer <= 0.0:
		_start_bury()
		return
	if _snap_cooldown_timer <= 0.0 and distance <= snap_range:
		_start_snap(player)


## Sand-burst arrival with the desert roar voice.
func _play_entrance() -> void:
	Sfx.play(&"burrow_pop")
	Sfx.play(&"boss_roar_2", -3.0)
	Telegraph.spawn_disc(self, global_position, 2.4, 0.45, IMPACT_COLOR)
	_visual.scale = Vector3.ONE * 0.15
	var tween := create_tween()
	tween.tween_property(_visual, "scale", Vector3.ONE, 0.55) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# --- Snap -------------------------------------------------------------------

func _start_snap(player: Node3D) -> void:
	_state = State.SNAP_WINDUP
	_state_timer = snap_windup
	_snap_point = player.global_position
	_snap_point.x = clampf(_snap_point.x, -arena_half_extent, arena_half_extent)
	_snap_point.z = clampf(_snap_point.z, -arena_half_extent, arena_half_extent)
	Telegraph.spawn_disc(self, _snap_point, snap_radius, snap_windup, TELEGRAPH_COLOR)
	_play_lid(1.15, snap_windup)


func _resolve_snap() -> void:
	_state = State.SNAP_RECOVER
	_state_timer = snap_recover
	_snap_cooldown_timer = snap_cooldown
	Telegraph.spawn_disc(self, _snap_point, snap_radius, 0.15, IMPACT_COLOR)
	Sfx.play(&"hit_crit", -3.0)
	_play_lid(_lid_rest_angle, 0.12)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var to_player := player.global_position - _snap_point
	var height := absf(to_player.y)
	to_player.y = 0.0
	if to_player.length() > snap_radius or height > snap_height_window:
		return
	var player_health := Health.find_in(player)
	if player_health != null and not player_health.is_dead:
		player_health.take_damage(snap_damage, false, self)


# --- Bury -------------------------------------------------------------------

func _start_bury() -> void:
	_state = State.BURIED
	_state_timer = bury_duration
	_bury_timer = bury_interval
	if not _buried_armor_applied:
		_buried_armor_applied = true
		_health.armor += bury_armor_bonus
	Sfx.play(&"burrow_pop", -2.0)
	# The whole bury reads as the shockwave countdown.
	Telegraph.spawn_disc(self, global_position, shockwave_radius,
			bury_duration, TELEGRAPH_COLOR)
	_play_lid(0.0, 0.15)
	if _cue_tween != null and _cue_tween.is_valid():
		_cue_tween.kill()
	_cue_tween = create_tween()
	_cue_tween.tween_property(_visual, "position:y", -bury_sink_depth, 0.25) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _resolve_bury() -> void:
	_state = State.PURSUE
	_scuttle_resting = false
	_scuttle_timer = scuttle_burst_time
	if _buried_armor_applied:
		_buried_armor_applied = false
		_health.armor -= bury_armor_bonus
	Telegraph.spawn_disc(self, global_position, shockwave_radius, 0.2, IMPACT_COLOR)
	Sfx.play(&"burrow_pop")
	Juice.shake(0.15, 0.35)
	if _cue_tween != null and _cue_tween.is_valid():
		_cue_tween.kill()
	_cue_tween = create_tween()
	_cue_tween.tween_property(_visual, "position:y", 0.0, 0.2) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var to_player := player.global_position - global_position
	var height := absf(to_player.y)
	to_player.y = 0.0
	if to_player.length() > shockwave_radius or height > shockwave_height_window:
		return
	var player_health := Health.find_in(player)
	if player_health != null and not player_health.is_dead:
		player_health.take_damage(shockwave_damage, false, self)


func _play_lid(target_x: float, duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(_lid_pivot, "rotation:x", target_x, duration) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
