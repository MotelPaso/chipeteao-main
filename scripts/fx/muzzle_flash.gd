class_name MuzzleFlash
extends MeshInstance3D
## Destello puntual del pool (fogonazo de la Pistola de dardos, destello de
## carga del Arco de caza): un quad emisivo pequeño que mira a cámara, crece
## de golpe y se desvanece. El quad y su material son por instancia y se
## construyen una vez en _ready; play() solo recolorea y anima.

var _material: StandardMaterial3D = null
var _tween: Tween = null


func _ready() -> void:
	# cast_shadow vive en MuzzleFlash.tscn con el resto de las reglas de
	# geometría de efectos (un efecto emisivo no proyecta sombra).
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = _material
	mesh = quad


## Contrato del pool: mata un destello viejo para que el reuso empiece limpio.
func pool_reset() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	transparency = 0.0


## Lanza el destello en `at`. Con grow_time > 0 el quad primero crece desde
## un punto (el destello de carga del arco); con 0 aparece de golpe (fogonazo).
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
