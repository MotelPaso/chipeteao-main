class_name Telegraph
extends RefCounted
## Ground-telegraph front door: a flat emissive disc that grows from its
## center to full radius over the wind-up (the fill level reads as a
## countdown) while its glow ramps up, then fades out. The signature is
## unchanged for every caster, but the disc is now a pooled TelegraphDisc
## (Pools) instead of a per-cast mesh+material build; it still lives at the
## scene root so the cue survives its caster dying mid-telegraph, and it
## releases itself after the fade. Purely visual — attack timing and
## damage stay in the caller.


static func spawn_disc(_host: Node, center: Vector3, radius: float,
		duration: float, color: Color) -> void:
	var disc := Pools.acquire_scene(Pools.TELEGRAPH_DISC_SCENE) as TelegraphDisc
	if disc == null:
		return
	disc.show_disc(center, radius, duration, color)
