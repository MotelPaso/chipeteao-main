class_name MythosMoveset
extends Node
## Los ataques de Mythos (nodo Moves de Mythos.tscn): cada hijo es un ataque
## (MythosMove) con sus propios valores. Aquí corren sus esperas y se elige
## el próximo: entre los que están listos para la vida, la distancia y la
## postura de ahora, el que lleva más tiempo sin usarse (así los ataques
## grandes, de espera larga, salen en cuanto pueden y ninguno se repite de
## más). El despegue (MythosTakeoff) queda aparte: Mythos lo usa cuando le
## toca volar.

var _moves: Array[MythosMove] = []
var _takeoff: MythosMove = null
## Cuándo se usó cada ataque por última vez, contado en ataques (los que
## nunca se usaron no están).
var _used_at: Dictionary[MythosMove, int] = {}
var _uses: int = 0


## Mythos lo llama una vez, al aparecer.
func setup(boss: Mythos) -> void:
	for child: Node in get_children():
		var move := child as MythosMove
		if move == null:
			continue
		move.setup(boss)
		if move is MythosTakeoff:
			_takeoff = move
		else:
			_moves.append(move)


## Un frame de pelea en la vida `life`: corren las esperas y lo que cada
## ataque hace de fondo.
func tick(delta: float, life: int) -> void:
	for move: MythosMove in _moves:
		move.tick_cooldown(delta)
		move.tick_always(delta, life)


## Deja en todos la espera de primer uso (al empezar cada vida).
func reset_cooldowns() -> void:
	for move: MythosMove in _moves:
		move.reset_cooldown()


func scale_damage(multiplier: float) -> void:
	for move: MythosMove in _moves:
		move.scale_damage(multiplier)
	if _takeoff != null:
		_takeoff.scale_damage(multiplier)


## El despegue, o null si la escena no trae uno.
func takeoff() -> MythosMove:
	return _takeoff


## El ataque que `move` encadena en la vida `life` (MythosMove.chain_to), o
## null si no encadena, no le tocó o no sirve para la postura de ahora. No
## mira la espera del encadenado: un combo sale entero.
func follow_up(move: MythosMove, life: int, grounded: bool) -> MythosMove:
	if move == null or move.chain_to == &"" or life < move.chain_from_life \
			or randf() > move.chain_chance:
		return null
	var next := get_node_or_null(NodePath(String(move.chain_to))) as MythosMove
	if next == null or not next.fits(life, grounded):
		return null
	_uses += 1
	_used_at[next] = _uses
	return next


## El próximo ataque: de los que están listos, el que hace más que no se
## usa (a igualdad, el primero de la lista). Null si ninguno lo está.
func next_ready(life: int, distance: float, grounded: bool) -> MythosMove:
	var chosen: MythosMove = null
	var oldest := 0
	for move: MythosMove in _moves:
		if not move.is_ready(life, distance, grounded):
			continue
		var used := int(_used_at.get(move, -1))
		if chosen == null or used < oldest:
			chosen = move
			oldest = used
	if chosen != null:
		_uses += 1
		_used_at[chosen] = _uses
	return chosen
