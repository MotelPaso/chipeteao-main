class_name Sunspitter
extends EnemyBase
## Ash Dunes ranged: a squat scarab that holds a standoff band, aims a
## thin warning line at the player that thickens over the windup, then
## locks a continuous amber beam that ticks damage while an unbroken line
## of sight lasts — any world geometry (mesa, rock, obelisk) blocks the
## beam short, so cover is the counterplay. Afterwards it skitters
## sideways while the beam recharges. The sight ray masks world layer 1
## only (enemies live on layer 2, so they never block or burn) and damage
## goes to the tracked "player" body — the beam can hurt nothing else.

enum State { SKITTER, AIM, FIRE }

const AIM_COLOR := Color(1.0, 0.62, 0.18)
const BEAM_COLOR := Color(1.0, 0.42, 0.1)

@export_group("Standoff Band")
@export var band_inner: float = 10.0
@export var band_outer: float = 14.0

@export_group("Beam")
@export var fire_range: float = 17.0
@export var aim_windup: float = 0.8
@export var beam_duration: float = 1.5
@export var beam_tick_damage: float = 4.0
@export var beam_tick_interval: float = 0.5
@export var beam_cooldown: float = 3.0
## Beam endpoints: leaves at the eye and tracks the player's chest.
@export var muzzle_height: float = 0.55
@export var target_height: float = 0.9

var _state: State = State.SKITTER
var _state_timer: float = 0.0
# Spawn grace so a fresh ring spawn doesn't lase the instant it lands.
var _cooldown_timer: float = 1.2
var _tick_timer: float = 0.0
# Sideways-skitter direction; flips after every beam for variety.
var _strafe_sign: float = 1.0
var _aim_line: BeamVisual
var _beam: BeamVisual
var _hum_held: bool = false


func _ready() -> void:
	super()
	_aim_line = BeamVisual.create(self, AIM_COLOR, 0.05)
	_beam = BeamVisual.create(self, BEAM_COLOR, 0.22)
	_health.died.connect(_on_sunspitter_died)
	_strafe_sign = 1.0 if get_instance_id() % 2 == 0 else -1.0


func _behavior_tick(delta: float) -> void:
	_cooldown_timer = maxf(_cooldown_timer - delta, 0.0)
	if _state == State.SKITTER:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		_abort_attack()
		return
	_state_timer -= delta
	if _state == State.AIM:
		_tick_aim(player)
	elif _state == State.FIRE:
		_tick_fire(player, delta)


func _movement_intent(seek: Vector3, distance: float) -> Vector3:
	if _state != State.SKITTER:
		return Vector3.ZERO  # plants itself to aim and fire
	if distance > band_outer:
		return seek
	if distance < band_inner:
		return -seek
	# Inside the band: sideways skitter while the beam recharges.
	return seek.cross(Vector3.UP) * _strafe_sign


func _facing_direction(steer: Vector3, seek: Vector3) -> Vector3:
	return seek if seek.length_squared() > 0.0001 else steer


func _combat_tick(player: Node3D, distance: float) -> void:
	if _state != State.SKITTER or _cooldown_timer > 0.0:
		return
	# The lower bound keeps the beam math away from the on-our-head case.
	if distance > fire_range or distance < 1.0:
		return
	if not _beam_sight(player, null):
		return  # never aims into a wall
	_state = State.AIM
	_state_timer = aim_windup


func _tick_aim(player: Node3D) -> void:
	# Warning line thickens over the windup — the width is the countdown.
	var progress := 1.0 - clampf(_state_timer / aim_windup, 0.0, 1.0)
	_beam_sight(player, _aim_line, lerpf(0.03, 0.14, progress))
	if _state_timer <= 0.0:
		_begin_fire()


func _tick_fire(player: Node3D, delta: float) -> void:
	if _state_timer <= 0.0:
		_end_fire()
		return
	var sight_clear := _beam_sight(player, _beam)
	_tick_timer -= delta
	if _tick_timer > 0.0:
		return
	_tick_timer += beam_tick_interval
	if not sight_clear:
		return  # blocked tick is consumed, not banked
	var player_health := Health.find_in(player)
	if player_health != null and not player_health.is_dead:
		player_health.take_damage(beam_tick_damage, false, self)


func _begin_fire() -> void:
	_state = State.FIRE
	_state_timer = beam_duration
	_tick_timer = 0.0  # first tick lands on the first beam frame
	_aim_line.clear()
	_acquire_hum()


func _end_fire() -> void:
	_state = State.SKITTER
	_cooldown_timer = beam_cooldown
	_strafe_sign = -_strafe_sign
	_beam.clear()
	_release_hum()


## Raycasts muzzle -> player chest against layer 1 (world + player;
## enemies are layer 2, invisible to it). Paints `line` — when given — up
## to whatever the ray struck, and returns true only when the player body
## itself is the first hit: a clear line of sight.
func _beam_sight(player: Node3D, line: BeamVisual, thickness: float = -1.0) -> bool:
	var from := global_position + Vector3.UP * muzzle_height
	var to := player.global_position + Vector3.UP * target_height
	var ray := PhysicsRayQueryParameters3D.create(from, to, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	var sight_clear := false
	var end := to
	if not hit.is_empty():
		var collider := hit["collider"] as Node3D
		end = hit["position"]
		sight_clear = collider != null and collider.is_in_group("player")
	if line != null:
		line.span(from, end, thickness)
	return sight_clear


func _apply_elite_damage(multiplier: float) -> void:
	beam_tick_damage *= multiplier


func _abort_attack() -> void:
	if _state == State.FIRE:
		_cooldown_timer = maxf(_cooldown_timer, beam_cooldown)
	_state = State.SKITTER
	_aim_line.clear()
	_beam.clear()
	_release_hum()


func _on_sunspitter_died() -> void:
	_abort_attack()


func _exit_tree() -> void:
	# Freed mid-beam (map change, cap culls): never leak a hum reference.
	_release_hum()


func _acquire_hum() -> void:
	if _hum_held:
		return
	_hum_held = true
	Sfx.acquire_loop(&"laser_hum")


func _release_hum() -> void:
	if not _hum_held:
		return
	_hum_held = false
	Sfx.release_loop(&"laser_hum")
