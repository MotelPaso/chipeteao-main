extends Node3D
## Sonda de la fusión de gemas de XP, sin partida: suelta gemas en un montón,
## una lejos y una ya en camino, fuerza un chequeo del XpGemMerger y comprueba
## que baja el número de gemas vivas, que la XP total se conserva, que las
## absorbidas vuelven al pool sin acreditar nada y que la gema en camino sigue
## intacta. Se corre a mano:
##   godot --headless --fixed-fps 60 --quit-after 240 \
##     res://scenes/tests/XpGemMergeProbe.tscn
## Salida:
##   Probe gem merge: done ok=1 ...   (ok=0 y un push_error si algo falla)

const CLUSTER_GEMS: int = 20
const FAR_GEMS: int = 3
const HOMING_GEMS: int = 1
const TOTAL_GEMS: int = CLUSTER_GEMS + FAR_GEMS + HOMING_GEMS
const GEM_VALUE: int = 2
const MERGES: int = 4
const CLUSTER_STEP: float = 0.25
const FAR_X: float = 24.0

@onready var _merger: Node = $XpGemMerger


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# La sonda llama a merge_once() ella misma: quieto el reloj del nodo.
	_merger.set_process(false)
	_merger.set("merge_threshold", 6)
	_merger.set("merge_distance", 1.0)
	_merger.set("max_merges_per_check", MERGES)

	var gems: Array[XpGem] = []
	for i in CLUSTER_GEMS:
		var at := Vector3(float(i % 5) * CLUSTER_STEP, 0.0, float(i / 5) * CLUSTER_STEP)
		gems.append(_spawn_gem(at))
	for i in FAR_GEMS:
		gems.append(_spawn_gem(Vector3(FAR_X + float(i) * 2.0, 0.0, 0.0)))
	var flying := _spawn_gem(Vector3(-0.1, 0.0, 0.0))
	flying.vacuum()
	gems.append(flying)

	var before := _live_gems()
	var xp_before := _sum_xp(before)
	var run_xp_before := RunState.xp
	var merged := int(_merger.call(&"merge_once"))
	var after := _live_gems()
	var xp_after := _sum_xp(after)

	var pooled := 0
	var scaled := 0
	for gem: XpGem in gems:
		if not gem.is_in_group(XpGem.LIVE_GROUP):
			pooled += 1
		elif gem.xp_value > GEM_VALUE and (gem.get_node("Visual") as Node3D).scale.x > 1.01:
			scaled += 1

	var counts_ok := merged == MERGES and before.size() == TOTAL_GEMS and after.size() == TOTAL_GEMS - merged
	var xp_ok := xp_before == xp_after and xp_before == TOTAL_GEMS * GEM_VALUE
	var pool_ok := pooled == merged and scaled > 0
	var homing_ok := flying.is_in_group(XpGem.LIVE_GROUP) and flying.xp_value == GEM_VALUE
	var paid_ok := RunState.xp == run_xp_before
	var ok := counts_ok and xp_ok and pool_ok and homing_ok and paid_ok
	if not ok:
		push_error("XpGemMergeProbe: merged=%d before=%d after=%d xp=%d/%d pooled=%d scaled=%d homing=%d paid=%d" % [
				merged, before.size(), after.size(), xp_before, xp_after, pooled, scaled,
				int(homing_ok), int(paid_ok)])
	print("Probe gem merge: done ok=%d before=%d after=%d merged=%d xp_before=%d xp_after=%d homing=%d pooled=%d scaled=%d xp_unchanged=%d" % [
			int(ok), before.size(), after.size(), merged, xp_before, xp_after,
			int(homing_ok), pooled, int(scaled > 0), int(paid_ok)])


func _spawn_gem(at: Vector3) -> XpGem:
	var gem := Pools.acquire_scene(Pools.XP_GEM_SCENE) as XpGem
	gem.global_position = at
	gem.xp_value = GEM_VALUE
	return gem


func _live_gems() -> Array[Node]:
	var out: Array[Node] = []
	for node: Node in get_tree().get_nodes_in_group(XpGem.LIVE_GROUP):
		out.append(node)
	return out


func _sum_xp(nodes: Array[Node]) -> int:
	var total := 0
	for node: Node in nodes:
		var gem := node as XpGem
		if gem != null:
			total += gem.xp_value
	return total
