class_name SealRig
extends Node3D
## Visual rig for the player's seal model (assets/models/foca.glb): purely
## cosmetic — the gameplay capsule/collision stays on Player. Owns the
## per-character tint (one material duplicate per spawn shared by every
## "Azul personaje" surface), hides the model's baked SUELO floor plane,
## and layers cheap procedural motion on the Model child: idle breathing,
## movement lean/bob, jump stretch, slide squash (flat + nose-down), and
## the pause-immune death face-plant. No skeletal animations exist in the
## model; everything here is transform math on cached targets — zero
## per-frame allocations.

## Prefix of the material resource_name that receives the character tint
## (the GLB exporter suffixes it, e.g. "Azul personaje.001").
const TINT_MATERIAL_PREFIX := "Azul personaje"

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

@onready var _model: Node3D = $Model

## The player body whose velocity drives lean/bob; null outside a player
## (test harnesses) keeps the rig idle-only.
var _body: CharacterBody3D = null
## The single tint material instance shared by all "Azul" surfaces.
var _tint_material: StandardMaterial3D = null
var _slide_ratio: float = 1.0
var _phase: float = 0.0
var _dead: bool = false
## Smoothed motion state (lerped toward targets each frame).
var _lean: Vector2 = Vector2.ZERO
var _bob: float = 0.0
var _stretch: float = 0.0
var _squash_blend: float = 0.0


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	var floor_plane := _model.find_child("SUELO", true, false) as MeshInstance3D
	if floor_plane != null:
		floor_plane.visible = false


## Per-character tint: ONE duplicate of the model's shared "Azul personaje"
## material, recolored and overridden onto every surface that used it
## (body, base, arms). Eyes/tusks/gel keep their imported materials.
func apply_tint(tint: Color) -> void:
	for node: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		for surface: int in mesh_node.mesh.get_surface_count():
			var material := mesh_node.mesh.surface_get_material(surface)
			if material == null \
					or not material.resource_name.begins_with(TINT_MATERIAL_PREFIX):
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
	var smoothing := minf(delta * 10.0, 1.0)

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
			minf(delta * 14.0, 1.0))

	# Compose scale: breathe * jump stretch * slide squash (volume-ish kept).
	var breathe := 1.0 + sin(_phase * breathe_speed) * breathe_amount
	var scale_y := breathe * (1.0 + _stretch) * lerpf(1.0, slide_squash, _squash_blend)
	var scale_xz := (1.0 - _stretch * 0.5) * lerpf(1.0, slide_spread, _squash_blend)
	_model.scale = Vector3(scale_xz, scale_y, scale_xz)

	# Lean into motion (forward run = nose-down pitch, strafing = roll)
	# plus the slide nose-dive; bob rides on top when grounded.
	_model.rotation.x = -_lean.y - slide_pitch * _squash_blend
	_model.rotation.z = _lean.x
	_model.position.y = absf(sin(_phase * bob_speed)) * _bob


## Death face-plant, adapted from the old capsule tween: the model pivots
## at its ground-level origin, tipping nose-first onto the floor with a
## bounce, lifted so the body rests on the ground instead of clipping in.
## Pause-immune — RunManager pauses the tree right after death.
func play_death() -> void:
	if _dead:
		return
	_dead = true
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	tween.tween_property(_model, "rotation:x", -TAU * 0.25, 0.5) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tween.tween_property(_model, "position:y", 0.55, 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_model, "scale", Vector3(1.0, 1.0, 0.8), 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
