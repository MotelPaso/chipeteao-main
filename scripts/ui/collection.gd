extends MetaScreen
## Collection screen (iteration 35): the completionist wall — every raider,
## weapon, evolution, and bestiary entry as discovered/undiscovered rows,
## with an overall completion percentage up top. Opened from the character
## select's Collection button. Undiscovered entries show as "???" teasers
## (evolutions include a vague recipe hint) so the screen doubles as the
## discovery map that pulls players back run after run.
##
## Chrome, Esc/Back and the staggered entrance come from MetaScreen; the
## badge here is a completion percentage, not a Shard balance.
##
## Discovery sources (SaveData counters, persisted at the run-end fold):
##   raiders:    SaveData.is_unlocked (the roster gate itself)
##   weapons:    used_weapon_<id>  (bumped on carry — spawn or card)
##   evolutions: evo_<weapon_id>   (bumped by the chest ceremony)
##   bestiary:   kills_<script>    (bumped by EnemyBase on death)

## Indent marker for evolution rows. Layout, not copy: it stays out of the
## translated strings so no locale ever has to carry the glyph.
const EVO_PREFIX := "⤷ "
const UNKNOWN := "???"

## Bestiary rows: script-file id -> display name + flavor. The id is the
## enemy's script file name (a SaveData key), so it stays in English; the
## name and flavor are what the player reads. Order is the reveal order on
## screen.
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


## Teal badge: this screen counts discoveries, not Shards.
func _badge_color() -> Color:
	return UiTheme.ACCENT


func _tracks_shards() -> bool:
	return false


func _build_rows(list_node: VBoxContainer) -> void:
	var found := 0
	var total := 0
	list_node.add_child(_section_header("RAIDERS"))
	for character: Dictionary in CharacterCatalog.CHARACTER_LIBRARY:
		total += 1
		if SaveData.is_unlocked(String(character.id)):
			found += 1
			list_node.add_child(_row(String(character.display_name),
					String(character.blurb), Color(character.tint)))
		else:
			list_node.add_child(_hidden_row("Un raider que sigue allá afuera..."))
	list_node.add_child(_section_header("ARSENAL"))
	for weapon: Dictionary in UpgradePool.WEAPON_LIBRARY:
		total += 2  # the weapon and its evolution each count
		var weapon_id := String(weapon.id)
		var carried := SaveData.stat("used_weapon_" + weapon_id) > 0
		if carried:
			found += 1
			list_node.add_child(_row(String(weapon.display_name),
					String(weapon.flavor), UiTheme.SHARD_BLUE))
		else:
			list_node.add_child(_hidden_row("Un arma sin reclamar..."))
		var recipe := EvolutionCatalog.by_weapon_id(weapon_id)
		if recipe.is_empty():
			total -= 1  # no evolution authored for this weapon
			continue
		if SaveData.stat("evo_" + weapon_id) > 0:
			found += 1
			list_node.add_child(_evo_row(String(recipe.evolved_name),
					"%s Nv %d: %s" % [String(weapon.display_name),
							EvolutionCatalog.EVOLVE_AT_LEVEL, String(recipe.flavor)],
					true))
		elif carried:
			list_node.add_child(_evo_row(UNKNOWN,
					"sube el arma al nivel %d para evolucionarla"
							% EvolutionCatalog.EVOLVE_AT_LEVEL,
					false))
		else:
			list_node.add_child(_evo_row(UNKNOWN, "una forma evolucionada te espera", false))
	list_node.add_child(_section_header("BESTIARIO"))
	for beast: Dictionary in BESTIARY:
		total += 1
		var kills := SaveData.stat("kills_" + String(beast.id))
		if kills > 0:
			found += 1
			list_node.add_child(_row(String(beast.display_name),
					"%s — %d abatidos" % [String(beast.flavor), kills],
					UiTheme.ACCENT_RED.lightened(0.15)))
		else:
			list_node.add_child(_hidden_row("Algo que aún no enfrentas..."))
	var percent := roundi(100.0 * float(found) / float(maxi(total, 1)))
	_badge_label.text = "Colección: %d / %d — %d%%" % [found, total, percent]


func _section_header(title: String) -> Label:
	var label := Label.new()
	label.text = title
	label.add_theme_font_override("font", UiTheme.spaced_font(3))
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", UiTheme.ACCENT_AMBER)
	return label


func _row(title: String, detail: String, accent: Color) -> PanelContainer:
	return _build_row(title, detail, accent, true)


func _hidden_row(tease: String) -> PanelContainer:
	return _build_row(UNKNOWN, tease, UiTheme.BORDER_LOCKED, false)


## Evolution rows sit indented under their weapon; discovered ones glow
## (the only rows on this screen that do — they are the rare find).
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
		row.modulate = Color(1.0, 1.0, 1.0, 0.55)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	row.add_child(box)
	var title_label := MetaScreen.label(title, 15,
			UiTheme.TEXT_BRIGHT if discovered else UiTheme.TEXT_FAINT)
	box.add_child(title_label)
	var detail_label := MetaScreen.label(detail, 11,
			UiTheme.TEXT_DIM if discovered else UiTheme.TEXT_FAINT)
	box.add_child(detail_label)
	return row
