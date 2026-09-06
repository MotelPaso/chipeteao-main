extends WeaponBase
## Stench ("Mal olor", iteration 43): flatulent pulses — every cooldown a
## gas cloud bursts from the carrier, damaging everything in its radius,
## poisoning it and slowing it. Knob mapping:
##   damage        — burst hit (through deal_damage); poison dps derives from it
##   cooldown      — seconds between pulses
##   attack_range  — cloud radius (area tomes scale it)
## Poison and slow durations follow the duration stat.

@export var poison_damage_fraction: float = 0.4
@export var poison_duration: float = 3.0
@export var slow_multiplier: float = 0.6
@export var slow_duration: float = 2.0
@export var gas_color: Color = Color(0.55, 0.8, 0.25)
@export var height_window: float = 2.2

## Extra cloud radius per point of Tome of Multitude, as a fraction of the
## base radius. The tome cannot add CLOUDS here: a second burst is centered
## on the same carrier, so it is the same sphere drawn twice — invisible,
## and it would silently double every pulse's damage, poison and slow. The
## extra count grows the one cloud instead.
const STENCH_RADIUS_PER_EXTRA: float = 0.12
## Fraction of the pulse interval each extra point shaves off, so a stacked
## tome also makes the gas go off more often.
const STENCH_PULSE_PER_EXTRA: float = 0.08
## Floor on the accumulated pulse scale: the poison and slow it applies are
## refreshes, so an interval that collapsed would just be a permanent field.
const STENCH_MIN_PULSE_SCALE: float = 0.6

var _shell_mesh: SphereMesh = null


func _ready() -> void:
	_shell_mesh = SphereMesh.new()
	_shell_mesh.radius = 1.0
	_shell_mesh.height = 2.0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(gas_color, 0.35)
	material.emission_enabled = true
	material.emission = gas_color
	material.emission_energy_multiplier = 0.5
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shell_mesh.material = material


## Cloud radius: the damage area, the drawn shell and the pulse trigger all
## read this one number — and so does fire(), which is where the Tome of
## Multitude bonus below reaches the attack.
func reach() -> float:
	return attack_range * area_scale() \
			* (1.0 + STENCH_RADIUS_PER_EXTRA * float(_multitude_extra()))


## Pulses per second rise with the tome too (see STENCH_PULSE_PER_EXTRA);
## the floor keeps a heavy stack from collapsing the interval into a tick.
func effective_cooldown() -> float:
	var pulse_scale := maxf(1.0 - STENCH_PULSE_PER_EXTRA * float(_multitude_extra()),
			STENCH_MIN_PULSE_SCALE)
	return maxf(super() * pulse_scale, MIN_COOLDOWN)


## Projectiles past the first this weapon would have fired, i.e. what the
## Tome of Multitude granted (weapon ascensions raise projectile_count too).
func _multitude_extra() -> int:
	return maxi(effective_projectile_count() - 1, 0)


## The cloud IS the hit area, so the pulse has to trigger on anything inside
## it. Leaving this at attack_range made the area-scaled outer band purely
## decorative: with a big area multiplier and every enemy in that band the
## gas simply never went off.
func targeting_range() -> float:
	return reach()


func fire(_target: Node3D) -> void:
	var radius := reach()
	var poison_dps := effective_damage() * poison_damage_fraction
	for body: Node3D in enemies_in_disc(global_position, radius, height_window):
		var health := Health.find_in(body)
		if health != null:
			deal_damage(health)
		var enemy := body as EnemyBase
		# Corpses take no status: apply_poison already refuses the dead, and
		# writing a slow onto a body this very pulse killed only leaves state
		# behind for whatever reads it next (a revived dummy, say).
		if enemy != null and (health == null or not health.is_dead):
			enemy.apply_poison(poison_dps, poison_duration * duration_scale())
			enemy.apply_slow(slow_multiplier, slow_duration * duration_scale())
	_play_cloud(radius)


## Expanding translucent sphere that thins out — the "pfff" read.
func _play_cloud(radius: float) -> void:
	var shell := spawn_fx_mesh(_shell_mesh)
	shell.global_position = global_position + Vector3.DOWN * 0.3
	shell.scale = Vector3.ONE * 0.3
	var tween := shell.create_tween()
	tween.set_parallel(true)
	tween.tween_property(shell, "scale", Vector3.ONE * radius, 0.45) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(shell, "transparency", 1.0, 0.6) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(shell.queue_free)
