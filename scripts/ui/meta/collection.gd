extends MetaScreen
## Colección: el muro del completista. Cada raider, arma, evolución y entrada
## del bestiario como fila descubierta o por descubrir, con el porcentaje
## total arriba. Se abre desde el botón Colección del selector. Lo no
## descubierto se muestra como "???" (las evoluciones con una pista vaga de
## la receta).
##
## Cromo, Esc/Volver y la entrada escalonada vienen de MetaScreen; aquí la
## insignia es un porcentaje de completado, no un saldo de esquirlas.
##
## Fuentes de descubrimiento (contadores de SaveData, guardados al cerrar la
## partida):
##   raiders:     SaveData.is_unlocked (el mismo candado del plantel)
##   armas:       used_weapon_<id>  (suma al llevarla: al aparecer o por carta)
##   evoluciones: evo_<weapon_id>   (suma en la ceremonia del cofre)
##   bestiario:   kills_<script>    (suma EnemyBase al morir)

## Sangría de las filas de evolución. Es diseño, no texto: queda fuera de las
## cadenas traducidas.
const EVO_PREFIX := "⤷ "

## Filas del bestiario, en el orden en que aparecen en pantalla. Edita aquí.
##
## | campo        | regla                                                  |
## |--------------|--------------------------------------------------------|
## | id           | nombre del archivo del script del enemigo, sin ".gd"   |
## |              | (scripts/enemies/<id>.gd): EnemyBase suma kills_<id> al |
## |              | morir. Un id que no calce nunca se descubre.           |
## | display_name | nombre en pantalla; en los jefes copia el boss_title de |
## |              | su escena (Rotking, Sarcognath, Fenwraith, Grubthing,  |
## |              | CofferMimic .tscn): si cambias uno, cambia el otro.     |
## | flavor       | texto corto bajo el nombre.                            |
const BESTIARY: Array[Dictionary] = [
	{"id": "grunt", "display_name": "Esbirro", "flavor": "la marea misma"},
	{"id": "skirmisher", "display_name": "Hostigador", "flavor": "guarda distancia y lanza saetas"},
	{"id": "tank", "display_name": "Mole", "flavor": "acorazado, lento, implacable"},
	{"id": "sunspitter", "display_name": "Escupesol", "flavor": "artillería láser a línea de visión"},
	{"id": "duneburrower", "display_name": "Excavadunas", "flavor": "embosca desde abajo"},
	{"id": "rotking", "display_name": "Rey Pútrido", "flavor": "jefe del Bosque Hueco"},
	{"id": "sarcognath", "display_name": "Sarcognato", "flavor": "jefe de las Dunas de Ceniza"},
	{"id": "fenwraith", "display_name": "Espectro de la Ciénaga", "flavor": "jefe de la Ciénaga Lóbrega"},
	{"id": "grubthing", "display_name": "Larvón", "flavor": "lo que duerme bajo el bosque"},
	{"id": "coffer_mimic", "display_name": "Cofre Mímico", "flavor": "la cosa sepulcral de las dunas"},
]

@export_group("Filas")
## Tamaño de fuente de los títulos de sección (RAIDERS, ARSENAL, BESTIARIO), en píxeles.
@export var section_font_size: int = 16
## Color de los títulos de sección.
@export var section_color: Color = UiTheme.ACCENT_AMBER
## Espacio extra entre las letras de los títulos de sección, en píxeles.
@export var section_spacing: int = 1
## Tamaño de fuente del título de cada fila, en píxeles.
@export var title_font_size: int = 15
## Color del título de una fila descubierta.
@export var title_color: Color = UiTheme.TEXT_BRIGHT
## Tamaño de fuente del detalle bajo el título, en píxeles.
@export var detail_font_size: int = 11
## Color del detalle de una fila descubierta.
@export var detail_color: Color = UiTheme.TEXT_DIM
## Color del título y del detalle de una fila sin descubrir.
@export var hidden_text_color: Color = UiTheme.TEXT_FAINT
## Modulate de una fila sin descubrir (atenuada).
@export var hidden_row_modulate: Color = Color(1.0, 1.0, 1.0, 0.55)
## Separación vertical entre el título y el detalle de cada fila, en píxeles.
@export var row_separation: int = 2
## Cuánto se aclara el rojo de acento (UiTheme.ACCENT_RED) en el borde de las
## filas del bestiario ya descubiertas (0-1).
@export var bestiary_row_lighten: float = 0.15

@export_group("Textos")
## Insignia de arriba (%d = descubiertos, %d = total, %d = porcentaje).
@export var badge_format: String = "Colección: %d / %d — %d%%"
## Título de la sección de raiders.
@export var raiders_title: String = "RAIDERS"
## Título de la sección de armas y evoluciones.
@export var arsenal_title: String = "ARSENAL"
## Título de la sección del bestiario.
@export var bestiary_title: String = "BESTIARIO"
## Título de una fila sin descubrir (raider, arma, evolución o enemigo).
@export var unknown_text: String = "???"
## Detalle de un raider sin desbloquear.
@export var hidden_raider_text: String = "Un raider que sigue allá afuera..."
## Detalle de un arma que nunca se llevó.
@export var hidden_weapon_text: String = "Un arma sin reclamar..."
## Detalle de una evolución descubierta (%s = arma, %d = nivel, %s = flavor).
@export var evo_found_format: String = "%s Nv %d: %s"
## Detalle de una evolución sin descubrir de un arma ya llevada (%d = nivel).
@export var evo_hint_format: String = "sube el arma al nivel %d para evolucionarla"
## Detalle de una evolución sin descubrir de un arma nunca llevada.
@export var evo_unknown_text: String = "una forma evolucionada te espera"
## Detalle de un enemigo abatido (%s = flavor, %d = bajas).
@export var kills_format: String = "%s — %d abatidos"
## Detalle de un enemigo que nunca se abatió.
@export var hidden_beast_text: String = "Algo que aún no enfrentas..."


## La insignia cuenta descubrimientos, no esquirlas.
func _tracks_shards() -> bool:
	return false


func _build_rows(list_node: VBoxContainer) -> void:
	var found := 0
	var total := 0
	list_node.add_child(_section_header(raiders_title))
	for character: Dictionary in CharacterCatalog.CHARACTER_LIBRARY:
		total += 1
		if SaveData.is_unlocked(String(character.id)):
			found += 1
			list_node.add_child(_row(String(character.display_name),
					String(character.blurb), Color(character.tint)))
		else:
			list_node.add_child(_hidden_row(hidden_raider_text))
	list_node.add_child(_section_header(arsenal_title))
	for weapon: Dictionary in UpgradePool.WEAPON_LIBRARY:
		total += 2  # el arma y su evolución cuentan por separado
		var weapon_id := String(weapon.id)
		var carried := SaveData.stat("used_weapon_" + weapon_id) > 0
		if carried:
			found += 1
			list_node.add_child(_row(String(weapon.display_name),
					String(weapon.flavor), UiTheme.SHARD_BLUE))
		else:
			list_node.add_child(_hidden_row(hidden_weapon_text))
		var recipe := EvolutionCatalog.by_weapon_id(weapon_id)
		if recipe.is_empty():
			total -= 1  # esta arma no tiene evolución
			continue
		if SaveData.stat("evo_" + weapon_id) > 0:
			found += 1
			list_node.add_child(_evo_row(String(recipe.evolved_name),
					evo_found_format % [String(weapon.display_name),
							EvolutionCatalog.EVOLVE_AT_LEVEL, String(recipe.flavor)],
					true))
		elif carried:
			list_node.add_child(_evo_row(unknown_text,
					evo_hint_format % EvolutionCatalog.EVOLVE_AT_LEVEL,
					false))
		else:
			list_node.add_child(_evo_row(unknown_text, evo_unknown_text, false))
	list_node.add_child(_section_header(bestiary_title))
	for beast: Dictionary in BESTIARY:
		total += 1
		var kills := SaveData.stat("kills_" + String(beast.id))
		if kills > 0:
			found += 1
			list_node.add_child(_row(String(beast.display_name),
					kills_format % [String(beast.flavor), kills],
					UiTheme.ACCENT_RED.lightened(bestiary_row_lighten)))
		else:
			list_node.add_child(_hidden_row(hidden_beast_text))
	var percent := roundi(100.0 * float(found) / float(maxi(total, 1)))
	_badge_label.text = badge_format % [found, total, percent]


func _section_header(title: String) -> Label:
	var header := Label.new()
	header.text = title
	header.add_theme_font_override("font", UiTheme.spaced_font(section_spacing))
	header.add_theme_font_size_override("font_size", section_font_size)
	header.add_theme_color_override("font_color", section_color)
	return header


func _row(title: String, detail: String, accent: Color) -> PanelContainer:
	return _build_row(title, detail, accent, true)


func _hidden_row(tease: String) -> PanelContainer:
	return _build_row(unknown_text, tease, UiTheme.BORDER_LOCKED, false)


## Las filas de evolución van con sangría bajo su arma; las descubiertas
## brillan (las únicas de la pantalla: son el hallazgo raro).
func _evo_row(title: String, detail: String, discovered: bool) -> PanelContainer:
	return _build_row(EVO_PREFIX + title, detail,
			UiTheme.ACCENT_AMBER if discovered else UiTheme.BORDER_LOCKED,
			discovered, discovered)


func _build_row(title: String, detail: String, accent: Color,
		discovered: bool, glow: bool = false) -> PanelContainer:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", MetaScreen.card_style(
			accent if discovered else UiTheme.BORDER_LOCKED, glow))
	if not discovered:
		row.modulate = hidden_row_modulate
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", row_separation)
	row.add_child(box)
	var title_label := MetaScreen.label(title, title_font_size,
			title_color if discovered else hidden_text_color)
	box.add_child(title_label)
	var detail_label := MetaScreen.label(detail, detail_font_size,
			detail_color if discovered else hidden_text_color)
	box.add_child(detail_label)
	return row
