extends CanvasLayer
## Esc pause menu (layer 30, processes always), instanced in
## RunSystems.tscn: pauses the tree, frees the mouse, and offers
## Resume / Settings (the shared SettingsPanel swapped over the buttons) /
## Quit to Menu. Esc toggles it closed again, recapturing the mouse.
##
## Pause ownership: this menu only ever unpauses a pause IT started, and
## `_pause_owned` is what makes that an invariant instead of a promise.
## Esc is also ignored while any "ui_blocking" member reports
## is_blocking() — the card picker (including its pre-reveal window) and
## the run-end screen — so it can never steal, or release, their pause. A
## group member that does not expose is_blocking() counts as blocking:
## the contract is only worth having if forgetting it fails SAFE.

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
## True only between the _open() that paused the tree and its _close().
var _pause_owned: bool = false


func _ready() -> void:
	visible = false
	_apply_styles()
	_resume_button.pressed.connect(_close)
	_settings_button.pressed.connect(_on_settings_pressed)
	_extract_button.pressed.connect(_on_extract_pressed)
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
## A member without the method is treated as blocking — assuming the
## opposite would let Esc open this menu over someone else's modal and
## then release a pause we never took.
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
		return  # somebody else already owns the pause; never steal it
	get_tree().paused = true
	_pause_owned = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_root.visible = true
	visible = true
	_resume_button.grab_focus()
	# Entrance: dim fades up, panel scales in. Interruptible — Esc-spam
	# kills the tween and _close snaps the final state anyway.
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
		return  # the pause (and the mouse) belong to whoever took them
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
	# Also fires if the panel is closed during teardown; only restore the
	# buttons while the menu is actually up.
	if visible:
		_root.visible = true
		_resume_button.grab_focus()


## Extract (iteration 38): the run has no clock, so leaving is the
## player's call. Unlike Quit, this ENDS the run properly — RunManager
## grades it (victory past the survival goal), folds the meta save, and
## opens the run-end screen, which then owns the pause.
func _on_extract_pressed() -> void:
	var manager := get_tree().get_first_node_in_group("run_manager")
	if manager == null:
		return
	visible = false
	_kill_open_tween()
	_pause_owned = false  # RunManager re-pauses for the run-end screen
	get_tree().paused = false
	manager.extract_run()


## Abandon the run: nothing folds into the meta save (by design — the run
## counters RunState.reset() drops never reach the ledger). Hiding the
## menu first closes the window where Esc during the fade would run
## _close() and hand the abandoned run a live, unpaused frame.
func _on_quit_pressed() -> void:
	if not ScreenFade.leave_run(CHARACTER_SELECT_SCENE_PATH):
		return  # a cut is already running; nothing was touched
	visible = false
	_kill_open_tween()
	_pause_owned = false


## UiTheme design system: shared panel treatment, spaced headline, teal
## Resume as the primary action.
func _apply_styles() -> void:
	_menu_panel.add_theme_stylebox_override("panel",
			UiTheme.panel(UiTheme.PANEL_BG, UiTheme.BORDER_DIM, 40.0, 26.0))
	UiTheme.style_title(_title_label, 44, UiTheme.TEXT_BRIGHT, 8, 10)
	UiTheme.style_button(_resume_button, UiTheme.ACCENT, true)
	UiTheme.style_button(_settings_button)
	UiTheme.style_button(_extract_button, UiTheme.ACCENT_AMBER)
	UiTheme.style_button(_quit_button)
