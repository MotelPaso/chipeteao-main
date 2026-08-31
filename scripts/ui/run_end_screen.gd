extends CanvasLayer
## Run-end overlay (GDD 9.6): opened by RunManager.run_ended with defeat
## ("YOU DIED") or victory ("RUN COMPLETE") styling and the finished run's
## stats from RunState. Layer 20 draws over the upgrade-card UI (10) and
## process_mode ALWAYS keeps the animation and buttons working while the
## tree is paused. Retry resets RunState and reloads the scene (the
## player's _ready recaptures the mouse); Change Character does the same
## cleanup but returns to the character select screen; Quit exits.
##
## Look (iteration 29): UiTheme system + a title with impact — defeat
## drops in oversized with a shake, victory lands with a back-ease and a
## looping golden shimmer — then the stats panel, rewards and buttons
## stagger in (~0.8s total, buttons clickable throughout). Scene changes
## go through ScreenFade. All tweens ignore time scale (a death can land
## mid hit-stop).

const DEFEAT_TITLE_COLOR := Color(0.9, 0.25, 0.2)
const VICTORY_TITLE_COLOR := Color(0.96, 0.78, 0.3)
const CHARACTER_SELECT_SCENE_PATH := "res://scenes/ui/CharacterSelect.tscn"

@onready var _root: Control = %Root
@onready var _title_label: Label = %TitleLabel
@onready var _subtitle_label: Label = %SubtitleLabel
@onready var _stats_panel: PanelContainer = %StatsPanel
@onready var _time_value: Label = %TimeValue
@onready var _level_value: Label = %LevelValue
@onready var _kills_value: Label = %KillsValue
@onready var _rewards_label: Label = %RewardsLabel
@onready var _retry_button: Button = %RetryButton
@onready var _change_character_button: Button = %ChangeCharacterButton
@onready var _quit_button: Button = %QuitButton

var _entrance_tween: Tween = null
var _shimmer_tween: Tween = null


func _ready() -> void:
	visible = false
	add_to_group("ui_blocking")
	_apply_styles()
	_retry_button.pressed.connect(_on_retry_pressed)
	_change_character_button.pressed.connect(_on_change_character_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)


## PauseMenu contract ("ui_blocking"): the end screen owns the run-end
## pause while it is up, so Esc must not open the pause menu over it.
func is_blocking() -> bool:
	return visible


## Connected to RunManager.run_ended in RunSystems.tscn. The tree is
## already paused when this runs.
func open(victory: bool) -> void:
	if visible:
		return
	UiTheme.style_title(_title_label, 72,
			VICTORY_TITLE_COLOR if victory else DEFEAT_TITLE_COLOR, 8, 14)
	_title_label.text = "RUN COMPLETE" if victory else "YOU DIED"
	_subtitle_label.text = "You survived!" if victory else "The horde got you."
	var total: int = int(RunState.run_time)
	_time_value.text = "%02d:%02d" % [floori(total / 60.0), total % 60]
	_level_value.text = str(RunState.level)
	_kills_value.text = str(RunState.kills)
	# Meta earnings from this run's fold (RunManager ran it just before
	# emitting run_ended): any map-tier victory bonus (credited outright)
	# plus quests newly completed, whose claimable Shard value waits in the
	# quest log.
	var earning_lines: Array[String] = []
	if SaveData.last_tier_bonus_shards > 0:
		earning_lines.append("+%d shards — Tier %d victory bonus" % [
				SaveData.last_tier_bonus_shards, GameConfig.selected_tier])
	var quest_count := SaveData.last_new_quest_ids.size()
	if quest_count > 0:
		earning_lines.append("+%d shards · %d quest%s completed — claim in the quest log" % [
				SaveData.last_reward_shards, quest_count,
				"" if quest_count == 1 else "s"])
	_rewards_label.visible = not earning_lines.is_empty()
	_rewards_label.text = "\n".join(earning_lines)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	visible = true
	_retry_button.grab_focus()
	_play_entrance(victory)


## Dim in, title lands with impact, then stats/rewards/buttons stagger.
## Runs through the pause (ALWAYS layer) and ignores hit-stop.
func _play_entrance(victory: bool) -> void:
	if _entrance_tween != null and _entrance_tween.is_valid():
		_entrance_tween.kill()
	if _shimmer_tween != null and _shimmer_tween.is_valid():
		_shimmer_tween.kill()
	_root.modulate.a = 0.0
	_title_label.pivot_offset = _title_label.size * 0.5
	_title_label.scale = Vector2(1.9, 1.9)
	_title_label.modulate = Color(1, 1, 1, 0)
	_title_label.rotation_degrees = 0.0
	var staggered: Array[Control] = [_stats_panel, _rewards_label,
			_retry_button.get_parent() as Control]
	for section: Control in staggered:
		section.modulate.a = 0.0
	_entrance_tween = create_tween()
	_entrance_tween.set_ignore_time_scale(true)
	_entrance_tween.tween_property(_root, "modulate:a", 1.0, 0.18)
	# Title: dropped-in scale; defeat slams fast and shakes, victory eases.
	_entrance_tween.parallel().tween_property(_title_label, "modulate:a", 1.0, 0.12)
	if victory:
		_entrance_tween.parallel().tween_property(_title_label, "scale", Vector2.ONE, 0.3) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_entrance_tween.parallel().tween_property(_title_label, "scale", Vector2.ONE, 0.14) \
				.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
		_entrance_tween.tween_property(_title_label, "rotation_degrees", -2.0, 0.04)
		_entrance_tween.tween_property(_title_label, "rotation_degrees", 1.6, 0.06)
		_entrance_tween.tween_property(_title_label, "rotation_degrees", 0.0, 0.06)
	for i in staggered.size():
		_entrance_tween.parallel().tween_property(staggered[i], "modulate:a", 1.0, 0.2) \
				.set_delay(0.22 + 0.09 * i)
	if victory:
		# Golden shine: the title breathes brighter, forever.
		_shimmer_tween = create_tween().set_loops()
		_shimmer_tween.set_ignore_time_scale(true)
		_shimmer_tween.tween_property(_title_label, "modulate",
				Color(1.3, 1.22, 1.0), 0.9).set_delay(0.4) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_shimmer_tween.tween_property(_title_label, "modulate", Color.WHITE, 0.9) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _on_retry_pressed() -> void:
	ScreenFade.transition(func() -> void:
		get_tree().paused = false
		RunState.reset()
		get_tree().reload_current_scene())


## Retry's cleanup, but back to the select screen for a new loadout (the
## GameConfig selection survives, so the screen reopens on the last pick).
func _on_change_character_pressed() -> void:
	ScreenFade.transition(func() -> void:
		get_tree().paused = false
		RunState.reset()
		get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE_PATH))


func _on_quit_pressed() -> void:
	get_tree().quit()


## UiTheme design system: headline typography, stat panel with the header
## accent line, teal hero Retry with quiet siblings.
func _apply_styles() -> void:
	_subtitle_label.add_theme_font_override("font", UiTheme.spaced_font(2))
	_stats_panel.add_theme_stylebox_override("panel",
			UiTheme.panel(UiTheme.PANEL_BG, UiTheme.BORDER_DIM, 26.0, 16.0))
	UiTheme.style_button(_retry_button, UiTheme.ACCENT, true)
	UiTheme.style_button(_change_character_button)
	UiTheme.style_button(_quit_button)
