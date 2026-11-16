class_name EnemyStudio
extends Node
## Estudio de fotos de los enemigos para las cartas de la Colección
## (EnemyStudio.tscn). Para a cada enemigo en UN EnemyStage que solo dibuja
## cuando se le pide (UPDATE_ONCE), saca UNA foto, la recorta al cuerpo y la
## guarda como textura. Diez cartas cuestan diez fotos al abrir y nada después.
##
## Las fotos quedan en memoria toda la sesión: volver a Enemigos no las
## repite. Un enemigo sin escena o sin cuerpo se salta y su carta conserva la
## inicial. En headless no se dibuja nada, así que el estudio no trabaja.
##
## Avanza de a un paso por frame (_process) en vez de esperar con await: si la
## pantalla se cierra a mitad de las fotos, no queda nada pendiente.

## Hay una foto nueva para la carta de ese enemigo.
signal photo_ready(enemy_id: String, photo: Texture2D)

enum Step { IDLE, POSING, SHOOTING }

## Frames entre parar el cuerpo y pedir la foto, y entre pedirla y leerla (el
## SubViewport dibuja al final del frame en que se le pide).
const POSE_FRAMES := 2
const SHOOT_FRAMES := 2

@export_group("Foto")
## Ángulo (grados) del cuerpo en la foto: 0 = de frente a la cámara.
@export var pose_angle: float = -22.0
## Aire alrededor del cuerpo al recortar, como fracción de su lado más largo.
@export var crop_margin: float = 0.08
## Lado máximo de la foto guardada, en píxeles.
@export var photo_max_side: int = 384

## Fotos ya sacadas, por id de enemigo. Compartidas por toda la sesión.
static var _photos: Dictionary[String, Texture2D] = {}

## Entradas que esperan su foto ({id, scene}).
var _queue: Array[Dictionary] = []
var _current_id: String = ""
var _step: Step = Step.IDLE
var _wait: int = 0

@onready var _stage: EnemyStage = $Stage


func _ready() -> void:
	set_process(false)


## La foto ya sacada de ese enemigo, o null si todavía no hay.
static func cached_photo(enemy_id: String) -> Texture2D:
	return _photos.get(enemy_id) as Texture2D


## Pide las fotos de esas entradas de CollectionEntries (usa `id` y `scene`).
## Las que faltan se sacan una por una y avisan con photo_ready.
func shoot_entries(entries: Array[Dictionary]) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for entry: Dictionary in entries:
		var scene := String(entry.get("scene", ""))
		if not scene.is_empty() and not _photos.has(String(entry.id)):
			_queue.append({"id": String(entry.id), "scene": scene})
	set_process(not _queue.is_empty() or _step != Step.IDLE)


func _process(_delta: float) -> void:
	match _step:
		Step.IDLE:
			_next()
		Step.POSING:
			_wait -= 1
			if _wait <= 0:
				_stage.render_target_update_mode = SubViewport.UPDATE_ONCE
				_wait = SHOOT_FRAMES
				_step = Step.SHOOTING
		Step.SHOOTING:
			_wait -= 1
			if _wait <= 0:
				_keep_photo()


func _next() -> void:
	if _queue.is_empty():
		_stage.clear()
		set_process(false)
		return
	var job: Dictionary = _queue.pop_front()
	_current_id = String(job.id)
	_stage.set_angle(pose_angle)
	if not _stage.show_enemy(String(job.scene)):
		return
	_wait = POSE_FRAMES
	_step = Step.POSING


func _keep_photo() -> void:
	_step = Step.IDLE
	var image := _stage.get_texture().get_image()
	if image == null or image.is_empty():
		return
	var used := image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return
	# Recorte cuadrado alrededor de lo que de verdad se dibujó.
	var side := int(float(maxi(used.size.x, used.size.y)) * (1.0 + crop_margin * 2.0))
	side = mini(side, mini(image.get_width(), image.get_height()))
	var center := used.get_center()
	var left := clampi(center.x - side / 2, 0, image.get_width() - side)
	var top := clampi(center.y - side / 2, 0, image.get_height() - side)
	var cropped := image.get_region(Rect2i(left, top, side, side))
	if side > photo_max_side:
		cropped.resize(photo_max_side, photo_max_side, Image.INTERPOLATE_LANCZOS)
	var photo := ImageTexture.create_from_image(cropped)
	_photos[_current_id] = photo
	photo_ready.emit(_current_id, photo)
