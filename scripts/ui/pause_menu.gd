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
@onready var _dim: ColorRect = %Dim
@onready var _menu_panel: PanelContainer = %MenuPanel
@onready var _resume_button: Button = %ResumeButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton
@onready var _settings_panel: SettingsPanel = %SettingsPanel

var _open_tween: Tween = null


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
	# Entrance: dim fades up, panel scales in. Interruptible — Esc-spam
	# kills the tween and _close snaps the final state anyway.
	if _open_tween != null and _open_tween.is_valid():
		_open_tween.kill()
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
	if _open_tween != null and _open_tween.is_valid():
		_open_tween.kill()
	_dim.modulate.a = 1.0
	_menu_panel.scale = Vector2.ONE
	_menu_panel.modulate.a = 1.0
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
	ScreenFade.transition(func() -> void:
		get_tree().paused = false
		RunState.reset()
		get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE_PATH))


## UiTheme design system: shared panel treatment, spaced headline, teal
## Resume as the primary action.
func _apply_styles() -> void:
	_menu_panel.add_theme_stylebox_override("panel",
			UiTheme.panel(UiTheme.PANEL_BG, UiTheme.BORDER_DIM, 40.0, 26.0))
	var title := _menu_panel.get_node("VBox/TitleLabel") as Label
	UiTheme.style_title(title, 44, UiTheme.TEXT_BRIGHT, 8, 10)
	UiTheme.style_button(_resume_button, UiTheme.ACCENT, true)
	UiTheme.style_button(_settings_button)
	UiTheme.style_button(_quit_button)
