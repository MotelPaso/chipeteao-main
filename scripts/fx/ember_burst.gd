class_name EmberBurst
extends Node3D
## Pooled Ember Wand detonation: the expanding emissive shell (the burst
## read), a ground scorch disc that lingers and fades, and a one-shot
## spray of rising ember particles. All meshes/materials are shared scene
## resources; per-instance fades use MeshInstance3D.transparency.

const SHELL_TIME: float = 0.35
const SCORCH_TIME: float = 1.1

@onready var _shell: MeshInstance3D = $Shell
@onready var _scorch: MeshInstance3D = $Scorch
@onready var _embers: GPUParticles3D = $Embers

var _tween: Tween = null


## Pooled-node contract: kill a stale burst so reuse starts clean.
func pool_reset() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_shell.transparency = 0.0
	_scorch.transparency = 0.0
	_embers.emitting = false


## Detonates at `center` (the struck enemy's origin) with the given hit
## radius: shell swells to the damage radius, scorch marks the ground.
func play(center: Vector3, radius: float) -> void:
	global_position = center
	_shell.transparency = 0.0
	_shell.scale = Vector3.ONE * 0.2
	_scorch.transparency = 0.35
	_scorch.scale = Vector3(radius * 0.8, 1.0, radius * 0.8)
	_embers.restart()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_shell, "scale", Vector3.ONE * radius, SHELL_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_shell, "transparency", 1.0, SHELL_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_property(_scorch, "transparency", 1.0, SCORCH_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.chain().tween_interval(0.2)
	_tween.chain().tween_callback(_release)


func _release() -> void:
	Pools.release(self)
