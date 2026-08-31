extends WeaponBase
## Ash's starting weapon: on cooldown, detonates a fire burst at the target's
## position, damaging every "enemies"-group body within burst_radius. The
## visual is a pooled EmberBurst: expanding emissive shell, a lingering
## ground scorch that fades, and rising ember particles (headless-safe).

@export var burst_radius: float = 2.5


func fire(target: Node3D) -> void:
	var center := target.global_position
	# Area tomes grow the burst; the visual expands to the same radius.
	var radius := burst_radius * area_scale()
	var radius_sq := radius * radius
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var body := enemy as Node3D
		if body == null or not body.is_inside_tree():
			continue
		if center.distance_squared_to(body.global_position) > radius_sq:
			continue
		var health := Health.find_in(body)
		if health != null:
			deal_damage(health)
	_spawn_burst_visual(center, radius)


func _spawn_burst_visual(center: Vector3, radius: float) -> void:
	# Pooled, scene-root parented so the effect stays put while the player
	# moves on (and survives this weapon being freed).
	var burst := Pools.acquire_scene(Pools.EMBER_BURST_SCENE) as EmberBurst
	if burst == null:
		return
	burst.play(center, radius)
