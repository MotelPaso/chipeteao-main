class_name Player
extends CharacterBody3D
## Player controller: WASD movement relative to camera yaw, mouse-look,
## jump, and a Shift+move slide (speed burst + lowered collision).
## At spawn it applies the selected character's loadout (GameConfig ->
## CharacterCatalog row): starting weapon, seal model tint, per-level passive.
## The visual body is the SealRig child (foca.glb); the gameplay capsule
## collision shape is unchanged and stays authoritative for physics.
## apply_root() (Sarcognath's Entomb) locks movement without touching the
## camera or the auto-firing weapons.
##
## Scene contract: the CollisionShape3D's CapsuleShape3D is marked
## `resource_local_to_scene` in Player.tscn. _set_body_height() MUTATES it
## while sliding, and a plain sub-resource is ONE object shared by every
## instance of the packed scene — sliding would resize the whole party's
## capsule and leak the crouched height into the next run.

@export_group("Movement")
## 6.6 (was 6.0, iteration-31 balance): the 160x160 arenas mean more
## travel between points of interest; a ~10% base speed bump keeps the
## loop's tempo without touching the spawn-ring pressure.
@export var move_speed: float = 6.6
@export var acceleration: float = 12.0
@export var air_acceleration: float = 4.0
@export var jump_velocity: float = 8.0

@export_group("Slide")
@export var slide_speed_multiplier: float = 1.8
@export var slide_duration: float = 0.6
@export var slide_cooldown: float = 0.8
@export var slide_collision_height: float = 0.9

## A slide needs real momentum behind it, not a standing start: the body
## must already carry this fraction of its effective speed.
const SLIDE_MIN_SPEED_RATIO: float = 0.5

@export_group("Combat")
## Cap on simultaneous weapons under the Weapons mount; the upgrade pool
## stops offering new-weapon cards once it is reached (5, iteration 38).
@export var max_weapons: int = 5
## Cap on DISTINCT tomes this raider can carry; past it the pool only
## offers deeper stacks of the tomes already held.
@export var max_tomes: int = 5

@export_group("Safety")
## Fail-safe: falling below this world Y (out-of-bounds through some
## geometry gap) teleports the player back to safe ground, no damage.
@export var void_rescue_y: float = -10.0

## Where a void-rescued DOWNED body lands relative to its rescuer: beside
## them, not inside them, so the solver does not shove either raider.
const RESCUE_MATE_OFFSET := Vector3(1.5, 0.5, 0.0)

@export_group("Camera")
@export var mouse_sensitivity: float = 0.003
@export var initial_pitch_deg: float = -20.0
@export var min_pitch_deg: float = -80.0
@export var max_pitch_deg: float = 10.0
## First-person pitch gets the full range; third/free keep the clamps above.
@export var first_person_min_pitch_deg: float = -85.0
@export var first_person_max_pitch_deg: float = 85.0
## Free-orbit zoom range and per-notch step (mouse wheel / pad D-pad).
@export var free_orbit_min_distance: float = 2.5
@export var free_orbit_max_distance: float = 11.0
@export var free_orbit_zoom_step: float = 1.0
## How fast the body turns to face its movement in free-orbit mode.
@export var free_orbit_turn_speed: float = 10.0

## Camera modes cycled per player with the "camera_mode" action:
## THIRD_PERSON is the shipped default (look turns the body), FIRST_PERSON
## collapses the arm to the eyes and hides the own seal, FREE_ORBIT
## decouples look from the body — the camera orbits the player while the
## body faces wherever it walks (weapons auto-aim, so facing is cosmetic).
enum CameraMode { THIRD_PERSON, FIRST_PERSON, FREE_ORBIT }

## Visual layer bit per party slot: the seal rig renders on layer
## RIG_LAYER_BASE + slot + 1 (instead of layer 1) so a first-person camera
## can cull ONLY its own body while teammates' cameras keep seeing it.
const RIG_LAYER_BASE: int = 10

@export_group("Co-op")
## Party slot (0-3). Slot 0 is the scene's built-in player; RunSystems
## assigns 1+ on the extra bodies it spawns in co-op. Decides which input
## device drives this body (see Coop.action / Coop.look_vector).
@export var player_index: int = 0

## Downed teammates revive when an alive player stands inside this radius
## holding their interact action for revive_time seconds.
@export var revive_radius: float = 3.0
@export var revive_time: float = 3.0
## Fraction of max HP a revived player comes back with.
@export var revive_heal_fraction: float = 0.5
## Losing rescuer contact drains progress at this rate (fraction/second).
@export var revive_decay_rate: float = 0.5

## Floating revive prompt: the Label3D metrics interactables already use
## (interactable.gd), lifted clear of the fallen body.
const PROMPT_FONT_SIZE: int = 52
const PROMPT_OUTLINE_SIZE: int = 14
const PROMPT_HEIGHT: float = 2.6
## Sentinel for "the prompt has never been painted", distinct from the
## "not being rescued" percentage.
const PROMPT_PCT_UNSET: int = -2

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var seal_rig: SealRig = $SealRig
@onready var weapons_mount: Node3D = $Weapons
@onready var health: Health = $Health
@onready var _stats: PlayerStats = $Stats
@onready var item_bag: ItemBag = $ItemBag

## Run points (iteration 40): earned per kill by the nearest raider,
## spent on chests, roulettes and springs. Per player, reset every run.
signal points_changed(total: int)
var points: int = 0


func add_points(amount: int) -> void:
	if amount <= 0:
		return
	points += amount
	points_changed.emit(points)


## Deducts if affordable; false (and no change) otherwise.
func spend_points(amount: int) -> bool:
	if amount <= 0:
		# A non-positive price must never move the wallet: without this a
		# negative amount would PAY the player and still report success.
		# Free (0) succeeds, a negative price is a caller bug and is refused.
		return amount == 0
	if amount > points:
		return false
	points -= amount
	points_changed.emit(points)
	return true

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _default_collision_height: float = 1.8
var _default_collision_radius: float = 0.4

var _yaw: float = 0.0
var _pitch: float = 0.0

var _camera_mode: CameraMode = CameraMode.THIRD_PERSON
## Free-orbit state: world-space camera yaw (decoupled from the body) and
## the current zoom distance (_ready seeds it from the authored arm length).
var _orbit_yaw: float = 0.0
var _orbit_distance: float = 0.0
## The scene's authored third-person arm length, restored on mode exit.
var _third_person_arm_length: float = 5.0

## This slot's action names, resolved once at ready. Coop.action() builds a
## String and interns a StringName per call, and the movement/camera reads
## below run several times per physics tick AND per mouse-motion event —
## a 1000 Hz mouse in 4-player co-op turned that into constant garbage.
var _actions: Dictionary[StringName, StringName] = {}

var _is_sliding: bool = false
var _slide_timer: float = 0.0
var _slide_cooldown_timer: float = 0.0
var _slide_direction: Vector3 = Vector3.ZERO

# Time left on an external root (Entomb): movement/jump/slide locked.
var _root_timer: float = 0.0
## Jumps left before touching the floor again (iteration 48): 1 plus
## PlayerStats.extra_jumps, refilled every frame the body is grounded.
## Starts at 1 so a raider spawned mid-air can still jump once.
var _jumps_left: int = 1

var _is_dead: bool = false

## Co-op downed state: the body stays, control and weapons stop, and a
## teammate can revive it (see _tick_downed). Never true in solo.
var _is_downed: bool = false
var _revive_progress: float = 0.0
var _revive_prompt: Label3D = null
var _saved_collision_layer: int = 0
## Last whole percentage painted on the prompt (see _update_revive_prompt).
var _last_prompt_pct: int = PROMPT_PCT_UNSET

## Where this run started; the void fail-safe returns the player here.
var _spawn_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	# Map marker (iteration 52): raiders are always visible on the map,
	# fog or no fog — the minimap's first job is "where am I".
	add_to_group(&"map_markers")
	_spawn_position = global_position
	_cache_slot_actions()
	_apply_character(CharacterCatalog.by_id_or_default(Coop.character_for_slot(player_index)))
	health.died.connect(_on_health_died)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# The camera arm must ignore our own capsule or it pushes the camera in.
	spring_arm.add_excluded_object(get_rid())
	# ...and every TEAMMATE's capsule too: raiders share layer 1 with the
	# world, so without this a mate walking behind you collapses the arm
	# into your own head. Deferred because RunSystems spawns slots 1+ after
	# this _ready runs.
	_exclude_party_from_spring_arm.call_deferred()
	if Coop.is_coop():
		# Split-screen renders through per-viewport follow cameras; the
		# body-local camera only serves as their transform source.
		($SpringArm3D/Camera3D as Camera3D).current = false
	var capsule := collision_shape.shape as CapsuleShape3D
	if capsule != null:
		_default_collision_height = capsule.height
		_default_collision_radius = capsule.radius
	_yaw = rotation.y
	_pitch = deg_to_rad(clamp(initial_pitch_deg, min_pitch_deg, max_pitch_deg))
	spring_arm.rotation.x = _pitch
	_third_person_arm_length = spring_arm.spring_length
	_orbit_distance = clampf(_third_person_arm_length,
			free_orbit_min_distance, free_orbit_max_distance)
	# Own-body visual layer (see RIG_LAYER_BASE): every rig mesh moves off
	# layer 1 onto this player's slot layer, which stays inside every
	# camera's default cull mask — nothing changes until first person
	# strips the bit from this player's own camera.
	_apply_rig_layer(seal_rig)
	# Anything attached to the rig LATER (VFX, an accessory, a curse mark)
	# must get the bit too, or its owner sees it hanging inside their own
	# first-person camera while the body itself is correctly culled.
	seal_rig.child_entered_tree.connect(_apply_rig_layer)


## Resolves this slot's action names once (see _actions).
func _cache_slot_actions() -> void:
	for base: StringName in Coop.BASE_ACTIONS:
		_actions[base] = Coop.action(player_index, base)


## Teammate capsules are obstacles for the camera arm; exclude them all.
func _exclude_party_from_spring_arm() -> void:
	for node: Node in get_tree().get_nodes_in_group("player"):
		var mate := node as Player
		if mate != null and mate != self:
			spring_arm.add_excluded_object(mate.get_rid())


## Visual layer this slot's own body renders on (see RIG_LAYER_BASE).
func rig_visual_layer() -> int:
	return 1 << (RIG_LAYER_BASE + player_index)


## Moves `root` and everything under it onto this slot's rig layer.
func _apply_rig_layer(root: Node) -> void:
	var layer := rig_visual_layer()
	var self_visual := root as VisualInstance3D
	if self_visual != null:
		self_visual.layers = layer
	for node: Node in root.find_children("*", "VisualInstance3D", true, false):
		(node as VisualInstance3D).layers = layer


## This slot's name for a base action ("interact" -> "p2_interact" in
## co-op); interactables ask through interact_action().
func _act(base: StringName) -> StringName:
	return _actions.get(base, base)


func interact_action() -> StringName:
	return _act(&"interact")


## True while this body drives the mouse: solo always, in co-op only the
## keyboard slot.
func _owns_mouse() -> bool:
	return not Coop.is_coop() or Coop.device_for_slot(player_index) == Coop.KEYBOARD_DEVICE


func _unhandled_input(event: InputEvent) -> void:
	if _is_dead:
		return
	# A DOWNED raider keeps LOOK (below) but not the camera-mode/zoom
	# actions: cycling modes re-aims the body yaw, which would spin a
	# face-planted corpse. Being able to turn and watch the fight — and see
	# the rescuer coming — is the whole point.
	if not _is_downed:
		# Camera actions are event-driven so mouse wheel notches and pad
		# buttons both land here, already filtered per slot by the action set.
		if event.is_action_pressed(_act(&"camera_mode")):
			_cycle_camera_mode()
			return
		if _camera_mode == CameraMode.FREE_ORBIT:
			if event.is_action_pressed(_act(&"camera_zoom_in")):
				_set_orbit_distance(_orbit_distance - free_orbit_zoom_step)
				return
			if event.is_action_pressed(_act(&"camera_zoom_out")):
				_set_orbit_distance(_orbit_distance + free_orbit_zoom_step)
				return
	if not _owns_mouse():
		return
	# Esc is owned by the PauseMenu layer (this node is pausable, so it
	# never even sees input while a menu holds the tree paused). Clicking
	# stays as a recapture fallback if the mouse ever ends up free mid-run.
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_apply_look(event.relative)
	elif event is InputEventMouseButton and event.pressed \
			and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## Mouse-look: the settings sensitivity (SaveData.mouse_sensitivity, a
## 0.3x-2.0x multiplier) scales the exported base per event — one autoload
## float read, cheap and always live. In first/third person the yaw turns
## the body; in free orbit it turns only the camera pivot.
func _apply_look(relative: Vector2) -> void:
	var sensitivity: float = mouse_sensitivity * SaveData.mouse_sensitivity
	var wide := _camera_mode == CameraMode.FIRST_PERSON
	_pitch = clamp(_pitch - relative.y * sensitivity,
			deg_to_rad(first_person_min_pitch_deg if wide else min_pitch_deg),
			deg_to_rad(first_person_max_pitch_deg if wide else max_pitch_deg))
	spring_arm.rotation.x = _pitch
	if _camera_mode == CameraMode.FREE_ORBIT:
		_orbit_yaw = wrapf(_orbit_yaw - relative.x * sensitivity, -PI, PI)
	else:
		# Wrapped like the orbit yaw: a long run spinning one way otherwise
		# grows the angle without bound until float32 resolution turns slow
		# mouse movement into visible steps.
		_yaw = wrapf(_yaw - relative.x * sensitivity, -PI, PI)
		rotation.y = _yaw


## One physics tick, as named steps. The order matters and used to live
## only as an implicit top-to-bottom block: timers and the void fail-safe
## run in EVERY state, look runs before the downed cut (a downed raider
## still owns their camera), and only body movement is gated on being up.
func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	_rescue_from_void()

	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		# Landing refills the jump budget (iteration 48). Refilling HERE and
		# not inside _try_jump is what lets a raider who walked off a ledge
		# still spend their mid-air jumps.
		_jumps_left = _max_jumps()

	_apply_stick_look(delta)

	if _is_downed:
		# Downed body: gravity only, plus the teammate-revive countdown.
		velocity.x = 0.0
		velocity.z = 0.0
		_pin_orbit_arm()
		move_and_slide()
		_tick_downed(delta)
		return

	# Tome of Swiftness etc. scale on top of the exported base speed.
	var effective_speed: float = move_speed * _stats.move_speed_multiplier
	var wish_dir := _read_wish_dir()
	_face_movement(wish_dir, delta)
	_pin_orbit_arm()
	_update_slide(delta, wish_dir, effective_speed)
	_apply_horizontal_velocity(delta, wish_dir, effective_speed)
	_try_jump()
	move_and_slide()


## External timers that must keep counting down in EVERY state. The root
## especially: Sarcognath applies Entomb and the killing damage in the same
## call, so "rooted -> downed" is the boss's normal path, and a frozen
## timer would hand the revived raider a fresh 3 s snare.
func _tick_timers(delta: float) -> void:
	_root_timer = maxf(_root_timer - delta, 0.0)
	_slide_cooldown_timer = maxf(_slide_cooldown_timer - delta, 0.0)


## Belt-and-braces void rescue on top of the arena perimeter walls. A body
## that slipped through a geometry gap is put back on solid ground with its
## transient state (slide, root) cleared. A DOWNED body goes to the nearest
## standing teammate rather than its own spawn: the run's start point can
## be 100 m away and nobody would ever find the corpse to revive it.
## Re-records the void-rescue anchor at the body's current position.
## Called by RunSystems.place_party on every stage change (iteration 49):
## the anchor taken at _ready belongs to a map that has been freed, and
## falling through the floor of stage 3 must not teleport a raider to
## where stage 1's spawn used to be.
func anchor_here() -> void:
	_spawn_position = global_position


func _rescue_from_void() -> void:
	if global_position.y >= void_rescue_y:
		return
	var destination := _spawn_position
	if _is_downed:
		var mate := Coop.nearest_player(get_tree(), global_position)
		if mate != null:
			destination = mate.global_position + RESCUE_MATE_OFFSET
	global_position = destination
	velocity = Vector3.ZERO
	if _is_sliding:
		_end_slide()
	_root_timer = 0.0
	# One-line log (project convention): a soak that falls through the
	# floor leaves a trace instead of teleporting silently.
	print("Void rescue: p%d at %.1fs" % [player_index, RunState.run_time])


## Right-stick look (assigned pad in co-op; any pad in solo) shares the
## mouse pipeline, so sensitivity and pitch clamps apply identically.
## Dividing by the base mouse sensitivity converts the radians/second
## stick rate into the pixel-like units _apply_look expects, so the
## user's sensitivity setting still scales pad look the same way.
func _apply_stick_look(delta: float) -> void:
	var stick := Coop.look_vector(player_index)
	if stick == Vector2.ZERO:
		return
	_apply_look(stick * Coop.LOOK_SPEED * delta / maxf(mouse_sensitivity, 0.0001))


## Movement intent for this tick, already flattened and normalized.
## First/third person: input is body-relative (body yaw == view yaw).
## Free orbit: input is CAMERA-relative and the body turns to face
## wherever it walks, so the orbit never drags the character around.
func _read_wish_dir() -> Vector3:
	if is_rooted():
		return Vector3.ZERO
	var input_dir: Vector2 = Input.get_vector(_act(&"move_left"), _act(&"move_right"),
			_act(&"move_forward"), _act(&"move_back"))
	var move_basis := Basis(Vector3.UP, _orbit_yaw) \
			if _camera_mode == CameraMode.FREE_ORBIT else transform.basis
	var wish_dir: Vector3 = move_basis * Vector3(input_dir.x, 0.0, input_dir.y)
	wish_dir.y = 0.0
	return wish_dir.normalized() if wish_dir.length_squared() > 0.0 else Vector3.ZERO


## Free orbit only: the body chases its own movement direction.
func _face_movement(wish_dir: Vector3, delta: float) -> void:
	if _camera_mode != CameraMode.FREE_ORBIT or wish_dir == Vector3.ZERO:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-wish_dir.x, -wish_dir.z),
			minf(free_orbit_turn_speed * delta, 1.0))


## Keeps the arm's WORLD yaw pinned to the orbit yaw regardless of how the
## body just turned (arm yaw is body-relative). Runs while downed too, so
## look still moves a fallen raider's camera in free orbit.
func _pin_orbit_arm() -> void:
	if _camera_mode == CameraMode.FREE_ORBIT:
		spring_arm.rotation.y = wrapf(_orbit_yaw - rotation.y, -PI, PI)


func _update_slide(delta: float, wish_dir: Vector3, effective_speed: float) -> void:
	if _is_sliding:
		_slide_timer -= delta
		if _slide_timer <= 0.0 or not is_on_floor():
			_end_slide()
	elif _can_start_slide(wish_dir, effective_speed):
		_start_slide(wish_dir)


func _apply_horizontal_velocity(delta: float, wish_dir: Vector3,
		effective_speed: float) -> void:
	if is_rooted():
		# Hard stop, not a decel: entombed feet plant instantly.
		velocity.x = 0.0
		velocity.z = 0.0
	elif _is_sliding:
		var slide_velocity: Vector3 = _slide_direction * effective_speed * slide_speed_multiplier
		velocity.x = slide_velocity.x
		velocity.z = slide_velocity.z
	else:
		var target: Vector3 = wish_dir * effective_speed
		var accel: float = acceleration if is_on_floor() else air_acceleration
		velocity.x = move_toward(velocity.x, target.x, accel * delta)
		velocity.z = move_toward(velocity.z, target.z, accel * delta)


func _try_jump() -> void:
	if not Input.is_action_just_pressed(_act(&"jump")) or is_rooted():
		return
	# Multi-jump (iteration 48): the floor jump plus PlayerStats.extra_jumps
	# mid-air ones, refilled on landing (see _physics_process). The rooted
	# and sliding rules are untouched.
	if _jumps_left <= 0:
		return
	_jumps_left -= 1
	if _is_sliding:
		_end_slide()
	velocity.y = jump_velocity


## Jumps available from a standing start: the floor one plus whatever the
## stats layer grants.
func _max_jumps() -> int:
	var stats := PlayerStats.find_in(self)
	return 1 + (stats.extra_jumps if stats != null else 0)


## External snare (Sarcognath's Entomb): locks ground movement, jumping,
## and sliding for `duration` seconds. Weapons keep auto-firing and the
## camera stays free, so a rooted player still fights. Re-application
## extends the lock, never shortens it.
func apply_root(duration: float) -> void:
	if _is_dead or duration <= 0.0:
		return
	if _is_sliding:
		_end_slide()
	_root_timer = maxf(_root_timer, duration)


func is_rooted() -> bool:
	return _root_timer > 0.0


## Applies a CharacterCatalog row: instances the starting weapon under the
## Weapons mount, tints the seal model, registers the passive.
func _apply_character(character: Dictionary) -> void:
	var scene := load(String(character.weapon_scene)) as PackedScene
	if scene == null:
		push_warning("Player: bad starting weapon scene '%s'" % character.weapon_scene)
	else:
		var weapon := scene.instantiate() as Node3D
		# The name must match the WEAPON_LIBRARY node_name so the upgrade
		# pool counts the starting weapon as owned.
		weapon.name = String(character.weapon_node_name)
		weapons_mount.add_child(weapon)
		# Collection discovery: starting weapons count as carried too.
		var weapon_id := UpgradePool.weapon_id_for_node(String(character.weapon_node_name))
		if not weapon_id.is_empty():
			SaveData.bump("used_weapon_" + weapon_id)
	# SealRig duplicates the model's shared material once for this spawn.
	seal_rig.apply_tint(Color(character.tint))
	_stats.set_character_passive(String(character.passive_stat),
			float(character.passive_amount),
			String(character.get("passive_kind", "per_level")),
			float(character.get("passive_base", 0.0)))


func _on_health_died() -> void:
	if _is_dead or _is_downed:
		return
	if _is_sliding:
		_end_slide()
	if Coop.is_coop():
		# Co-op: a fallen raider goes DOWN instead of ending the run — the
		# body stays where it fell and a teammate can revive it. RunManager
		# only declares defeat once every party member is down at once.
		_enter_downed()
		return
	_is_dead = true
	# Freeze control and physics; RunManager pauses the whole tree right
	# after this handler. The rig's face-plant tween is pause-immune so it
	# plays out under the fading run-end screen.
	set_physics_process(false)
	seal_rig.play_death()


# --- camera modes -----------------------------------------------------------

func _cycle_camera_mode() -> void:
	var was_free := _camera_mode == CameraMode.FREE_ORBIT
	_camera_mode = ((int(_camera_mode) + 1) % CameraMode.size()) as CameraMode
	_apply_camera_mode(was_free)


func camera_mode() -> CameraMode:
	return _camera_mode


## This raider's own Camera3D. In co-op none of these is the viewport's
## active camera (SplitScreen renders each one into its own SubViewport),
## so anything that acts ON a camera — FOV kicks, shake — has to be handed
## this instead of asking the viewport which camera is current.
func view_camera() -> Camera3D:
	return spring_arm.get_node_or_null("Camera3D") as Camera3D


func _apply_camera_mode(was_free: bool = false) -> void:
	var camera := view_camera()
	var rig_bit := rig_visual_layer()
	# Every mode change resets the transient state, then the mode sets its own.
	camera.cull_mask |= rig_bit
	spring_arm.rotation.y = 0.0
	if was_free:
		# Leaving free orbit into a body-locked mode: the camera's yaw
		# becomes the body yaw, so the view doesn't snap on the switch.
		_yaw = wrapf(_orbit_yaw, -PI, PI)
		rotation.y = _yaw
	match _camera_mode:
		CameraMode.THIRD_PERSON:
			spring_arm.spring_length = _third_person_arm_length
		CameraMode.FIRST_PERSON:
			# Arm collapsed to the eyes; the own seal is culled from THIS
			# camera only (the rig sits on the slot's visual layer).
			spring_arm.spring_length = 0.05
			camera.cull_mask &= ~rig_bit
		CameraMode.FREE_ORBIT:
			_orbit_yaw = _yaw
			spring_arm.spring_length = _orbit_distance
	# Re-clamp pitch into the mode's range (first person allows more).
	var wide := _camera_mode == CameraMode.FIRST_PERSON
	_pitch = clamp(_pitch,
			deg_to_rad(first_person_min_pitch_deg if wide else min_pitch_deg),
			deg_to_rad(first_person_max_pitch_deg if wide else max_pitch_deg))
	spring_arm.rotation.x = _pitch


func _set_orbit_distance(distance: float) -> void:
	_orbit_distance = clampf(distance, free_orbit_min_distance, free_orbit_max_distance)
	if _camera_mode == CameraMode.FREE_ORBIT:
		spring_arm.spring_length = _orbit_distance


# --- co-op downed / revive --------------------------------------------------

## The five things that flip together when a raider goes down or stands
## back up: group membership (every targeting system keys off "player"),
## ghost collision, weapon ticking, the rig's face-plant and the floating
## prompt. Keeping them in ONE place is what stops the two paths drifting.
func _set_downed(down: bool) -> void:
	_is_downed = down
	_revive_progress = 0.0
	if down:
		# Leaving the "player" group makes every targeting system (enemy
		# seek, gem homing, interact prompts, RunManager's alive count)
		# skip this body with zero extra checks; revive re-joins it.
		remove_from_group("player")
		add_to_group("downed_players")
		# Purge BEFORE the mount stops ticking: a weapon that leaves timed
		# fields behind (blood pools, slime puddles) advances them from its
		# own _physics_process, so freezing the mount strands them on the
		# ground — still throbbing, still holding pooled visuals, dealing
		# nothing — until a revive that may never come.
		_clear_weapon_fields()
		# Weapons stop auto-firing with the body (mount children tick physics).
		weapons_mount.process_mode = Node.PROCESS_MODE_DISABLED
		# Ghost collision: the corpse must not wall off teammates or the horde.
		_saved_collision_layer = collision_layer
		collision_layer = 0
		seal_rig.play_death()
		# Total wipe (nobody left in the group): RunManager ends the run in
		# this same frame and pauses the tree, so a prompt shown now would
		# hang over the end screen — it is no_depth_test — begging for an
		# interaction nobody can make any more.
		if not get_tree().get_nodes_in_group("player").is_empty():
			_show_revive_prompt()
	else:
		remove_from_group("downed_players")
		add_to_group("player")
		weapons_mount.process_mode = Node.PROCESS_MODE_INHERIT
		collision_layer = _saved_collision_layer
		seal_rig.reset_death()
		_hide_revive_prompt()


## Tells every carried weapon that owns a timed ground field to drop it.
## Optional half of the contract: a weapon that keeps such a field exposes
## clear_weapon_fields() (releasing its pooled visuals the way its
## _exit_tree already does), and the ones that keep none need nothing.
func _clear_weapon_fields() -> void:
	for weapon: Node in weapons_mount.get_children():
		if weapon.has_method("clear_weapon_fields"):
			weapon.call("clear_weapon_fields")


func _enter_downed() -> void:
	# An Entomb landed with the killing blow (Sarcognath roots and damages
	# in one call) must not outlive the downed stretch: clear it here so the
	# revived raider comes back able to move.
	_root_timer = 0.0
	_set_downed(true)


func is_downed() -> bool:
	return _is_downed


## While down: any alive teammate inside revive_radius holding THEIR
## interact action fills the revive bar; letting go drains it slowly.
func _tick_downed(delta: float) -> void:
	if not RunState.run_active:
		# The run ended under us (wipe, extraction): drop the world-space
		# prompt instead of leaving it floating over the end screen.
		_hide_revive_prompt()
		return
	var rescuing := false
	for node: Node in get_tree().get_nodes_in_group("player"):
		var mate := node as Player
		if mate == null or not mate.is_inside_tree():
			continue
		if global_position.distance_to(mate.global_position) > revive_radius:
			continue
		if Input.is_action_pressed(mate.interact_action()):
			rescuing = true
			break
	if rescuing:
		# Guarded: revive_time is an @export now, and a 0 there would make
		# every downed raider pop back up on the first frame of contact.
		_revive_progress += delta / maxf(revive_time, 0.01)
		if _revive_progress >= 1.0:
			_revive()
			return
	else:
		_revive_progress = maxf(_revive_progress - revive_decay_rate * delta, 0.0)
	_update_revive_prompt(rescuing)


func _revive() -> void:
	_set_downed(false)
	health.revive(revive_heal_fraction)
	Juice.sparkle(global_position + Vector3.UP * 1.0)
	Sfx.play(&"heal")


## Floating world-space prompt over the downed body (same Label3D scheme
## interactables use), doubling as the revive progress readout.
func _show_revive_prompt() -> void:
	if _revive_prompt == null:
		_revive_prompt = Label3D.new()
		_revive_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_revive_prompt.no_depth_test = true
		_revive_prompt.font_size = PROMPT_FONT_SIZE
		_revive_prompt.outline_size = PROMPT_OUTLINE_SIZE
		_revive_prompt.position = Vector3.UP * PROMPT_HEIGHT
		add_child(_revive_prompt)
	_revive_prompt.visible = true
	_last_prompt_pct = PROMPT_PCT_UNSET
	_update_revive_prompt(false)


func _update_revive_prompt(rescuing: bool) -> void:
	if _revive_prompt == null:
		return
	# The readout only moves on whole-percent steps (~33 of them across the
	# revive), so skip the String build on the other physics ticks.
	var pct := roundi(_revive_progress * 100.0) if rescuing else -1
	if pct == _last_prompt_pct:
		return
	_last_prompt_pct = pct
	if rescuing:
		_revive_prompt.text = "Reviviendo... %d%%" % pct
		_revive_prompt.modulate = Color(0.5, 0.95, 0.6)
	else:
		_revive_prompt.text = "CAÍDO — mantén [Interactuar] cerca"
		_revive_prompt.modulate = Color(1.0, 0.42, 0.35)


func _hide_revive_prompt() -> void:
	if _revive_prompt != null:
		_revive_prompt.visible = false


func _can_start_slide(wish_dir: Vector3, effective_speed: float) -> bool:
	if not Input.is_action_pressed(_act(&"sprint")) or wish_dir == Vector3.ZERO:
		return false
	if not is_on_floor() or _slide_cooldown_timer > 0.0:
		return false
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	return horizontal_speed > effective_speed * SLIDE_MIN_SPEED_RATIO


func _start_slide(direction: Vector3) -> void:
	_is_sliding = true
	_slide_timer = slide_duration
	_slide_direction = direction
	_set_body_height(slide_collision_height)
	Juice.fov_kick_begin(view_camera())
	Sfx.play(&"slide")


func _end_slide() -> void:
	_is_sliding = false
	_slide_cooldown_timer = slide_cooldown
	_set_body_height(_default_collision_height)
	Juice.fov_kick_end(view_camera())


func _set_body_height(height: float) -> void:
	var capsule := collision_shape.shape as CapsuleShape3D
	if capsule == null:
		return
	# Setting height below 2*radius makes Godot shrink the radius, so
	# re-apply the default radius (clamped) to keep restores lossless.
	# Safe to mutate: Player.tscn marks the capsule resource_local_to_scene,
	# so this instance owns its own copy (see the class docstring).
	capsule.height = height
	capsule.radius = minf(_default_collision_radius, height * 0.5)
	collision_shape.position.y = height * 0.5
	# The seal squashes flat and dips its nose to match the low collider.
	seal_rig.set_slide_ratio(height / _default_collision_height)


## Map marker contract (group "map_markers"). The arrow's heading comes
## from this body's own rotation, which is where the raider is facing.
func map_marker_kind() -> StringName:
	return &"player"
