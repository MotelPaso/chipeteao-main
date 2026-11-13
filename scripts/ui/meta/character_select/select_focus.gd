class_name SelectFocus
extends RefCounted
## Navegación con control y teclado del selector de personaje: cablea a mano
## los vecinos de foco de la cuadrícula, del botón Iniciar y de la fila de
## pantallas meta. La búsqueda automática de Godot elige el control más
## cercano en cada dirección, y con el detalle a la derecha y los botones
## abajo eso deja caminos sin salida; con este cableado:
##   - una carta va a sus vecinas; a la derecha de la última columna está
##     Iniciar, bajo la última fila la fila de pantallas meta, y sobre la
##     primera fila el lobby co-op;
##   - una carta que pide desbloquear baja primero a su «Sí»;
##   - Iniciar vuelve a la izquierda al raider elegido, sube al lobby y baja a
##     la fila de pantallas meta;
##   - la fila de pantallas meta va a izquierda y derecha (tras el último
##     botón está Iniciar) y arriba vuelve al raider elegido;
##   - Ajustes baja al lobby.
## Es estático y nunca va en una escena; lo llama character_select.gd cada vez
## que cambian las cartas, los slots o las columnas.


## `cards` en el orden de la cuadrícula, con `columns` columnas. `above` es el
## control del lobby al que sube la primera fila (o null), `meta_row` los
## botones bajo la cuadrícula y `picked` la carta del raider elegido.
static func link(cards: Array[CharacterCard], columns: int, above: Control,
		meta_row: Array[Button], start: Button, settings: Button,
		picked: CharacterCard) -> void:
	columns = maxi(columns, 1)
	var below_grid: Control = meta_row[0] if not meta_row.is_empty() else start
	for i in cards.size():
		var card := cards[i]
		var column := i % columns
		var below: Control = cards[i + columns] if i + columns < cards.size() \
				else below_grid
		var last_in_row := column == columns - 1 or i + 1 >= cards.size()
		_wire(card, SIDE_LEFT, cards[i - 1] if column > 0 else card)
		_wire(card, SIDE_RIGHT, start if last_in_row else cards[i + 1])
		if i >= columns:
			_wire(card, SIDE_TOP, cards[i - columns])
		elif above != null:
			_wire(card, SIDE_TOP, above)
		var yes := card.unlock_button()
		if yes == null:
			_wire(card, SIDE_BOTTOM, below)
			continue
		_wire(card, SIDE_BOTTOM, yes)
		_wire(yes, SIDE_TOP, card)
		_wire(yes, SIDE_BOTTOM, below)
		_wire(yes, SIDE_LEFT, yes)
		_wire(yes, SIDE_RIGHT, yes)
	for j in meta_row.size():
		var button := meta_row[j]
		if picked != null:
			_wire(button, SIDE_TOP, picked)
		_wire(button, SIDE_BOTTOM, button)
		_wire(button, SIDE_LEFT, meta_row[maxi(j - 1, 0)])
		_wire(button, SIDE_RIGHT, meta_row[j + 1] if j + 1 < meta_row.size() else start)
	if picked != null:
		_wire(start, SIDE_LEFT, picked)
	_wire(start, SIDE_RIGHT, start)
	_wire(start, SIDE_BOTTOM, meta_row[-1] if not meta_row.is_empty() else start)
	if above != null:
		_wire(start, SIDE_TOP, above)
		_wire(settings, SIDE_BOTTOM, above)
	_wire(settings, SIDE_TOP, settings)
	_wire(settings, SIDE_LEFT, settings)


static func _wire(from: Control, side: Side, to: Control) -> void:
	from.set_focus_neighbor(side, from.get_path_to(to))
