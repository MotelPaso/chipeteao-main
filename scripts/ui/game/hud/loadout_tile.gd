class_name LoadoutTile
extends PanelContainer
## Una casilla de las franjas de equipo y de la fila de power-ups: un sticker
## del color de su tipo o rareza, con contorno de tinta y sombra dura, que
## lleva el ícono o, mientras no hay ícono, el glifo de dos letras del
## catálogo en tinta, y una esquina con nivel, pilas, copias o segundos. Quien
## la usa solo le pasa una entrada (show_entry) y, si la quiere chica,
## set_compact; el aspecto vive aquí y en LoadoutTile.tscn.
##
## Qué dibuja una casilla, en este orden:
##   1. el `icon` propio de la fila del catálogo;
##   2. res://assets/icons/<biblioteca>/<id>.png (así se agregan sprites por id
##      sin tocar código);
##   3. en tomos y objetos, el icono de su estadística o de su efecto especial
##      (ItemIcons / StatIcons, los mismos de la Colección);
##   4. el glifo de dos letras sobre el color (o sobre la imagen de reemplazo
##      con show_placeholder_art).

## Carpeta raíz de los íconos por id.
const ICON_ROOT := "res://assets/icons/"
## Imagen de reemplazo cuando no hay ícono propio (lleva el glifo encima).
const ICON_PLACEHOLDER := "res://assets/icons/placeholder.png"
## Bibliotecas de íconos: subcarpetas de ICON_ROOT.
const ICON_LIBRARY_WEAPONS := "weapons"
const ICON_LIBRARY_TOMES := "tomes"
const ICON_LIBRARY_ITEMS := "items"
const ICON_LIBRARY_POWERUPS := "powerups"
const ICON_LIBRARY_PETS := "pets"
## Bibliotecas cuyas filas de catálogo tienen icono de estadística (paso 3).
const STAT_ICON_LIBRARIES: Array[String] = [ICON_LIBRARY_TOMES, ICON_LIBRARY_ITEMS]

@export_group("Recuadro")
## Grosor del contorno de tinta, en píxeles. El cuerpo toma el color de la
## entrada.
@export var border_width: int = 3
## Radio de las esquinas, en píxeles.
@export var corner_radius: int = UiTheme.RADIUS_SMALL
## Sombra dura bajo la casilla (desplazamiento en píxeles).
@export var shadow_offset: Vector2 = Vector2(0.0, 3.0)
## Dibuja la imagen de reemplazo (assets/icons/placeholder.png) bajo el glifo
## de las entradas sin ícono propio. Apagado, el glifo va sobre el color.
@export var show_placeholder_art: bool = false
@export_group("Glifo")
## Tamaño de fuente del glifo en una casilla sin imagen, en píxeles.
@export var glyph_font_size: int = 18
## Tamaño de fuente del glifo sobre la imagen de reemplazo, en píxeles: más
## chico, para que se lea como etiqueta sobre el arte y no como el arte.
@export var placeholder_glyph_font_size: int = 13
## Grosor del contorno del glifo sobre la imagen de reemplazo, en píxeles.
@export var placeholder_glyph_outline: int = 4
## Espacio extra entre las letras del glifo, en píxeles.
@export var glyph_letter_spacing: int = 1
@export_group("Casilla chica")
## Lado de la casilla chica (la de los objetos de la bolsa), en píxeles. El de
## la casilla normal es Custom Minimum Size en LoadoutTile.tscn.
@export var compact_size: Vector2 = Vector2(34.0, 34.0)
## Tamaño de fuente del glifo en una casilla chica, en píxeles.
@export var compact_glyph_font_size: int = 14
## Tamaño de fuente de la esquina en una casilla chica, en píxeles. El de la
## casilla normal es el de Corner en LoadoutTile.tscn.
@export var compact_corner_font_size: int = 9

var _compact: bool = false
## Tamaño de la casilla normal (el de la escena), para volver de la chica.
var _normal_size: Vector2 = Vector2.ZERO

@onready var _icon: TextureRect = %Icon
@onready var _stat_icon: TextureRect = %StatIcon
@onready var _glyph: Label = %Glyph
@onready var _corner: Label = %Corner


func _ready() -> void:
	_glyph.add_theme_font_override("font", UiTheme.spaced_font(glyph_letter_spacing))


## Achica la casilla (compact_size y sus fuentes). Llamar después de agregarla
## al árbol y antes de show_entry.
func set_compact(on: bool) -> void:
	if on == _compact:
		return
	_compact = on
	if on:
		_normal_size = custom_minimum_size
		custom_minimum_size = compact_size
		_corner.add_theme_font_size_override("font_size", compact_corner_font_size)
	else:
		custom_minimum_size = _normal_size
		_corner.remove_theme_font_size_override("font_size")


## Pinta la casilla para `entry` = {glyph, library, entry_id, color, corner,
## tip, icon, row}. `row` es la fila del catálogo (opcional): de ella sale el
## icono de estadística de tomos y objetos. Llamar después de agregarla al árbol.
func show_entry(entry: Dictionary) -> void:
	var color: Color = entry.color
	tooltip_text = String(entry.tip)
	var style := UiTheme.flat(color, corner_radius)
	style.border_color = UiTheme.INK
	style.set_border_width_all(border_width)
	UiTheme.add_hard_shadow(style, shadow_offset)
	add_theme_stylebox_override("panel", style)
	var icon_path := icon_path_for(entry)
	if icon_path == ICON_PLACEHOLDER and not show_placeholder_art:
		icon_path = ""
	var on_placeholder := icon_path == ICON_PLACEHOLDER
	# Sin sprite propio, un tomo o un objeto dibuja el icono de su estadística.
	var stat_icon: Texture2D = stat_icon_for(entry) \
			if icon_path.is_empty() or on_placeholder else null
	if stat_icon != null:
		icon_path = ""
		on_placeholder = false
	_stat_icon.visible = stat_icon != null
	_stat_icon.texture = stat_icon
	_icon.visible = not icon_path.is_empty()
	if _icon.visible:
		_icon.texture = load(icon_path)
	# El glifo es el arte mientras no hay icono: solo sobre una casilla vacía,
	# o sobre la imagen de reemplazo para que se siga leyendo.
	_glyph.visible = stat_icon == null and (icon_path.is_empty() or on_placeholder)
	if _glyph.visible:
		_glyph.text = String(entry.glyph)
		var free_size := compact_glyph_font_size if _compact else glyph_font_size
		_glyph.add_theme_font_size_override("font_size",
				placeholder_glyph_font_size if on_placeholder else free_size)
		_glyph.add_theme_color_override("font_color",
				UiTheme.TEXT_BRIGHT if on_placeholder else UiTheme.INK)
		_glyph.add_theme_constant_override("outline_size",
				placeholder_glyph_outline if on_placeholder else 0)
	set_corner(String(entry.corner))


## Cambia la etiqueta de la esquina inferior derecha; un texto vacío la oculta.
## La etiqueta crece hacia arriba y a la izquierda desde su esquina en la
## escena, así que cualquier texto queda dentro de la casilla.
func set_corner(text: String) -> void:
	_corner.visible = not text.is_empty()
	_corner.text = text


## La textura que dibuja una casilla, en este orden: el `icon` propio de la
## fila, luego la convención por id (assets/icons/<biblioteca>/<id>.png) y
## luego el reemplazo común; vacío si no hay ninguna. ResourceLoader.exists con
## el tipo es la comprobación que también sirve en una build exportada, donde
## el PNG va empacado como .ctex y FileAccess sobre el .png responde false.
static func icon_path_for(entry: Dictionary) -> String:
	var declared := String(entry.get("icon", ""))
	if not declared.is_empty() and ResourceLoader.exists(declared, "Texture2D"):
		return declared
	var library := String(entry.get("library", ""))
	var entry_id := String(entry.get("entry_id", ""))
	if not library.is_empty() and not entry_id.is_empty():
		var path := "%s%s/%s.png" % [ICON_ROOT, library, entry_id]
		if ResourceLoader.exists(path, "Texture2D"):
			return path
	if ResourceLoader.exists(ICON_PLACEHOLDER, "Texture2D"):
		return ICON_PLACEHOLDER
	return ""


## El icono de estadística de una entrada de tomo u objeto (el mismo de la
## Colección), sacado de su fila de catálogo `row`. null si la entrada no es
## de esas bibliotecas, no trae fila o su fila no tiene icono propio: ahí la
## casilla cae al glifo en vez de repetir el icono genérico en todas.
static func stat_icon_for(entry: Dictionary) -> Texture2D:
	if not STAT_ICON_LIBRARIES.has(String(entry.get("library", ""))):
		return null
	var row: Dictionary = entry.get("row", {})
	if row.is_empty():
		return null
	var icon := ItemIcons.texture(row)
	return null if icon == StatIcons.texture("") else icon


## Glifo de una casilla: el `glyph` de dos letras de la fila del catálogo si
## lo declara; si no, el de respaldo. Toda fila del juego declara uno: las
## iniciales de los nombres en español chocan ("Vial de sangre" y "Vara de
## brasas" darían "VD"), y las franjas existen para distinguirlos.
static func catalog_glyph(row: Dictionary, fallback_title: String) -> String:
	var glyph := String(row.get("glyph", ""))
	return glyph if not glyph.is_empty() else glyph_for(fallback_title)


## SOLO respaldo (ver catalog_glyph): iniciales de un nombre de varias
## palabras, o sus dos primeras letras. Para una fila de catálogo que olvidó
## declarar su glifo; los nombres en español comparten demasiado la segunda
## palabra ("... de ...") como para que sea la fuente principal.
static func glyph_for(title: String) -> String:
	var words := title.split(" ", false)
	if words.size() >= 2:
		return (words[0].substr(0, 1) + words[1].substr(0, 1)).to_upper()
	return title.substr(0, 2).to_upper()
