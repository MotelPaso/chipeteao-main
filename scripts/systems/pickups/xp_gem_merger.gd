class_name XpGemMerger
extends Node
## Junta las gemas de XP que se amontonan. Con más de `merge_threshold` gemas
## vivas, empareja las más cercanas que siguen en el suelo y están dentro de
## `merge_distance`; la XP se suma en la que queda y la otra vuelve al pool sin
## cobrarse ni sonar. Las gemas ya en camino hacia un raider no se tocan.
## Vive en RunSystems.tscn, así que atraviesa los cambios de etapa sin que
## ningún punto de drop (enemigos, jefes, altares, lluvia) tenga que saberlo.

@export_group("Fusión")
## Gemas vivas a partir de las cuales se empieza a fusionar.
@export var merge_threshold: int = 64
## Distancia máxima en metros entre dos gemas para formar una pareja.
@export var merge_distance: float = 2.0
## Parejas como máximo por chequeo, para que no desaparezcan todas de golpe.
@export var max_merges_per_check: int = 8
## Segundos entre chequeos del grupo de gemas vivas.
@export var check_seconds: float = 0.25
@export_group("")

var _check_left: float = 0.0


func _process(delta: float) -> void:
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = maxf(check_seconds, 0.05)
	merge_once()


## Chequeo único: lo usa el reloj y la sonda de fusión. Devuelve las parejas
## que se juntaron de verdad, para que la sonda pueda comprobar el resultado.
func merge_once() -> int:
	var tree := get_tree()
	if tree == null:
		return 0
	var gems := _resting_gems(tree)
	if gems.size() <= maxi(merge_threshold, 1):
		return 0
	var max_dist_sq := maxf(merge_distance, 0.0) ** 2
	var limit := maxi(max_merges_per_check, 1)
	var used: Dictionary[int, bool] = {}
	var merged := 0
	for gem: XpGem in gems:
		if merged >= limit:
			break
		if used.has(gem.get_instance_id()):
			continue
		var nearest: XpGem = null
		var nearest_sq := max_dist_sq
		for other: XpGem in gems:
			if other == gem or used.has(other.get_instance_id()):
				continue
			var dist_sq := gem.global_position.distance_squared_to(other.global_position)
			if dist_sq <= nearest_sq:
				nearest_sq = dist_sq
				nearest = other
		if nearest == null or not gem.merge_from(nearest):
			continue
		used[gem.get_instance_id()] = true
		used[nearest.get_instance_id()] = true
		merged += 1
	return merged


func _resting_gems(tree: SceneTree) -> Array[XpGem]:
	var out: Array[XpGem] = []
	for node: Node in tree.get_nodes_in_group(XpGem.LIVE_GROUP):
		var gem := node as XpGem
		if gem != null and gem.can_merge():
			out.append(gem)
	return out
