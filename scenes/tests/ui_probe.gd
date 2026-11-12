extends Node
## Arnés headless de la interfaz. Abre las escenas de UI que ningún soak
## visita (CharacterSelect, Collection, QuestLog, RelicShop, SettingsPanel,
## PauseMenu, RunEndScreen) y aprieta sus controles: un handler que falla al
## primer clic, un menú que no devuelve la pausa o un nombre `%` cambiado en
## un .tscn hacen fallar el gate.
##
## Se corre solo con (el --quit-after es un techo duro de dos minutos; el
## probe sale mucho antes):
##   godot --headless --fixed-fps 60 --quit-after 7200 \
##     res://scenes/tests/UiProbe.tscn
##
## Contrato de salida (tools/verificar.sh busca cada nombre de paso en su
## propia lista fija, así que un paso que deja de correr en silencio es falla):
##   UiProbe: step <name> ok      ... uno por paso, en orden
##   UiProbe: done steps=%d       ... solo cuando pasaron todos los pasos
## Un control que falta, una precondición rechazada o una pausa que no se
## levanta es un push_error, que PATRON_ERROR atrapa por sí solo.
##
## ARQUITECTURA. %StartButton y los botones del fin de partida REEMPLAZAN
## current_scene, así que un driver dentro de la escena probada se liberaría
## a mitad de su propia prueba. Por eso el script raíz de esta escena hace
## una sola cosa: crea el Driver de abajo y lo agrega a get_tree().root
## (diferido: agregar un hijo a la raíz desde un _ready dispara "Parent node
## is busy setting up children"), donde sobrevive a cada cambio de escena.
## El driver maneja CharacterSelect y todo lo que sigue, y vuelve a tomar
## current_scene después de cada corte.
##
## Aprieta los controles REALES: botones por nombre único resuelto contra su
## propio owner (%SettingsButton existe en CharacterSelect.tscn y en
## PauseMenu.tscn; los botones co-op y el «Sí» de cada tarjeta se resuelven
## dentro de su instancia de CoopLobby / CharacterCard), y pause_game como
## InputEventAction con la liberación en un frame POSTERIOR. Nunca llama a un
## handler con guion bajo: llamar _on_card_pressed directo prueba que el
## método existe, no que el botón llega a él.

## Archivo de guardado si BONK_SAVE_PATH no está definido. SaveData._ready ya
## lee la variable; esto es solo el respaldo, para que un probe corrido a mano
## nunca toque el progreso del jugador.
const FALLBACK_SAVE_PATH := "user://ui_probe_save.json"
## Fragmentos que se cargan tras el arranque para que alcance exactamente un
## desbloqueo de raider (las filas bloqueadas del catálogo cuestan 50-180).
const SEEDED_SHARDS: int = 200


func _ready() -> void:
	# Diferido: agregar a la raíz del árbol desde un _ready dispara
	# "Parent node is busy setting up children".
	_spawn_driver.call_deferred()


func _spawn_driver() -> void:
	var driver := Driver.new()
	driver.name = "UiProbeDriver"
	driver.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(driver)


## El arnés completo. Un Node colgado de la RAÍZ del árbol, para sobrevivir a
## cada change_scene_to_file que disparan los pasos de abajo.
class Driver extends Node:
	const CHARACTER_SELECT_PATH := "res://scenes/ui/CharacterSelect.tscn"
	const COLLECTION_PATH := "res://scenes/ui/Collection.tscn"
	const QUEST_LOG_PATH := "res://scenes/ui/QuestLog.tscn"
	const RELIC_SHOP_PATH := "res://scenes/ui/RelicShop.tscn"
	const RUN_PATH := "res://scenes/world/Run.tscn"

	## Frames que puede tardar un paso antes de contar como trabado. Holgado a
	## propósito: detecta CUELGUES, no mide tiempos. Dos pasos esperan tiempo de
	## partida real y lo dicen en STEP_DEADLINES.
	const STEP_DEADLINE_FRAMES: int = 600
	## Pasos que esperan el reloj de la partida, que avanza una vez por frame:
	## start_run pide run_time >= 10 (600 frames por sí solo) y retry pide >= 5,
	## así que el plazo por defecto saltaría en una partida SANA.
	const STEP_DEADLINES: Dictionary[String, int] = {
		"start_run": 1200,
		"retry": 900,
	}
	## Frames para que ScreenFade termine tras llegar a una escena. Su corte dura
	## FADE_IN_TIME 0.22 + FADE_OUT_TIME 0.26 = ~29 frames, y un clic que cae en
	## esa ventana se PIERDE en silencio.
	const FADE_SETTLE_FRAMES: int = 40
	## Tiempo de partida (segundos) que debe alcanzar la partida antes de que start_run / retry cuenten.
	const RUN_TIME_TARGET: float = 10.0
	const RETRY_TIME_TARGET: float = 5.0

	## Todos los pasos, en orden. Cada uno es un método _step_<name> que
	## devuelve true cuando terminó.
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
	## scene_file_path de la última escena que vio el driver, para que un cambio
	## dispare UNA sola espera del fundido y no una por sondeo.
	var _last_scene: String = ""
	## Personaje que compró el paso de desbloqueo; lo revisa el paso siguiente.
	var _unlock_id: String = ""
	## Acciones esperando su frame de liberación (ver _send_action).
	var _release: Array[StringName] = []

	## --- capturas -------------------------------------------------------
	## BONK_SHOT_DIR, la misma variable del arnés de soak y por la misma razón:
	## cada aserción de este archivo es sobre NODOS (un control que existe, es
	## visible, no está deshabilitado) y nada de eso ve un panel dibujado sobre
	## el reloj o un texto cortado. Se ignora con --headless, que es como lo
	## corre tools/verificar.sh, así que el gate no cambia.
	## Dos segundos, no diez: este arnés cruza siete pantallas en cerca de un
	## minuto y con diez segundos fotografiaría tres.
	const SHOT_EVERY_DEFAULT: float = 2.0
	var _camera: ShotCamera = null
	## El (paso, fase) de la última foto. Un paso no es una pantalla
	## (_visit_meta_screen abre Colección, la revisa y vuelve dentro de un solo
	## paso), así que la FASE es lo que cambia cuando cambiaría la imagen.
	var _shot_at: Vector2i = Vector2i(-1, -1)

	func _ready() -> void:
		_camera = ShotCamera.new(get_viewport(), SHOT_EVERY_DEFAULT)
		if OS.get_environment(SaveData.SAVE_PATH_ENV).is_empty():
			SaveData.save_path = FALLBACK_SAVE_PATH
			SaveData.load_from_disk()
			print("UiProbe: save path %s" % SaveData.save_path)
		SaveData.shards = SEEDED_SHARDS
		print("UiProbe: shards=%d" % SaveData.shards)
		get_tree().change_scene_to_file(CHARACTER_SELECT_PATH)

	func _process(delta: float) -> void:
		_flush_releases()
		_tick_shots(delta)
		if _failed:
			return
		# Una espera por CORTE: ScreenFade sigue fundiendo FADE_OUT_TIME sobre una
		# escena que el driver ya ve, y un clic en esa ventana se pierde sin rastro.
		var scene := get_tree().current_scene
		var path := scene.scene_file_path if scene != null else ""
		if path != _last_scene:
			_last_scene = path
			_settle = FADE_SETTLE_FRAMES
			return
		# Un level-up durante los pasos de partida pondría la UI de cartas sobre
		# todo y trabaría el probe igual que al arnés de soak; elige la opción 0
		# como lo hace ArenaProbe.
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
			_camera.final_shot()
			get_tree().quit(0)

	## Una foto cada vez que el driver pasa a un nuevo (paso, fase), o sea una
	## por PANTALLA, más la foto periódica de la cámara, que atrapa los fundidos
	## y las esperas entre medio.
	func _tick_shots(delta: float) -> void:
		if not _camera.enabled():
			return
		var at := Vector2i(_step, _phase)
		if at != _shot_at:
			_shot_at = at
			_camera.request("ui_%02d_%s_p%d" % [_step, STEPS[mini(_step,
					STEPS.size() - 1)], _phase])
		_camera.tick(delta, _periodic_shot_stem)

	func _periodic_shot_stem() -> String:
		return "ui_%02d_%s_t%d" % [_step, STEPS[mini(_step, STEPS.size() - 1)],
				Engine.get_frames_drawn()]

	func _deadline(step_name: String) -> int:
		return int(STEP_DEADLINES.get(step_name, STEP_DEADLINE_FRAMES))

	func _fail(reason: String) -> void:
		_failed = true
		push_error("UiProbe: %s" % reason)
		get_tree().quit(1)

	# --- pasos ---------------------------------------------------------

	func _step_collection() -> bool:
		return _visit_meta_screen(_unique_button("%CollectionButton"), COLLECTION_PATH)

	func _step_quests() -> bool:
		return _visit_meta_screen(_unique_button("%QuestsButton"), QUEST_LOG_PATH)

	func _step_relics() -> bool:
		return _visit_meta_screen(_unique_button("%ArmoryButton"), RELIC_SHOP_PATH)

	## La fila co-op rechaza un grupo más grande que los mandos conectados.
	## En headless no hay ninguno, así que 2 jugadores es siempre el camino de
	## rechazo; las filas de varios jugadores no se alcanzan aquí y las cubre
	## el soak co-op (BONK_PLAYERS=2).
	func _step_coop_count_reject() -> bool:
		match _phase:
			0:
				if not _at_scene(CHARACTER_SELECT_PATH):
					return false
				var button := _lobby_node("%Count2") as Button
				if button == null:
					_fail("no %Count2 button in %CoopLobby")
					return false
				if not _press(button, "co-op count 2"):
					return false
				_phase = 1
				return false
			_:
				# La pista es la única salida del camino de rechazo: la pantalla de
				# selección no toca Coop hasta Start, así que player_count leería 1
				# se aceptara o no el clic.
				var hint := _lobby_node("%CoopHint") as Label
				return hint != null and hint.text.find("Conecta") >= 0

	## Un raider bloqueado comprado con el flujo real de dos clics: la tarjeta
	## arma la confirmación en línea y el %UnlockYes («Sí») de la tarjeta la confirma.
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
				var yes := _visible_unlock_yes(card)
				if yes == null:
					return false  # la cara de confirmación aparece en el siguiente refresco
				if not _press(yes, "confirm «Sí» for %s" % _unlock_id):
					return false
				_phase = 2
				return false
			_:
				if not SaveData.is_unlocked(_unlock_id):
					_fail("raider '%s' is still locked after confirming" % _unlock_id)
					return false
				var card := _card_for(_unlock_id)
				if _visible_unlock_yes(card) != null:
					_fail("card '%s' still shows the confirm button after unlocking"
							% _unlock_id)
					return false
				return true

	## Cada tarjeta una vez, después del desbloqueo para que no quede ninguna
	## confirmación armada. Las bloqueadas que no alcanzan van por el camino de
	## rechazo y las desbloqueadas por el de selección: handlers que nada más corre.
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

	## El inicio real: %StartButton corre ScreenFade.transition, que REEMPLAZA
	## current_scene con la partida.
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

	## pause_game (Esc / Start) abre el menú de pausa por su propio
	## _unhandled_input, el único camino que existe: _open() es privado.
	## ui_cancel (B) no lo abre, solo lo cierra.
	func _step_pause_open() -> bool:
		match _phase:
			0:
				_send_action(&"pause_game", true)
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

	## El SettingsPanel compartido, abierto desde el %SettingsButton del menú de
	## PAUSA (la pantalla de selección tiene otro nodo con el mismo nombre único,
	## por eso cada % aquí se resuelve contra su owner). %FpsCheck es un
	## CheckButton: un clic cambia button_pressed, que es lo que emite `toggled`;
	## pressed.emit() no lo haría.
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
				# Preset gráfico: Media debe llegar al guardado y a la escala 3D del
				# viewport raíz, y Alta debe devolver exactamente la escala nativa 1.0.
				var medium := panel.get_node_or_null("%QualityMedium") as Button
				var high := panel.get_node_or_null("%QualityHigh") as Button
				if medium == null or high == null:
					_fail("no %QualityMedium / %QualityHigh under the settings panel")
					return false
				var quality_before := SaveData.graphics_quality
				medium.button_pressed = true
				if SaveData.graphics_quality != 1 or high.button_pressed \
						or not is_equal_approx(get_tree().root.scaling_3d_scale, 0.75):
					_fail("pressing %%QualityMedium left quality=%d scale=%.2f" % [
							SaveData.graphics_quality, get_tree().root.scaling_3d_scale])
					return false
				high.button_pressed = true
				if SaveData.graphics_quality != 0 \
						or not is_equal_approx(get_tree().root.scaling_3d_scale, 1.0):
					_fail("pressing %%QualityHigh left quality=%d scale=%.2f" % [
							SaveData.graphics_quality, get_tree().root.scaling_3d_scale])
					return false
				Settings.set_graphics_quality(quality_before)
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

	## Extraer por el grupo run_manager, la misma llamada que hace el botón del
	## menú de pausa. Lo que tiene que aparecer es la pantalla de fin.
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

	## Reintentar recarga la partida con ScreenFade.leave_run, el único ritual
	## dueño de la limpieza, el reinicio y el cambio de escena.
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

	## Nada que apretar: el último paso existe para que la partida termine en
	## una línea de paso como las demás, y para que la cuenta del resumen sea la
	## que busca verificar.sh.
	func _step_done() -> bool:
		return true

	# --- ayudantes -----------------------------------------------------

	## True cuando current_scene ES esa escena. El fundido tras un corte se
	## espera en _process, una vez por cambio.
	func _at_scene(scene_path: String) -> bool:
		var scene := get_tree().current_scene
		return scene != null and scene.scene_file_path == scene_path

	## Abre una pantalla meta, revisa que llegó y vuelve por su propio
	## %BackButton. Las tres comparten meta_screen.gd, así que una forma cubre
	## Colección, Misiones y Armería.
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

	## pressed.emit() se salta `disabled` y la visibilidad, así que un arnés que
	## solo emite prueba que el handler corre, no que un jugador pueda llegar a
	## él. Ambas cosas se afirman antes.
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

	## Un nombre único en la raíz de la escena ACTUAL, que es su owner.
	func _unique(unique_name: String) -> Node:
		var scene := get_tree().current_scene
		if scene == null:
			return null
		return scene.get_node_or_null(unique_name)


	## Igual, pero como Button. Va separado de _unique porque %CardsGrid es un
	## GridContainer: un ayudante tipado Button devolvería null y se leería como
	## "la grilla está vacía" en vez de "tipo equivocado".
	func _unique_button(unique_name: String) -> Button:
		return _unique(unique_name) as Button

	## Un nodo único dentro de la instancia %CoopLobby de la pantalla de
	## selección (sus nodos pertenecen a la escena del lobby, no a la de selección).
	func _lobby_node(unique_name: String) -> Node:
		var lobby := _unique("%CoopLobby")
		if lobby == null:
			return null
		return lobby.get_node_or_null(unique_name)

	## El %UnlockYes de la tarjeta mientras muestra la confirmación, si no null
	## (toda tarjeta tiene el botón; solo la cara de confirmación lo muestra).
	func _visible_unlock_yes(card: Button) -> Button:
		if card == null:
			return null
		var yes := card.get_node_or_null("%UnlockYes") as Button
		if yes == null or not yes.is_visible_in_tree():
			return null
		return yes

	## El raider bloqueado más barato que este saldo puede comprar.
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

	## La grilla tiene un Button por fila de CHARACTER_LIBRARY, en orden.
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

	## Una UI de cartas de level-up pausaría el árbol sobre todo lo demás; el
	## arnés de soak la responde igual.
	func _serve_card_ui() -> void:
		for node: Node in get_tree().get_nodes_in_group("upgrade_ui"):
			var ui := node as CanvasLayer
			if ui != null and ui.visible and ui.has_method("_on_card_pressed"):
				ui.call("_on_card_pressed", 0)

	## Un InputEventAction, liberado en un frame POSTERIOR como lo haría un
	## jugador: con ambos en el mismo vaciado, Input.is_action_just_pressed
	## nunca vería la pulsación.
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
