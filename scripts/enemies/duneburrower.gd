class_name Duneburrower
extends EnemyBase
## Ash Dunes ambusher: cycles between a slow, vulnerable surface chase and
## a burrowed dash. Burrowed it sinks off the enemy layer and out of the
## "enemies" group — weapons can neither target nor hit the moving sand
## mound — slides fast under the player, then telegraphs a disc and erupts
## for area damage before resurfacing vulnerable. Counterplay: step off
## the disc during the windup, then punish the surfaced worm.

enum State { SURFACED, BURROWED, ERUPTING }

const TELEGRAPH_COLOR := Color(0.95, 0.7, 0.25)
const IMPACT_COLOR := Color(1.0, 0.85, 0.45)
const SAND_BURST_COLOR := Color(0.8, 0.66, 0.4)

@export_group("Cycle")
## Vulnerable chase time after each eruption before it burrows again.
@export var surface_duration: float = 4.0
## Failsafe: burrowed pursuit erupts in place after this long, so a faster
## player can't kite an unkillable mound forever.
@export var max_burrow_duration: float = 6.0
## The mound strikes once it slides within this flat range of the player.
@export var strike_trigger_range: float = 1.1
@export var burrow_speed_multiplier: float = 2.4

@export_group("Eruption")
@export var erupt_windup: float = 0.8
@export var erupt_radius: float = 2.0
@export var erupt_damage: float = 14.0
## Ground eruption: a player higher than this above the strike point (a
## mesa ledge) is missed.
@export var erupt_height_window: float = 1.5

var _state: State = State.SURFACED
var _state_timer: float = 0.0
var _strike_point: Vector3 = Vector3.ZERO
var _surface_separation: float = 0.0
# Player body excepted from collision while burrowed (mound passes under).
var _tunneled_player: PhysicsBody3D = null

@onready var _mound: Node3D = $Mound


func _ready() -> void:
	super()
	_state_timer = surface_duration


func _behavior_tick(delta: float) -> void:
	_state_timer -= delta
	if _state_timer > 0.0:
		return
	match _state:
		State.SURFACED:
			_burrow()
		State.BURROWED:
			_begin_eruption()  # failsafe: strike wherever the mound is
		State.ERUPTING:
			_erupt()


func _movement_intent(seek: Vector3, _distance: float) -> Vector3:
	# The mound freezes under its telegraph disc; both other states chase.
	return Vector3.ZERO if _state == State.ERUPTING else seek


func _combat_tick(_player: Node3D, distance: float) -> void:
	if _state == State.BURROWED and distance <= strike_trigger_range:
		_begin_eruption()


func _burrow() -> void:
	_state = State.BURROWED
	_state_timer = max_burrow_duration
	move_speed *= burrow_speed_multiplier
	# Off the enemy layer and out of the group: weapons can't target it,
	# player projectiles (mask 2) pass over, and the horde neither shoves
	# nor avoids it. Mask drops to world-only so the body still rides the
	# floor under gravity — but the player shares layer 1 with the world,
	# so a collision exception is what actually lets the mound slide UNDER
	# them instead of ramming (or climbing) their capsule.
	remove_from_group("enemies")
	collision_layer = 0
	collision_mask = 1
	var player := get_tree().get_first_node_in_group("player") as PhysicsBody3D
	if player != null:
		_tunneled_player = player
		add_collision_exception_with(player)
	_surface_separation = separation_strength
	separation_strength = 0.0
	_visual.visible = false
	_mound.visible = true


func _begin_eruption() -> void:
	if _state == State.ERUPTING:
		return
	_state = State.ERUPTING
	_state_timer = erupt_windup
	# The disc marks where the worm will surface — under the player at
	# trigger time; escaping it during the windup avoids all damage.
	_strike_point = global_position
	Telegraph.spawn_disc(self, _strike_point, erupt_radius, erupt_windup, TELEGRAPH_COLOR)


func _erupt() -> void:
	_state = State.SURFACED
	_state_timer = surface_duration
	move_speed /= burrow_speed_multiplier
	# Any residual slide drift snaps back to the telegraphed spot, so the
	# hit area is exactly what the disc promised.
	global_position.x = _strike_point.x
	global_position.z = _strike_point.z
	add_to_group("enemies")
	collision_layer = 2
	collision_mask = 3
	if _tunneled_player != null and is_instance_valid(_tunneled_player):
		remove_collision_exception_with(_tunneled_player)
	_tunneled_player = null
	separation_strength = _surface_separation
	_mound.visible = false
	_visual.visible = true
	_play_erupt_pop()
	Telegraph.spawn_disc(self, _strike_point, erupt_radius, 0.2, IMPACT_COLOR)
	Sfx.play(&"burrow_pop")
	Juice.shake(0.1, 0.3, 0.4)
	Juice.burst(_strike_point + Vector3.UP * 0.5, SAND_BURST_COLOR, 7)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var to_player := player.global_position - _strike_point
	var height := to_player.y
	to_player.y = 0.0
	if to_player.length() > erupt_radius or absf(height) > erupt_height_window:
		return
	var player_health := Health.find_in(player)
	if player_health != null and not player_health.is_dead:
		player_health.take_damage(erupt_damage, false, self)


## Surfacing squash-and-stretch: the worm pops out of the ground.
func _play_erupt_pop() -> void:
	_visual.scale = Vector3(1.3, 0.15, 1.3)
	var tween := create_tween()
	tween.tween_property(_visual, "scale", Vector3.ONE, 0.28) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
