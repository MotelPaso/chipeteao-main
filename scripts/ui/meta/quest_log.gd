extends MetaScreen
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
## styled progress bars. The chrome, the Esc/Back exit, the staggered
## entrance and the claim payoff (row flashes gold, the shard balance
## counts up and pops) all come from MetaScreen.

const CLAIMED_MODULATE := Color(1.0, 1.0, 1.0, 0.45)

## Three mutually exclusive row states. An enum instead of two booleans:
## _build_row(quest, true, true) used to be a state the types allowed but
## the screen can never be in.
enum RowState { IN_PROGRESS, CLAIMABLE, CLAIMED }


## Claimable first (the dopamine shelf), then in-progress in catalog
## order, then claimed rows dimmed at the bottom.
func _build_rows(list_node: VBoxContainer) -> void:
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
		list_node.add_child(_build_row(quest, RowState.CLAIMABLE))
	for quest: Dictionary in in_progress:
		list_node.add_child(_build_row(quest, RowState.IN_PROGRESS))
	for quest: Dictionary in claimed:
		list_node.add_child(_build_row(quest, RowState.CLAIMED))


## The payoff moment: credit the Shards, then let MetaScreen flash the
## row, count the balance up and resort the list.
func _on_claim_pressed(quest_id: String, row: PanelContainer) -> void:
	var before := SaveData.shards
	if SaveData.claim_quest(quest_id) <= 0:
		return
	payoff(row, before, SaveData.shards, &"gem_pickup")


func _build_row(quest: Dictionary, state: RowState) -> PanelContainer:
	var row := PanelContainer.new()
	var claimable := state == RowState.CLAIMABLE
	row.add_theme_stylebox_override("panel", MetaScreen.card_style(
			UiTheme.ACCENT_AMBER if claimable else UiTheme.BORDER_DIM, claimable))
	if state == RowState.CLAIMED:
		row.modulate = CLAIMED_MODULATE
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 16)
	row.add_child(columns)
	columns.add_child(_build_info(quest, state))
	columns.add_child(_build_side(quest, state, row))
	return row


## Left column: name, description and the progress line.
func _build_info(quest: Dictionary, state: RowState) -> VBoxContainer:
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 3)
	info.add_child(MetaScreen.label(String(quest.display_name), 16, UiTheme.TEXT_BRIGHT))
	info.add_child(MetaScreen.label(String(quest.description), 12, UiTheme.TEXT_DIM))
	info.add_child(_progress_line(SaveData.stat(String(quest.stat)), int(quest.target),
			state != RowState.IN_PROGRESS))
	return info


## Right column: the reward, plus the state's own affordance (Claim
## button / CLAIMED stamp / nothing while it is still in progress).
func _build_side(quest: Dictionary, state: RowState,
		row: PanelContainer) -> VBoxContainer:
	var side := VBoxContainer.new()
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", 4)
	var reward := MetaScreen.label("+%d esquirlas" % int(quest.reward), 14,
			UiTheme.SHARD_BLUE)
	reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	side.add_child(reward)
	if state == RowState.CLAIMABLE:
		var claim := Button.new()
		claim.text = "Reclamar"
		claim.custom_minimum_size = Vector2(110.0, 34.0)
		claim.pressed.connect(_on_claim_pressed.bind(String(quest.id), row))
		UiTheme.style_button(claim, UiTheme.ACCENT_AMBER, true)
		side.add_child(claim)
	elif state == RowState.CLAIMED:
		var done := MetaScreen.label("RECLAMADA", 12, UiTheme.TEXT_FAINT)
		done.add_theme_font_override("font", UiTheme.spaced_font(2))
		done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		side.add_child(done)
	return side


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
	line.add_child(MetaScreen.label("%d/%d" % [mini(current, target), target], 12,
			Color(0.72, 0.74, 0.78)))
	return line
