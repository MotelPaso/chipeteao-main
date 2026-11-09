class_name RowText
extends RefCounted
## Llena la descripción de una fila de catálogo con sus propios números, para
## que cada número viva una sola vez (en su campo) y el texto lo siga solo.
## Lo usan ItemCatalog y PowerUpCatalog al armar su índice por id, así todo
## lector de by_id() recibe el texto ya armado.
## Contrato de la fila:
##   description: texto del jugador; lleva un %d por número (y %% para un
##                signo de porcentaje suelto) solo si la fila tiene text_values.
##   text_values: OPCIONAL, nombres de campos de la misma fila que llenan
##                esos %d en orden, redondeados a entero. "amount" es el
##                amount del primer efecto, como en los tomos.


## La fila con su descripción armada, o la misma fila si no tiene text_values.
static func render(row: Dictionary) -> Dictionary:
	var names: Array = row.get("text_values", [])
	if names.is_empty():
		return row
	var values: Array = []
	for field: Variant in names:
		values.append(roundi(value_of(row, String(field))))
	var rendered := row.duplicate()
	rendered["description"] = String(row.get("description", "")) % values
	return rendered


## Cada fila de una tabla, armada (para el índice por id de un catálogo).
static func render_all(rows: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row: Dictionary in rows:
		out.append(render(row))
	return out


## Un número de la fila: un campo propio, o "amount" para el primer efecto.
## Un campo que no existe vale 0 y deja una advertencia (el lint
## text_values lo atrapa antes).
static func value_of(row: Dictionary, field: String) -> float:
	if field == "amount":
		var effects: Array = row.get("effects", [])
		if effects.is_empty():
			return 0.0
		var first: Dictionary = effects[0]
		return float(first.get("amount", 0.0))
	if not row.has(field):
		push_warning("RowText: row '%s' has no field '%s' for its description"
				% [String(row.get("id", "?")), field])
		return 0.0
	return float(row[field])
