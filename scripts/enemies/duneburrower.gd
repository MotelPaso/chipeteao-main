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
## Group a worm joins WHILE BURROWED, because burrowing takes it out of
## "enemies" and anything that has to reach every live body — the
## spawner's time stop, first of all — would otherwise skip the one enemy
## that can still hurt you from under the sand.
const BURROWED_GROUP: StringName = &"burrowed"
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
# State captured on burrowing and restored on erupting, so a surfaced worm
# always comes back exactly as it went down (rather than to hardcoded
# defaults that drift the moment a scene overrides one of them).
var _surface_separation: float = 0.0
var _surface_speed: float = 0.0
var _surface_layer: int = 0
var _surface_mask: int = 0
# Player bodies excepted from collision while burrowed (the mound has to
# pass under ALL of them: in co-op every raider is an obstacle otherwise).
var _tunneled_players: Array[PhysicsBody3D] = []

@onready var _mound: Node3D = $Mound


func _init() -> void:
	# Not possessable (iteration 56): it caches and restores its own
	# layers and group on every burrow cycle, so a possessed one would
	# keep attacking the party it now belongs to. Only contact fighters,
	# whose _combat_tick damages whatever Health it is handed, can switch
	# sides.
	possessable = false


func _ready() -> void:
	super()
	_state_timer = surface_duration
	# Seeded from the scene so an eruption can always restore a real
	# surfaced state, even on a path that never went through _burrow().
	_surface_speed = move_speed
	_surface_separation = separation_strength
	_surface_layer = collision_layer
	_surface_mask = collision_mask


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
	_surface_speed = move_speed
	_surface_layer = collision_layer
	_surface_mask = collision_mask
	move_speed *= burrow_speed_multiplier
	# Off the enemy layer and out of the group: weapons can't target it,
	# player projectiles (mask 2) pass over, and the horde neither shoves
	# nor avoids it. Mask drops to world-only so the body still rides the
	# floor under gravity — but the player shares layer 1 with the world,
	# so a collision exception is what actually lets the mound slide UNDER
	# them instead of ramming (or climbing) their capsule.
	remove_from_group("enemies")
	# ...but still findable by anything that must reach EVERY live body.
	# Leaving "enemies" is what hides the worm from weapons and from the
	# horde; it also hid it from EnemySpawner's freeze, so Tiempo detenido
	# never stopped a burrowed worm and its eruption landed inside the one
	# window whose whole promise is that nothing can touch you.
	add_to_group(BURROWED_GROUP)
	collision_layer = 0
	collision_mask = 1
	_tunneled_players.clear()
	for node: Node3D in Coop.alive_players(get_tree()):
		var body := node as PhysicsBody3D
		if body == null:
			continue
		_tunneled_players.append(body)
		add_collision_exception_with(body)
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
	# Restored, not divided back: a scene that sets burrow_speed_multiplier
	# to 0 would otherwise divide by zero, and any speed change applied
	# while burrowed (an elite promotion) would survive the round trip
	# scaled by the multiplier.
	move_speed = _surface_speed
	# Any residual slide drift snaps back to the telegraphed spot, so the
	# hit area is exactly what the disc promised.
	global_position.x = _strike_point.x
	global_position.z = _strike_point.z
	add_to_group("enemies")
	remove_from_group(BURROWED_GROUP)
	collision_layer = _surface_layer
	collision_mask = _surface_mask
	for body: PhysicsBody3D in _tunneled_players:
		if is_instance_valid(body):
			remove_collision_exception_with(body)
	_tunneled_players.clear()
	separation_strength = _surface_separation
	_mound.visible = false
	_visual.visible = true
	_play_erupt_pop()
	Telegraph.spawn_disc(self, _strike_point, erupt_radius, 0.2, IMPACT_COLOR)
	Sfx.play(&"burrow_pop")
	Juice.shake(0.1, 0.3, 0.4)
	Juice.burst(_strike_point + Vector3.UP * 0.5, SAND_BURST_COLOR, 7)
	# The disc is an area promise: everyone standing on it eats the strike.
	damage_players_in_disc(_strike_point, erupt_radius, erupt_height_window,
			erupt_damage, self)


# Was missing pre-tiers, so elite/tier damage factors silently skipped the
# burrower; now both land on the eruption.
func _apply_elite_damage(multiplier: float) -> void:
	erupt_damage *= multiplier


## Surfacing squash-and-stretch: the worm pops out of the ground.
func _play_erupt_pop() -> void:
	_visual.scale = Vector3(1.3, 0.15, 1.3)
	var tween := create_tween()
	tween.tween_property(_visual, "scale", Vector3.ONE, 0.28) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
