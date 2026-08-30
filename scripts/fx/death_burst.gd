class_name DeathBurst
extends GPUParticles3D
## One-shot burst of colored low-poly shards (enemy deaths, chest/shrine
## sparkles). Tint rides the per-particle color into a shared unshaded
## vertex-color material; the process material is local-to-scene, so each
## burst gets its own copy at instantiate and the draw material is never
## duplicated. Spawn via Juice.burst(), which sets `amount` before adding
## to the tree, then calls fire().


## Starts the burst and schedules the self-free. Call after add_child.
func fire(tint: Color) -> void:
	var particle_material := process_material as ParticleProcessMaterial
	if particle_material != null:
		particle_material.color = tint
	emitting = true
	# The `finished` signal never fires on the headless dummy renderer, so
	# free on a pause-immune timer instead; unscaled so a boss-death
	# slow-mo can't stretch cleanup.
	get_tree().create_timer(lifetime + 0.3, true, false, true) \
			.timeout.connect(queue_free)
