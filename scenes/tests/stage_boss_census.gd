class_name StageBossCensus
extends RefCounted
## Las cuentas de cuerpos alrededor del jefe de etapa. StageBossProbe lo
## avanza y le avisa cuándo empieza y termina la calma; solo observa.
##   Probe calm:    vida de cada cuerpo y cantidad de enemigos y proyectiles
##                  al empezar y al terminar la calma (nada debe cambiar)
##   Probe hazards: lo que el jefe dejó en la arena un rato después de morir
##   Probe alone:   si peleó SOLO (EnemySpawner.stage_boss_fights_alone): la
##                  horda que quedaba al empezar y la que hubo, como mucho,
##                  pasado el barrido. Ejemplo:
##     Probe alone: held=true others_at_start=14 others_max_after_purge=0 fight=165.2s
## "others" son los cuerpos del grupo "enemies" que no son el jefe de etapa.

## Segundos tras el fin de la calma que se le dan al barrido de la horda
## antes de exigir que no quede nadie.
const PURGE_GRACE: float = 4.0

var _tree: SceneTree = null
var _fight_from: float = -1.0
var _held: bool = false
var _others_at_start: int = 0
var _others_max: int = 0
var _calm_health: Dictionary[int, float] = {}
var _calm_counts: Array[int] = []


func _init(tree: SceneTree) -> void:
	_tree = tree


## Un frame del probe: `now` son sus segundos y `state` el fight_state() del
## jefe de etapa ("" si no hay ninguno).
func tick(now: float, state: StringName) -> void:
	var fighting := state == &"flight" or state == &"move" or state == &"ashes"
	if fighting and _fight_from < 0.0:
		_fight_from = now
		_held = EnemySpawner.is_holding(_tree)
		_others_at_start = _others()
		_others_max = 0
	elif fighting and now - _fight_from >= PURGE_GRACE:
		_others_max = maxi(_others_max, _others())
	elif not fighting and _fight_from >= 0.0:
		print("Probe alone: held=%s others_at_start=%d others_max_after_purge=%d fight=%.1fs" % [
				_held, _others_at_start, _others_max, now - _fight_from])
		_fight_from = -1.0


func _others() -> int:
	var count := 0
	for node: Node in _tree.get_nodes_in_group(&"enemies"):
		if not node.is_in_group(BossSchedule.STAGE_BOSS_GROUP):
			count += 1
	return count

## Empieza la calma: guarda las vidas y las cuentas para comparar al final.
func begin_calm() -> void:
	_calm_health = _health_snapshot()
	_calm_counts = _live_counts()


## Vida actual de cada cuerpo con Health de la partida, por id de instancia.
func _health_snapshot() -> Dictionary[int, float]:
	var out: Dictionary[int, float] = {}
	for group: StringName in [&"player", &"downed_players", &"enemies", &"boss", &"possessed"]:
		for node: Node in _tree.get_nodes_in_group(group):
			var health := Health.find_in(node)
			if health != null:
				out[health.get_instance_id()] = health.current_hp
	return out


## Cuerpos y proyectiles vivos: enemigos, saetas enemigas y disparos.
func _live_counts() -> Array[int]:
	return [_tree.get_node_count_in_group(&"enemies"),
			_tree.get_node_count_in_group(&"enemy_projectiles"),
			_tree.get_node_count_in_group(&"player_shots")]


## La calma terminó tras `frames` frames del probe: ninguna vida debió
## cambiar y nada debió aparecer.
func report_calm(frames: int) -> void:
	var after := _health_snapshot()
	var changed := 0
	for id: int in _calm_health:
		if not after.has(id) or not is_equal_approx(after[id], _calm_health[id]):
			changed += 1
	var born := 0
	for id: int in after:
		if not _calm_health.has(id):
			born += 1
	var counts := _live_counts()
	print(("Probe calm: frames=%d seconds=%.2f healths=%d changed=%d born=%d"
			+ " enemies=%d->%d bolts=%d->%d shots=%d->%d") % [
			frames, float(frames) / 60.0, _calm_health.size(), changed, born,
			_calm_counts[0], counts[0], _calm_counts[1], counts[1],
			_calm_counts[2], counts[2]])


## Zonas de fuego que siguen vivas (marcadas, ardiendo o apagándose) y
## cuántas de ellas todavía hacen daño.
func print_hazards(reason: String) -> void:
	var live := 0
	var burning := 0
	for node: Node in _tree.get_nodes_in_group(FireZone.GROUP):
		var zone := node as FireZone
		if zone == null:
			continue
		if zone.zone_radius() > 0.0:
			live += 1
		if zone.is_burning():
			burning += 1
	# Lo demás que el jefe deja en la arena: tornados, ondas y bolas de fuego.
	print("Probe hazards: reason=%s live=%d burning=%d tornados=%d waves=%d fireballs=%d" % [
			reason, live, burning, _tree.get_node_count_in_group(FireTornado.GROUP),
			_tree.get_node_count_in_group(FireWave.GROUP),
			_tree.get_node_count_in_group(Fireball.GROUP)])
