extends WeaponBase
## Látigo de espinas: restalla un latigazo con espinas por una franja angosta
## desde quien lo empuña hacia el blanco, daña a todo cuerpo del grupo
## "enemies" dentro y ralentiza un momento a los EnemyBase (refresca, no
## apila: ver EnemyBase.apply_slow). Sin modelo en la mano: el golpe se lee
## por un WhipCrack del pool, una franja verde que se estira por el carril y
## vuelve, soltando partículas de espinas.

## Ancho total de la franja del latigazo; su largo es attack_range. Los dos crecen con los tomos de área.
@export var strip_width: float = 1.2
## Porcentaje de velocidad que pierden los enemigos azotados (30 = conservan el 70%).
@export var slow_percent: float = 30.0
@export var slow_duration: float = 1.5
## Color de la franja del latigazo.
@export var crack_color: Color = Color(0.5, 0.85, 0.3)

@export_group("Multitud")
## Segundos entre los latigazos extra del Tomo de Multitud; un látigo no puede estar en dos lugares a la vez.
@export var extra_stagger: float = 0.09
## Grados entre latigazos vecinos; la franja es angosta, así que un abanico chico ya separa los carriles.
@export var extra_fan_deg: float = 18.0


func fire(target: Node3D) -> void:
	# Caso degenerado (blanco justo arriba o abajo): se azota hacia donde
	# miramos, y hacia FORWARD si nuestro frente también es vertical.
	var center_dir := flat_dir_or(target.global_position - global_position,
			flat_dir_or(-global_transform.basis.z, Vector3.FORWARD))
	# El largo se fija al disparar: los extras de la ráfaga usan el mismo.
	var length := attack_range * area_scale()
	fire_volley(maxi(effective_projectile_count(), 1), center_dir, _lash.bind(length),
			extra_stagger, extra_fan_deg)


## Un latigazo: la pasada de daño más su visual.
func _lash(lash_dir: Vector3, length: float) -> void:
	_lash_strip(lash_dir, length)
	_spawn_crack_visual(lash_dir, length)


## Golpea a cada enemigo cuya posición plana cae dentro de la franja: a no
## más de `length` a lo largo de lash_dir y a no más de medio ancho (escalado
## por área) de su eje.
func _lash_strip(lash_dir: Vector3, length: float) -> void:
	var half_width := strip_width * 0.5 * area_scale()
	var slow_mult := 1.0 - clampf(slow_percent, 0.0, 95.0) / 100.0
	for body: Node3D in enemies_in_lane(global_position, lash_dir, length, half_width):
		var health := Health.find_in(body)
		if health != null:
			deal_damage(health)
		var enemy := body as EnemyBase
		# Sin ralentizar cadáveres: el latigazo que mató este cuerpo no le
		# deja una ralentización encima (la misma guarda que en stench.gd).
		if enemy != null and (health == null or not health.is_dead):
			enemy.apply_slow(slow_mult, slow_duration * duration_scale())


func _spawn_crack_visual(lash_dir: Vector3, length: float) -> void:
	# Del pool, colgado de la arena: el latigazo queda en su lugar mientras el
	# jugador camina.
	var crack := Pools.acquire_scene(Pools.WHIP_CRACK_SCENE) as WhipCrack
	if crack == null:
		return
	crack.play(global_position + Vector3.UP * 0.9, lash_dir, length, crack_color)
