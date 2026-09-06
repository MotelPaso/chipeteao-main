extends CanvasLayer
## Run-end overlay (GDD 9.6): opened by RunManager.run_ended with the
## finished run's stats from RunState. Layer 20 draws over the upgrade-card
## UI (10) and process_mode ALWAYS keeps the animation and buttons working
## while the tree is paused. Retry reloads the arena (the player's _ready
## recaptures the mouse); Change Character does the same cleanup but
## returns to the character select screen; Quit exits the game.
##
## The four endings (survived or not × died or extracted) are ENDINGS
## rows, not scattered conditionals: copy, title color and which flourish
## plays all travel together, so a fifth ending is one more row.
##
## Look (iteration 29): UiTheme system + a title with impact — defeat
## drops in oversized with a shake, victory lands with a back-ease and a
## looping golden shimmer — then the stats panel, rewards and buttons
## stagger in (~0.8s total, buttons clickable throughout). Leaving goes
## through ScreenFade.leave_run, which owns the cleanup and keeps the tree
## paused across the cut. All tweens ignore time scale (a death can land
## mid hit-stop).

const DEFEAT_TITLE_COLOR := Color(0.9, 0.25, 0.2)
const VICTORY_TITLE_COLOR := Color(0.96, 0.78, 0.3)
const CHARACTER_SELECT_SCENE_PATH := "res://scenes/ui/CharacterSelect.tscn"

## One row per ending. `shake` is the defeat slam, `shimmer` the golden
## breathing loop on a title worth staring at.
const ENDINGS: Dictionary[String, Dictionary] = {
	"death_win": {
		"title": "INCURSIÓN COMPLETA", "subtitle": "¡Sobreviviste!",
		"color": VICTORY_TITLE_COLOR, "shake": false, "shimmer": true,
	},
	"death_loss": {
		"title": "MORISTE", "subtitle": "La horda te alcanzó.",
		"color": DEFEAT_TITLE_COLOR, "shake": true, "shimmer": false,
	},
	"exit_win": {
		"title": "EXTRACCIÓN LOGRADA", "subtitle": "Saliste con vida.",
		"color": VICTORY_TITLE_COLOR, "shake": false, "shimmer": true,
	},
	"exit_loss": {
		"title": "INCURSIÓN ABANDONADA", "subtitle": "Saliste antes de la meta.",
		"color": DEFEAT_TITLE_COLOR, "shake": false, "shimmer": false,
	},
}

@onready var _root: Control = %Root
@onready var _title_label: Label = %TitleLabel
@onready var _subtitle_label: Label = %SubtitleLabel
@onready var _stats_panel: PanelContainer = %StatsPanel
@onready var _time_value: Label = %TimeValue
@onready var _level_value: Label = %LevelValue
@onready var _kills_value: Label = %KillsValue
@onready var _rewards_label: Label = %RewardsLabel
@onready var _buttons_row: Control = %Buttons
@onready var _retry_button: Button = %RetryButton
@onready var _change_character_button: Button = %ChangeCharacterButton
@onready var _quit_button: Button = %QuitButton

var _entrance_tween: Tween = null
var _shimmer_tween: Tween = null


func _ready() -> void:
	visible = false
	add_to_group("ui_blocking")
	_apply_styles()
	# The container re-sorts one frame AFTER the title text and font
	# change, so the size read in _play_entrance is still the old one.
	# Re-centering on every resize keeps the scale-in anchored on the
	# headline instead of sliding it across the screen.
	_title_label.resized.connect(_center_title_pivot)
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
	# Iteration 38: no clock ends the run; victory means the survival goal
	# was met before the end (death or extraction), defeat means it wasn't.
	var ending: Dictionary = ENDINGS[_ending_key(victory, not _party_wiped())]
	UiTheme.style_title(_title_label, 72, ending.color as Color, 8, 14)
	_title_label.text = String(ending.title)
	_subtitle_label.text = String(ending.subtitle)
	var total: int = int(RunState.run_time)
	_time_value.text = "%02d:%02d" % [floori(total / 60.0), total % 60]
	_level_value.text = str(RunState.level)
	_kills_value.text = str(RunState.kills)
	_rewards_label.text = "\n".join(_earning_lines())
	_rewards_label.visible = not _rewards_label.text.is_empty()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	visible = true
	_retry_button.grab_focus()
	_play_entrance(ending)


func _ending_key(victory: bool, extracted: bool) -> String:
	if extracted:
		return "exit_win" if victory else "exit_loss"
	return "death_win" if victory else "death_loss"


## Meta earnings from this run's fold (RunManager ran it just before
## emitting run_ended): any map-tier victory bonus (credited outright)
## plus quests newly completed, whose claimable Shard value waits in the
## quest log.
func _earning_lines() -> Array[String]:
	var lines: Array[String] = []
	if SaveData.last_tier_bonus_shards > 0:
		lines.append("+%d esquirlas — bono por victoria en Grado %d" % [
				SaveData.last_tier_bonus_shards, GameConfig.selected_tier])
	var quest_count := SaveData.last_new_quest_ids.size()
	if quest_count > 0:
		# The whole noun phrase agrees, not just a plural letter: Spanish
		# inflects the participle too ("1 misión completada" / "3 misiones
		# completadas"), so the count decides the phrase, not a suffix.
		var quest_phrase := "misión completada" if quest_count == 1 else "misiones completadas"
		lines.append("+%d esquirlas · %d %s — reclámalas en el registro" % [
				SaveData.last_reward_shards, quest_count, quest_phrase])
	# Daily Hunt scoreboard line (iteration 36).
	if GameConfig.daily_mode:
		lines.append("Puntaje diario: %d — mejor de hoy: %d" % [
				GameConfig.last_daily_score,
				SaveData.stat("daily_best_" + GameConfig.daily_date)])
	return lines


## True when nobody in the party is standing (a death ended the run, not
## an extraction). Downed co-op bodies leave the "player" group, so an
## empty group at run end means a wipe.
func _party_wiped() -> bool:
	for node: Node in get_tree().get_nodes_in_group("player"):
		var health := Health.find_in(node)
		if health != null and not health.is_dead:
			return false
	return true


## Dim in, title lands with impact, then stats/rewards/buttons stagger.
## Runs through the pause (ALWAYS layer) and ignores hit-stop.
func _play_entrance(ending: Dictionary) -> void:
	if _entrance_tween != null and _entrance_tween.is_valid():
		_entrance_tween.kill()
	if _shimmer_tween != null and _shimmer_tween.is_valid():
		_shimmer_tween.kill()
	_root.modulate.a = 0.0
	_center_title_pivot()
	_title_label.scale = Vector2(1.9, 1.9)
	_title_label.modulate = Color(1, 1, 1, 0)
	_title_label.rotation_degrees = 0.0
	var staggered: Array[Control] = [_stats_panel, _rewards_label, _buttons_row]
	for section: Control in staggered:
		section.modulate.a = 0.0
	_entrance_tween = create_tween()
	_entrance_tween.set_ignore_time_scale(true)
	_entrance_tween.tween_property(_root, "modulate:a", 1.0, 0.18)
	# Title: dropped-in scale; the slam shakes, everything else eases.
	_entrance_tween.parallel().tween_property(_title_label, "modulate:a", 1.0, 0.12)
	if bool(ending.shake):
		_entrance_tween.parallel().tween_property(_title_label, "scale", Vector2.ONE, 0.14) \
				.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
		_entrance_tween.tween_property(_title_label, "rotation_degrees", -2.0, 0.04)
		_entrance_tween.tween_property(_title_label, "rotation_degrees", 1.6, 0.06)
		_entrance_tween.tween_property(_title_label, "rotation_degrees", 0.0, 0.06)
	else:
		_entrance_tween.parallel().tween_property(_title_label, "scale", Vector2.ONE, 0.3) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in staggered.size():
		_entrance_tween.parallel().tween_property(staggered[i], "modulate:a", 1.0, 0.2) \
				.set_delay(0.22 + 0.09 * i)
	if bool(ending.shimmer):
		# Golden shine: the title breathes brighter, forever.
		_shimmer_tween = create_tween().set_loops()
		_shimmer_tween.set_ignore_time_scale(true)
		_shimmer_tween.tween_property(_title_label, "modulate",
				Color(1.3, 1.22, 1.0), 0.9).set_delay(0.4) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_shimmer_tween.tween_property(_title_label, "modulate", Color.WHITE, 0.9) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _center_title_pivot() -> void:
	_title_label.pivot_offset = _title_label.size * 0.5


func _on_retry_pressed() -> void:
	ScreenFade.leave_run()


## Retry's cleanup, but back to the select screen for a new loadout (the
## GameConfig selection survives, so the screen reopens on the last pick).
func _on_change_character_pressed() -> void:
	ScreenFade.leave_run(CHARACTER_SELECT_SCENE_PATH)


func _on_quit_pressed() -> void:
	Settings.flush_save()
	Sfx.stop_all_loops()
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
