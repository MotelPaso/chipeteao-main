class_name LoadoutStrip
extends Container
## Franja de equipo del jugador 1. HUD.tscn tiene dos, apiladas en LoadoutDock
## (abajo a la izquierda, crece hacia arriba y nunca llega a la barra de vida):
##   - BuildStrip, la fila de abajo: armas con su nivel, tomos con sus pilas y
##     con una línea de tinta entre grupo y grupo;
##   - BagStrip, encima: los objetos con sus copias en casillas chicas, en una
##     cuadrícula (sus columnas son `columns` del nodo). Si no caben en
##     `max_tiles`, la última casilla pasa a ser "+N".
## Se consulta cada `refresh_seconds` y solo toca las casillas cuando cambia
## su firma: si son las mismas, las actualiza en su lugar; si no, las rehace.
## La casilla nueva o que subió recibe un golpe de escala.
## El HUD le pasa el jugador con set_player al unir el grupo.
##
## El script extiende Container para servir a los dos nodos: BuildStrip es un
## HBoxContainer y BagStrip un GridContainer.

## Qué muestra una franja.
enum Contents {
	BUILD, ## Armas y tomos.
	BAG, ## Objetos de la bolsa.
}

const TILE_SCENE := preload("res://scenes/ui/hud/LoadoutTile.tscn")
## Los nombres de tomo llevan el tipo como prefijo ("Tomo de Furia") y el
## glifo de respaldo sale de lo que queda. Del más largo al más corto, para que
## "Tomo del Azar" pierda "Tomo del " entero y no solo "Tomo de " (dejaría
## "l Azar"). El prefijo en inglés queda para filas sin traducir.
const TOME_NAME_PREFIXES: Array[String] = ["Tome of ", "Tomo del ", "Tomo de "]

@export_group("Franja")
## Qué muestra esta franja: el equipo (armas y tomos) o la bolsa (objetos).
@export var contents: Contents = Contents.BUILD
## Segundos entre consultas del equipo del jugador.
@export var refresh_seconds: float = 0.5
## Casillas chicas (LoadoutTile > grupo «Casilla chica»): las de la bolsa.
@export var compact_tiles: bool = false
## Tope de casillas de la franja (columnas x filas en la bolsa); 0 = sin tope.
## Pasado el tope, la última casilla es "+N" con lo que no cupo.
@export var max_tiles: int = 0
@export_group("Separador de grupos")
## Tamaño de la línea entre los grupos de casillas (armas, tomos), en
## píxeles (ancho, alto).
@export var divider_size: Vector2 = Vector2(3.0, 30.0)
## Color de esa línea.
@export var divider_color: Color = UiTheme.INK
@export_group("Colores")
## Borde de las casillas de arma.
@export var weapon_color: Color = UiTheme.ACCENT_MINT
## Borde de un arma ya evolucionada.
@export var evolved_weapon_color: Color = UiTheme.ACCENT_AMBER
## Borde de las casillas de tomo.
@export var tome_color: Color = Color(0.72, 0.5, 0.95)
@export_group("Textos")
## Esquina de un objeto con más de una copia.
@export var copies_format: String = "x%d"
## Casilla "+N": cuántos objetos no cupieron en la franja.
@export var overflow_format: String = "+%d"
## Tooltip de la casilla "+N".
@export var overflow_tip_format: String = "%d objetos más"
@export_group("Casilla +N")
## Color de la casilla "+N".
@export var overflow_color: Color = UiTheme.PAPER
@export_group("Animación")
## Escala máxima del golpe de una casilla nueva o que subió de nivel.
@export var gain_pop_scale: float = 1.2
## Duración de ese golpe, en segundos.
@export var gain_pop_time: float = 0.2

var _player: Node = null
var _signature: String = ""
## Casillas en pantalla por clave ("biblioteca/id"), y lo que mostraba cada
## una ("esquina|tooltip") para saber cuál subió.
var _tiles: Dictionary[String, LoadoutTile] = {}
var _shown: Dictionary[String, String] = {}
## Falso hasta la primera consulta: el equipo con que empieza la partida no
## es una ganancia y no recibe golpe.
var _primed: bool = false
var _refresh_left: float = 0.0


func _process(delta: float) -> void:
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = refresh_seconds
	refresh()


## El jugador cuyo equipo muestra esta franja; null la deja quieta.
func set_player(body: Node) -> void:
	_player = body
	refresh()


## Junta el equipo del jugador y reconstruye la franja si cambió.
func refresh() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var entries := gather_build() if contents == Contents.BUILD else gather_bag()
	var signature := ""
	for entry: Dictionary in entries:
		signature += "%s|%s|%s;" % [entry.tip, entry.corner, entry.icon]
	if signature != _signature:
		_signature = signature
		show_entries(entries)
	_primed = true


## Armas (nivel) y tomos (pilas), en ese orden: del jugador de la franja o, si se pasa uno, de
## `body` (el mapa de Tab pide las de su propio jugador).
func gather_build(body: Node = null) -> Array[Dictionary]:
	var player := body if body != null else _player
	var entries: Array[Dictionary] = []
	var mount := player.get_node_or_null("Weapons")
	if mount != null:
		for child: Node in mount.get_children():
			var weapon := child as WeaponBase
			if weapon == null:
				continue
			# Nombre y glifo salen de los catálogos: la receta de evolución si
			# el arma evolucionó, la biblioteca de armas si no.
			var row := EvolutionCatalog.by_weapon_node(weapon.name) if weapon.evolved \
					else UpgradePool.weapon_by_node(weapon.name)
			var title := weapon.evolved_name if weapon.evolved \
					else UpgradePool.weapon_display_name(weapon.name)
			entries.append({
				"glyph": LoadoutTile.catalog_glyph(row, title),
				"library": LoadoutTile.ICON_LIBRARY_WEAPONS,
				"entry_id": UpgradePool.weapon_id_for_node(weapon.name),
				"color": evolved_weapon_color if weapon.evolved else weapon_color,
				# Siempre el NIVEL del arma, también evolucionada (el borde ámbar
				# ya dice que evolucionó).
				"corner": UiTheme.WEAPON_LEVEL_ABBREV % weapon.upgrade_level,
				"tip": title, "icon": String(row.get("icon", "")),
			})
	var stats := PlayerStats.find_in(player)
	if stats != null:
		for tome_id: String in stats.carried_tome_ids():
			var tome := Tome.by_id(tome_id)
			var title := String(tome.get("title", tome_id))
			entries.append({
				"glyph": _tome_glyph(tome, title),
				"library": LoadoutTile.ICON_LIBRARY_TOMES,
				"entry_id": tome_id,
				"color": tome_color,
				"corner": Tome.stack_label(stats.stack_count(tome_id)),
				"tip": title, "icon": String(tome.get("icon", "")), "row": tome,
			})
	return entries


## Objetos de la bolsa, en el orden en que se recogieron y con sus copias:
## del jugador de la franja o, si se pasa uno, de `body`.
func gather_bag(body: Node = null) -> Array[Dictionary]:
	var player := body if body != null else _player
	var items: Array[Dictionary] = []
	var bag := ItemBag.find_in(player)
	if bag == null:
		return items
	for item_id: String in bag.carried_ids():
		var row := ItemCatalog.by_id(item_id)
		var copies := bag.count(item_id)
		items.append({
			"glyph": LoadoutTile.catalog_glyph(row, item_id),
			"library": LoadoutTile.ICON_LIBRARY_ITEMS,
			"entry_id": item_id,
			"color": ItemCatalog.rarity_color(String(row.get("rarity", "Common"))),
			"corner": copies_format % copies if copies > 1 else "",
			"tip": String(row.get("display_name", item_id)), "icon": String(row.get("icon", "")),
			"row": row,
		})
	return items


## Muestra `entries` en la franja. Si son las mismas casillas en el mismo
## orden las actualiza en su lugar; si no, las rehace con una línea cada vez
## que cambia la biblioteca (armas, tomos). Con más entradas que
## `max_tiles`, la última casilla es "+N". La casilla nueva o cuya esquina
## cambió recibe un golpe de escala (salvo en la primera consulta).
func show_entries(entries: Array[Dictionary]) -> void:
	var fitted := _fit(entries)
	var keys: Array[String] = []
	for entry: Dictionary in fitted:
		keys.append(_key(entry))
	if keys != _tiles.keys():
		_rebuild(fitted, keys)
		return
	for i in fitted.size():
		var shown := _shown_text(fitted[i])
		if shown == _shown[keys[i]]:
			continue
		_shown[keys[i]] = shown
		_tiles[keys[i]].show_entry(fitted[i])
		_pop(_tiles[keys[i]])


## `entries` recortado a `max_tiles`: las que caben y, al final, la casilla
## "+N" con las que no.
func _fit(entries: Array[Dictionary]) -> Array[Dictionary]:
	if max_tiles <= 0 or entries.size() <= max_tiles:
		return entries
	var fitted := entries.slice(0, max_tiles - 1)
	var hidden := entries.size() - fitted.size()
	fitted.append({
		# Misma biblioteca que lo que resume, así no abre un grupo aparte.
		"glyph": overflow_format % hidden, "entry_id": "overflow",
		"library": String(entries[-1].get("library", "")),
		"color": overflow_color, "corner": "", "icon": "",
		"tip": overflow_tip_format % hidden,
	})
	return fitted


func _rebuild(entries: Array[Dictionary], keys: Array[String]) -> void:
	var old_keys := _tiles.keys()
	for child: Node in get_children():
		# Primero fuera del contenedor: queue_free() recién actúa al final del
		# cuadro, y las casillas viejas se acomodarían junto a las nuevas por un
		# cuadro, haciendo saltar la franja cada vez que cambia el equipo.
		remove_child(child)
		child.queue_free()
	_tiles.clear()
	_shown.clear()
	var last_library := ""
	for i in entries.size():
		var entry := entries[i]
		# La línea se decide por la biblioteca que declara cada entrada y no
		# por su color (un arma evolucionada es ámbar).
		var library := String(entry.get("library", ""))
		if not last_library.is_empty() and library != last_library:
			add_child(_divider())
		last_library = library
		var tile: LoadoutTile = TILE_SCENE.instantiate()
		add_child(tile)
		tile.set_compact(compact_tiles)
		tile.show_entry(entry)
		_tiles[keys[i]] = tile
		_shown[keys[i]] = _shown_text(entry)
		if not old_keys.has(keys[i]):
			_pop(tile)


## Golpe de escala de una casilla que el jugador acaba de ganar o subir.
## Diferido: una casilla recién agregada todavía no tiene tamaño y el golpe
## saldría desde su esquina.
func _pop(tile: LoadoutTile) -> void:
	if _primed:
		UiTheme.pop.call_deferred(tile, gain_pop_scale, gain_pop_time)


func _divider() -> ColorRect:
	var line := ColorRect.new()
	line.color = divider_color
	line.custom_minimum_size = divider_size
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


static func _key(entry: Dictionary) -> String:
	return "%s/%s" % [entry.get("library", ""), entry.get("entry_id", "")]


static func _shown_text(entry: Dictionary) -> String:
	return "%s|%s" % [entry.get("corner", ""), entry.get("tip", "")]


## La parte que distingue un nombre de tomo ("Tomo de Furia" -> "Furia"), para
## el glifo de respaldo: con el prefijo común todos los glifos serían iguales.
## Se quita un solo prefijo, del más largo al más corto (ver TOME_NAME_PREFIXES).
## La sigla de un tomo en su casilla: la `short` de su fila del catálogo (FU,
## CE…); sin ella, la que sale de su nombre.
func _tome_glyph(tome: Dictionary, title: String) -> String:
	var short := String(tome.get("short", ""))
	return short if not short.is_empty() else LoadoutTile.catalog_glyph(tome, _tome_short_name(title))


func _tome_short_name(display_name: String) -> String:
	for prefix: String in TOME_NAME_PREFIXES:
		if display_name.begins_with(prefix):
			return display_name.substr(prefix.length())
	return display_name
