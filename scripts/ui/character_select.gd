extends Control
## Character select screen (GDD 5), the game's entry scene: pick a raider,
## then Start Run loads Main (which recaptures the mouse itself). Cards
## are built from CharacterCatalog at runtime, so a new playable character
## is one catalog row; grayed "???" slots pad the roster out to
## CharacterCatalog.ROSTER_SIZE to telegraph future unlocks. The pick
## lands in the GameConfig autoload, which the player reads at spawn.
## Styling matches the run UI: code-built dark StyleBoxFlat panels.

const MAIN_SCENE_PATH := "res://scenes/world/Main.tscn"

const CARD_SIZE := Vector2(236, 330)
const LOCKED_CARD_SIZE := Vector2(128, 170)
const UNSELECTED_BORDER_COLOR := Color(0.32, 0.34, 0.42)
const LOCKED_TEXT_COLOR := Color(0.4, 0.42, 0.48)

@onready var _cards_row: HBoxContainer = %CardsRow
@onready var _locked_row: HBoxContainer = %LockedRow
@onready var _start_button: Button = %StartButton

## Card button per playable character id, for selection restyling.
var _cards_by_id: Dictionary[String, Button] = {}


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	for character: Dictionary in CharacterCatalog.CHARACTER_LIBRARY:
		var card := _build_character_card(character)
		_cards_row.add_child(card)
		_cards_by_id[String(character.id)] = card
	for _i: int in CharacterCatalog.ROSTER_SIZE - CharacterCatalog.CHARACTER_LIBRARY.size():
		_locked_row.add_child(_build_locked_card())
	_style_button(_start_button)
	_start_button.pressed.connect(_on_start_pressed)
	# Reopening mid-session keeps the previous pick; unknown ids fall back.
	_select(String(CharacterCatalog.by_id_or_default(GameConfig.selected_character_id).id))
	_start_button.grab_focus()


func _select(character_id: String) -> void:
	GameConfig.selected_character_id = character_id
	for id: String in _cards_by_id:
		var character := CharacterCatalog.by_id(id)
		var selected := id == character_id
		_style_card(_cards_by_id[id],
				Color(character.tint) if selected else UNSELECTED_BORDER_COLOR,
				4 if selected else 2)
	var picked := CharacterCatalog.by_id(character_id)
	_start_button.text = "Start Run — %s" % String(picked.display_name)


func _on_start_pressed() -> void:
	# RunState keeps ticking while this unpaused screen is up, so a fresh
	# run starts from a clean slate (mirrors the run-end Retry cleanup).
	RunState.reset()
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)


func _build_character_card(character: Dictionary) -> Button:
	var card := Button.new()
	card.custom_minimum_size = CARD_SIZE
	card.pressed.connect(_select.bind(String(character.id)))
	var box := _card_box(card)
	box.add_child(_portrait_swatch(Color(character.tint)))
	box.add_child(_label(String(character.display_name), 26, Color(0.95, 0.96, 0.98)))
	box.add_child(_label(String(character.weapon_display_name), 15, Color(0.62, 0.65, 0.7)))
	box.add_child(_label(String(character.passive_description), 15, Color(0.85, 0.78, 0.5)))
	var blurb := _label(String(character.blurb), 13, Color(0.6, 0.62, 0.68))
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	blurb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(blurb)
	return card


## Grayed non-clickable "???" slot telegraphing a future roster unlock.
func _build_locked_card() -> Button:
	var card := Button.new()
	card.custom_minimum_size = LOCKED_CARD_SIZE
	card.disabled = true
	card.focus_mode = Control.FOCUS_NONE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.12, 0.9)
	style.border_color = Color(0.19, 0.2, 0.25)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	card.add_theme_stylebox_override("disabled", style)
	var box := _card_box(card)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_label("???", 30, LOCKED_TEXT_COLOR))
	box.add_child(_label("Locked", 12, LOCKED_TEXT_COLOR))
	return card


## Full-rect content VBox inside a card button (UpgradeCardUI convention).
func _card_box(card: Button) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 16.0
	box.offset_top = 14.0
	box.offset_right = -16.0
	box.offset_bottom = -14.0
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	return box


## Tinted stand-in for character art in the body color.
func _portrait_swatch(tint: Color) -> Panel:
	var swatch := Panel.new()
	swatch.custom_minimum_size = Vector2(0.0, 104.0)
	var style := StyleBoxFlat.new()
	style.bg_color = tint
	style.border_color = tint.lightened(0.25)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	swatch.add_theme_stylebox_override("panel", style)
	return swatch


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
