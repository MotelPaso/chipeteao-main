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

## Segundos entre los latigazos que agrega el Tomo de Multitud. Un látigo no
## puede estar en dos lugares a la vez, así que los extras restallan uno tras otro.
const EXTRA_LASH_STAGGER: float = 0.09
## Giro entre latigazos vecinos: la franja es angosta, así que un abanico
## chico basta para que cada extra barra su propio carril.
const EXTRA_LASH_FAN_DEG: float = 18.0
## La cadena escalonada entera termina dentro de esta fracción de un
## enfriamiento, o la cola de una ráfaga se montaría sobre la siguiente.
const LASH_CHAIN_WINDOW: float = 0.6


func fire(target: Node3D) -> void:
	# Caso degenerado (blanco justo arriba o abajo): se azota hacia donde
	# miramos, y hacia FORWARD si nuestro frente también es vertical.
	var center_dir := flat_dir_or(target.global_position - global_position,
			flat_dir_or(-global_transform.basis.z, Vector3.FORWARD))
	var length := attack_range * area_scale()
	var count := maxi(effective_projectile_count(), 1)
	var step := minf(EXTRA_LASH_STAGGER,
			effective_cooldown() * LASH_CHAIN_WINDOW / float(maxi(count - 1, 1)))
	for i: int in count:
		var yaw := deg_to_rad(EXTRA_LASH_FAN_DEG) * (float(i) - float(count - 1) * 0.5)
		var lash_dir := center_dir.rotated(Vector3.UP, yaw)
		if i == 0:
			_lash(lash_dir, length)
		else:
			# Temporizador pausable y en paso de física: un latigazo extra no
			# sale con la pantalla de mejoras abierta, y el daño cae en el mismo
			# tick que el resto del combate.
			get_tree().create_timer(step * float(i), false, true).timeout \
					.connect(_lash.bind(lash_dir, length))


## Un latigazo: la pasada de daño más su visual. Los extras escalonados
## llegan aquí un poco después, cuando el arma puede haber salido del árbol
## con un raider quitado.
func _lash(lash_dir: Vector3, length: float) -> void:
	if not is_inside_tree():
		return
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
