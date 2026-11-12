class_name MapOverlay
extends Control
## El mapa de Tab (MapOverlay.tscn): una superposición del tamaño de la celda
## con toda la etapa, el equipo de este jugador, el grupo y lo que llevan.
## Los paneles, la leyenda y el encabezado son nodos de la escena; el mapa en
## sí se dibuja en _draw dentro del rectángulo de %MapArea.
##
## NO pausa. Un bullet-heaven no tiene un momento seguro para leer un menú,
## así que la horda sigue mientras el mapa está abierto: mirarlo es una
## decisión con costo. Se oculta solo en cuanto termina la partida, cuando
## algo que SÍ es dueño de la pausa pausa el árbol (el selector de cartas, el
## menú de pausa) o cuando el jugador de esta ranura ya no está. La escena
## guarda process_mode Always para que _process siga corriendo con el árbol en
## pausa y pueda ocultar el mapa.
##
## Una instancia por jugador, creada por el HUD (ViewWidgets) en su propia
## CanvasLayer (capa 8: sobre el HUD, bajo el selector de cartas) y anclada a
## la celda de pantalla dividida de ese jugador.
##
## Foco: ningún Control de aquí toma foco. Tab es el `ui_focus_next` de Godot,
## y un solo Control con foco en este árbol se comería la tecla antes de que
## el interruptor la vea.
##
## El soak lee `slot` y marker_count() por el grupo "map_overlay".

## Filas del panel de estadísticas, en orden. `property` es la propiedad de
## PlayerStats que se muestra (se lee POR NOMBRE: si se renombra allá, la fila
## muestra empty_text; el lint stat_rows lo revisa). `show` dice cómo se escribe:
##   "multiplier"    multiplicador que parte en 1.0, como +N%   (1.25 -> +25%)
##   "fraction"      fracción que parte en 0, como +N%          (0.1 -> +10%)
##   "flat"          número entero con signo                    (3 -> +3)
##   "attack_speed"  el multiplicador de enfriamiento leído como velocidad de
##                   ataque y en POSITIVO (GLOSARIO regla 7): 0.8 -> +25%.
const STAT_ROWS: Array[Dictionary] = [
	{"label": "Daño", "property": "damage_multiplier", "show": "multiplier"},
	{"label": "Velocidad de ataque", "property": "cooldown_multiplier", "show": "attack_speed"},
	{"label": "Área", "property": "area_multiplier", "show": "multiplier"},
	{"label": "Velocidad", "property": "move_speed_multiplier", "show": "multiplier"},
	{"label": "Prob. de crítico", "property": "crit_chance", "show": "fraction"},
	{"label": "Daño crítico", "property": "crit_damage", "show": "multiplier"},
	{"label": "Robo de vida", "property": "lifesteal", "show": "fraction"},
	{"label": "Armadura", "property": "armor", "show": "flat"},
	{"label": "Evasión", "property": "evasion", "show": "fraction"},
	{"label": "Espinas", "property": "thorns", "show": "flat"},
	{"label": "Suerte", "property": "luck", "show": "flat"},
	{"label": "HP máx.", "property": "bonus_max_hp", "show": "flat"},
	{"label": "Proyectiles", "property": "projectile_bonus", "show": "flat"},
	{"label": "Duración", "property": "duration_multiplier", "show": "multiplier"},
	{"label": "XP", "property": "xp_multiplier", "show": "multiplier"},
	{"label": "Saltos", "property": "extra_jumps", "show": "flat"},
]

@export_group("Jugador y refresco")
## Qué jugador es dueño de este mapa (ranura 0-3). Lo asigna el HUD.
@export var slot: int = 0
## Segundos entre refrescos mientras el mapa está abierto. Mientras está
## oculto no se refresca NADA.
@export var refresh_seconds: float = 0.1
@export_group("Mapa")
## Fondo del marco del mapa.
@export var frame_color: Color = Color(0.05, 0.055, 0.08, 0.9)
## Píxeles que el marco sobresale alrededor del mapa.
@export var frame_margin: float = 3.0
## Grosor del borde del marco, en píxeles.
@export var border_width: float = 2.0
## Cuánto se oscurece el turquesa de UiTheme.ACCENT para el borde (0-1).
@export var border_darken: float = 0.2
@export_group("Leyenda")
## Tamaño de la muestra de color de cada fila, en píxeles.
@export var swatch_size: Vector2 = Vector2(12.0, 12.0)
## Tamaño de letra de la leyenda, en píxeles.
@export var legend_font_size: int = 13
## Color del texto de la leyenda.
@export var legend_text_color: Color = UiTheme.TEXT_FAINT
## Separación entre la muestra y su texto, en píxeles.
@export var legend_row_separation: int = 6
@export_group("Encabezado")
## Espacio extra entre las letras del encabezado, en píxeles.
@export var header_letter_spacing: int = 3
@export_group("Textos")
## Texto de un panel sin nada que mostrar.
@export var empty_text: String = "—"
## Encabezado: la etapa (desde 1).
@export var stage_format: String = "Etapa %d"
## Se agrega al encabezado desde la segunda vuelta.
@export var lap_format: String = " · Vuelta %d"
## Encabezado completo: etapa (y vuelta), minutos y segundos de la partida.
@export var header_format: String = "%s — %02d:%02d"
## Fila de un power-up activo: nombre y segundos restantes.
@export var powerup_row_format: String = "%s  %ds"
## Panel de mascota cuando no lleva ninguna.
@export var no_pet_text: String = "Sin mascota"
## Panel de mascota: nombre, su arma y, abajo, la estadística que da.
@export var pet_format: String = "%s  %s\n%s"
## Fila de estadística: nombre y valor.
@export var stat_row_format: String = "%s  %s"
## Fila de un jugador: número, personaje, vida, nivel y puntos.
@export var player_row_format: String = "J%d  %s  %s  %s  %d pts"
## Fila de una ranura sin cuerpo: número y personaje.
@export var missing_player_format: String = "J%d  %s  —"
## Vida en la fila de un jugador: actual y máxima.
@export var player_hp_format: String = "%d/%d"
## Fila de un objeto con varias copias.
@export var item_copies_format: String = "%s ×%d"
## Fila de un arma: nombre y nivel o rango.
@export var weapon_row_format: String = "%s  %s"
## Rango de un arma que pasó su primer hito.
@export var tier_format: String = "★%d"
## Fila de un tomo: nombre y pilas.
@export var tome_row_format: String = "%s %s"

var _map: MapDraw = null
var _refresh_left: float = 0.0
## Minimap.composite_key() de la última composición de este mapa; vacío =
## desconocido, así que el próximo refresco compone sin condiciones.
var _composited: Array = []
## Último cuerpo que vio _has_raider() para esta ranura. Solo es un atajo
## para ese sí/no de cada cuadro: todo lo que lee al jugador vuelve a buscarlo.
var _seen_raider: Node3D = null

@onready var _header: Label = %Header
@onready var _legend: VBoxContainer = %Legend
@onready var _map_area: Control = %MapArea
@onready var _powerups_section: MapSection = %PowerUps
@onready var _pet_section: MapSection = %Pet
@onready var _stats_section: MapSection = %Stats
@onready var _players_section: MapSection = %Players
@onready var _items_section: MapSection = %Items


func _ready() -> void:
	add_to_group(&"map_overlay")
	_header.add_theme_font_override("font", UiTheme.spaced_font(header_letter_spacing))
	_map = MapDraw.new(get_tree())
	_map.build_background()
	_build_legend()


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
			_refresh_left = refresh_seconds
			_map.collect_markers()
			_composite_if_changed()
			_refresh_panels()
			queue_redraw()
	if not visible or _map == null:
		return
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = refresh_seconds
	# Métodos simples, sin Control: un soak headless ejercita todo el camino
	# del mapa aunque _draw() nunca se despache.
	_map.collect_markers()
	_composite_if_changed()
	_refresh_panels()
	queue_redraw()


## Dibuja el mapa cuadrado dentro de %MapArea. Lo dibuja este nodo, así que
## queda bajo sus hijos, Dim incluido.
func _draw() -> void:
	if _map == null:
		return
	var area := _map_area.get_rect()
	var side := minf(area.size.x, area.size.y)
	if side <= 0.0:
		return
	var rect := Rect2(area.position, Vector2(side, side))
	draw_rect(rect.grow(frame_margin), frame_color, true)
	_map.draw_into(self, rect)
	draw_rect(rect.grow(frame_margin), UiTheme.ACCENT.darkened(border_darken), false,
			border_width)


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


## La misma puerta que la del minimapa (Minimap._composite_if_changed): el
## MapDraw propio de este mapa guarda la textura de su última composición,
## oculto o no, así que al abrirse solo recompone si la niebla cambió.
func _composite_if_changed() -> void:
	var key := Minimap.composite_key(_map, get_tree())
	if key == _composited:
		return
	_composited = key
	_map.composite()


## Filas de la leyenda directo de MapDraw.MARKER_LABELS: un tipo agregado ahí
## aparece aquí sin tocar nada.
func _build_legend() -> void:
	for kind: StringName in MapDraw.MARKER_LABELS:
		var style: Dictionary = MapDraw.MARKER_STYLES.get(kind, {})
		if style.is_empty():
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", legend_row_separation)
		_own(row)
		_legend.add_child(row)
		var swatch := ColorRect.new()
		swatch.color = style["color"]
		swatch.custom_minimum_size = swatch_size
		_own(swatch)
		row.add_child(swatch)
		var label := Label.new()
		label.text = MapDraw.MARKER_LABELS[kind]
		label.add_theme_font_size_override("font_size", legend_font_size)
		label.add_theme_color_override("font_color", legend_text_color)
		_own(label)
		row.add_child(label)


## Cada Control que crea este mapa en código: nunca toma foco (Tab es
## ui_focus_next) ni recibe el mouse (el mundo sigue vivo detrás).
func _own(control: Control) -> void:
	control.focus_mode = Control.FOCUS_NONE
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _refresh_panels() -> void:
	var seconds := int(RunState.run_time)
	var title := stage_format % (RunState.stage_index + 1)
	if RunState.lap > 0:
		title += lap_format % (RunState.lap + 1)
	_header.text = header_format % [title, seconds / 60, seconds % 60]
	# Una sola búsqueda para los cuatro paneles que leen al jugador de esta
	# ranura: nada entre medio puede cambiar un cuerpo de grupo.
	var raider := PartySlots.raider_at(get_tree(), slot)
	_powerups_section.set_body(_powerups_text(raider))
	_pet_section.set_body(_pet_text(raider))
	_stats_section.set_body(_stats_text(raider))
	_players_section.set_body(_players_text())
	_items_section.set_body(_items_text(raider))


## `PartySlots.raider_at(slot) != null`, preguntado cada cuadro aunque el mapa
## esté oculto, sin las dos búsquedas de grupo cuando el último cuerpo visto
## sigue respondiendo: dentro del árbol, en uno de los dos grupos y con esta
## ranura. Un cuerpo así es uno que la búsqueda encontraría, así que no podría
## dar null; si no se cumple, decide la búsqueda completa y se recuerda.
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
	_seen_raider = PartySlots.raider_at(get_tree(), slot)
	return _seen_raider != null


## Power-ups activos con sus segundos restantes. El mapa es donde miras al
## decidir qué hacer, y "once segundos de Furia" es justo esa clase de decisión.
func _powerups_text(raider: Node3D) -> String:
	var powerups := PowerUps.find_in(raider)
	if powerups == null:
		return empty_text
	var rows: PackedStringArray = PackedStringArray()
	for live: Dictionary in powerups.active():
		rows.append(powerup_row_format % [PowerUpCatalog.display_name_of(String(live.id)),
				ceili(float(live.time_left))])
	return "\n".join(rows) if not rows.is_empty() else empty_text


## La capa de estadísticas derivadas, como la lee el jugador (ver STAT_ROWS).
func _stats_text(body: Node3D) -> String:
	var stats := PlayerStats.find_in(body) if body != null else null
	if stats == null:
		return empty_text
	var rows: PackedStringArray = PackedStringArray()
	for row: Dictionary in STAT_ROWS:
		rows.append(stat_row_format % [String(row.label), _stat_value(stats, row)])
	return "\n".join(rows)


func _stat_value(stats: PlayerStats, row: Dictionary) -> String:
	var raw: Variant = stats.get(String(row.property))
	if raw == null:
		return empty_text
	var value := float(raw)
	match String(row.show):
		"multiplier":
			return _percent(value - 1.0)
		"attack_speed":
			return _percent(1.0 / maxf(value, 0.01) - 1.0)
		"fraction":
			return _percent(value)
		_:
			return _flat(value)


func _percent(fraction: float) -> String:
	return "%+d%%" % roundi(fraction * 100.0)


func _flat(amount: float) -> String:
	return "%+d" % roundi(amount)


## Todo el grupo, caídos incluidos: saber que un compañero está en 0 de vida
## al otro lado del mapa es casi todo el propósito de este panel en co-op.
func _players_text() -> String:
	var rows: PackedStringArray = PackedStringArray()
	for player_slot: int in maxi(Coop.player_count, 1):
		var body := PartySlots.raider_at(get_tree(), player_slot)
		var name_text := String(CharacterCatalog.by_id_or_default(
				Coop.character_for_slot(player_slot)).get("display_name", empty_text))
		if body == null:
			rows.append(missing_player_format % [player_slot + 1, name_text])
			continue
		var health := Health.find_in(body)
		var hp := player_hp_format % [ceili(health.current_hp), roundi(health.max_hp)] \
				if health != null else empty_text
		var points: Variant = body.get("points")
		rows.append(player_row_format % [
				player_slot + 1, name_text, hp,
				UiTheme.LEVEL_ABBREV % RunState.level,
				int(points) if points != null else 0])
	return "\n".join(rows)


## La línea de la mascota: nombre, su arma y la estadística que da. Se
## muestra aunque no haya mascota, porque "no tienes compañero" también es
## información cuando hay una caja de mascota en el mapa.
func _pet_text(body: Node3D) -> String:
	if body == null:
		return empty_text
	var pet_id: Variant = body.get("pet_id")
	if pet_id == null or String(pet_id).is_empty():
		return no_pet_text
	var row := PetCatalog.by_id(String(pet_id))
	if row.is_empty():
		return no_pet_text
	return pet_format % [String(row.display_name),
			PetCatalog.weapon_display_name(row), String(row.get("stat_label", ""))]


## Objetos con copias, luego armas con su nivel o rango de hito, luego
## tomos con sus pilas: las mismas tres familias que las franjas del HUD, con
## nombres completos porque aquí hay espacio.
func _items_text(body: Node3D) -> String:
	if body == null:
		return empty_text
	var rows: PackedStringArray = PackedStringArray()
	var bag := ItemBag.find_in(body)
	if bag != null:
		for item_id: String in bag.carried_ids():
			var row := ItemCatalog.by_id(item_id)
			var display := String(row.get("display_name", item_id))
			var copies := bag.count(item_id)
			rows.append(display if copies <= 1 else item_copies_format % [display, copies])
	var mount := body.get_node_or_null("Weapons")
	if mount != null:
		for child: Node in mount.get_children():
			var weapon := child as WeaponBase
			if weapon == null:
				continue
			var display := weapon.evolved_name if weapon.evolved and not weapon.evolved_name.is_empty() \
					else UpgradePool.weapon_display_name(weapon.name)
			var tag := (tier_format % weapon.ascension_tier) if weapon.ascension_tier > 0 \
					else (UiTheme.WEAPON_LEVEL_ABBREV % weapon.upgrade_level)
			rows.append(weapon_row_format % [display, tag])
	var stats := PlayerStats.find_in(body)
	if stats != null:
		for tome_id: String in stats.carried_tome_ids():
			var tome := Tome.by_id(tome_id)
			rows.append(tome_row_format % [String(tome.get("display_name", tome_id)),
					Tome.stack_label(stats.stack_count(tome_id))])
	return "\n".join(rows) if not rows.is_empty() else empty_text
