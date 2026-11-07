class_name PowerUpRow
extends HBoxContainer
## Fila de power-ups activos del jugador 1, abajo al centro: una casilla por
## power-up con su glifo y los segundos que le quedan. En co-op la fila de
## cada compañero muestra solo un conteo (ver MateRow).
## El HUD le pasa el jugador con set_player al unir el grupo.

const TILE_SCENE := preload("res://scenes/ui/hud/LoadoutTile.tscn")

## Segundos entre consultas de los power-ups del jugador.
@export var refresh_seconds: float = 0.2
## Esquina de cada casilla: los segundos que le quedan al power-up.
@export var seconds_format: String = "%ds"

var _player: Node = null
## Ids de las casillas, en orden: la ESTRUCTURA de la fila. Solo un cambio aquí
## reconstruye la fila; los segundos de las esquinas se cambian en su lugar.
var _ids: String = ""
## Texto de la esquina de cada casilla, en el mismo orden.
var _corner_texts: PackedStringArray = PackedStringArray()
var _refresh_left: float = 0.0


func _process(delta: float) -> void:
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = refresh_seconds
	refresh()


## El jugador cuyos power-ups muestra la fila; null la deja quieta.
func set_player(body: Node) -> void:
	_player = body


## Reconstruye la fila cuando cambió el CONJUNTO de power-ups y solo cambia
## las esquinas cuando cambiaron los segundos enteros (una vez por segundo
## mientras corra alguno): reconstruir rehace nodos y busca íconos en disco.
func refresh() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var powerups := PowerUps.find_in(_player)
	var entries: Array[Dictionary] = []
	if powerups != null:
		for live: Dictionary in powerups.active():
			var powerup_id := String(live.id)
			var row := PowerUpCatalog.by_id(powerup_id)
			entries.append({
				"glyph": String(row.get("glyph", "??")),
				"library": LoadoutTile.ICON_LIBRARY_POWERUPS,
				"entry_id": powerup_id,
				"color": row.get("color", Color.WHITE) as Color,
				"corner": seconds_format % ceili(float(live.time_left)),
				"tip": String(row.get("display_name", powerup_id)),
				"icon": String(row.get("icon", "")),
			})
	var ids := ""
	var corners := PackedStringArray()
	for entry: Dictionary in entries:
		ids += "%s;" % entry.entry_id
		corners.append(String(entry.corner))
	if ids == _ids:
		_update_corners(corners)
		return
	_ids = ids
	_corner_texts = corners
	show_entries(entries)


## Reemplaza las casillas de la fila por `entries`.
func show_entries(entries: Array[Dictionary]) -> void:
	for child: Node in get_children():
		# Primero fuera del contenedor: queue_free() recién actúa al final del
		# cuadro y la fila saltaría.
		remove_child(child)
		child.queue_free()
	for entry: Dictionary in entries:
		var tile: LoadoutTile = TILE_SCENE.instantiate()
		add_child(tile)
		tile.show_entry(entry)


## Mismas casillas, segundos nuevos: cambia solo las esquinas cuyo texto cambió.
func _update_corners(corners: PackedStringArray) -> void:
	var tiles := get_children()
	for i in mini(corners.size(), tiles.size()):
		if i < _corner_texts.size() and corners[i] == _corner_texts[i]:
			continue
		var tile := tiles[i] as LoadoutTile
		if tile != null:
			tile.set_corner(corners[i])
	_corner_texts = corners
