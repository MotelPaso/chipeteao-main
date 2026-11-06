class_name CatalogIndex
extends RefCounted
## Índice id -> fila que comparten los catálogos estáticos (tomos, objetos,
## reliquias, personajes, mascotas, misiones, mapas, evoluciones, armas).
##
## Las búsquedas por id están en un camino caliente: PlayerStats.recompute()
## resuelve una fila por cada stack de tomo, por cada stack de objeto y por
## cada reliquia, y corre en cada subida de nivel, boon de altar y fin de boon
## temporal. Las bibliotecas no cambian en tiempo de ejecución, así que un
## índice armado una vez nunca queda desactualizado. Cada catálogo guarda su
## propio índice en un `static var` y expone su by_id().

## Mapa id -> fila de `rows`, con `field` como llave. Las filas sin ese campo
## (o con el valor vacío) se saltan, así las llaves opcionales como
## `unlock_boss` se indexan sin ruido. Con ids repetidos gana la primera fila.
static func build(rows: Array[Dictionary], field: String = "id") -> Dictionary[String, Dictionary]:
	var index: Dictionary[String, Dictionary] = {}
	for row: Dictionary in rows:
		var key := String(row.get(field, ""))
		if key.is_empty() or index.has(key):
			continue
		index[key] = row
	return index


## Todos los valores de `field` en las filas de `rows` cuyo `match_field` vale
## `value` (la forma «todos los ids de esta rareza/tipo»).
static func values_where(rows: Array[Dictionary], match_field: String, value: String,
		field: String = "id") -> Array[String]:
	var out: Array[String] = []
	for row: Dictionary in rows:
		if String(row.get(match_field, "")) == value:
			out.append(String(row.get(field, "")))
	return out
