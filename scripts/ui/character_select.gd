extends Control
## Character-and-map select screen (GDD 5/7), the game's entry scene:
## pick a raider and a hunting ground, then Start Run loads the selected
## map's arena (which recaptures the mouse itself). Character cards are
## built from CharacterCatalog and the map row from MapCatalog at
## runtime, so new content is one catalog row each; both picks land in
## the GameConfig autoload.
##
## Meta-progression (GDD 8): SaveData gates the roster and the maps.
## Locked characters show grayed with a lock glyph and their Shard price;
## clicking one with enough Shards flips the card into an inline "Unlock
## for N? [Yes]" confirm (second click cancels), while a short balance
## earns a red-flash shake instead. Locked maps show grayed with the
## catalog's unlock hint and reject clicks the same way (map unlocks are
## earned, never bought). Under the map row, a T1/T2/T3 tier picker for
## the selected map: tiers are win-gated per map (SaveData
## .is_tier_unlocked), locked picks gray out and explain the gate, and the
## last pick per map persists (SaveData.tier_choice). The Shard balance
## sits top-right and the Quests button opens the quest log.
##
## Look (iteration 29): everything styles through UiTheme — animated fog
## backdrop shader, letter-spaced pulsing title, cards with tinted glow
## selection states (selected lifts, others dim), segmented map/tier
## controls, hero Start CTA, staggered entrance, and ScreenFade around
## every scene change.

const QUEST_LOG_SCENE_PATH := "res://scenes/ui/QuestLog.tscn"

# Sized so the map row plus two grid rows of four cards fit the default
# 1152x648 window alongside the title and start button.
const CARD_SIZE := Vector2(172, 196)
const MAP_CARD_SIZE := Vector2(252, 54)
const REJECT_FLASH_COLOR := Color(1.0, 0.42, 0.42)
const TIER_BUTTON_SIZE := Vector2(64, 36)
## Non-selected cards sit slightly dimmed so the pick reads at a glance.
const UNSELECTED_DIM := Color(0.8, 0.82, 0.86)

@onready var _title_label: Label = %TitleLabel
@onready var _subtitle_label: Label = %SubtitleLabel
@onready var _cards_grid: GridContainer = %CardsGrid
@onready var _map_row: HBoxContainer = %MapRow
@onready var _tier_row: HBoxContainer = %TierRow
@onready var _tier_summary_label: Label = %TierSummaryLabel
@onready var _button_row: HBoxContainer = %ButtonRow
@onready var _start_button: Button = %StartButton
@onready var _quests_button: Button = %QuestsButton
@onready var _settings_button: Button = %SettingsButton
@onready var _settings_panel: SettingsPanel = %SettingsPanel
@onready var _shards_label: Label = %ShardsLabel
@onready var _version_label: Label = %VersionLabel

## Card button per playable character id, for selection restyling.
var _cards_by_id: Dictionary[String, Button] = {}
## Card button per catalog map id, for selection restyling.
var _map_cards_by_id: Dictionary[String, Button] = {}
## Tier picker buttons, index 0 = tier 1; restyled per selected map.
var _tier_buttons: Array[Button] = []
## Character id whose card currently shows the inline unlock confirm.
var _pending_unlock_id: String = ""
var _title_tween: Tween = null
var _entrance_tween: Tween = null


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	for map_row: Dictionary in MapCatalog.MAP_LIBRARY:
		var map_card := Button.new()
		map_card.custom_minimum_size = MAP_CARD_SIZE
		map_card.pressed.connect(_on_map_card_pressed.bind(String(map_row.id)))
		UiTheme.attach_motion(map_card, 1.03)
		_map_row.add_child(map_card)
		_map_cards_by_id[String(map_row.id)] = map_card
	for tier in range(1, MapCatalog.TIER_COUNT + 1):
		var tier_button := Button.new()
		tier_button.custom_minimum_size = TIER_BUTTON_SIZE
		tier_button.text = "T%d" % tier
		tier_button.add_theme_font_size_override("font_size", 15)
		tier_button.pressed.connect(_on_tier_pressed.bind(tier))
		UiTheme.attach_motion(tier_button, 1.06)
		_tier_row.add_child(tier_button)
		_tier_buttons.append(tier_button)
	for character: Dictionary in CharacterCatalog.CHARACTER_LIBRARY:
		var card := Button.new()
		card.custom_minimum_size = CARD_SIZE
		card.pressed.connect(_on_card_pressed.bind(String(character.id)))
		UiTheme.attach_motion(card, 1.03)
		_cards_grid.add_child(card)
		_cards_by_id[String(character.id)] = card
	_apply_chrome()
	UiTheme.style_button(_start_button, UiTheme.ACCENT, true)
	UiTheme.attach_motion(_start_button, 1.05, 0.93)
	UiTheme.style_button(_quests_button)
	UiTheme.style_button(_settings_button)
	_start_button.pressed.connect(_on_start_pressed)
	_quests_button.pressed.connect(_on_quests_pressed)
	# The shared SettingsPanel (same scene the pause menu embeds) overlays
	# this whole screen; on close, focus returns to Start.
	_settings_button.pressed.connect(_settings_panel.open)
	_settings_panel.closed.connect(func() -> void: _start_button.grab_focus())
	SaveData.shards_changed.connect(func(_balance: int) -> void: _refresh_shards())
	_refresh_shards()
	_version_label.text = "v%s" % String(
			ProjectSettings.get_setting("application/config/version", "0.0.0"))
	# Reopening mid-session keeps the previous picks; unknown ids fall
	# back, and a locked id (stale selection) falls back to the default —
	# so Change Character after a run keeps the map that was just played.
	var remembered := String(
			CharacterCatalog.by_id_or_default(GameConfig.selected_character_id).id)
	if not SaveData.is_unlocked(remembered):
		remembered = CharacterCatalog.DEFAULT_ID
	_select(remembered)
	var remembered_map := String(MapCatalog.by_id_or_default(GameConfig.selected_map_id).id)
	if not SaveData.is_map_unlocked(remembered_map):
		remembered_map = MapCatalog.DEFAULT_ID
	_select_map(remembered_map)
	_start_button.grab_focus()
	_play_entrance()


## Title/subtitle/shard typography plus the slow title glow pulse (this
## screen is the game's face; the motion says "alive", never "busy").
func _apply_chrome() -> void:
	UiTheme.style_title(_title_label, 52, UiTheme.ACCENT_AMBER, 10, 12)
	_subtitle_label.add_theme_font_override("font", UiTheme.spaced_font(2))
	_subtitle_label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	UiTheme.style_badge(_shards_label, UiTheme.SHARD_BLUE,
			UiTheme.PANEL_BG, UiTheme.SHARD_BLUE.darkened(0.45))
	_tier_summary_label.add_theme_font_override("font", UiTheme.spaced_font(1))
	if _title_tween != null and _title_tween.is_valid():
		_title_tween.kill()
	_title_tween = create_tween().set_loops()
	_title_tween.tween_property(_title_label, "modulate",
			Color(1.14, 1.1, 1.0), 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_title_tween.tween_property(_title_label, "modulate",
			Color.WHITE, 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Staggered section fade/scale-in on open (~0.4s total). Sections tween
## their own modulate, cards tween theirs separately, so the selection
## restyle never fights the entrance.
func _play_entrance() -> void:
	if _entrance_tween != null and _entrance_tween.is_valid():
		_entrance_tween.kill()
	var sections: Array[Control] = [_title_label, _subtitle_label, _map_row,
			_tier_row, _cards_grid, _button_row]
	# Hide instantly, but wait a frame for the first layout pass so pivots
	# center on real sizes before the scale-in.
	for section: Control in sections:
		section.modulate.a = 0.0
	await get_tree().process_frame
	_entrance_tween = create_tween().set_parallel()
	_entrance_tween.set_ignore_time_scale(true)
	for i in sections.size():
		var section := sections[i]
		section.pivot_offset = section.size * 0.5
		section.scale = Vector2(0.96, 0.96)
		var delay := 0.05 * i
		_entrance_tween.tween_property(section, "modulate:a", 1.0, 0.22) \
				.set_delay(delay)
		_entrance_tween.tween_property(section, "scale", Vector2.ONE, 0.26) \
				.set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _refresh_shards() -> void:
	_shards_label.text = "Shards: %d" % SaveData.shards
	UiTheme.pop(_shards_label, 1.12, 0.22)


## Selection is only ever offered for unlocked characters (_on_card_pressed
## routes locked clicks into the unlock flow instead).
func _select(character_id: String) -> void:
	GameConfig.selected_character_id = character_id
	_refresh_all_cards()
	var picked := CharacterCatalog.by_id(character_id)
	_start_button.text = "Start Run — %s" % String(picked.display_name)


func _on_card_pressed(character_id: String) -> void:
	if SaveData.is_unlocked(character_id):
		_cancel_pending_unlock()
		_select(character_id)
		return
	if _pending_unlock_id == character_id:
		# Second click on the confirm card backs out.
		_cancel_pending_unlock()
		_refresh_all_cards()
		return
	var cost := int(CharacterCatalog.by_id(character_id).get("unlock_cost", 0))
	if SaveData.can_afford(cost):
		_pending_unlock_id = character_id
		_refresh_all_cards()
	else:
		_reject_card(_cards_by_id[character_id])


func _on_unlock_confirmed(character_id: String) -> void:
	_pending_unlock_id = ""
	if SaveData.purchase_character(character_id):
		Sfx.play(&"chest_open")  # unlock fanfare: reuse the payoff sound
		_select(character_id)  # also refreshes every card
	else:
		_refresh_all_cards()


func _cancel_pending_unlock() -> void:
	_pending_unlock_id = ""


func _on_start_pressed() -> void:
	var map_row := MapCatalog.by_id_or_default(GameConfig.selected_map_id)
	var scene_path := String(map_row.scene_path)
	ScreenFade.transition(func() -> void:
		# RunState keeps ticking while this unpaused screen is up, so a
		# fresh run starts from a clean slate (mirrors the run-end Retry).
		RunState.reset()
		get_tree().change_scene_to_file(scene_path))


func _on_quests_pressed() -> void:
	ScreenFade.transition(func() -> void:
		get_tree().change_scene_to_file(QUEST_LOG_SCENE_PATH))


## --- Map row (GDD 7: pick the biome; victory-gated unlocks) -------------

func _select_map(map_id: String) -> void:
	GameConfig.selected_map_id = map_id
	# Restore this map's remembered tier pick; a tier the map hasn't
	# earned yet (or a legacy save with none) drops to the baseline.
	var remembered_tier := SaveData.tier_choice(map_id)
	if not SaveData.is_tier_unlocked(map_id, remembered_tier):
		remembered_tier = 1
	GameConfig.selected_tier = remembered_tier
	_refresh_map_cards()
	_refresh_tier_row()


func _on_map_card_pressed(map_id: String) -> void:
	if SaveData.is_map_unlocked(map_id):
		_select_map(map_id)
	else:
		_reject_card(_map_cards_by_id[map_id])


## --- Tier picker (win tier N on a map to open its tier N+1) -------------

func _on_tier_pressed(tier: int) -> void:
	var map_id := GameConfig.selected_map_id
	if SaveData.is_tier_unlocked(map_id, tier):
		GameConfig.selected_tier = tier
		SaveData.set_tier_choice(map_id, tier)
		_refresh_tier_row()
		return
	_reject_card(_tier_buttons[tier - 1])
	# Locked feedback: the summary line explains the gate until the next
	# refresh repaints it with the selected tier's summary.
	_tier_summary_label.text = "Tier %d locked — win Tier %d on %s" % [
			tier, tier - 1, String(MapCatalog.by_id_or_default(map_id).display_name)]
	_tier_summary_label.add_theme_color_override("font_color", UiTheme.TEXT_FAINT)


## Segmented-control look: the selected tier is an amber-filled segment,
## unlocked ones are quiet outlines, locked ones sink into the ground.
func _refresh_tier_row() -> void:
	var map_id := GameConfig.selected_map_id
	for i in _tier_buttons.size():
		var tier := i + 1
		var tier_button := _tier_buttons[i]
		if not SaveData.is_tier_unlocked(map_id, tier):
			tier_button.tooltip_text = "Win Tier %d here to unlock" % (tier - 1)
			tier_button.add_theme_color_override("font_color", UiTheme.TEXT_FAINT)
			_style_card(tier_button, UiTheme.BORDER_LOCKED, 2)
			continue
		tier_button.tooltip_text = ""
		var selected := tier == GameConfig.selected_tier
		tier_button.add_theme_color_override("font_color",
				UiTheme.ACCENT_AMBER if selected else Color(0.85, 0.87, 0.9))
		_style_card(tier_button,
				UiTheme.ACCENT_AMBER if selected else UiTheme.BORDER_DIM,
				3 if selected else 2, UiTheme.ACCENT_AMBER if selected else Color(0, 0, 0, 0))
	_tier_summary_label.text = MapCatalog.tier_summary(map_id, GameConfig.selected_tier)
	_tier_summary_label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)


func _refresh_map_cards() -> void:
	for id: String in _map_cards_by_id:
		_populate_map_card(_map_cards_by_id[id], MapCatalog.by_id(id))


func _populate_map_card(card: Button, map_row: Dictionary) -> void:
	for child: Node in card.get_children():
		child.queue_free()
	var map_id := String(map_row.id)
	var box := _map_card_box(card)
	if not SaveData.is_map_unlocked(map_id):
		box.add_child(_label(String(map_row.display_name), 16, UiTheme.TEXT_FAINT))
		box.add_child(_label(String(map_row.locked_hint), 10,
				UiTheme.SHARD_BLUE.darkened(0.2)))
		_style_card(card, UiTheme.BORDER_LOCKED, 2)
		_settle_card(card, false)
		return
	box.add_child(_label(String(map_row.display_name), 16, UiTheme.TEXT_BRIGHT))
	box.add_child(_palette_strip(map_row.palette as Array))
	var selected := map_id == GameConfig.selected_map_id
	var accent := (map_row.palette as Array)[0] as Color
	_style_card(card, accent if selected else UiTheme.BORDER_DIM,
			3 if selected else 2, accent if selected else Color(0, 0, 0, 0))
	_settle_card(card, selected)


## Compact full-rect VBox for the short map cards (the character _card_box
## margins are too deep for a 54px card).
func _map_card_box(card: Button) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 10.0
	box.offset_top = 6.0
	box.offset_right = -10.0
	box.offset_bottom = -6.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	return box


## Tiny biome mood strip: the catalog palette as flat color chips.
func _palette_strip(palette: Array) -> HBoxContainer:
	var strip := HBoxContainer.new()
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	strip.add_theme_constant_override("separation", 4)
	for entry: Variant in palette:
		var chip := Panel.new()
		chip.custom_minimum_size = Vector2(34.0, 10.0)
		chip.add_theme_stylebox_override("panel", UiTheme.flat(entry as Color, 3))
		strip.add_child(chip)
	return strip


## --- Card content (rebuilt whenever lock/selection state changes) ------

func _refresh_all_cards() -> void:
	for id: String in _cards_by_id:
		_populate_card(_cards_by_id[id], CharacterCatalog.by_id(id))


func _populate_card(card: Button, character: Dictionary) -> void:
	for child: Node in card.get_children():
		child.queue_free()
	var character_id := String(character.id)
	if not SaveData.is_unlocked(character_id):
		if _pending_unlock_id == character_id:
			_populate_confirm_card(card, character)
		else:
			_populate_locked_card(card, character)
		_settle_card(card, _pending_unlock_id == character_id)
		return
	var box := _card_box(card)
	box.add_child(_portrait_swatch(Color(character.tint)))
	box.add_child(_label(String(character.display_name), 20, UiTheme.TEXT_BRIGHT))
	box.add_child(_label(String(character.weapon_display_name), 12, UiTheme.TEXT_DIM))
	var passive := _label(String(character.passive_description), 12, Color(0.85, 0.78, 0.5))
	passive.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(passive)
	var blurb := _label(String(character.blurb), 11, Color(0.6, 0.62, 0.68))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# The passive line takes priority in the compact grid card; the flavor
	# blurb takes the leftover space and trims rather than overflowing.
	blurb.max_lines_visible = 2
	blurb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	blurb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	blurb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(blurb)
	var selected := character_id == GameConfig.selected_character_id
	var tint := Color(character.tint)
	_style_card(card, tint if selected else UiTheme.BORDER_DIM,
			3 if selected else 2, tint if selected else Color(0, 0, 0, 0))
	_settle_card(card, selected)


## Selection motion: the picked card lifts slightly and brightens while
## the rest dim a step. Tween per card, parked in meta so rapid clicking
## never stacks animations.
func _settle_card(card: Button, selected: bool) -> void:
	card.pivot_offset = card.size * 0.5
	UiTheme.kill_meta_tween(card, &"ui_settle_tween")
	var tween := card.create_tween()
	tween.set_ignore_time_scale(true)
	tween.set_parallel()
	tween.tween_property(card, "scale",
			Vector2.ONE * (1.035 if selected else 1.0), 0.16) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "modulate",
			Color.WHITE if selected else UNSELECTED_DIM, 0.16)
	card.set_meta(&"ui_settle_tween", tween)


## Grayed roster slot: lock glyph in place of the portrait, dimmed
## identity lines, and the Shard price as the call to action.
func _populate_locked_card(card: Button, character: Dictionary) -> void:
	var box := _card_box(card)
	box.add_child(_lock_glyph())
	box.add_child(_label(String(character.display_name), 20, UiTheme.TEXT_FAINT))
	box.add_child(_label(String(character.weapon_display_name), 12,
			UiTheme.TEXT_FAINT.darkened(0.15)))
	var passive := _label(String(character.passive_description), 12,
			UiTheme.TEXT_FAINT.darkened(0.15))
	passive.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(passive)
	# Price chip: a small shard-blue pill so the cost reads as a button.
	var cost := _label("%d Shards" % int(character.get("unlock_cost", 0)),
			13, UiTheme.SHARD_BLUE)
	cost.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiTheme.style_badge(cost, UiTheme.SHARD_BLUE,
			Color(0.07, 0.1, 0.14, 0.9), UiTheme.SHARD_BLUE.darkened(0.5))
	var hint_text := String(character.get("unlock_hint", ""))
	if hint_text.is_empty():
		cost.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(cost)
	else:
		# Boss-unlockable characters advertise both paths: the Shard price
		# and the catalog's vague clue toward the hidden-boss unlock.
		box.add_child(cost)
		var hint := _label("— or %s" % hint_text, 10, UiTheme.SHARD_BLUE.darkened(0.25))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.size_flags_vertical = Control.SIZE_EXPAND_FILL
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_child(hint)
	_style_card(card, UiTheme.BORDER_LOCKED, 2)


## The inline purchase prompt the locked card flips into when affordable.
func _populate_confirm_card(card: Button, character: Dictionary) -> void:
	var box := _card_box(card)
	box.add_child(_portrait_swatch(Color(character.tint)))
	box.add_child(_label(String(character.display_name), 20, UiTheme.TEXT_BRIGHT))
	var ask := _label("Unlock for %d Shards?" % int(character.get("unlock_cost", 0)),
			13, UiTheme.SHARD_BLUE)
	ask.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(ask)
	var yes := Button.new()
	yes.text = "Yes"
	yes.custom_minimum_size = Vector2(0.0, 36.0)
	yes.pressed.connect(_on_unlock_confirmed.bind(String(character.id)))
	UiTheme.style_button(yes, UiTheme.SHARD_BLUE, true)
	box.add_child(yes)
	var hint := _label("click card to cancel", 10, UiTheme.TEXT_FAINT)
	hint.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(hint)
	_style_card(card, UiTheme.SHARD_BLUE, 3, UiTheme.SHARD_BLUE)


## Can't-afford feedback: quick red flash plus a rotation wobble (rotation
## doesn't fight the GridContainer's layout the way position would).
func _reject_card(card: Button) -> void:
	card.pivot_offset = card.size / 2.0
	var tween := create_tween()
	tween.set_ignore_time_scale(true)
	tween.tween_property(card, "modulate", REJECT_FLASH_COLOR, 0.06)
	tween.parallel().tween_property(card, "rotation_degrees", -4.0, 0.05)
	tween.tween_property(card, "rotation_degrees", 4.0, 0.08)
	tween.tween_property(card, "rotation_degrees", -2.0, 0.07)
	tween.tween_property(card, "rotation_degrees", 0.0, 0.06)
	tween.parallel().tween_property(card, "modulate", Color.WHITE, 0.18)


## Full-rect content VBox inside a card button (UpgradeCardUI convention).
func _card_box(card: Button) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 12.0
	box.offset_top = 12.0
	box.offset_right = -12.0
	box.offset_bottom = -12.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)
	return box


## Tinted stand-in for character art in the body color.
func _portrait_swatch(tint: Color) -> Panel:
	var swatch := Panel.new()
	swatch.custom_minimum_size = Vector2(0.0, 40.0)
	var style := UiTheme.flat(tint, 8)
	style.border_color = tint.lightened(0.25)
	style.set_border_width_all(2)
	UiTheme.add_glow(style, tint, 5, 0.3)
	swatch.add_theme_stylebox_override("panel", style)
	return swatch


## Small code-drawn padlock (shackle arch over a body box) standing where
## the portrait swatch would be, so "locked" reads without any glyph font.
func _lock_glyph() -> Control:
	var glyph := Control.new()
	glyph.custom_minimum_size = Vector2(0.0, 40.0)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shackle := Panel.new()
	shackle.set_anchors_preset(Control.PRESET_CENTER_TOP)
	shackle.offset_left = -8.0
	shackle.offset_right = 8.0
	shackle.offset_top = 4.0
	shackle.offset_bottom = 20.0
	var arch := StyleBoxFlat.new()
	arch.draw_center = false
	arch.border_color = UiTheme.TEXT_FAINT
	arch.set_border_width_all(3)
	arch.corner_radius_top_left = 8
	arch.corner_radius_top_right = 8
	shackle.add_theme_stylebox_override("panel", arch)
	glyph.add_child(shackle)
	var body := Panel.new()
	body.set_anchors_preset(Control.PRESET_CENTER_TOP)
	body.offset_left = -11.0
	body.offset_right = 11.0
	body.offset_top = 16.0
	body.offset_bottom = 34.0
	body.add_theme_stylebox_override("panel", UiTheme.flat(UiTheme.TEXT_FAINT, 3))
	glyph.add_child(body)
	return glyph


func _label(label_text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


## Card state styleboxes; glow_color (alpha > 0) adds the soft outer glow
## the selected card wears in its border color.
func _style_card(card: Button, border_color: Color, border_width: int,
		glow_color: Color = Color(0, 0, 0, 0)) -> void:
	var fills: Dictionary[String, Color] = {
		"normal": UiTheme.CARD_BG,
		"hover": UiTheme.CARD_BG_HOVER,
		"pressed": UiTheme.CARD_BG_PRESSED,
		"focus": UiTheme.CARD_BG_HOVER,
	}
	for state: String in fills:
		var style := UiTheme.flat(fills[state], UiTheme.RADIUS)
		style.border_color = border_color
		style.set_border_width_all(border_width)
		if glow_color.a > 0.0:
			UiTheme.add_glow(style, glow_color, 9, 0.4)
		card.add_theme_stylebox_override(state, style)
