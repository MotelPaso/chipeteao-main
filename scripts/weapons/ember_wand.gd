extends WeaponBase
## Vara de brasas: en cada enfriamiento lanza una bola de fuego hacia el
## blanco. La bola no daña por sí misma: solo si choca con un enemigo explota
## en el punto del choque, y la explosión daña a todo cuerpo del grupo
## "enemies" dentro de burst_radius y le deja una quemadura (daño por segundo
## aparte del veneno). El visual de la explosión es un EmberBurst del pool:
## cáscara que se expande, una marca en el suelo y brasas que suben.

@export_group("Bola de fuego")
## Escena de la bola de fuego (EmberBall.tscn: su tamaño y color están ahí).
@export var projectile_scene: PackedScene
## Velocidad de vuelo de la bola, en m/s.
@export var projectile_speed: float = 22.0
## Radianes por segundo que la bola puede girar hacia su blanco; más alto = menos fallos.
@export var homing_turn_speed: float = 8.0
## La bola vuela este múltiplo de attack_range antes de apagarse sin explotar.
@export var range_grace: float = 1.4

@export_group("Estallido")
## Radio de la explosión, en metros (los tomos de área lo escalan); la evolución «Lanza solar» lo multiplica.
@export var burst_radius: float = 2.5

@export_group("Quemadura")
## Quemadura por segundo, como fracción del daño efectivo del arma (0.3 = 30%).
@export var burn_damage_fraction: float = 0.3
## Segundos que dura la quemadura (los alarga el Tomo de Persistencia).
@export var burn_duration: float = 3.0

@export_group("Multitud")
## Segundos entre las bolas extra del Tomo de Multitud.
@export var extra_stagger: float = 0.1


func fire(target: Node3D) -> void:
	fire_volley_retarget(maxi(effective_projectile_count(), 1),
			_launch.bind(target), _relaunch, extra_stagger)


## Una bola extra del Tomo de Multitud: busca su PROPIO blanco, así los extras
## se reparten por la horda en vez de caer todos en el mismo.
func _relaunch() -> void:
	var target := acquire_target()
	if target != null:
		_launch(target)


## `target` es Variant: la bola extra sale un instante después y el enemigo
## pudo liberarse; un parámetro tipado fallaría antes del is_instance_valid.
func _launch(target: Variant) -> void:
	if projectile_scene == null:
		push_warning("%s: projectile_scene not set" % name)
		return
	if not is_instance_valid(target):
		return
	var live_target := target as Node3D
	var direction := aim_dir_or(body_aim_point(live_target) - global_position,
			-global_transform.basis.z)
	var ball := Pools.acquire_scene(projectile_scene) as Projectile
	if ball == null:
		return
	ball.global_transform = Transform3D(
			Basis.looking_at(direction, safe_up(direction)), global_position)
	ball.launch(self, attack_range * range_grace, live_target)
	# Después del reinicio del pool, que los deja en su valor de escena.
	ball.speed = projectile_speed
	ball.homing_turn_speed = homing_turn_speed
	ball.assisted = true
	ball.on_impact = _detonate


## `struck` es el enemigo que chocó la bola: siempre recibe la explosión. Los
## demás cuentan si su punto de puntería (el centro del cuerpo, no los pies)
## queda dentro del radio, porque la bola choca a la altura del cuerpo.
func _detonate(center: Vector3, struck: Node3D) -> void:
	# Una bola que explota con el arma ya liberada (raider quitado) no hace nada.
	if not is_inside_tree():
		return
	# Los tomos de área agrandan el estallido; el visual crece al mismo radio.
	var radius := burst_radius * area_scale()
	var burn_dps := effective_damage() * burn_damage_fraction
	var burn_time := burn_duration * duration_scale()
	for body: Node3D in _bodies_in_blast(center, radius, struck):
		var health := Health.find_in(body)
		if health != null:
			deal_damage(health)
		var enemy := body as EnemyBase
		if enemy != null and (health == null or not health.is_dead):
			enemy.apply_burn(burn_dps, burn_time)
	_spawn_burst_visual(center, radius)


## Una esfera, no un disco: alcanza cuerpos por encima y por debajo del centro.
func _bodies_in_blast(center: Vector3, radius: float, struck: Node3D) -> Array[Node3D]:
	var found: Array[Node3D] = []
	if is_instance_valid(struck) and struck.is_in_group("enemies"):
		found.append(struck)
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var body := node as Node3D
		if body == null or body == struck or not body.is_inside_tree():
			continue
		var reach := radius + body_hit_radius(body)
		if center.distance_squared_to(body_aim_point(body)) <= reach * reach:
			found.append(body)
	return found


func _spawn_burst_visual(center: Vector3, radius: float) -> void:
	# Del pool, colgado de la arena: el efecto queda en su lugar mientras el
	# jugador camina (y sobrevive a que esta arma se libere).
	var burst := Pools.acquire_scene(Pools.EMBER_BURST_SCENE) as EmberBurst
	if burst == null:
		return
	burst.play(center, radius)
