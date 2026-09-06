class_name DeathBurst
extends GPUParticles3D
## One-shot burst of colored low-poly shards (enemy deaths, chest/shrine
## sparkles). Tint rides the per-particle color into a shared unshaded
## vertex-color material; the process material is local-to-scene, so each
## pooled instance keeps its own copy and the draw material is never
## duplicated. Pooled: Juice.burst() acquires one from Pools and calls
## fire(); the scene's `amount` is the buffer size (sized for the biggest
## boss burst) and fire() emits the requested count via amount_ratio, so
## reuse never reallocates the particle buffer.

var _fire_seq: int = 0


## Pooled-node contract: parked bursts sit dark.
func pool_reset() -> void:
	emitting = false


## Starts a burst of `particles` shards and schedules the pool release.
## Call after the node is inside the tree and positioned.
func fire(tint: Color, particles: int) -> void:
	var particle_material := process_material as ParticleProcessMaterial
	if particle_material != null:
		particle_material.color = tint
	# Clamped to the authored buffer, never grown: raising `amount` at
	# runtime reallocates the particle buffer mid-death AND sticks, so the
	# instance that served one boss kept paying for 24+ particles while
	# serving 4-shard grunt bursts forever after. Bigger bursts = a bigger
	# `amount` in the scene (see Juice.boss_burst_amount).
	var wanted := clampi(particles, 1, amount)
	amount_ratio = float(wanted) / float(amount)
	restart()
	# The `finished` signal never fires on the headless dummy renderer, so
	# release on a timer instead; unscaled so a boss-death slow-mo can't
	# stretch cleanup, but PAUSABLE like every other pooled FX (which park
	# themselves from node-bound tweens) — a pause-immune timer recycled
	# bursts whose particles were frozen on screen by the card UI, so the
	# explosion simply vanished mid-air. The sequence guard drops a stale
	# timer if this pooled instance was re-fired in the meantime.
	_fire_seq += 1
	get_tree().create_timer(lifetime + 0.3, false, false, true) \
			.timeout.connect(_on_burst_done.bind(_fire_seq))


func _on_burst_done(seq: int) -> void:
	if seq != _fire_seq:
		return
	Pools.release(self)
