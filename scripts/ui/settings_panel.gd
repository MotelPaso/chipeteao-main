class_name SettingsPanel
extends Control
## The ONE settings surface, instanced in two hosts: as the PauseMenu's
## swappable sub-panel (under a paused tree — works because the pause
## layer processes always) and as an overlay on the character select
## screen (gear button). Sliders and the fullscreen toggle write through
## the Settings autoload, which applies live and debounces the SaveData
## write; close() flushes any pending save and emits closed so the host
## can restore its own UI. Esc while visible closes it too. Styling
## matches the run UI: code-built dark StyleBoxFlat.

signal closed

const SLIDER_TRACK_COLOR := Color(0.05, 0.06, 0.09, 0.9)
const SLIDER_FILL_COLOR := Color(0.55, 0.8, 0.92)

@onready var _panel: PanelContainer = %Panel
@onready var _sfx_slider: HSlider = %SfxSlider
@onready var _ambient_slider: HSlider = %AmbientSlider
@onready var _sensitivity_slider: HSlider = %SensitivitySlider
@onready var _sensitivity_value: Label = %SensitivityValue
@onready var _fullscreen_check: CheckButton = %FullscreenCheck
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	visible = false
	_apply_styles()
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	_ambient_slider.value_changed.connect(_on_ambient_changed)
	_sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	_fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	_back_button.pressed.connect(close)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


## Host entry point: sync every control to the persisted values, show.
func open() -> void:
	_refresh_controls()
	visible = true
	_back_button.grab_focus()


func close() -> void:
	if not visible:
		return
	visible = false
	Settings.flush_save()
	closed.emit()


## set_value_no_signal so refreshing never re-applies (or re-saves).
func _refresh_controls() -> void:
	_sfx_slider.set_value_no_signal(SaveData.sfx_volume)
	_ambient_slider.set_value_no_signal(SaveData.ambient_volume)
	_sensitivity_slider.set_value_no_signal(SaveData.mouse_sensitivity)
	_fullscreen_check.set_pressed_no_signal(SaveData.fullscreen)
	_refresh_sensitivity_label(SaveData.mouse_sensitivity)


func _refresh_sensitivity_label(value: float) -> void:
	_sensitivity_value.text = "%.2fx" % value


func _on_sfx_changed(value: float) -> void:
	Settings.set_sfx_volume(value)


func _on_ambient_changed(value: float) -> void:
	Settings.set_ambient_volume(value)


func _on_sensitivity_changed(value: float) -> void:
	Settings.set_mouse_sensitivity(value)
	_refresh_sensitivity_label(value)


func _on_fullscreen_toggled(on: bool) -> void:
	Settings.set_fullscreen(on)


func _apply_styles() -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.09, 0.1, 0.14, 0.97)
	panel.set_corner_radius_all(10)
	panel.set_border_width_all(2)
	panel.border_color = Color(0.32, 0.34, 0.42)
	panel.content_margin_left = 30.0
	panel.content_margin_right = 30.0
	panel.content_margin_top = 22.0
	panel.content_margin_bottom = 22.0
	_panel.add_theme_stylebox_override("panel", panel)
	for slider: HSlider in [_sfx_slider, _ambient_slider, _sensitivity_slider]:
		var track := StyleBoxFlat.new()
		track.bg_color = SLIDER_TRACK_COLOR
		track.set_corner_radius_all(4)
		track.content_margin_top = 3.0
		track.content_margin_bottom = 3.0
		slider.add_theme_stylebox_override("slider", track)
		var fill := StyleBoxFlat.new()
		fill.bg_color = SLIDER_FILL_COLOR
		fill.set_corner_radius_all(4)
		slider.add_theme_stylebox_override("grabber_area", fill)
		slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	var fills := {
		"normal": Color(0.14, 0.15, 0.2, 0.97),
		"hover": Color(0.2, 0.22, 0.28, 0.97),
		"pressed": Color(0.1, 0.11, 0.15, 0.97),
		"focus": Color(0.2, 0.22, 0.28, 0.97),
	}
	for state: String in fills:
		var style := StyleBoxFlat.new()
		style.bg_color = fills[state]
		style.border_color = Color(0.55, 0.58, 0.66)
		style.set_border_width_all(2)
		style.set_corner_radius_all(8)
		_back_button.add_theme_stylebox_override(state, style)
