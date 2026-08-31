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
## sits top-right and the Quests button opens the quest log. Styling
## matches the run UI: dark StyleBoxFlat.

const QUEST_LOG_SCENE_PATH := "res://scenes/ui/QuestLog.tscn"

# Sized so the map row plus two grid rows of four cards fit the default
# 1152x648 window alongside the title and start button.
const CARD_SIZE := Vector2(172, 196)
const MAP_CARD_SIZE := Vector2(252, 54)
const UNSELECTED_BORDER_COLOR := Color(0.32, 0.34, 0.42)
const LOCKED_BORDER_COLOR := Color(0.22, 0.23, 0.28)
const LOCKED_TEXT_COLOR := Color(0.45, 0.47, 0.52)
const SHARD_TEXT_COLOR := Color(0.55, 0.8, 0.92)
const REJECT_FLASH_COLOR := Color(1.0, 0.42, 0.42)
const TIER_ACCENT_COLOR := Color(0.96, 0.78, 0.3)
const TIER_SUMMARY_COLOR := Color(0.72, 0.74, 0.78)
const TIER_BUTTON_SIZE := Vector2(64, 36)

@onready var _cards_grid: GridContainer = %CardsGrid
@onready var _map_row: HBoxContainer = %MapRow
@onready var _tier_row: HBoxContainer = %TierRow
@onready var _tier_summary_label: Label = %TierSummaryLabel
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


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	for map_row: Dictionary in MapCatalog.MAP_LIBRARY:
		var map_card := Button.new()
		map_card.custom_minimum_size = MAP_CARD_SIZE
		map_card.pressed.connect(_on_map_card_pressed.bind(String(map_row.id)))
		_map_row.add_child(map_card)
		_map_cards_by_id[String(map_row.id)] = map_card
	for tier in range(1, MapCatalog.TIER_COUNT + 1):
		var tier_button := Button.new()
		tier_button.custom_minimum_size = TIER_BUTTON_SIZE
		tier_button.text = "T%d" % tier
		tier_button.add_theme_font_size_override("font_size", 15)
		tier_button.pressed.connect(_on_tier_pressed.bind(tier))
		_tier_row.add_child(tier_button)
		_tier_buttons.append(tier_button)
	for character: Dictionary in CharacterCatalog.CHARACTER_LIBRARY:
		var card := Button.new()
		card.custom_minimum_size = CARD_SIZE
		card.pressed.connect(_on_card_pressed.bind(String(character.id)))
		_cards_grid.add_child(card)
		_cards_by_id[String(character.id)] = card
	_style_button(_start_button)
	_style_button(_quests_button)
	_style_button(_settings_button)
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


func _refresh_shards() -> void:
	_shards_label.text = "Shards: %d" % SaveData.shards


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
		_select(character_id)  # also refreshes every card
	else:
		_refresh_all_cards()


func _cancel_pending_unlock() -> void:
	_pending_unlock_id = ""


func _on_start_pressed() -> void:
	# RunState keeps ticking while this unpaused screen is up, so a fresh
	# run starts from a clean slate (mirrors the run-end Retry cleanup).
	RunState.reset()
	var map_row := MapCatalog.by_id_or_default(GameConfig.selected_map_id)
	get_tree().change_scene_to_file(String(map_row.scene_path))


func _on_quests_pressed() -> void:
	get_tree().change_scene_to_file(QUEST_LOG_SCENE_PATH)


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
	_tier_summary_label.add_theme_color_override("font_color", LOCKED_TEXT_COLOR)


func _refresh_tier_row() -> void:
	var map_id := GameConfig.selected_map_id
	for i in _tier_buttons.size():
		var tier := i + 1
		var tier_button := _tier_buttons[i]
		if not SaveData.is_tier_unlocked(map_id, tier):
			tier_button.tooltip_text = "Win Tier %d here to unlock" % (tier - 1)
			tier_button.add_theme_color_override("font_color", LOCKED_TEXT_COLOR)
			_style_card(tier_button, LOCKED_BORDER_COLOR, 2)
			continue
		tier_button.tooltip_text = ""
		var selected := tier == GameConfig.selected_tier
		tier_button.add_theme_color_override("font_color",
				TIER_ACCENT_COLOR if selected else Color(0.85, 0.87, 0.9))
		_style_card(tier_button,
				TIER_ACCENT_COLOR if selected else UNSELECTED_BORDER_COLOR,
				3 if selected else 2)
	_tier_summary_label.text = MapCatalog.tier_summary(map_id, GameConfig.selected_tier)
	_tier_summary_label.add_theme_color_override("font_color", TIER_SUMMARY_COLOR)


func _refresh_map_cards() -> void:
	for id: String in _map_cards_by_id:
		_populate_map_card(_map_cards_by_id[id], MapCatalog.by_id(id))


func _populate_map_card(card: Button, map_row: Dictionary) -> void:
	for child: Node in card.get_children():
		child.queue_free()
	var map_id := String(map_row.id)
	var box := _map_card_box(card)
	if not SaveData.is_map_unlocked(map_id):
		box.add_child(_label(String(map_row.display_name), 16, LOCKED_TEXT_COLOR))
		box.add_child(_label(String(map_row.locked_hint), 10, SHARD_TEXT_COLOR.darkened(0.2)))
		_style_card(card, LOCKED_BORDER_COLOR, 2)
		return
	box.add_child(_label(String(map_row.display_name), 16, Color(0.95, 0.96, 0.98)))
	box.add_child(_palette_strip(map_row.palette as Array))
	var selected := map_id == GameConfig.selected_map_id
	var accent := (map_row.palette as Array)[0] as Color
	_style_card(card, accent if selected else UNSELECTED_BORDER_COLOR, 4 if selected else 2)


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
		var style := StyleBoxFlat.new()
		style.bg_color = entry as Color
		style.set_corner_radius_all(3)
		chip.add_theme_stylebox_override("panel", style)
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
		return
	var box := _card_box(card)
	box.add_child(_portrait_swatch(Color(character.tint)))
	box.add_child(_label(String(character.display_name), 20, Color(0.95, 0.96, 0.98)))
	box.add_child(_label(String(character.weapon_display_name), 12, Color(0.62, 0.65, 0.7)))
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
	_style_card(card,
			Color(character.tint) if selected else UNSELECTED_BORDER_COLOR,
			4 if selected else 2)


## Grayed roster slot: lock glyph in place of the portrait, dimmed
## identity lines, and the Shard price as the call to action.
func _populate_locked_card(card: Button, character: Dictionary) -> void:
	var box := _card_box(card)
	box.add_child(_lock_glyph())
	box.add_child(_label(String(character.display_name), 20, LOCKED_TEXT_COLOR))
	box.add_child(_label(String(character.weapon_display_name), 12,
			LOCKED_TEXT_COLOR.darkened(0.15)))
	var passive := _label(String(character.passive_description), 12,
			LOCKED_TEXT_COLOR.darkened(0.15))
	passive.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(passive)
	var cost := _label("Unlock — %d Shards" % int(character.get("unlock_cost", 0)),
			13, SHARD_TEXT_COLOR)
	var hint_text := String(character.get("unlock_hint", ""))
	if hint_text.is_empty():
		cost.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_child(cost)
	else:
		# Boss-unlockable characters advertise both paths: the Shard price
		# and the catalog's vague clue toward the hidden-boss unlock.
		box.add_child(cost)
		var hint := _label("— or %s" % hint_text, 10, SHARD_TEXT_COLOR.darkened(0.2))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.size_flags_vertical = Control.SIZE_EXPAND_FILL
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_child(hint)
	_style_card(card, LOCKED_BORDER_COLOR, 2)


## The inline purchase prompt the locked card flips into when affordable.
func _populate_confirm_card(card: Button, character: Dictionary) -> void:
	var box := _card_box(card)
	box.add_child(_portrait_swatch(Color(character.tint)))
	box.add_child(_label(String(character.display_name), 20, Color(0.95, 0.96, 0.98)))
	var ask := _label("Unlock for %d Shards?" % int(character.get("unlock_cost", 0)),
			13, SHARD_TEXT_COLOR)
	ask.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(ask)
	var yes := Button.new()
	yes.text = "Yes"
	yes.custom_minimum_size = Vector2(0.0, 36.0)
	yes.pressed.connect(_on_unlock_confirmed.bind(String(character.id)))
	_style_button(yes)
	box.add_child(yes)
	var hint := _label("click card to cancel", 10, Color(0.5, 0.52, 0.58))
	hint.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(hint)
	_style_card(card, SHARD_TEXT_COLOR, 3)


## Can't-afford feedback: quick red flash plus a rotation wobble (rotation
## doesn't fight the GridContainer's layout the way position would).
func _reject_card(card: Button) -> void:
	card.pivot_offset = card.size / 2.0
	var tween := create_tween()
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
	var style := StyleBoxFlat.new()
	style.bg_color = tint
	style.border_color = tint.lightened(0.25)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
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
	arch.border_color = LOCKED_TEXT_COLOR
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
	var block := StyleBoxFlat.new()
	block.bg_color = LOCKED_TEXT_COLOR
	block.set_corner_radius_all(3)
	body.add_theme_stylebox_override("panel", block)
	glyph.add_child(body)
	return glyph


func _label(label_text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _style_card(card: Button, border_color: Color, border_width: int) -> void:
	var fills := {
		"normal": Color(0.13, 0.14, 0.18, 0.97),
		"hover": Color(0.18, 0.2, 0.26, 0.97),
		"pressed": Color(0.1, 0.11, 0.14, 0.97),
		"focus": Color(0.18, 0.2, 0.26, 0.97),
	}
	for state: String in fills:
		var style := StyleBoxFlat.new()
		style.bg_color = fills[state]
		style.border_color = border_color
		style.set_border_width_all(border_width)
		style.set_corner_radius_all(10)
		card.add_theme_stylebox_override(state, style)


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
