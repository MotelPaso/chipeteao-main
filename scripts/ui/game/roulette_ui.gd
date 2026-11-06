extends CanvasLayer
## Menú de la ruleta, creado por un RouletteShrine: pausa el árbol (contrato
## "ui_blocking", capa entre las cartas y la pantalla de fin), lista todos los
## resultados y, al GIRAR, hace un barrido tipo tragamonedas antes de que caiga
## el resultado real (ya sorteado y aplicado). Salir o Esc quitan la pausa.
##
## Pausa segura: esta capa tiene todo el árbol pausado, así que nunca puede
## sobrevivir a su dueño. Se cierra sola si el raider que la abrió, o el altar al
## que pertenece (al desmontar la etapa), desaparece; expone dismiss() para
## cerrarla desde código (grupo "blocking_ui_closable"); y sin pantalla
## (headless) juega sola: un soak no tiene quien presione GIRAR, y una ruleta
## esperando para siempre congela la partida. La pausa también se suelta desde
## _exit_tree, así que un panel liberado en vez de cerrado devuelve el árbol
## igual; y, como el selector de cartas, nunca suelta una pausa que tomó otra
## capa bloqueante.

## Segundos que dura el barrido completo del resaltado; las esperas entre saltos
## se derivan de este valor.
@export var sweep_time: float = 1.4
## Saltos del resaltado en un giro (mínimo 2).
@export var sweep_steps: int = 22

## Forma del frenado: los últimos saltos duran ~4.6 veces más que los primeros.
const SWEEP_EASE_MIN := 0.03
const SWEEP_EASE_MAX := 0.14

const DIM_COLOR := Color(0.03, 0.03, 0.05, 0.75)
const ROW_SIZE := Vector2(260.0, 26.0)
const ROW_BG := Color(0.07, 0.075, 0.11, 0.9)
const SPIN_BUTTON_SIZE := Vector2(200.0, 46.0)
const CLOSE_BUTTON_SIZE := Vector2(140.0, 46.0)
const HIGHLIGHT_ON := Color(1.6, 1.5, 1.2)
const HIGHLIGHT_OFF := Color(1.0, 1.0, 1.0, 0.55)

## Juego sin pantalla: gira una vez, muestra el resultado y se va (segundos).
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
## true solo entre el _ready que pausó el árbol y la liberación que lo devuelve
## (la regla de _pause_owned de pause_menu.gd). El cierre y el respaldo de
## _exit_tree pasan por aquí, así que la pausa se suelta una sola vez y un panel
## que nunca llegó a pausar no suelta nada.
var _pause_held: bool = false


## DEBE llamarse antes de add_child(): _ready arma el panel con el precio del
## altar y los puntos del raider.
func setup(shrine: RouletteShrine, player: Node) -> void:
	_shrine = shrine
	_player = player


func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Nada que vigilar (ni pausa propia que soltar) hasta que el panel está
	# arriba.
	set_process(false)
	if _shrine == null or not is_instance_valid(_player):
		push_error("RouletteUi: setup() must run before add_child()")
		queue_free()
		return
	add_to_group(BlockingUi.GROUP)
	add_to_group(BlockingUi.CLOSABLE_GROUP)
	_build()
	get_tree().paused = true
	_pause_held = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	set_process(true)
	if DisplayServer.get_name() == "headless":
		_auto_play()


## Contrato de PauseMenu/UpgradeCardUi ("ui_blocking"): true mientras esta capa
## es dueña de la pausa. Es false apenas queda en cola para borrarse: el nodo
## sigue en el grupo hasta que la cola de borrado se vacía al final del frame, y
## una ruleta que se va y contesta "sí" hace que el selector de cartas (o un
## cambio de etapa) se salte su propia quita de pausa en ese frame.
func is_blocking() -> bool:
	return not is_queued_for_deletion()


## Cierre desde código (harness de soak, desmontaje). A mitad de un giro espera:
## el resultado ya está aplicado y solo falta mostrarlo.
func dismiss() -> void:
	if _spinning:
		return
	_close()


## Con el árbol pausado nada más puede notar que el raider que abrió la ruleta
## ya no está (caída de todo el grupo en co-op), o que el altar se fue con la
## etapa. No quedaría nadie para presionar Salir y la pausa duraría más que la
## partida. Se revisan ambas referencias, como en el panel del vendedor: el
## precio y el giro se leen del altar, así que una ruleta sin altar ya no tiene
## nada que vender.
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
		row.text = "  " + RouletteShrine.outcome_label(outcome)
		row.custom_minimum_size = ROW_SIZE
		var color := RouletteShrine.outcome_color(outcome)
		var tint := color.lightened(0.15)
		row.add_theme_color_override("font_color", tint)
		UiTheme.style_badge(row, tint, ROW_BG, Color(color, 0.4))
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
	# Indicaciones de botón bajo los botones; siguen al último dispositivo usado.
	box.add_child(InputHints.build([["ui_accept", "Elegir"], ["ui_cancel", "Salir"]]))
	_spin_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _spinning:
		_close()
		get_viewport().set_input_as_handled()


## GIRAR queda deshabilitado durante todo el barrido: un botón que parece
## presionable y se traga el clic en silencio es peor que uno en gris.
func _refresh_points() -> void:
	_points_label.text = "Tienes %d pts" % int(_player.get("points"))
	if _spin_button != null:
		# El precio se duplica con cada giro, así que la etiqueta se vuelve a
		# leer aquí en vez de fijarse una vez al armar el panel.
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
	# Limpia el giro anterior antes de empezar: la ruleta se reusa, y una línea
	# de resultado y un resaltado viejos seguirían en pantalla durante el nuevo
	# barrido.
	_result_label.text = ""
	for row: Label in _rows:
		row.modulate = Color.WHITE
	_close_button.disabled = true
	_refresh_points()
	Sfx.play(&"card_pick")
	_sweep_to(outcome)


## Barrido tipo tragamonedas: el resaltado salta entre filas, frenando, y se
## detiene en el resultado real. Corre en esta capa ALWAYS e ignora la escala de
## tiempo.
func _sweep_to(outcome: Dictionary) -> void:
	var target := _row_index(String(outcome.id))
	if target < 0:
		# Caer en cualquier lado contradiría la línea de resultado que viene, y
		# una ruleta que miente es peor que ninguna animación.
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


## Esperas de salto con frenado, normalizadas para que sumen sweep_time: eso es
## lo que le da sentido al valor exportado.
func _sweep_delays(steps: int) -> PackedFloat32Array:
	var delays := PackedFloat32Array()
	var total := 0.0
	for step in steps:
		var t := float(step) / float(steps - 1)
		var weight := lerpf(SWEEP_EASE_MIN, SWEEP_EASE_MAX, t * t)
		delays.append(weight)
		total += weight
	var delay_scale := maxf(sweep_time, 0.1) / maxf(total, 0.001)
	for i in delays.size():
		delays[i] *= delay_scale
	return delays


func _highlight(index: int) -> void:
	for i in _rows.size():
		_rows[i].modulate = HIGHLIGHT_ON if i == index else HIGHLIGHT_OFF
	Sfx.play(&"hit_soft")


func _land(outcome: Dictionary) -> void:
	_spinning = false
	_result_label.text = "▶ %s" % RouletteShrine.outcome_label(outcome)
	_result_label.add_theme_color_override("font_color",
			RouletteShrine.outcome_color(outcome).lightened(0.2))
	UiTheme.pop(_result_label, 1.3, 0.3)
	Sfx.play(&"shrine_done")
	_close_button.disabled = false
	_refresh_points()
	_close_button.grab_focus()


## Los soaks (y toda corrida sin pantalla) no tienen manos: gira una vez y se
## va, así el árbol pausado siempre se devuelve.
func _auto_play() -> void:
	await get_tree().create_timer(HEADLESS_SPIN_DELAY, true, false, true).timeout
	if not is_inside_tree():
		return
	_on_spin()
	await get_tree().create_timer(HEADLESS_LEAVE_DELAY, true, false, true).timeout
	if is_inside_tree():
		_close()


## Protegido porque varios caminos pueden llegar aquí (Esc, el botón Salir, el
## respaldo de salida sin pantalla, el vigía de arriba) y la pausa debe soltarse
## una sola vez, por el primero que llegue.
func _close() -> void:
	if is_queued_for_deletion():
		return
	_release_pause()
	queue_free()


## Devuelve el árbol como máximo una vez, y solo si la pausa es NUESTRA (regla
## de upgrade_card_ui.gd). Un giro puede poner otra capa "ui_blocking" en
## pantalla, y la partida puede terminar debajo de este panel, en cuyo caso la
## pantalla de fin es dueña de la pausa y del mouse: quitar la pausa en
## cualquiera de los dos casos reanudaría el mundo detrás del modal de otro y le
## quitaría el mouse a sus botones.
func _release_pause() -> void:
	if not _pause_held:
		return
	_pause_held = false
	if not RunState.run_active or BlockingUi.other_open(get_tree(), self):
		return
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## _close() es el único camino que quita la pausa, así que un panel LIBERADO en
## vez de cerrado (free() desde un harness, el padre de la etapa que se va con
## un cambio de etapa) dejaría un árbol pausado sin nada en pantalla que lo
## suelte.
func _exit_tree() -> void:
	_release_pause()
