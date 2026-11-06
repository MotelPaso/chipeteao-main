class_name Skirmisher
extends EnemyBase
## Hostigador a distancia: mantiene una banda de distancia con el raider
## (avanza si está lejos, retrocede si está encima, se planta y dispara
## dentro) y lanza saetas lentas y esquivables con un ritmo fijo. Siempre
## mira al raider, incluso al retroceder, para que se lea como tirador.

@export var band_inner: float = 8.0
@export var band_outer: float = 12.0
@export var fire_cooldown: float = 3.0
@export var fire_range: float = 18.0
## Daño de cada saeta. Las saetas son el desgaste dominante de la partida
## una vez que se aprende a esquivar el contacto, así que subirlo pesa más
## de lo que parece.
@export var bolt_damage: float = 6.0
@export var bolt_scene: PackedScene
## Las saetas salen a la altura de la mano y van al pecho del raider.
@export var muzzle_height: float = 1.2
@export var target_height: float = 0.9

# Espera inicial para que uno recién aparecido no dispare al aterrizar.
var _fire_timer: float = 1.0


func _init() -> void:
	# No poseíble: dispara EnemyBolts que solo dañan al grupo "player", así
	# que poseído seguiría atacando al equipo al que ahora pertenece.
	possessable = false


func _behavior_tick(delta: float) -> void:
	_fire_timer = maxf(_fire_timer - delta, 0.0)


func _movement_intent(seek: Vector3, distance: float) -> Vector3:
	if distance > band_outer:
		return seek
	if distance < band_inner:
		return -seek
	return Vector3.ZERO


func _facing_direction(steer: Vector3, seek: Vector3) -> Vector3:
	return seek if seek.length_squared() > 0.0001 else steer


func _combat_tick(player: Node3D, distance: float) -> void:
	# El mínimo también aleja a look_at del caso degenerado de mirar recto
	# hacia arriba cuando el raider está parado sobre su cabeza.
	if _fire_timer > 0.0 or distance > fire_range or distance < 0.5:
		return
	if bolt_scene == null:
		return
	# Solo un tiro que salió de verdad gasta la espera.
	if _fire_bolt(player):
		_fire_timer = fire_cooldown


## Bajo este largo al cuadrado una puntería es "ninguna dirección" (el
## tirador está parado sobre su objetivo): un milímetro al cuadrado.
const AIM_EPSILON_SQ: float = 0.000001


func _fire_bolt(player: Node3D) -> bool:
	# Del pool, colgada de la raíz de la escena para sobrevivir a su tirador.
	var bolt := Pools.acquire_scene(bolt_scene) as EnemyBolt
	if bolt == null:
		return false
	bolt.damage = bolt_damage
	bolt.global_position = global_position + Vector3.UP * muzzle_height
	bolt.launcher = self
	# La saeta vuela hacia la puntería 3D real; si es casi colineal con UP
	# (raider saltando justo encima) look_at no puede armar una base, así que
	# se usa WeaponBase.safe_up, la única guarda y el único umbral de toda
	# puntería del juego.
	var to_target := player.global_position + Vector3.UP * target_height \
			- bolt.global_position
	# Si la horda lo empuja encima del raider, dispara desde EXACTAMENTE el
	# punto objetivo: normalized() da cero y look_at falla. La orientación
	# propia del tirador es el respaldo honesto.
	var aim := to_target.normalized() if to_target.length_squared() > AIM_EPSILON_SQ \
			else -global_transform.basis.z
	var up := WeaponBase.safe_up(aim)
	var aim_at := bolt.global_position + aim
	# look_at rechaza un origen que considera igual a su objetivo, y lo decide
	# con Vector3.is_equal_approx (tolerancia RELATIVA a las coordenadas), así
	# que ni una puntería unitaria lo descarta. Se usa el mismo predicado del
	# motor: el camino normal queda intacto y el degenerado arma la misma base
	# que haría look_at (Basis.looking_at, conservando la escala) y lo registra.
	if bolt.global_position.is_equal_approx(aim_at):
		print("Skirmisher degenerate aim: bolt=%v aim=%v self=%v" % [
				bolt.global_position, aim, global_position])
		var bolt_scale := bolt.scale
		bolt.global_transform = Transform3D(Basis.looking_at(aim, up), bolt.global_position)
		bolt.scale = bolt_scale
	else:
		bolt.look_at(aim_at, up)
	return true


func _apply_elite_damage(multiplier: float) -> void:
	bolt_damage *= multiplier
