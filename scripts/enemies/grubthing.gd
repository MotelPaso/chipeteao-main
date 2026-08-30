class_name Grubthing
extends SecretBossBase
## Hidden Hollow Woods miniboss (GDD 6), awakened by the Odd Stump: a fat
## pale larva-beast in an angry mushroom cap. Deliberately simple moveset
## on the boss state-machine pattern — a Lunging Hop (telegraphed landing
## disc it leaps onto; step off it) and a Glob Spit volley (three slow
## arcing spit lobs, each with its own telegraphed splash disc). Payout,
## HP-bar binding, and the character-unlock death flow live on
## SecretBossBase.

enum State { ENTRANCE, PURSUE, HOP_WINDUP, HOP_LEAP, HOP_RECOVER, SPIT }

const TELEGRAPH_COLOR := Color(0.72, 0.85, 0.3)
const IMPACT_COLOR := Color(0.9, 0.95, 0.55)
const GLOB_COLOR := Color(0.62, 0.78, 0.3)

@export var entrance_duration: float = 0.8

@export_group("Lunging Hop")
## Player distance that triggers a hop (no minimum: it flops in place too).
@export var hop_max_range: float = 9.0
@export var hop_windup: float = 0.75
## Airtime of the leap toward the telegraphed landing spot.
@export var hop_leap_time: float = 0.45
@export var hop_recover: float = 0.5
@export var hop_cooldown: float = 2.8
@export var hop_damage: float = 12.0
@export var hop_radius: float = 2.0
## Landing squash is ground-based; a player higher than this is missed.
@export var hop_height_window: float = 1.4
## The leap dash speed is distance/leap_time, capped here.
@export var hop_max_speed: float = 24.0

@export_group("Glob Spit")
@export var spit_min_range: float = 4.0
@export var spit_max_range: float = 16.0
@export var spit_interval: float = 5.5
@export var spit_windup: float = 1.0
@export var glob_count: int = 3
@export var glob_radius: float = 1.5
@export var glob_damage: float = 10.0
## First glob leads the player's spot; the rest scatter within this range.
@export var glob_scatter: float = 2.4
@export var glob_height_window: float = 1.5

var _state: State = State.ENTRANCE
var _state_timer: float = 0.0
var _entrance_played: bool = false
var _hop_cooldown_timer: float = 0.0
var _hop_target: Vector3 = Vector3.ZERO
var _base_move_speed: float = 0.0
var _spit_timer: float = 0.0
var _glob_spots: Array[Vector3] = []
var _cue_tween: Tween


func _ready() -> void:
	super()
	_state_timer = entrance_duration
	_spit_timer = spit_interval * 0.5
	_base_move_speed = move_speed


func _scale_attack_damage(multiplier: float) -> void:
	hop_damage *= multiplier
	glob_damage *= multiplier


func _behavior_tick(delta: float) -> void:
	_hop_cooldown_timer = maxf(_hop_cooldown_timer - delta, 0.0)
	if _state == State.PURSUE:
		_spit_timer = maxf(_spit_timer - delta, 0.0)
		return
	if _state == State.ENTRANCE and not _entrance_played:
		# Deferred off _ready so the trigger has assigned the real spawn
		# position before the arrival ring appears.
		_entrance_played = true
		_play_entrance()
	if _state == State.HOP_LEAP:
		# Arriving early still resolves on the telegraphed disc.
		var to_target := _hop_target - global_position
		to_target.y = 0.0
		if to_target.length() <= 0.35:
			_resolve_hop()
			return
	_state_timer -= delta
	if _state_timer > 0.0:
		return
	match _state:
		State.ENTRANCE:
			_state = State.PURSUE
		State.HOP_WINDUP:
			_begin_leap()
		State.HOP_LEAP:
			_resolve_hop()
		State.HOP_RECOVER:
			_state = State.PURSUE
		State.SPIT:
			_resolve_spit()


func _movement_intent(seek: Vector3, _distance: float) -> Vector3:
	if _state == State.HOP_LEAP:
		var to_target := _hop_target - global_position
		to_target.y = 0.0
		return to_target.normalized() if to_target.length() > 0.001 else Vector3.ZERO
	return seek if _state == State.PURSUE else Vector3.ZERO


func _facing_direction(steer: Vector3, seek: Vector3) -> Vector3:
	if _state == State.ENTRANCE:
		return Vector3.ZERO
	if _state == State.HOP_LEAP:
		return steer
	return seek if seek.length_squared() > 0.0001 else steer


func _combat_tick(player: Node3D, distance: float) -> void:
	if _state != State.PURSUE:
		return
	if _hop_cooldown_timer <= 0.0 and distance <= hop_max_range:
		_start_hop(player)
		return
	if _spit_timer <= 0.0 \
			and distance >= spit_min_range and distance <= spit_max_range:
		_start_spit(player)


## Burrow-burst arrival: pops out of a flash ring where the trigger put it.
func _play_entrance() -> void:
	Sfx.play(&"burrow_pop")
	Sfx.play(&"boss_roar", -3.0)
	Telegraph.spawn_disc(self, global_position, 2.4, 0.45, IMPACT_COLOR)
	_visual.scale = Vector3.ONE * 0.15
	var tween := create_tween()
	tween.tween_property(_visual, "scale", Vector3.ONE, 0.55) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# --- Lunging Hop ------------------------------------------------------------

func _start_hop(player: Node3D) -> void:
	_state = State.HOP_WINDUP
	_state_timer = hop_windup
	_hop_target = player.global_position
	_hop_target.x = clampf(_hop_target.x, -arena_half_extent, arena_half_extent)
	_hop_target.z = clampf(_hop_target.z, -arena_half_extent, arena_half_extent)
	# One disc covers windup + airtime, so the promise holds until landing.
	Telegraph.spawn_disc(self, _hop_target, hop_radius,
			hop_windup + hop_leap_time, TELEGRAPH_COLOR)
	_play_cue_squash(Vector3(1.18, 0.62, 1.18), hop_windup)


func _begin_leap() -> void:
	_state = State.HOP_LEAP
	_state_timer = hop_leap_time
	var flat := _hop_target - global_position
	flat.y = 0.0
	_base_move_speed = move_speed
	move_speed = minf(flat.length() / maxf(hop_leap_time, 0.05), hop_max_speed)
	# Visual-only arc: the body rises and falls while the chassis dashes.
	if _cue_tween != null and _cue_tween.is_valid():
		_cue_tween.kill()
	_cue_tween = create_tween()
	_cue_tween.tween_property(_visual, "scale", Vector3(0.85, 1.25, 0.85), 0.1)
	_cue_tween.parallel().tween_property(_visual, "position:y", 1.1, hop_leap_time * 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_cue_tween.tween_property(_visual, "position:y", 0.0, hop_leap_time * 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _resolve_hop() -> void:
	_state = State.HOP_RECOVER
	_state_timer = hop_recover
	_hop_cooldown_timer = hop_cooldown
	move_speed = _base_move_speed
	Telegraph.spawn_disc(self, _hop_target, hop_radius, 0.2, IMPACT_COLOR)
	Juice.shake(0.15, 0.35)
	Sfx.play(&"burrow_pop", -2.0)
	_play_cue_squash(Vector3.ONE, 0.25)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var to_player := player.global_position - _hop_target
	var height := absf(to_player.y)
	to_player.y = 0.0
	if to_player.length() > hop_radius or height > hop_height_window:
		return
	var player_health := Health.find_in(player)
	if player_health != null and not player_health.is_dead:
		player_health.take_damage(hop_damage, false, self)


# --- Glob Spit --------------------------------------------------------------

func _start_spit(player: Node3D) -> void:
	_state = State.SPIT
	_state_timer = spit_windup
	_spit_timer = spit_interval
	_glob_spots.clear()
	var base := player.global_position
	for i in glob_count:
		var spot := base
		if i > 0:
			var angle := randf() * TAU
			spot += Vector3(cos(angle), 0.0, sin(angle)) \
					* randf_range(glob_scatter * 0.4, glob_scatter)
		spot.x = clampf(spot.x, -arena_half_extent, arena_half_extent)
		spot.z = clampf(spot.z, -arena_half_extent, arena_half_extent)
		_glob_spots.append(spot)
	var mouth := global_position + Vector3.UP * 1.1
	for spot: Vector3 in _glob_spots:
		Telegraph.spawn_disc(self, spot, glob_radius, spit_windup, TELEGRAPH_COLOR)
		_launch_glob_visual(mouth, spot + Vector3.UP * 0.1, spit_windup)
	_play_cue_squash(Vector3(0.92, 1.16, 0.92), 0.25)


func _resolve_spit() -> void:
	_state = State.PURSUE
	_play_cue_squash(Vector3.ONE, 0.25)
	for spot: Vector3 in _glob_spots:
		Telegraph.spawn_disc(self, spot, glob_radius, 0.18, IMPACT_COLOR)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var player_health := Health.find_in(player)
	if player_health == null or player_health.is_dead:
		return
	for spot: Vector3 in _glob_spots:
		var to_player := player.global_position - spot
		var height := absf(to_player.y)
		to_player.y = 0.0
		if to_player.length() <= glob_radius and height <= glob_height_window:
			# One hit max even where splash discs overlap.
			player_health.take_damage(glob_damage, false, self)
			return


## Cosmetic spit lob: a glob sphere arcs from the mouth to the splash spot
## over the windup and frees itself. Damage stays on the disc resolve.
func _launch_glob_visual(from: Vector3, to: Vector3, duration: float) -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var glob := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.24
	mesh.height = 0.48
	var material := StandardMaterial3D.new()
	material.albedo_color = GLOB_COLOR
	material.emission_enabled = true
	material.emission = GLOB_COLOR
	material.emission_energy_multiplier = 0.8
	mesh.material = material
	glob.mesh = mesh
	scene_root.add_child(glob)
	glob.global_position = from
	# Quadratic arc: linear lerp plus a 4t(1-t) parabolic lift (peaks at
	# +arc height mid-flight, zero at both ends).
	var arc_height := 2.2
	var slide := func(t: float) -> void:
		var pos := from.lerp(to, t)
		pos.y += arc_height * 4.0 * t * (1.0 - t)
		glob.global_position = pos
	var tween := glob.create_tween()
	tween.tween_method(slide, 0.0, 1.0, duration)
	tween.tween_callback(glob.queue_free)


func _play_cue_squash(target: Vector3, duration: float) -> void:
	if _cue_tween != null and _cue_tween.is_valid():
		_cue_tween.kill()
	_cue_tween = create_tween()
	_cue_tween.tween_property(_visual, "scale", target, duration) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
