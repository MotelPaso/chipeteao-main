class_name UpgradeCard
extends Button
## Una carta del selector de mejoras (UpgradeCardUI.tscn la instancia tres
## veces). El selector solo le pasa datos: show_rolled() con una mejora sorteada
## por UpgradePool, o show_choice() con una opción que armó quien abrió la
## elección. Tamaños de letra, márgenes y colores de texto están en los nodos
## de UpgradeCard.tscn; lo que depende de los datos (cinta, borde, brillo) se
## pinta aquí con los valores de abajo.

## Rareza (id de UpgradePool.RARITIES) cuya carta respira con brillo.
const SHINE_RARITY := "Legendary"
## Prefijo del target de las cartas que invierten en un arma ("weapon/<NodeName>").
const WEAPON_TARGET_PREFIX := "weapon/"

@export_group("Cinta")
## Color del texto de la cinta superior (la rareza o la etiqueta de la opción).
@export var ribbon_text_color: Color = Color(0.07, 0.075, 0.1)
## Espaciado extra entre letras de la cinta, en píxeles.
@export var ribbon_letter_spacing: int = 3
## Cuánto se aclara el borde de la cinta respecto de su color (0-1).
@export var ribbon_border_lighten: float = 0.2

@export_group("Opciones")
## Color de borde y brillo de una opción que no trae color propio.
@export var default_choice_color: Color = UiTheme.ACCENT_AMBER

@export_group("Brillo")
## Color al que sube una carta legendaria en cada respiro (valores sobre 1 la
## iluminan).
@export var shine_color: Color = Color(1.25, 1.18, 1.0)
## Segundos de cada mitad del respiro (subir o bajar).
@export var shine_half_time: float = 0.7

@export_group("Movimiento")
## Escala de la carta con el cursor o el foco encima.
@export var hover_grow: float = 1.05
## Escala de la carta al presionarla.
@export var press_squash: float = 0.97

@onready var _rarity_label: Label = %RarityLabel
@onready var _title_label: Label = %TitleLabel
@onready var _desc_label: Label = %DescLabel
@onready var _weapon_label: Label = %WeapLabel

## Brillo en bucle de una carta legendaria; null si no hay uno corriendo.
var _shine: Tween = null


func _ready() -> void:
	_rarity_label.add_theme_font_override("font", UiTheme.spaced_font(ribbon_letter_spacing))
	UiTheme.attach_motion(self, hover_grow, press_squash)


## Una mejora sorteada (fila de UpgradePool.roll_offer): la cinta lleva la
## rareza y su color pinta el borde y el brillo de la carta.
func show_rolled(item: Dictionary) -> void:
	var rarity: Dictionary = item.rarity
	var rarity_color := rarity.color as Color
	# Una carta de elección puede haber ocultado la cinta (opción sin etiqueta);
	# una carta sorteada siempre muestra ahí su rareza.
	_rarity_label.visible = true
	# rarity.name es un id (precios de cofre, filas de objetos y pisos de
	# min_rarity dependen de él): solo se traduce aquí, camino a la pantalla.
	_rarity_label.text = UpgradePool.rarity_display(String(rarity.name)).to_upper()
	_style_ribbon(rarity_color)
	_title_label.text = item.title
	_desc_label.text = item.description
	# Toda carta que invierte en un arma (target "weapon/<NodeName>": cartas de
	# stat por arma y extras del catálogo) nombra aquí el arma que mejora. Las
	# cartas de arma nueva, tomo y stat genérica no tienen ese target.
	var weapon_target := String(item.entry.get("target", ""))
	if weapon_target.begins_with(WEAPON_TARGET_PREFIX):
		_weapon_label.text = UpgradePool.weapon_display_name(
				weapon_target.get_slice("/", 1))
		_weapon_label.visible = true
	else:
		_weapon_label.visible = false
	UiTheme.style_card(self, rarity_color)
	if String(rarity.name) == SHINE_RARITY:
		_start_shine()
	else:
		self_modulate = Color.WHITE


## Una opción armada por quien abrió la elección ({title, description, color}):
## la cinta lleva `tag` en vez de una rareza (se oculta si viene vacía) y el
## color de la opción pinta el borde y el brillo.
func show_choice(option: Dictionary, tag: String) -> void:
	var color: Color = option.get("color", default_choice_color)
	_rarity_label.text = tag.to_upper()
	_rarity_label.visible = not tag.is_empty()
	_style_ribbon(color)
	_title_label.text = String(option.get("title", ""))
	_desc_label.text = String(option.get("description", ""))
	# Las opciones no apuntan a un arma: así el nombre de arma de una carta
	# sorteada nunca queda en una de elección.
	_weapon_label.visible = false
	UiTheme.style_card(self, color)
	self_modulate = Color.WHITE


## Mata el brillo en bucle. Usa set_loops() e ignora la escala de tiempo en una
## capa que procesa siempre: si queda corriendo, sigue escribiendo self_modulate
## en una carta oculta el resto de la partida.
func stop_shine() -> void:
	if _shine != null and _shine.is_valid():
		_shine.kill()
	_shine = null


## Píldora del color dado con texto oscuro, espaciada como un sello.
func _style_ribbon(color: Color) -> void:
	UiTheme.style_badge(_rarity_label, ribbon_text_color, color,
			color.lightened(ribbon_border_lighten))


## Brillo lento: toda la carta respira más clara (el brillo de sombra del
## stylebox la acompaña).
func _start_shine() -> void:
	stop_shine()
	_shine = create_tween().set_loops()
	_shine.set_ignore_time_scale(true)
	_shine.tween_property(self, "self_modulate", shine_color, shine_half_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_shine.tween_property(self, "self_modulate", Color.WHITE, shine_half_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
