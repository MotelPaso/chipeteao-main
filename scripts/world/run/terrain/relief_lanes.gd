class_name ReliefLanes
extends RefCounted
## Los puentes de arcos abiertos de una arena vistos por la HORDA. Un
## enemigo persigue en línea recta y trepa lo que lo frena; bajo un tablero
## no hay nada que trepar, y el puente sería un refugio. Con esto, quien
## persigue a alguien parado sobre un puente entra por una cabecera, y quien
## quedó debajo sale por el costado y sube a la orilla.
##
## Lo arma ReliefDressing al levantar los puentes. EnemyBase se lo pide una
## vez al scatter (`horde_lanes`) y llama a seek() en cada tick: mientras
## ningún raider anda por un puente, seek() devuelve la línea recta de
## siempre tras una comparación.
##
## Ninguna escena usa este script: lo que alguien podría querer tocar está
## en las constantes de aquí arriba.

# --- edita aquí --------------------------------------------------------------
## Metros bajo el tablero a partir de los cuales alguien está abajo, en el cañón.
const BELOW: float = 1.5
## Metros más allá de cada punta del tablero, y a cada costado de la obra,
## donde un raider todavía "anda por el puente".
const NEAR_ALONG: float = 6.0
const NEAR_ASIDE: float = 8.0
## Metros detrás del borde del cañón donde la horda entra al tablero: pasadas
## las torres de la cabecera.
const MOUTH: float = 2.8
## El punto por donde sube quien quedó en el cañón: metros hacia dentro de
## la orilla y metros hacia el costado de la obra.
const CLIMB_BACK: float = 3.0
const CLIMB_ASIDE: float = 4.0
# -----------------------------------------------------------------------------


## Un puente: su tablero en planta y a qué altura se pisa.
class Lane extends RefCounted:
	var center: Vector2
	## A lo largo del tablero y a lo ancho, unitarios.
	var axis: Vector2
	var side: Vector2
	## Del centro a cada borde del cañón, y lo que el tablero entra en la orilla.
	var half_span: float
	var overlap: float
	## Mitad del tablero y mitad de la obra (los estribos), en metros.
	var half_deck: float
	var half_work: float
	var level: float
	## True si algún raider anda por este puente en este tick.
	var hot: bool = false


var _tree: SceneTree = null
var _lanes: Array[Lane] = []
var _frame: int = -1
var _any_hot: bool = false


func _init(tree: SceneTree) -> void:
	_tree = tree


## Suma el puente `bridge`, ya colocado.
func add(bridge: Bridge) -> void:
	var lane := Lane.new()
	var basis := bridge.global_transform.basis
	lane.center = Vector2(bridge.global_position.x, bridge.global_position.z)
	lane.axis = Vector2(basis.x.x, basis.x.z).normalized()
	lane.side = Vector2(basis.z.x, basis.z.z).normalized()
	lane.half_span = bridge.span * 0.5
	lane.overlap = bridge.overlap
	lane.half_deck = bridge.deck_width() * 0.5
	lane.half_work = bridge.width * 0.5
	lane.level = bridge.global_position.y
	_lanes.append(lane)


func is_empty() -> bool:
	return _lanes.is_empty()


## Hacia dónde camina el enemigo parado en `from` que persigue a quien está
## en `to`: `straight` (la línea recta, plana y unitaria) salvo que un
## puente pida un rodeo.
func seek(from: Vector3, to: Vector3, straight: Vector3) -> Vector3:
	var frame := Engine.get_physics_frames()
	if frame != _frame:
		_frame = frame
		_refresh()
	if not _any_hot:
		return straight
	for lane: Lane in _lanes:
		if not lane.hot:
			continue
		var goal := _goal(lane, from, to)
		if goal == Vector2.INF:
			continue
		var away := Vector3(goal.x - from.x, 0.0, goal.y - from.z)
		if away.length_squared() > 0.04:
			return away.normalized()
	return straight


## Una vez por tick: qué puentes tienen un raider encima o al lado.
func _refresh() -> void:
	_any_hot = false
	var players := Coop.alive_players(_tree)
	for lane: Lane in _lanes:
		lane.hot = false
		for node: Node in players:
			var body := node as Node3D
			if body == null:
				continue
			var at := body.global_position
			if at.y < lane.level - BELOW:
				continue
			var flat := Vector2(at.x, at.z) - lane.center
			if absf(flat.dot(lane.axis)) <= lane.half_span + lane.overlap + NEAR_ALONG \
					and absf(flat.dot(lane.side)) <= lane.half_work + NEAR_ASIDE:
				lane.hot = true
				_any_hot = true
				break


## El punto al que va primero el enemigo, o Vector2.INF si le sirve la
## línea recta.
func _goal(lane: Lane, from: Vector3, to: Vector3) -> Vector2:
	# A quien está en el cañón se lo alcanza como siempre: cayendo.
	if to.y < lane.level - BELOW:
		return Vector2.INF
	var target := Vector2(to.x, to.z) - lane.center
	var target_along := target.dot(lane.axis)
	var on_deck := absf(target.dot(lane.side)) <= lane.half_deck + 0.5 \
			and absf(target_along) <= lane.half_span + lane.overlap + 2.0
	var own := Vector2(from.x, from.z) - lane.center
	var along := own.dot(lane.axis)
	var aside := own.dot(lane.side)
	if from.y < lane.level - BELOW:
		var under := absf(aside) <= lane.half_work + 1.0 and absf(along) <= lane.half_span
		if not on_deck and not under:
			return Vector2.INF
		# En el cañón: sale por su costado y sube a la orilla, la suya si el
		# objetivo está en el tablero y la del objetivo si no.
		var bank := signf(along) if on_deck and absf(along) > 1.0 else signf(target_along)
		if bank == 0.0:
			bank = 1.0
		var turn := 1.0 if aside >= 0.0 else -1.0
		return lane.center + lane.axis * (bank * (lane.half_span + CLIMB_BACK)) \
				+ lane.side * (turn * (lane.half_work + CLIMB_ASIDE))
	if not on_deck:
		return Vector2.INF
	# Ya sobre el tablero: derecho al objetivo.
	if absf(aside) <= lane.half_deck + 0.6 \
			and absf(along) <= lane.half_span + lane.overlap + 3.0:
		return Vector2.INF
	if absf(along) <= lane.half_span:
		return Vector2.INF
	# En una orilla: a la boca de su cabecera, y de ahí por el tablero.
	return lane.center + lane.axis * (signf(along) * clampf(absf(along),
			lane.half_span + MOUTH, lane.half_span + lane.overlap + 1.0))
