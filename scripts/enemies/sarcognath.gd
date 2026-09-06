class_name Sarcognath
extends BossBase
## Ash Dunes boss: a massive entombed jackal-sarcophagus construct that
## hover-stalks the player. Moveset on the Rotking state-machine pattern:
## a Sweep Beam (telegraphed rotating warning line, then a radial laser
## that scythes through an arc — run with it, hop the line, or stand in
## the uncovered gap), Sand Coffins (a ring of eruption discs around the
## player with one gap slot plus one disc on their feet — find the gap),
## and a once-per-HP-threshold Entomb that roots a player caught on its
## disc (Player.apply_root; weapons keep firing). Title/tier/curse/payout
## plumbing lives on BossBase; the Elder rematch comes via apply_tier().

enum State { ENTRANCE, PURSUE, SWEEP, COFFINS, ENTOMB }

const TELEGRAPH_COLOR := Color(0.25, 0.95, 0.8)
const BEAM_COLOR := Color(0.15, 1.0, 0.85)
const SAND_COLOR := Color(0.95, 0.72, 0.28)
const SAND_IMPACT_COLOR := Color(1.0, 0.86, 0.5)
## Cut-sandstone skin for the shared spike-cluster cue.
const SPIKE_COLOR := Color(0.74, 0.6, 0.38)
const SPIKE_ROUGHNESS: float = 0.9
const SPIKE_BOTTOM_RADIUS: float = 0.2
const SPIKE_LENGTH: float = 1.2
const SPIKE_SINK_DEPTH: float = 1.3

@export var entrance_duration: float = 1.0
## Arrival ring: sized by hand here (the Sarcognath has no melee radius to
## derive it from, unlike the other bosses).
const ENTRANCE_RING_RADIUS: float = 3.0

@export_group("Sweep Beam")
@export var sweep_windup: float = 1.0
@export var sweep_duration: float = 3.0
@export var sweep_arc_deg: float = 120.0
@export var sweep_length: float = 15.0
@export var sweep_tick_damage: float = 8.0
@export var sweep_tick_interval: float = 0.5
@export var sweep_cooldown: float = 8.0
@export var sweep_max_range: float = 14.0
## Angular half-width of the beam's hit wedge.
@export var sweep_hit_half_angle_deg: float = 7.0
## The beam scythes at chest height: feet higher than this above the
## boss's footing (a timed jump, a mesa) pass over it.
@export var sweep_height_window: float = 1.2
@export var beam_height: float = 0.9

@export_group("Sand Coffins")
@export var coffin_interval: float = 6.0
@export var coffin_windup: float = 1.0
## Evenly spaced ring slots around the player; one random slot stays empty
## (the escape gap) and one extra disc lands on the player's feet.
@export var coffin_ring_slots: int = 5
@export var coffin_ring_radius: float = 2.6
@export var coffin_radius: float = 1.6
@export var coffin_damage: float = 12.0
@export var coffin_min_range: float = 3.0
@export var coffin_max_range: float = 18.0
@export var coffin_height_window: float = 1.5

@export_group("Entomb")
## HP ratios (descending) that each trigger exactly one Entomb cast as the
## boss drops through them.
@export var entomb_thresholds: Array[float] = [0.66, 0.33]
@export var entomb_windup: float = 1.2
@export var entomb_radius: float = 2.0
@export var entomb_damage: float = 10.0
@export var entomb_root_duration: float = 1.5
@export var entomb_height_window: float = 1.5

var _state: State = State.ENTRANCE
var _state_timer: float = 0.0
var _entrance_played: bool = false
var _sweep_cooldown_timer: float = 3.0  # first sweep lands early
var _sweep_firing: bool = false
var _sweep_angle: float = 0.0
var _sweep_sign: float = 1.0
## Burn cadence PER raider (instance id -> seconds until this body can be
## burned again). The beam is an area attack, so two raiders standing in it
## must both burn on their own sweep_tick_interval instead of sharing one.
var _sweep_tick_cd: Dictionary[int, float] = {}
var _coffin_timer: float = 0.0
var _coffin_spots: Array[Vector3] = []
var _entomb_spot: Vector3 = Vector3.ZERO
var _thresholds_remaining: Array[float] = []
var _pending_entombs: int = 0
var _warn_line: BeamVisual
var _beam: BeamVisual
var _hum_held: bool = false
var _hover_time: float = 0.0
var _hover_base: float = 0.0


func _ready() -> void:
	super()
	_state_timer = entrance_duration
	_coffin_timer = coffin_interval * 0.6
	_thresholds_remaining = entomb_thresholds.duplicate()
	_warn_line = BeamVisual.create(self, TELEGRAPH_COLOR, 0.06)
	_beam = BeamVisual.create(self, BEAM_COLOR, 0.3)
	_hover_base = _visual.position.y
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_sarcognath_died)


func _behavior_tick(delta: float) -> void:
	_hover_time += delta
	_visual.position.y = _hover_base + sin(_hover_time * 2.0) * 0.09
	_sweep_cooldown_timer = maxf(_sweep_cooldown_timer - delta, 0.0)
	if _state == State.PURSUE:
		_coffin_timer = maxf(_coffin_timer - delta, 0.0)
		return
	if _state == State.ENTRANCE and not _entrance_played:
		# Deferred off _ready so the spawner has assigned the real spawn
		# position before the arrival ring appears.
		_entrance_played = true
		_play_entrance()
	_state_timer -= delta
	if _state == State.SWEEP:
		_tick_sweep(delta)
	if _state_timer > 0.0:
		return
	match _state:
		State.ENTRANCE:
			_state = State.PURSUE
		State.SWEEP:
			_advance_sweep_phase()
		State.COFFINS:
			_resolve_coffins()
		State.ENTOMB:
			_resolve_entomb()


func _movement_intent(seek: Vector3, _distance: float) -> Vector3:
	# Attacks (and the entrance) pause the hover-stalk.
	return seek if _state == State.PURSUE else Vector3.ZERO


func _facing_direction(steer: Vector3, seek: Vector3) -> Vector3:
	if _state == State.ENTRANCE:
		return Vector3.ZERO
	if _state == State.SWEEP:
		# The crest tracks its own beam while it scythes.
		return Vector3(cos(_sweep_angle), 0.0, sin(_sweep_angle))
	return seek if seek.length_squared() > 0.0001 else steer


func _combat_tick(player: Node3D, distance: float) -> void:
	if _state != State.PURSUE:
		return
	if _pending_entombs > 0:
		_start_entomb(player)
		return
	if _sweep_cooldown_timer <= 0.0 and distance <= sweep_max_range:
		_start_sweep(player)
		return
	if _coffin_timer <= 0.0 \
			and distance >= coffin_min_range and distance <= coffin_max_range:
		_start_coffins(player)


func _scale_attack_damage(multiplier: float) -> void:
	sweep_tick_damage *= multiplier
	coffin_damage *= multiplier
	entomb_damage *= multiplier


## Rises out of a flash ring with the second roar voice.
func _play_entrance() -> void:
	Sfx.play(&"boss_roar_2")
	_play_boss_entrance(ENTRANCE_RING_RADIUS, SAND_IMPACT_COLOR)


# --- Sweep Beam -------------------------------------------------------------

func _start_sweep(player: Node3D) -> void:
	_state = State.SWEEP
	_sweep_firing = false
	_state_timer = sweep_windup
	_sweep_sign = 1.0 if randf() < 0.5 else -1.0
	var to_player := player.global_position - global_position
	var player_angle := atan2(to_player.z, to_player.x)
	# Start half the arc behind the player's bearing so the beam crosses
	# their spot mid-sweep: stand still and get clipped, or move with it,
	# hop the line, or step into the 240 degrees it never covers.
	_sweep_angle = player_angle - _sweep_sign * deg_to_rad(sweep_arc_deg) * 0.5


func _tick_sweep(delta: float) -> void:
	var origin := global_position + Vector3.UP * beam_height
	if not _sweep_firing:
		# Warning line: creeps a few degrees into the coming arc (reads as
		# rotation direction) and thickens as the windup runs out.
		var progress := 1.0 - clampf(_state_timer / sweep_windup, 0.0, 1.0)
		var warn_angle := _sweep_angle + progress * deg_to_rad(12.0) * _sweep_sign
		var warn_to := origin \
				+ Vector3(cos(warn_angle), 0.0, sin(warn_angle)) * sweep_length
		_warn_line.span(origin, warn_to, lerpf(0.04, 0.16, progress))
		return
	_sweep_angle += deg_to_rad(sweep_arc_deg) / sweep_duration * delta * _sweep_sign
	var beam_to := origin \
			+ Vector3(cos(_sweep_angle), 0.0, sin(_sweep_angle)) * sweep_length
	_beam.span(origin, beam_to)
	# Every raider the wedge crosses burns, each on their own cadence: the
	# laser is 120 degrees of area, not a single-target attack.
	for player: Node3D in Coop.alive_players(get_tree()):
		var id := player.get_instance_id()
		var cooldown := maxf(float(_sweep_tick_cd.get(id, 0.0)) - delta, 0.0)
		_sweep_tick_cd[id] = cooldown
		if cooldown > 0.0 or not _sweep_contact(player):
			continue
		var player_health := Health.find_in(player)
		if player_health == null or player_health.is_dead:
			continue
		_sweep_tick_cd[id] = sweep_tick_interval
		player_health.take_damage(sweep_tick_damage, false, self)


## True while the player stands in the beam's current wedge: inside its
## reach, inside its angular width, and not above the height window.
func _sweep_contact(player: Node3D) -> bool:
	var to_player := player.global_position - global_position
	var height := to_player.y
	to_player.y = 0.0
	var dist := to_player.length()
	if dist > sweep_length or dist < 0.2:
		return false
	if absf(height) > sweep_height_window:
		return false
	var player_angle := atan2(to_player.z, to_player.x)
	return absf(angle_difference(_sweep_angle, player_angle)) \
			<= deg_to_rad(sweep_hit_half_angle_deg)


func _advance_sweep_phase() -> void:
	if not _sweep_firing:
		_sweep_firing = true
		_state_timer = sweep_duration
		_sweep_tick_cd.clear()
		_warn_line.clear()
		_acquire_hum()
		return
	_end_sweep()


func _end_sweep() -> void:
	_state = State.PURSUE
	_sweep_firing = false
	_sweep_cooldown_timer = sweep_cooldown
	# Dropped here rather than kept: ids of raiders who left (or died) would
	# otherwise linger in the map for the rest of the fight.
	_sweep_tick_cd.clear()
	_beam.clear()
	_release_hum()


# --- Sand Coffins -----------------------------------------------------------

func _start_coffins(player: Node3D) -> void:
	_state = State.COFFINS
	_state_timer = coffin_windup
	_coffin_timer = coffin_interval
	_coffin_spots.clear()
	# Clamped like the ring slots: a player standing past the arena edge
	# (clamped climbers, knockback) would otherwise get a disc off-field.
	var base := _clamp_to_arena(player.global_position)
	_coffin_spots.append(base)  # the on-player disc forces a move
	var base_angle := randf() * TAU
	var gap_slot := randi_range(0, coffin_ring_slots - 1)
	for i in coffin_ring_slots:
		if i == gap_slot:
			continue
		var slot_angle := base_angle + TAU * float(i) / float(coffin_ring_slots)
		_coffin_spots.append(_clamp_to_arena(base
				+ Vector3(cos(slot_angle), 0.0, sin(slot_angle)) * coffin_ring_radius))
	for spot: Vector3 in _coffin_spots:
		Telegraph.spawn_disc(self, spot, coffin_radius, coffin_windup, SAND_COLOR)


func _resolve_coffins() -> void:
	_state = State.PURSUE
	Juice.shake(0.2, 0.4)
	for spot: Vector3 in _coffin_spots:
		_spawn_sand_spikes(spot)
	# Against the marked SPOTS and the whole party: the raider the ring was
	# drawn around may no longer be the nearest one by now.
	damage_players_in_discs(_coffin_spots, coffin_radius, coffin_height_window,
			coffin_damage, self)


# --- Entomb -----------------------------------------------------------------

func _start_entomb(player: Node3D) -> void:
	_state = State.ENTOMB
	_state_timer = entomb_windup
	_pending_entombs -= 1
	# Marked on the player's feet: keep moving and it whiffs entirely.
	_entomb_spot = _clamp_to_arena(player.global_position)
	Telegraph.spawn_disc(self, _entomb_spot, entomb_radius, entomb_windup, TELEGRAPH_COLOR)


func _resolve_entomb() -> void:
	_state = State.PURSUE
	Telegraph.spawn_disc(self, _entomb_spot, entomb_radius, 0.2, SAND_IMPACT_COLOR)
	_spawn_sand_spikes(_entomb_spot)
	Juice.shake(0.15, 0.35)
	# Anyone caught on the marked disc is rooted, not just the nearest
	# raider: the mark is the promise, the same one everybody could see.
	for caught: Node3D in damage_players_in_disc(_entomb_spot, entomb_radius,
			entomb_height_window, entomb_damage, self):
		var body := caught as Player
		if body != null:
			body.apply_root(entomb_root_duration)


# --- shared bits ------------------------------------------------------------

func _on_damaged(_amount: float, current: float) -> void:
	var ratio := current / _health.max_hp
	# A big hit can drop through both thresholds at once; each still yields
	# its own Entomb cast, chained one ENTOMB state at a time.
	while not _thresholds_remaining.is_empty() and ratio <= _thresholds_remaining[0]:
		_thresholds_remaining.remove_at(0)
		_pending_entombs += 1


func _on_sarcognath_died() -> void:
	_warn_line.clear()
	_beam.clear()
	_release_hum()


func _exit_tree() -> void:
	# Freed mid-sweep (run teardown): never leak a hum reference.
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


## Sandstone spike cluster popping out of the ground and sinking back: the
## Rotking's silhouette recolored to cut sandstone (BossBase owns the cue).
func _spawn_sand_spikes(center: Vector3) -> void:
	_spawn_spike_cluster(center, coffin_radius * 0.5, SPIKE_COLOR,
			SPIKE_ROUGHNESS, SPIKE_BOTTOM_RADIUS, SPIKE_LENGTH, SPIKE_SINK_DEPTH)
