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
## Volume is a 0-100 percentage everywhere (SettingsApply converts it to
## dB); sensitivity's range is SaveData's, which is also what clamps the
## stored value.
const VOLUME_MIN := 0.0
const VOLUME_MAX := 100.0

@onready var _panel: PanelContainer = %Panel
@onready var _title_label: Label = %TitleLabel
@onready var _sfx_slider: HSlider = %SfxSlider
@onready var _ambient_slider: HSlider = %AmbientSlider
@onready var _sensitivity_slider: HSlider = %SensitivitySlider
@onready var _sensitivity_value: Label = %SensitivityValue
@onready var _fullscreen_check: CheckButton = %FullscreenCheck
@onready var _back_button: Button = %BackButton

var _open_tween: Tween = null


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


## Host entry point: sync every control to the persisted values, show
## with a quick pop-in (interruptible; close snaps the final state).
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


## set_value_no_signal so refreshing never re-applies (or re-saves). The
## label reads the slider back, not SaveData: Range snaps the assignment
## to its step, and a grabber sitting on 0.35 under a label that reads
## "0.37x" is a bug report waiting to happen.
func _refresh_controls() -> void:
	_sfx_slider.set_value_no_signal(SaveData.sfx_volume)
	_ambient_slider.set_value_no_signal(SaveData.ambient_volume)
	_sensitivity_slider.set_value_no_signal(SaveData.mouse_sensitivity)
	_fullscreen_check.set_pressed_no_signal(SaveData.fullscreen)
	_refresh_sensitivity_label(_sensitivity_slider.value)


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


## Slider bounds come from the code that clamps the stored values, not
## from the scene: two copies of 0.3-2.0 drift the day one of them moves.
func _apply_ranges() -> void:
	for slider: HSlider in [_sfx_slider, _ambient_slider]:
		slider.min_value = VOLUME_MIN
		slider.max_value = VOLUME_MAX
	_sensitivity_slider.min_value = SaveData.MIN_MOUSE_SENSITIVITY
	_sensitivity_slider.max_value = SaveData.MAX_MOUSE_SENSITIVITY


## UiTheme design system: shared panel + headline, filled-track sliders
## with a round teal grabber, teal Back button.
func _apply_styles() -> void:
	_apply_ranges()
	_panel.add_theme_stylebox_override("panel",
			UiTheme.panel(UiTheme.PANEL_BG, UiTheme.BORDER_DIM, 32.0, 24.0))
	UiTheme.style_title(_title_label, 30, Color(0.96, 0.93, 0.82), 6, 8)
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
	_sensitivity_value.add_theme_color_override("font_color", UiTheme.ACCENT)
	UiTheme.style_button(_back_button, UiTheme.ACCENT, true)
