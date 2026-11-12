extends CanvasLayer
## Autoload ScreenFade: fundido a negro de un cuarto de segundo alrededor de
## cada cambio de escena (selector → partida, partida → selector, reintentar,
## pantallas meta). transition(action) funde a negro un rect de pantalla
## completa, ejecuta el callable (el change_scene/reload y su limpieza) y
## vuelve a fundir. Dibuja encima de todo (UiLayers.SCREEN_FADE), procesa
## siempre e ignora la escala de tiempo, así que funciona desde la pantalla de
## fin en pausa y en pleno hit-stop. Es seguro en headless: solo es un tween de
## un ColorRect.
##
## transition_async() es la variante que espera, para trabajo que dura varios
## frames (el cambio de etapa). Mientras hay un fundido en curso, las
## peticiones repetidas se DESCARTAN y ambas devuelven false: gana el primer
## cambio y el fundido nunca deja el juego a medio negro. Por eso la limpieza
## irreversible va DENTRO del callable (o se revisa el retorno), nunca antes
## de la llamada: la ventana ocupada dura FADE_OUT_TIME más que el cambio.
##
## leave_run() es el único ritual para terminar una partida: es dueño de la
## limpieza, el reinicio y el cambio, y mantiene el árbol en pausa en el corte.
## Es un autoload sin escena: edita los valores aquí.

## Duración (segundos) del fundido a negro y del regreso.
const FADE_IN_TIME := 0.22
const FADE_OUT_TIME := 0.26
## Color del rect del fundido.
const FADE_COLOR := Color(0.015, 0.018, 0.03)

var _rect: ColorRect
var _tween: Tween = null
var _busy: bool = false


func _ready() -> void:
	layer = UiLayers.SCREEN_FADE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.color = FADE_COLOR
	_rect.modulate.a = 0.0
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)


## True mientras corre un corte, es decir, mientras toda petición nueva se
## descartaría.
func is_busy() -> bool:
	return _busy


## Devuelve false si ya corría un fundido y esta petición se descartó sin
## hacer nada.
func transition(action: Callable) -> bool:
	if _busy:
		return false
	_busy = true
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP  # traga los clics del corte
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_ignore_time_scale(true)
	_tween.tween_property(_rect, "modulate:a", 1.0, FADE_IN_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.tween_callback(action)
	# Devuelve el mouse con el corte, no con la bandera: el rect sigue
	# fundiéndose FADE_OUT_TIME más sobre la escena que el jugador ya ve, y
	# tragarse esos clics se siente como una UI congelada.
	_tween.tween_callback(_release_mouse)
	_tween.tween_property(_rect, "modulate:a", 0.0, FADE_OUT_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_clear_busy)
	return true


## Hermano asíncrono de transition(): ESPERA la acción entre el fundido de
## entrada y el de salida. transition() no puede: su acción corre dentro de
## un tween_callback, y un callback que es corrutina vuelve al tween en su
## primer await, así que la pantalla volvería a mitad del trabajo. El cambio
## de etapa necesita varios frames (liberaciones, la arena siguiente).
##
## Mismo contrato que transition(): una petición que llega durante otro
## fundido se DESCARTA y devuelve false, para que el llamador decida si
## reintenta.
func transition_async(action: Callable) -> bool:
	if _busy:
		return false
	_busy = true
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP  # traga los clics del corte
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_ignore_time_scale(true)
	_tween.tween_property(_rect, "modulate:a", 1.0, FADE_IN_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await _tween.finished
	await action.call()
	# Devuelve el mouse con el corte, no con la bandera (ver transition).
	_release_mouse()
	_tween = create_tween()
	_tween.set_ignore_time_scale(true)
	_tween.tween_property(_rect, "modulate:a", 0.0, FADE_OUT_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await _tween.finished
	_clear_busy()
	return true


## La única forma de salir de una partida en curso (reintentar, volver al
## selector, abandonar desde la pausa). Es dueña de todo el ritual para que
## ningún llamador olvide un paso: guarda los ajustes, para los loops de
## audio, borra el estado de la partida y cambia de escena. Una scene_path
## vacía recarga la escena actual.
##
## El árbol queda EN PAUSA durante el cambio a propósito: change_scene_to_file
## y reload_current_scene son diferidos, y despausar aquí le daría a la escena
## saliente un frame más de una partida que ya terminó (los enemigos que
## mueren en ella sumarían bajas a la partida SIGUIENTE y el director
## dispararía eventos en una escena por liberarse).
func leave_run(scene_path: String = "") -> bool:
	return transition(func() -> void:
		Settings.flush_save()
		Sfx.stop_all_loops()
		get_tree().paused = true
		RunState.reset()
		if scene_path.is_empty():
			get_tree().reload_current_scene()
		else:
			get_tree().change_scene_to_file(scene_path)
		_unpause_after_swap())


## Devuelve la pausa cuando el cambio diferido ya aterrizó: dos frames,
## porque el primero todavía es del árbol saliente. Esperar aquí es seguro y
## en ningún otro lado: este autoload es el único nodo que sobrevive al cambio.
func _unpause_after_swap() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().paused = false


func _release_mouse() -> void:
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _clear_busy() -> void:
	_busy = false
	_release_mouse()
