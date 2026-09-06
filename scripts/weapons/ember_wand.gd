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
	# A sphere, not a disc: the detonation should catch bodies above and
	# below its center as readily as the ones beside it.
	damage_all(enemies_in_sphere(center, radius))
	_spawn_burst_visual(center, radius)


func _spawn_burst_visual(center: Vector3, radius: float) -> void:
	# Pooled, scene-root parented so the effect stays put while the player
	# moves on (and survives this weapon being freed).
	var burst := Pools.acquire_scene(Pools.EMBER_BURST_SCENE) as EmberBurst
	if burst == null:
		return
	burst.play(center, radius)
