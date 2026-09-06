class_name MetaScreen
extends Control
## Shared chassis for the three between-run screens (Quest Log, Armory,
## Collection). They are the same screen with different rows: same fog
## backdrop, same spaced amber title, same badge pill, same Back button,
## same staggered entrance and — for the two that spend or earn Shards —
## the same count-up payoff. Everything that is NOT row content lives
## here, so a fix or a restyle lands on all three at once instead of
## drifting three ways.
##
## Scene contract (QuestLog.tscn / RelicShop.tscn / Collection.tscn):
## %TitleLabel, %BadgeLabel, %List (VBoxContainer) and %BackButton. The
## title text stays in the scene — it is per-screen copy, not behaviour.
##
## Subclass hooks: _badge_color(), _tracks_shards() and _build_rows(list).
## Shared moments a subclass calls: payoff() (claim / buy), reject()
## (can't afford) and rebuild().

const CHARACTER_SELECT_SCENE_PATH := "res://scenes/ui/CharacterSelect.tscn"

const PAYOFF_FLASH := Color(1.7, 1.45, 0.85)
const REJECT_FLASH := Color(1.0, 0.42, 0.42)
const CARD_MARGIN_H := 16.0
const CARD_MARGIN_V := 10.0
## Only the rows that fit on screen animate in; a 40-row list would
## otherwise open as a slideshow.
const ENTRANCE_ROWS := 8
const COUNT_TIME := 0.4

@onready var _title_label: Label = %TitleLabel
@onready var _badge_label: Label = %BadgeLabel
@onready var _list: VBoxContainer = %List
@onready var _back_button: Button = %BackButton

var _count_tween: Tween = null


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	UiTheme.style_title(_title_label, 40, UiTheme.ACCENT_AMBER, 8, 10)
	var badge := _badge_color()
	UiTheme.style_badge(_badge_label, badge, UiTheme.PANEL_BG, badge.darkened(0.45))
	_badge_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiTheme.style_button(_back_button, UiTheme.ACCENT, true)
	_back_button.pressed.connect(_on_back_pressed)
	if _tracks_shards():
		SaveData.shards_changed.connect(_on_shards_changed)
		refresh_badge()
	rebuild()
	play_entrance()
	_back_button.grab_focus()


func _exit_tree() -> void:
	# SaveData outlives every screen, so the connection has to go with us.
	if SaveData.shards_changed.is_connected(_on_shards_changed):
		SaveData.shards_changed.disconnect(_on_shards_changed)


## Esc leaves, the same as everywhere else in the game (the HUD teaches
## "Esc" and the pause menu, settings and roulette all honour it).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _on_back_pressed() -> void:
	ScreenFade.transition(func() -> void:
		get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE_PATH))


# --- badge ------------------------------------------------------------

func refresh_badge() -> void:
	set_badge_count(SaveData.shards)


func set_badge_count(value: int) -> void:
	_badge_label.text = "Esquirlas: %d" % value


## The balance broadcast arrives synchronously from claim_quest /
## purchase_relic, i.e. BEFORE the count-up starts: repainting on it would
## show the final number for one frame and then jump back to count.
func _on_shards_changed(_balance: int) -> void:
	if _count_tween != null and _count_tween.is_valid():
		return
	refresh_badge()


func _count_balance(before: int, after: int) -> void:
	set_badge_count(before)  # start from the old value, never from the new one
	if _count_tween != null and _count_tween.is_valid():
		_count_tween.kill()
	_count_tween = create_tween()
	_count_tween.set_ignore_time_scale(true)
	_count_tween.tween_method(_set_badge_step, float(before), float(after), COUNT_TIME)
	_count_tween.tween_callback(refresh_badge)  # settle on the real balance
	UiTheme.pop(_badge_label, 1.2, 0.3)


func _set_badge_step(value: float) -> void:
	set_badge_count(int(value))


# --- shared moments ---------------------------------------------------

## The payoff moment (claim a quest, buy a rank): count the balance up or
## down, flash the row gold, and resort the list once the flash lands.
func payoff(row: Control, before: int, after: int, sound: StringName) -> void:
	Sfx.play(sound)
	_count_balance(before, after)
	if not is_instance_valid(row):
		rebuild()
		return
	var flash := create_tween()
	flash.set_ignore_time_scale(true)
	flash.tween_property(row, "modulate", PAYOFF_FLASH, 0.08)
	flash.tween_property(row, "modulate", Color.WHITE, 0.2)
	flash.tween_callback(rebuild)


## Can't-afford wobble. One tween per row, parked in metadata: mashing the
## button restarts it instead of stacking N tweens writing the same
## rotation and modulate (the kill_meta_tween pattern the rest of the UI
## already uses).
func reject(row: Control) -> void:
	if not is_instance_valid(row):
		return
	row.pivot_offset = row.size * 0.5
	UiTheme.kill_meta_tween(row, &"ui_reject_tween")
	row.rotation_degrees = 0.0
	row.modulate = Color.WHITE
	var tween := create_tween()
	tween.set_ignore_time_scale(true)
	tween.tween_property(row, "modulate", REJECT_FLASH, 0.06)
	tween.parallel().tween_property(row, "rotation_degrees", -2.0, 0.05)
	tween.tween_property(row, "rotation_degrees", 2.0, 0.08)
	tween.tween_property(row, "rotation_degrees", 0.0, 0.07)
	tween.parallel().tween_property(row, "modulate", Color.WHITE, 0.18)
	row.set_meta(&"ui_reject_tween", tween)


## remove_child BEFORE queue_free: a child freed this frame still sits in
## the container until the frame ends, so appending the new rows first
## would double the container's height for one frame and make the
## ScrollContainer jump away from the row the player just used.
func rebuild() -> void:
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_build_rows(_list)


## Staggered fade-in of the topmost rows. Bails out on an empty list: a
## Tween with no tweeners warns on stderr, and the soaks grep for that.
func play_entrance() -> void:
	var rows: Array[Control] = []
	for child: Node in _list.get_children():
		var row := child as Control
		if row != null:
			rows.append(row)
		if rows.size() >= ENTRANCE_ROWS:
			break
	if rows.is_empty():
		return
	var tween := create_tween().set_parallel()
	tween.set_ignore_time_scale(true)
	for i in rows.size():
		var settled := rows[i].modulate
		rows[i].modulate = Color(settled.r, settled.g, settled.b, 0.0)
		tween.tween_property(rows[i], "modulate:a", settled.a, 0.18) \
				.set_delay(0.04 * i)


# --- shared row chrome ------------------------------------------------

## The card look every row in the three screens wears: rounded card body,
## 2px accent border, optional glow for the "earned" states.
static func card_style(accent: Color, glow: bool) -> StyleBoxFlat:
	var style := UiTheme.flat(UiTheme.CARD_BG, UiTheme.RADIUS)
	style.border_color = accent
	style.set_border_width_all(2)
	if glow:
		UiTheme.add_glow(style, accent, 8, 0.32)
	style.content_margin_left = CARD_MARGIN_H
	style.content_margin_right = CARD_MARGIN_H
	style.content_margin_top = CARD_MARGIN_V
	style.content_margin_bottom = CARD_MARGIN_V
	return style


static func label(label_text: String, font_size: int, color: Color) -> Label:
	var text_label := Label.new()
	text_label.text = label_text
	text_label.add_theme_font_size_override("font_size", font_size)
	text_label.add_theme_color_override("font_color", color)
	return text_label


# --- subclass hooks ---------------------------------------------------

## Badge pill accent (and its text color). Shards blue by default.
func _badge_color() -> Color:
	return UiTheme.SHARD_BLUE


## False for screens whose badge is not a Shard balance (the Collection
## writes its own completion percentage while it rebuilds).
func _tracks_shards() -> bool:
	return true


## Fill the list. Called on open and after every payoff.
func _build_rows(_list_node: VBoxContainer) -> void:
	pass
