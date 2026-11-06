class_name MetaScreen
extends Control
## Chasis compartido de las tres pantallas entre partidas (Registro de
## misiones, Armería, Colección): son la misma pantalla con distintas filas.
## Mismo fondo de niebla, mismo título ámbar espaciado, misma insignia, mismo
## botón Volver, misma entrada escalonada y, en las dos que gastan o ganan
## esquirlas, el mismo conteo animado. Todo lo que NO es contenido de filas
## vive aquí, así un arreglo llega a las tres a la vez.
##
## Contrato de escena (QuestLog.tscn / RelicShop.tscn / Collection.tscn):
## %TitleLabel, %BadgeLabel, %List (VBoxContainer dentro de un
## ScrollContainer) y %BackButton. El texto del título vive en la escena.
##
## Ganchos de las subclases: _badge_color(), _tracks_shards() y
## _build_rows(list). Momentos compartidos que llama una subclase: payoff()
## (reclamar / comprar), reject() (no alcanza) y rebuild().

## Destello de la fila (modulate) al pagar.
const PAYOFF_FLASH := Color(1.7, 1.45, 0.85)
## Margen interno (píxeles) de la tarjeta de cada fila: lados y arriba/abajo.
const CARD_MARGIN_H := 16.0
const CARD_MARGIN_V := 10.0
## Solo animan su entrada las filas que caben en pantalla; una lista de 40
## filas se abriría como una presentación de diapositivas.
const ENTRANCE_ROWS := 8
## Duración (segundos) del conteo del saldo.
const COUNT_TIME := 0.4
## Píxeles que se desplaza la lista con ui_up / ui_down cuando no hay un
## botón de fila al que mover el foco (ver _input).
const SCROLL_STEP := 110

@onready var _title_label: Label = %TitleLabel
@onready var _badge_label: Label = %BadgeLabel
@onready var _list: VBoxContainer = %List
@onready var _back_button: Button = %BackButton
## El ScrollContainer de la lista (toda escena MetaScreen pone %List en uno).
@onready var _scroll: ScrollContainer = _list.get_parent() as ScrollContainer

var _count_tween: Tween = null


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	UiTheme.style_title(_title_label, 40, UiTheme.ACCENT_AMBER, 8, 10)
	var badge := _badge_color()
	UiTheme.style_badge(_badge_label, badge, UiTheme.PANEL_BG, badge.darkened(0.45))
	_badge_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiTheme.style_button(_back_button, UiTheme.ACCENT, true)
	_back_button.pressed.connect(_on_back_pressed)
	# Indicaciones de botones bajo Volver; siguen al último dispositivo usado.
	_back_button.get_parent().add_child(InputHints.build([
			["ui_accept", "Elegir"], ["ui_cancel", "Volver"]]))
	if _scroll != null:
		# Un control que recorre los botones de las filas debe ver el enfocado.
		_scroll.follow_focus = true
	if _tracks_shards():
		SaveData.shards_changed.connect(_on_shards_changed)
		refresh_badge()
	rebuild()
	play_entrance()
	_back_button.grab_focus()


func _exit_tree() -> void:
	# SaveData sobrevive a cada pantalla: la conexión se va con nosotros.
	if SaveData.shards_changed.is_connected(_on_shards_changed):
		SaveData.shards_changed.disconnect(_on_shards_changed)


## Esc sale, igual que en el resto del juego (la pausa, los ajustes y la
## ruleta también lo respetan).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


## Desplazamiento con control o flechas. El foco solo recorre BOTONES y la
## mayoría de las filas no tiene ninguno (toda la Colección, cada misión sin
## reclamar), así que arriba/abajo desplazan la lista cuando mover el foco se
## saltaría filas que siguen fuera de vista:
##   - una lista sin botones: siempre (Volver conserva el foco);
##   - abajo desde el ÚLTIMO botón de fila / arriba desde el PRIMERO: mientras
##     quede lista en esa dirección; después sigue hacia Volver.
## Corre en _input, antes de que la GUI mueva el foco, para tomar la
## pulsación primero.
func _input(event: InputEvent) -> void:
	if _scroll == null or not is_visible_in_tree():
		return
	var direction := 0
	if event.is_action_pressed("ui_down", true):
		direction = 1
	elif event.is_action_pressed("ui_up", true):
		direction = -1
	if direction == 0 or not _can_scroll(direction):
		return
	var buttons := _row_buttons()
	var focus_owner := get_viewport().gui_get_focus_owner()
	var at_list_edge: bool = buttons.is_empty() \
			or (direction == 1 and focus_owner == buttons.back()) \
			or (direction == -1 and focus_owner == buttons.front())
	if at_list_edge:
		_scroll.scroll_vertical += direction * SCROLL_STEP
		get_viewport().set_input_as_handled()


func _can_scroll(direction: int) -> bool:
	var bar := _scroll.get_v_scroll_bar()
	if direction > 0:
		return _scroll.scroll_vertical < int(bar.max_value - bar.page)
	return _scroll.scroll_vertical > 0


func _on_back_pressed() -> void:
	ScreenFade.transition(func() -> void:
		get_tree().change_scene_to_file(ScenePaths.CHARACTER_SELECT))


# --- insignia ---------------------------------------------------------

func refresh_badge() -> void:
	set_badge_count(SaveData.shards)


func set_badge_count(value: int) -> void:
	_badge_label.text = UiTheme.SHARDS_BALANCE % value


## El aviso de saldo llega en forma síncrona desde claim_quest /
## purchase_relic, es decir, ANTES de que empiece el conteo: repintar con él
## mostraría el número final un frame y luego saltaría atrás a contar.
func _on_shards_changed(_balance: int) -> void:
	if _count_tween != null and _count_tween.is_valid():
		return
	refresh_badge()


func _count_balance(before: int, after: int) -> void:
	set_badge_count(before)  # parte del valor viejo, nunca del nuevo
	if _count_tween != null and _count_tween.is_valid():
		_count_tween.kill()
	_count_tween = create_tween()
	_count_tween.set_ignore_time_scale(true)
	_count_tween.tween_method(_set_badge_step, float(before), float(after), COUNT_TIME)
	_count_tween.tween_callback(refresh_badge)  # termina en el saldo real
	UiTheme.pop(_badge_label, 1.2, 0.3)


func _set_badge_step(value: float) -> void:
	set_badge_count(int(value))


# --- momentos compartidos ---------------------------------------------

## El momento de pago (reclamar una misión, comprar un rango): cuenta el
## saldo hacia arriba o abajo, hace destellar la fila en oro y reordena la
## lista cuando termina el destello.
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


## Vaivén de "no alcanza". Un tween por fila guardado en la metadata:
## insistir en el botón lo reinicia en vez de apilar tweens que escriben la
## misma rotación y modulate.
func reject(row: Control) -> void:
	if not is_instance_valid(row):
		return
	row.pivot_offset = row.size * 0.5
	UiTheme.kill_meta_tween(row, &"ui_reject_tween")
	row.rotation_degrees = 0.0
	row.modulate = Color.WHITE
	var tween := create_tween()
	tween.set_ignore_time_scale(true)
	tween.tween_property(row, "modulate", UiTheme.REJECT_FLASH, 0.06)
	tween.parallel().tween_property(row, "rotation_degrees", -2.0, 0.05)
	tween.tween_property(row, "rotation_degrees", 2.0, 0.08)
	tween.tween_property(row, "rotation_degrees", 0.0, 0.07)
	tween.parallel().tween_property(row, "modulate", Color.WHITE, 0.18)
	row.set_meta(&"ui_reject_tween", tween)


## remove_child ANTES de queue_free: un hijo liberado este frame sigue en el
## contenedor hasta que termina el frame, así que agregar primero las filas
## nuevas duplicaría la altura del contenedor un frame y haría saltar el
## ScrollContainer lejos de la fila que el jugador acaba de usar.
##
## El foco sobrevive a la reconstrucción: el botón que un control acaba de
## presionar (Comprar, Reclamar) está en una de las filas liberadas, y sin
## esto el foco moriría con ella.
func rebuild() -> void:
	var focused_slot := -1
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner is Button:
		focused_slot = _row_buttons().find(focus_owner as Button)
	for child: Node in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	_build_rows(_list)
	var buttons := _link_row_focus()
	if focused_slot >= 0:
		if buttons.is_empty():
			_back_button.grab_focus()
		else:
			buttons[mini(focused_slot, buttons.size() - 1)].grab_focus()


## Todos los botones de las filas (Comprar, Reclamar), de arriba abajo.
func _row_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	for node: Node in _list.find_children("*", "Button", true, false):
		var button := node as Button
		if button.focus_mode != Control.FOCUS_NONE:
			buttons.append(button)
	return buttons


## Encadena los botones de las filas y Volver en un ciclo para el control:
## abajo recorre las filas en orden y termina en Volver, arriba desde Volver
## va a la última fila. Con la búsqueda automática de Godot, la última fila
## (medio oculta bajo el borde de la lista) pierde contra Volver, que queda
## más cerca en pantalla, y nunca se alcanza.
func _link_row_focus() -> Array[Button]:
	var buttons := _row_buttons()
	if buttons.is_empty():
		_back_button.focus_neighbor_top = NodePath()
		_back_button.focus_neighbor_bottom = NodePath()
		return buttons
	var loop: Array[Control] = []
	loop.append_array(buttons)
	loop.append(_back_button)
	for i in loop.size():
		var here := loop[i]
		here.focus_neighbor_top = here.get_path_to(loop[(i - 1 + loop.size()) % loop.size()])
		here.focus_neighbor_bottom = here.get_path_to(loop[(i + 1) % loop.size()])
	return buttons


## Aparición escalonada de las primeras filas. Sale antes con la lista vacía:
## un Tween sin tweeners avisa por stderr y los soaks buscan eso.
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


# --- cromo compartido de las filas ------------------------------------

## El aspecto de tarjeta de toda fila de las tres pantallas: cuerpo
## redondeado, borde de 2 px en el acento y brillo opcional para los estados
## "ganados".
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


# --- ganchos de las subclases -----------------------------------------

## Color de la insignia (y de su texto). Azul de esquirla por defecto.
func _badge_color() -> Color:
	return UiTheme.SHARD_BLUE


## False en las pantallas cuya insignia no es un saldo de esquirlas (la
## Colección escribe su propio porcentaje al reconstruir).
func _tracks_shards() -> bool:
	return true


## Llena la lista. Se llama al abrir y después de cada pago.
func _build_rows(_list_node: VBoxContainer) -> void:
	pass
