class_name BloodPoolFx
extends Node3D
## Pooled Blood Vial pool visual: crimson disc with a darker rim ring and
## slow rising bubble particles, throbbing gently while active. Purely
## cosmetic — blood_vial.gd owns the damage ticks and calls play() when a
## pool forms and expire() when its last tick lapses.

const THROB_TIME: float = 0.35
const FADE_TIME: float = 0.3

@onready var _disc: MeshInstance3D = $Disc
@onready var _rim: MeshInstance3D = $Rim
@onready var _bubbles: GPUParticles3D = $Bubbles

var _throb: Tween = null
var _fade: Tween = null
var _radius: float = 1.0


## Pooled-node contract: kill stale tweens so reuse starts clean.
func pool_reset() -> void:
	_kill_tweens()
	_disc.transparency = 0.0
	_rim.transparency = 0.0
	_bubbles.emitting = false


## Forms the pool at `center` (ground plane) with the given damage radius.
func play(center: Vector3, radius: float) -> void:
	_radius = radius
	global_position = center
	_disc.transparency = 0.0
	_rim.transparency = 0.15
	# The whole node scales to the radius; the bubble emission sphere is
	# authored at 0.85 local units, so it tracks the disc automatically.
	scale = Vector3(radius, 1.0, radius)
	_bubbles.restart()
	_bubbles.emitting = true
	_throb = create_tween().set_loops()
	_throb.tween_property(self, "scale", Vector3(radius * 1.06, 1.4, radius * 1.06),
			THROB_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_throb.tween_property(self, "scale", Vector3(radius, 1.0, radius), THROB_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Fades the pool out and parks it back in the pool of pools.
func expire() -> void:
	if _throb != null and _throb.is_valid():
		_throb.kill()
	_bubbles.emitting = false
	_fade = create_tween()
	_fade.set_parallel(true)
	_fade.tween_property(_disc, "transparency", 1.0, FADE_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fade.tween_property(_rim, "transparency", 1.0, FADE_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fade.chain().tween_callback(_release)


func _release() -> void:
	Pools.release(self)


func _kill_tweens() -> void:
	if _throb != null and _throb.is_valid():
		_throb.kill()
	if _fade != null and _fade.is_valid():
		_fade.kill()
