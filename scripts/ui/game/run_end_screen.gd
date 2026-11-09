extends CanvasLayer
## Pantalla de fin de partida (GDD 9.6): la abre RunManager.run_ended con las
## estadísticas de RunState. Su capa (20, en RunEndScreen.tscn) dibuja sobre
## las cartas de mejora y process_mode ALWAYS mantiene la animación y los botones
## vivos con el árbol en pausa. Reintentar recarga la partida (el _ready del
## jugador recaptura el mouse), Cambiar raider hace la misma limpieza pero
## vuelve al selector y Salir cierra el juego.
##
## Los cuatro finales (cumplió la meta o no × murió o se extrajo) son filas de
## ENDINGS: texto, color del título y adorno viajan juntos, así que un quinto
## final es una fila más.
##
## Aspecto: la derrota cae grande con una sacudida y la victoria aterriza con
## un rebote y un brillo dorado en bucle; luego entran escalonados el panel
## de estadísticas, las recompensas y los botones (~0.8 s; los botones
## responden desde el inicio). Salir pasa por ScreenFade.leave_run, dueño de
## la limpieza, que mantiene el árbol en pausa durante el corte. Todos los
## tweens ignoran la escala de tiempo (una muerte puede caer en pleno
## hit-stop).

## Color del título en las derrotas y en las victorias.
const DEFEAT_TITLE_COLOR := Color(0.9, 0.25, 0.2)
const VICTORY_TITLE_COLOR := Color(0.96, 0.78, 0.3)

## Una fila por final. `shake` es el golpe de la derrota y `shimmer` el
## brillo dorado en bucle del título.
const ENDINGS: Dictionary[String, Dictionary] = {
	"death_win": {
		"title": "INCURSIÓN COMPLETA", "subtitle": "¡Sobreviviste!",
		"color": VICTORY_TITLE_COLOR, "shake": false, "shimmer": true,
	},
	"death_loss": {
		"title": "MORISTE", "subtitle": "La horda te alcanzó.",
		"color": DEFEAT_TITLE_COLOR, "shake": true, "shimmer": false,
	},
	"exit_win": {
		"title": "EXTRACCIÓN LOGRADA", "subtitle": "Saliste con vida.",
		"color": VICTORY_TITLE_COLOR, "shake": false, "shimmer": true,
	},
	"exit_loss": {
		"title": "INCURSIÓN ABANDONADA", "subtitle": "Saliste antes de superar una etapa.",
		"color": DEFEAT_TITLE_COLOR, "shake": false, "shimmer": false,
	},
}

@export_group("Textos")
## Indicación del botón de aceptar, bajo los botones.
@export var accept_hint_text: String = "Elegir"
## Línea de etapas superadas en la partida (%d = etapas).
@export var stages_format: String = "Etapas superadas: %d"
## Línea de vueltas completas al circuito de mapas (%d = vueltas); solo sale con al menos una.
@export var laps_format: String = "Vueltas: %d"
## Línea de misiones nuevas (%s = esquirlas ganadas, %d = misiones, %s = frase de misión).
@export var quests_format: String = "%s · %d %s — reclámalas en el registro"
## Frase de misión cuando se completó una sola.
@export var quest_singular_text: String = "misión completada"
## Frase de misión cuando se completaron varias.
@export var quest_plural_text: String = "misiones completadas"
## Línea de la Cacería diaria (%d = puntaje de esta partida, %d = mejor de hoy).
@export var daily_score_format: String = "Puntaje diario: %d — mejor de hoy: %d"

@export_group("Animación")
## Duración del fundido de entrada del atenuado, en segundos.
@export var dim_fade_time: float = 0.18
## Escala desde la que cae el título.
@export var title_start_scale: float = 1.9
## Duración del fundido de entrada del título, en segundos.
@export var title_fade_time: float = 0.12
## Duración de la caída del título en una derrota con golpe, en segundos.
@export var title_slam_time: float = 0.14
## Duración de la caída con rebote del título en los demás finales, en segundos.
@export var title_bounce_time: float = 0.3
## Primer giro de la sacudida de la derrota, en grados.
@export var shake_first_angle: float = -2.0
## Segundo giro de la sacudida de la derrota, en grados.
@export var shake_second_angle: float = 1.6
## Duración del primer giro de la sacudida, en segundos.
@export var shake_first_time: float = 0.04
## Duración del segundo giro y del regreso a recto, en segundos cada uno.
@export var shake_swing_time: float = 0.06
## Duración del fundido de estadísticas, recompensas y botones, en segundos.
@export var section_fade_time: float = 0.2
## Retraso de la primera sección tras abrir la pantalla, en segundos.
@export var section_delay: float = 0.22
## Retraso extra entre una sección y la siguiente, en segundos.
@export var section_stagger: float = 0.09
## Brillo (modulate) al que sube el título en el destello dorado de la victoria.
@export var shimmer_color: Color = Color(1.3, 1.22, 1.0)
## Duración de cada mitad del destello dorado, en segundos.
@export var shimmer_time: float = 0.9
## Espera antes de cada subida del destello dorado, en segundos.
@export var shimmer_delay: float = 0.4

@onready var _root: Control = %Root
@onready var _title_label: Label = %TitleLabel
@onready var _subtitle_label: Label = %SubtitleLabel
@onready var _stats_panel: PanelContainer = %StatsPanel
@onready var _time_value: Label = %TimeValue
@onready var _level_value: Label = %LevelValue
@onready var _kills_value: Label = %KillsValue
@onready var _rewards_label: Label = %RewardsLabel
@onready var _buttons_row: Control = %Buttons
@onready var _retry_button: Button = %RetryButton
@onready var _change_character_button: Button = %ChangeCharacterButton
@onready var _quit_button: Button = %QuitButton

var _entrance_tween: Tween = null
var _shimmer_tween: Tween = null


func _ready() -> void:
	visible = false
	add_to_group(BlockingUi.GROUP)
	_apply_styles()
	# El contenedor reacomoda un frame DESPUÉS del cambio de texto y fuente
	# del título, así que el tamaño que lee _play_entrance todavía es el
	# viejo. Recentrar el pivote en cada cambio de tamaño mantiene la escala
	# anclada en el titular en vez de deslizarlo por la pantalla.
	_title_label.resized.connect(_center_title_pivot)
	# Indicación de botones bajo los botones; sigue al último dispositivo.
	_buttons_row.get_parent().add_child(InputHints.build([["ui_accept", accept_hint_text]]))
	_retry_button.pressed.connect(_on_retry_pressed)
	_change_character_button.pressed.connect(_on_change_character_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)


## Contrato de BlockingUi (grupo BlockingUi.GROUP): la pantalla de fin es dueña
## de la pausa mientras está arriba, así que Esc no abre la pausa encima.
func is_blocking() -> bool:
	return visible


## Conectada a RunManager.run_ended en RunSystems.tscn. El árbol ya está en
## pausa cuando esto corre.
func open(victory: bool) -> void:
	if visible:
		return
	# Ningún reloj termina la partida: victoria es haber cumplido la meta de
	# supervivencia antes del final (muerte o extracción).
	var ending: Dictionary = ENDINGS[_ending_key(victory, not _party_wiped())]
	_title_label.add_theme_color_override("font_color", ending.color as Color)
	_title_label.text = String(ending.title)
	_subtitle_label.text = String(ending.subtitle)
	var total: int = int(RunState.run_time)
	_time_value.text = "%02d:%02d" % [floori(total / 60.0), total % 60]
	_level_value.text = str(RunState.level)
	_kills_value.text = str(RunState.kills)
	_rewards_label.text = "\n".join(_earning_lines())
	_rewards_label.visible = not _rewards_label.text.is_empty()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	visible = true
	_retry_button.grab_focus()
	_play_entrance(ending)


func _ending_key(victory: bool, extracted: bool) -> String:
	if extracted:
		return "exit_win" if victory else "exit_loss"
	return "death_win" if victory else "death_loss"


## Ganancias meta del cierre de esta partida (RunManager lo corrió justo
## antes de emitir run_ended): etapas y vueltas, las misiones nuevas cuyas
## esquirlas esperan en el registro y el puntaje de la Cacería diaria.
func _earning_lines() -> Array[String]:
	var lines: Array[String] = []
	# El avance por etapas va primero: es de lo que trató la partida.
	lines.append(stages_format % RunState.stages_cleared_total)
	if RunState.laps_completed > 0:
		lines.append(laps_format % RunState.laps_completed)
	var quest_count := SaveData.last_new_quest_ids.size()
	if quest_count > 0:
		# Concuerda la frase entera, no solo una letra plural: el español
		# también flexiona el participio ("1 misión completada" / "3 misiones
		# completadas"), así que la cantidad elige la frase.
		var quest_phrase := quest_singular_text if quest_count == 1 else quest_plural_text
		lines.append(quests_format % [
				UiTheme.SHARDS_GAIN % SaveData.last_reward_shards, quest_count, quest_phrase])
	# Línea del marcador de la Cacería diaria.
	if GameConfig.daily_mode:
		lines.append(daily_score_format % [
				GameConfig.last_daily_score,
				SaveData.stat(DailyHunt.BEST_STAT_PREFIX + GameConfig.daily_date)])
	return lines


## True cuando nadie del grupo sigue en pie (una muerte terminó la partida,
## no una extracción). Los cuerpos caídos en co-op salen del grupo "player",
## así que un grupo vacío al final significa que cayeron todos.
func _party_wiped() -> bool:
	for node: Node in get_tree().get_nodes_in_group("player"):
		var health := Health.find_in(node)
		if health != null and not health.is_dead:
			return false
	return true


## Aparece el atenuado, el título aterriza con impacto y luego entran
## escalonados estadísticas, recompensas y botones. Corre a través de la
## pausa (capa ALWAYS) e ignora el hit-stop.
func _play_entrance(ending: Dictionary) -> void:
	if _entrance_tween != null and _entrance_tween.is_valid():
		_entrance_tween.kill()
	if _shimmer_tween != null and _shimmer_tween.is_valid():
		_shimmer_tween.kill()
	_root.modulate.a = 0.0
	_center_title_pivot()
	_title_label.scale = Vector2.ONE * title_start_scale
	_title_label.modulate = Color(1, 1, 1, 0)
	_title_label.rotation_degrees = 0.0
	var staggered: Array[Control] = [_stats_panel, _rewards_label, _buttons_row]
	for section: Control in staggered:
		section.modulate.a = 0.0
	_entrance_tween = create_tween()
	_entrance_tween.set_ignore_time_scale(true)
	_entrance_tween.tween_property(_root, "modulate:a", 1.0, dim_fade_time)
	# Título: cae desde grande; el golpe sacude y lo demás suaviza.
	_entrance_tween.parallel().tween_property(_title_label, "modulate:a", 1.0,
			title_fade_time)
	if bool(ending.shake):
		_entrance_tween.parallel().tween_property(_title_label, "scale", Vector2.ONE,
				title_slam_time) \
				.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
		_entrance_tween.tween_property(_title_label, "rotation_degrees", shake_first_angle,
				shake_first_time)
		_entrance_tween.tween_property(_title_label, "rotation_degrees", shake_second_angle,
				shake_swing_time)
		_entrance_tween.tween_property(_title_label, "rotation_degrees", 0.0, shake_swing_time)
	else:
		_entrance_tween.parallel().tween_property(_title_label, "scale", Vector2.ONE,
				title_bounce_time) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in staggered.size():
		_entrance_tween.parallel().tween_property(staggered[i], "modulate:a", 1.0,
				section_fade_time).set_delay(section_delay + section_stagger * i)
	if bool(ending.shimmer):
		# Brillo dorado: el título respira más claro, en bucle.
		_shimmer_tween = create_tween().set_loops()
		_shimmer_tween.set_ignore_time_scale(true)
		_shimmer_tween.tween_property(_title_label, "modulate",
				shimmer_color, shimmer_time).set_delay(shimmer_delay) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_shimmer_tween.tween_property(_title_label, "modulate", Color.WHITE, shimmer_time) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _center_title_pivot() -> void:
	_title_label.pivot_offset = _title_label.size * 0.5


func _on_retry_pressed() -> void:
	# Se revisa el retorno (screen_fade.gd lo pide): una pulsación que llega
	# durante un corte se DESCARTA.
	if not ScreenFade.leave_run():
		return


## La limpieza de Reintentar, pero de vuelta al selector para elegir otro
## raider (la elección en GameConfig sobrevive, así que el selector reabre
## en lo último elegido).
func _on_change_character_pressed() -> void:
	if not ScreenFade.leave_run(ScenePaths.CHARACTER_SELECT):
		return


func _on_quit_pressed() -> void:
	Settings.flush_save()
	Sfx.stop_all_loops()
	get_tree().quit()


## Sistema de diseño UiTheme: panel de estadísticas con línea de acento y
## Reintentar turquesa como botón principal. La tipografía del título y del
## subtítulo vive en la escena; el color del título lo elige el final.
func _apply_styles() -> void:
	_stats_panel.add_theme_stylebox_override("panel",
			UiTheme.panel(UiTheme.PANEL_BG, UiTheme.BORDER_DIM, 26.0, 16.0))
	UiTheme.style_button(_retry_button, UiTheme.ACCENT, true)
	UiTheme.style_button(_change_character_button)
	UiTheme.style_button(_quit_button)
