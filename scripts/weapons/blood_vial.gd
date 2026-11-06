extends WeaponBase
## Vial de sangre: lanza un frasco carmesí al grupo de enemigos más denso en
## alcance; al caer se rompe en un charco de sangre que pulsa daño (`damage`
## es por pulso, por el embudo compartido) y devuelve al jugador como
## curación heal_fraction del daño que hizo el charco: un drenaje propio,
## aparte del robo de vida normal.
## Los charcos son registros BloodPoolEntry que esta arma avanza cada frame
## de física; un charco dura pool_ticks * tick_interval segundos.

## Radio del vecindario con que se puntúa la densidad alrededor de cada candidato.
@export var cluster_radius: float = 3.0
## La puntuación deja de juntar candidatos pasado este número, para acotar el
## conteo O(n^2) de vecinos en hordas enormes.
@export var max_cluster_candidates: int = 24
## Radio del charco (los tomos de área lo escalan al lanzar).
@export var pool_radius: float = 2.2
## Pulsos de daño por charco. La duración es pool_ticks * tick_interval, así
## que "Coagular" (+1 pulso) también alarga el charco un intervalo.
@export var pool_ticks: int = 6
@export var tick_interval: float = 0.5
## Fracción del daño del charco que vuelve al jugador como curación.
@export var heal_fraction: float = 0.15
## Altura máxima, en metros, por encima o por debajo del plano del charco a la que alcanza.
@export var pool_height_window: float = 1.6
## Segundos de vuelo del frasco desde la mano hasta el impacto.
@export var lob_time: float = 0.435
## Altura máxima del arco del frasco sobre la línea recta del lanzamiento.
@export var arc_height: float = 4.145
## Cuánto sobre el punto de impacto se dibuja el charco. El origen de los
## enemigos ya está a ras del suelo: esto solo despega el disco de la cara
## superior del piso; más abajo el disco y el borde quedan enterrados.
@export var pool_ground_offset: float = 0.03

@export_group("Multitud")
## Segundos entre los frascos extra del Tomo de Multitud; lanzados juntos caerían en el mismo charco.
@export var extra_stagger: float = 0.12
## Grados entre frascos vecinos, girados alrededor de QUIEN LANZA para que los charcos extra caigan junto al grupo.
@export var extra_fan_deg: float = 22.0

## Piso de tick_interval al avanzar un charco. Con cero (puesto a mano o por
## una fila de evolución, que WeaponBase.evolve aplica por nombre),
## _tick_pools gastaría todo su presupuesto de pulsos en un frame.
const MIN_TICK_INTERVAL: float = 0.01



## Un charco vivo. Un registro en vez de un Dictionary suelto porque su
## `visual` es un nodo del POOL que cruza frames: con campos el compilador
## atrapa un nombre mal escrito.
class BloodPoolEntry extends RefCounted:
	var center: Vector3 = Vector3.ZERO
	var radius: float = 0.0
	var ticks_left: int = 0
	var tick_timer: float = 0.0
	var visual: BloodPoolFx = null


var _pools: Array[BloodPoolEntry] = []
## Frascos aún en el aire, para que un arma que muere a mitad de lanzamiento
## se los lleve en vez de dejarlos congelados en el arco.
var _flasks_in_flight: Array[MeshInstance3D] = []

var _flask_mesh: SphereMesh


func _ready() -> void:
	# Mismo motivo que en SlimeTrail: los visuales de los charcos son de la
	# etapa y estos registros no, así que el cambio de mapa los suelta.
	RunState.stage_changed.connect(
			func(_index: int, _map_id: String) -> void: clear_weapon_fields())
	# El frasco lanzado es un proyectil visible con una malla compartida por
	# todos los lanzamientos. El charco al caer es la escena BloodPool del pool
	# (borde más oscuro y burbujas lentas).
	_flask_mesh = SphereMesh.new()
	_flask_mesh.radius = 0.14
	_flask_mesh.height = 0.24
	# Teselado explícito: el del motor (64 x 32) es absurdo para un frasco de
	# 28 cm que se ve medio segundo.
	_flask_mesh.radial_segments = 12
	_flask_mesh.rings = 6
	var flask_material := StandardMaterial3D.new()
	flask_material.albedo_color = Color(0.5, 0.06, 0.1)
	flask_material.emission_enabled = true
	flask_material.emission = Color(0.7, 0.08, 0.1)
	flask_material.emission_energy_multiplier = 1.2
	_flask_mesh.material = flask_material


func _physics_process(delta: float) -> void:
	super(delta)
	_tick_pools(delta)


## Charcos y frascos cuelgan de la arena, no de esta arma, así que nada los
## libera cuando el arma se va: se devuelven a mano o las instancias de
## BloodPoolFx laten para siempre y nunca vuelven a Pools. Se guardan al
## instante y sin desvanecer: el tween de expire() se crearía sobre un nodo
## que puede estar saliendo del árbol con nosotros.
func _exit_tree() -> void:
	clear_weapon_fields()
	# Los frascos son del ARMA, no de la etapa: vuelan una fracción de
	# segundo y un cambio de etapa los libera con la arena de todos modos.
	for flask: MeshInstance3D in _flasks_in_flight:
		if is_instance_valid(flask):
			flask.queue_free()
	_flasks_in_flight.clear()


## La mitad opcional del contrato de caída del Player, y el gancho de etapa:
## los VISUALES de los charcos son de la etapa y estos registros viajan con el
## raider, así que sin esto _tick_pools seguiría dañando en las coordenadas de
## la arena anterior, sin nada en pantalla.
func clear_weapon_fields() -> void:
	for pool: BloodPoolEntry in _pools:
		if pool.visual != null and is_instance_valid(pool.visual):
			Pools.release(pool.visual)
		pool.visual = null
	_pools.clear()


## El enemigo en alcance con más vecinos dentro de cluster_radius (entre los
## primeros max_cluster_candidates encontrados): el frasco cae en los grupos,
## no en el rezagado más cercano. En empate gana el primer candidato.
func acquire_target() -> Node3D:
	# Atajo con la horda vacía (ver WeaponBase.acquire_target).
	if get_tree().get_first_node_in_group("enemies") == null:
		return null
	var candidates := enemies_in_sphere(global_position, attack_range)
	if candidates.size() > max_cluster_candidates:
		candidates.resize(max_cluster_candidates)
	var best: Node3D = null
	var best_neighbors := -1
	var cluster_sq := cluster_radius * cluster_radius
	for body: Node3D in candidates:
		var neighbors := 0
		# Fuera del bucle interno: nada dentro mueve un cuerpo.
		var body_position := body.global_position
		for other: Node3D in candidates:
			if other != body and body_position \
					.distance_squared_to(other.global_position) <= cluster_sq:
				neighbors += 1
		if neighbors > best_neighbors:
			best_neighbors = neighbors
			best = body
	return best


func fire(target: Node3D) -> void:
	# Abanico alrededor de quien lanza: se gira el tramo lanzador -> impacto, así
	# la separación lateral crece con la distancia y los charcos quedan en fila.
	var origin := global_position
	fire_volley(maxi(effective_projectile_count(), 1), target.global_position - origin,
			_throw_from.bind(origin), extra_stagger, extra_fan_deg)


## Lanza un frasco a `origin + offset`; ambos se fijan al disparar la ráfaga.
func _throw_from(offset: Vector3, origin: Vector3) -> void:
	_lob_flask(origin + offset)


## Lanza el visual del frasco en un arco parabólico; el charco aparece donde
## cae (la posición del blanco al lanzar), lob_time segundos después.
func _lob_flask(impact: Vector3) -> void:
	var flask := spawn_fx_mesh(_flask_mesh)
	var start := global_position + Vector3.UP * 1.2
	flask.global_position = start
	_flasks_in_flight.append(flask)
	# El tween es NUESTRO, no del frasco: sus pasos llaman a esta arma, y
	# atado al frasco (que cuelga de la arena) seguiría corriendo contra un
	# arma liberada si el arma se fuera antes.
	var tween := create_tween()
	# Se ata el ID de instancia, nunca el nodo: un cambio de etapa libera el
	# frasco en pleno vuelo mientras este tween (del arma, que viaja con el
	# Player) sigue corriendo, y Godot no puede pasar un Object liberado como
	# argumento atado: la llamada falla ANTES de la guarda is_instance_valid()
	# del método. Un int siempre pasa, y la búsqueda de abajo da null si murió.
	var flask_id := flask.get_instance_id()
	tween.tween_method(_arc_flask.bind(flask_id, start, impact), 0.0, 1.0, lob_time)
	tween.tween_callback(_shatter.bind(flask_id, impact))


## Muestra del vuelo: interpolación lineal más un arco que llega al máximo a
## mitad de camino.
func _arc_flask(progress: float, flask_id: int, start: Vector3, impact: Vector3) -> void:
	var flask := _live_flask(flask_id)
	if flask == null:
		return
	var pos := start.lerp(impact, progress)
	pos.y += arc_height * 4.0 * progress * (1.0 - progress)
	flask.global_position = pos


func _shatter(flask_id: int, impact: Vector3) -> void:
	var flask := _live_flask(flask_id)
	if flask != null:
		flask.queue_free()
	# Se reconstruye en vez de borrar por referencia: un frasco que se llevó
	# el cambio de etapa ya no existe, erase() no lo encuentra y el arreglo
	# crecería con una entrada muerta por lanzamiento interrumpido.
	var kept: Array[MeshInstance3D] = []
	for other: MeshInstance3D in _flasks_in_flight:
		if is_instance_valid(other) and other != flask:
			kept.append(other)
	_flasks_in_flight = kept
	_spawn_pool(impact)


## El frasco detrás de un ID, o null si ya fue liberado.
func _live_flask(flask_id: int) -> MeshInstance3D:
	if not is_instance_id_valid(flask_id):
		return null
	return instance_from_id(flask_id) as MeshInstance3D


func _spawn_pool(center: Vector3) -> void:
	# Visual del pool (disco, borde oscuro y burbujas lentas) colgado de la arena.
	var visual := Pools.acquire_scene(Pools.BLOOD_POOL_SCENE) as BloodPoolFx
	var radius := pool_radius * area_scale()
	if visual != null:
		# Apenas sobre el suelo: el origen del cuerpo golpeado ya está EN el
		# suelo, y cualquier cosa debajo se dibuja dentro de la losa opaca.
		visual.play(center + Vector3.UP * pool_ground_offset, radius)
	var pool := BloodPoolEntry.new()
	pool.center = center
	pool.radius = radius
	pool.ticks_left = maxi(roundi(float(pool_ticks) * duration_scale()), 1)
	pool.tick_timer = 0.0
	pool.visual = visual
	_pools.append(pool)


## Avanza cada charco: un pulso cada tick_interval (el primero apenas cae) y
## el charco expira un intervalo después del último pulso, así su duración es
## exactamente pulsos * intervalo.
func _tick_pools(delta: float) -> void:
	var step := maxf(tick_interval, MIN_TICK_INTERVAL)
	# Hacia atrás, para quitar los charcos terminados en el mismo recorrido.
	for i in range(_pools.size() - 1, -1, -1):
		var pool := _pools[i]
		pool.tick_timer -= delta
		while pool.tick_timer <= 0.0 and pool.ticks_left > 0:
			_pulse_pool(pool)
			pool.ticks_left -= 1
			pool.tick_timer += step
		if pool.ticks_left <= 0 and pool.tick_timer <= 0.0:
			_expire_pool(pool)
			_pools.remove_at(i)


## Un pulso de daño: cada enemigo parado en el charco recibe un golpe por el
## embudo compartido, y el jugador bebe una fracción del total.
func _pulse_pool(pool: BloodPoolEntry) -> void:
	var dealt_total := damage_all(
			enemies_in_disc(pool.center, pool.radius, pool_height_window))
	if dealt_total > 0.0:
		# Drenaje propio: la misma curación que usa el robo de vida, pagada
		# sobre el daño que entró de verdad.
		_lifesteal_heal(dealt_total * heal_fraction)


func _expire_pool(pool: BloodPoolEntry) -> void:
	if pool.visual == null or not is_instance_valid(pool.visual):
		return
	# Se desvanece y vuelve solo al pool.
	pool.visual.expire()
	pool.visual = null
