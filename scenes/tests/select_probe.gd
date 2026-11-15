extends Node
## Arnés headless del selector de personaje. UiProbe aprieta sus botones; este
## mide lo que UiProbe no ve: que la pantalla quepa y se pueda recorrer con
## control en cada forma de ventana. Abre CharacterSelect.tscn en cada tamaño
## de WINDOWS y revisa:
##   - layout: ningún texto ni botón sale de la pantalla, ningún texto queda
##     cortado y todas las cartas se ven sin desplazar (con holgura para la
##     fila de slots de co-op, que headless no puede abrir: no hay controles);
##   - focus: con el control se llega a todos los botones desde Iniciar y a
##     Iniciar desde todos; cada carta llega a Iniciar por la derecha, a las
##     pantallas meta por abajo y al lobby co-op por arriba;
##   - detail: al enfocar cada carta el panel de detalle muestra ese raider,
##     con su cuerpo 3D si su modelo existe y con la inicial si no;
##   - unlock: la carta que pide confirmar baja a su «Sí» y de ahí se sale.
##
## Se corre solo con:
##   godot --headless --fixed-fps 60 --quit-after 3600 \
##     res://scenes/tests/SelectProbe.tscn
##
## Contrato de salida (tools/verificar.sh busca cada línea):
##   SelectProbe: size <ancho>x<alto> ok ...   una por tamaño de WINDOWS
##   SelectProbe: done sizes=%d                solo si pasaron todos
## Cualquier falla es un push_error, que PATRON_ERROR atrapa por sí solo.
##
## Con BONK_SHOT_DIR y sin --headless guarda una captura por tamaño, una de
## la confirmación de desbloqueo y, en la primera ventana, una por raider.

const SELECT_SCENE: PackedScene = preload("res://scenes/ui/CharacterSelect.tscn")
## Guardado de respaldo si BONK_SAVE_PATH no está definido, para que un probe
## corrido a mano nunca toque el progreso del jugador.
const FALLBACK_SAVE_PATH := "user://select_probe_save.json"
## Esquirlas para que una carta bloqueada pueda pedir confirmación.
const SEEDED_SHARDS: int = 200
## Ventanas a probar. Con el estirado del proyecto (lienzo 1280x720, aspecto
## "expand") dan: 16:9 = 1280x720, MacBook 16:10 = 1280x831, 4:3 = 1280x960,
## ultrawide 21:9 = 1706x720.
const WINDOWS: Array[Vector2i] = [
	Vector2i(1280, 720), Vector2i(1512, 982), Vector2i(1024, 768), Vector2i(2560, 1080),
]
## Frames de espera: a que la ventana aplique su tamaño, a que termine la
## entrada escalonada y a que un cambio de foco llegue al detalle.
const RESIZE_FRAMES: int = 4
const ENTRANCE_FRAMES: int = 70
const FOCUS_FRAMES: int = 2
## Tope de frames esperando que el hilo de carga entregue los modelos 3D.
const MODEL_LOAD_FRAMES: int = 600
## Alto (píxeles) que la fila de slots de co-op le quita a la cuadrícula.
const COOP_ROW_HEIGHT: float = 48.0
## Tolerancia (píxeles) al comparar rectángulos.
const SLACK: float = 0.75
const SHOT_DIR_ENV := "BONK_SHOT_DIR"

var _failed: bool = false
var _select: Control = null


func _ready() -> void:
	if OS.get_environment(SaveData.SAVE_PATH_ENV).is_empty():
		SaveData.save_path = FALLBACK_SAVE_PATH
		SaveData.load_from_disk()
	SaveData.shards = SEEDED_SHARDS
	_run.call_deferred()


func _run() -> void:
	for window: Vector2i in WINDOWS:
		await _probe_window(window)
		if _failed:
			get_tree().quit(1)
			return
	print("SelectProbe: done sizes=%d" % WINDOWS.size())
	get_tree().quit(0)


func _probe_window(window: Vector2i) -> void:
	get_tree().root.size = window
	await _frames(RESIZE_FRAMES)
	_select = SELECT_SCENE.instantiate() as Control
	add_child(_select)
	await _frames(ENTRANCE_FRAMES)
	var canvas := Vector2i(_select.size)
	var where := "%dx%d" % [canvas.x, canvas.y]
	var cards := _cards()
	if cards.is_empty():
		_fail(where, "no cards in %CardsGrid")
	_check_layout(where)
	_check_cards_fit(where, cards)
	var focusables := _check_focus(where, cards)
	# Una captura por raider solo en la primera ventana: alcanza para revisar
	# el encuadre de cada cuerpo 3D.
	var models := await _check_details(where, cards, window == WINDOWS[0])
	await _check_unlock(where, cards)
	await _shoot(where)
	if not _failed:
		print("SelectProbe: size %s ok cards=%d columns=%d focusables=%d models=%d" % [
				where, cards.size(), (_node("%CardsGrid") as GridContainer).columns,
				focusables, models])
	_select.queue_free()
	_select = null
	await _frames(RESIZE_FRAMES)


# --- comprobaciones ----------------------------------------------------------

## Ningún texto ni botón visible sale de la pantalla ni queda cortado, y
## ningún contenedor recibe menos espacio que el mínimo de su contenido.
func _check_layout(where: String) -> void:
	var screen := _select.get_global_rect().grow(SLACK)
	var settings := _node("%SettingsPanel")
	for node: Node in _select.find_children("*", "Control", true, false):
		var control := node as Control
		if not control.is_visible_in_tree() or settings.is_ancestor_of(control):
			continue
		var label := control as Label
		var button := control as Button
		if label != null and not label.text.is_empty():
			if not screen.encloses(label.get_global_rect()):
				_fail(where, "label off screen: %s" % _select.get_path_to(label))
			if label.autowrap_mode != TextServer.AUTOWRAP_OFF:
				if label.get_visible_line_count() < label.get_line_count():
					_fail(where, "label text cut: %s '%s'" % [
							_select.get_path_to(label), label.text])
			elif label.get_minimum_size().x > label.size.x + SLACK:
				_fail(where, "label too narrow: %s '%s'" % [
						_select.get_path_to(label), label.text])
		elif button != null:
			if not screen.encloses(button.get_global_rect()):
				_fail(where, "button off screen: %s" % _select.get_path_to(button))
			if button.get_minimum_size().x > button.size.x + SLACK:
				_fail(where, "button text cut: %s '%s'" % [
						_select.get_path_to(button), button.text])
		elif control is Container:
			var needed := control.get_combined_minimum_size()
			if needed.x > control.size.x + SLACK or needed.y > control.size.y + SLACK:
				_fail(where, "container overflows: %s needs %s has %s" % [
						_select.get_path_to(control), needed, control.size])


## Todas las cartas se ven sin desplazar la cuadrícula, y seguirían entrando
## con la fila de slots de co-op abierta.
func _check_cards_fit(where: String, cards: Array[CharacterCard]) -> void:
	var scroll := _node("%ContentScroll") as ScrollContainer
	var view := scroll.get_global_rect().grow(SLACK)
	for card: CharacterCard in cards:
		if not view.encloses(card.get_global_rect()):
			_fail(where, "card '%s' needs scrolling" % card.character_id)
	var pad := _node("%GridPad") as Control
	if pad.get_combined_minimum_size().y + COOP_ROW_HEIGHT > scroll.size.y + SLACK:
		_fail(where, "grid would scroll with the co-op slot row open (%s + %s > %s)" % [
				pad.get_combined_minimum_size().y, COOP_ROW_HEIGHT, scroll.size.y])


## Recorre el foco como lo haría el control (find_valid_focus_neighbor es la
## misma búsqueda que usan ui_left/right/up/down). Devuelve cuántos botones
## enfocables hay.
func _check_focus(where: String, cards: Array[CharacterCard]) -> int:
	var start := _node("%StartButton") as Button
	var settings := _node("%SettingsPanel")
	var focusables: Array[Control] = []
	for node: Node in _select.find_children("*", "BaseButton", true, false):
		var control := node as Control
		if control.is_visible_in_tree() and control.focus_mode == Control.FOCUS_ALL \
				and not settings.is_ancestor_of(control):
			focusables.append(control)
	var from_start := _reachable(start)
	for control: Control in focusables:
		if not from_start.has(control):
			_fail(where, "pad cannot reach %s from Start" % _select.get_path_to(control))
		if not _reachable(control).has(start):
			_fail(where, "pad cannot reach Start from %s" % _select.get_path_to(control))
	var meta_row := _node("%ButtonRow")
	var lobby := _node("%CoopLobby")
	var columns := (_node("%CardsGrid") as GridContainer).columns
	for i in cards.size():
		var card := cards[i]
		if _walk(card, SIDE_RIGHT, func(c: Control) -> bool: return c == start) == null:
			_fail(where, "card '%s' does not reach Start going right" % card.character_id)
		if _walk(card, SIDE_BOTTOM, meta_row.is_ancestor_of) == null:
			_fail(where, "card '%s' does not reach the meta row going down"
					% card.character_id)
		if i < columns and _walk(card, SIDE_TOP, lobby.is_ancestor_of) == null:
			_fail(where, "card '%s' does not reach the co-op lobby going up"
					% card.character_id)
	return focusables.size()


## Enfoca cada carta y revisa que el panel de detalle la siga, que su texto
## quepa y que el retrato muestre el cuerpo 3D exactamente cuando el modelo
## de la fila existe. Devuelve cuántos raiders mostraron cuerpo 3D.
func _check_details(where: String, cards: Array[CharacterCard],
		shoot_each: bool) -> int:
	var detail := _node("%CharacterDetail") as CharacterDetail
	var portrait := detail.portrait()
	var models := 0
	for card: CharacterCard in cards:
		var row := CharacterCatalog.by_id(card.character_id)
		card.grab_focus()
		await _frames(FOCUS_FRAMES)
		if detail.character_id != card.character_id:
			_fail(where, "detail shows '%s' with card '%s' focused" % [
					detail.character_id, card.character_id])
			continue
		var model_scene := String(row.get("model_scene", ""))
		var expects_model := model_scene.is_empty() \
				or ResourceLoader.exists(model_scene, "PackedScene")
		var waited := 0
		while expects_model and not portrait.shows_model() and waited < MODEL_LOAD_FRAMES:
			await get_tree().process_frame
			waited += 1
		if portrait.shows_model() != expects_model:
			_fail(where, "portrait of '%s' shows_model=%s, expected %s" % [
					card.character_id, portrait.shows_model(), expects_model])
		if portrait.shows_model():
			models += 1
		if not card.tooltip_text.contains(String(row.get("blurb", ""))):
			_fail(where, "tooltip of '%s' lost its full text" % card.character_id)
		_check_layout("%s focus=%s" % [where, card.character_id])
		if shoot_each:
			await _shoot("%s_%s" % [where, card.character_id])
	(_node("%StartButton") as Button).grab_focus()
	await _frames(FOCUS_FRAMES)
	if detail.character_id != GameConfig.selected_character_id:
		_fail(where, "detail did not return to the picked raider on Start")
	return models


## La confirmación de desbloqueo dentro de la carta: aparece el «Sí», se baja
## a él desde la carta, de ahí se llega a Iniciar y su texto cabe. Un segundo
## clic la cancela (la compra real la cubre UiProbe).
func _check_unlock(where: String, cards: Array[CharacterCard]) -> void:
	var locked: CharacterCard = null
	for card: CharacterCard in cards:
		var cost := int(CharacterCatalog.by_id(card.character_id).get("unlock_cost", 0))
		if not SaveData.is_unlocked(card.character_id) and SaveData.can_afford(cost):
			locked = card
			break
	if locked == null:
		_fail(where, "no locked raider is affordable with %d shards" % SaveData.shards)
		return
	locked.grab_focus()
	locked.pressed.emit()
	await _frames(FOCUS_FRAMES)
	var yes := locked.unlock_button()
	if yes == null or not yes.is_visible_in_tree():
		_fail(where, "card '%s' shows no confirm button" % locked.character_id)
		return
	if locked.find_valid_focus_neighbor(SIDE_BOTTOM) != yes:
		_fail(where, "card '%s' does not go down to its confirm button" % locked.character_id)
	if not _reachable(yes).has(_node("%StartButton")):
		_fail(where, "pad cannot reach Start from the confirm button")
	_check_layout("%s confirm=%s" % [where, locked.character_id])
	await _shoot("%s_confirm" % where)
	locked.pressed.emit()
	await _frames(FOCUS_FRAMES)
	if locked.unlock_button() != null:
		_fail(where, "second press did not cancel the confirm face")


# --- ayudantes -----------------------------------------------------------------

func _fail(where: String, reason: String) -> void:
	_failed = true
	push_error("SelectProbe: %s: %s" % [where, reason])


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


## Un nombre único de CharacterSelect.tscn.
func _node(unique_name: String) -> Node:
	return _select.get_node(unique_name)


func _cards() -> Array[CharacterCard]:
	var cards: Array[CharacterCard] = []
	for child: Node in _node("%CardsGrid").get_children():
		if child is CharacterCard:
			cards.append(child as CharacterCard)
	return cards


## Todos los controles a los que llega el foco desde `from` con las cuatro
## direcciones.
func _reachable(from: Control) -> Dictionary[Control, bool]:
	var seen: Dictionary[Control, bool] = {from: true}
	var queue: Array[Control] = [from]
	while not queue.is_empty():
		var current: Control = queue.pop_back()
		for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			var next := current.find_valid_focus_neighbor(side)
			if next != null and not seen.has(next):
				seen[next] = true
				queue.append(next)
	return seen


## Avanza el foco hacia `side` desde `from` hasta que `arrived` acepte un
## control; null si se atasca antes.
func _walk(from: Control, side: Side, arrived: Callable) -> Control:
	var current := from
	for step in 32:
		var next := current.find_valid_focus_neighbor(side)
		if next == null or next == current:
			return null
		if arrived.call(next):
			return next
		current = next
	return null


## Captura de la pantalla actual (solo con BONK_SHOT_DIR y con ventana real:
## el servidor headless no dibuja nada).
func _shoot(stem: String) -> void:
	var dir := OS.get_environment(SHOT_DIR_ENV).strip_edges()
	if dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(dir)
	await _frames(20)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(
			dir.path_join("select_%s.png" % stem))
