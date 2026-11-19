class_name MapOverlay
extends Control
## El mapa de Tab (MapOverlay.tscn): una superposición del tamaño de la celda
## del jugador con toda la etapa a la izquierda (encabezado, mapa y leyenda) y
## sus paneles a la derecha: estadísticas, grupo, power-ups, mascota y equipo.
## Usa el diseño de la primera pantalla del menú (MainMenu.tscn): su velo
## petróleo con viñeta, su título amarillo y, por panel, una tarjeta de color
## como las de MenuTile (MapSection). El layout, las tarjetas y los colores
## son nodos de la escena; este script los llena y decide cuánto cabe.
##
## Se adapta a la celda. Parte con todo a la vista (Density.ROOMY) y, si los
## paneles no entran, baja un escalón: primero achica la letra y quita nombres
## y filas en cero (COMPACT), después quita los títulos (TIGHT). Nada se sale
## nunca de la celda: en co-op al lado está la vista de otro jugador.
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
## muestra un guion; el lint stat_rows lo revisa). `show` dice cómo se escribe:
##   "multiplier"    multiplicador que parte en 1.0, como +N%   (1.25 -> +25%)
##   "fraction"      fracción que parte en 0, como +N%          (0.1 -> +10%)
##   "flat"          número entero con signo                    (3 -> +3)
##   "attack_speed"  el multiplicador de enfriamiento leído como velocidad de
##                   ataque y en POSITIVO (GLOSARIO regla 7): 0.8 -> +25%.
## Opcionales: `short` es el nombre para las celdas chicas de co-op, donde el
## completo no cabe, y `base_property` la propiedad de PlayerStats con el
## valor de partida de la fila: mientras el valor sea ese, la fila se ve
## apagada como las que están en cero.
const STAT_ROWS: Array[Dictionary] = [
	{"label": "Daño", "property": "damage_multiplier", "show": "multiplier"},
	{"label": "Velocidad de ataque", "short": "Vel. de ataque",
		"property": "cooldown_multiplier", "show": "attack_speed"},
	{"label": "Área", "property": "area_multiplier", "show": "multiplier"},
	{"label": "Velocidad", "property": "move_speed_multiplier", "show": "multiplier"},
	{"label": "Prob. de crítico", "property": "crit_chance", "show": "fraction"},
	{"label": "Daño crítico", "property": "crit_damage", "show": "multiplier",
		"base_property": "base_crit_damage"},
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
## Segundos entre refrescos de los paneles mientras el mapa está abierto.
## Mientras está oculto no se refresca NADA.
@export var refresh_seconds: float = 0.1
@export_group("Mapa")
## Parte del ancho de la celda que puede ocupar el mapa (0-1); el resto es de
## los paneles. El mapa es cuadrado: su lado es lo que deja el alto de la celda
## después del encabezado y de la leyenda, sin pasar de esta parte del ancho.
@export_range(0.2, 0.8) var map_share: float = 0.5
## Lado mínimo del mapa, en píxeles.
@export var min_map_side: float = 160.0
## Una celda al menos así de ancha respecto de su alto (la de 2 jugadores)
## lleva la leyenda al pie de los paneles y no bajo el mapa: ahí el alto es lo
## que falta y el ancho lo que sobra.
@export var wide_cell_aspect: float = 2.6
@export_group("Tarjetas")
## Separación entre las tarjetas de los paneles con espacio, en píxeles. Tiene
## que dejar ver la sombra dura de la de arriba.
@export var panel_gap: int = 20
## Separación entre las tarjetas de los paneles en una celda chica, en píxeles.
@export var compact_panel_gap: int = 10
@export_group("Aparición")
## Segundos que tarda el mapa en aparecer al abrirlo.
@export var fade_seconds: float = 0.1
## Retraso, en segundos, entre el salto de una tarjeta y el de la siguiente.
@export var pop_stagger: float = 0.025
@export_group("Encabezado")
## Tamaño de letra del encabezado con espacio, en píxeles.
@export var header_font_size: int = 34
## Tamaño de letra del encabezado en una celda chica, en píxeles.
@export var compact_header_font_size: int = 20
## Grosor del contorno de tinta del encabezado con espacio, en píxeles.
@export var header_outline: int = 10
## Grosor del contorno de tinta del encabezado en una celda chica, en píxeles.
@export var compact_header_outline: int = 6
@export_group("Textos")
## Encabezado: la etapa (desde 1).
@export var stage_format: String = "Etapa %d"
## Se agrega al encabezado desde la segunda vuelta.
@export var lap_format: String = " · Vuelta %d"
## Encabezado completo: etapa (y vuelta), minutos y segundos de la partida.
@export var header_format: String = "%s — %02d:%02d"
## Chapa en la esquina del mapa: cuánto de la etapa exploró el grupo, en %.
@export var explored_format: String = "Explorado %d%%"
## Etiqueta de un power-up activo: los segundos que le quedan.
@export var powerup_seconds_format: String = "%ds"
## Panel de mascota cuando no lleva ninguna.
@export var no_pet_text: String = "Sin mascota"
## Panel de mascota: nombre, su arma y, abajo, la estadística que da.
@export var pet_format: String = "%s · %s\n%s"
## Indicación del botón que cierra el mapa, al pie de los paneles.
@export var close_hint: String = "Cerrar"

## Las franjas de equipo del HUD, que arman las entradas de armas, tomos y
## objetos de cualquier jugador (MapEntries.loadout): de ellas salen las
## fichas del panel «Objetos», con los mismos glifos y colores que las
## casillas del HUD. Las asigna ViewWidgets.
var build_strip: LoadoutStrip = null
var bag_strip: LoadoutStrip = null

var _map: MapDraw = null
var _refresh_left: float = 0.0
var _density: MapSection.Density = MapSection.Density.ROOMY
## Cuadros que faltan para volver a medir si los paneles caben: los
## contenedores se reacomodan al final del cuadro, no al cambiar la densidad.
var _settle_frames: int = 0
## Último cuerpo que vio _has_raider() para esta ranura. Solo es un atajo
## para ese sí/no de cada cuadro: todo lo que lee al jugador vuelve a buscarlo.
var _seen_raider: Node3D = null
## Los cinco paneles, para avisarles la densidad de una vez.
var _sections: Array[MapSection] = []
## El fundido de aparición en curso, para cortarlo si el mapa se reabre.
var _fade: Tween = null

@onready var _layout: MarginContainer = %Layout
@onready var _map_column: Control = %MapColumn
@onready var _header_row: Control = %HeaderRow
@onready var _square: Control = %Square
@onready var _header: Label = %Header
@onready var _explored: Label = %Explored
@onready var _map_view: MapView = %MapView
@onready var _legend: MapLegend = %Legend
@onready var _side_legend: MapLegend = %SideLegend
@onready var _side: Control = %Side
@onready var _panels: Control = %Panels
@onready var _extras: Control = %Extras
@onready var _hint_slot: Control = %HintSlot
@onready var _stats_panel: MapSection = %StatsPanel
@onready var _stats: MapStats = %Stats
@onready var _players_panel: MapSection = %PlayersPanel
@onready var _players: MapPlayers = %Players
@onready var _powerups_panel: MapSection = %PowerUpsPanel
@onready var _powerups: MapChips = %PowerUps
@onready var _pet_panel: MapSection = %PetPanel
@onready var _pet: Label = %Pet
@onready var _items_panel: MapSection = %ItemsPanel
@onready var _items: MapChips = %Items


func _ready() -> void:
	add_to_group(&"map_overlay")
	_sections = [_stats_panel, _players_panel, _powerups_panel, _pet_panel, _items_panel]
	_stats.setup(STAT_ROWS)
	# La tecla o el botón de ESTE jugador, como las indicaciones del menú.
	_hint_slot.add_child(InputHints.build(
			[[String(Coop.action(slot, &"map_overlay")), close_hint]]))
	_map_view.set_map(_map)
	resized.connect(_on_resized)
	_on_resized()


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
		if visible:
			_open()
	if not visible:
		return
	_fit_map()
	_fit_density()
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = refresh_seconds
	_refresh_panels()


## El mapa compartido que muestra este mapa de Tab (lo crea ViewWidgets).
func set_map(map: MapDraw) -> void:
	_map = map
	if is_node_ready():
		_map_view.set_map(map)


## Gancho de etapa, reenviado por el HUD desde WorldDirector.on_stage_started.
## El mapa compartido ya se reconstruyó; aquí solo se ponen al día los paneles
## de un mapa que quedó abierto.
func on_stage_started(_arena: Node3D = null) -> void:
	if visible:
		_refresh_panels()


## Marcadores que hay ahora en el mapa (el soak lo lee por nombre).
func marker_count() -> int:
	return _map.marker_count() if _map != null else 0


## Al abrirse: paneles al día en el mismo cuadro en que aparece, y un fundido
## corto que además tapa el cuadro en que los contenedores se acomodan.
func _open() -> void:
	_refresh_left = refresh_seconds
	_settle_frames = 2
	_refresh_panels()
	if _fade != null:
		_fade.kill()
	modulate.a = 0.0
	_fade = create_tween()
	# El hit-stop baja Engine.time_scale; el mapa aparece igual.
	_fade.set_ignore_time_scale(true)
	_fade.tween_property(self, "modulate:a", 1.0, fade_seconds)
	# Las tarjetas saltan una tras otra, como las del menú al entrar.
	var order := 0
	for section: MapSection in _sections:
		if section.is_visible_in_tree():
			section.pop(pop_stagger * order)
			order += 1


## La celda cambió de tamaño: el mapa y la densidad se vuelven a medir.
func _on_resized() -> void:
	_fit_map()
	_set_density(MapSection.Density.ROOMY)


## Da al mapa el lado que le deja el alto de la celda después del encabezado y
## de la leyenda, sin pasar de su parte del ancho. Se mide cada cuadro mientras
## el mapa está abierto: la leyenda cambia de alto cuando aparece un tipo nuevo.
func _fit_map() -> void:
	var inner := size - Vector2(
			_layout.get_theme_constant(&"margin_left") + _layout.get_theme_constant(&"margin_right"),
			_layout.get_theme_constant(&"margin_top") + _layout.get_theme_constant(&"margin_bottom"))
	var wide := size.x >= size.y * wide_cell_aspect
	_legend.visible = not wide
	_side_legend.visible = wide
	var gap := float(_map_column.get_theme_constant(&"separation"))
	var chrome := _header_row.get_combined_minimum_size().y + gap
	if not wide:
		chrome += _legend.get_combined_minimum_size().y + gap
	var side := floorf(clampf(inner.y - chrome, min_map_side, inner.x * map_share))
	if is_equal_approx(side, _square.custom_minimum_size.x):
		return
	_square.custom_minimum_size = Vector2(side, side)


## Baja un escalón de densidad mientras los paneles no quepan en su columna.
## Nunca vuelve a subir sola: cambiaría de tamaño cada vez que vence un power-up.
func _fit_density() -> void:
	if _settle_frames > 0:
		_settle_frames -= 1
		return
	if _density == MapSection.Density.TIGHT:
		return
	if _panels.get_combined_minimum_size().y <= _side.size.y + 0.5:
		return
	_set_density((_density + 1) as MapSection.Density)


func _set_density(level: MapSection.Density) -> void:
	_density = level
	var compact := level != MapSection.Density.ROOMY
	for section: MapSection in _sections:
		section.set_density(level)
	_stats.compact = compact
	_players.compact = compact
	_powerups.compact = compact
	_items.compact = compact
	_legend.compact = compact
	_side_legend.compact = compact
	_header.add_theme_font_size_override("font_size",
			compact_header_font_size if compact else header_font_size)
	_header.add_theme_constant_override("outline_size",
			compact_header_outline if compact else header_outline)
	var gap := compact_panel_gap if compact else panel_gap
	_panels.add_theme_constant_override("separation", gap)
	_extras.add_theme_constant_override("separation", gap)
	# La indicación de cierre solo cuando sobra el alto.
	_hint_slot.visible = not compact
	_settle_frames = 2
	if visible:
		_refresh_panels()


func _refresh_panels() -> void:
	var seconds := int(RunState.run_time)
	var title := stage_format % (RunState.stage_index + 1)
	if RunState.lap > 0:
		title += lap_format % (RunState.lap + 1)
	_header.text = header_format % [title, seconds / 60, seconds % 60]
	var fog := FogOfWar.find(get_tree())
	_explored.visible = fog != null
	if fog != null:
		_explored.text = explored_format % roundi(fog.explored_fraction() * 100.0)
	var kinds: Array[StringName] = []
	if _map != null:
		kinds = _map.legend_kinds()
	_legend.show_kinds(kinds)
	_side_legend.show_kinds(kinds)
	var compact := _density != MapSection.Density.ROOMY
	# Una sola búsqueda para los paneles que leen al jugador de esta ranura:
	# nada entre medio puede cambiar un cuerpo de grupo.
	var raider := PartySlots.raider_at(get_tree(), slot)
	_stats.show_stats(PlayerStats.find_in(raider) if raider != null else null)
	# En solitario el panel repetiría lo que el HUD ya muestra del jugador 1.
	_players_panel.visible = Coop.is_coop()
	if _players_panel.visible:
		_players.show_party(maxi(Coop.player_count, 1))
	var powerups := MapEntries.powerups(raider, powerup_seconds_format)
	_powerups.show_entries(powerups)
	# En una celda chica un panel vacío solo ocupa lugar, y la mascota pasa a
	# ser una ficha más del equipo, como en la franja del HUD.
	_powerups_panel.visible = not (compact and powerups.is_empty())
	_pet_panel.visible = not compact
	if not compact:
		_pet.text = MapEntries.pet_text(raider, pet_format, no_pet_text)
	_items.show_entries(MapEntries.loadout(raider, build_strip, bag_strip, compact))


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
