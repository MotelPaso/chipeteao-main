class_name QuestCard
extends PanelContainer
## Tarjeta de una misión en el Registro de misiones (QuestCard.tscn): ficha con
## el icono de su tipo, nombre, descripción, barra de progreso gruesa con
## "x / y" y lo que falta, la recompensa como ficha con el icono de esquirla,
## y lo propio de su estado: nada mientras sigue en curso, el sello «¡Lista!»
## y el botón Reclamar cuando está completa, o el sello RECLAMADA, atenuada,
## cuando ya se cobró.
## Quien la usa le pasa la fila del catálogo, el estado y el avance (show_quest)
## y escucha claim_pressed; el aspecto vive aquí y en QuestCard.tscn.

## El jugador apretó Reclamar en esta tarjeta.
signal claim_pressed(quest_id: String)

## Estados de una misión; se excluyen entre sí.
enum State {
	IN_PROGRESS, ## Falta avance.
	CLAIMABLE, ## Completa, con el premio sin cobrar.
	CLAIMED, ## Premio ya cobrado.
}

## Icono de la ficha de recompensa.
const SHARD_ICON: Texture2D = preload("res://assets/ui/icons/shard.svg")

@export_group("Tarjeta")
## Fondo de la tarjeta.
@export var body_color: Color = UiTheme.CARD_BG
## Fondo de la tarjeta de una misión lista para reclamar.
@export var claimable_body_color: Color = UiTheme.CARD_BG_HOVER
## Contorno de la tarjeta.
@export var border_color: Color = UiTheme.INK
## Grosor del contorno, en píxeles.
@export var border_width: int = 3
## Radio de las esquinas, en píxeles.
@export var corner_radius: int = UiTheme.RADIUS
## Margen interno de la tarjeta, en píxeles (lados, arriba/abajo).
@export var padding: Vector2 = Vector2(14.0, 10.0)
## Sombra dura bajo la tarjeta (desplazamiento en píxeles).
@export var shadow_offset: Vector2 = Vector2(0.0, 4.0)
## Modulate de una tarjeta ya reclamada (atenuada).
@export var claimed_modulate: Color = Color(1.0, 1.0, 1.0, 0.55)
@export_group("Ficha de tipo")
## Fondo de la ficha con el icono del tipo de misión.
@export var type_chip_color: Color = UiTheme.PAPER
## Radio de las esquinas de las fichas (tipo y recompensa), en píxeles.
@export var chip_radius: int = 12
## Aire entre el contorno de la ficha de tipo y su dibujo, en píxeles.
@export var type_chip_padding: int = 6
@export_group("Barra de progreso")
## Relleno de la barra mientras la misión sigue en curso.
@export var progress_color: Color = UiTheme.SHARD_BLUE
## Relleno de la barra de una misión completa.
@export var complete_color: Color = UiTheme.ACCENT_MINT
## Radio de las esquinas de la barra, en píxeles.
@export var bar_radius: int = 8
## Margen entre el canal de la barra y su relleno, en píxeles.
@export var bar_inset: int = 3
@export_group("Recompensa")
## Fondo de la ficha de recompensa.
@export var reward_chip_color: Color = UiTheme.PAPER
## Margen interno de la ficha de recompensa, en píxeles (lados, arriba/abajo).
@export var reward_chip_padding: Vector2 = Vector2(10.0, 3.0)
@export_group("Sello")
## Fondo del sello «¡Lista!».
@export var ready_stamp_color: Color = UiTheme.ACCENT
## Giro del sello «¡Lista!», en grados.
@export var ready_stamp_tilt: float = -5.0
## Margen interno del sello, en píxeles (lados, arriba/abajo).
@export var stamp_padding: Vector2 = Vector2(10.0, 1.0)
## Espacio extra entre las letras del sello RECLAMADA, en píxeles.
@export var claimed_spacing: int = 1
@export_group("Animación")
## Escala desde la que entra la tarjeta al abrir el registro.
@export var entrance_start_scale: float = 0.96
## Duración de la entrada de la tarjeta, en segundos.
@export var entrance_time: float = 0.2
@export_group("Textos")
## Avance sobre la barra: actual y meta.
@export var count_format: String = "%d / %d"
## Lo que falta para completar la misión, junto a la barra.
@export var remaining_format: String = "Faltan %d"
## Lo que falta cuando es exactamente uno.
@export var remaining_one_text: String = "Falta 1"
## Recompensa en esquirlas, dentro de su ficha.
@export var reward_format: String = "+%d"
## Tooltip de la ficha de recompensa.
@export var reward_tip_format: String = UiTheme.SHARDS_GAIN
## Sello de una misión completa sin reclamar.
@export var ready_text: String = "¡Lista!"
## Botón de una misión completa sin reclamar.
@export var claim_text: String = "Reclamar"
## Sello de una misión ya reclamada.
@export var claimed_text: String = "RECLAMADA"

var _quest_id: String = ""

@onready var _type_chip: PanelContainer = %TypeChip
@onready var _type_icon: TextureRect = %TypeIcon
@onready var _name: Label = %Name
@onready var _description: Label = %Description
@onready var _bar: ProgressBar = %Bar
@onready var _count: Label = %Count
@onready var _remaining: Label = %Remaining
@onready var _reward_chip: PanelContainer = %RewardChip
@onready var _reward_icon: TextureRect = %RewardIcon
@onready var _reward: Label = %Reward
@onready var _ready_stamp: Label = %ReadyStamp
@onready var _claim: Button = %ClaimButton
@onready var _claimed_stamp: Label = %ClaimedStamp


func _ready() -> void:
	_type_chip.add_theme_stylebox_override("panel", _chip_style(type_chip_color,
			Vector2.ONE * type_chip_padding))
	_reward_chip.add_theme_stylebox_override("panel", _chip_style(reward_chip_color,
			reward_chip_padding))
	_reward_icon.texture = SHARD_ICON
	for label: Label in [_name, _count, _reward, _ready_stamp]:
		label.add_theme_font_override("font", UiTheme.display_font())
	var stamp := UiTheme.flat(ready_stamp_color, UiTheme.RADIUS_SMALL)
	stamp.border_color = border_color
	stamp.set_border_width_all(border_width)
	stamp.content_margin_left = stamp_padding.x
	stamp.content_margin_right = stamp_padding.x
	stamp.content_margin_top = stamp_padding.y
	stamp.content_margin_bottom = stamp_padding.y
	_ready_stamp.add_theme_stylebox_override("normal", stamp)
	_ready_stamp.text = ready_text
	_claimed_stamp.add_theme_font_override("font", UiTheme.spaced_font(claimed_spacing))
	_claimed_stamp.text = claimed_text
	_claim.text = claim_text
	UiTheme.style_button(_claim, UiTheme.ACCENT_AMBER, true)
	_claim.pressed.connect(_on_claim_pressed)
	# La tarjeta escala desde su centro, y su tamaño lo decide la lista.
	resized.connect(_center_pivot)
	_ready_stamp.resized.connect(_center_pivot)
	_center_pivot()


## Pinta la tarjeta para `quest` (fila de QuestCatalog) en `state`, con
## `current` como valor de su contador. Llamar después de agregarla al árbol.
func show_quest(quest: Dictionary, state: State, current: int) -> void:
	_quest_id = String(quest.id)
	var target := int(quest.target)
	var done := mini(current, target)
	var complete := state != State.IN_PROGRESS
	var body := UiTheme.flat(claimable_body_color if state == State.CLAIMABLE
			else body_color, corner_radius)
	body.border_color = border_color
	body.set_border_width_all(border_width)
	body.content_margin_left = padding.x
	body.content_margin_right = padding.x
	body.content_margin_top = padding.y
	body.content_margin_bottom = padding.y
	UiTheme.add_hard_shadow(body, shadow_offset)
	add_theme_stylebox_override("panel", body)
	modulate = claimed_modulate if state == State.CLAIMED else Color.WHITE
	_type_icon.texture = QuestTypes.texture(QuestTypes.type_of(String(quest.stat)))
	_name.text = String(quest.display_name)
	_description.text = String(quest.description)
	# La barra se acota a la meta: pasarse se lee llena.
	_bar.max_value = float(target)
	_bar.value = float(target if complete else done)
	UiTheme.style_bar(_bar, complete_color if complete else progress_color,
			bar_radius, bar_inset)
	_count.text = count_format % [target if complete else done, target]
	var left := target - done
	_remaining.visible = not complete
	_remaining.text = remaining_one_text if left == 1 else remaining_format % left
	_reward.text = reward_format % int(quest.reward)
	_reward_chip.tooltip_text = reward_tip_format % int(quest.reward)
	_ready_stamp.visible = state == State.CLAIMABLE
	_ready_stamp.rotation_degrees = ready_stamp_tilt
	_claim.visible = state == State.CLAIMABLE
	# Sin foco mientras está oculto: MetaScreen recorre con el control todo
	# botón enfocable de la lista.
	_claim.focus_mode = Control.FOCUS_ALL if state == State.CLAIMABLE \
			else Control.FOCUS_NONE
	_claimed_stamp.visible = state == State.CLAIMED


## Entrada al abrir el registro: aparece y crece un poco, tras `delay`
## segundos. Termina en el modulate de su estado (una reclamada queda atenuada).
func play_entrance(delay: float) -> void:
	var rest := modulate
	modulate = Color(rest, 0.0)
	scale = Vector2.ONE * entrance_start_scale
	var tween := create_tween().set_parallel()
	tween.set_ignore_time_scale(true)
	tween.tween_property(self, "modulate", rest, entrance_time).set_delay(delay) \
			.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE, entrance_time).set_delay(delay) \
			.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)


func _center_pivot() -> void:
	pivot_offset = size * 0.5
	_ready_stamp.pivot_offset = _ready_stamp.size * 0.5


func _chip_style(color: Color, margin: Vector2) -> StyleBoxFlat:
	var box := UiTheme.flat(color, chip_radius)
	box.border_color = border_color
	box.set_border_width_all(border_width)
	box.content_margin_left = margin.x
	box.content_margin_right = margin.x
	box.content_margin_top = margin.y
	box.content_margin_bottom = margin.y
	return box


func _on_claim_pressed() -> void:
	claim_pressed.emit(_quest_id)
