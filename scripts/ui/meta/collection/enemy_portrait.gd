class_name EnemyPortrait
extends Control
## Retrato 3D giratorio de un enemigo en el detalle de la Colección
## (EnemyPortrait.tscn): su cuerpo dando vueltas lentas dentro de UN
## EnemyStage. Es el único SubViewport vivo de la pantalla, y solo dibuja
## mientras se ve. Sin cuerpo que mostrar se oculta solo y deja ver el marco
## de abajo (la foto o la inicial).

@export_group("Modelo")
## Velocidad del giro, en grados por segundo.
@export var spin_speed: float = 28.0
## Ángulo (grados) con que aparece cada enemigo: 0 = de frente a la cámara.
@export var start_angle: float = -24.0
## Duración (segundos) del fundido con que aparece el cuerpo.
@export var model_fade_time: float = 0.18
## Tope del lado del SubViewport (píxeles), para pantallas muy grandes.
@export var max_viewport_side: int = 1024

var _angle: float = 0.0
var _fade: Tween = null

@onready var _stage: EnemyStage = $Stage
@onready var _view: TextureRect = $View


func _ready() -> void:
	_view.texture = _stage.get_texture()
	_stage.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	resized.connect(_fit_viewport)
	_fit_viewport()
	visible = false
	set_process(false)


func _process(delta: float) -> void:
	_angle = fmod(_angle + spin_speed * delta, 360.0)
	_stage.set_angle(_angle)


## Muestra girando al enemigo de esa escena. Devuelve false (y se oculta) si
## no hay cuerpo que mostrar.
func show_enemy(scene_path: String) -> bool:
	_angle = start_angle
	_stage.set_angle(_angle)
	var shown := _stage.show_enemy(scene_path)
	visible = shown
	set_process(shown)
	if not shown:
		return false
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_view.modulate.a = 0.0
	_fade = create_tween()
	_fade.set_ignore_time_scale(true)
	_fade.tween_property(_view, "modulate:a", 1.0, model_fade_time) \
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	return true


## Saca al enemigo y deja de dibujar.
func clear() -> void:
	_stage.clear()
	visible = false
	set_process(false)


## El SubViewport mide lo que mide el retrato en pantalla (con tope), así el
## cuerpo se ve nítido sin dibujar píxeles de más.
func _fit_viewport() -> void:
	var side := clampi(roundi(maxf(size.x, size.y)), 64, max_viewport_side)
	var aspect := size.x / maxf(size.y, 1.0)
	_stage.size = Vector2i(side, maxi(roundi(float(side) / maxf(aspect, 0.1)), 64)) \
			if aspect >= 1.0 else Vector2i(maxi(roundi(float(side) * aspect), 64), side)
