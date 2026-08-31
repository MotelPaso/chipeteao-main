class_name MuzzleFlash
extends MeshInstance3D
## Pooled point-flash sprite (Dart Pistol muzzle, Hunting Bow draw glint):
## a small billboarded emissive quad that pops in scale and fades out. The
## quad and its material are per-instance, built once at _ready; play()
## only recolors and tweens.

var _material: StandardMaterial3D = null
var _tween: Tween = null


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _material
	mesh = quad


## Pooled-node contract: kill a stale flash so reuse starts clean.
func pool_reset() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	transparency = 0.0


## Fires the flash at `at`. grow_time > 0 swells the quad from a pinprick
## first (the bow's drawn-back glint); 0 pops instantly (muzzle flash).
func play(at: Vector3, color: Color, size: float = 0.45,
		grow_time: float = 0.0, fade_time: float = 0.09) -> void:
	_material.albedo_color = color
	global_position = at
	transparency = 0.0
	_tween = create_tween()
	if grow_time > 0.0:
		scale = Vector3.ONE * (size * 0.15)
		_tween.tween_property(self, "scale", Vector3.ONE * size, grow_time) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		scale = Vector3.ONE * size
	_tween.tween_property(self, "transparency", 1.0, fade_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_release)


func _release() -> void:
	Pools.release(self)
