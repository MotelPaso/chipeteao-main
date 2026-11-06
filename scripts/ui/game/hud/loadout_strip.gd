class_name LoadoutStrip
extends HBoxContainer
## Franja de equipo del jugador 1, abajo en la pantalla. HUD.tscn tiene dos:
## BuildStrip (abajo a la izquierda: armas con su nivel, tomos con sus pilas
## y la mascota) y BagStrip (abajo a la derecha: objetos con sus copias). Se
## consulta cada `refresh_seconds` y se reconstruye solo cuando cambia su firma.
## El HUD le pasa el jugador con set_player al unir el grupo.

## Qué muestra una franja.
enum Contents {
	BUILD, ## Armas, tomos y mascota.
	BAG, ## Objetos de la bolsa.
}

const TILE_SCENE := preload("res://scenes/ui/hud/LoadoutTile.tscn")
## Los nombres de tomo llevan el tipo como prefijo ("Tomo de Furia") y el
## glifo de respaldo sale de lo que queda. Del más largo al más corto, para que
## "Tomo del Azar" pierda "Tomo del " entero y no solo "Tomo de " (dejaría
## "l Azar"). El prefijo en inglés queda para filas sin traducir.
const TOME_NAME_PREFIXES: Array[String] = ["Tome of ", "Tomo del ", "Tomo de "]

## Qué muestra esta franja: el equipo (armas, tomos y mascota) o la bolsa (objetos).
@export var contents: Contents = Contents.BUILD
## Segundos entre consultas del equipo del jugador.
@export var refresh_seconds: float = 0.5
## Espacio en blanco entre los grupos de casillas (armas, tomos, mascota), en píxeles.
@export var group_gap: float = 8.0
@export_group("Colores")
## Borde de las casillas de arma.
@export var weapon_color: Color = Color(0.3, 0.82, 0.76)
## Borde de un arma ya evolucionada.
@export var evolved_weapon_color: Color = UiTheme.ACCENT_AMBER
## Borde de las casillas de tomo.
@export var tome_color: Color = Color(0.72, 0.5, 0.95)
@export_group("Textos")
## Esquina de un arma que pasó su primer hito: ★ y el rango (★2 es el nivel 20).
@export var tier_format: String = "★%d"
## Esquina de un objeto con más de una copia.
@export var copies_format: String = "x%d"
## Tooltip de la mascota: su nombre y la estadística que da.
@export var pet_tip_format: String = "%s — %s"

var _player: Node = null
var _signature: String = ""
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
	if signature == _signature:
		return
	_signature = signature
	show_entries(entries)


## Armas (nivel, o rango con ★ desde el primer hito), tomos (pilas) y
## mascota del jugador, en ese orden.
func gather_build() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var mount := _player.get_node_or_null("Weapons")
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
				# Dos lecturas de la misma escala: el NIVEL del arma mientras
				# sube a su primer hito, después el RANGO del hito. "Sube el arma
				# al nivel 10" es esta esquina llegando a N10, y ★2 es el nivel 20.
				"corner": (tier_format % weapon.ascension_tier) if weapon.ascension_tier > 0 \
						else (UiTheme.WEAPON_LEVEL_ABBREV % weapon.upgrade_level),
				"tip": title, "icon": String(row.get("icon", "")),
			})
	var stats := PlayerStats.find_in(_player)
	if stats != null:
		for tome_id: String in stats.carried_tome_ids():
			var tome := Tome.by_id(tome_id)
			var title := String(tome.get("display_name", tome_id))
			entries.append({
				"glyph": LoadoutTile.catalog_glyph(tome, _tome_short_name(title)),
				"library": LoadoutTile.ICON_LIBRARY_TOMES,
				"entry_id": tome_id,
				"color": tome_color,
				"corner": Tome.stack_label(stats.stack_count(tome_id)),
				"tip": title, "icon": String(tome.get("icon", "")),
			})
	# La mascota cierra la franja de armas y tomos: es un arma fuera del tope
	# de cinco más una estadística, así que va junto a ellos y no entre los objetos.
	var pet_id: Variant = _player.get("pet_id")
	if pet_id != null and not String(pet_id).is_empty():
		var pet := PetCatalog.by_id(String(pet_id))
		if not pet.is_empty():
			entries.append({
				"glyph": String(pet.get("glyph", "??")),
				"library": LoadoutTile.ICON_LIBRARY_PETS,
				"entry_id": String(pet_id),
				"color": pet.get("color", Color.WHITE) as Color,
				"corner": "",
				"tip": pet_tip_format % [String(pet.display_name),
						String(pet.get("stat_label", ""))],
				"icon": String(pet.get("icon", "")),
			})
	return entries


## Objetos de la bolsa del jugador, en el orden en que los recogió, con sus copias.
func gather_bag() -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var bag := ItemBag.find_in(_player)
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
		})
	return items


## Reemplaza las casillas de la franja por `entries`, con un espacio en blanco
## cada vez que cambia la biblioteca (armas, tomos, mascota).
func show_entries(entries: Array[Dictionary]) -> void:
	for child: Node in get_children():
		# Primero fuera del contenedor: queue_free() recién actúa al final del
		# cuadro, y las casillas viejas se acomodarían junto a las nuevas por un
		# cuadro, haciendo saltar la franja cada vez que cambia el equipo.
		remove_child(child)
		child.queue_free()
	var last_library := ""
	for entry: Dictionary in entries:
		# El espacio se decide por la biblioteca que declara cada entrada y no
		# por su color (un arma evolucionada es ámbar).
		var library := String(entry.get("library", ""))
		if not last_library.is_empty() and library != last_library:
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(group_gap, 0.0)
			add_child(spacer)
		last_library = library
		var tile: LoadoutTile = TILE_SCENE.instantiate()
		add_child(tile)
		tile.show_entry(entry)


## La parte que distingue un nombre de tomo ("Tomo de Furia" -> "Furia"), para
## el glifo de respaldo: con el prefijo común todos los glifos serían iguales.
## Se quita un solo prefijo, del más largo al más corto (ver TOME_NAME_PREFIXES).
func _tome_short_name(display_name: String) -> String:
	for prefix: String in TOME_NAME_PREFIXES:
		if display_name.begins_with(prefix):
			return display_name.substr(prefix.length())
	return display_name
