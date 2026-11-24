class_name ReliefPieces
extends RefCounted
## La línea `Relief pieces:` de una etapa con relieve por zonas: qué piezas
## armó de verdad cada consumidor del trazado, para que el harness (y quien
## lea el log) sepa qué tiene este mapa. La imprime el scatter después de
## vestir la arena:
##
##   Relief pieces: <mapa> recipe=<id> stepped_mountain=N hollow_tree=N
##       ravine=N river=N bridges=N waterfall=N road=N twin_mounts=N lake=N
##       island=N springhead=N buttes=N own=<ok|missing:<llave>|undefined>
##       wanted=<piezas opcionales sorteadas>
##
## `own` dice si está la pieza propia de la receta (ReliefRecipes.own_pieces):
## `missing:<llave>` si le falta, `undefined` si la receta no la declara.
## `wanted` lista las piezas opcionales que pidió el sorteo de la receta
## (ReliefRecipes.options), o "none": si una pedida no aparece arriba, no cupo.
##
## stepped_mountain, ravine, lake, island, springhead, twin_mounts y buttes
## salen del trazado que levantó el Terrain; hollow_tree, river, waterfall y
## road, de ReliefStructures, ReliefRoad y ReliefWaters; bridges, de
## ReliefDressing. Las llaves son internas (las lee el harness): no se renombran.

## Las llaves de la línea, en su orden.
const KEYS: Array[String] = ["stepped_mountain", "hollow_tree", "ravine", "river", "bridges",
		"waterfall", "road", "twin_mounts", "lake", "island", "springhead", "buttes"]


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
	var values := _layout_counts(layout)
	for key: String in ["hollow_tree", "river", "bridges", "waterfall", "road"]:
		values[key] = int(pieces.get(key, 0))
	var parts := PackedStringArray()
	for key: String in KEYS:
		parts.append("%s=%d" % [key, int(values.get(key, 0))])
	var wanted := PackedStringArray()
	for key: String in layout.options:
		if bool(layout.options[key]):
			wanted.append(key)
	print("Relief pieces: %s recipe=%s %s own=%s wanted=%s" % [map_id, layout.recipe,
			" ".join(parts), _own(layout.recipe, values),
			",".join(wanted) if not wanted.is_empty() else "none"])


## Las piezas que salen del trazado mismo: zonas por tipo, cañón y lago.
static func _layout_counts(layout: ReliefLayout) -> Dictionary:
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
	counts["ravine"] = 1 if ravine != null else 0
	counts["lake"] = 1 if ravine != null and ravine.lake_to > ravine.lake_from else 0
	return counts


## "ok" si están todas las piezas propias de la receta `recipe`, la primera
## que falta como "missing:<llave>", o "undefined" si la receta no declara ninguna.
static func _own(recipe: StringName, values: Dictionary) -> String:
	var own := ReliefRecipes.own_pieces(recipe)
	if own.is_empty():
		return "undefined"
	for key: String in own:
		if int(values.get(key, 0)) < int(own[key]):
			return "missing:%s" % key
	return "ok"


## Niveles apilados hasta `zone`, ella incluida (la cumbre de la montaña
## escalonada tiene tres).
static func _levels(layout: ReliefLayout, zone: ReliefLayout.Zone) -> int:
	var levels := 1
	var up := zone.parent
	while up >= 0:
		levels += 1
		up = layout.zones[up].parent
	return levels
