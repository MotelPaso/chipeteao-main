extends CanvasLayer
## Esc pause menu (layer 30, processes always), instanced in
## RunSystems.tscn: pauses the tree, frees the mouse, and offers
## Resume / Settings (the shared SettingsPanel swapped over the buttons) /
## Quit to Menu. Esc toggles it closed again, recapturing the mouse.
##
## Pause ownership: this menu only ever unpauses a pause IT started. Esc
## is ignored while any "ui_blocking" member reports is_blocking() — the
## card picker (including its pre-reveal window) and the run-end screen —
## so it can never steal, or release, their pause. Both those layers sit
## below run-end (20) styling-wise but this draws above everything at 30.

const CHARACTER_SELECT_SCENE_PATH := "res://scenes/ui/CharacterSelect.tscn"

@onready var _root: Control = %Root
@onready var _menu_panel: PanelContainer = %MenuPanel
@onready var _resume_button: Button = %ResumeButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton
@onready var _settings_panel: SettingsPanel = %SettingsPanel


func _ready() -> void:
	visible = false
	_apply_styles()
	_resume_button.pressed.connect(_close)
	_settings_button.pressed.connect(_on_settings_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_settings_panel.closed.connect(_on_settings_closed)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _settings_panel.visible:
		return  # the panel handles Esc itself and returns to these buttons
	if visible:
		_close()
		get_viewport().set_input_as_handled()
		return
	if not RunState.run_active or _blocking_ui_open():
		return
	_open()
	get_viewport().set_input_as_handled()


## Any layer that owns (or is about to own) the tree pause right now?
## Loose coupling: members of "ui_blocking" expose is_blocking() -> bool.
func _blocking_ui_open() -> bool:
	for node: Node in get_tree().get_nodes_in_group("ui_blocking"):
		if not node.has_method(&"is_blocking"):
			continue
		var blocking: Variant = node.call(&"is_blocking")
		if blocking == true:
			return true
	return false


func _open() -> void:
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_root.visible = true
	visible = true
	_resume_button.grab_focus()


func _close() -> void:
	visible = false
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _on_settings_pressed() -> void:
	_root.visible = false
	_settings_panel.open()


func _on_settings_closed() -> void:
	# Also fires if the panel is closed during teardown; only restore the
	# buttons while the menu is actually up.
	if visible:
		_root.visible = true
		_resume_button.grab_focus()


## Abandon the run: nothing folds into the meta save (by design — see
## SaveData), mirrors the run-end screen's Change Character cleanup.
func _on_quit_pressed() -> void:
	Settings.flush_save()
	Sfx.stop_all_loops()
	get_tree().paused = false
	RunState.reset()
	get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE_PATH)


## Placeholder look built in code, matching the run-end screen.
func _apply_styles() -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.09, 0.1, 0.14, 0.95)
	panel.set_corner_radius_all(10)
	panel.set_border_width_all(2)
	panel.border_color = Color(0.32, 0.34, 0.42)
	panel.content_margin_left = 40.0
	panel.content_margin_right = 40.0
	panel.content_margin_top = 24.0
	panel.content_margin_bottom = 28.0
	_menu_panel.add_theme_stylebox_override("panel", panel)
	for button: Button in [_resume_button, _settings_button, _quit_button]:
		_style_button(button)


func _style_button(button: Button) -> void:
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
		button.add_theme_stylebox_override(state, style)
