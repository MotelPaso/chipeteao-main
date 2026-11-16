class_name CollectionCard
extends Button
## Carta compacta de una entrada en la cuadrícula de la Colección
## (CollectionCard.tscn): el dibujo arriba (CollectionArt) y el nombre abajo;
## sin descubrir, candado o silueta y «???». Se ve y se mueve como las cartas
## del selector de personaje, pero es un componente propio de la Colección.
## El texto largo se lee en el panel de detalle (CollectionDetail).
##
## La pantalla solo pasa la entrada de CollectionEntries (show_entry); la
## carta decide cómo se ve.
##
## Movimiento: con el foco del control o el mouse encima, la carta crece un
## poco, su anillo amarillo (FocusRing) aparece con un fundido y el dibujo,
## que en reposo está apenas girado como un sticker, se endereza; al
## presionarla se aplasta. Solo se animan scale, rotation y modulate, nunca
## el tamaño del layout.

## El foco o el mouse llegó a la carta: la pantalla muestra su detalle.
signal highlighted(entry_id: String)

## Llave de metadata del tween de pose: la entrada y el cambio de pose nunca
## mueven la carta a la vez.
const POSE_TWEEN_KEY := &"ui_pose_tween"

@export_group("Bordes")
## Borde de una carta descubierta.
@export var idle_border_color: Color = UiTheme.BORDER_DIM
## Borde de una carta sin descubrir.
@export var locked_border_color: Color = UiTheme.BORDER_LOCKED
## Grosor del borde, en píxeles.
@export var border_width: int = 2

@export_group("Texto")
## Color del nombre de una carta descubierta.
@export var name_color: Color = UiTheme.PAPER
## Color del nombre de una carta sin descubrir.
@export var locked_name_color: Color = UiTheme.TEXT_FAINT

@export_group("Movimiento")
## Giro del dibujo en reposo, en grados. Alterna de lado de una carta a la
## siguiente; con foco se endereza.
@export var art_tilt: float = 1.6
## Escala de la carta con el foco del control o el mouse encima.
@export var focus_scale: float = 1.05
## Escala de la carta mientras se mantiene presionada.
@export var press_scale: float = 0.97
## Modulate de una carta sin descubrir en reposo (más apagada).
@export var locked_modulate: Color = Color(0.8, 0.82, 0.86)
## Duración (segundos) del paso entre poses (crecer, anillo, aplastar).
@export var pose_time: float = 0.14
## Escala desde la que entra la carta al abrir la pantalla.
@export var entrance_start_scale: float = 0.95
## Duración (segundos) de la entrada de la carta.
@export var entrance_time: float = 0.24

## Id de la entrada que muestra la carta.
var entry_id: String = ""

var _locked: bool = false
## True entre button_down y button_up.
var _held: bool = false

@onready var _art: CollectionArt = %Art
@onready var _name: Label = %Name
@onready var _focus_ring: Panel = $FocusRing


func _ready() -> void:
	# La carta escala desde su centro, pero su tamaño solo se conoce después
	# del primer layout: seguir `resized` mantiene el pivote centrado.
	resized.connect(func() -> void: pivot_offset = size * 0.5)
	_focus_ring.add_theme_stylebox_override("panel", UiTheme.focus_ring(UiTheme.RADIUS))
	focus_entered.connect(_on_highlight_changed)
	focus_exited.connect(_on_highlight_changed)
	mouse_entered.connect(_on_highlight_changed)
	mouse_exited.connect(_on_highlight_changed)
	button_down.connect(_on_held_changed.bind(true))
	button_up.connect(_on_held_changed.bind(false))


## Pinta la carta con esa entrada de CollectionEntries.
func show_entry(entry: Dictionary) -> void:
	entry_id = String(entry.id)
	_locked = bool(entry.get("locked", false))
	_art.show_entry(entry)
	_name.text = String(entry.get("name", ""))
	_name.add_theme_color_override("font_color",
			locked_name_color if _locked else name_color)
	UiTheme.style_card(self, locked_border_color if _locked else idle_border_color,
			border_width, false)
	# El resalte lo dibuja FocusRing, que puede fundirse (un stylebox cambia
	# de golpe).
	add_theme_stylebox_override("hover", get_theme_stylebox(&"normal"))
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	settle()


## Pone la foto del raider o del enemigo en el dibujo de la carta.
func set_photo(photo: Texture2D) -> void:
	_art.set_photo(photo)


## Lleva la carta a su pose: escala y anillo según el foco y el mouse. Un solo
## tween por carta guardado en la metadata, así las pulsaciones rápidas lo
## redirigen en vez de apilar animaciones.
func settle() -> void:
	var lit := is_lit()
	pivot_offset = size * 0.5
	# Encima de sus vecinas mientras está agrandada, para que no la tapen.
	z_index = 1 if lit else 0
	UiTheme.kill_meta_tween(self, POSE_TWEEN_KEY)
	var target_scale := press_scale if _held else (focus_scale if lit else 1.0)
	var tween := create_tween().set_parallel()
	tween.set_ignore_time_scale(true)
	tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2.ONE * target_scale, pose_time)
	tween.tween_property(self, "modulate", rest_modulate(), pose_time)
	tween.tween_property(_focus_ring, "modulate:a", 1.0 if lit else 0.0, pose_time)
	tween.tween_property(_art, "rotation_degrees", 0.0 if lit else _rest_tilt(), pose_time)
	set_meta(POSE_TWEEN_KEY, tween)


## Entrada al abrir la pantalla: tras `delay` segundos, la carta funde y crece
## desde entrance_start_scale hasta su pose de reposo. Es decorativa: usar la
## carta antes de que termine la corta y la deja en su pose.
func play_entrance(delay: float) -> void:
	UiTheme.kill_meta_tween(self, POSE_TWEEN_KEY)
	var rest := rest_modulate()
	modulate = Color(rest, 0.0)
	scale = Vector2.ONE * entrance_start_scale
	var tween := create_tween().set_parallel()
	tween.set_ignore_time_scale(true)
	tween.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate", rest, entrance_time).set_delay(delay)
	tween.tween_property(self, "scale", Vector2.ONE, entrance_time).set_delay(delay)
	set_meta(POSE_TWEEN_KEY, tween)


## Modulate de reposo: blanco la descubierta y la que tiene el foco o el
## mouse, apagada la que está sin descubrir.
func rest_modulate() -> Color:
	return locked_modulate if _locked and not is_lit() else Color.WHITE


## True con el foco del control o el mouse encima.
func is_lit() -> bool:
	return has_focus() or is_hovered()


## Giro del dibujo en reposo: alterna de lado de una carta a la siguiente.
func _rest_tilt() -> float:
	return art_tilt if get_index() % 2 == 0 else -art_tilt


func _on_highlight_changed() -> void:
	settle()
	if is_lit():
		highlighted.emit(entry_id)


func _on_held_changed(held: bool) -> void:
	_held = held
	settle()
