class_name PlayerWallet
extends Node
## Puntos de la partida de un raider: se ganan por baja (cobra el raider
## más cercano) y se gastan en cofres, ruletas, manantiales y vendedores.
## Los multiplicadores con nombre (Fiebre del oro, Lluvia dorada) se
## componen como producto. Es el nodo Wallet de Player.tscn; el resto del
## juego llama a los métodos del mismo nombre en Player (con has_method) y
## escucha Player.points_changed, que Player reemite desde la de aquí.

## Cambiaron los puntos; Player la reemite como su propia points_changed.
signal points_changed(total: int)

## Puntos actuales; empiezan en 0 en cada partida (el raider es nuevo).
var points: int = 0

## Multiplicadores activos por nombre de fuente.
var _points_sources: Dictionary[String, float] = {}


## Multiplicador total de puntos: producto de todas las fuentes activas.
func points_multiplier() -> float:
	var factor := 1.0
	for source_id: String in _points_sources:
		factor *= _points_sources[source_id]
	return factor


## Activa o actualiza una fuente de multiplicador.
func set_points_source(source_id: String, multiplier: float) -> void:
	_points_sources[source_id] = multiplier


## Quita una fuente de multiplicador.
func clear_points_source(source_id: String) -> void:
	_points_sources.erase(source_id)


## Suma puntos con el multiplicador actual.
func add_points(amount: int) -> void:
	if amount <= 0:
		return
	# Redondea hacia arriba: un x1.5 sobre una baja de 1 punto paga 2, no 1.
	points += ceili(float(amount) * points_multiplier())
	points_changed.emit(points)


## Descuenta si alcanza y devuelve true; si no alcanza, false sin cambiar nada.
func spend_points(amount: int) -> bool:
	if amount <= 0:
		# Precio 0 es gratis (true). Un precio negativo es un error del
		# llamador y se rechaza: si no, PAGARÍA al jugador.
		return amount == 0
	if amount > points:
		return false
	points -= amount
	points_changed.emit(points)
	return true
