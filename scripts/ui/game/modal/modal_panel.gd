class_name ModalPanel
extends CanvasLayer
## Base de los paneles que un objeto del mundo abre sobre la partida pausada: la
## tienda del vendedor (VendorUi) y la ruleta (RouletteUi). Sus escenas heredan
## de ModalPanel.tscn (fondo, panel, título, puntos, cuerpo, resultado y
## botones) y sus scripts extienden este, que es dueño del contrato de pausa:
##   - al entrar al árbol pausa el árbol, libera el mouse y entra a los grupos
##     de BlockingUi ("ui_blocking" y "blocking_ui_closable");
##   - suelta la pausa UNA sola vez, al cerrarse o al salir del árbol, y solo si
##     la partida sigue y ninguna otra capa la tomó;
##   - se cierra solo si el raider o el objeto que lo abrió desaparecen: con el
##     árbol pausado nadie más lo notaría y la pausa duraría más que la partida;
##   - sin pantalla (headless) juega solo y se va, porque un soak no tiene quien
##     presione nada y un panel esperando para siempre congela la partida.
## Cada panel implementa _build() y _play_headless(), y si hace falta
## _can_close(), _accept_hint() y _log_tag().

## Corrida sin pantalla: segundos hasta que el panel juega solo, y desde esa
## jugada hasta que se cierra. Los soaks dependen de estos tiempos.
const HEADLESS_PLAY_DELAY := 0.4
const HEADLESS_LEAVE_DELAY := 3.0

@export_group("Panel")
## Margen interior del panel, en píxeles (horizontal, vertical).
@export var panel_margin: Vector2 = Vector2(32.0, 22.0)
## Espaciado extra entre letras del título, en píxeles. Tamaño y contorno del
## título están en el nodo Title de la escena.
@export var title_letter_spacing: int = 1

@export_group("Textos")
## Línea de puntos del raider; %d son sus puntos.
@export var points_template: String = UiTheme.POINTS_BALANCE
## Texto del botón que cierra el panel; también va en la indicación de cancelar.
@export var close_text: String = "Salir"

@onready var _panel: PanelContainer = %Panel
@onready var _title: Label = %Title
@onready var _points: Label = %Points
@onready var _body: VBoxContainer = %Body
@onready var _result: Label = %Result
@onready var _buttons: HBoxContainer = %Buttons
@onready var _close_button: Button = %CloseButton

## El objeto del mundo que abrió el panel (el puesto, el altar).
var _host: Node = null
## El raider que abrió el panel.
var _player: Node = null
## true solo entre el _ready que pausó el árbol y la liberación que lo devuelve
## (la regla de _pause_owned de pause_menu.gd). El cierre y el respaldo de
## _exit_tree pasan por aquí, así que la pausa se suelta una sola vez y un panel
## que nunca llegó a pausar no suelta nada.
var _pause_held: bool = false


func _ready() -> void:
	# Nada que vigilar (ni pausa propia que soltar) hasta que el panel está
	# arriba.
	set_process(false)
	if not is_instance_valid(_host) or not is_instance_valid(_player):
		push_error("%s: setup() must run before add_child()" % _log_tag())
		queue_free()
		return
	add_to_group(BlockingUi.GROUP)
	add_to_group(BlockingUi.CLOSABLE_GROUP)
	_title.add_theme_font_override("font", UiTheme.spaced_font(title_letter_spacing))
	_close_button.text = close_text
	UiTheme.style_button(_close_button)
	_close_button.pressed.connect(_close)
	_build()
	# Indicaciones de botón bajo los botones; siguen al último dispositivo usado.
	_buttons.get_parent().add_child(InputHints.build([
			["ui_accept", _accept_hint()], ["ui_cancel", close_text]]))
	get_tree().paused = true
	_pause_held = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	set_process(true)
	if DisplayServer.get_name() == "headless":
		_auto_play()


## Con el árbol pausado nada más puede notar que el raider ya no está (caída de
## todo el grupo en co-op, desmontaje de la escena) o que el objeto que abrió el
## panel se fue con la etapa. No quedaría nadie para presionar Salir.
func _process(_delta: float) -> void:
	if is_queued_for_deletion():
		return
	if not is_instance_valid(_player) or not is_instance_valid(_host):
		_close()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _can_close():
		_close()
		get_viewport().set_input_as_handled()


## _close() es el único camino que quita la pausa, así que un panel LIBERADO en
## vez de cerrado (free() desde un harness, el padre de la etapa que se va con
## un cambio de etapa) dejaría un árbol pausado sin nada en pantalla que lo
## suelte.
func _exit_tree() -> void:
	_release_pause()


## Contrato "ui_blocking" (BlockingUi): true mientras esta capa es dueña de la
## pausa. Es false apenas queda en cola para borrarse: el nodo sigue en el grupo
## hasta que la cola de borrado se vacía al final del frame, y un panel que se va
## y contesta "sí" hace que el selector de cartas (o un cambio de etapa) se salte
## su propia quita de pausa en ese frame.
func is_blocking() -> bool:
	return not is_queued_for_deletion()


## Cierre desde código (grupo "blocking_ui_closable": el cambio de etapa y los
## harness lo llaman). Respeta _can_close(): la ruleta espera a que termine su
## giro, porque el resultado ya está aplicado y solo falta mostrarlo.
func dismiss() -> void:
	if not _can_close():
		return
	_close()


## Lo llama el setup() de cada panel, antes de add_child(): quién lo abrió y
## para qué raider.
func _bind(host: Node, player: Node) -> void:
	_host = host
	_player = player


## Pinta el marco con el acento del panel: el borde del panel y el título.
func _style_frame(title_text: String, accent: Color) -> void:
	_panel.add_theme_stylebox_override("panel",
			UiTheme.panel(UiTheme.PANEL_BG, accent, panel_margin.x, panel_margin.y))
	_title.text = title_text
	_title.add_theme_color_override("font_color", accent)


## Escribe los puntos del raider en su línea y los devuelve.
func _show_points() -> int:
	var purse := int(_player.get("points"))
	_points.text = points_template % purse
	return purse


## Virtual: llena el panel (título, cuerpo, botones propios) y deja el foco en
## algo que se pueda presionar: con el árbol pausado, quien juega con control o
## teclado igual tiene que poder contestar.
func _build() -> void:
	pass


## Virtual: lo que el panel hace solo en una corrida sin pantalla.
func _play_headless() -> void:
	pass


## Virtual: false mientras Esc y dismiss() no deben cerrar el panel.
func _can_close() -> bool:
	return true


## Virtual: texto de la indicación del botón de aceptar.
func _accept_hint() -> String:
	return ""


## Virtual: nombre del panel en los mensajes de error.
func _log_tag() -> String:
	return "ModalPanel"


## Los soaks (y toda corrida sin pantalla) no tienen manos: el panel juega una
## vez y se va, así el árbol pausado siempre se devuelve.
func _auto_play() -> void:
	await get_tree().create_timer(HEADLESS_PLAY_DELAY, true, false, true).timeout
	if not is_inside_tree():
		return
	_play_headless()
	await get_tree().create_timer(HEADLESS_LEAVE_DELAY, true, false, true).timeout
	if is_inside_tree():
		_close()


## Protegido porque varios caminos pueden llegar aquí (Esc, el botón Salir, el
## cierre tras una venta, el respaldo sin pantalla, el vigía de _process) y la
## pausa debe soltarse una sola vez, por el primero que llegue.
func _close() -> void:
	if is_queued_for_deletion():
		return
	_release_pause()
	queue_free()


## Devuelve el árbol como máximo una vez, y solo si la pausa es NUESTRA. Una
## compra o un giro pueden poner otra capa "ui_blocking" en pantalla, y la
## partida puede terminar debajo de este panel, en cuyo caso la pantalla de fin
## es dueña de la pausa y del mouse: quitar la pausa en cualquiera de los dos
## casos reanudaría el mundo detrás del modal de otro y le quitaría el mouse a
## sus botones.
func _release_pause() -> void:
	if not _pause_held:
		return
	_pause_held = false
	if not RunState.run_active or BlockingUi.other_open(get_tree(), self):
		return
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
