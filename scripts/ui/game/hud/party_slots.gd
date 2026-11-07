class_name PartySlots
extends RefCounted
## Búsquedas de jugadores por ranura (player_index, de 0 a Coop.MAX_PLAYERS - 1)
## que comparten el HUD, el mapa de Tab, la flecha del jefe y el selector de
## cartas.
## Un jugador caído sale del grupo "player" y entra a "downed_players", y uno
## reanimado vuelve al FINAL de "player": el orden de los grupos cambia en la
## partida, así que siempre se busca por player_index.


## El jugador en `slot`, de pie o caído; null si la ranura está vacía.
static func raider_at(tree: SceneTree, slot: int) -> Node3D:
	for group: String in ["player", "downed_players"]:
		for node: Node in tree.get_nodes_in_group(group):
			var body := node as Node3D
			if body != null and int(body.get("player_index")) == slot:
				return body
	return null


## El jugador DE PIE con la ranura más baja; null si no queda ninguno de pie.
static func lowest_standing(tree: SceneTree) -> Node3D:
	var best: Node3D = null
	var best_slot := Coop.MAX_PLAYERS
	for node: Node in tree.get_nodes_in_group(&"player"):
		var body := node as Node3D
		if body == null:
			continue
		var slot := int(body.get("player_index"))
		if slot < best_slot:
			best_slot = slot
			best = body
	return best
