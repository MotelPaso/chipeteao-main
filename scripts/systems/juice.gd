extends Node
## Autoload "Juice": the game-feel layer (GDD 1: kinetic, satisfying
## spectacle). Central, cheap helpers every system calls directly —
## trauma-based camera shake, guarded hit-stop, shared-material hit
## flashes, death particle bursts, a damage vignette, the level-up ring
## pulse, and the slide FOV kick. Everything is pause-safe (this node
## always processes; restores run under a paused tree) and headless-safe
## (camera/scene lookups are guarded, so no-window runs never crash).

const VIGNETTE_SHADER: String = """
shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.82, 0.06, 0.05, 1.0);

void fragment() {
	float edge = smoothstep(0.3, 0.75, length(UV - vec2(0.5)));
	COLOR = vec4(tint.rgb, edge * intensity);
}
"""

@export_group("Camera Shake")
## Peak camera offset (meters) at full trauma.
@export var shake_max_offset: float = 0.4
## How fast the shake noise is sampled; higher = jitterier.
@export var shake_noise_speed: float = 10.0
@export var kill_shake_strength: float = 0.05
## Horde deaths pool trauma only up to this cap, so a mass wipe reads as a
## rumble instead of an earthquake.
@export var kill_shake_cap: float = 0.18
@export var hurt_shake_strength: float = 0.08
@export var hurt_shake_cap: float = 0.3
@export var boss_death_shake_strength: float = 0.35

@export_group("Hit Stop")
@export var crit_stop_scale: float = 0.3
@export var crit_stop_duration: float = 0.05
@export var crit_shake_strength: float = 0.1
## Minimum seconds between crit punches: rapid-fire crit builds must not
## chain the game into permanent slow motion.
@export var crit_punch_cooldown: float = 0.35
@export var boss_death_stop_scale: float = 0.4
@export var boss_death_stop_duration: float = 0.5

@export_group("Hit Flash")
@export var flash_duration: float = 0.08

@export_group("Damage Vignette")
@export var vignette_strength: float = 0.5
@export var vignette_fade_time: float = 0.45

@export_group("Slide FOV")
@export var fov_kick_amount: float = 5.0
@export var fov_kick_in_time: float = 0.1
@export var fov_kick_out_time: float = 0.15

@export_group("Bursts")
@export var death_burst_min: int = 4
@export var death_burst_max: int = 6
## Never raise this above DeathBurst.tscn's authored `amount` (24): the
## burst clamps to its buffer instead of reallocating it mid-death.
@export var boss_burst_amount: int = 24
@export var sparkle_amount: int = 6
@export var sparkle_color: Color = Color(1.0, 0.84, 0.3)

@export_group("Level Pulse")
@export var level_pulse_color: Color = Color(0.35, 0.95, 0.6)
@export var level_pulse_duration: float = 0.5


## Cameras the feel layer drives. Split-screen registers each player's own
## (source) camera here, because that is the one SplitScreen mirrors into
## the SubViewport that actually renders; with the group empty (solo) the
## root viewport's active camera is used, exactly as before.
const FEEL_CAMERA_GROUP: StringName = &"feel_camera"


## Per-owner hit-flash bookkeeping: the meshes touched and the overlays to
## put back. One entry per body; repeat hits only refresh the timer.
class FlashState:
	extends RefCounted
	var meshes: Array[MeshInstance3D] = []
	var prev: Array[Material] = []
	## Node that owns the COMPOSED overlay (EnemyBase.current_overlay), when
	## there is one: asking it beats putting `prev` back, which resurrects an
	## overlay the body dropped during the flash window.
	var overlay_owner: Node = null
	var time_left: float = 0.0


## One live slide FOV kick. Keyed per camera so co-op raiders sliding at
## the same time do not fight over a single base FOV.
class FovKick:
	extends RefCounted
	var camera: Camera3D = null
	var base_fov: float = 0.0
	var tween: Tween = null


# --- shake state ---
var _trauma: float = 0.0
var _trauma_decay: float = 0.0
var _shake_time: float = 0.0
## Cameras currently displaced, with the h/v offset each rested at.
var _shake_cameras: Array[Camera3D] = []
var _shake_rest: Dictionary[int, Vector2] = {}
var _noise_x: FastNoiseLite = FastNoiseLite.new()
var _noise_y: FastNoiseLite = FastNoiseLite.new()
## Per-process-frame cache of _feel_cameras() (the shake asks every tick).
var _feel_cameras_cache: Array[Camera3D] = []
var _feel_cameras_frame: int = -1

# --- hit-stop state (single accumulator: overlaps extend, never stack) ---
var _stop_left: float = 0.0
var _crit_cd_left: float = 0.0

# --- flash state ---
var _flash_material: StandardMaterial3D
var _flashes: Dictionary[int, FlashState] = {}
var _expired_flash_keys: Array[int] = []

# --- vignette state ---
var _vignette_material: ShaderMaterial
var _vignette_tween: Tween

# --- FOV kick state (one entry per camera currently kicked) ---
var _fov_kicks: Dictionary[int, FovKick] = {}
## Reused scratch for the per-tick sweep, like _expired_flash_keys: a
## dictionary cannot be erased from while it is being iterated.
var _expired_fov_keys: Array[int] = []

# --- level pulse state ---
## Process frame the last level ring/sting fired on: RunState emits
## leveled_up once PER LEVEL, so one fat gem can fire it three times in a
## single frame.
var _level_pulse_frame: int = -1


func _ready() -> void:
	# Restores (time_scale, shake, vignette fade) must keep running while
	# the card UI or run-end screen has the tree paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_noise_x.seed = 1337
	_noise_y.seed = 7331
	_noise_x.frequency = 3.0
	_noise_y.frequency = 3.0
	_flash_material = StandardMaterial3D.new()
	_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_material.albedo_color = Color(1.0, 1.0, 1.0, 0.7)
	_flash_material.emission_enabled = true
	_flash_material.emission = Color(1.0, 1.0, 1.0)
	_flash_material.emission_energy_multiplier = 2.2
	_build_vignette()
	RunState.leveled_up.connect(_on_leveled_up)


func _process(delta: float) -> void:
	# Hit-stop scales _process delta too; divide it back out so the stop
	# window and the crit cooldown count real (unscaled) time.
	var unscaled := delta / maxf(Engine.time_scale, 0.001)
	_crit_cd_left = maxf(_crit_cd_left - unscaled, 0.0)
	if _stop_left > 0.0:
		_stop_left -= unscaled
		if _stop_left <= 0.0:
			_stop_left = 0.0
			Engine.time_scale = 1.0
	_tick_flashes(delta)
	_tick_shake(delta)
	_tick_fov_kicks()


# --- camera shake -----------------------------------------------------------

## Adds `strength` trauma that fully decays over roughly `duration`
## seconds. trauma_cap < 1 limits how much THIS kind of shake can pool
## (spammy sources); bigger uncapped shakes can still push past it.
func shake(strength: float, duration: float = 0.3, trauma_cap: float = 1.0) -> void:
	if strength <= 0.0 or duration <= 0.0:
		return
	if _trauma >= trauma_cap:
		return
	# Decay is carried as "time left to drain", not as a sticky maximum
	# rate: a fast shake used to clamp every later one to its own rate, so
	# one boss death silenced the horde rumble for the rest of the fight.
	var time_left := _trauma / _trauma_decay if _trauma_decay > 0.0 else 0.0
	_trauma = minf(_trauma + strength, clampf(trauma_cap, 0.0, 1.0))
	_trauma_decay = _trauma / maxf(time_left, duration)


func _tick_shake(delta: float) -> void:
	if _trauma <= 0.0:
		return
	_shake_time += delta * shake_noise_speed
	_sync_shake_cameras(_feel_cameras())
	# h/v_offset survive the SpringArm3D (which overwrites the child
	# transform every frame) and never rotate the rig.
	var amount := pow(_trauma, 1.5) * shake_max_offset
	var offset_h := _noise_x.get_noise_1d(_shake_time) * amount
	var offset_v := _noise_y.get_noise_1d(_shake_time) * amount
	for camera: Camera3D in _shake_cameras:
		if not is_instance_valid(camera):
			continue
		var rest: Vector2 = _shake_rest.get(camera.get_instance_id(), Vector2.ZERO)
		camera.h_offset = rest.x + offset_h
		camera.v_offset = rest.y + offset_v
	_trauma = maxf(_trauma - _trauma_decay * delta, 0.0)
	if _trauma == 0.0:
		_trauma_decay = 0.0
		_release_shake_cameras()


## Starts displacing cameras that just joined the set and puts back the
## ones that left it (a view closing mid-shake must not stay offset).
func _sync_shake_cameras(cameras: Array[Camera3D]) -> void:
	for i in range(_shake_cameras.size() - 1, -1, -1):
		var tracked := _shake_cameras[i]
		if cameras.has(tracked) and is_instance_valid(tracked):
			continue
		_rest_camera(tracked)
		_shake_cameras.remove_at(i)
	for camera: Camera3D in cameras:
		if _shake_cameras.has(camera):
			continue
		_shake_cameras.append(camera)
		_shake_rest[camera.get_instance_id()] = Vector2(camera.h_offset, camera.v_offset)


func _release_shake_cameras() -> void:
	for camera: Camera3D in _shake_cameras:
		_rest_camera(camera)
	_shake_cameras.clear()
	_shake_rest.clear()


func _rest_camera(camera: Camera3D) -> void:
	if camera == null:
		return
	if not is_instance_valid(camera):
		# A camera freed mid-shake takes its instance id with it (asking a
		# freed object for anything is an error), so its rest entry is found
		# by resolving the ids instead. The bookkeeping HAS to go: this is an
		# autoload, and a stage swap or a co-op slot leaving retires a camera
		# per view, every time.
		for key: int in _shake_rest.keys():
			if not is_instance_id_valid(key):
				_shake_rest.erase(key)
		return
	var key := camera.get_instance_id()
	var rest: Vector2 = _shake_rest.get(key, Vector2.ZERO)
	camera.h_offset = rest.x
	camera.v_offset = rest.y
	_shake_rest.erase(key)


# --- hit stop ---------------------------------------------------------------

## Brief Engine.time_scale dip. Overlapping calls take the slowest scale
## and the furthest end time on ONE accumulator, and _process always
## restores exactly 1.0 — the game can never stick slow.
func hit_stop(scale: float, duration: float) -> void:
	if duration <= 0.0:
		return
	var clamped := clampf(scale, 0.05, 1.0)
	if _stop_left > 0.0:
		Engine.time_scale = minf(Engine.time_scale, clamped)
		_stop_left = maxf(_stop_left, duration)
	else:
		Engine.time_scale = clamped
		_stop_left = duration


# --- hit flash --------------------------------------------------------------

## White flash on every mesh under mesh_owner (pass the enemy's visual
## rig). One shared overlay material — never duplicated per hit; previous
## overlays (e.g. the elite glow) are restored when the flash ends.
func flash(mesh_owner: Node3D) -> void:
	if mesh_owner == null or not is_instance_valid(mesh_owner):
		return
	var key := mesh_owner.get_instance_id()
	if _flashes.has(key):
		var active: FlashState = _flashes[key]
		active.time_left = flash_duration  # refresh only: no rescan, no alloc
		return
	var entry := FlashState.new()
	var owner_mesh := mesh_owner as MeshInstance3D
	if owner_mesh != null:
		entry.meshes.append(owner_mesh)
	for node: Node in mesh_owner.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh != null:
			entry.meshes.append(mesh)
	if entry.meshes.is_empty():
		return
	entry.overlay_owner = _overlay_owner(mesh_owner)
	for mesh: MeshInstance3D in entry.meshes:
		entry.prev.append(mesh.material_overlay)
		mesh.material_overlay = _flash_material
	entry.time_left = flash_duration
	_flashes[key] = entry


## The node that owns the composed overlay for `mesh_owner`, or null when
## nobody claims the slot. EnemyBase exposes current_overlay() on the body
## while callers hand us its Visual child, so look one level up too.
static func _overlay_owner(mesh_owner: Node3D) -> Node:
	if mesh_owner.has_method(&"current_overlay"):
		return mesh_owner
	var parent := mesh_owner.get_parent()
	if parent != null and parent.has_method(&"current_overlay"):
		return parent
	return null


func _tick_flashes(delta: float) -> void:
	if _flashes.is_empty():
		return
	_expired_flash_keys.clear()
	for key: int in _flashes:
		var entry: FlashState = _flashes[key]
		entry.time_left -= delta
		if entry.time_left <= 0.0:
			_restore_flash(entry)
			_expired_flash_keys.append(key)
	for key: int in _expired_flash_keys:
		_flashes.erase(key)


## Ends a flash. When the body composes its own overlay (poison tint, elite
## glow) it is asked for the CURRENT answer instead of replaying the one
## captured 0.08 s ago — poison wearing off inside the flash window used to
## be undone by the restore, leaving the body green until it died.
func _restore_flash(entry: FlashState) -> void:
	var composed: Material = null
	var owned := entry.overlay_owner != null and is_instance_valid(entry.overlay_owner)
	if owned:
		composed = entry.overlay_owner.call(&"current_overlay") as Material
	for i in entry.meshes.size():
		var mesh := entry.meshes[i]
		if is_instance_valid(mesh):
			mesh.material_overlay = composed if owned else entry.prev[i]


# --- particle bursts --------------------------------------------------------

## Plays a one-shot DeathBurst at `at`, tinted `color`. Pooled: the burst
## releases itself back to Pools when done.
func burst(at: Vector3, color: Color, amount: int) -> void:
	var fx := Pools.acquire_scene(Pools.DEATH_BURST_SCENE) as DeathBurst
	if fx == null:
		return
	fx.global_position = at
	fx.fire(color, maxi(amount, 1))


# --- semantic feel moments (tunables above; call sites stay one-liners) -----

func enemy_died(at: Vector3, color: Color) -> void:
	shake(kill_shake_strength, 0.25, kill_shake_cap)
	burst(at, color, randi_range(death_burst_min, death_burst_max))
	Sfx.play(&"enemy_die")


func boss_died(at: Vector3, color: Color) -> void:
	shake(boss_death_shake_strength, 0.6)
	hit_stop(boss_death_stop_scale, boss_death_stop_duration)
	burst(at, color, boss_burst_amount)
	Sfx.play(&"boss_die")


## Crit landed: micro hit-stop + a slightly bigger shake, rate-limited so
## high-crit builds punctuate instead of drone.
func crit_punch() -> void:
	if _crit_cd_left > 0.0:
		return
	_crit_cd_left = crit_punch_cooldown
	shake(crit_shake_strength, 0.25)
	hit_stop(crit_stop_scale, crit_stop_duration)


func player_hurt() -> void:
	shake(hurt_shake_strength, 0.3, hurt_shake_cap)
	_pulse_vignette()
	Sfx.play(&"player_hurt")


## Gold completion sparkle for chests and shrines.
func sparkle(at: Vector3) -> void:
	burst(at, sparkle_color, sparkle_amount)


# --- slide FOV kick ---------------------------------------------------------

## Widens `camera` while a slide lasts. Pass the slider's OWN camera: in
## split-screen there is no active camera on the root viewport, so the
## no-argument form has nothing to kick (and kicking every view would flare
## the FOV of raiders who are not sliding). SplitScreen mirrors the source
## camera's fov into the view that renders, so the kick propagates for free.
func fov_kick_begin(camera: Camera3D = null) -> void:
	var target := camera if camera != null else _active_camera()
	if target == null or not is_instance_valid(target):
		return
	var key := target.get_instance_id()
	var kick: FovKick = _fov_kicks.get(key, null)
	if kick == null:
		# First kick on this camera: record its rest FOV. While the restore
		# tween of the SAME camera is still mid-flight the recorded base
		# stays valid — never re-read a moving fov.
		kick = FovKick.new()
		kick.camera = target
		kick.base_fov = target.fov
		_fov_kicks[key] = kick
	_kill_fov_tween(kick)
	kick.tween = create_tween()
	kick.tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	kick.tween.tween_property(target, "fov", kick.base_fov + fov_kick_amount,
			fov_kick_in_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func fov_kick_end(camera: Camera3D = null) -> void:
	var target := camera if camera != null else _active_camera()
	if target == null:
		return
	var key := target.get_instance_id()
	var kick: FovKick = _fov_kicks.get(key, null)
	if kick == null:
		return
	if not is_instance_valid(kick.camera):
		_kill_fov_tween(kick)
		_fov_kicks.erase(key)
		return
	_kill_fov_tween(kick)
	kick.tween = create_tween()
	kick.tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	kick.tween.tween_property(kick.camera, "fov", kick.base_fov, fov_kick_out_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	kick.tween.tween_callback(_on_fov_restored.bind(key))


## Entries only ever leave on the normal paths (the restore tween finishing,
## or fov_kick_end finding the camera already gone), and a raider whose
## camera dies MID-SLIDE reaches neither: the kick would sit in this
## autoload holding a dead Camera3D for the rest of the process, one per
## view per run in split-screen. Swept here instead — the dictionary is
## empty except during a slide, so this costs a branch.
func _tick_fov_kicks() -> void:
	if _fov_kicks.is_empty():
		return
	_expired_fov_keys.clear()
	for key: int in _fov_kicks:
		var kick: FovKick = _fov_kicks[key]
		if is_instance_valid(kick.camera):
			continue
		_kill_fov_tween(kick)
		_expired_fov_keys.append(key)
	for key: int in _expired_fov_keys:
		_fov_kicks.erase(key)


func _on_fov_restored(key: int) -> void:
	_fov_kicks.erase(key)


func _kill_fov_tween(kick: FovKick) -> void:
	if kick.tween != null and kick.tween.is_valid():
		kick.tween.kill()


# --- damage vignette --------------------------------------------------------

func _build_vignette() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 4  # above the 3D scene, below the HUD (5)
	add_child(layer)
	var shader := Shader.new()
	shader.code = VIGNETTE_SHADER
	_vignette_material = ShaderMaterial.new()
	_vignette_material.shader = shader
	_vignette_material.set_shader_parameter("intensity", 0.0)
	var rect := ColorRect.new()
	rect.material = _vignette_material
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)


func _pulse_vignette() -> void:
	if _vignette_material == null:
		return
	if _vignette_tween != null and _vignette_tween.is_valid():
		_vignette_tween.kill()
	_vignette_material.set_shader_parameter("intensity", vignette_strength)
	_vignette_tween = create_tween()
	_vignette_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_vignette_tween.tween_property(_vignette_material, "shader_parameter/intensity",
			0.0, vignette_fade_time).set_delay(0.05)


# --- level-up pulse ---------------------------------------------------------

func _on_leveled_up(_new_level: int) -> void:
	# RunState emits once PER LEVEL, so a rift gem worth three levels fired
	# this three times in one frame: three copies of the same wav stacking
	# on the bus and three rings drawn pixel on pixel. One per frame.
	var frame := Engine.get_process_frames()
	if frame == _level_pulse_frame:
		return
	_level_pulse_frame = frame
	Sfx.play(&"level_up")
	# Shared party level: the ring pulses at EVERY standing raider's feet
	# (one node in solo — identical to the old single-ring behavior).
	for node: Node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Node3D
		if player != null and player.is_inside_tree():
			_spawn_level_ring(player.global_position + Vector3.UP * 0.15)


## Expanding emissive ring at the player's feet. Its tween ignores pause so
## the pulse plays under the card UI's freeze-frame.
func _spawn_level_ring(at: Vector3) -> void:
	var scene_root := RunRoot.stage_parent(get_tree())
	if scene_root == null:
		return
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.42
	mesh.outer_radius = 0.55
	ring.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(level_pulse_color.r, level_pulse_color.g,
			level_pulse_color.b, 0.85)
	material.emission_enabled = true
	material.emission = level_pulse_color
	material.emission_energy_multiplier = 2.4
	ring.material_override = material
	scene_root.add_child(ring)
	ring.global_position = at
	ring.scale = Vector3(0.4, 0.55, 0.4)
	# Bound to the RING, not to this autoload: the ring dies with the scene,
	# and a tween owned by Juice would outlive it (quitting to menu inside
	# the half-second pulse tweened a freed object).
	var tween := ring.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(4.6, 0.25, 4.6), level_pulse_duration) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, level_pulse_duration) \
			.set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(ring.queue_free)


# --- shared math ------------------------------------------------------------

## Framerate-independent smoothing weight for `lerp(a, b, Juice.damp(r, d))`.
## The obvious `rate * delta` is the Euler approximation of this: its error
## grows with delta, so a smoothed value's response time drifts with the
## framerate (and below 10 fps it saturates at 1.0 and stops smoothing).
## Lives on the feel layer so the seal rig, the pets and the camera all
## settle at the same real speed whatever the frame time is.
static func damp(rate: float, delta: float) -> float:
	return 1.0 - exp(-rate * delta)


# --- shared lookups ---------------------------------------------------------

## Every camera the feel layer should displace. In split-screen the root
## viewport has NO active camera (each player's own camera is deactivated
## in favour of a follow camera inside a SubViewport), which is why the
## plain lookup below returned null and shake died in co-op; SplitScreen
## registers the source cameras it mirrors in FEEL_CAMERA_GROUP instead.
## Cached per process frame: the shake asks for this every tick.
func _feel_cameras() -> Array[Camera3D]:
	var frame := Engine.get_process_frames()
	if frame == _feel_cameras_frame:
		return _feel_cameras_cache
	_feel_cameras_frame = frame
	_feel_cameras_cache.clear()
	var tree := get_tree()
	if tree != null:
		for node: Node in tree.get_nodes_in_group(FEEL_CAMERA_GROUP):
			var camera := node as Camera3D
			if camera != null and camera.is_inside_tree():
				_feel_cameras_cache.append(camera)
	if _feel_cameras_cache.is_empty():
		var single := _active_camera()
		if single != null:
			_feel_cameras_cache.append(single)
	return _feel_cameras_cache


func _active_camera() -> Camera3D:
	var viewport := get_viewport()
	if viewport == null:
		return null
	return viewport.get_camera_3d()
