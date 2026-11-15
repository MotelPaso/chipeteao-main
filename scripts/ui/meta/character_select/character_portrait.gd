class_name CharacterPortrait
extends Control
## Retrato del raider en el panel de detalle del selector
## (CharacterPortrait.tscn): su cuerpo 3D girando lento dentro de UN
## SubViewport, sobre un fondo teñido con su color. El cuerpo lo arma el mismo
## SealRig de la partida (modelo de la fila, foca por defecto, tinte), así que
## el retrato es lo que se va a jugar.
##
## Si la fila nombra un model_scene que no existe, o el modelo no carga, queda
## la inicial del raider sobre el fondo y no se registra ningún error. Los
## modelos se cargan en un hilo para que moverse entre cartas no dé tirones.

## Cuerpo de las filas sin model_scene, el mismo respaldo de la partida.
const SEAL_SCENE := SealRig.DEFAULT_MODEL_SCENE
## Tope del lado del SubViewport (píxeles), para pantallas muy grandes.
const MAX_VIEWPORT_SIDE := 1400
## Frames tras mostrar un cuerpo en que se vuelve a encuadrar (ver _reframe_in).
const REFRAME_FRAMES := 3

@export_group("Modelo")
## Las filas sin model_scene muestran la foca teñida (su cuerpo en la
## partida). Apagado, muestran la inicial.
@export var seal_for_rows_without_model: bool = true
## Velocidad del giro, en grados por segundo.
@export var spin_speed: float = 28.0
## Ángulo (grados) con que aparece cada raider: 0 = de frente a la cámara.
@export var start_angle: float = -24.0
## Aire alrededor del cuerpo: 1.0 lo ajusta justo al borde del retrato.
@export var framing_margin: float = 1.22
## Holgura alrededor de las articulaciones de un cuerpo con esqueleto, como
## fracción de su alto (cubre cabeza, manos y pies, que pasan de la última
## articulación).
@export var skin_padding: float = 0.14
## Altura a la que mira la cámara, como fracción del alto del cuerpo desde su
## centro (0.1 = un poco sobre el centro).
@export var look_height: float = 0.04
## Cuánto sube la cámara sobre ese punto, como fracción del alto del cuerpo.
@export var camera_lift: float = 0.22
## Duración (segundos) del fundido con que aparece el cuerpo.
@export var model_fade_time: float = 0.18

@export_group("Fondo")
## Cuánto se oscurece el tinte del raider para el fondo (0-1).
@export_range(0.0, 1.0) var backdrop_darken: float = 0.72
## Cuánto se oscurece el tinte para el borde del retrato (0-1).
@export_range(0.0, 1.0) var backdrop_rim_darken: float = 0.25
## Alfa (0-1) del foco de luz detrás del cuerpo, en el color del tinte.
@export_range(0.0, 1.0) var spot_alpha: float = 0.55
## Cuánto se oscurece el tinte para el contorno de la inicial (0-1).
@export_range(0.0, 1.0) var monogram_outline_darken: float = 0.7

## Escenas de modelo ya cargadas, por ruta. Guardarlas aquí las mantiene en la
## caché del motor: el load() de SealRig.setup las devuelve al instante.
var _scenes: Dictionary[String, PackedScene] = {}
## Rutas pedidas al hilo de carga que todavía no llegan.
var _loading: Array[String] = []
## Fila que debe verse; el cuerpo aparece cuando su escena termina de cargar.
var _row: Dictionary = {}
## Ruta del modelo que está en el rig, o "" si se ve la inicial.
var _shown_path: String = ""
## Frames que faltan para volver a encuadrar: el script de pose de un modelo
## (brazos abajo, animación de reposo) corre después de mostrarlo.
var _reframe_in: int = 0
var _fade_tween: Tween = null

@onready var _backdrop: Panel = $Backdrop
@onready var _backdrop_style: StyleBoxFlat = \
		($Backdrop as Panel).get_theme_stylebox(&"panel") as StyleBoxFlat
@onready var _spot: TextureRect = $Spot
@onready var _monogram: Label = $Monogram
@onready var _view: TextureRect = $View
@onready var _viewport: SubViewport = $Viewport
@onready var _camera: Camera3D = $Viewport/Stage/Camera
@onready var _pivot: Node3D = $Viewport/Stage/Pivot
@onready var _rig: SealRig = $Viewport/Stage/Pivot/Rig


func _ready() -> void:
	_view.texture = _viewport.get_texture()
	_view.modulate.a = 0.0
	# El lienzo no cambia de tamaño cuando la ventana crece en proporción, pero
	# sus píxeles sí: también se sigue a la ventana.
	resized.connect(_fit_viewport)
	get_window().size_changed.connect(_fit_viewport)
	_fit_viewport()


func _process(delta: float) -> void:
	_poll_loading()
	if _shown_path.is_empty():
		return
	_pivot.rotate_y(deg_to_rad(spin_speed) * delta)
	if _reframe_in > 0:
		_reframe_in -= 1
		if _reframe_in == 0:
			_frame_camera()


## Empieza a cargar en segundo plano los modelos de esas filas, para que el
## primer paso por cada carta ya los encuentre listos.
func preload_rows(rows: Array[Dictionary]) -> void:
	for row: Dictionary in rows:
		_request(_model_path(row))


## Muestra el raider de la fila `row` del catálogo: fondo e inicial al
## instante, y su cuerpo 3D en cuanto está cargado.
func show_character(row: Dictionary) -> void:
	_row = row
	var tint := Color(row.tint)
	_backdrop_style.bg_color = tint.darkened(backdrop_darken)
	_backdrop_style.border_color = tint.darkened(backdrop_rim_darken)
	_spot.modulate = Color(tint, spot_alpha)
	_monogram.text = String(row.display_name).left(1).to_upper()
	_monogram.add_theme_color_override("font_outline_color",
			tint.darkened(monogram_outline_darken))
	var path := _model_path(row)
	_request(path)
	if _scenes.has(path):
		_show_model(path)
	else:
		_show_monogram()


## True mientras se ve el cuerpo 3D (y no la inicial de respaldo).
func shows_model() -> bool:
	return not _shown_path.is_empty()


## Ruta del cuerpo de la fila, o "" si le toca la inicial: sin modelo y con la
## foca apagada, o con un model_scene que no existe en el proyecto.
func _model_path(row: Dictionary) -> String:
	var path := String(row.get("model_scene", ""))
	if path.is_empty():
		path = SEAL_SCENE if seal_for_rows_without_model else ""
	if path.is_empty() or not ResourceLoader.exists(path, "PackedScene"):
		return ""
	return path


func _request(path: String) -> void:
	if path.is_empty() or _scenes.has(path) or _loading.has(path):
		return
	if ResourceLoader.load_threaded_request(path, "PackedScene") == OK:
		_loading.append(path)


## Recoge las cargas terminadas; si llegó la del raider en pantalla, lo muestra.
func _poll_loading() -> void:
	if _loading.is_empty():
		return
	for path: String in _loading.duplicate():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			continue
		_loading.erase(path)
		if status != ResourceLoader.THREAD_LOAD_LOADED:
			continue
		var scene := ResourceLoader.load_threaded_get(path) as PackedScene
		if scene != null:
			_scenes[path] = scene
	if not _row.is_empty() and _shown_path.is_empty():
		var wanted := _model_path(_row)
		if _scenes.has(wanted):
			_show_model(wanted)


func _show_monogram() -> void:
	_shown_path = ""
	_kill_fade()
	_view.modulate.a = 0.0
	_monogram.visible = true


## Arma el cuerpo en el rig (igual que Player._apply_character: primero el
## modelo, después el tinte), lo encuadra y lo funde sobre el fondo.
func _show_model(path: String) -> void:
	_rig.setup(path, float(_row.get("model_scale", 1.0)),
			String(_row.get("tint_material_prefix", "")))
	_rig.apply_tint(Color(_row.tint))
	_shown_path = path
	_monogram.visible = false
	_pivot.rotation = Vector3(0.0, deg_to_rad(start_angle), 0.0)
	_frame_camera()
	_reframe_in = REFRAME_FRAMES
	_kill_fade()
	_view.modulate.a = 0.0
	_fade_tween = create_tween()
	_fade_tween.set_ignore_time_scale(true)
	_fade_tween.tween_property(_view, "modulate:a", 1.0, model_fade_time) \
			.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)


func _kill_fade() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null


## Aleja la cámara lo justo para que el cuerpo entre en el retrato, mida lo
## que mida su modelo. El ancho usa el radio de giro, así no se sale al rotar.
func _frame_camera() -> void:
	var bounds := BodyBounds.of(_rig, _pivot, skin_padding)
	if bounds.size.is_zero_approx():
		return
	var center := bounds.get_center()
	var height := bounds.size.y
	var spin_radius := Vector2(
			maxf(absf(bounds.position.x), absf(bounds.end.x)),
			maxf(absf(bounds.position.z), absf(bounds.end.z))).length()
	var aspect := maxf(size.x / maxf(size.y, 1.0), 0.1)
	var half_extent := maxf(height * 0.5, spin_radius / aspect) * framing_margin
	var distance := half_extent / tan(deg_to_rad(_camera.fov) * 0.5)
	var target := Vector3(0.0, center.y + height * look_height, 0.0)
	_camera.position = target + Vector3(0.0, height * camera_lift, -distance)
	_camera.look_at(target)


## El SubViewport dibuja a la resolución real de pantalla del retrato (el
## lienzo de la UI se estira con la ventana), así el cuerpo no se ve borroso.
func _fit_viewport() -> void:
	var pixels := size * get_viewport().get_final_transform().get_scale()
	_viewport.size = Vector2i(
			clampi(roundi(pixels.x), 2, MAX_VIEWPORT_SIDE),
			clampi(roundi(pixels.y), 2, MAX_VIEWPORT_SIDE))
	if not _shown_path.is_empty():
		_frame_camera()
