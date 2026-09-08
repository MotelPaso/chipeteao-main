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
## earns a red-flash shake instead. There is no map or difficulty picker
## any more (iteration 50): every run opens in Bosque Hueco and walks the
## whole map list, so the choices left here are the raider, the party and
## the Daily Hunt. The Shard balance sits top-right and the Quests button
## opens the quest log.
##
## Look (iteration 29): everything styles through UiTheme — animated fog
## backdrop shader, letter-spaced pulsing title, cards with tinted glow
## selection states (selected lifts, others dim), hero Start CTA,
## staggered entrance, and ScreenFade around
## every scene change. Card contents are built by CardFactory; the cards'
## state styleboxes are UiTheme.style_card — the same look the upgrade
## cards wear, so the two screens can never drift apart.
##
## Layout (iteration 46): the roster grows by catalog rows, so nothing is
## sized for "today's" 13 raiders. Title/subtitle stay pinned at the top
## and the button row at the bottom — the CTA is reachable at any window
## size — while the middle (maps, tier, co-op, card grid) scrolls, and the
## grid derives its column count from the window width and the roster
## size instead of hardcoding four.

const QUEST_LOG_SCENE_PATH := "res://scenes/ui/QuestLog.tscn"
const COLLECTION_SCENE_PATH := "res://scenes/ui/Collection.tscn"
const RELIC_SHOP_SCENE_PATH := "res://scenes/ui/RelicShop.tscn"

## Tall enough for the longest catalog passive plus two blurb lines in
## Spanish; the grid scrolls, so height is no longer a screen-fit budget.
const CARD_SIZE := Vector2(184, 244)
## Line caps keep a card's content BOUNDED: every text block trims with an
## ellipsis instead of wrapping past the bottom edge (Spanish runs ~30%
## longer than the English these cards were first measured against). The
## locked card gets the tighter passive cap because it also carries the
## price chip and the unlock hint.
const PASSIVE_MAX_LINES := 3
const LOCKED_PASSIVE_MAX_LINES := 2
const UNLOCK_HINT_MAX_LINES := 2
const BLURB_MAX_LINES := 2
const REJECT_FLASH_COLOR := Color(1.0, 0.42, 0.42)
## Segmented button size, shared by the co-op player-count row (it was
## the tier picker's size before iteration 50 removed that row).
const SEGMENT_BUTTON_SIZE := Vector2(64, 36)
## Non-selected cards sit slightly dimmed so the pick reads at a glance.
const UNSELECTED_DIM := Color(0.8, 0.82, 0.86)
## Side margin of the scene's Layout MarginContainer, so the column math
## measures the width the grid actually gets.
const LAYOUT_SIDE_MARGIN := 24.0
## The grid never drops below this, and aims to stay within this many rows
## before it widens (a taller grid just scrolls).
const GRID_MIN_COLUMNS := 4
const GRID_TARGET_ROWS := 3

@onready var _title_label: Label = %TitleLabel
@onready var _subtitle_label: Label = %SubtitleLabel
@onready var _cards_grid: GridContainer = %CardsGrid
## HFlowContainer: the meta buttons wrap to a second line rather than
## running off a narrow window (Spanish labels are wider than the English).
@onready var _button_row: HFlowContainer = %ButtonRow
@onready var _start_button: Button = %StartButton
@onready var _quests_button: Button = %QuestsButton
@onready var _settings_button: Button = %SettingsButton
@onready var _settings_panel: SettingsPanel = %SettingsPanel
@onready var _shards_label: Label = %ShardsLabel
@onready var _version_label: Label = %VersionLabel

## Card button per playable character id, for selection restyling.
var _cards_by_id: Dictionary[String, Button] = {}
## Character id whose card currently shows the inline unlock confirm.
var _pending_unlock_id: String = ""
var _title_tween: Tween = null
var _entrance_tween: Tween = null
## Autoload/Input subscriptions kept as fields so _exit_tree can drop them
## explicitly (they outlive this scene; node-to-node ones do not).
var _on_shards_changed: Callable
var _on_pads_changed: Callable

## --- Co-op lobby state (GDD extension: local co-op, 1-4 players) --------
## Selected party size; 1 = the unchanged solo flow.
var _coop_count: int = 1
## Character id per slot (index 0 mirrors GameConfig.selected_character_id).
var _coop_characters: Array[String] = []
## Slot the next character-card click assigns to (auto-advances).
var _editing_slot: int = 0
var _coop_buttons: Array[Button] = []
var _slot_buttons: Array[Button] = []
var _coop_row: HBoxContainer = null
var _slot_row: HBoxContainer = null
var _coop_hint: Label = null


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build_coop_rows()
	for character: Dictionary in CharacterCatalog.CHARACTER_LIBRARY:
		var card := Button.new()
		card.custom_minimum_size = CARD_SIZE
		card.pressed.connect(_on_card_pressed.bind(String(character.id)))
		UiTheme.attach_motion(card, 1.03)
		card.mouse_exited.connect(_resettle_card.bind(String(character.id)))
		_keep_pivot_centered(card)
		_cards_grid.add_child(card)
		_cards_by_id[String(character.id)] = card
	_update_grid_columns()
	resized.connect(_update_grid_columns)
	_apply_chrome()
	# attach_motion is idempotent (first call wins), so the hero CTA has to
	# claim its stronger grow/squash BEFORE style_button attaches the
	# default one — the other order silently ships the defaults.
	UiTheme.attach_motion(_start_button, 1.05, 0.93)
	UiTheme.style_button(_start_button, UiTheme.ACCENT, true)
	UiTheme.style_button(_quests_button)
	UiTheme.style_button(_settings_button)
	_start_button.pressed.connect(_on_start_pressed)
	_quests_button.pressed.connect(_on_quests_pressed)
	_build_extra_buttons()
	# The shared SettingsPanel (same scene the pause menu embeds) overlays
	# this whole screen; on close, focus returns to Start.
	_settings_button.pressed.connect(_settings_panel.open)
	_settings_panel.closed.connect(func() -> void: _start_button.grab_focus())
	_on_shards_changed = func(_balance: int) -> void: _refresh_shards()
	SaveData.shards_changed.connect(_on_shards_changed)
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
	# Remember the last party (Retry / back from a run replays it); pads
	# may have (dis)connected since, so the count re-validates itself.
	_restore_coop_session()
	_start_button.grab_focus()
	_play_entrance()


## Subscriptions to autoloads and Input outlive this scene, so they are
## dropped by hand; everything else dies with the node tree.
func _exit_tree() -> void:
	if _on_shards_changed.is_valid() \
			and SaveData.shards_changed.is_connected(_on_shards_changed):
		SaveData.shards_changed.disconnect(_on_shards_changed)
	if _on_pads_changed.is_valid() \
			and Input.joy_connection_changed.is_connected(_on_pads_changed):
		Input.joy_connection_changed.disconnect(_on_pads_changed)


## --- Card grid sizing (the roster grows by catalog rows) ----------------

## Columns come from the roster size (aim for GRID_TARGET_ROWS rows) capped
## by what the window can actually show, so adding a raider widens the grid
## instead of pushing rows — and the CTA — out of the screen.
func _update_grid_columns() -> void:
	var separation := float(_cards_grid.get_theme_constant(&"h_separation"))
	var available := get_viewport_rect().size.x - LAYOUT_SIDE_MARGIN * 2.0
	var fits := maxi(1, floori((available + separation) / (CARD_SIZE.x + separation)))
	var wanted := maxi(GRID_MIN_COLUMNS, ceili(
			float(CharacterCatalog.CHARACTER_LIBRARY.size()) / float(GRID_TARGET_ROWS)))
	var columns := clampi(wanted, 1, fits)
	if _cards_grid.columns != columns:
		_cards_grid.columns = columns


## Cards scale from their center, but their size is only known after the
## first layout pass; following `resized` keeps the pivot centered instead
## of sampling it once at build time, when it is still zero.
func _keep_pivot_centered(control: Control) -> void:
	control.resized.connect(func() -> void:
		control.pivot_offset = control.size * 0.5)


## --- Co-op lobby (players row + per-slot character assignment) ----------

func _build_coop_rows() -> void:
	var vbox := _cards_grid.get_parent()
	var grid_index := _cards_grid.get_index()
	_coop_row = HBoxContainer.new()
	_coop_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_coop_row.add_theme_constant_override("separation", 8)
	var tag := CardFactory.label("Jugadores", 14, UiTheme.TEXT_DIM)
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_coop_row.add_child(tag)
	for count in range(1, Coop.MAX_PLAYERS + 1):
		var count_button := Button.new()
		count_button.custom_minimum_size = SEGMENT_BUTTON_SIZE
		count_button.text = str(count)
		count_button.add_theme_font_size_override("font_size", 15)
		count_button.pressed.connect(_on_coop_count_pressed.bind(count))
		UiTheme.attach_motion(count_button, 1.06)
		_coop_row.add_child(count_button)
		_coop_buttons.append(count_button)
	_coop_hint = CardFactory.label("", 11, UiTheme.TEXT_FAINT)
	_coop_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_coop_row.add_child(_coop_hint)
	vbox.add_child(_coop_row)
	vbox.move_child(_coop_row, grid_index)
	_slot_row = HBoxContainer.new()
	_slot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_slot_row.add_theme_constant_override("separation", 8)
	_slot_row.visible = false
	vbox.add_child(_slot_row)
	vbox.move_child(_slot_row, grid_index + 1)
	_on_pads_changed = func(_device: int, _connected: bool) -> void: _refresh_coop_rows()
	Input.joy_connection_changed.connect(_on_pads_changed)
	_refresh_coop_rows()


func _restore_coop_session() -> void:
	_coop_characters = Coop.character_ids.duplicate()
	_set_coop_count(mini(Coop.player_count, _max_supported_players()), true)


## J1 plays keyboard+mouse (or any pad in solo); each extra player needs
## their own connected joypad.
func _max_supported_players() -> int:
	return mini(Input.get_connected_joypads().size() + 1, Coop.MAX_PLAYERS)


func _on_coop_count_pressed(count: int) -> void:
	if count > _max_supported_players():
		_reject_card(_coop_buttons[count - 1])
		# The number is what is still MISSING, not the party total: with one
		# pad already plugged in, a 4-player party needs two more, not three.
		var missing := maxi(count - 1 - Input.get_connected_joypads().size(), 1)
		_coop_hint.text = "Conecta %d control(es) para %d jugadores" % [missing, count]
		_coop_hint.add_theme_color_override("font_color", UiTheme.TEXT_FAINT)
		return
	_set_coop_count(count)


func _set_coop_count(count: int, silent: bool = false) -> void:
	_coop_count = clampi(count, 1, Coop.MAX_PLAYERS)
	# Fill fresh slots with the current solo pick; sanitize stale/locked ids.
	_coop_characters.resize(_coop_count)
	for i in _coop_count:
		# by_id, never by_id_or_default: an id that left the catalog has to
		# be REPLACED here, and the fallback row would report the DEFAULT
		# character's unlock state and let the junk id ride into Coop.
		var row := CharacterCatalog.by_id(_coop_characters[i])
		if row.is_empty() or not SaveData.is_unlocked(String(row.id)):
			_coop_characters[i] = String(CharacterCatalog.by_id_or_default(
					GameConfig.selected_character_id).id)
	_editing_slot = mini(_editing_slot, _coop_count - 1)
	if not silent:
		Sfx.play(&"card_pick")
	_refresh_coop_rows()
	_refresh_all_cards()
	_refresh_start_button()


func _refresh_coop_rows() -> void:
	var supported := _max_supported_players()
	if _coop_count > supported:
		# A pad was unplugged mid-lobby: fold back to what still works.
		_set_coop_count(supported, true)
		return
	for i in _coop_buttons.size():
		var count := i + 1
		var selected := count == _coop_count
		var usable := count <= supported
		_coop_buttons[i].add_theme_color_override("font_color",
				UiTheme.ACCENT_AMBER if selected
				else (Color(0.85, 0.87, 0.9) if usable else UiTheme.TEXT_FAINT))
		UiTheme.style_card(_coop_buttons[i],
				UiTheme.ACCENT_AMBER if selected
				else (UiTheme.BORDER_DIM if usable else UiTheme.BORDER_LOCKED),
				3 if selected else 2, selected)
	var pads := Input.get_connected_joypads().size()
	if _coop_count > 2:
		_coop_hint.text = "J1 teclado+mouse · J2-J%d control · %d control(es)" \
				% [_coop_count, pads]
	elif _coop_count == 2:
		# "J2-J2" reads as an empty range, so the two-player party names its
		# single pad slot outright instead of spelling a range.
		_coop_hint.text = "J1 teclado+mouse · J2 control · %d control(es)" % pads
	else:
		_coop_hint.text = ("%d control(es) conectado(s)" % pads) if pads > 0 \
				else "Conecta controles para co-op local"
	_coop_hint.add_theme_color_override("font_color", UiTheme.TEXT_FAINT)
	_refresh_slot_row()


## One button per party slot showing its assigned raider; the highlighted
## one is the slot the next card click configures.
func _refresh_slot_row() -> void:
	_slot_row.visible = _coop_count > 1
	# A slot button rebuilds this row from its own `pressed`, so the focus
	# owner is usually one of the buttons about to die: remember it and hand
	# the focus to the rebuilt row, or pad/keyboard navigation dead-ends
	# here. remove_child before queue_free because the free is deferred —
	# otherwise the old buttons keep laying out for the rest of the frame.
	var focus_owner := get_viewport().gui_get_focus_owner()
	var had_focus := focus_owner != null and _slot_buttons.has(focus_owner)
	for button: Button in _slot_buttons:
		_slot_row.remove_child(button)
		button.queue_free()
	_slot_buttons.clear()
	if _coop_count <= 1:
		return
	for slot in _coop_count:
		var slot_button := Button.new()
		slot_button.custom_minimum_size = Vector2(150, 36)
		var character := CharacterCatalog.by_id_or_default(_coop_characters[slot])
		slot_button.text = "J%d: %s" % [slot + 1, String(character.display_name)]
		slot_button.add_theme_font_size_override("font_size", 13)
		slot_button.pressed.connect(func() -> void:
			_editing_slot = slot
			Sfx.play(&"card_pick")
			_refresh_slot_row()
			_refresh_all_cards())
		UiTheme.attach_motion(slot_button, 1.05)
		var tint := Color(character.tint)
		var editing := slot == _editing_slot
		slot_button.add_theme_color_override("font_color",
				tint.lightened(0.35) if editing else Color(0.85, 0.87, 0.9))
		UiTheme.style_card(slot_button, tint if editing else UiTheme.BORDER_DIM,
				3 if editing else 2, editing)
		_slot_row.add_child(slot_button)
		_slot_buttons.append(slot_button)
	if had_focus:
		_slot_buttons[clampi(_editing_slot, 0, _slot_buttons.size() - 1)].grab_focus()


func _refresh_start_button() -> void:
	if _coop_count > 1:
		_start_button.text = "Iniciar incursión — %d jugadores" % _coop_count
	else:
		var picked := CharacterCatalog.by_id_or_default(GameConfig.selected_character_id)
		_start_button.text = "Iniciar incursión — %s" % String(picked.display_name)


## Title/subtitle/shard typography plus the slow title glow pulse (this
## screen is the game's face; the motion says "alive", never "busy").
func _apply_chrome() -> void:
	UiTheme.style_title(_title_label, 52, UiTheme.ACCENT_AMBER, 10, 12)
	_subtitle_label.add_theme_font_override("font", UiTheme.spaced_font(2))
	_subtitle_label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	UiTheme.style_badge(_shards_label, UiTheme.SHARD_BLUE,
			UiTheme.PANEL_BG, UiTheme.SHARD_BLUE.darkened(0.45))
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
	var sections: Array[Control] = [_title_label, _subtitle_label,
			_coop_row, _slot_row, _cards_grid, _button_row]
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
	_shards_label.text = "Esquirlas: %d" % SaveData.shards
	UiTheme.pop(_shards_label, 1.12, 0.22)


## Selection is only ever offered for unlocked characters (_on_card_pressed
## routes locked clicks into the unlock flow instead). In co-op the click
## assigns the raider to the highlighted slot and auto-advances to the
## next one, so "click 4 cards" configures a full party.
func _select(character_id: String) -> void:
	if _coop_count > 1:
		_coop_characters[_editing_slot] = character_id
		if _editing_slot == 0:
			GameConfig.selected_character_id = character_id
		_editing_slot = (_editing_slot + 1) % _coop_count
		_refresh_slot_row()
	else:
		GameConfig.selected_character_id = character_id
	_refresh_all_cards()
	_refresh_start_button()


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
		_reject_card(_cards_by_id[character_id],
				_rest_modulate(_card_selected(character_id)))


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
	# A normal start is never the daily (the Daily Hunt button sets it).
	GameConfig.daily_mode = false
	# Freeze the party into the Coop autoload: slot 0 keyboard+mouse, the
	# rest one connected joypad each (in system order). Solo re-configures
	# to 1 so a previous co-op session never leaks into a solo run.
	var pads := Input.get_connected_joypads()
	# joy_connection_changed is what normally folds the party back, but a
	# pad can die between that signal and this click: re-check the list
	# HERE rather than indexing it blind, and let the player see the
	# smaller party before committing to it.
	var usable := mini(_coop_count, pads.size() + 1)
	if usable < _coop_count:
		_set_coop_count(usable, true)
		_coop_hint.text = "Se desconectó un control — vuelves al modo solo" if usable <= 1 \
				else "Se desconectó un control — ahora son %d jugadores" % usable
		_reject_card(_start_button)
		return
	var slot_devices: Array[int] = [Coop.KEYBOARD_DEVICE]
	for extra in range(1, _coop_count):
		slot_devices.append(pads[extra - 1])
	var slot_characters: Array[String] = []
	if _coop_count > 1:
		for i in _coop_count:
			slot_characters.append(_coop_characters[i])
	else:
		slot_characters.append(GameConfig.selected_character_id)
	Coop.configure(_coop_count, slot_devices, slot_characters)
	# One scene for every run (iteration 49): Run.tscn owns the persistent
	# run block and swaps the arena per stage. Every run opens in the
	# forest and walks the map list from there, so there is no map to pick.
	GameConfig.start_map_id = MapCatalog.DEFAULT_ID
	ScreenFade.transition(func() -> void:
		# RunState keeps ticking while this unpaused screen is up, so a
		# fresh run starts from a clean slate (mirrors the run-end Retry).
		RunState.reset()
		get_tree().change_scene_to_file(RUN_SCENE_PATH))


## The one scene a run boots into (iteration 49).
const RUN_SCENE_PATH: String = "res://scenes/world/Run.tscn"


func _on_quests_pressed() -> void:
	ScreenFade.transition(func() -> void:
		get_tree().change_scene_to_file(QUEST_LOG_SCENE_PATH))


## Meta-screen buttons added in code beside the scene's Quests/Settings
## pair (same pattern as the code-built co-op rows), so the .tscn stays
## untouched as screens accumulate: Collection (35), Armory + Daily (36).
func _build_extra_buttons() -> void:
	var collection_button := _extra_button("Colección", func() -> void:
		ScreenFade.transition(func() -> void:
			get_tree().change_scene_to_file(COLLECTION_SCENE_PATH)))
	_button_row.move_child(collection_button, _quests_button.get_index() + 1)
	var armory_button := _extra_button("Armería", func() -> void:
		ScreenFade.transition(func() -> void:
			get_tree().change_scene_to_file(RELIC_SHOP_SCENE_PATH)))
	_button_row.move_child(armory_button, collection_button.get_index() + 1)
	var best := SaveData.stat("daily_best_" + _today_id())
	var daily_button := _extra_button(
			"Cacería diaria" if best <= 0 else "Cacería diaria — mejor %d" % best,
			_on_daily_pressed)
	UiTheme.style_button(daily_button, UiTheme.ACCENT_AMBER)
	_button_row.move_child(daily_button, _start_button.get_index() + 1)


func _extra_button(label_text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = label_text
	button.custom_minimum_size = _quests_button.custom_minimum_size
	button.add_theme_font_size_override("font_size", 20)
	UiTheme.style_button(button)
	button.pressed.connect(on_pressed)
	_button_row.add_child(button)
	return button


## --- Daily Hunt (iteration 36) ------------------------------------------

func _today_id() -> String:
	return Time.get_date_string_from_system()


## Launches the seeded daily: character, map, and world layout are the same
## for everyone playing that date (picked deterministically from THIS
## player's unlocked pools), tier 1, solo. Retries are allowed — the best
## score of the day is what sticks.
func _on_daily_pressed() -> void:
	var date_id := _today_id()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(date_id)
	var characters: Array[String] = []
	for character: Dictionary in CharacterCatalog.CHARACTER_LIBRARY:
		if SaveData.is_unlocked(String(character.id)):
			characters.append(String(character.id))
	if characters.is_empty():
		return
	GameConfig.daily_mode = true
	GameConfig.daily_seed = int(hash(date_id))
	GameConfig.daily_date = date_id
	GameConfig.selected_character_id = characters[rng.randi() % characters.size()]
	# The daily starts in the forest like every other run (iteration 49);
	# its seed is what makes the layout, cards and spawns identical for
	# everyone that day, not the map.
	GameConfig.selected_map_id = MapCatalog.DEFAULT_ID
	GameConfig.start_map_id = MapCatalog.DEFAULT_ID
	Coop.configure(1, [Coop.KEYBOARD_DEVICE] as Array[int],
			[GameConfig.selected_character_id] as Array[String])
	ScreenFade.transition(func() -> void:
		RunState.reset()
		get_tree().change_scene_to_file(RUN_SCENE_PATH))


## --- Card content (rebuilt whenever lock/selection state changes) ------

func _refresh_all_cards() -> void:
	for id: String in _cards_by_id:
		_populate_card(_cards_by_id[id], CharacterCatalog.by_id(id))


## queue_free is deferred, so the outgoing content box would keep laying
## out (stacked under the new one) for the rest of the frame; removing it
## first makes every rebuild a clean swap even under fast clicking.
func _clear_card(card: Button) -> void:
	for child: Node in card.get_children():
		card.remove_child(child)
		child.queue_free()


func _populate_card(card: Button, character: Dictionary) -> void:
	_clear_card(card)
	var character_id := String(character.id)
	if not SaveData.is_unlocked(character_id):
		if _pending_unlock_id == character_id:
			_populate_confirm_card(card, character)
		else:
			_populate_locked_card(card, character)
		_settle_card(card, _pending_unlock_id == character_id)
		return
	var box := CardFactory.card_box(card)
	box.add_child(CardFactory.portrait_swatch(Color(character.tint)))
	# Wrapped, never trimmed: a raider's name is untranslatable AND
	# unshortenable (GLOSARIO rule 5), and the roster now holds one long
	# enough to run past the card edge ("PNG gucci morty" against a 7-letter
	# previous longest). Two lines beat an ellipsis eating a proper noun.
	var name_label := CardFactory.label(
			String(character.display_name), 20, UiTheme.TEXT_BRIGHT)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(name_label)
	box.add_child(CardFactory.label(
			String(character.weapon_display_name), 12, UiTheme.TEXT_DIM))
	# Both text blocks are capped: a long translated passive used to wrap
	# without limit and shove the blurb out through the bottom of the card.
	var passive := CardFactory.label(
			String(character.passive_description), 12, Color(0.85, 0.78, 0.5))
	passive.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	passive.max_lines_visible = PASSIVE_MAX_LINES
	passive.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(passive)
	var blurb := CardFactory.label(String(character.blurb), 11, Color(0.6, 0.62, 0.68))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# The passive line takes priority in the compact grid card; the flavor
	# blurb takes the leftover space and trims rather than overflowing.
	blurb.max_lines_visible = BLURB_MAX_LINES
	blurb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	blurb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	blurb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(blurb)
	# Co-op: a card reads selected when ANY slot picked it, and shows which
	# ones ("J1 · J3") so the party composition is visible at a glance.
	var selected := _card_selected(character_id)
	if _coop_count > 1 and selected:
		var owners: Array[String] = []
		for slot in _coop_count:
			if _coop_characters[slot] == character_id:
				owners.append("J%d" % (slot + 1))
		box.add_child(CardFactory.label(" · ".join(owners), 11, UiTheme.ACCENT_AMBER))
	var tint := Color(character.tint)
	UiTheme.style_card(card, tint if selected else UiTheme.BORDER_DIM,
			3 if selected else 2, selected)
	_settle_card(card, selected)


## The one answer to "does this card read as picked?", shared by the
## repaint and by the hover motion that has to restore the rest pose.
func _card_selected(character_id: String) -> bool:
	if not SaveData.is_unlocked(character_id):
		return _pending_unlock_id == character_id
	if _coop_count > 1:
		return _coop_characters.has(character_id)
	return character_id == GameConfig.selected_character_id


func _rest_modulate(selected: bool) -> Color:
	return Color.WHITE if selected else UNSELECTED_DIM


## Selection motion: the picked card lifts slightly and brightens while
## the rest dim a step. Tween per card, parked in meta so rapid clicking
## never stacks animations — and it is the single owner of a card's rest
## pose, so it also cancels (and straightens) a running reject wobble.
func _settle_card(card: Button, selected: bool) -> void:
	card.pivot_offset = card.size * 0.5
	UiTheme.kill_meta_tween(card, &"ui_settle_tween")
	card.rotation_degrees = 0.0
	var tween := card.create_tween()
	tween.set_ignore_time_scale(true)
	tween.set_parallel()
	tween.tween_property(card, "scale",
			Vector2.ONE * (1.035 if selected else 1.0), 0.16) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "modulate", _rest_modulate(selected), 0.16)
	card.set_meta(&"ui_settle_tween", tween)


## UiTheme's shared hover motion always returns a button to scale 1.0,
## which would wipe the selected card's lift on mouse-out. Re-settling
## after killing the hover tween keeps one winner instead of two tweens
## racing on the same property.
func _resettle_card(character_id: String) -> void:
	var card: Button = _cards_by_id.get(character_id)
	if card == null:
		return
	UiTheme.kill_meta_tween(card, &"ui_motion_tween")
	_settle_card(card, _card_selected(character_id))


## Grayed roster slot: lock glyph in place of the portrait, dimmed
## identity lines, and the Shard price as the call to action.
func _populate_locked_card(card: Button, character: Dictionary) -> void:
	var box := CardFactory.card_box(card)
	box.add_child(CardFactory.lock_glyph())
	box.add_child(CardFactory.label(
			String(character.display_name), 20, UiTheme.TEXT_FAINT))
	box.add_child(CardFactory.label(String(character.weapon_display_name), 12,
			UiTheme.TEXT_FAINT.darkened(0.15)))
	var passive := CardFactory.label(String(character.passive_description), 12,
			UiTheme.TEXT_FAINT.darkened(0.15))
	passive.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	passive.max_lines_visible = LOCKED_PASSIVE_MAX_LINES
	passive.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(passive)
	# Price chip: a small shard-blue pill so the cost reads as a button.
	var cost := CardFactory.label("%d esquirlas" % int(character.get("unlock_cost", 0)),
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
		var hint := CardFactory.label(
				"— o %s" % hint_text, 10, UiTheme.SHARD_BLUE.darkened(0.25))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.max_lines_visible = UNLOCK_HINT_MAX_LINES
		hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		hint.size_flags_vertical = Control.SIZE_EXPAND_FILL
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_child(hint)
	UiTheme.style_card(card, UiTheme.BORDER_LOCKED, 2, false)


## The inline purchase prompt the locked card flips into when affordable.
func _populate_confirm_card(card: Button, character: Dictionary) -> void:
	var box := CardFactory.card_box(card)
	box.add_child(CardFactory.portrait_swatch(Color(character.tint)))
	box.add_child(CardFactory.label(
			String(character.display_name), 20, UiTheme.TEXT_BRIGHT))
	var ask := CardFactory.label(
			"¿Desbloquear por %d esquirlas?" % int(character.get("unlock_cost", 0)),
			13, UiTheme.SHARD_BLUE)
	ask.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(ask)
	var yes := Button.new()
	yes.text = "Sí"
	yes.custom_minimum_size = Vector2(0.0, 36.0)
	yes.pressed.connect(_on_unlock_confirmed.bind(String(character.id)))
	UiTheme.style_button(yes, UiTheme.SHARD_BLUE, true)
	box.add_child(yes)
	var hint := CardFactory.label("clic en la carta para cancelar", 10, UiTheme.TEXT_FAINT)
	hint.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(hint)
	UiTheme.style_card(card, UiTheme.SHARD_BLUE, 3)


## Can't-afford feedback: quick red flash plus a rotation wobble (rotation
## doesn't fight the GridContainer's layout the way position would). The
## flash returns to the card's REST modulate — an unselected card is dim,
## and landing it on white would leave it brighter than its neighbours —
## and shares _settle_card's meta so the two never animate at once.
func _reject_card(card: Button, rest_modulate: Color = Color.WHITE) -> void:
	card.pivot_offset = card.size / 2.0
	UiTheme.kill_meta_tween(card, &"ui_settle_tween")
	var tween := card.create_tween()
	tween.set_ignore_time_scale(true)
	tween.tween_property(card, "modulate", REJECT_FLASH_COLOR, 0.06)
	tween.parallel().tween_property(card, "rotation_degrees", -4.0, 0.05)
	tween.tween_property(card, "rotation_degrees", 4.0, 0.08)
	tween.tween_property(card, "rotation_degrees", -2.0, 0.07)
	tween.tween_property(card, "rotation_degrees", 0.0, 0.06)
	tween.parallel().tween_property(card, "modulate", rest_modulate, 0.18)
	card.set_meta(&"ui_settle_tween", tween)
