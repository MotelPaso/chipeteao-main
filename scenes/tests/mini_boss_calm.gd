class_name MiniBossCalm
extends RefCounted
## Lo que MiniBossProbe mide de la CALMA de la entrada de un minijefe: con el
## mundo congelado ninguna vida cambia y nada nace. Guarda las vidas y los
## cuerpos del primer frame de la entrada y los compara con los del ÚLTIMO
## frame en que la entrada seguía en curso: lo que el minijefe haga en el
## instante en que empieza a pelear (barrer a la horda) ya no es la entrada.
## La vida del propio minijefe no cuenta (su plan de vida se aplica justo al
## empezar la pelea).
## Línea de log: "Probe mini calm: frames=… seconds=… healths=… changed=…
## born=… enemies=a->b bolts=a->b shots=a->b".

## Grupos de cuerpos con Health de la partida.
const HEALTH_GROUPS: Array[StringName] = [&"player", &"downed_players", &"enemies", &"boss",
		&"possessed"]

var _tree: SceneTree = null
var _boss: Node3D = null
var _first_health: Dictionary[int, float] = {}
var _first_counts: Array[int] = []
var _last_health: Dictionary[int, float] = {}
var _last_counts: Array[int] = []


func _init(tree: SceneTree) -> void:
	_tree = tree


## Primer frame de la entrada de `boss`.
func begin(boss: Node3D) -> void:
	_boss = boss
	_first_health = _health_snapshot()
	_first_counts = _live_counts()
	_last_health = _first_health
	_last_counts = _first_counts


## Un frame más con la entrada en curso.
func sample() -> void:
	_last_health = _health_snapshot()
	_last_counts = _live_counts()


## La entrada terminó después de `frames` frames: imprime qué cambió entre su
## primer frame y el último.
func report(frames: int) -> void:
	var changed := 0
	for id: int in _first_health:
		if not _last_health.has(id) or not is_equal_approx(_last_health[id], _first_health[id]):
			changed += 1
	var born := 0
	for id: int in _last_health:
		if not _first_health.has(id):
			born += 1
	print(("Probe mini calm: frames=%d seconds=%.2f healths=%d changed=%d born=%d"
			+ " enemies=%d->%d bolts=%d->%d shots=%d->%d") % [
			frames, float(frames) / 60.0, _first_health.size(), changed, born,
			_first_counts[0], _last_counts[0], _first_counts[1], _last_counts[1],
			_first_counts[2], _last_counts[2]])


## Vida de cada cuerpo con Health de la partida, por id de instancia, menos la
## del propio minijefe.
func _health_snapshot() -> Dictionary[int, float]:
	var out: Dictionary[int, float] = {}
	for group: StringName in HEALTH_GROUPS:
		for node: Node in _tree.get_nodes_in_group(group):
			if node == _boss:
				continue
			var health := Health.find_in(node)
			if health != null:
				out[health.get_instance_id()] = health.current_hp
	return out


## Cuerpos y proyectiles vivos: enemigos, saetas enemigas y disparos.
func _live_counts() -> Array[int]:
	return [_tree.get_node_count_in_group(&"enemies"),
			_tree.get_node_count_in_group(&"enemy_projectiles"),
			_tree.get_node_count_in_group(&"player_shots")]
