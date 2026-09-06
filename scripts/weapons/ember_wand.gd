extends WeaponBase
## Ash's starting weapon: on cooldown, detonates a fire burst at the target's
## position, damaging every "enemies"-group body within burst_radius. The
## visual is a pooled EmberBurst: expanding emissive shell, a lingering
## ground scorch that fades, and rising ember particles (headless-safe).

@export var burst_radius: float = 2.5

## Seconds between the detonations a Tome of Multitude adds. Staggered, not
## simultaneous: two bursts on the same body in the same frame are one
## explosion that happens to roll damage twice.
const EXTRA_BURST_STAGGER: float = 0.1
## The whole staggered chain has to end inside this fraction of one
## cooldown, or the tail of one volley would overlap the next.
const BURST_CHAIN_WINDOW: float = 0.6


func fire(target: Node3D) -> void:
	var count := maxi(effective_projectile_count(), 1)
	var step := minf(EXTRA_BURST_STAGGER,
			effective_cooldown() * BURST_CHAIN_WINDOW / float(maxi(count - 1, 1)))
	_detonate(target.global_position)
	for i: int in range(1, count):
		# Pausable and stepped in physics: an extra burst must not go off
		# while the upgrade UI holds the tree, and damage belongs on the
		# same tick the rest of the combat runs on.
		get_tree().create_timer(step * float(i), false, true).timeout \
				.connect(_rekindle)


## A follow-up detonation from a Tome of Multitude. It picks its OWN center
## instead of reusing the volley's: the opening burst may have cleared that
## spot, and re-acquiring walks the extras across the horde. Lands a beat
## after fire(), when this weapon may already have left the tree with a
## removed raider.
func _rekindle() -> void:
	if not is_inside_tree():
		return
	var target := acquire_target()
	if target != null:
		_detonate(target.global_position)


func _detonate(center: Vector3) -> void:
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
