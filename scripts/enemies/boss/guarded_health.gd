class_name GuardedHealth
extends Health
## Health de un jefe con varias vidas. Mientras la guarda está armada ningún
## golpe baja la vida de GUARD_HP, así `died` no se emite hasta que el dueño
## suelta la guarda para su última vida. Al tocar la guarda emite
## `guard_reached` una sola vez; arm_guard() la vuelve a armar para la vida
## siguiente.

## La vida de esta vida se agotó (quedan más vidas).
signal guard_reached

## Vida que queda cuando una vida con guarda se agota. Mayor que
## MIN_CHIP_DAMAGE: el golpe mínimo de Health nunca la lleva a cero.
const GUARD_HP: float = 2.0

var _guarded: bool = false
var _guard_tripped: bool = false


## Arma la guarda para una vida que NO es la última.
func arm_guard() -> void:
	_guarded = true
	_guard_tripped = false


## Suelta la guarda: en esta vida el cuerpo muere de verdad.
func drop_guard() -> void:
	_guarded = false
	_guard_tripped = false


func is_guarded() -> bool:
	return _guarded


## Con la guarda armada, el golpe se recorta a lo que queda sobre GUARD_HP.
func take_damage(amount: float, is_crit: bool = false, attacker: Node3D = null) -> float:
	if not _guarded or is_dead or invulnerable or amount <= 0.0:
		return super(amount, is_crit, attacker)
	var room := current_hp - GUARD_HP
	if room <= 0.0:
		_trip_guard()
		return 0.0
	# Health le resta la armadura al golpe: se suma aquí para que lo que
	# entra sea, como mucho, `room`.
	var applied := super(minf(amount, room + armor), is_crit, attacker)
	if current_hp <= GUARD_HP:
		_trip_guard()
	return applied


func _trip_guard() -> void:
	if _guard_tripped:
		return
	_guard_tripped = true
	guard_reached.emit()
