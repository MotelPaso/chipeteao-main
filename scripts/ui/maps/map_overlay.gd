class_name MapOverlay
extends Control
## El mapa de Tab: una superposición del tamaño de la celda con toda la
## etapa, el equipo de este jugador, el grupo y lo que llevan.
##
## NO pausa. Un bullet-heaven no tiene un momento seguro para leer un menú,
## así que la horda sigue mientras el mapa está abierto: mirarlo es una
## decisión con costo. Se oculta solo en cuanto termina la partida, cuando
## algo que SÍ es dueño de la pausa pausa el árbol (el selector de cartas, el
## menú de pausa) o cuando el jugador de esta ranura ya no está.
##
## Una instancia por jugador, creada por el HUD en su propia CanvasLayer (capa
## 8: sobre el HUD, bajo el selector de cartas) y anclada a la celda de
## pantalla dividida de ese jugador.
##
## Foco: cada Control de aquí es FOCUS_NONE. Tab es el `ui_focus_next` de
## Godot, y un solo Control con foco en este árbol se comería la tecla antes
## de que el interruptor la vea.

## Qué jugador es dueño de este mapa (ranura 0-3). Lo asigna el HUD.
@export var slot: int = 0

## Fracción de la celda que ocupa el mapa (0-1); los paneles usan el resto.
const MAP_SHARE: float = 0.6
## Margen alrededor de todo, en píxeles.
const PAD: float = 18.0
## Separación entre el mapa y la columna de paneles, en píxeles.
const GUTTER: float = 14.0
## Segundos entre refrescos mientras el mapa está abierto. Mientras está
## oculto no se refresca NADA.
const REFRESH: float = 0.1
## Tamaño de la muestra de color de la leyenda, en píxeles.
const SWATCH := Vector2(12.0, 12.0)
const HEADER_FONT_SIZE: int = 20
const SECTION_FONT_SIZE: int = 15
const BODY_FONT_SIZE: int = 13

var _map: MapDraw = null
var _dim: ColorRect = null
var _header: Label = null
var _legend: VBoxContainer = null
var _powerups_body: Label = null
var _pet_body: Label = null
var _stats_body: Label = null
var _players_body: Label = null
var _items_body: Label = null
var _refresh_left: float = 0.0
## Minimap.composite_key() de la última composición de este mapa; vacío =
## desconocido, así que el próximo refresco compone sin condiciones.
var _composited: Array = []
## Último cuerpo que vio _has_raider() para esta ranura. Solo es un atajo
## para ese sí/no de cada cuadro: todo lo que lee al jugador vuelve a buscarlo.
var _seen_raider: Node3D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"map_overlay")
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_map = MapDraw.new(get_tree())
	_map.build_background()
	_build_ui()


## Gancho de etapa, reenviado por el HUD desde WorldDirector.on_stage_started.
func on_stage_started(arena: Node3D = null) -> void:
	if _map == null:
		_map = MapDraw.new(get_tree())
	_map.build_background(arena)
	# La clave no ve los píxeles reescritos dentro de una Image conocida (ver
	# Minimap.composite_key): se olvida.
	_composited = []
	_map.collect_markers()
	queue_redraw()


## Marcadores que hay ahora en este mapa (el soak lo lee por nombre).
func marker_count() -> int:
	return _map.marker_count() if _map != null else 0


func _process(delta: float) -> void:
	# Oculto cuando otra cosa es dueña de la pantalla. Se revisa ANTES del
	# interruptor para que una pulsación en el mismo cuadro que una muerte no
	# abra el mapa sobre la pantalla de fin.
	if not RunState.run_active or get_tree().paused or not _has_raider():
		if visible:
			visible = false
		return
	if Input.is_action_just_pressed(Coop.action(slot, &"map_overlay")):
		visible = not visible
		if visible and _map != null:
			# Se refresca AQUÍ y no en el próximo tick: el mapa debe estar al
			# día en el mismo cuadro en que aparece.
			_refresh_left = REFRESH
			_map.collect_markers()
			_composite_if_changed()
			_refresh_panels()
			queue_redraw()
	if not visible or _map == null:
		return
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = REFRESH
	# Métodos simples, sin Control: un soak headless ejercita todo el camino
	# del mapa aunque _draw() nunca se despache.
	_map.collect_markers()
	_composite_if_changed()
	_refresh_panels()
	queue_redraw()


## La misma puerta que la del minimapa (Minimap._composite_if_changed): el
## MapDraw propio de este mapa guarda la textura de su última composición,
## oculto o no, así que al abrirse solo recompone si la niebla cambió.
func _composite_if_changed() -> void:
	var key := Minimap.composite_key(_map, get_tree())
	if key == _composited:
		return
	_composited = key
	_map.composite()


## --- armado ---------------------------------------------------------------

func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(UiTheme.BG_DEEP, 0.88)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_own(_dim)
	add_child(_dim)
	_header = Label.new()
	_header.position = Vector2(PAD, PAD)
	UiTheme.style_title(_header, HEADER_FONT_SIZE, UiTheme.TEXT_BRIGHT, 3, 6)
	_own(_header)
	add_child(_header)
	_legend = VBoxContainer.new()
	_legend.add_theme_constant_override("separation", 3)
	_own(_legend)
	add_child(_legend)
	_build_legend()
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_own(column)
	add_child(column)
	_powerups_body = _add_section(column, "Power-ups")
	_pet_body = _add_section(column, "Mascota")
	_stats_body = _add_section(column, "Estadísticas")
	_players_body = _add_section(column, "Jugadores")
	_items_body = _add_section(column, "Objetos")
	_anchor_column(column)


## Un panel con título y un cuerpo de varias líneas; devuelve el Label del cuerpo.
func _add_section(column: VBoxContainer, title: String) -> Label:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",
			UiTheme.flat(UiTheme.PANEL_BG, UiTheme.RADIUS_SMALL))
	_own(panel)
	column.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_own(box)
	panel.add_child(box)
	var header := Label.new()
	header.text = title
	header.add_theme_font_size_override("font_size", SECTION_FONT_SIZE)
	header.add_theme_font_override("font", UiTheme.spaced_font(2))
	header.add_theme_color_override("font_color", UiTheme.ACCENT)
	_own(header)
	box.add_child(header)
	var body := Label.new()
	body.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	body.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_own(body)
	box.add_child(body)
	return body


func _anchor_column(column: VBoxContainer) -> void:
	column.anchor_left = MAP_SHARE
	column.anchor_right = 1.0
	column.anchor_top = 0.0
	column.anchor_bottom = 1.0
	column.offset_left = GUTTER
	column.offset_top = PAD
	column.offset_right = -PAD
	column.offset_bottom = -PAD


## Filas de la leyenda directo de MapDraw.MARKER_LABELS: un tipo agregado ahí
## aparece aquí sin tocar nada.
func _build_legend() -> void:
	for kind: StringName in MapDraw.MARKER_LABELS:
		var style: Dictionary = MapDraw.MARKER_STYLES.get(kind, {})
		if style.is_empty():
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_own(row)
		_legend.add_child(row)
		var swatch := ColorRect.new()
		swatch.color = style["color"]
		swatch.custom_minimum_size = SWATCH
		_own(swatch)
		row.add_child(swatch)
		var label := Label.new()
		label.text = MapDraw.MARKER_LABELS[kind]
		label.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
		label.add_theme_color_override("font_color", UiTheme.TEXT_FAINT)
		_own(label)
		row.add_child(label)


## Cada Control que crea este mapa: nunca toma foco (Tab es ui_focus_next) ni
## recibe el mouse (el mundo sigue vivo detrás).
func _own(control: Control) -> void:
	control.focus_mode = Control.FOCUS_NONE
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE


## --- contenido ------------------------------------------------------------

func _refresh_panels() -> void:
	var seconds := int(RunState.run_time)
	var title := "Etapa %d" % (RunState.stage_index + 1)
	if RunState.lap > 0:
		title += " · Vuelta %d" % (RunState.lap + 1)
	_header.text = "%s — %02d:%02d" % [title, seconds / 60, seconds % 60]
	_legend.position = Vector2(PAD, size.y - PAD - _legend.size.y)
	# Una sola búsqueda para los cuatro paneles que leen al jugador de esta
	# ranura: nada entre medio puede cambiar un cuerpo de grupo.
	var raider := _raider()
	_powerups_body.text = _powerups_text(raider)
	_pet_body.text = _pet_text(raider)
	_stats_body.text = _stats_text(raider)
	_players_body.text = _players_text()
	_items_body.text = _items_text(raider)


## El jugador de esta ranura, de pie o caído; null si la ranura está vacía.
func _raider() -> Node3D:
	for group: String in ["player", "downed_players"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body != null and int(body.get("player_index")) == slot:
				return body
	return null


## `_raider() != null`, preguntado cada cuadro aunque el mapa esté oculto,
## sin las dos búsquedas de grupo cuando el último cuerpo visto sigue
## respondiendo: dentro del árbol, en uno de los dos grupos y con esta ranura.
## Un cuerpo así es uno que encontraría la búsqueda de _raider(), así que no
## podría dar null; si no se cumple, decide la búsqueda completa y se recuerda.
## is_inside_tree() es obligatorio: un nodo conserva sus grupos al salir del
## árbol, pero las listas de grupo del árbol lo sueltan.
func _has_raider() -> bool:
	# Se lee por el miembro, nunca copiado antes a una variable local tipada:
	# un cuerpo liberado no se puede asignar a una variable tipada.
	if is_instance_valid(_seen_raider) and _seen_raider.is_inside_tree() \
			and (_seen_raider.is_in_group(&"player") \
				or _seen_raider.is_in_group(&"downed_players")) \
			and int(_seen_raider.get("player_index")) == slot:
		return true
	_seen_raider = _raider()
	return _seen_raider != null


## Power-ups activos con sus segundos restantes. El mapa es donde miras al
## decidir qué hacer, y "once segundos de Furia" es justo esa clase de decisión.
func _powerups_text(raider: Node3D) -> String:
	var powerups := PowerUps.find_in(raider)
	if powerups == null:
		return "—"
	var rows: PackedStringArray = PackedStringArray()
	for live: Dictionary in powerups.active():
		rows.append("%s  %ds" % [PowerUpCatalog.display_name_of(String(live.id)),
				ceili(float(live.time_left))])
	return "\n".join(rows) if not rows.is_empty() else "—"


## La capa de estadísticas derivadas, como la lee el jugador.
## `cooldown_multiplier` se muestra como VELOCIDAD DE ATAQUE y en POSITIVO
## (GLOSARIO regla 7): 0.8 es "+20% de velocidad de ataque", nunca "-20% de
## enfriamiento". Solo cambia la redacción, no el multiplicador.
func _stats_text(body: Node3D) -> String:
	var stats := PlayerStats.find_in(body) if body != null else null
	if stats == null:
		return "—"
	var rows: PackedStringArray = PackedStringArray()
	rows.append("Daño  %s" % _percent(stats.damage_multiplier - 1.0))
	rows.append("Velocidad de ataque  %s" % _percent(1.0 / maxf(stats.cooldown_multiplier, 0.01) - 1.0))
	rows.append("Área  %s" % _percent(stats.area_multiplier - 1.0))
	rows.append("Velocidad  %s" % _percent(stats.move_speed_multiplier - 1.0))
	rows.append("Prob. de crítico  %s" % _percent(stats.crit_chance))
	rows.append("Daño crítico  %s" % _percent(stats.crit_damage - 1.0))
	rows.append("Robo de vida  %s" % _percent(stats.lifesteal))
	rows.append("Armadura  %s" % _flat(stats.armor))
	rows.append("Evasión  %s" % _percent(stats.evasion))
	rows.append("Espinas  %s" % _flat(stats.thorns))
	rows.append("Suerte  %s" % _flat(stats.luck))
	rows.append("HP máx.  %s" % _flat(stats.bonus_max_hp))
	rows.append("Proyectiles  %s" % _flat(float(stats.projectile_bonus)))
	rows.append("Duración  %s" % _percent(stats.duration_multiplier - 1.0))
	rows.append("XP  %s" % _percent(stats.xp_multiplier - 1.0))
	rows.append("Saltos  %s" % _flat(float(stats.extra_jumps)))
	return "\n".join(rows)


func _percent(fraction: float) -> String:
	return "%+d%%" % roundi(fraction * 100.0)


func _flat(amount: float) -> String:
	return "%+d" % roundi(amount)


## Todo el grupo, caídos incluidos: saber que un compañero está en 0 de vida
## al otro lado del mapa es casi todo el propósito de este panel en co-op.
func _players_text() -> String:
	var rows: PackedStringArray = PackedStringArray()
	for player_slot: int in maxi(Coop.player_count, 1):
		var body := _raider_at(player_slot)
		var name_text := String(CharacterCatalog.by_id_or_default(
				Coop.character_for_slot(player_slot)).get("display_name", "—"))
		if body == null:
			rows.append("J%d  %s  —" % [player_slot + 1, name_text])
			continue
		var health := Health.find_in(body)
		var hp := "%d/%d" % [ceili(health.current_hp), roundi(health.max_hp)] \
				if health != null else "—"
		var points: Variant = body.get("points")
		rows.append("J%d  %s  %s  %s  %d pts" % [
				player_slot + 1, name_text, hp,
				UiTheme.LEVEL_ABBREV % RunState.level,
				int(points) if points != null else 0])
	return "\n".join(rows)


func _raider_at(player_slot: int) -> Node3D:
	for group: String in ["player", "downed_players"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body != null and int(body.get("player_index")) == player_slot:
				return body
	return null


## La línea de la mascota: nombre, su arma y la estadística que da. Se
## muestra aunque no haya mascota, porque "no tienes compañero" también es
## información cuando hay una caja de mascota en el mapa.
func _pet_text(body: Node3D) -> String:
	if body == null:
		return "—"
	var pet_id: Variant = body.get("pet_id")
	if pet_id == null or String(pet_id).is_empty():
		return "Sin mascota"
	var row := PetCatalog.by_id(String(pet_id))
	if row.is_empty():
		return "Sin mascota"
	return "%s  %s\n%s" % [String(row.display_name),
			PetCatalog.weapon_display_name(row), String(row.get("stat_label", ""))]


## Objetos con copias, luego armas con su nivel o rango de hito, luego
## tomos con sus pilas: las mismas tres familias que las franjas del HUD, con
## nombres completos porque aquí hay espacio.
func _items_text(body: Node3D) -> String:
	if body == null:
		return "—"
	var rows: PackedStringArray = PackedStringArray()
	var bag := ItemBag.find_in(body)
	if bag != null:
		for item_id: String in bag.carried_ids():
			var row := ItemCatalog.by_id(item_id)
			var display := String(row.get("display_name", item_id))
			var copies := bag.count(item_id)
			rows.append(display if copies <= 1 else "%s ×%d" % [display, copies])
	var mount := body.get_node_or_null("Weapons")
	if mount != null:
		for child: Node in mount.get_children():
			var weapon := child as WeaponBase
			if weapon == null:
				continue
			var display := weapon.evolved_name if weapon.evolved and not weapon.evolved_name.is_empty() \
					else UpgradePool.weapon_display_name(weapon.name)
			var tag := ("★%d" % weapon.ascension_tier) if weapon.ascension_tier > 0 \
					else (UiTheme.WEAPON_LEVEL_ABBREV % weapon.upgrade_level)
			rows.append("%s  %s" % [display, tag])
	var stats := PlayerStats.find_in(body)
	if stats != null:
		for tome_id: String in stats.carried_tome_ids():
			var tome := Tome.by_id(tome_id)
			rows.append("%s %s" % [String(tome.get("display_name", tome_id)),
					Tome.stack_label(stats.stack_count(tome_id))])
	return "\n".join(rows) if not rows.is_empty() else "—"


## --- dibujo ---------------------------------------------------------------

func _draw() -> void:
	if _map == null:
		return
	var side := minf(size.x * MAP_SHARE - PAD * 2.0, size.y - PAD * 2.0 - HEADER_FONT_SIZE * 2.0)
	if side <= 0.0:
		return
	var rect := Rect2(Vector2(PAD, PAD + HEADER_FONT_SIZE * 2.0), Vector2(side, side))
	draw_rect(rect.grow(3.0), Color(0.05, 0.055, 0.08, 0.9), true)
	_map.draw_into(self, rect)
	draw_rect(rect.grow(3.0), UiTheme.ACCENT.darkened(0.2), false, 2.0)
