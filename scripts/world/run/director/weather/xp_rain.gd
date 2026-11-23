class_name XpRain
extends RefCounted
## Lluvia de XP de la luna llena: cuánta XP reparte y en cuántas gemas, y
## cómo cae cada gema. Los números son exports del nodo Weather (grupo
## «Luna llena»); este script solo hace la cuenta y suelta las gemas.


## Plan de la lluvia: {gems, value, every}. La XP total alcanza para subir
## `levels` niveles desde ahora, ya divididos los multiplicadores de XP de la
## partida (dificultad) y del grupo, así los niveles que se ven son esos.
## Al principio la XP total es poca y salen menos gemas que `max_gems`.
static func plan(levels: float, max_gems: int, seconds: float,
		raiders: Array[Node3D]) -> Dictionary:
	var multiplier := RunState.difficulty_xp_multiplier() * _party_xp_multiplier(raiders)
	var total := float(RunState.xp_for_levels(levels)) / maxf(multiplier, 0.01)
	var gems := clampi(roundi(total), 1, maxi(max_gems, 1))
	return {
		"gems": gems,
		"value": maxi(roundi(total / float(gems)), 1),
		"every": maxf(seconds, 0.1) / float(gems),
	}


## Una gema cae del cielo cerca de un jugador al azar: un destello arriba y
## la gema en el suelo. Si el anillo está tapado, cae junto al jugador.
static func drop_gem(tree: SceneTree, layout: StageLayout, value: int,
		min_distance: float, max_distance: float, color: Color,
		burst_height: float, burst_count: int) -> void:
	var anchor := Coop.random_player(tree)
	if anchor == null:
		return
	var at := Vector3.INF
	if layout != null:
		at = layout.rain_point(anchor.global_position, min_distance, max_distance)
	if at == Vector3.INF:
		at = anchor.global_position
	var gem := Pools.acquire_scene(Pools.XP_GEM_SCENE) as XpGem
	if gem == null:
		return
	gem.xp_value = value
	gem.global_position = at + Vector3.UP * 0.6
	Juice.burst(at + Vector3.UP * burst_height, color, burst_count)


## Multiplicador de XP promedio del grupo (Tomo de Sabiduría, la propia luna
## llena…): cualquiera puede recoger las gemas.
static func _party_xp_multiplier(raiders: Array[Node3D]) -> float:
	var total := 0.0
	var count := 0
	for body: Node3D in raiders:
		var stats := PlayerStats.find_in(body)
		if stats != null:
			total += stats.xp_multiplier
			count += 1
	return total / float(count) if count > 0 else 1.0
