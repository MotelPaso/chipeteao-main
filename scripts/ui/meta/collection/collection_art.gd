class_name CollectionArt
extends Panel
## El dibujo de una entrada de la Colección (CollectionArt.tscn): un marco con
## contorno de tinta sobre el color de la entrada, y adentro lo que le toque:
## la foto de un raider o de un enemigo, la postal de un mapa, el icono de un
## objeto o de un tomo con su sigla, o la sigla grande de un arma. Sin
## descubrir muestra la silueta de la foto si ya llegó, o un candado.
##
## La usan la carta (chica) y el detalle (grande). Quien la usa pasa la
## entrada de CollectionEntries (show_entry) y, cuando un estudio termina una
## foto, set_photo; el marco decide cómo se ve.

@export_group("Marco")
## Cuánto se oscurece el color de la entrada para el fondo (0-1).
@export_range(0.0, 1.0) var body_darken: float = 0.35
## Grosor del contorno de tinta, en píxeles.
@export var border_width: int = 3
## Radio de las esquinas, en píxeles.
@export var corner_radius: int = 10

@export_group("Contenido")
## Aire alrededor del icono, como fracción del lado más corto del marco.
@export_range(0.0, 0.4) var icon_padding: float = 0.14
## Tamaño de la sigla grande (armas), como fracción del alto del marco.
@export_range(0.1, 0.9) var glyph_height: float = 0.42
## Cuánto se oscurece el color de la entrada para el contorno de la sigla.
@export_range(0.0, 1.0) var glyph_outline_darken: float = 0.7
## Color de la silueta de una entrada sin descubrir.
@export var silhouette_color: Color = Color(0.03, 0.08, 0.09, 0.85)
## Duración (segundos) del fundido con que aparece la foto.
@export var photo_fade_time: float = 0.18

var _style: StyleBoxFlat = null
var _locked: bool = false
var _art: String = ""

@onready var _postcard: MapPostcard = %Postcard
@onready var _photo: TextureRect = %Photo
@onready var _icon: TextureRect = %Icon
@onready var _glyph: Label = %Glyph
@onready var _badge: Label = %Badge
@onready var _lock: Control = %Lock


func _ready() -> void:
	_style = UiTheme.flat(UiTheme.CARD_BG, corner_radius)
	_style.set_border_width_all(border_width)
	_style.border_color = UiTheme.INK
	add_theme_stylebox_override("panel", _style)
	resized.connect(_fit)
	_fit()


## Pinta el marco con esa entrada de CollectionEntries.
func show_entry(entry: Dictionary) -> void:
	_locked = bool(entry.get("locked", false))
	_art = String(entry.get("art", ""))
	var tint: Color = entry.get("tint", UiTheme.CARD_BG)
	_style.bg_color = tint.darkened(body_darken)
	_photo.texture = null
	_photo.visible = false
	# La foto de un raider llena el marco (es un busto); la de un enemigo se ve
	# entera, porque su cuerpo completo es lo que se colecciona.
	_photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED 			if _art == CollectionEntries.ART_ENEMY else TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_postcard.visible = _art == CollectionEntries.ART_MAP and not _locked
	if _postcard.visible:
		_postcard.show_palette(entry.get("palette", []))
	var icon: Texture2D = entry.get("icon")
	_icon.texture = icon
	_icon.visible = _art == CollectionEntries.ART_ICON and icon != null and not _locked
	var sigla := String(entry.get("glyph", ""))
	_glyph.text = sigla
	_glyph.visible = _art == CollectionEntries.ART_GLYPH and not _locked
	_glyph.add_theme_color_override("font_outline_color", tint.darkened(glyph_outline_darken))
	_badge.text = sigla
	_badge.visible = _icon.visible and not sigla.is_empty()
	# Respaldo de raiders y enemigos mientras no llega la foto (o si no hay
	# modelo): la inicial del nombre.
	if _uses_photo() and not _locked:
		_glyph.text = String(entry.get("name", "?")).left(1).to_upper()
		_glyph.visible = true
	_lock.visible = _locked
	_fit()


## Pone la foto de un raider o de un enemigo (de PortraitStudio o
## EnemyStudio). Sin descubrir se ve como silueta. Con null no cambia nada.
func set_photo(photo: Texture2D) -> void:
	if photo == null or not _uses_photo():
		return
	var had_photo := _photo.texture != null
	_photo.texture = photo
	_photo.visible = true
	_photo.self_modulate = silhouette_color if _locked else Color.WHITE
	_glyph.visible = false
	_lock.visible = false
	if had_photo:
		return
	_photo.modulate.a = 0.0
	var fade := _photo.create_tween()
	fade.set_ignore_time_scale(true)
	fade.tween_property(_photo, "modulate:a", 1.0, photo_fade_time) \
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)


func _uses_photo() -> bool:
	return _art == CollectionEntries.ART_RAIDER or _art == CollectionEntries.ART_ENEMY


## Medidas que dependen del tamaño del marco: el aire del icono y el tamaño
## de la sigla. El pivote al centro deja que la carta gire el marco.
func _fit() -> void:
	pivot_offset = size * 0.5
	var pad := minf(size.x, size.y) * icon_padding
	_icon.offset_left = pad
	_icon.offset_top = pad
	_icon.offset_right = -pad
	_icon.offset_bottom = -pad
	_glyph.add_theme_font_size_override("font_size", maxi(roundi(size.y * glyph_height), 8))
