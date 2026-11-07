class_name SettingsPanel
extends Control
## La ÚNICA superficie de ajustes, instanciada en dos anfitriones: como
## subpanel del PauseMenu (bajo un árbol en pausa; funciona porque la capa de
## pausa procesa siempre) y como capa sobre el selector de personaje (botón
## Ajustes). Los sliders y los interruptores escriben a través del autoload
## Settings, que aplica en vivo y agrupa la escritura en SaveData; close()
## vacía el guardado pendiente y emite closed para que el anfitrión restaure
## su propia UI. Esc también lo cierra mientras está visible.

signal closed

## Color del canal de los sliders.
const SLIDER_TRACK_COLOR := Color(0.05, 0.06, 0.09, 0.9)
## El volumen es un porcentaje 0-100 en todo el juego (SettingsApply lo pasa
## a dB); el rango de la sensibilidad es el de SaveData, que también acota el
## valor guardado.
const VOLUME_MIN := 0.0
const VOLUME_MAX := 100.0

@onready var _panel: PanelContainer = %Panel
@onready var _sfx_slider: HSlider = %SfxSlider
@onready var _ambient_slider: HSlider = %AmbientSlider
@onready var _sensitivity_slider: HSlider = %SensitivitySlider
@onready var _sensitivity_value: Label = %SensitivityValue
@onready var _sfx_value: Label = %SfxValue
@onready var _ambient_value: Label = %AmbientValue
@onready var _fullscreen_check: CheckButton = %FullscreenCheck
@onready var _fps_check: CheckButton = %FpsCheck
## Preset gráfico: un botón por índice de SaveData.graphics_quality (Alta,
## Media, Baja, en ese orden), en un ButtonGroup. No es un OptionButton: el
## panel no tiene ningún popup, y una lista desplegable sería una superficie
## más que estilizar y recorrer con control.
@onready var _quality_buttons: Array[Button] = [%QualityHigh as Button,
		%QualityMedium as Button, %QualityLow as Button]
@onready var _back_button: Button = %BackButton

var _open_tween: Tween = null


func _ready() -> void:
	visible = false
	_apply_styles()
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_ambient_slider.value_changed.connect(_on_ambient_changed)
	_sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	_fps_check.toggled.connect(_on_fps_toggled)
	var quality_group := ButtonGroup.new()
	for index in _quality_buttons.size():
		var button := _quality_buttons[index]
		button.button_group = quality_group
		button.toggled.connect(_on_quality_toggled.bind(index))
	_back_button.pressed.connect(close)
	_link_focus()
	# Indicaciones de botones bajo Volver; siguen al último dispositivo usado.
	_back_button.get_parent().add_child(InputHints.build([
			["ui_accept", "Elegir"], ["ui_cancel", "Volver"]]))


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


## Entrada del anfitrión: sincroniza cada control con lo guardado y aparece
## con un pop rápido (interrumpible; close fija el estado final).
func open() -> void:
	_refresh_controls()
	visible = true
	_back_button.grab_focus()
	if _open_tween != null and _open_tween.is_valid():
		_open_tween.kill()
	_panel.pivot_offset = _panel.size * 0.5
	_panel.scale = Vector2(0.94, 0.94)
	_panel.modulate.a = 0.0
	_open_tween = create_tween().set_parallel()
	_open_tween.set_ignore_time_scale(true)
	_open_tween.tween_property(_panel, "modulate:a", 1.0, 0.14)
	_open_tween.tween_property(_panel, "scale", Vector2.ONE, 0.2) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func close() -> void:
	if not visible:
		return
	visible = false
	if _open_tween != null and _open_tween.is_valid():
		_open_tween.kill()
	_panel.scale = Vector2.ONE
	_panel.modulate.a = 1.0
	Settings.flush_save()
	closed.emit()


## set_value_no_signal para que refrescar nunca vuelva a aplicar (ni a
## guardar). La etiqueta lee el slider, no SaveData: Range ajusta lo asignado
## a su paso, y la etiqueta debe decir lo mismo que muestra el agarrador.
func _refresh_controls() -> void:
	_sfx_slider.set_value_no_signal(SaveData.sfx_volume)
	_ambient_slider.set_value_no_signal(SaveData.ambient_volume)
	_sensitivity_slider.set_value_no_signal(SaveData.mouse_sensitivity)
	_fullscreen_check.set_pressed_no_signal(SaveData.fullscreen)
	_fps_check.set_pressed_no_signal(SaveData.show_fps)
	for index in _quality_buttons.size():
		_quality_buttons[index].set_pressed_no_signal(index == SaveData.graphics_quality)
	_refresh_sensitivity_label(_sensitivity_slider.value)
	_refresh_volume_labels()
	_aim_at_chosen_quality()


## Navegación con control y teclado, cableada a mano. Con la búsqueda
## automática de Godot, ui_up desde Volver salta a las cartas del selector
## que quedan DETRÁS de este panel (son enfocables y, medidas borde a borde,
## quedan más cerca que las filas de arriba). Cada fila nombra a sus vecinos
## y la columna da la vuelta, así que el foco nunca sale del panel:
##   Efectos ↕ Ambiente ↕ Sensibilidad ↕ Pantalla completa ↕ FPS
##   ↕ Calidad (Alta ↔ Media ↔ Baja) ↕ Volver ↕ (de vuelta a Efectos)
## Izquierda/derecha sobre un slider mueve su valor (lo hace HSlider); sobre
## un control simple no va a ningún lado en vez de salir del panel.
func _link_focus() -> void:
	var column: Array[Control] = [_sfx_slider, _ambient_slider,
			_sensitivity_slider, _fullscreen_check, _fps_check,
			_quality_buttons[0], _back_button]
	for i in column.size():
		var here := column[i]
		var above := column[(i - 1 + column.size()) % column.size()]
		var below := column[(i + 1) % column.size()]
		here.focus_neighbor_top = here.get_path_to(above)
		here.focus_neighbor_bottom = here.get_path_to(below)
		here.focus_previous = here.get_path_to(above)
		here.focus_next = here.get_path_to(below)
		here.focus_neighbor_left = here.get_path_to(here)
		here.focus_neighbor_right = here.get_path_to(here)
	# La fila de calidad: todos sus botones comparten las filas de arriba y de
	# abajo, e izquierda/derecha recorren la fila sin salirse de ella.
	for i in _quality_buttons.size():
		var button := _quality_buttons[i]
		button.focus_neighbor_top = button.get_path_to(_fps_check)
		button.focus_neighbor_bottom = button.get_path_to(_back_button)
		button.focus_neighbor_left = button.get_path_to(_quality_buttons[maxi(i - 1, 0)])
		button.focus_neighbor_right = button.get_path_to(
				_quality_buttons[mini(i + 1, _quality_buttons.size() - 1)])
	_aim_at_chosen_quality()


## Entrar a la fila de calidad desde arriba o abajo cae en el preset que
## está ENCENDIDO, no siempre en Alta.
func _aim_at_chosen_quality() -> void:
	var chosen := _quality_buttons[0]
	for button in _quality_buttons:
		if button.button_pressed:
			chosen = button
	_fps_check.focus_neighbor_bottom = _fps_check.get_path_to(chosen)
	_back_button.focus_neighbor_top = _back_button.get_path_to(chosen)


func _refresh_sensitivity_label(value: float) -> void:
	_sensitivity_value.text = "%.2fx" % value


func _on_sfx_changed(value: float) -> void:
	Settings.set_sfx_volume(value)
	_refresh_volume_labels()


func _on_ambient_changed(value: float) -> void:
	Settings.set_ambient_volume(value)
	_refresh_volume_labels()


## Los volúmenes se leen como porcentaje junto a su slider, igual que el
## multiplicador de sensibilidad: las tres filas terminan en un número.
func _refresh_volume_labels() -> void:
	_sfx_value.text = "%d%%" % roundi(_sfx_slider.value)
	_ambient_value.text = "%d%%" % roundi(_ambient_slider.value)


func _on_sensitivity_changed(value: float) -> void:
	Settings.set_mouse_sensitivity(value)
	_refresh_sensitivity_label(value)


func _on_fullscreen_toggled(on: bool) -> void:
	Settings.set_fullscreen(on)


func _on_fps_toggled(on: bool) -> void:
	Settings.set_show_fps(on)


## Un ButtonGroup también APAGA la opción anterior; solo el botón que se
## encendió trae una decisión.
func _on_quality_toggled(on: bool, index: int) -> void:
	if on:
		Settings.set_graphics_quality(index)
		_aim_at_chosen_quality()


## Los límites de los sliders salen del código que acota los valores
## guardados, no de la escena: dos copias de 0.3-2.0 se separan el día que
## una cambia.
func _apply_ranges() -> void:
	for slider: HSlider in [_sfx_slider, _ambient_slider]:
		slider.min_value = VOLUME_MIN
		slider.max_value = VOLUME_MAX
	_sensitivity_slider.min_value = SaveData.MIN_MOUSE_SENSITIVITY
	_sensitivity_slider.max_value = SaveData.MAX_MOUSE_SENSITIVITY


## Sistema de diseño UiTheme: panel compartido, sliders con canal lleno y
## agarrador redondo turquesa, interruptores de píldora y botón Volver
## turquesa. El título, las etiquetas y los encabezados de sección (SONIDO /
## CONTROLES / PANTALLA) tienen su aspecto en la escena.
func _apply_styles() -> void:
	_apply_ranges()
	_panel.add_theme_stylebox_override("panel",
			UiTheme.panel(UiTheme.PANEL_BG, UiTheme.BORDER_DIM, 32.0, 24.0))
	var grabber := UiTheme.grabber_icon(UiTheme.ACCENT)
	var grabber_hi := UiTheme.grabber_icon(UiTheme.ACCENT.lightened(0.25))
	for slider: HSlider in [_sfx_slider, _ambient_slider, _sensitivity_slider]:
		var track := UiTheme.flat(SLIDER_TRACK_COLOR, 4)
		track.set_border_width_all(1)
		track.border_color = Color(0.0, 0.0, 0.0, 0.6)
		track.content_margin_top = 4.0
		track.content_margin_bottom = 4.0
		slider.add_theme_stylebox_override("slider", track)
		var fill := UiTheme.flat(UiTheme.ACCENT.darkened(0.15), 4)
		fill.border_width_right = 2
		fill.border_color = UiTheme.ACCENT.lightened(0.3)
		slider.add_theme_stylebox_override("grabber_area", fill)
		slider.add_theme_stylebox_override("grabber_area_highlight", fill)
		slider.add_theme_icon_override("grabber", grabber)
		slider.add_theme_icon_override("grabber_highlight", grabber_hi)
		slider.add_theme_icon_override("grabber_disabled", grabber)
	for check: CheckButton in [_fullscreen_check, _fps_check]:
		UiTheme.style_toggle(check)
	for button: Button in _quality_buttons:
		UiTheme.style_button(button, UiTheme.ACCENT)
		var chosen := button.get_theme_stylebox("pressed").duplicate() as StyleBoxFlat
		chosen.border_color = UiTheme.ACCENT
		button.add_theme_stylebox_override("hover_pressed", chosen)
		button.add_theme_color_override("font_hover_pressed_color", UiTheme.TEXT_BRIGHT)
	UiTheme.style_button(_back_button, UiTheme.ACCENT, true)
