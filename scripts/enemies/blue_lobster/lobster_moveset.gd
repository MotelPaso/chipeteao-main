class_name LobsterMoveset
extends Node
## Los ataques de la Langosta Azul (nodo Moves de BlueLobster.tscn): cada hijo
## es un ataque (LobsterMove) con sus propios valores. Aquí corren sus esperas
## y se elige el próximo: entre los que están listos para la distancia de
## ahora, el que lleva más tiempo sin usarse (así ninguno se repite de más y
## los de espera larga salen en cuanto pueden).

var _moves: Array[LobsterMove] = []
## Cuándo se usó cada ataque por última vez, contado en ataques (los que
## nunca se usaron no están).
var _used_at: Dictionary[LobsterMove, int] = {}
var _uses: int = 0


## La langosta lo llama una vez, al aparecer.
func setup(boss: BlueLobster) -> void:
	for child: Node in get_children():
		var move := child as LobsterMove
		if move != null:
			move.setup(boss)
			_moves.append(move)


## Un frame de pelea: corren las esperas.
func tick(delta: float) -> void:
	for move: LobsterMove in _moves:
		move.tick_cooldown(delta)


func scale_damage(multiplier: float) -> void:
	for move: LobsterMove in _moves:
		move.scale_damage(multiplier)


## El ataque llamado `move_name` (el nombre de su nodo), o null.
func by_name(move_name: StringName) -> LobsterMove:
	return get_node_or_null(NodePath(String(move_name))) as LobsterMove


## El próximo ataque: de los que están listos a `distance` metros, el que
## hace más que no se usa (a igualdad, el primero de la lista). Null si
## ninguno lo está.
func next_ready(distance: float) -> LobsterMove:
	var chosen: LobsterMove = null
	var oldest := 0
	for move: LobsterMove in _moves:
		if not move.is_ready(distance):
			continue
		var used := int(_used_at.get(move, -1))
		if chosen == null or used < oldest:
			chosen = move
			oldest = used
	if chosen != null:
		mark_used(chosen)
	return chosen


## Anota que `move` acaba de usarse (también cuando alguien lo fuerza).
func mark_used(move: LobsterMove) -> void:
	_uses += 1
	_used_at[move] = _uses
