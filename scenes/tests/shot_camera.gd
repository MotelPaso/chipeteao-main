class_name ShotCamera
extends RefCounted
## Cámara que llevan los dos arneses de soak, activada con BONK_SHOT_DIR.
##
## POR QUÉ EXISTE. Los gates corren --headless, y el renderer dummy no
## compila shaders ni rasteriza nada: un suelo con las caras al revés, un
## material que no se aplica, un panel encima del reloj o un texto cortado
## dejan el log igual de verde. Con esta clase un soak mira la pantalla.
##
## CÓMO CAPTURA. Desde DENTRO del motor
## (Viewport.get_texture().get_image() después de
## RenderingServer.frame_post_draw), nunca con un capturador de pantalla:
## macOS rechaza `screencapture` desde una terminal sin el permiso de
## Grabación de pantalla, y en un soak no hay nadie que lo conceda.
##
## Solo AGREGA frames. Nada aquí cambia lo que afirma un arnés, y sin la
## variable cada línea de abajo no hace nada.

## Segundos entre fotos periódicas cuando BONK_SHOT_EVERY no está definido.
const SHOT_EVERY_DEFAULT: float = 10.0
const SHOT_DIR_ENV := "BONK_SHOT_DIR"
const SHOT_EVERY_ENV := "BONK_SHOT_EVERY"

var _dir: String = ""
var _on: bool = false
var _every: float = SHOT_EVERY_DEFAULT
## Cuenta HACIA ABAJO hasta la próxima foto periódica. Se alimenta con el
## delta del llamador y no con RunState.run_time: run_time se congela
## mientras un menú tiene la pausa, y un menú es justo lo que vale fotografiar.
var _left: float = 0.0
## Nombres pendientes, uno por frame DIBUJADO: dos eventos en el mismo
## frame dan dos archivos y no la misma imagen guardada dos veces.
var _queue: Array[String] = []
var _busy: bool = false
var _taken: int = 0
var _viewport: Viewport = null
## Fotos pedidas con retraso, como {left, stem}. Un EVENTO no es lo mismo
## que cómo se ve: el mapa se abre el frame después de apretar Tab, el tinte
## del clima entra de a poco y un cambio de etapa va detrás de un fundido,
## así que la foto del frame del evento muestra el momento anterior.
var _pending: Array[Dictionary] = []


## `viewport` es el que se guarda: el get_viewport() del propio arnés, o sea
## la raíz de la ventana, que compone las celdas de pantalla dividida y cada
## CanvasLayer encima.
func _init(viewport: Viewport, every_default: float = SHOT_EVERY_DEFAULT) -> void:
	_viewport = viewport
	_every = every_default
	var dir := OS.get_environment(SHOT_DIR_ENV).strip_edges()
	if dir.is_empty():
		return
	# El DisplayServer dummy nunca dibuja y su textura está vacía, así que cada
	# PNG sería mentira. Se avisa una sola vez: quien pidió fotos tiene que
	# poder ver que no obtuvo ninguna.
	if DisplayServer.get_name() == "headless":
		print("Shots skipped: headless")
		return
	var every := OS.get_environment(SHOT_EVERY_ENV)
	if every.is_valid_float():
		_every = maxf(every.to_float(), 0.1)
	DirAccess.make_dir_recursive_absolute(dir)
	if not DirAccess.dir_exists_absolute(dir):
		push_warning("ShotCamera: cannot create %s '%s'" % [SHOT_DIR_ENV, dir])
		return
	_dir = dir
	_on = true
	_left = _every
	print("Shots on: dir=%s every=%.1fs" % [_dir, _every])


## Lo que consulta cada llamador en vez de releer el entorno.
func enabled() -> bool:
	return _on


func every() -> float:
	return _every


## Encola una foto con nombre `stem` (sin extensión). Seguro desde cualquier
## lugar, incluso desde una señal de un nodo que está por liberarse.
func request(stem: String) -> void:
	if _on:
		_queue.append(stem)


## Encola una foto dentro de `delay` segundos. Ver _pending: algunos eventos
## valen por lo que DEJAN en pantalla, no por el frame en que ocurren.
func request_in(delay: float, stem: String) -> void:
	if not _on:
		return
	if delay <= 0.0:
		request(stem)
		return
	_pending.append({"left": delay, "stem": stem})


## Maneja la foto periódica y vacía la cola, un frame a la vez.
## `periodic_stem` es un Callable que devuelve el nombre de la foto periódica:
## Callable y no texto porque el nombre lleva el reloj de la partida, que
## solo se conoce cuando toca la foto.
func tick(delta: float, periodic_stem: Callable) -> void:
	if not _on:
		return
	for index in range(_pending.size() - 1, -1, -1):
		var due: Dictionary = _pending[index]
		due["left"] = float(due["left"]) - delta
		if float(due["left"]) <= 0.0:
			_pending.remove_at(index)
			request(String(due["stem"]))
	_left -= delta
	if _left <= 0.0:
		_left = _every
		request(String(periodic_stem.call()))
	if _busy or _queue.is_empty():
		return
	_busy = true
	# Se lanza sin await: el frame del llamador tiene otro trabajo.
	_take(_queue.pop_front())


## Un PNG, guardado cuando su frame ya se DIBUJÓ: get_image() antes de
## frame_post_draw devuelve el frame ANTERIOR, que en una foto de evento es
## el frame previo al evento.
func _take(stem: String) -> void:
	await RenderingServer.frame_post_draw
	_busy = false
	var image := _frame()
	if image == null:
		push_warning("ShotCamera: no frame to save for '%s'" % stem)
		return
	_write(image, stem)


## `final.png`, tomada SIN esperar frame_post_draw: esto corre desde un
## _exit_tree, donde una corrutina esperando una señal nunca se reanuda.
## Cuesta un frame de atraso y guarda lo que había en pantalla al terminar.
func final_shot() -> void:
	if not _on:
		return
	var image := _frame()
	if image == null:
		push_warning("ShotCamera: no frame to save for final.png")
		return
	_write(image, "final")


## El último frame dibujado de la ventana, o null si ya no queda viewport
## que leer (cierre, o un display server que nunca dibujó).
func _frame() -> Image:
	if not is_instance_valid(_viewport):
		return null
	var texture := _viewport.get_texture()
	return texture.get_image() if texture != null else null


func _write(image: Image, stem: String) -> void:
	var path := "%s/%s.png" % [_dir, stem]
	# El reloj de la partida se congela mientras un menú tiene la pausa, así que
	# dos fotos pueden pedir el mismo nombre; el sufijo con contador guarda ambas.
	# `final` es el único nombre que se sobrescribe a propósito.
	if stem != "final" and FileAccess.file_exists(path):
		path = "%s/%s-%d.png" % [_dir, stem, _taken]
	var error := image.save_png(path)
	if error != OK:
		push_warning("ShotCamera: cannot write '%s' (error %d)" % [path, error])
		return
	_taken += 1
	print("Shot saved: %s" % path)
