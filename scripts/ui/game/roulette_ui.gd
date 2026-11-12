class_name RouletteUi
extends ModalPanel
## Menú de la ruleta (RoulettePanel.tscn), abierto por un RouletteShrine: lista
## todos los resultados y, al GIRAR, hace un barrido tipo tragamonedas antes de
## que caiga el resultado real (ya sorteado y aplicado por el altar). La pausa,
## el cierre y el juego sin pantalla los maneja ModalPanel; mientras el barrido
## corre, Esc y dismiss() esperan.

@export_group("Barrido")
## Segundos que dura el barrido completo del resaltado; las esperas entre saltos
## se derivan de este valor.
@export var sweep_time: float = 1.4
## Saltos del resaltado en un giro (mínimo 2).
@export var sweep_steps: int = 22
## Peso relativo del primer salto; con el del último da la forma del frenado.
@export var sweep_first_hop: float = 0.03
## Peso relativo del último salto (con los valores de fábrica, ~4.6 veces el
## primero).
@export var sweep_last_hop: float = 0.14
## Color de la fila resaltada (valores sobre 1 la iluminan).
@export var highlight_on: Color = Color(1.6, 1.5, 1.2)
## Color de las demás filas durante el barrido.
@export var highlight_off: Color = Color(1.0, 1.0, 1.0, 0.55)

@export_group("Filas")
## Tamaño mínimo de cada fila de resultado, en píxeles.
@export var row_size: Vector2 = Vector2(260.0, 26.0)
## Fondo de cada fila.
@export var row_bg: Color = Color(UiTheme.TILE_BG, 0.9)
## Cuánto se aclara el color del resultado en el texto de su fila (0-1).
@export var row_text_lighten: float = 0.15
## Opacidad del borde de cada fila (0-1).
@export var row_border_alpha: float = 0.4

@export_group("Resultado")
## Cuánto se aclara el color del resultado en la línea final (0-1).
@export var result_lighten: float = 0.2
## Escala del golpe de la línea final al caer el resultado.
@export var result_pop_scale: float = 1.3
## Segundos del golpe de la línea final.
@export var result_pop_time: float = 0.3

@export_group("Color")
## Acento de la ruleta: borde del panel, título y botón GIRAR.
@export var accent_color: Color = UiTheme.ACCENT_AMBER

@export_group("Textos")
## Título del panel.
@export var title_text: String = "RULETA DE LA FORTUNA"
## Botón de girar; %d es el precio del próximo giro.
@export var spin_template: String = "GIRAR — %d pts"
## Línea cuando el raider no alcanza a pagar el giro.
@export var broke_line: String = UiTheme.POINTS_SHORT
## Línea del resultado; %s es el texto del resultado.
@export var result_template: String = "▶ %s"
## Texto de cada fila; %s es el texto del resultado (la sangría va aquí).
@export var row_template: String = "  %s"
## Indicación del botón de aceptar.
@export var spin_hint_text: String = "Elegir"

@onready var _outcome_grid: GridContainer = %Outcomes
@onready var _spin_button: Button = %SpinButton

var _shrine: RouletteShrine = null
var _rows: Array[Label] = []
var _spinning: bool = false


## DEBE llamarse antes de add_child(): _ready arma el panel con el precio del
## altar y los puntos del raider.
func setup(shrine: RouletteShrine, player: Node) -> void:
	_shrine = shrine
	_bind(shrine, player)


func _build() -> void:
	_style_frame(title_text, accent_color)
	for outcome: Dictionary in RouletteShrine.OUTCOMES:
		_outcome_grid.add_child(_build_row(outcome))
	UiTheme.style_button(_spin_button, accent_color, true)
	_spin_button.pressed.connect(_on_spin)
	_refresh_points()
	_spin_button.grab_focus()


func _build_row(outcome: Dictionary) -> Label:
	var row := Label.new()
	row.text = row_template % RouletteShrine.outcome_label(outcome)
	row.custom_minimum_size = row_size
	var color := RouletteShrine.outcome_color(outcome)
	var tint := color.lightened(row_text_lighten)
	row.add_theme_color_override("font_color", tint)
	UiTheme.style_badge(row, tint, row_bg, Color(color, row_border_alpha))
	_rows.append(row)
	return row


func _play_headless() -> void:
	_on_spin()


func _can_close() -> bool:
	return not _spinning


func _accept_hint() -> String:
	return spin_hint_text


func _log_tag() -> String:
	return "RouletteUi"


## GIRAR queda deshabilitado durante todo el barrido: un botón que parece
## presionable y se traga el clic en silencio es peor que uno en gris.
func _refresh_points() -> void:
	var purse := _show_points()
	# El precio se duplica con cada giro, así que la etiqueta se vuelve a leer
	# aquí en vez de fijarse una vez al armar el panel.
	var cost := _shrine.current_price()
	_spin_button.text = spin_template % cost
	_spin_button.disabled = _spinning or purse < cost


func _on_spin() -> void:
	if _spinning:
		return
	var outcome := _shrine.spin(_player)
	if outcome.is_empty():
		_result.text = broke_line
		return
	_spinning = true
	# Limpia el giro anterior antes de empezar: la ruleta se reusa, y una línea
	# de resultado y un resaltado viejos seguirían en pantalla durante el nuevo
	# barrido.
	_result.text = ""
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


## Esperas de salto con frenado, normalizadas para que sumen sweep_time.
func _sweep_delays(steps: int) -> PackedFloat32Array:
	var delays := PackedFloat32Array()
	var total := 0.0
	for step in steps:
		var t := float(step) / float(steps - 1)
		var weight := lerpf(sweep_first_hop, sweep_last_hop, t * t)
		delays.append(weight)
		total += weight
	var delay_scale := maxf(sweep_time, 0.1) / maxf(total, 0.001)
	for i in delays.size():
		delays[i] *= delay_scale
	return delays


func _highlight(index: int) -> void:
	for i in _rows.size():
		_rows[i].modulate = highlight_on if i == index else highlight_off
	Sfx.play(&"hit_soft")


func _land(outcome: Dictionary) -> void:
	_spinning = false
	_result.text = result_template % RouletteShrine.outcome_label(outcome)
	_result.add_theme_color_override("font_color",
			RouletteShrine.outcome_color(outcome).lightened(result_lighten))
	UiTheme.pop(_result, result_pop_scale, result_pop_time)
	Sfx.play(&"shrine_done")
	_close_button.disabled = false
	_refresh_points()
	_close_button.grab_focus()
