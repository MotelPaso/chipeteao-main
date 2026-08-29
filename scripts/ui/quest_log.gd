extends Control
## Quest log screen (GDD 8), opened from the character select's Quests
## button: every QuestCatalog challenge as a scrollable row with name,
## description, an x/y progress bar, and its Shard reward. Completed but
## unclaimed quests float to the top with a glowing border and a Claim
## button — claiming is the manual payoff moment that credits the Shards
## (SaveData persists immediately). Claimed rows sink to the bottom,
## dimmed. Styling matches the run UI: code-built dark StyleBoxFlat.

const CHARACTER_SELECT_SCENE_PATH := "res://scenes/ui/CharacterSelect.tscn"

const SHARD_TEXT_COLOR := Color(0.55, 0.8, 0.92)
const CLAIMABLE_BORDER_COLOR := Color(0.96, 0.78, 0.3)
const ROW_BORDER_COLOR := Color(0.24, 0.26, 0.32)
const CLAIMED_MODULATE := Color(1.0, 1.0, 1.0, 0.45)

@onready var _shards_label: Label = %ShardsLabel
@onready var _quest_list: VBoxContainer = %QuestList
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_style_button(_back_button)
	_back_button.pressed.connect(_on_back_pressed)
	SaveData.shards_changed.connect(func(_balance: int) -> void: _refresh_shards())
	_refresh_shards()
	_rebuild_rows()
	_back_button.grab_focus()


func _refresh_shards() -> void:
	_shards_label.text = "Shards: %d" % SaveData.shards


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE_PATH)


func _on_claim_pressed(quest_id: String) -> void:
	if SaveData.claim_quest(quest_id) > 0:
		_rebuild_rows()  # the claimed row restyles and sinks to the bottom


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
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.12, 0.16, 0.97)
	style.border_color = CLAIMABLE_BORDER_COLOR if claimable else ROW_BORDER_COLOR
	style.set_border_width_all(3 if claimable else 2)
	style.set_corner_radius_all(10)
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
	info.add_child(_label(String(quest.display_name), 16, Color(0.95, 0.96, 0.98)))
	info.add_child(_label(String(quest.description), 12, Color(0.62, 0.65, 0.7)))
	info.add_child(_progress_line(SaveData.stat(String(quest.stat)), int(quest.target)))

	var side := VBoxContainer.new()
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", 4)
	columns.add_child(side)
	var reward := _label("+%d Shards" % int(quest.reward), 14, SHARD_TEXT_COLOR)
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side.add_child(reward)
	if claimable:
		var claim := Button.new()
		claim.text = "Claim"
		claim.custom_minimum_size = Vector2(110.0, 34.0)
		claim.pressed.connect(_on_claim_pressed.bind(String(quest.id)))
		_style_button(claim)
		side.add_child(claim)
	elif claimed:
		var done := _label("CLAIMED", 12, Color(0.55, 0.58, 0.64))
		done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		side.add_child(done)
	return row


## "x/y" bar + counter; the bar clamps so overshoot still reads full.
func _progress_line(current: int, target: int) -> HBoxContainer:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(260.0, 12.0)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.max_value = float(target)
	bar.value = float(mini(current, target))
	bar.show_percentage = false
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.07, 0.08, 0.11)
	background.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", background)
	var fill := StyleBoxFlat.new()
	fill.bg_color = SHARD_TEXT_COLOR.darkened(0.15)
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fill)
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
