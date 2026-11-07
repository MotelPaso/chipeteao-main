class_name CharacterCard
extends Button
## Carta de un raider en el selector de personaje (CharacterCard.tscn). La
## escena tiene sus tres caras y cada etiqueta guarda ahí su fuente, color y
## tope de líneas:
##   Unlocked: retrato, nombre, arma, pasiva, descripción (y en co-op, qué
##             jugadores la eligieron);
##   Locked:   candado, nombre, arma, precio en esquirlas, pista y pasiva;
##   Confirm:  "¿Desbloquear por N esquirlas?" con el botón «Sí» (%UnlockYes).
## El selector solo pasa la fila del catálogo y el estado (show_character);
## la carta decide cómo se ve. Sus styleboxes de estado salen de
## UiTheme.style_card, el mismo aspecto que las cartas de mejora.

## Se presionó «Sí» en la cara de confirmación.
signal unlock_confirmed(character_id: String)

enum Face { UNLOCKED, LOCKED, CONFIRM }

## Llave de metadata del tween de reposo. La comparte el vaivén de rechazo,
## así los dos nunca animan la carta a la vez.
const SETTLE_TWEEN_KEY := &"ui_settle_tween"

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

@export_group("Retrato")
## Cuánto se oscurece el tinte del raider para el cuerpo del retrato (0-1).
@export_range(0.0, 1.0) var portrait_body_darken: float = 0.35
## Cuánto se aclara el tinte para el borde del retrato (0-1).
@export_range(0.0, 1.0) var portrait_rim_lighten: float = 0.3
## Alfa (0-1) del brillo del retrato, en el color del tinte.
@export_range(0.0, 1.0) var portrait_glow_alpha: float = 0.35
## Cuánto se oscurece el tinte para el contorno de la inicial (0-1).
@export_range(0.0, 1.0) var monogram_outline_darken: float = 0.7

@export_group("Movimiento")
## Escala de la carta al pasar el mouse.
@export var hover_grow: float = 1.03
## Escala de la carta elegida en reposo (sube un poco).
@export var selected_scale: float = 1.035
## Modulate de las cartas no elegidas en reposo (un paso más oscuras).
@export var unselected_modulate: Color = Color(0.8, 0.82, 0.86)
## Duración (segundos) del paso a la pose de reposo.
@export var settle_time: float = 0.16

@export_group("Textos")
## Pregunta de la cara de confirmación (%d = precio en esquirlas).
@export var confirm_format: String = "¿Desbloquear por %d esquirlas?"
## Pista de desbloqueo por jefe bajo el precio (%s = unlock_hint del catálogo).
@export var hint_format: String = "o %s"
## Separador entre los jugadores que eligieron la carta ("J1 · J3").
@export var owners_separator: String = " · "
## Primera línea del tooltip (%s = nombre, %s = arma).
@export var tooltip_title_format: String = "%s — %s"
## Precio y pista en el tooltip de una carta bloqueada (%s = precio, %s = pista).
@export var tooltip_price_hint_format: String = "%s, o %s"

## Id de la fila del catálogo que muestra la carta.
var character_id: String = ""

@onready var _unlocked: VBoxContainer = $Unlocked
@onready var _unlocked_monogram: Label = $Unlocked/Portrait/Monogram
@onready var _unlocked_name: Label = $Unlocked/Name
@onready var _unlocked_weapon: Label = $Unlocked/Weapon
@onready var _unlocked_passive: Label = $Unlocked/Passive
@onready var _unlocked_blurb: Label = $Unlocked/Blurb
@onready var _owners: Label = $Unlocked/Owners
@onready var _locked: VBoxContainer = $Locked
@onready var _locked_name: Label = $Locked/Name
@onready var _locked_weapon: Label = $Locked/Weapon
@onready var _price: Label = $Locked/Price
@onready var _hint: Label = $Locked/Hint
@onready var _locked_passive: Label = $Locked/Passive
@onready var _confirm: VBoxContainer = $Confirm
@onready var _confirm_monogram: Label = $Confirm/Portrait/Monogram
@onready var _confirm_name: Label = $Confirm/Name
@onready var _ask: Label = $Confirm/Ask
@onready var _unlock_yes: Button = %UnlockYes
## Lo comparten los retratos de Unlocked y Confirm (local a cada carta).
@onready var _portrait_style: StyleBoxFlat = \
		($Unlocked/Portrait as Panel).get_theme_stylebox(&"panel") as StyleBoxFlat


func _ready() -> void:
	UiTheme.attach_motion(self, hover_grow)
	# La carta escala desde su centro, pero su tamaño solo se conoce después
	# del primer layout: seguir `resized` mantiene el pivote centrado.
	resized.connect(func() -> void: pivot_offset = size * 0.5)
	UiTheme.style_button(_unlock_yes, UiTheme.SHARD_BLUE, true)
	_unlock_yes.pressed.connect(func() -> void: unlock_confirmed.emit(character_id))


## Pinta la carta con la fila `row` del catálogo en la cara `face`. `selected`
## la levanta y le da el borde del tinte; `owner_slots` son los slots de co-op
## (desde 0) que la eligieron, y se escriben bajo la descripción.
func show_character(row: Dictionary, face: Face, selected: bool,
		owner_slots: Array[int] = []) -> void:
	character_id = String(row.id)
	tooltip_text = _tooltip(row, face != Face.UNLOCKED)
	_unlocked.visible = face == Face.UNLOCKED
	_locked.visible = face == Face.LOCKED
	_confirm.visible = face == Face.CONFIRM
	match face:
		Face.UNLOCKED:
			_fill_unlocked(row, selected, owner_slots)
		Face.LOCKED:
			_fill_locked(row)
		Face.CONFIRM:
			_fill_confirm(row)
	settle(selected)


## Pose de reposo: la elegida sube un poco y se aclara, las demás se atenúan.
## Un tween por carta guardado en la metadata, para que los clics rápidos no
## apilen animaciones; también cancela (y endereza) un vaivén de rechazo.
func settle(selected: bool) -> void:
	pivot_offset = size * 0.5
	UiTheme.kill_meta_tween(self, SETTLE_TWEEN_KEY)
	rotation_degrees = 0.0
	var tween := create_tween()
	tween.set_ignore_time_scale(true)
	tween.set_parallel()
	tween.tween_property(self, "scale",
			Vector2.ONE * (selected_scale if selected else 1.0), settle_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate", rest_modulate(selected), settle_time)
	set_meta(SETTLE_TWEEN_KEY, tween)


## El movimiento de hover de UiTheme siempre devuelve el botón a escala 1.0,
## lo que borraría la elevación de la carta elegida al salir el mouse: se
## mata ese tween y se vuelve a la pose de reposo. El selector lo conecta a
## mouse_exited DESPUÉS del hover de UiTheme, para que este gane.
func resettle(selected: bool) -> void:
	UiTheme.kill_meta_tween(self, &"ui_motion_tween")
	settle(selected)


## "No alcanza": destello rojo y vaivén (UiTheme.reject) que termina en el
## modulate de reposo, no en blanco (una carta no elegida está atenuada).
func reject(selected: bool) -> void:
	UiTheme.reject(self, UiTheme.REJECT_SWINGS, UiTheme.REJECT_SWING_TIMES,
			rest_modulate(selected), SETTLE_TWEEN_KEY)


## Modulate de reposo: blanco la elegida, atenuada el resto.
func rest_modulate(selected: bool) -> Color:
	return Color.WHITE if selected else unselected_modulate


## El «Sí» mientras la carta pide confirmar el desbloqueo, o null.
func unlock_button() -> Button:
	return _unlock_yes if _confirm.visible else null


func _fill_unlocked(row: Dictionary, selected: bool, owner_slots: Array[int]) -> void:
	var tint := Color(row.tint)
	_paint_portrait(tint, String(row.display_name))
	_unlocked_name.text = String(row.display_name)
	_unlocked_weapon.text = String(row.weapon_display_name)
	_unlocked_passive.text = String(row.passive_description)
	_unlocked_blurb.text = String(row.blurb)
	var owners: Array[String] = []
	for slot in owner_slots:
		owners.append(UiTheme.PLAYER_TAG % (slot + 1))
	_owners.text = owners_separator.join(owners)
	_owners.visible = not owners.is_empty()
	UiTheme.style_card(self, tint if selected else idle_border_color,
			selected_border_width if selected else idle_border_width, selected)


func _fill_locked(row: Dictionary) -> void:
	_locked_name.text = String(row.display_name)
	_locked_weapon.text = String(row.weapon_display_name)
	_price.text = UiTheme.SHARDS_AMOUNT % int(row.get("unlock_cost", 0))
	var hint := String(row.get("unlock_hint", ""))
	_hint.visible = not hint.is_empty()
	if not hint.is_empty():
		_hint.text = hint_format % hint
	_locked_passive.text = String(row.passive_description)
	UiTheme.style_card(self, locked_border_color, idle_border_width, false)


func _fill_confirm(row: Dictionary) -> void:
	_paint_portrait(Color(row.tint), String(row.display_name))
	_confirm_name.text = String(row.display_name)
	_ask.text = confirm_format % int(row.get("unlock_cost", 0))
	UiTheme.style_card(self, confirm_border_color, selected_border_width)


## Tiñe el retrato (cuerpo, borde y brillo salen del tinte) y escribe la
## inicial del raider, que hace de cara mientras no haya arte de retrato.
func _paint_portrait(tint: Color, display_name: String) -> void:
	_portrait_style.bg_color = tint.darkened(portrait_body_darken)
	_portrait_style.border_color = tint.lightened(portrait_rim_lighten)
	_portrait_style.shadow_color = Color(tint.r, tint.g, tint.b, portrait_glow_alpha)
	for monogram: Label in [_unlocked_monogram, _confirm_monogram]:
		monogram.text = display_name.left(1).to_upper()
		monogram.visible = not display_name.is_empty()
		monogram.add_theme_color_override("font_outline_color",
				tint.darkened(monogram_outline_darken))


## El texto completo de la carta al pasar el mouse: la carta recorta la
## pasiva y la descripción para caber, el tooltip nunca.
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
