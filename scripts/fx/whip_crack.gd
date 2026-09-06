class_name WhipCrack
extends Node3D
## Pooled Thorn Whip lash visual: a flat tapering green strip that whips
## out along the hit lane and snaps back, plus a one-shot spray of tiny
## thorn particles along the strip. The strip mesh/material are built once
## per instance; the particle process material is local-to-scene so each
## pooled instance can resize its emission box to the lash length.

## Strip width at the wielder's end (tapers toward the tip).
const BASE_WIDTH: float = 0.26
const TIP_WIDTH: float = 0.05
const EXTEND_TIME: float = 0.07
const SNAP_TIME: float = 0.13

@onready var _strip: MeshInstance3D = $Strip
@onready var _thorns: GPUParticles3D = $Thorns

var _material: StandardMaterial3D = null
var _tween: Tween = null


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.vertex_color_use_as_albedo = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_strip.material_override = _material
	_strip.mesh = _build_strip()


## Pooled-node contract: kill a stale crack so reuse starts clean.
func pool_reset() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_strip.transparency = 0.0
	_thorns.emitting = false


## Cracks the whip from `from` along `direction` (flat) for `length`
## meters: fast extension, brief thorn spray along the strip, snap back.
func play(from: Vector3, direction: Vector3, length: float, color: Color) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	flat = flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD
	global_transform = Transform3D(Basis.looking_at(flat, Vector3.UP), from)
	_material.albedo_color = color
	_strip.transparency = 0.0
	_strip.scale = Vector3(1.0, 1.0, 0.1)
	var thorn_material := _thorns.process_material as ParticleProcessMaterial
	if thorn_material != null:
		# Spray along the whole strip: box centered halfway down the lash.
		thorn_material.emission_box_extents = Vector3(0.25, 0.15, length * 0.5)
	_thorns.position = Vector3(0.0, 0.0, -length * 0.5)
	_thorns.restart()
	_tween = create_tween()
	_tween.tween_property(_strip, "scale:z", length, EXTEND_TIME) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# chain() + parallel(), NOT set_parallel(true): set_parallel makes the
	# tweeners that follow run WITH the previous one, so the snap-back used
	# to race the extension from the same start value and the lash never
	# reached past 20% of the damage lane it actually covers.
	_tween.chain().tween_property(_strip, "scale:z", length * 0.2, SNAP_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(_strip, "transparency", 1.0, SNAP_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Linger long enough for the thorn particles to finish before parking.
	_tween.chain().tween_interval(0.4)
	_tween.chain().tween_callback(_release)


func _release() -> void:
	Pools.release(self)


## Flat tapering strip in the XZ plane from the origin to z = -1 (unit
## length; play() stretches scale.z to the lash length).
func _build_strip() -> ArrayMesh:
	const SEGMENTS: int = 6
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	for i: int in SEGMENTS + 1:
		var t := float(i) / float(SEGMENTS)
		var half_width := lerpf(BASE_WIDTH, TIP_WIDTH, t) * 0.5
		vertices.append(Vector3(-half_width, 0.0, -t))
		vertices.append(Vector3(half_width, 0.0, -t))
		var alpha := lerpf(0.8, 0.3, t)
		colors.append(Color(1, 1, 1, alpha))
		colors.append(Color(1, 1, 1, alpha))
	return FxMesh.strip(vertices, colors)
