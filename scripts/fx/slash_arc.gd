class_name SlashArc
extends MeshInstance3D
## Pooled crescent slash swipe (Shortsword's arc, Twin Daggers' mini cuts):
## a procedurally built flat crescent — outer edge full, tapering to points
## at both arc ends via vertex alpha — that sweeps through the hit arc and
## fades. One ArrayMesh and one material are built per instance at _ready
## and reused forever after; play() only tweens transform/transparency.

## Crescent span baked into the mesh; the play() sweep rotation carries
## the rest of the attack arc visually.
const ARC_DEG: float = 110.0
const SEGMENTS: int = 14
## Max crescent thickness (fraction of the unit outer radius), mid-arc.
const THICKNESS: float = 0.55
## Peak vertex alpha (kept modest so telegraphs stay readable through it).
const PEAK_ALPHA: float = 0.7

var _material: StandardMaterial3D = null
var _tween: Tween = null


func _ready() -> void:
	# cast_shadow lives in SlashArc.tscn with the rest of the FX geometry
	# rules (emissive FX never casts), not here.
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.vertex_color_use_as_albedo = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = _material
	mesh = _build_crescent()


## Pooled-node contract: kill a stale sweep so reuse starts clean.
func pool_reset() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	transparency = 0.0


## Flashes the crescent through an arc centered on `center_dir` (flat,
## world XZ) at `at`, scaled to `radius`. sweep_deg is the total rotation
## travelled during the swipe; mirror flips the sweep direction so
## alternating dagger cuts read left/right.
func play(at: Vector3, center_dir: Vector3, radius: float, color: Color,
		sweep_deg: float = 120.0, duration: float = 0.22, mirror: bool = false) -> void:
	_material.albedo_color = color
	var flat := Vector3(center_dir.x, 0.0, center_dir.z)
	flat = flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD
	global_transform = Transform3D(Basis.looking_at(flat, Vector3.UP), at)
	scale = Vector3.ONE * radius
	var sweep := deg_to_rad(sweep_deg) * (-1.0 if mirror else 1.0)
	rotate_object_local(Vector3.UP, sweep * 0.5)
	transparency = 0.0
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(self, "rotation:y", rotation.y - sweep, duration) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "transparency", 1.0, duration) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.chain().tween_callback(_release)


func _release() -> void:
	Pools.release(self)


## Flat crescent in the XZ plane, centered on -Z, unit outer radius:
## a triangle strip whose inner radius rises toward the arc's midpoint
## (crescent taper) with vertex alpha fading to zero at both tips.
func _build_crescent() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var half := deg_to_rad(ARC_DEG) * 0.5
	for i: int in SEGMENTS + 1:
		var t := float(i) / float(SEGMENTS)
		var angle := -half + t * half * 2.0
		# sin taper: full thickness mid-arc, points at the ends.
		var taper := sin(t * PI)
		var inner := 1.0 - THICKNESS * taper
		var dir := Vector3(sin(angle), 0.0, -cos(angle))
		vertices.append(dir * inner)
		vertices.append(dir)
		var alpha := PEAK_ALPHA * taper
		colors.append(Color(1, 1, 1, alpha * 0.35))  # inner edge, softer
		colors.append(Color(1, 1, 1, alpha))
	return FxMesh.strip(vertices, colors)
