class_name LoadoutTile
extends PanelContainer
## Una casilla de las franjas de equipo y de la fila de power-ups: un recuadro
## del color de su tipo o rareza con el ícono, o con el glifo de dos letras
## del catálogo mientras no hay ícono, y una esquina con nivel, pilas, copias
## o segundos. Quien la usa solo le pasa una entrada (show_entry); el aspecto
## vive aquí y en LoadoutTile.tscn.
##
## Convención de íconos: una casilla dibuja res://assets/icons/<biblioteca>/<id>.png
## si existe y, si no, la imagen de reemplazo con el glifo encima; así se
## agregan sprites por id sin tocar código. El `icon` propio de una fila de
## catálogo gana sobre ambos.

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

@export_group("Recuadro")
## Color de fondo de la casilla.
@export var background_color: Color = Color(UiTheme.TILE_BG, 0.9)
## Grosor del borde, en píxeles; el borde toma el color de la entrada.
@export var border_width: int = 2
## Radio de las esquinas, en píxeles.
@export var corner_radius: int = UiTheme.RADIUS_SMALL
## Tamaño del brillo exterior, en píxeles; toma el color de la entrada.
@export var glow_size: int = 6
## Opacidad del brillo exterior (0-1).
@export var glow_alpha: float = 0.25
@export_group("Glifo")
## Tamaño de fuente del glifo en una casilla sin imagen, en píxeles.
@export var glyph_font_size: int = 16
## Tamaño de fuente del glifo sobre la imagen de reemplazo, en píxeles: más
## chico, para que se lea como etiqueta sobre el arte y no como el arte.
@export var placeholder_glyph_font_size: int = 13
## Grosor del contorno del glifo sobre la imagen de reemplazo, en píxeles.
@export var placeholder_glyph_outline: int = 4
## Cuánto se aclara el color de la entrada para pintar el glifo (0-1).
@export var glyph_lighten: float = 0.25
## Espacio extra entre las letras del glifo, en píxeles.
@export var glyph_letter_spacing: int = 1

@onready var _icon: TextureRect = %Icon
@onready var _glyph: Label = %Glyph
@onready var _corner: Label = %Corner


func _ready() -> void:
	_glyph.add_theme_font_override("font", UiTheme.spaced_font(glyph_letter_spacing))


## Pinta la casilla para `entry` = {glyph, library, entry_id, color, corner,
## tip, icon}. Llamar después de agregarla al árbol.
func show_entry(entry: Dictionary) -> void:
	var color: Color = entry.color
	tooltip_text = String(entry.tip)
	var style := UiTheme.flat(background_color, corner_radius)
	style.border_color = color
	style.set_border_width_all(border_width)
	UiTheme.add_glow(style, color, glow_size, glow_alpha)
	add_theme_stylebox_override("panel", style)
	var icon_path := icon_path_for(entry)
	var on_placeholder := icon_path == ICON_PLACEHOLDER
	_icon.visible = not icon_path.is_empty()
	if _icon.visible:
		_icon.texture = load(icon_path)
	# El glifo es el arte mientras no hay sprite: solo sobre una casilla vacía,
	# o sobre la imagen de reemplazo para que se siga leyendo.
	_glyph.visible = icon_path.is_empty() or on_placeholder
	if _glyph.visible:
		_glyph.text = String(entry.glyph)
		_glyph.add_theme_font_size_override("font_size",
				placeholder_glyph_font_size if on_placeholder else glyph_font_size)
		_glyph.add_theme_color_override("font_color", color.lightened(glyph_lighten))
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
