class_name CollectionFocus
extends RefCounted
## Navegación con control y teclado de la cuadrícula de la Colección: cablea a
## mano los vecinos de foco de las cartas y del botón Volver. La búsqueda
## automática de Godot elige el control más cercano en cada dirección, y con
## el detalle a la derecha eso deja caminos sin salida; con este cableado:
##   - una carta va a sus vecinas; en los bordes izquierdo, derecho e inferior
##     el foco se queda en la carta (nunca sale a un lugar sin control);
##   - una carta de la última fila incompleta baja desde arriba a la última
##     carta, así ninguna queda inalcanzable;
##   - sobre la primera fila está Volver, y de Volver se baja a `resume`, la
##     última carta mirada.
## Es estático y nunca va en una escena; lo llama collection_browser.gd cada
## vez que cambian las cartas o las columnas.


## `cards` en el orden de la cuadrícula, con `columns` columnas.
static func link(cards: Array[CollectionCard], columns: int, back: Button,
		resume: CollectionCard) -> void:
	columns = maxi(columns, 1)
	for i in cards.size():
		var card := cards[i]
		var column := i % columns
		var last_in_row := column == columns - 1 or i + 1 >= cards.size()
		_wire(card, SIDE_LEFT, cards[i - 1] if column > 0 else card)
		_wire(card, SIDE_RIGHT, card if last_in_row else cards[i + 1])
		_wire(card, SIDE_TOP, cards[i - columns] if i >= columns else back)
		var below := i + columns
		if below < cards.size():
			_wire(card, SIDE_BOTTOM, cards[below])
		elif i / columns < (cards.size() - 1) / columns:
			_wire(card, SIDE_BOTTOM, cards[-1])
		else:
			_wire(card, SIDE_BOTTOM, card)
	var landing: Control = resume if resume != null \
			else (cards[0] if not cards.is_empty() else back)
	_wire(back, SIDE_BOTTOM, landing)
	_wire(back, SIDE_TOP, back)
	_wire(back, SIDE_LEFT, back)
	_wire(back, SIDE_RIGHT, back)


static func _wire(from: Control, side: Side, to: Control) -> void:
	from.set_focus_neighbor(side, from.get_path_to(to))
