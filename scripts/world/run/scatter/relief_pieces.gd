class_name ReliefPieces
extends RefCounted
## La línea `Relief pieces:` de una etapa con relieve por zonas: qué piezas
## armó de verdad cada consumidor del trazado, para que el harness (y quien
## lea el log) sepa qué tiene este mapa. La imprime el scatter después de
## vestir la arena:
##
##   Relief pieces: <mapa> recipe=<id> stepped_mountain=N hollow_tree=N
##       ravine=N river=N bridges=N waterfall=N road=N twin_mounts=N lake=N
##       island=N springhead=N buttes=N wanted=<piezas opcionales sorteadas>
##
## `wanted` lista las piezas opcionales que pidió el sorteo de la receta
## (ReliefRecipes.options), o "none": si una pedida no aparece arriba, no cupo.
##
## stepped_mountain, ravine, lake, island, springhead, twin_mounts y buttes
## salen del trazado que levantó el Terrain; hollow_tree, river, waterfall y
## road, de ReliefStructures, ReliefRoad y ReliefWaters; bridges, de
## ReliefDressing. Las llaves son internas (las lee el harness): no se renombran.


## Imprime la línea para `terrain` con lo que anotaron los consumidores en
## `pieces` (llave -> cantidad).
static func report(terrain: Terrain, pieces: Dictionary) -> void:
	var layout := terrain.relief_layout() if terrain != null else null
	if layout == null:
		return
	var arena: Node = terrain
	while arena != null and not (arena is Arena):
		arena = arena.get_parent()
	var map_id := (arena as Arena).map_id if arena != null else String(terrain.name)
	var counts := {"stepped_mountain": 0, "twin_mounts": 0, "island": 0, "springhead": 0,
			"buttes": 0}
	for zone: ReliefLayout.Zone in layout.zones:
		match zone.kind:
			&"summit":
				if _levels(layout, zone) >= 3:
					counts["stepped_mountain"] += 1
			&"mount":
				counts["twin_mounts"] += 1
			&"island":
				counts["island"] += 1
			&"spring":
				counts["springhead"] += 1
			&"butte":
				counts["buttes"] += 1
	var ravine := layout.ravine
	var wanted := PackedStringArray()
	for key: String in layout.options:
		if bool(layout.options[key]):
			wanted.append(key)
	print(("Relief pieces: %s recipe=%s stepped_mountain=%d hollow_tree=%d ravine=%d river=%d"
			+ " bridges=%d waterfall=%d road=%d twin_mounts=%d lake=%d island=%d springhead=%d"
			+ " buttes=%d wanted=%s") % [map_id, layout.recipe, counts["stepped_mountain"],
			int(pieces.get("hollow_tree", 0)), 1 if ravine != null else 0,
			int(pieces.get("river", 0)), int(pieces.get("bridges", 0)),
			int(pieces.get("waterfall", 0)), int(pieces.get("road", 0)), counts["twin_mounts"],
			1 if ravine != null and ravine.lake_to > ravine.lake_from else 0, counts["island"],
			counts["springhead"], counts["buttes"],
			",".join(wanted) if not wanted.is_empty() else "none"])


## Niveles apilados hasta `zone`, ella incluida (la cumbre de la montaña
## escalonada tiene tres).
static func _levels(layout: ReliefLayout, zone: ReliefLayout.Zone) -> int:
	var levels := 1
	var up := zone.parent
	while up >= 0:
		levels += 1
		up = layout.zones[up].parent
	return levels
