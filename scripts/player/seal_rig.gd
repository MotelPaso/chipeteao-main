class_name SealRig
extends Node3D
## Visual rig for the player's body model: purely cosmetic — the gameplay
## capsule/collision stays on Player. WHICH body is per-character catalog
## data (setup(), called from Player._apply_character): a row with no model
## fields falls back to the seal (assets/models/foca.glb). Owns the
## per-character tint (one material duplicate per spawn shared by every
## surface whose material name carries the row's tint prefix), hides the
## model's baked SUELO floor plane, and layers cheap procedural motion on
## the Model child: idle breathing, movement lean/bob, jump stretch, slide
## squash (flat + nose-down), and the pause-immune death face-plant. No
## skeletal animations exist in any model; everything here is transform
## math on cached targets — zero per-frame allocations.

## Prefix of the material resource_name that receives the character tint
## (the GLB exporter suffixes it, e.g. "Azul personaje.001"). Each model
## names its tintable materials its own way; a character row overrides
## this via tint_material_prefix.
const TINT_MATERIAL_PREFIX := "Azul personaje"

## Body loaded when a character row names no model: the seal WRAPPER scene,
## which bakes the seal's own yaw flip and 0.6 scale, so the fallback needs
## no rig-side special case (a raw .glb row would pass a model_scale).
const DEFAULT_MODEL_SCENE := "res://assets/models/foca_character.tscn"

## Display name of the model any export junk hides by (the seal's baked
## floor plane). Purely cosmetic garbage; other models may not name one.
const HIDDEN_NODE_NAME := "SUELO"

@export_group("Idle")
## Breathing scale-Y pulse amplitude (0.02 = +-2%).
@export var breathe_amount: float = 0.02
@export var breathe_speed: float = 2.2

@export_group("Movement")
## Max lean (radians) into the horizontal movement direction at full speed.
@export var lean_max: float = 0.14
## Bob height at full ground speed.
@export var bob_amount: float = 0.05
@export var bob_speed: float = 9.0
## Speed treated as "full" for lean/bob normalization.
@export var reference_speed: float = 6.0
## Vertical velocity that maps to full jump stretch.
@export var stretch_reference: float = 8.0
## Max jump stretch on scale Y (0.12 = +12%, width shrinks to match).
@export var stretch_max: float = 0.12

@export_group("Slide")
## Scale Y while sliding (flatter than the capsule's 0.5 height ratio
## reads better on the wide seal body).
@export var slide_squash: float = 0.55
## Extra widening on X/Z while squashed.
@export var slide_spread: float = 1.15
## Nose-down pitch (radians) while sliding.
@export var slide_pitch: float = 0.22

@export_group("Death")
## Height above the model origin the face-plant lifts the body to while
## it rests on the floor — body shapes differ, the wide seal reads right
## on 0.55.
@export var death_lift: float = 0.55

## Convergence rates for the smoothed motion state, in "fraction closed per
## second" (see _damp): lean/bob/stretch settle quickly, the slide squash a
## touch faster so the flatten reads as an impact.
const MOTION_DAMP_RATE: float = 10.0
const SQUASH_DAMP_RATE: float = 14.0

@onready var _model: Node3D = $Model

## The player body whose velocity drives lean/bob; null outside a player
## (test harnesses) keeps the rig idle-only.
var _body: CharacterBody3D = null
## The single tint material instance shared by all tint-prefix surfaces.
var _tint_material: StandardMaterial3D = null
## resource_name prefix of the CURRENT model's tintable materials.
var _tint_prefix: String = TINT_MATERIAL_PREFIX
var _slide_ratio: float = 1.0
var _phase: float = 0.0
var _dead: bool = false
## Smoothed motion state (lerped toward targets each frame).
var _lean: Vector2 = Vector2.ZERO
var _bob: float = 0.0
var _stretch: float = 0.0
var _squash_blend: float = 0.0
## The pause-immune face-plant, kept so a revive can cancel it (see
## reset_death): a live tween writes the same _model properties _process
## rewrites every frame, and the two fight over the model.
var _death_tween: Tween = null


## Framerate-independent smoothing weight for `lerp(a, b, _damp(rate, d))`.
## The obvious `rate * delta` is the Euler approximation of this: its error
## grows with delta, so the rig's response time drifts with the framerate
## (and below 10 fps it saturates at 1.0 and stops smoothing altogether).
static func _damp(rate: float, delta: float) -> float:
	return 1.0 - exp(-rate * delta)


func _ready() -> void:
	_body = get_parent() as CharacterBody3D


## Cosmetic body swap with a CharacterCatalog row's model data. Empty
## scene path = the default seal; the scale MULTIPLIES what the model
## scene already carries (1.0 / non-positive = no rescaling — the wrapper
## scenes bake their own transform, raw .glb rows declare one); an empty
## tint prefix falls back to the seal's "Azul personaje".
func setup(model_scene: String, model_scale: float, tint_prefix: String) -> void:
	_clear_model()
	_tint_material = null
	_tint_prefix = tint_prefix if not tint_prefix.is_empty() else TINT_MATERIAL_PREFIX
	var path := model_scene if not model_scene.is_empty() else DEFAULT_MODEL_SCENE
	var packed := load(path) as PackedScene
	if packed == null:
		# Cosmetic only: the gameplay body never depended on the rig, so a
		# bad path costs an invisible character and one warning.
		push_warning("SealRig: model scene '%s' does not load" % path)
		return
	var model := packed.instantiate()
	if model == null:
		push_warning("SealRig: '%s' instantiates to nothing" % path)
		return
	var body := model as Node3D
	if body == null:
		push_warning("SealRig: root of '%s' is not a Node3D" % path)
		model.free()
		return
	if model_scale > 0.0 and model_scale != 1.0:
		body.scale = body.scale * model_scale
	_model.add_child(body)
	for node: Node in _model.find_children(HIDDEN_NODE_NAME, "MeshInstance3D", true, false):
		(node as MeshInstance3D).visible = false


## Throws out the previous body so a re-setup swaps cleanly; queue_free
## keeps it safe from a freed-node window since setup runs inside the
## spawn's own _ready chain.
func _clear_model() -> void:
	for child: Node in _model.get_children():
		child.queue_free()


## Per-character tint: ONE duplicate of the model's shared tint-prefix
## material, recolored and overridden onto every surface that used it
## (the seal's body, base, arms). Eyes/tusks/gel keep their imported
## materials.
func apply_tint(tint: Color) -> void:
	for node: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		for surface: int in mesh_node.mesh.get_surface_count():
			var material := mesh_node.mesh.surface_get_material(surface)
			if material == null \
					or not material.resource_name.begins_with(_tint_prefix):
				continue
			if _tint_material == null:
				_tint_material = material.duplicate() as StandardMaterial3D
			mesh_node.set_surface_override_material(surface, _tint_material)
	if _tint_material != null:
		_tint_material.albedo_color = tint


## Current tint color (test harnesses), or transparent black before tinting.
func tint_color() -> Color:
	return _tint_material.albedo_color if _tint_material != null else Color(0, 0, 0, 0)


## Player slide hook: ratio is collision height / default height (1 = no
## slide). Mapped to a flatter squash plus a nose-down tilt on the seal.
func set_slide_ratio(ratio: float) -> void:
	_slide_ratio = clampf(ratio, 0.1, 1.0)


func _process(delta: float) -> void:
	if _dead:
		return
	_phase += delta
	var smoothing := _damp(MOTION_DAMP_RATE, delta)

	# Movement-driven targets (all zero when idle or outside a player).
	var target_lean := Vector2.ZERO
	var speed_factor := 0.0
	var target_stretch := 0.0
	if _body != null:
		var local_velocity := _body.global_transform.basis.inverse() * _body.velocity
		var horizontal := Vector2(local_velocity.x, local_velocity.z)
		speed_factor = clampf(horizontal.length() / reference_speed, 0.0, 1.0)
		if speed_factor > 0.01:
			target_lean = horizontal.normalized() * lean_max * speed_factor
		if not _body.is_on_floor():
			target_stretch = clampf(absf(local_velocity.y) / stretch_reference, 0.0, 1.0) \
					* stretch_max
			speed_factor = 0.0  # no ground bob mid-air
	_lean = _lean.lerp(target_lean, smoothing)
	_stretch = lerpf(_stretch, target_stretch, smoothing)
	_bob = lerpf(_bob, bob_amount * speed_factor, smoothing)
	# Slide ratio 0.5 (the capsule's crouch) maps to a full squash blend.
	_squash_blend = lerpf(_squash_blend, clampf((1.0 - _slide_ratio) * 2.0, 0.0, 1.0),
			_damp(SQUASH_DAMP_RATE, delta))

	# Compose scale: breathe * jump stretch * slide squash (volume-ish kept).
	var breathe := 1.0 + sin(_phase * breathe_speed) * breathe_amount
	var scale_y := breathe * (1.0 + _stretch) * lerpf(1.0, slide_squash, _squash_blend)
	var scale_xz := (1.0 - _stretch * 0.5) * lerpf(1.0, slide_spread, _squash_blend)
	_model.scale = Vector3(scale_xz, scale_y, scale_xz)

	# Lean INTO the motion (forward run = nose-down pitch, strafing = roll
	# toward the strafe) plus the slide nose-dive; bob rides on top when
	# grounded. Signs: the model's nose points down -Z, so a NEGATIVE pitch
	# dips it — the same sign the slide dive already uses — and running
	# forward gives local_velocity.z < 0, hence _lean.y straight through.
	# Likewise strafing right gives _lean.x > 0 and needs a negative roll to
	# drop the head toward +X.
	_model.rotation.x = _lean.y - slide_pitch * _squash_blend
	_model.rotation.z = -_lean.x
	_model.position.y = absf(sin(_phase * bob_speed)) * _bob


## Death face-plant, adapted from the old capsule tween: the model pivots
## at its ground-level origin, tipping nose-first onto the floor with a
## bounce, lifted so the body rests on the ground instead of clipping in.
## Pause-immune — RunManager pauses the tree right after death.
func play_death() -> void:
	if _dead:
		return
	_dead = true
	_kill_death_tween()
	_death_tween = create_tween()
	_death_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_death_tween.set_parallel(true)
	_death_tween.tween_property(_model, "rotation:x", -TAU * 0.25, 0.5) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	_death_tween.tween_property(_model, "position:y", death_lift, 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_death_tween.tween_property(_model, "scale", Vector3(1.0, 1.0, 0.8), 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Co-op revive: undo the face-plant and hand the model back to the
## procedural motion loop (which rewrites rotation/scale/position every
## frame, so a simple snap is enough).
func reset_death() -> void:
	if not _dead:
		return
	_dead = false
	# Kill FIRST: the face-plant is pause-immune and 0.5 s long, so a fast
	# revive would leave it writing rotation/position/scale on top of the
	# snap below and of _process, flickering the seal between poses.
	_kill_death_tween()
	_model.rotation = Vector3.ZERO
	_model.position.y = 0.0
	_model.scale = Vector3.ONE


func _kill_death_tween() -> void:
	if _death_tween != null and _death_tween.is_valid():
		_death_tween.kill()
	_death_tween = null
