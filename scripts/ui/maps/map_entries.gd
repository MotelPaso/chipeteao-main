class_name MapEntries
extends RefCounted
## Lo que el mapa de Tab muestra de un jugador, ya armado para sus paneles:
## las fichas de power-ups y las del equipo. Solo
## junta datos; cómo se ven es cosa de MapChips, MapChip y MapOverlay.tscn.
## Las entradas son las de las franjas del HUD: {glyph, library, entry_id,
## color, corner, tip, icon} (ver LoadoutTile.show_entry).


## Power-ups activos con sus segundos restantes. El mapa es donde miras al
## decidir qué hacer, y "once segundos de Furia" es justo esa clase de decisión.
static func powerups(raider: Node3D, seconds_format: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var active := PowerUps.find_in(raider)
	if active == null:
		return entries
	for live: Dictionary in active.active():
		var powerup_id := String(live.id)
		var row := PowerUpCatalog.by_id(powerup_id)
		entries.append({
			"glyph": String(row.get("glyph", "??")),
			"library": LoadoutTile.ICON_LIBRARY_POWERUPS,
			"entry_id": powerup_id,
			"color": row.get("color", Color.WHITE) as Color,
			"corner": seconds_format % ceili(float(live.time_left)),
			"tip": PowerUpCatalog.display_name_of(powerup_id),
			"icon": String(row.get("icon", "")),
		})
	return entries


## Armas con su nivel o rango, tomos con sus pilas y objetos con sus copias:
## las mismas tres familias que las franjas del HUD, y armadas por ellas
## (`build_strip`, `bag_strip`), así glifos y colores son los mismos.
static func loadout(raider: Node3D, build_strip: LoadoutStrip,
		bag_strip: LoadoutStrip) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if raider == null:
		return entries
	if build_strip != null:
		entries.append_array(build_strip.gather_build(raider))
	if bag_strip != null:
		entries.append_array(bag_strip.gather_bag(raider))
	return entries

