class_name MythosBolts
extends RefCounted
## Lo que comparten los ataques de Mythos para apuntar: el abanico de plumas
## de fuego (EnemyBolt del pool) y el cálculo de adónde va a estar un raider.
## La velocidad y el alcance de cada pluma son los de su escena
## (FireFeather.tscn).


## Abanico de `count` plumas desde `origin` hacia `target`, abierto `spread`
## radianes en el plano. Apunta adonde el raider va a estar cuando lleguen:
## `lead` es qué parte de ese adelanto se usa (0 = donde está ahora) y
## `max_lead` su tope en metros. `shift` corre el abanico una fracción del
## paso entre plumas (0.5 = medio paso: cae en los huecos de la tanda anterior).
static func fan(boss: Mythos, scene: PackedScene, origin: Vector3, target: Node3D,
		count: int, spread: float, damage: float, shift: float = 0.0, lead: float = 0.0,
		max_lead: float = 0.0, target_height: float = 0.9) -> void:
	if scene == null or not is_instance_valid(target):
		return
	var bolts: Array[EnemyBolt] = []
	for i: int in maxi(count, 1):
		var bolt := Pools.acquire_scene(scene) as EnemyBolt
		if bolt == null:
			break
		bolts.append(bolt)
	if bolts.is_empty():
		return
	var seconds := origin.distance_to(target.global_position) / maxf(bolts[0].speed, 0.1)
	var aim := predicted(target, seconds * lead, max_lead) + Vector3.UP * target_height
	var flat := aim - origin
	var drop := flat.y
	flat.y = 0.0
	var reach := maxf(flat.length(), 0.1)
	var base_angle := atan2(flat.z, flat.x)
	var step := spread / float(maxi(bolts.size() - 1, 1))
	for i: int in bolts.size():
		var angle := base_angle + (float(i) - float(bolts.size() - 1) * 0.5 + shift) * step
		_launch(bolts[i], boss, origin,
				Vector3(cos(angle) * reach, drop, sin(angle) * reach), damage)


## Una sola pluma desde `origin` hacia `direction`.
static func shot(boss: Mythos, scene: PackedScene, origin: Vector3, direction: Vector3,
		damage: float) -> void:
	var bolt := Pools.acquire_scene(scene) as EnemyBolt if scene != null else null
	if bolt != null:
		_launch(bolt, boss, origin, direction, damage)


## Dónde va a estar `target` dentro de `seconds` si sigue como va, nunca a
## más de `max_lead` metros de donde está ahora. Siempre a ras de sus pies.
static func predicted(target: Node3D, seconds: float, max_lead: float) -> Vector3:
	var body := target as CharacterBody3D
	if body == null or seconds <= 0.0 or max_lead <= 0.0:
		return target.global_position
	var ahead := body.velocity * seconds
	ahead.y = 0.0
	return target.global_position + ahead.limit_length(max_lead)


static func _launch(bolt: EnemyBolt, boss: Mythos, origin: Vector3, direction: Vector3,
		damage: float) -> void:
	var heading := direction.normalized()
	bolt.damage = damage
	bolt.launcher = boss
	bolt.global_position = origin
	bolt.look_at(origin + heading, WeaponBase.safe_up(heading))
