class_name Fenwraith
extends BossBase
## Gloomfen boss (iteration 37): a drowned marsh spirit that fights at
## range and refuses to be pinned down. State machine on the EnemyBase
## hooks, Rotking-style. Moveset:
##   - Miasma Nova: telegraphed poison burst around itself when crowded
##     (jump or leave the ring during the windup to dodge).
##   - Bog Volley: a fan of slow bolts lobbed at mid range (EnemyBolt,
##     pooled — the skirmisher's projectile, denser).
##   - Sink & Rise: telegraphs a spot near the player, sinks into the
##     marsh, and erupts there — a gap-closer that keeps the fight moving.
## Title/tier/curse/payout/arena-clamp plumbing lives on BossBase; the
## spawner promotes the Elder rematch through apply_tier().

enum State { ENTRANCE, PURSUE, NOVA, VOLLEY, BLINK }

const TELEGRAPH_COLOR := Color(0.35, 0.85, 0.6)
const IMPACT_COLOR := Color(0.6, 1.0, 0.7)
## Sink & Rise: the disc marking both ends of the teleport, and how long
## the shroud takes to unfold again on arrival.
const BLINK_DISC_RADIUS: float = 2.2
const BLINK_RISE_TIME: float = 0.3

@export var entrance_duration: float = 0.9

@export_group("Miasma Nova")
@export var nova_trigger_range: float = 5.0
@export var nova_radius: float = 5.5
@export var nova_damage: float = 22.0
@export var nova_windup: float = 0.9
@export var nova_recover: float = 0.7
@export var nova_cooldown: float = 5.0
## A player higher than this above the boss's footing is missed.
@export var nova_height_window: float = 1.5

@export_group("Bog Volley")
@export var volley_interval: float = 5.5
@export var volley_windup: float = 0.5
@export var volley_min_range: float = 6.0
@export var volley_max_range: float = 22.0
@export var volley_bolt_count: int = 5
@export var volley_spread_degrees: float = 40.0
@export var bolt_damage: float = 9.0
@export var bolt_scene: PackedScene
@export var muzzle_height: float = 1.6
@export var target_height: float = 0.9

@export_group("Sink & Rise")
@export var blink_interval: float = 9.0
@export var blink_trigger_range: float = 12.0
@export var blink_windup: float = 0.7
## The eruption point lands this far from the hunted player.
@export var blink_arrival_distance: float = 5.0

var _state: State = State.ENTRANCE
var _state_timer: float = 0.0
var _entrance_played: bool = false
var _nova_cooldown_timer: float = 0.0
var _nova_resolved: bool = false
var _volley_timer: float = 0.0
var _blink_timer: float = 0.0
var _blink_target: Vector3 = Vector3.ZERO


func _ready() -> void:
	super()
	_state_timer = entrance_duration
	_volley_timer = volley_interval
	_blink_timer = blink_interval * 0.6  # first sink comes a bit early


func _scale_attack_damage(multiplier: float) -> void:
	nova_damage *= multiplier
	bolt_damage *= multiplier


func _behavior_tick(delta: float) -> void:
	_nova_cooldown_timer = maxf(_nova_cooldown_timer - delta, 0.0)
	if _state == State.PURSUE:
		_volley_timer = maxf(_volley_timer - delta, 0.0)
		_blink_timer = maxf(_blink_timer - delta, 0.0)
		return
	if _state == State.ENTRANCE and not _entrance_played:
		_entrance_played = true
		_play_entrance()
	_state_timer -= delta
	if _state_timer > 0.0:
		return
	match _state:
		State.ENTRANCE:
			_state = State.PURSUE
		State.NOVA:
			if _nova_resolved:
				_state = State.PURSUE
			else:
				_resolve_nova()
		State.VOLLEY:
			_resolve_volley()
		State.BLINK:
			_resolve_blink()


func _movement_intent(seek: Vector3, _distance: float) -> Vector3:
	return seek if _state == State.PURSUE else Vector3.ZERO


func _facing_direction(steer: Vector3, seek: Vector3) -> Vector3:
	if _state == State.ENTRANCE:
		return Vector3.ZERO
	return seek if seek.length_squared() > 0.0001 else steer


func _combat_tick(player: Node3D, distance: float) -> void:
	if _state != State.PURSUE:
		return
	if _nova_cooldown_timer <= 0.0 and distance <= nova_trigger_range:
		_start_nova()
		return
	if _blink_timer <= 0.0 and distance >= blink_trigger_range:
		_start_blink(player)
		return
	if _volley_timer <= 0.0 \
			and distance >= volley_min_range and distance <= volley_max_range:
		_start_volley()


func _play_entrance() -> void:
	Sfx.play(&"boss_roar_2")
	_play_boss_entrance(nova_radius * 0.6, IMPACT_COLOR)


## --- Miasma Nova -------------------------------------------------------

func _start_nova() -> void:
	_state = State.NOVA
	_state_timer = nova_windup
	_nova_resolved = false
	Telegraph.spawn_disc(self, global_position, nova_radius, nova_windup, TELEGRAPH_COLOR)


func _resolve_nova() -> void:
	_nova_resolved = true
	_state_timer = nova_recover
	_nova_cooldown_timer = nova_cooldown
	Telegraph.spawn_disc(self, global_position, nova_radius, 0.2, IMPACT_COLOR)
	Juice.shake(0.2, 0.4)
	# Every raider caught in the ring takes it (co-op: the nova is honest),
	# and naming ourselves as the attacker lets thorns answer back.
	damage_players_in_disc(global_position, nova_radius, nova_height_window,
			nova_damage, self)


## --- Bog Volley --------------------------------------------------------

func _start_volley() -> void:
	_state = State.VOLLEY
	_state_timer = volley_windup
	_volley_timer = volley_interval


func _resolve_volley() -> void:
	_state = State.PURSUE
	if bolt_scene == null:
		return
	var player := Coop.nearest_player(get_tree(), global_position)
	if player == null:
		return
	var origin := global_position + Vector3.UP * muzzle_height
	var aim_point := player.global_position + Vector3.UP * target_height
	var base_aim := aim_point - origin
	base_aim.y = 0.0
	if base_aim.length_squared() < 0.01:
		return
	var base_angle := atan2(base_aim.z, base_aim.x)
	var spread := deg_to_rad(volley_spread_degrees)
	var count := maxi(volley_bolt_count, 1)
	for i in count:
		var bolt := Pools.acquire_scene(bolt_scene) as EnemyBolt
		if bolt == null:
			return
		bolt.damage = bolt_damage
		bolt.global_position = origin
		var t := 0.5 if count == 1 else float(i) / float(count - 1)
		var bolt_angle := base_angle + lerpf(-spread * 0.5, spread * 0.5, t)
		var flat_target := origin + Vector3(cos(bolt_angle), 0.0, sin(bolt_angle)) * 10.0
		flat_target.y = aim_point.y
		var aim := (flat_target - origin).normalized()
		bolt.look_at(bolt.global_position + aim, WeaponBase.safe_up(aim))


## --- Sink & Rise -------------------------------------------------------

func _start_blink(player: Node3D) -> void:
	_state = State.BLINK
	_state_timer = blink_windup
	_blink_timer = blink_interval
	var angle := randf() * TAU
	var wanted := player.global_position \
			+ Vector3(cos(angle), 0.0, sin(angle)) * blink_arrival_distance
	wanted.y = global_position.y
	# Hard teleport, so the square clamp is not enough: the arena mask
	# (iteration 44) fills whole cells with 7 m walls, and surfacing inside
	# one leaves the boss perched on rock where no melee can reach it while
	# it keeps lobbing volleys. Same question the spawner asks before every
	# ring spawn.
	_blink_target = _safe_arena_point(wanted)
	Telegraph.spawn_disc(self, _blink_target, BLINK_DISC_RADIUS, blink_windup, TELEGRAPH_COLOR)
	# Sinking cue: the shroud squashes into the marsh during the windup.
	_play_cue(_visual, "scale", Vector3(1.2, 0.1, 1.2), blink_windup * 0.8,
			Tween.TRANS_QUAD, Tween.EASE_IN)


func _resolve_blink() -> void:
	_state = State.PURSUE
	global_position = _blink_target
	Sfx.play(&"burrow_pop")
	Telegraph.spawn_disc(self, global_position, BLINK_DISC_RADIUS, 0.2, IMPACT_COLOR)
	Juice.shake(0.15, 0.3)
	_play_cue(_visual, "scale", Vector3.ONE, BLINK_RISE_TIME,
			Tween.TRANS_BACK, Tween.EASE_OUT)
