class_name PickRecipients
extends RefCounted
## A quién le toca cada elección del selector de cartas. La XP y el nivel son
## de todo el grupo, así que en co-op las elecciones rotan entre los raiders que
## siguen en pie; en solo siempre es el único jugador.

## Ranura (player_index) desde la que empieza a buscar la próxima elección.
var _rotation: int = 0


## El raider de la próxima elección, o null si no hay nadie en pie. Rota por
## RANURA del grupo, no por posición en la lista de vivos: el contador nombra
## una ranura (0..player_count-1) y la elección va a ese raider si está en pie,
## si no a la siguiente ranura en pie. Rotar sobre la lista de vivos cambiaría el
## reparto cada vez que alguien cae o revive (cambia el módulo), y un raider
## podría recibir el doble de cartas que otro en una partida con muchas caídas.
func next(tree: SceneTree) -> Node:
	var players: Array[Node] = tree.get_nodes_in_group("player")
	if players.is_empty():
		return null
	if not Coop.is_coop():
		return players[0]
	for i in Coop.player_count:
		var slot := (_rotation + i) % Coop.player_count
		for node: Node in players:
			if int(node.get("player_index")) != slot:
				continue
			# La siguiente elección empieza a buscar una ranura después de esta,
			# así un raider caído cede el turno sin mover el orden de los demás.
			_rotation = slot + 1
			return node
	return null


## El raider en pie con la RANURA MÁS BAJA, o null. No usa
## get_first_node_in_group, cuyo orden cambia cada vez que alguien cae y revive.
static func lowest_slot(tree: SceneTree) -> Node:
	var best: Node = null
	var best_slot := Coop.MAX_PLAYERS
	for node: Node in tree.get_nodes_in_group("player"):
		var slot := int(node.get("player_index"))
		if slot < best_slot:
			best_slot = slot
			best = node
	return best
