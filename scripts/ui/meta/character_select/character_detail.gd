class_name CharacterDetail
extends PanelContainer
## Panel de detalle del selector de personaje (CharacterDetail.tscn): el
## raider que el jugador está mirando, con su retrato 3D, nombre, arma,
## pasiva y descripción completas, y su precio si está bloqueado. Las cartas
## de la cuadrícula son compactas; el texto largo vive aquí.
##
## El selector solo pasa la fila del catálogo y si está bloqueada
## (show_character); el panel decide cómo se ve y cómo entra. Cada etiqueta
## guarda su fuente y su color en la escena.

@export_group("Panel")
## Cuánto se oscurece el tinte del raider para el borde del panel (0-1).
@export_range(0.0, 1.0) var border_darken: float = 0.2
## Margen interior del panel (horizontal, vertical), en píxeles.
@export var panel_margin: Vector2 = Vector2(16.0, 14.0)

@export_group("Movimiento")
## Píxeles que se desliza el contenido al cambiar de raider (0 = solo fundido).
@export var slide_distance: float = 14.0
## Alfa (0-1) desde el que funde el contenido al cambiar de raider.
@export_range(0.0, 1.0) var fade_from: float = 0.0
## Duración (segundos) del cambio de raider.
@export var swap_time: float = 0.18

@export_group("Textos")
## Pista de desbloqueo por jefe junto al precio (%s = unlock_hint del catálogo).
@export var hint_format: String = "o %s"

## Id del raider que muestra el panel.
var character_id: String = ""

var _style: StyleBoxFlat = null
var _swap_tween: Tween = null

@onready var _body: Control = $Body
@onready var _content: VBoxContainer = $Body/Content
@onready var _portrait: CharacterPortrait = %Portrait
@onready var _name: Label = %Name
@onready var _weapon: Label = %Weapon
@onready var _passive: Label = %Passive
@onready var _blurb: Label = %Blurb
@onready var _lock_row: VBoxContainer = %LockRow
@onready var _price: Label = %Price
@onready var _hint: Label = %Hint


func _ready() -> void:
	_style = UiTheme.panel(UiTheme.PANEL_BG, UiTheme.BORDER_DIM,
			panel_margin.x, panel_margin.y)
	add_theme_stylebox_override("panel", _style)
	# Content se desliza dentro de Body, que no es un contenedor (así el layout
	# no pelea con el deslizamiento): Content toma el tamaño de Body, y Body
	# copia su alto mínimo para que el panel nunca quede más chico que su
	# contenido.
	_body.resized.connect(_fit_content)
	_content.minimum_size_changed.connect(_fit_content)
	_fit_content()


## Empieza a cargar los cuerpos 3D de esas filas (ver CharacterPortrait).
func preload_rows(rows: Array[Dictionary]) -> void:
	_portrait.preload_rows(rows)


## Muestra la fila `row` del catálogo; `locked` suma el precio en esquirlas y
## la pista del jefe. Si cambió el raider, el contenido entra con un fundido y
## un deslizamiento corto; `animate` apagado lo deja quieto (al abrir).
func show_character(row: Dictionary, locked: bool, animate: bool = true) -> void:
	# Al cerrar la pantalla, la carta con foco lo pierde cuando este panel ya
	# salió del árbol: no queda nada que mostrar.
	if not is_inside_tree():
		return
	var changed := String(row.id) != character_id
	# El primer raider que recibe el panel aparece quieto: lo anima la entrada
	# de la pantalla.
	var first := character_id.is_empty()
	character_id = String(row.id)
	_style.border_color = Color(row.tint).darkened(border_darken)
	_name.text = String(row.display_name)
	_weapon.text = String(row.weapon_display_name)
	_passive.text = String(row.passive_description)
	_blurb.text = String(row.get("blurb", ""))
	_lock_row.visible = locked
	if locked:
		_price.text = UiTheme.SHARDS_AMOUNT % int(row.get("unlock_cost", 0))
		var hint := String(row.get("unlock_hint", ""))
		_hint.visible = not hint.is_empty()
		_hint.text = hint_format % hint
	if changed:
		_portrait.show_character(row)
		if animate and not first:
			_play_swap()


## El retrato 3D del panel (para los arneses de prueba).
func portrait() -> CharacterPortrait:
	return _portrait


## Entrada del contenido nuevo. Si llega otro cambio a medio camino, sigue
## desde donde va en vez de volver a empezar: recorrer cartas rápido con el
## control no hace parpadear el panel.
func _play_swap() -> void:
	var running := _swap_tween != null and _swap_tween.is_valid() \
			and _swap_tween.is_running()
	if running:
		_swap_tween.kill()
	else:
		_content.modulate.a = fade_from
		_content.position.x = slide_distance
	_swap_tween = create_tween().set_parallel()
	_swap_tween.set_ignore_time_scale(true)
	_swap_tween.tween_property(_content, "modulate:a", 1.0, swap_time) \
			.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	_swap_tween.tween_property(_content, "position:x", 0.0, swap_time) \
			.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)


func _fit_content() -> void:
	_body.custom_minimum_size.y = _content.get_combined_minimum_size().y
	_content.size = _body.size
