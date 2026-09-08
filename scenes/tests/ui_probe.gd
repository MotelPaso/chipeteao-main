extends Node
## Headless UI harness (iteration 57). Seven of the nine UI scenes had
## never been booted by anything: CharacterSelect, Collection, QuestLog,
## RelicShop and SettingsPanel were never instanced at all, and PauseMenu
## and RunEndScreen were instanced by RunSystems.tscn but never opened. A
## handler that errors on its first press, a menu that never gives the
## pause back, a `%` name renamed in a .tscn — none of that could fail a
## soak, because no soak ever went there.
##
## Run it alone with (the --quit-after is a hard two-minute ceiling; the
## probe quits itself long before that):
##   godot --headless --fixed-fps 60 --quit-after 7200 \
##     res://scenes/tests/UiProbe.tscn
##
## Output contract (tools/verificar.sh greps every step name off its own
## fixed list, so a step that silently stops running is a failure):
##   UiProbe: step <name> ok      ... one per step, in order
##   UiProbe: done steps=%d       ... only when every step passed
## A missing control, a rejected precondition or a pause that does not
## lift is a push_error, which PATRON_ERROR catches on its own.
##
## ARCHITECTURE. %StartButton and the run-end buttons REPLACE
## current_scene, so a driver living inside the scene under test would be
## freed halfway through its own test. This scene's root script therefore
## does exactly one thing: it creates the Driver below and adds it to
## get_tree().root (deferred — adding a child to the root from inside a
## _ready trips "Parent node is busy setting up children"), where it
## outlives every scene change. The driver then drives CharacterSelect
## and everything downstream, re-acquiring current_scene after each cut.
##
## It presses the REAL controls: buttons by unique name resolved against
## their own owner (%SettingsButton exists in both CharacterSelect.tscn
## and PauseMenu.tscn), by text only for the ones built in code, and
## ui_cancel as a parsed InputEventAction with the release on a LATER
## frame. It never calls an underscore handler: a test that calls
## _on_card_pressed directly proves the method exists, not that the
## button reaches it.

## Save file when BONK_SAVE_PATH is not set. SaveData._ready already
## honours the env var; this is only the fallback, so a hand-run probe
## still never touches the player's ledger.
const FALLBACK_SAVE_PATH := "user://ui_probe_save.json"
## Shards seeded after boot so exactly one raider unlock is affordable
## (the locked catalog rows cost 50-180).
const SEEDED_SHARDS: int = 200


func _ready() -> void:
	# Deferred: adding to the tree root from inside a _ready trips
	# "Parent node is busy setting up children".
	_spawn_driver.call_deferred()


func _spawn_driver() -> void:
	var driver := Driver.new()
	driver.name = "UiProbeDriver"
	driver.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(driver)


## The whole harness. A Node parented to the tree ROOT, so it survives
## every change_scene_to_file the steps below trigger.
class Driver extends Node:
	const CHARACTER_SELECT_PATH := "res://scenes/ui/CharacterSelect.tscn"
	const COLLECTION_PATH := "res://scenes/ui/Collection.tscn"
	const QUEST_LOG_PATH := "res://scenes/ui/QuestLog.tscn"
	const RELIC_SHOP_PATH := "res://scenes/ui/RelicShop.tscn"
	const RUN_PATH := "res://scenes/world/Run.tscn"

	## Frames a step may take before it counts as wedged. Generous on
	## purpose: this is a HANG detector, not a stopwatch. Two steps wait
	## on real run time and say so in STEP_DEADLINES below.
	const STEP_DEADLINE_FRAMES: int = 600
	## Steps that wait for the run clock, which ticks once per frame:
	## start_run wants run_time >= 10 (600 frames on its own) and retry
	## wants >= 5, so the default deadline would fire on a HEALTHY run.
	const STEP_DEADLINES: Dictionary[String, int] = {
		"start_run": 1200,
		"retry": 900,
	}
	## Frames to let ScreenFade finish after a scene lands. Its cut is
	## FADE_IN 0.22 + FADE_OUT 0.26 = ~29 frames, and a press that lands
	## inside that window is DROPPED silently.
	const FADE_SETTLE_FRAMES: int = 40
	## Run time the run has to reach before start_run / retry count.
	const RUN_TIME_TARGET: float = 10.0
	const RETRY_TIME_TARGET: float = 5.0

	## Every step, in order. Each one is a method named _step_<name>
	## returning true when it is finished.
	const STEPS: Array[String] = [
		"collection", "quests", "relics", "coop_count_reject",
		"unlock_confirm", "cards_all", "start_run", "pause_open",
		"settings_toggle", "pause_close", "extract", "retry", "done",
	]

	var _step: int = 0
	var _step_frames: int = 0
	var _phase: int = 0
	var _steps_done: int = 0
	var _failed: bool = false
	var _settle: int = 0
	## scene_file_path of the scene the driver last saw, so a change can
	## trigger exactly ONE fade settle instead of one per poll.
	var _last_scene: String = ""
	## Character the unlock step bought, checked by the step after it.
	var _unlock_id: String = ""
	## Actions waiting for their release frame (see _send_action).
	var _release: Array[StringName] = []

	func _ready() -> void:
		if OS.get_environment(SaveData.SAVE_PATH_ENV).is_empty():
			SaveData.save_path = FALLBACK_SAVE_PATH
			SaveData.load_from_disk()
			print("UiProbe: save path %s" % SaveData.save_path)
		SaveData.shards = SEEDED_SHARDS
		print("UiProbe: shards=%d" % SaveData.shards)
		get_tree().change_scene_to_file(CHARACTER_SELECT_PATH)

	func _process(_delta: float) -> void:
		_flush_releases()
		if _failed:
			return
		# One settle per CUT: ScreenFade keeps fading for FADE_OUT_TIME
		# over a scene the driver can already see, and a press landing in
		# that window is dropped without a trace.
		var scene := get_tree().current_scene
		var path := scene.scene_file_path if scene != null else ""
		if path != _last_scene:
			_last_scene = path
			_settle = FADE_SETTLE_FRAMES
			return
		# A level-up during the run steps would park a card UI over
		# everything and wedge the probe exactly like the soak harness
		# would be wedged; pick option 0 the same way ArenaProbe does.
		_serve_card_ui()
		if _settle > 0:
			_settle -= 1
			return
		var step_name := STEPS[_step]
		_step_frames += 1
		if _step_frames > _deadline(step_name):
			_fail("step %s never finished (%d frames)" % [step_name, _step_frames])
			return
		var finished: bool = call("_step_" + step_name)
		if not finished:
			return
		print("UiProbe: step %s ok" % step_name)
		_steps_done += 1
		_step += 1
		_step_frames = 0
		_phase = 0
		if _step >= STEPS.size():
			print("UiProbe: done steps=%d" % _steps_done)
			get_tree().quit(0)

	func _deadline(step_name: String) -> int:
		return int(STEP_DEADLINES.get(step_name, STEP_DEADLINE_FRAMES))

	func _fail(reason: String) -> void:
		_failed = true
		push_error("UiProbe: %s" % reason)
		get_tree().quit(1)

	# --- steps ---------------------------------------------------------

	## Colección: the button is built in code (no unique name), so it is
	## matched by its label — the only thing that identifies it.
	func _step_collection() -> bool:
		return _visit_meta_screen(_extra_button("Colección"), COLLECTION_PATH)

	func _step_quests() -> bool:
		return _visit_meta_screen(_unique_button("%QuestsButton"), QUEST_LOG_PATH)

	func _step_relics() -> bool:
		return _visit_meta_screen(_extra_button("Armería"), RELIC_SHOP_PATH)

	## The co-op row rejects a party bigger than the connected pads allow.
	## Headless there are none, so 2 players is always the reject path —
	## the multi-slot rows themselves are unreachable here and belong to
	## the co-op soak (BONK_PLAYERS=2).
	func _step_coop_count_reject() -> bool:
		match _phase:
			0:
				if not _at_scene(CHARACTER_SELECT_PATH):
					return false
				var button := _button_with_text("2")
				if button == null:
					_fail("no co-op count button labelled '2'")
					return false
				if not _press(button, "co-op count 2"):
					return false
				_phase = 1
				return false
			_:
				# The hint is the reject path's only output: the select
				# screen does not touch Coop until Start, so player_count
				# would read 1 whether the press was accepted or not.
				return _hint_label_text().find("Conecta") >= 0

	## One locked raider bought through the real two-press flow: the card
	## arms the inline confirm, the code-built «Sí» inside it commits.
	func _step_unlock_confirm() -> bool:
		match _phase:
			0:
				_unlock_id = _affordable_locked_id()
				if _unlock_id.is_empty():
					_fail("no locked raider is affordable with %d shards" % SaveData.shards)
					return false
				var card := _card_for(_unlock_id)
				if card == null:
					_fail("no card in %%CardsGrid for raider '%s'" % _unlock_id)
					return false
				if not _press(card, "locked card %s" % _unlock_id):
					return false
				_phase = 1
				return false
			1:
				var card := _card_for(_unlock_id)
				var yes := _find_button_with_text(card, "Sí")
				if yes == null:
					return false  # the confirm card rebuilds over a frame
				if not _press(yes, "confirm «Sí» for %s" % _unlock_id):
					return false
				_phase = 2
				return false
			_:
				if not SaveData.is_unlocked(_unlock_id):
					_fail("raider '%s' is still locked after confirming" % _unlock_id)
					return false
				var card := _card_for(_unlock_id)
				if _find_button_with_text(card, "Sí") != null:
					_fail("card '%s' still shows the confirm button after unlocking"
							% _unlock_id)
					return false
				return true

	## Every card once, after the unlock so no confirm is left armed by an
	## earlier press. Locked-and-unaffordable cards take the reject path,
	## unlocked ones the select path: both are handlers nothing else runs.
	func _step_cards_all() -> bool:
		var grid := _unique("%CardsGrid")
		if grid == null:
			_fail("no %CardsGrid on the select screen")
			return false
		var cards: Array[Button] = []
		for child: Node in grid.get_children():
			var card := child as Button
			if card != null:
				cards.append(card)
		if cards.is_empty():
			_fail("%CardsGrid is empty")
			return false
		if _phase >= cards.size():
			return true
		if not _press(cards[_phase], "card %d" % _phase):
			return false
		_phase += 1
		return false

	## The real start: %StartButton runs ScreenFade.transition, which
	## REPLACES current_scene with the run.
	func _step_start_run() -> bool:
		match _phase:
			0:
				var button := _unique_button("%StartButton")
				if button == null:
					_fail("no %StartButton on the select screen")
					return false
				if not _press(button, "%StartButton"):
					return false
				_phase = 1
				return false
			_:
				if not _at_scene(RUN_PATH):
					return false
				return RunState.run_time >= RUN_TIME_TARGET

	## Esc opens the pause menu through its own _unhandled_input, which is
	## the only path that exists: _open() is private.
	func _step_pause_open() -> bool:
		match _phase:
			0:
				_send_action(&"ui_cancel", true)
				_phase = 1
				return false
			_:
				if not get_tree().paused:
					return false
				var menu := _pause_menu()
				if menu == null:
					_fail("the tree paused but no PauseMenu is in the run")
					return false
				if not menu.visible:
					return false
				return true

	## The shared SettingsPanel, opened from the PAUSE menu's own
	## %SettingsButton (the select screen has a different node with the
	## same unique name, which is why every % here is resolved against its
	## owner). %FpsCheck is a CheckButton: a click changes button_pressed,
	## which is what emits `toggled` — pressed.emit() would not.
	func _step_settings_toggle() -> bool:
		var menu := _pause_menu()
		if menu == null:
			_fail("no PauseMenu to open settings from")
			return false
		var panel := menu.get_node_or_null("%SettingsPanel") as Control
		if panel == null:
			_fail("no %SettingsPanel under the pause menu")
			return false
		match _phase:
			0:
				var button := menu.get_node_or_null("%SettingsButton") as Button
				if button == null:
					_fail("no %SettingsButton under the pause menu")
					return false
				if not _press(button, "pause %SettingsButton"):
					return false
				_phase = 1
				return false
			1:
				if not panel.visible:
					return false
				var check := panel.get_node_or_null("%FpsCheck") as CheckButton
				if check == null:
					_fail("no %FpsCheck under the settings panel")
					return false
				if check.disabled or not check.is_visible_in_tree():
					_fail("%FpsCheck is disabled or hidden")
					return false
				var before := SaveData.show_fps
				check.button_pressed = not check.button_pressed
				if SaveData.show_fps == before:
					_fail("toggling %FpsCheck did not move SaveData.show_fps")
					return false
				check.button_pressed = not check.button_pressed
				if SaveData.show_fps != before:
					_fail("toggling %FpsCheck twice did not restore SaveData.show_fps")
					return false
				_phase = 2
				return false
			2:
				var back := panel.get_node_or_null("%BackButton") as Button
				if back == null:
					_fail("no %BackButton under the settings panel")
					return false
				if not _press(back, "settings %BackButton"):
					return false
				_phase = 3
				return false
			_:
				return not panel.visible

	func _step_pause_close() -> bool:
		var menu := _pause_menu()
		if menu == null:
			_fail("no PauseMenu to close")
			return false
		match _phase:
			0:
				var button := menu.get_node_or_null("%ResumeButton") as Button
				if button == null:
					_fail("no %ResumeButton under the pause menu")
					return false
				if not _press(button, "%ResumeButton"):
					return false
				_phase = 1
				return false
			_:
				if get_tree().paused:
					return false
				return not menu.visible

	## Extract through the run_manager group, the same call the pause
	## menu's own button makes. The end screen is what has to appear.
	func _step_extract() -> bool:
		match _phase:
			0:
				if get_tree().get_first_node_in_group("run_manager") == null:
					_fail("no run_manager in the run")
					return false
				get_tree().call_group("run_manager", "extract_run")
				_phase = 1
				return false
			_:
				var screen := _run_end_screen()
				if screen == null or not screen.visible:
					return false
				var showing := false
				for node: Node in get_tree().get_nodes_in_group("ui_blocking"):
					var shown: Variant = node.get("visible")
					if shown != null and bool(shown):
						showing = true
						break
				if not showing:
					_fail("the run ended but no ui_blocking member is visible")
					return false
				return true

	## Retry reloads the run behind ScreenFade.leave_run, which is the one
	## ritual that owns the cleanup, the reset and the swap.
	func _step_retry() -> bool:
		match _phase:
			0:
				var screen := _run_end_screen()
				if screen == null:
					_fail("no RunEndScreen to retry from")
					return false
				var button := screen.get_node_or_null("%RetryButton") as Button
				if button == null:
					_fail("no %RetryButton under the run-end screen")
					return false
				if not _press(button, "%RetryButton"):
					return false
				_phase = 1
				return false
			_:
				if not _at_scene(RUN_PATH):
					return false
				if get_tree().paused:
					return false
				return RunState.run_time >= RETRY_TIME_TARGET

	## Nothing to press: the last step exists so the run ends on a step
	## line like every other one, and so the count in the summary is the
	## count verificar.sh greps.
	func _step_done() -> bool:
		return true

	# --- helpers -------------------------------------------------------

	## True when current_scene IS that scene. The fade after a cut is
	## waited out by the settle in _process, once per change.
	func _at_scene(scene_path: String) -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.scene_file_path == scene_path

	## Open a meta screen, check it landed, come back through its own
	## %BackButton. The three of them share meta_screen.gd, so one shape
	## covers Colección, Misiones and Armería.
	func _visit_meta_screen(open_button: Button, scene_path: String) -> bool:
		match _phase:
			0:
				if not _at_scene(CHARACTER_SELECT_PATH):
					return false
				if open_button == null:
					_fail("no button to open %s" % scene_path.get_file())
					return false
				if not _press(open_button, "open %s" % scene_path.get_file()):
					return false
				_phase = 1
				return false
			1:
				if not _at_scene(scene_path):
					return false
				_phase = 2
				return false
			2:
				var scene := get_tree().current_scene
				var back := scene.get_node_or_null("%BackButton") as Button
				if back == null:
					_fail("no %%BackButton on %s" % scene_path.get_file())
					return false
				if not _press(back, "%BackButton"):
					return false
				_phase = 3
				return false
			_:
				return _at_scene(CHARACTER_SELECT_PATH)

	## pressed.emit() bypasses `disabled` and visibility, so a harness
	## that only emits proves the handler runs, not that a player could
	## ever reach it. Both are asserted first.
	func _press(button: Button, what: String) -> bool:
		if button == null:
			_fail("no button for '%s'" % what)
			return false
		if button.disabled:
			_fail("button '%s' is disabled" % what)
			return false
		if not button.is_visible_in_tree():
			_fail("button '%s' is not visible" % what)
			return false
		button.pressed.emit()
		return true

	## A unique name on the CURRENT scene's root, which is what owns it.
	func _unique(unique_name: String) -> Node:
		var scene := get_tree().current_scene
		if scene == null:
			return null
		return scene.get_node_or_null(unique_name)


	## Same, cast to Button — separate from _unique because %CardsGrid is a
	## GridContainer and a single Button-typed helper returned null for it,
	## which read as "the grid is empty" instead of "wrong type".
	func _unique_button(unique_name: String) -> Button:
		return _unique(unique_name) as Button

	## The code-built meta buttons (Colección, Armería) carry no unique
	## name; their label is the only handle they have.
	func _extra_button(label_text: String) -> Button:
		return _find_button_with_text(get_tree().current_scene, label_text)

	## First Button whose own text matches, anywhere under `root`.
	func _find_button_with_text(root: Node, label_text: String) -> Button:
		if root == null:
			return null
		var button := root as Button
		if button != null and button.text == label_text:
			return button
		for child: Node in root.get_children():
			var found := _find_button_with_text(child, label_text)
			if found != null:
				return found
		return null

	func _button_with_text(label_text: String) -> Button:
		return _find_button_with_text(get_tree().current_scene, label_text)

	## Text of the co-op row's hint label (built in code, no unique name):
	## the only visible proof the reject path ran.
	func _hint_label_text() -> String:
		var scene := get_tree().current_scene
		if scene == null:
			return ""
		var texts := ""
		for label: Label in _labels(scene):
			texts += label.text + "\n"
		return texts

	func _labels(root: Node) -> Array[Label]:
		var found: Array[Label] = []
		var label := root as Label
		if label != null:
			found.append(label)
		for child: Node in root.get_children():
			found.append_array(_labels(child))
		return found

	## The cheapest locked raider this balance can buy.
	func _affordable_locked_id() -> String:
		var best := ""
		var best_cost := 0
		for row: Dictionary in CharacterCatalog.CHARACTER_LIBRARY:
			var id := String(row.get("id", ""))
			if SaveData.is_unlocked(id):
				continue
			var cost := int(row.get("unlock_cost", 0))
			if not SaveData.can_afford(cost):
				continue
			if best.is_empty() or cost < best_cost:
				best = id
				best_cost = cost
		return best

	## The grid holds one Button per CHARACTER_LIBRARY row, in order.
	func _card_for(character_id: String) -> Button:
		var grid := _unique("%CardsGrid")
		if grid == null:
			return null
		var index := -1
		for i in CharacterCatalog.CHARACTER_LIBRARY.size():
			if String(CharacterCatalog.CHARACTER_LIBRARY[i].get("id", "")) == character_id:
				index = i
				break
		if index < 0 or index >= grid.get_child_count():
			return null
		return grid.get_child(index) as Button

	func _pause_menu() -> CanvasLayer:
		var scene := get_tree().current_scene
		if scene == null:
			return null
		return scene.find_child("PauseMenu", true, false) as CanvasLayer

	func _run_end_screen() -> CanvasLayer:
		var scene := get_tree().current_scene
		if scene == null:
			return null
		return scene.find_child("RunEndScreen", true, false) as CanvasLayer

	## A level-up card UI would pause the tree over everything else; the
	## soak harness answers it the same way.
	func _serve_card_ui() -> void:
		for node: Node in get_tree().get_nodes_in_group("upgrade_ui"):
			var ui := node as CanvasLayer
			if ui != null and ui.visible and ui.has_method("_on_card_pressed"):
				ui.call("_on_card_pressed", 0)

	## A parsed InputEventAction, released on a LATER frame: both in one
	## flush and is_action_just_pressed never sees the press, which is
	## exactly what PauseMenu._unhandled_input tests for.
	func _send_action(action: StringName, pressed: bool) -> void:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
		if pressed:
			_release.append(action)

	func _flush_releases() -> void:
		if _release.is_empty():
			return
		var pending := _release.duplicate()
		_release.clear()
		for action: StringName in pending:
			var event := InputEventAction.new()
			event.action = action
			event.pressed = false
			Input.parse_input_event(event)
