extends CanvasLayer
## Run-end overlay (GDD 9.6): opened by RunManager.run_ended with defeat
## ("YOU DIED") or victory ("RUN COMPLETE") styling and the finished run's
## stats from RunState. Layer 20 draws over the upgrade-card UI (10) and
## process_mode ALWAYS keeps the fade and buttons working while the tree
## is paused. Retry resets RunState and reloads the scene (the player's
## _ready recaptures the mouse); Quit exits the game.

const DEFEAT_TITLE_COLOR := Color(0.9, 0.25, 0.2)
const VICTORY_TITLE_COLOR := Color(0.96, 0.78, 0.3)
const FADE_DURATION := 0.45

@onready var _root: Control = %Root
@onready var _title_label: Label = %TitleLabel
@onready var _subtitle_label: Label = %SubtitleLabel
@onready var _stats_panel: PanelContainer = %StatsPanel
@onready var _time_value: Label = %TimeValue
@onready var _level_value: Label = %LevelValue
@onready var _kills_value: Label = %KillsValue
@onready var _retry_button: Button = %RetryButton
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	visible = false
	_apply_styles()
	_retry_button.pressed.connect(_on_retry_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)


## Connected to RunManager.run_ended in Main.tscn. The tree is already
## paused when this runs.
func open(victory: bool) -> void:
	if visible:
		return
	_title_label.text = "RUN COMPLETE" if victory else "YOU DIED"
	_title_label.add_theme_color_override("font_color",
			VICTORY_TITLE_COLOR if victory else DEFEAT_TITLE_COLOR)
	_subtitle_label.text = "You survived!" if victory else "The horde got you."
	var total: int = int(RunState.run_time)
	_time_value.text = "%02d:%02d" % [floori(total / 60.0), total % 60]
	_level_value.text = str(RunState.level)
	_kills_value.text = str(RunState.kills)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	visible = true
	_retry_button.grab_focus()
	# Fade the whole overlay in; the tween runs through the pause because
	# it is bound to this ALWAYS-processing layer.
	_root.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_root, "modulate:a", 1.0, FADE_DURATION) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _on_retry_pressed() -> void:
	get_tree().paused = false
	RunState.reset()
	get_tree().reload_current_scene()


func _on_quit_pressed() -> void:
	get_tree().quit()


## Placeholder look built in code (no assets), matching the HUD and card
## UI conventions: dark translucent flat boxes with rounded corners.
func _apply_styles() -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.09, 0.1, 0.14, 0.9)
	panel.set_corner_radius_all(10)
	panel.set_border_width_all(2)
	panel.border_color = Color(0.0, 0.0, 0.0, 0.5)
	panel.content_margin_left = 26.0
	panel.content_margin_right = 26.0
	panel.content_margin_top = 16.0
	panel.content_margin_bottom = 16.0
	_stats_panel.add_theme_stylebox_override("panel", panel)
	for button: Button in [_retry_button, _quit_button]:
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
