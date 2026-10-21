extends CanvasLayer
## Roulette menu (iteration 41), built in code by a RouletteShrine: pauses
## the tree (ui_blocking contract, layer between cards and run-end), lists
## every outcome, and on SPIN runs a slot-style highlight sweep before the
## real result (already rolled and applied) lands. Leave/Esc unpauses.
##
## Pause safety: this layer holds the whole tree paused, so it must never
## be able to outlive its owner. It closes itself if the raider that
## opened it — or the shrine it belongs to, on a stage teardown — goes
## away, exposes dismiss() for anything that needs to shut it down
## programmatically (group "blocking_ui_closable"), and on a headless
## display it plays itself — a soak has nobody to press SPIN, and a wheel
## waiting forever freezes the whole run. The release also runs from
## _exit_tree, so a panel freed rather than closed still hands the tree
## back — and, like the card picker, it never releases a pause another
## blocking layer has taken over.

## Sweep tunables. The delays are derived from sweep_time, so the constant
## actually controls the length of the spin.
@export var sweep_time: float = 1.4
@export var sweep_steps: int = 22

## Shape of the slowdown: the last hops are ~4.6x longer than the first.
const SWEEP_EASE_MIN := 0.03
const SWEEP_EASE_MAX := 0.14

const DIM_COLOR := Color(0.03, 0.03, 0.05, 0.75)
const ROW_SIZE := Vector2(260.0, 26.0)
const ROW_BG := Color(0.07, 0.075, 0.11, 0.9)
const SPIN_BUTTON_SIZE := Vector2(200.0, 46.0)
const CLOSE_BUTTON_SIZE := Vector2(140.0, 46.0)
const HIGHLIGHT_ON := Color(1.6, 1.5, 1.2)
const HIGHLIGHT_OFF := Color(1.0, 1.0, 1.0, 0.55)

## Headless self-play: spin once, show the result, leave.
const HEADLESS_SPIN_DELAY := 0.4
const HEADLESS_LEAVE_DELAY := 3.0

var _shrine: RouletteShrine = null
var _player: Node = null
var _rows: Array[Label] = []
var _spin_button: Button = null
var _close_button: Button = null
var _result_label: Label = null
var _points_label: Label = null
var _spinning: bool = false
## True only between the _ready that paused the tree and the release that
## hands it back (pause_menu.gd's _pause_owned rule). Both the close and the
## _exit_tree backstop go through it, so the pause is released exactly once
## and a panel that never got as far as pausing releases nothing.
var _pause_held: bool = false


## MUST be called before add_child(): _ready builds the panel from the
## shrine's price and the raider's points.
func setup(shrine: RouletteShrine, player: Node) -> void:
	_shrine = shrine
	_player = player


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Nothing to watch — and no pause of ours to release — until the panel
	# is actually up.
	set_process(false)
	if _shrine == null or not is_instance_valid(_player):
		push_error("RouletteUi: setup() must run before add_child()")
		queue_free()
		return
	add_to_group("ui_blocking")
	add_to_group("blocking_ui_closable")
	_build()
	get_tree().paused = true
	_pause_held = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	set_process(true)
	if DisplayServer.get_name() == "headless":
		_auto_play()


## PauseMenu/UpgradeCardUi contract ("ui_blocking"): true while this layer
## owns the tree pause. False once it is queued for deletion — the node
## stays in the group until the delete queue flushes at the end of the
## frame, and a dying wheel answering "yes" makes the card picker (or a
## stage swap) skip its own unpause for that frame.
func is_blocking() -> bool:
	return not is_queued_for_deletion()


## Programmatic close (soak harnesses, teardown). Mid-spin it waits: the
## outcome is already applied, only the reveal is pending.
func dismiss() -> void:
	if _spinning:
		return
	_close()


## The tree is paused, so nothing else can notice that the raider who
## opened the wheel is gone (co-op wipe) — or that the shrine itself went
## with the stage. Nobody would be left to press Leave, and the pause would
## outlive the run. Both references are checked, like the vendor's panel:
## the price and the spin are read off the shrine, so a wheel whose altar is
## gone has nothing left to sell either.
func _process(_delta: float) -> void:
	if is_queued_for_deletion():
		return
	if not is_instance_valid(_player) or not is_instance_valid(_shrine):
		_close()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = DIM_COLOR
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
			UiTheme.panel(UiTheme.PANEL_BG, UiTheme.ACCENT_AMBER, 32.0, 22.0))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	_build_header(box)
	_build_outcome_grid(box)
	_build_result(box)
	_build_buttons(box)


func _build_header(box: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "RULETA DE LA FORTUNA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiTheme.style_title(title, 36, UiTheme.ACCENT_AMBER, 6, 8)
	box.add_child(title)
	_points_label = Label.new()
	_points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_points_label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	box.add_child(_points_label)
	_refresh_points()


func _build_outcome_grid(box: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	box.add_child(grid)
	for outcome: Dictionary in RouletteShrine.OUTCOMES:
		var row := Label.new()
		row.text = "  " + String(outcome.label)
		row.custom_minimum_size = ROW_SIZE
		var tint := (outcome.color as Color).lightened(0.15)
		row.add_theme_color_override("font_color", tint)
		UiTheme.style_badge(row, tint, ROW_BG, Color(outcome.color as Color, 0.4))
		grid.add_child(row)
		_rows.append(row)


func _build_result(box: VBoxContainer) -> void:
	_result_label = Label.new()
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.custom_minimum_size = Vector2(0.0, 30.0)
	_result_label.add_theme_font_size_override("font_size", 20)
	_result_label.add_theme_color_override("font_color", UiTheme.TEXT_BRIGHT)
	box.add_child(_result_label)


func _build_buttons(box: VBoxContainer) -> void:
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 14)
	box.add_child(buttons)
	_spin_button = Button.new()
	_spin_button.text = "GIRAR — %d pts" % _shrine.current_price()
	_spin_button.custom_minimum_size = SPIN_BUTTON_SIZE
	UiTheme.style_button(_spin_button, UiTheme.ACCENT_AMBER, true)
	_spin_button.pressed.connect(_on_spin)
	buttons.add_child(_spin_button)
	_close_button = Button.new()
	_close_button.text = "Salir"
	_close_button.custom_minimum_size = CLOSE_BUTTON_SIZE
	UiTheme.style_button(_close_button)
	_close_button.pressed.connect(_close)
	buttons.add_child(_close_button)
	_spin_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _spinning:
		_close()
		get_viewport().set_input_as_handled()


## Spin stays disabled for the whole sweep: a button that looks pressable
## and silently swallows the press is worse than a greyed-out one.
func _refresh_points() -> void:
	_points_label.text = "Tienes %d pts" % int(_player.get("points"))
	if _spin_button != null:
		# The price doubles with every spin (iteration 46), so the label is
		# re-read here and not baked once when the panel is built.
		var cost := _shrine.current_price()
		_spin_button.text = "GIRAR — %d pts" % cost
		_spin_button.disabled = _spinning or int(_player.get("points")) < cost


func _on_spin() -> void:
	if _spinning:
		return
	var outcome := _shrine.spin(_player)
	if outcome.is_empty():
		_result_label.text = "No te alcanzan los puntos."
		return
	_spinning = true
	# Clear the previous spin before this one starts: the wheel is
	# reusable, so a stale result line and a stale highlight would still be
	# on screen while the new sweep runs.
	_result_label.text = ""
	for row: Label in _rows:
		row.modulate = Color.WHITE
	_close_button.disabled = true
	_refresh_points()
	Sfx.play(&"card_pick")
	_sweep_to(outcome)


## Slot-machine sweep: the highlight hops across rows, slowing down, and
## stops on the real outcome. Runs on this ALWAYS layer, ignores time scale.
func _sweep_to(outcome: Dictionary) -> void:
	var target := _row_index(String(outcome.id))
	if target < 0:
		# Landing anywhere would contradict the result line we are about
		# to print, and a lying wheel is worse than no animation.
		push_warning("RouletteUi: outcome '%s' has no row" % String(outcome.id))
		_land(outcome)
		return
	var steps := maxi(sweep_steps, 2)
	var tween := create_tween()
	tween.set_ignore_time_scale(true)
	var index := randi() % _rows.size()
	var delays := _sweep_delays(steps)
	for step in steps:
		index = (index + 1) % _rows.size()
		if step == steps - 1:
			index = target
		tween.tween_callback(_highlight.bind(index))
		tween.tween_interval(delays[step])
	tween.tween_callback(_land.bind(outcome))


func _row_index(outcome_id: String) -> int:
	for i in RouletteShrine.OUTCOMES.size():
		if String(RouletteShrine.OUTCOMES[i].id) == outcome_id:
			return i
	return -1


## Eased-out hop delays normalized so they add up to sweep_time — that is
## what makes the exported constant mean something.
func _sweep_delays(steps: int) -> PackedFloat32Array:
	var delays := PackedFloat32Array()
	var total := 0.0
	for step in steps:
		var t := float(step) / float(steps - 1)
		var weight := lerpf(SWEEP_EASE_MIN, SWEEP_EASE_MAX, t * t)
		delays.append(weight)
		total += weight
	var scale := maxf(sweep_time, 0.1) / maxf(total, 0.001)
	for i in delays.size():
		delays[i] *= scale
	return delays


func _highlight(index: int) -> void:
	for i in _rows.size():
		_rows[i].modulate = HIGHLIGHT_ON if i == index else HIGHLIGHT_OFF
	Sfx.play(&"hit_soft")


func _land(outcome: Dictionary) -> void:
	_spinning = false
	_result_label.text = "▶ %s" % String(outcome.label)
	_result_label.add_theme_color_override("font_color", (outcome.color as Color).lightened(0.2))
	UiTheme.pop(_result_label, 1.3, 0.3)
	Sfx.play(&"shrine_done")
	_close_button.disabled = false
	_refresh_points()
	_close_button.grab_focus()


## Soaks (and any other headless run) have no hands: play one spin and
## leave, so the paused tree is always handed back.
func _auto_play() -> void:
	await get_tree().create_timer(HEADLESS_SPIN_DELAY, true, false, true).timeout
	if not is_inside_tree():
		return
	_on_spin()
	await get_tree().create_timer(HEADLESS_LEAVE_DELAY, true, false, true).timeout
	if is_inside_tree():
		_close()


## Guarded because several paths can reach it — Esc, the Salir button, the
## headless leave backstop, the watchdog above — and the tree pause must be
## released exactly once, by whichever gets here first.
func _close() -> void:
	if is_queued_for_deletion():
		return
	_release_pause()
	queue_free()


## Hands the tree back, at most once, and only when it is OURS to hand back
## (upgrade_card_ui.gd's rule). A spin can put another "ui_blocking" layer
## on screen — the card picker off a rolled prize — and the run can end
## under this panel, in which case the run-end screen owns the pause and the
## mouse; unpausing in either case would resume the world behind somebody
## else's modal and steal the mouse from its buttons.
func _release_pause() -> void:
	if not _pause_held:
		return
	_pause_held = false
	if not RunState.run_active or _other_blocking_ui_open():
		return
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## Any OTHER member of "ui_blocking" holding the pause right now?
func _other_blocking_ui_open() -> bool:
	for node: Node in get_tree().get_nodes_in_group("ui_blocking"):
		if node == self or not node.has_method(&"is_blocking"):
			continue
		if node.call(&"is_blocking") == true:
			return true
	return false


## _close() is the only path that unpauses, so a panel FREED instead of
## closed — free() from a harness, the stage parent going with a stage swap
## — would strand a paused tree with nothing left on screen to release it.
func _exit_tree() -> void:
	_release_pause()
