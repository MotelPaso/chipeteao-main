class_name PortraitStudio
extends Node
## Estudio de fotos de las cartas del selector (PortraitStudio.tscn): arma el
## cuerpo 3D de cada raider en UN SubViewport, lo encuadra en la cabeza y el
## busto, saca UNA foto y la guarda como textura. Las cartas muestran esa
## foto, así que doce caras cuestan doce fotos al abrir y nada después (un
## SubViewport vivo por carta dibujaría doce escenas 3D en cada frame).
##
## Las fotos quedan en memoria toda la sesión: volver al selector no las
## repite. Un raider cuyo modelo no existe o no carga se salta sin avisar y su
## carta conserva la inicial. En headless no se dibuja nada, así que el
## estudio no trabaja.
##
## Avanza de a un paso por frame (_process) en vez de esperar con await: si el
## selector se cierra a mitad de las fotos, no queda nada pendiente.

## Hay una cara nueva para la carta de ese raider.
signal face_ready(character_id: String, face: Texture2D)

enum Step { IDLE, LOADING, POSING, SHOOTING }

## Frames entre armar el cuerpo y encuadrarlo: el script de pose del modelo
## (brazos abajo, animación de reposo) corre después de entrar al árbol.
const POSE_FRAMES := 3
## Frames entre pedir la foto y leerla: el SubViewport dibuja al final del
## frame en que se le pide.
const SHOOT_FRAMES := 2
## Veces que se repite una foto que salió vacía antes de dejar la inicial: el
## primer dibujo de un modelo puede tardar un frame más (compila sus shaders).
const SHOOT_RETRIES := 3

@export_group("Encuadre")
## Las filas sin model_scene muestran la foca teñida (su cuerpo en la partida).
@export var seal_for_rows_without_model: bool = true
## Ángulo (grados) del cuerpo en la foto: 0 = de frente a la cámara.
@export var pose_angle: float = -22.0
## Alto de la ventana de la foto, como múltiplo del ancho del cuerpo: un
## cuerpo alto y angosto (humanoide) queda recortado en el busto y uno ancho
## (la foca) sale entero.
@export var window_per_width: float = 0.85
## Límites de esa ventana, como fracción del alto del cuerpo.
@export_range(0.1, 1.0) var window_min: float = 0.42
@export_range(0.1, 1.0) var window_max: float = 1.0
## Aire sobre la cabeza, como fracción de la ventana.
@export var headroom: float = 0.08
## Aire alrededor: 1.0 ajusta la ventana justo al borde de la foto.
@export var framing_margin: float = 1.12
## Cuánto sube la cámara sobre el punto que mira, como fracción de la ventana.
@export var camera_lift: float = 0.12
## Holgura alrededor de las articulaciones de un cuerpo con esqueleto, como
## fracción de su alto.
@export var skin_padding: float = 0.14

@export_group("Foto")
## Aire que se deja alrededor del cuerpo al recortar la foto, como fracción
## del lado más largo de lo dibujado.
@export var crop_margin: float = 0.06
## Ancho máximo de la foto guardada, en píxeles (las más grandes se reducen).
@export var face_max_width: int = 448

## Caras ya fotografiadas, por id de personaje. Compartidas por toda la sesión.
static var _faces: Dictionary[String, Texture2D] = {}

## Filas que esperan su foto.
var _queue: Array[Dictionary] = []
## Fila en el estudio ahora.
var _row: Dictionary = {}
var _path: String = ""
var _step: Step = Step.IDLE
var _wait: int = 0
var _retries_left: int = 0
## Escenas de modelo cargadas aquí; guardarlas las mantiene en la caché del
## motor mientras dura el selector.
var _scenes: Dictionary[String, PackedScene] = {}

@onready var _viewport: SubViewport = $Viewport
@onready var _camera: Camera3D = $Viewport/Stage/Camera
@onready var _pivot: Node3D = $Viewport/Stage/Pivot
@onready var _rig: SealRig = $Viewport/Stage/Pivot/Rig


func _ready() -> void:
	set_process(false)


## La cara ya fotografiada de ese raider, o null si todavía no hay.
static func cached_face(character_id: String) -> Texture2D:
	return _faces.get(character_id) as Texture2D


## Pide las caras de esas filas del catálogo. Las que faltan se fotografían
## una por una y avisan con face_ready.
func shoot_rows(rows: Array[Dictionary]) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for row: Dictionary in rows:
		if not _faces.has(String(row.id)):
			_queue.append(row)
	set_process(not _queue.is_empty() or _step != Step.IDLE)


func _process(_delta: float) -> void:
	match _step:
		Step.IDLE:
			_next_row()
		Step.LOADING:
			_poll_load()
		Step.POSING:
			_wait -= 1
			if _wait <= 0:
				_shoot()
		Step.SHOOTING:
			_wait -= 1
			if _wait <= 0:
				_keep_photo()


func _next_row() -> void:
	if _queue.is_empty():
		set_process(false)
		return
	_row = _queue.pop_front()
	_path = _model_path(_row)
	if _path.is_empty():
		return
	if not ResourceLoader.has_cached(_path):
		ResourceLoader.load_threaded_request(_path, "PackedScene")
	_step = Step.LOADING


## La escena puede llegar por este pedido o por el del retrato del detalle,
## que carga los mismos modelos: lo que cuenta es que ya esté en la caché.
func _poll_load() -> void:
	if not ResourceLoader.has_cached(_path):
		match ResourceLoader.load_threaded_get_status(_path):
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				return
			ResourceLoader.THREAD_LOAD_LOADED:
				var scene := ResourceLoader.load_threaded_get(_path) as PackedScene
				if scene == null:
					_step = Step.IDLE
					return
				_scenes[_path] = scene
			_:
				_step = Step.IDLE
				return
	# Igual que Player._apply_character: primero el modelo, después el tinte.
	_rig.setup(_path, float(_row.get("model_scale", 1.0)),
			String(_row.get("tint_material_prefix", "")))
	_rig.apply_tint(Color(_row.tint))
	_pivot.rotation = Vector3(0.0, deg_to_rad(pose_angle), 0.0)
	_wait = POSE_FRAMES
	_step = Step.POSING


func _shoot() -> void:
	if not _frame_camera():
		_step = Step.IDLE
		return
	_retries_left = SHOOT_RETRIES
	_request_photo()


func _request_photo() -> void:
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_wait = SHOOT_FRAMES
	_step = Step.SHOOTING


func _keep_photo() -> void:
	_step = Step.IDLE
	var image := _viewport.get_texture().get_image()
	if image != null and not image.is_empty():
		image = _crop_to_body(image)
	if image == null or image.is_empty():
		if _retries_left > 0:
			_retries_left -= 1
			_request_photo()
		return
	var face := ImageTexture.create_from_image(image)
	var character_id := String(_row.id)
	_faces[character_id] = face
	face_ready.emit(character_id, face)


## Recorta la foto a lo que de verdad se dibujó. La caja de un cuerpo con
## esqueleto es una estimación (articulaciones más holgura) y puede dejar al
## raider chico o corrido; los píxeles no mienten. El recorte conserva la
## proporción de la foto y nunca corta el cuerpo por arriba ni por los lados.
## Devuelve null si no se dibujó nada.
func _crop_to_body(image: Image) -> Image:
	var used := image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return null
	var full := Vector2(image.get_size())
	var aspect := full.x / full.y
	var margin := float(maxi(used.size.x, used.size.y)) * crop_margin
	var width := minf(maxf(used.size.x + margin * 2.0,
			(used.size.y + margin * 2.0) * aspect), full.x)
	var height := minf(width / aspect, full.y)
	width = height * aspect
	var left := clampf(used.get_center().x - width * 0.5, 0.0, full.x - width)
	var top := clampf(float(used.position.y) - margin, 0.0, full.y - height)
	var region := Rect2i(roundi(left), roundi(top), roundi(width), roundi(height))
	var cropped := image.get_region(region)
	if cropped.get_width() > face_max_width:
		cropped.resize(face_max_width, roundi(face_max_width / aspect),
				Image.INTERPOLATE_LANCZOS)
	return cropped


## Ruta del cuerpo de la fila, o "" si no hay modelo que fotografiar.
func _model_path(row: Dictionary) -> String:
	var path := String(row.get("model_scene", ""))
	if path.is_empty() and seal_for_rows_without_model:
		path = SealRig.DEFAULT_MODEL_SCENE
	if path.is_empty() or not ResourceLoader.exists(path, "PackedScene"):
		return ""
	return path


## Apunta la cámara a la parte de arriba del cuerpo. La ventana de la foto
## mide según el ANCHO del cuerpo, así un humanoide sale de busto y un cuerpo
## redondo sale entero. Devuelve false si no hay cuerpo que medir.
func _frame_camera() -> bool:
	var bounds := BodyBounds.of(_rig, _pivot, skin_padding)
	if bounds.size.is_zero_approx():
		return false
	var height := bounds.size.y
	var width := maxf(bounds.size.x, bounds.size.z)
	var window := clampf(width * window_per_width, height * window_min, height * window_max)
	var top := bounds.end.y + window * headroom
	var target := Vector3(bounds.get_center().x, top - window * 0.5, bounds.get_center().z)
	var aspect := float(_viewport.size.x) / float(maxi(_viewport.size.y, 1))
	var half_extent := maxf(window * 0.5, width * 0.5 / aspect) * framing_margin
	var distance := half_extent / tan(deg_to_rad(_camera.fov) * 0.5)
	_camera.position = target + Vector3(0.0, window * camera_lift, -distance)
	_camera.look_at(target)
	return true
