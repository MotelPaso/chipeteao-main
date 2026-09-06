class_name BloodPoolFx
extends Node3D
## Pooled Blood Vial pool visual: crimson disc with a darker rim ring and
## slow rising bubble particles, throbbing gently while active. Purely
## cosmetic — blood_vial.gd owns the damage ticks and calls play() when a
## pool forms and expire() when its last tick lapses.
## The radius scales the DISC AND RIM, never the root: the bubbles hang off
## the same node, and a non-uniform root scale squashed them into smears
## that pumped with the throb instead of reading as bubbles.

const THROB_TIME: float = 0.35
const FADE_TIME: float = 0.3
## Bubble emission sphere at radius 1, matching the authored disc.
const BUBBLE_EMISSION_RATIO: float = 0.85

@onready var _disc: MeshInstance3D = $Disc
@onready var _rim: MeshInstance3D = $Rim
@onready var _bubbles: GPUParticles3D = $Bubbles

var _throb: Tween = null
var _fade: Tween = null
## True between expire() and the pooled release: expire() has two callers
## in waiting (run teardown, weapon evolution) and a second fade tween
## would queue a second release for a node that may already be re-acquired.
var _expiring: bool = false


## Pooled-node contract: kill stale tweens so reuse starts clean.
func pool_reset() -> void:
	_kill_tweens()
	_expiring = false
	_disc.transparency = 0.0
	_rim.transparency = 0.0
	_disc.scale = Vector3.ONE
	_rim.scale = Vector3.ONE
	_bubbles.emitting = false


## Forms the pool at `center` (ground plane) with the given damage radius.
func play(center: Vector3, radius: float) -> void:
	_expiring = false
	global_position = center
	_disc.transparency = 0.0
	_rim.transparency = 0.15
	_scale_ground(radius)
	# The bubbles keep unit scale and grow their emission sphere instead,
	# so each bubble stays round whatever the pool radius is.
	var bubble_material := _bubbles.process_material as ParticleProcessMaterial
	if bubble_material != null:
		bubble_material.emission_sphere_radius = radius * BUBBLE_EMISSION_RATIO
	_bubbles.restart()
	_bubbles.emitting = true
	var rest := Vector3(radius, 1.0, radius)
	var swollen := Vector3(radius * 1.06, 1.4, radius * 1.06)
	_throb = create_tween().set_loops()
	_throb.set_parallel(true)
	_throb.tween_property(_disc, "scale", swollen, THROB_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_throb.tween_property(_rim, "scale", swollen, THROB_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_throb.chain().tween_property(_disc, "scale", rest, THROB_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_throb.parallel().tween_property(_rim, "scale", rest, THROB_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Fades the pool out and parks it back in the pool of pools.
func expire() -> void:
	if _expiring:
		return
	_expiring = true
	_kill_tweens()
	_bubbles.emitting = false
	_fade = create_tween()
	_fade.set_parallel(true)
	_fade.tween_property(_disc, "transparency", 1.0, FADE_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fade.tween_property(_rim, "transparency", 1.0, FADE_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fade.chain().tween_callback(_release)


func _scale_ground(radius: float) -> void:
	var ground := Vector3(radius, 1.0, radius)
	_disc.scale = ground
	_rim.scale = ground


func _release() -> void:
	Pools.release(self)


func _kill_tweens() -> void:
	if _throb != null and _throb.is_valid():
		_throb.kill()
	if _fade != null and _fade.is_valid():
		_fade.kill()
