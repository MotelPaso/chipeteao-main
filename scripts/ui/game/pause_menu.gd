extends CanvasLayer
## Menú de pausa con Esc (capa 30, procesa siempre), instanciado en
## RunSystems.tscn: pausa el árbol, libera el mouse y ofrece Continuar, Ajustes
## (el SettingsPanel compartido reemplaza a los botones), Extraerse y Salir al
## menú. Esc lo vuelve a cerrar y recaptura el mouse.
##
## Dueño de la pausa: este menú solo quita una pausa que puso ÉL, y
## `_pause_owned` es lo que lo garantiza. Esc también se ignora mientras algún
## miembro de "ui_blocking" responde is_blocking() (el selector de cartas,
## incluida su ventana previa, y la pantalla de fin), así que nunca les roba ni
## les suelta la pausa. Un miembro del grupo sin is_blocking() cuenta como
## bloqueante: si alguien olvida el contrato, falla del lado SEGURO.

const CHARACTER_SELECT_SCENE_PATH := "res://scenes/ui/CharacterSelect.tscn"

@onready var _root: Control = %Root
@onready var _dim: ColorRect = %Dim
@onready var _menu_panel: PanelContainer = %MenuPanel
@onready var _title_label: Label = %TitleLabel
@onready var _resume_button: Button = %ResumeButton
@onready var _settings_button: Button = %SettingsButton
@onready var _extract_button: Button = %ExtractButton
@onready var _quit_button: Button = %QuitButton
@onready var _settings_panel: SettingsPanel = %SettingsPanel

var _open_tween: Tween = null
## true solo entre el _open() que pausó el árbol y su _close().
var _pause_owned: bool = false


func _ready() -> void:
	visible = false
	# Este menú es dueño de la pausa mientras está arriba, y las demás capas que
	# bloquean deciden si sueltan una pausa preguntándole a este grupo: fuera de
	# él, una tienda abierta sobre el menú devolvería el mundo al cerrarse.
	add_to_group("ui_blocking")
	_apply_styles()
	_resume_button.pressed.connect(_close)
	_settings_button.pressed.connect(_on_settings_pressed)
	_extract_button.pressed.connect(_on_extract_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_settings_panel.closed.connect(_on_settings_closed)
	# Indicaciones de botón bajo los botones; siguen al último dispositivo usado.
	_resume_button.get_parent().add_child(InputHints.build([
			["ui_accept", "Elegir"], ["ui_cancel", "Continuar"]]))


## pause_game (Esc / Start) abre y cierra el menú. ui_cancel (B en un control)
## solo lo CIERRA: B es "volver" en todo el juego, pero no lo abre porque en la
## partida B queda libre para jugar.
func _unhandled_input(event: InputEvent) -> void:
	var toggle := event.is_action_pressed("pause_game")
	var back := visible and event.is_action_pressed("ui_cancel")
	if not toggle and not back:
		return
	if _settings_panel.visible:
		return  # el panel maneja Esc / B por su cuenta y vuelve a estos botones
	if visible:
		_close()
		get_viewport().set_input_as_handled()
		return
	if not RunState.run_active or _blocking_ui_open():
		return
	_open()
	get_viewport().set_input_as_handled()


## Contrato "ui_blocking": true mientras este menú es dueño de la pausa. Su
## propio _blocking_ui_open() no se salta a sí mismo, así que esto debe
## contestar con la verdad, y lo hace: con el menú visible, Esc lo cierra antes
## de llegar a esa comprobación.
func is_blocking() -> bool:
	return visible


## ¿Alguna capa es dueña de la pausa (o está por serlo) ahora? Acople flojo: los
## miembros de "ui_blocking" exponen is_blocking() -> bool. Un miembro sin el
## método cuenta como bloqueante: suponer lo contrario dejaría que Esc abra este
## menú sobre el modal de otro y después suelte una pausa que no tomamos.
func _blocking_ui_open() -> bool:
	for node: Node in get_tree().get_nodes_in_group("ui_blocking"):
		if not node.has_method(&"is_blocking"):
			push_warning("ui_blocking member without is_blocking(): %s" % node.name)
			return true
		var blocking: Variant = node.call(&"is_blocking")
		if blocking == true:
			return true
	return false


func _open() -> void:
	if get_tree().paused:
		return  # otro ya es dueño de la pausa; nunca se la roba
	get_tree().paused = true
	_pause_owned = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_root.visible = true
	visible = true
	_resume_button.grab_focus()
	# Entrada: el fondo oscuro sube y el panel crece. Se puede interrumpir:
	# presionar Esc muchas veces mata el tween y _close deja el estado final.
	_kill_open_tween()
	_dim.modulate.a = 0.0
	_menu_panel.pivot_offset = _menu_panel.size * 0.5
	_menu_panel.scale = Vector2(0.94, 0.94)
	_menu_panel.modulate.a = 0.0
	_open_tween = create_tween().set_parallel()
	_open_tween.set_ignore_time_scale(true)
	_open_tween.tween_property(_dim, "modulate:a", 1.0, 0.15)
	_open_tween.tween_property(_menu_panel, "modulate:a", 1.0, 0.14)
	_open_tween.tween_property(_menu_panel, "scale", Vector2.ONE, 0.2) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _close() -> void:
	visible = false
	_kill_open_tween()
	_dim.modulate.a = 1.0
	_menu_panel.scale = Vector2.ONE
	_menu_panel.modulate.a = 1.0
	if not _pause_owned:
		return  # la pausa (y el mouse) son de quien los tomó
	_pause_owned = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _kill_open_tween() -> void:
	if _open_tween != null and _open_tween.is_valid():
		_open_tween.kill()


func _on_settings_pressed() -> void:
	_root.visible = false
	_settings_panel.open()


func _on_settings_closed() -> void:
	# También se dispara si el panel se cierra al desmontar la escena: solo se
	# devuelven los botones si el menú sigue arriba.
	if visible:
		_root.visible = true
		_resume_button.grab_focus()


## Extraerse: la partida no tiene reloj, así que irse es decisión del jugador. A
## diferencia de Salir, esto TERMINA la partida como corresponde: RunManager la
## califica (victoria si pasó la meta de supervivencia), la suma al guardado
## meta y abre la pantalla de fin, que desde ahí es dueña de la pausa.
func _on_extract_pressed() -> void:
	var manager := get_tree().get_first_node_in_group("run_manager")
	if manager == null:
		return
	visible = false
	_kill_open_tween()
	_pause_owned = false  # RunManager vuelve a pausar para la pantalla de fin
	get_tree().paused = false
	manager.extract_run()


## Abandona la partida: nada se suma al guardado meta (a propósito: los
## contadores que RunState.reset() descarta nunca llegan al registro). Ocultar el
## menú primero cierra la ventana en la que un Esc durante el fundido llamaría a
## _close() y le daría a la partida abandonada un frame vivo y sin pausa.
func _on_quit_pressed() -> void:
	if not ScreenFade.leave_run(CHARACTER_SELECT_SCENE_PATH):
		return  # ya hay un corte en curso; no se tocó nada
	visible = false
	_kill_open_tween()
	_pause_owned = false


## Sistema de diseño UiTheme: panel compartido, titular espaciado y Continuar en
## verde azulado como acción principal.
func _apply_styles() -> void:
	_menu_panel.add_theme_stylebox_override("panel",
			UiTheme.panel(UiTheme.PANEL_BG, UiTheme.BORDER_DIM, 40.0, 26.0))
	UiTheme.style_title(_title_label, 44, UiTheme.TEXT_BRIGHT, 8, 10)
	UiTheme.style_button(_resume_button, UiTheme.ACCENT, true)
	UiTheme.style_button(_settings_button)
	UiTheme.style_button(_extract_button, UiTheme.ACCENT_AMBER)
	UiTheme.style_button(_quit_button)
