class_name MuzzleFlash
extends MeshInstance3D
## Destello puntual del pool (fogonazo de la Pistola de dardos, destello de
## carga del Arco de caza): un quad emisivo pequeño que mira a cámara, crece
## y se desvanece. Quien lo usa solo elige el estilo; color, tamaño y tiempos
## de cada estilo se editan aquí. El quad y su material son por instancia y
## se construyen una vez en _ready; play() solo recolorea y anima.

## Qué destello se dibuja.
enum Style { MUZZLE, GLINT }

@export_group("Fogonazo (Pistola de dardos)")
## Color del fogonazo en la boca de la Pistola de dardos.
@export var muzzle_color: Color = Color(1.0, 0.8, 0.35)
## Lado del fogonazo, en metros.
@export var muzzle_size: float = 0.5
## Segundos que tarda en crecer desde un punto; 0 = aparece de golpe.
@export var muzzle_grow_time: float = 0.0
## Segundos que tarda en desvanecerse.
@export var muzzle_fade_time: float = 0.09

@export_group("Destello de carga (Arco de caza)")
## Color del destello que crece en la cuerda del Arco de caza al soltar.
@export var glint_color: Color = Color(0.75, 0.95, 0.55)
## Lado del destello ya crecido, en metros.
@export var glint_size: float = 0.4
## Segundos que tarda en crecer desde un punto; 0 = aparece de golpe.
@export var glint_grow_time: float = 0.14
## Segundos que tarda en desvanecerse tras crecer.
@export var glint_fade_time: float = 0.1

@export_group("Crecimiento")
## Tamaño inicial al crecer, como fracción del tamaño final (0-1).
@export var grow_from_scale: float = 0.15

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


## Lanza el destello de estilo `style` en `at`.
func play(at: Vector3, style: Style) -> void:
	var is_glint := style == Style.GLINT
	var size := glint_size if is_glint else muzzle_size
	var grow_time := glint_grow_time if is_glint else muzzle_grow_time
	var fade_time := glint_fade_time if is_glint else muzzle_fade_time
	_material.albedo_color = glint_color if is_glint else muzzle_color
	global_position = at
	transparency = 0.0
	_tween = create_tween()
	if grow_time > 0.0:
		scale = Vector3.ONE * (size * grow_from_scale)
		_tween.tween_property(self, "scale", Vector3.ONE * size, grow_time) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		scale = Vector3.ONE * size
	_tween.tween_property(self, "transparency", 1.0, fade_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_callback(_release)


func _release() -> void:
	Pools.release(self)
