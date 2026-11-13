class_name CharacterCard
extends Button
## Carta compacta de un raider en la cuadrícula del selector de personaje
## (CharacterCard.tscn). La escena tiene sus tres caras y cada etiqueta guarda
## ahí su fuente y su color:
##   Unlocked: retrato (la inicial sobre el tinte) y nombre; en co-op, qué
##             jugadores la eligieron;
##   Locked:   candado, nombre y precio en esquirlas;
##   Confirm:  "¿Desbloquear por N esquirlas?" con el botón «Sí» (%UnlockYes).
## El arma, la pasiva y la descripción se leen en el panel de detalle
## (CharacterDetail) y en el tooltip. El selector solo pasa la fila del
## catálogo y el estado (show_character); la carta decide cómo se ve.
##
## Movimiento: con el foco del control o el mouse encima, la carta crece un
## poco y su anillo (FocusRing) aparece con un fundido; al presionarla se
## aplasta. Solo se animan scale y modulate, nunca el tamaño del layout.

## Se presionó «Sí» en la cara de confirmación.
signal unlock_confirmed(character_id: String)
## El foco o el mouse llegó a la carta: el selector muestra su detalle.
signal highlighted(character_id: String)
## La carta quedó sin foco y sin mouse.
signal unhighlighted(character_id: String)

enum Face { UNLOCKED, LOCKED, CONFIRM }

## Llave de metadata del tween de pose. La comparten la entrada y el vaivén
## de rechazo, así nunca hay dos animaciones moviendo la carta a la vez.
const POSE_TWEEN_KEY := &"ui_pose_tween"

@export_group("Bordes")
## Borde de la carta sin elegir (la elegida usa el tinte del raider).
@export var idle_border_color: Color = UiTheme.BORDER_DIM
## Borde de la carta bloqueada.
@export var locked_border_color: Color = UiTheme.BORDER_LOCKED
## Borde de la cara de confirmación.
@export var confirm_border_color: Color = UiTheme.SHARD_BLUE
## Grosor del borde (píxeles) de la carta elegida y de la confirmación.
@export var selected_border_width: int = 3
## Grosor del borde (píxeles) de las demás cartas.
@export var idle_border_width: int = 2
## Cuánto se aclara el tinte del raider para el anillo de foco (0-1).
@export_range(0.0, 1.0) var ring_lighten: float = 0.45
## Alfa (0-1) del brillo exterior del anillo de foco.
@export_range(0.0, 1.0) var ring_glow_alpha: float = 0.55

@export_group("Retrato")
## Cuánto se oscurece el tinte del raider para el cuerpo del retrato (0-1).
@export_range(0.0, 1.0) var portrait_body_darken: float = 0.35
## Cuánto se aclara el tinte para el borde del retrato (0-1).
@export_range(0.0, 1.0) var portrait_rim_lighten: float = 0.3
## Cuánto se oscurece el tinte para el contorno de la inicial (0-1).
@export_range(0.0, 1.0) var monogram_outline_darken: float = 0.7

@export_group("Movimiento")
## Escala de la carta con el foco del control o el mouse encima.
@export var focus_scale: float = 1.05
## Escala de la carta mientras se mantiene presionada.
@export var press_scale: float = 0.97
## Modulate de las cartas no elegidas en reposo (un paso más oscuras).
@export var unselected_modulate: Color = Color(0.8, 0.82, 0.86)
## Duración (segundos) del paso entre poses (crecer, anillo, aplastar).
@export var pose_time: float = 0.14
## Escala desde la que entra la carta al abrir el selector.
@export var entrance_start_scale: float = 0.95
## Duración (segundos) de la entrada de la carta.
@export var entrance_time: float = 0.24

@export_group("Textos")
## Pregunta de la cara de confirmación (%d = precio en esquirlas).
@export var confirm_format: String = "¿Desbloquear por %d esquirlas?"
## Separador entre los jugadores que eligieron la carta ("J1 · J3").
@export var owners_separator: String = " · "
## Primera línea del tooltip (%s = nombre, %s = arma).
@export var tooltip_title_format: String = "%s — %s"
## Precio y pista en el tooltip de una carta bloqueada (%s = precio, %s = pista).
@export var tooltip_price_hint_format: String = "%s, o %s"

## Id de la fila del catálogo que muestra la carta.
var character_id: String = ""

## Si la carta se ve elegida (decide su borde y su modulate de reposo).
var _selected: bool = false
## True entre button_down y button_up.
var _held: bool = false
## Último estado de resalte avisado, para emitir cada señal una sola vez.
var _was_lit: bool = false

@onready var _unlocked: VBoxContainer = $Unlocked
@onready var _monogram: Label = $Unlocked/Portrait/Monogram
@onready var _unlocked_name: Label = $Unlocked/Name
@onready var _owners: Label = $Unlocked/Portrait/Owners
@onready var _locked: VBoxContainer = $Locked
@onready var _locked_name: Label = $Locked/Name
@onready var _price: Label = $Locked/Price
@onready var _confirm: VBoxContainer = $Confirm
@onready var _ask: Label = $Confirm/Ask
@onready var _unlock_yes: Button = %UnlockYes
@onready var _focus_ring: Panel = $FocusRing
@onready var _ring_style: StyleBoxFlat = \
		($FocusRing as Panel).get_theme_stylebox(&"panel") as StyleBoxFlat
@onready var _portrait_style: StyleBoxFlat = \
		($Unlocked/Portrait as Panel).get_theme_stylebox(&"panel") as StyleBoxFlat


func _ready() -> void:
	# La carta escala desde su centro, pero su tamaño solo se conoce después
	# del primer layout: seguir `resized` mantiene el pivote centrado.
	resized.connect(func() -> void: pivot_offset = size * 0.5)
	focus_entered.connect(_on_highlight_changed)
	focus_exited.connect(_on_highlight_changed)
	mouse_entered.connect(_on_highlight_changed)
	mouse_exited.connect(_on_highlight_changed)
	button_down.connect(_on_held_changed.bind(true))
	button_up.connect(_on_held_changed.bind(false))
	UiTheme.style_button(_unlock_yes, UiTheme.SHARD_BLUE, true)
	_unlock_yes.pressed.connect(func() -> void: unlock_confirmed.emit(character_id))


## Pinta la carta con la fila `row` del catálogo en la cara `face`. `selected`
## le da el borde del tinte; `owner_slots` son los slots de co-op (desde 0)
## que la eligieron, y se escriben en la esquina del retrato.
func show_character(row: Dictionary, face: Face, selected: bool,
		owner_slots: Array[int] = []) -> void:
	character_id = String(row.id)
	_selected = selected
	tooltip_text = _tooltip(row, face != Face.UNLOCKED)
	_unlocked.visible = face == Face.UNLOCKED
	_locked.visible = face == Face.LOCKED
	_confirm.visible = face == Face.CONFIRM
	var tint := Color(row.tint)
	_ring_style.border_color = tint.lightened(ring_lighten)
	_ring_style.shadow_color = Color(tint, ring_glow_alpha)
	match face:
		Face.UNLOCKED:
			_fill_unlocked(row, tint, owner_slots)
		Face.LOCKED:
			_fill_locked(row)
		Face.CONFIRM:
			_fill_confirm(row)
	settle(selected)


## Lleva la carta a su pose de reposo: escala y anillo según el foco y el
## mouse, y modulate según si está elegida. Un solo tween por carta guardado
## en la metadata, así las pulsaciones rápidas lo redirigen en vez de apilar
## animaciones; también cancela (y endereza) un vaivén de rechazo.
func settle(selected: bool) -> void:
	_selected = selected
	var lit := is_lit()
	pivot_offset = size * 0.5
	# Encima de sus vecinas mientras está agrandada, para que no la tapen.
	z_index = 1 if lit else 0
	UiTheme.kill_meta_tween(self, POSE_TWEEN_KEY)
	rotation_degrees = 0.0
	var target_scale := press_scale if _held else (focus_scale if lit else 1.0)
	var tween := create_tween().set_parallel()
	tween.set_ignore_time_scale(true)
	tween.tween_property(self, "scale", Vector2.ONE * target_scale, pose_time) \
			.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate", rest_modulate(selected), pose_time) \
			.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.tween_property(_focus_ring, "modulate:a", 1.0 if lit else 0.0, pose_time) \
			.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	set_meta(POSE_TWEEN_KEY, tween)


## Entrada al abrir el selector: tras `delay` segundos, la carta funde y crece
## desde entrance_start_scale hasta su pose de reposo. Es decorativa: usar la
## carta antes de que termine la corta y la deja en su pose.
func play_entrance(delay: float) -> void:
	UiTheme.kill_meta_tween(self, POSE_TWEEN_KEY)
	var rest := rest_modulate(_selected)
	modulate = Color(rest, 0.0)
	scale = Vector2.ONE * entrance_start_scale
	var tween := create_tween().set_parallel()
	tween.set_ignore_time_scale(true)
	tween.tween_property(self, "modulate", rest, entrance_time).set_delay(delay) \
			.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, entrance_time).set_delay(delay) \
			.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	set_meta(POSE_TWEEN_KEY, tween)


## "No alcanza": destello rojo y vaivén (UiTheme.reject) que termina en el
## modulate de reposo, no en blanco (una carta no elegida está atenuada).
func reject(selected: bool) -> void:
	UiTheme.reject(self, UiTheme.REJECT_SWINGS, UiTheme.REJECT_SWING_TIMES,
			rest_modulate(selected), POSE_TWEEN_KEY)


## Modulate de reposo: blanco la elegida y la que tiene el foco o el mouse,
## atenuada el resto.
func rest_modulate(selected: bool) -> Color:
	return Color.WHITE if selected or is_lit() else unselected_modulate


## True con el foco del control o el mouse encima.
func is_lit() -> bool:
	return has_focus() or is_hovered()


## El «Sí» mientras la carta pide confirmar el desbloqueo, o null.
func unlock_button() -> Button:
	return _unlock_yes if _confirm.visible else null


func _on_highlight_changed() -> void:
	settle(_selected)
	var lit := is_lit()
	if lit:
		# Se avisa en cada cambio, no solo en el primero: el foco y el mouse
		# pueden estar en cartas distintas y el detalle sigue a la última.
		highlighted.emit(character_id)
	elif _was_lit:
		unhighlighted.emit(character_id)
	_was_lit = lit


func _on_held_changed(held: bool) -> void:
	_held = held
	settle(_selected)


func _fill_unlocked(row: Dictionary, tint: Color, owner_slots: Array[int]) -> void:
	var display_name := String(row.display_name)
	_portrait_style.bg_color = tint.darkened(portrait_body_darken)
	_portrait_style.border_color = tint.lightened(portrait_rim_lighten)
	_monogram.text = display_name.left(1).to_upper()
	_monogram.add_theme_color_override("font_outline_color",
			tint.darkened(monogram_outline_darken))
	_unlocked_name.text = display_name
	var owners: Array[String] = []
	for slot in owner_slots:
		owners.append(UiTheme.PLAYER_TAG % (slot + 1))
	_owners.text = owners_separator.join(owners)
	_owners.visible = not owners.is_empty()
	_style(tint if _selected else idle_border_color,
			selected_border_width if _selected else idle_border_width, _selected)


func _fill_locked(row: Dictionary) -> void:
	_locked_name.text = String(row.display_name)
	_price.text = UiTheme.SHARDS_AMOUNT % int(row.get("unlock_cost", 0))
	_style(locked_border_color, idle_border_width, false)


func _fill_confirm(row: Dictionary) -> void:
	_ask.text = confirm_format % int(row.get("unlock_cost", 0))
	_style(confirm_border_color, selected_border_width, true)


## Aspecto de carta de UiTheme.style_card, sin sus estados de hover y de
## foco: ese resalte lo dibuja FocusRing, que puede fundirse (un stylebox
## cambia de golpe).
func _style(border: Color, width: int, glow: bool) -> void:
	UiTheme.style_card(self, border, width, glow)
	add_theme_stylebox_override("hover", get_theme_stylebox(&"normal"))
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())


## El texto completo de la carta al pasar el mouse: nombre, arma, pasiva y
## descripción, y el precio si está bloqueada.
func _tooltip(row: Dictionary, locked: bool) -> String:
	var lines: Array[String] = [
		tooltip_title_format % [String(row.display_name), String(row.weapon_display_name)],
		String(row.passive_description),
	]
	var blurb := String(row.get("blurb", ""))
	if not blurb.is_empty():
		lines.append_array(["", blurb])
	if locked:
		var price := UiTheme.SHARDS_AMOUNT % int(row.get("unlock_cost", 0))
		var hint := String(row.get("unlock_hint", ""))
		lines.append_array(["",
				price if hint.is_empty() else tooltip_price_hint_format % [price, hint]])
	return "\n".join(lines)
