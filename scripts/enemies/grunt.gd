class_name Grunt
extends EnemyBase
## Esbirro cuerpo a cuerpo: persigue en línea recta (EnemyBase pone la
## persecución, la separación y la muerte) y daña al raider por contacto,
## con un tiempo de espera entre golpes.

@export_group("Cuerpo a cuerpo")
## Daño de cada golpe al raider; los shiny y las variantes del cielo lo multiplican.
@export var contact_damage: float = 5.0
## Segundos entre golpes.
@export var attack_cooldown: float = 0.8
## Distancia al raider, en metros, a la que golpea.
@export var attack_range: float = 1.3
## Metros sobre los pies del esbirro por encima de los cuales el raider queda fuera de su alcance.
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
	# Se nombra como atacante para que las espinas del raider respondan.
	player_health.take_damage(contact_damage, false, self)


func _apply_elite_damage(multiplier: float) -> void:
	contact_damage *= multiplier


## Un siervo levantado de este cadáver pega como él (una mole poseída sigue
## pegando como mole).
func _copy_combat_stats_to(servant: EnemyBase) -> void:
	var grunt := servant as Grunt
	if grunt != null:
		grunt.contact_damage = contact_damage
	super(servant)
