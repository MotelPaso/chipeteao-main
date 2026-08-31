extends Control
## Quest log screen (GDD 8), opened from the character select's Quests
## button: every QuestCatalog challenge as a scrollable row with name,
## description, an x/y progress bar, and its Shard reward. Completed but
## unclaimed quests float to the top with a glowing border and a Claim
## button — claiming is the manual payoff moment that credits the Shards
## (SaveData persists immediately). Claimed rows sink to the bottom,
## dimmed.
##
## Look (iteration 29): UiTheme design system — fog backdrop shader,
## spaced amber title, quest rows as cards (claimable ones glow amber),
## styled progress bars, staggered row entrance, and a claim payoff (row
## flashes gold, the shard balance counts up and pops) before the resort.

const CHARACTER_SELECT_SCENE_PATH := "res://scenes/ui/CharacterSelect.tscn"

const CLAIMED_MODULATE := Color(1.0, 1.0, 1.0, 0.45)
const CLAIM_FLASH := Color(1.7, 1.45, 0.85)

@onready var _title_label: Label = %TitleLabel
@onready var _shards_label: Label = %ShardsLabel
@onready var _quest_list: VBoxContainer = %QuestList
@onready var _back_button: Button = %BackButton

var _count_tween: Tween = null


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	UiTheme.style_title(_title_label, 40, UiTheme.ACCENT_AMBER, 8, 10)
	UiTheme.style_badge(_shards_label, UiTheme.SHARD_BLUE,
			UiTheme.PANEL_BG, UiTheme.SHARD_BLUE.darkened(0.45))
	_shards_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiTheme.style_button(_back_button, UiTheme.ACCENT, true)
	_back_button.pressed.connect(_on_back_pressed)
	SaveData.shards_changed.connect(func(_balance: int) -> void: _refresh_shards())
	_refresh_shards()
	_rebuild_rows()
	_play_entrance()
	_back_button.grab_focus()


func _refresh_shards() -> void:
	_shards_label.text = "Shards: %d" % SaveData.shards


## Staggered fade-in of the visible top rows (capped so a long list never
## turns the open into a slideshow).
func _play_entrance() -> void:
	var rows := _quest_list.get_children()
	var tween := create_tween().set_parallel()
	tween.set_ignore_time_scale(true)
	for i in mini(rows.size(), 8):
		var row := rows[i] as Control
		if row == null:
			continue
		var settled := row.modulate
		row.modulate = Color(settled.r, settled.g, settled.b, 0.0)
		tween.tween_property(row, "modulate:a", settled.a, 0.18) \
				.set_delay(0.04 * i)


func _on_back_pressed() -> void:
	ScreenFade.transition(func() -> void:
		get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE_PATH))


## The payoff moment: credit the Shards, flash the row gold, count the
## balance up with a pop, then resort the list.
func _on_claim_pressed(quest_id: String, row: PanelContainer) -> void:
	var before := SaveData.shards
	if SaveData.claim_quest(quest_id) <= 0:
		return
	Sfx.play(&"gem_pickup")
	var after := SaveData.shards
	if _count_tween != null and _count_tween.is_valid():
		_count_tween.kill()
	_count_tween = create_tween()
	_count_tween.set_ignore_time_scale(true)
	_count_tween.tween_method(_set_shard_count, float(before), float(after), 0.4)
	UiTheme.pop(_shards_label, 1.2, 0.3)
	if is_instance_valid(row):
		var flash := create_tween()
		flash.set_ignore_time_scale(true)
		flash.tween_property(row, "modulate", CLAIM_FLASH, 0.08)
		flash.tween_property(row, "modulate", Color.WHITE, 0.2)
		flash.tween_callback(_rebuild_rows)  # the claimed row sinks, dimmed
	else:
		_rebuild_rows()


func _set_shard_count(value: float) -> void:
	_shards_label.text = "Shards: %d" % int(value)


## Claimable first (the dopamine shelf), then in-progress in catalog
## order, then claimed rows dimmed at the bottom.
func _rebuild_rows() -> void:
	for child: Node in _quest_list.get_children():
		child.queue_free()
	var claimable: Array[Dictionary] = []
	var in_progress: Array[Dictionary] = []
	var claimed: Array[Dictionary] = []
	for quest: Dictionary in QuestCatalog.QUEST_LIBRARY:
		var quest_id := String(quest.id)
		if SaveData.is_quest_claimed(quest_id):
			claimed.append(quest)
		elif SaveData.is_quest_completed(quest_id):
			claimable.append(quest)
		else:
			in_progress.append(quest)
	for quest: Dictionary in claimable:
		_quest_list.add_child(_build_row(quest, true, false))
	for quest: Dictionary in in_progress:
		_quest_list.add_child(_build_row(quest, false, false))
	for quest: Dictionary in claimed:
		_quest_list.add_child(_build_row(quest, false, true))


func _build_row(quest: Dictionary, claimable: bool, claimed: bool) -> PanelContainer:
	var row := PanelContainer.new()
	var style := UiTheme.flat(UiTheme.CARD_BG, UiTheme.RADIUS)
	style.border_color = UiTheme.ACCENT_AMBER if claimable else UiTheme.BORDER_DIM
	style.set_border_width_all(2)
	if claimable:
		UiTheme.add_glow(style, UiTheme.ACCENT_AMBER, 8, 0.35)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	row.add_theme_stylebox_override("panel", style)
	if claimed:
		row.modulate = CLAIMED_MODULATE

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	row.add_child(columns)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 3)
	columns.add_child(info)
	info.add_child(_label(String(quest.display_name), 16, UiTheme.TEXT_BRIGHT))
	info.add_child(_label(String(quest.description), 12, UiTheme.TEXT_DIM))
	info.add_child(_progress_line(SaveData.stat(String(quest.stat)), int(quest.target),
			claimable or claimed))

	var side := VBoxContainer.new()
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", 4)
	columns.add_child(side)
	var reward := _label("+%d Shards" % int(quest.reward), 14, UiTheme.SHARD_BLUE)
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side.add_child(reward)
	if claimable:
		var claim := Button.new()
		claim.text = "Claim"
		claim.custom_minimum_size = Vector2(110.0, 34.0)
		claim.pressed.connect(_on_claim_pressed.bind(String(quest.id), row))
		UiTheme.style_button(claim, UiTheme.ACCENT_AMBER, true)
		side.add_child(claim)
	elif claimed:
		var done := _label("CLAIMED", 12, UiTheme.TEXT_FAINT)
		done.add_theme_font_override("font", UiTheme.spaced_font(2))
		done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		side.add_child(done)
	return row


## "x/y" bar + counter; the bar clamps so overshoot still reads full.
## Finished quests turn the fill amber (earned, not just progressing).
func _progress_line(current: int, target: int, complete: bool) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(260.0, 14.0)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.max_value = float(target)
	bar.value = float(mini(current, target))
	bar.show_percentage = false
	UiTheme.style_bar(bar,
			UiTheme.ACCENT_AMBER if complete else UiTheme.SHARD_BLUE.darkened(0.15),
			5, 2)
	line.add_child(bar)
	line.add_child(_label("%d/%d" % [mini(current, target), target], 12,
			Color(0.72, 0.74, 0.78)))
	return line


func _label(label_text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
