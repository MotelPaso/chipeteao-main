class_name Grunt
extends EnemyBase
## Melee grunt: chases straight at the player (EnemyBase supplies the seek,
## separation, and death flow) and damages the player on contact, on a
## cooldown.

@export var contact_damage: float = 5.0
@export var attack_cooldown: float = 0.8
@export var attack_range: float = 1.3
## Height gate: a player this far above the grunt's footing (a ledge, a
## well-timed jump) is out of melee reach. An @export like every other
## enemy's height window, so a taller melee body can widen it in its scene.
@export var melee_height_window: float = 1.6

var _attack_timer: float = 0.0


func _behavior_tick(delta: float) -> void:
	_attack_timer = maxf(_attack_timer - delta, 0.0)


func _combat_tick(player: Node3D, distance: float) -> void:
	if _attack_timer > 0.0 or distance > attack_range:
		return
	if absf(player.global_position.y - global_position.y) > melee_height_window:
		return
	var player_health := Health.find_in(player)
	if player_health == null or player_health.is_dead:
		return
	_attack_timer = attack_cooldown
	# Passing ourselves as attacker lets player thorns retaliate.
	player_health.take_damage(contact_damage, false, self)


func _apply_elite_damage(multiplier: float) -> void:
	contact_damage *= multiplier
