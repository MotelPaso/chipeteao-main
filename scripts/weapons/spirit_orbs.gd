extends WeaponBase
## Orbes espirituales: un anillo de espíritus brillantes que orbitan al
## portador y queman lo que tocan. No dispara: el arma entera es un aura de
## contacto permanente, así que reemplaza _physics_process en vez de fire().
## A propósito NO llama a super(): no hay enfriamiento ni ciclo
## acquire_target()/fire(), el anillo siempre corre.
## Cómo usa los ajustes de WeaponBase:
##   damage           — daño por toque (por deal_damage: crítico y robo de vida aplican)
##   cooldown         — intervalo de re-golpe POR ENEMIGO (los tomos de celeridad lo acortan)
##   attack_range     — radio de la órbita (Largo alcance ensancha el anillo)
##   projectile_count — cantidad de orbes

## Distancia de contacto desde el centro de un orbe hasta un enemigo, en metros.
@export var hit_radius: float = 3.1
## Velocidad angular del anillo, en radianes por segundo.
@export var orbit_speed: float = 2.6
## Altura del anillo sobre los pies del portador, en metros.
@export var orb_height: float = 1.0

## Oscilación vertical que evita que el anillo se lea como una calcomanía plana.
const BOB_HEIGHT: float = 0.15
const ORB_RADIUS: float = 0.40

var _angle: float = 0.0
var _orbs: Array[MeshInstance3D] = []
## Centro del anillo este frame (los pies del montaje portador); se guarda
## para que el contacto acote su búsqueda alrededor del mismo punto.
var _ring_center: Vector3 = Vector3.ZERO
## Temporizadores de re-golpe por enemigo, por ID de instancia.
var _rehit: Dictionary[int, float] = {}
## Lista auxiliar de _tick_rehit: las claves cuyo temporizador terminó este
## frame. Es un miembro para que la cuenta regresiva no reserve memoria en
## los frames donde nada expira.
var _rehit_expired: Array[int] = []
## Lista auxiliar de _touch_enemies: la posición mundial de cada orbe este frame.
var _orb_positions: PackedVector3Array = PackedVector3Array()
## Una malla (con su material) compartida por todos los orbes durante la vida
## del arma: _rebuild_orbs corre cada vez que una mejora cambia la cantidad.
var _orb_mesh: SphereMesh = null


func _ready() -> void:
	_orb_mesh = SphereMesh.new()
	_orb_mesh.radius = ORB_RADIUS
	_orb_mesh.height = ORB_RADIUS * 2.0
	# Teselado explícito: el del motor (64 x 32) son miles de triángulos por
	# orbe para una bola brillante sin sombreado.
	_orb_mesh.radial_segments = 12
	_orb_mesh.rings = 6
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.6, 0.95, 1.0)
	material.emission_enabled = true
	material.emission = Color(0.45, 0.9, 1.0)
	material.emission_energy_multiplier = 2.2
	_orb_mesh.material = material


func _physics_process(delta: float) -> void:
	if _orbs.size() != effective_projectile_count():
		_rebuild_orbs()
	_update_ring(delta)
	_tick_rehit(delta)
	_touch_enemies()


## Presentación: avanza el reloj de la órbita y coloca los orbes en el mundo.
func _update_ring(delta: float) -> void:
	_angle = wrapf(_angle + orbit_speed * delta, 0.0, TAU)
	var radius := attack_range
	# Anillo en espacio mundial alrededor de los pies del portador: el ángulo
	# de la órbita tiene su propio reloj, así girar o moverse de lado no
	# arrastra el anillo con el cuerpo (los orbes son hijos, de ahí
	# global_position). El centro sigue al montaje portador: el anillo de una
	# mascota orbita a la mascota.
	_ring_center = global_position
	var carrier := carrier_node()
	if carrier != null:
		_ring_center = carrier.global_position
	for i in _orbs.size():
		var orb_angle := _angle + TAU * float(i) / float(_orbs.size())
		_orbs[i].global_position = _ring_center + Vector3(
				cos(orb_angle) * radius,
				orb_height + sin(orb_angle * 2.0) * BOB_HEIGHT,
				sin(orb_angle) * radius)


## Simulación: descuenta la inmunidad por enemigo que dejó el último toque.
## Recorre el diccionario en su lugar: escribir un valor bajo una clave
## existente es seguro durante la iteración, borrar no, así que los borrados
## esperan al final del bucle.
func _tick_rehit(delta: float) -> void:
	for key: int in _rehit:
		var left := _rehit[key] - delta
		_rehit[key] = left
		if left <= 0.0:
			_rehit_expired.append(key)
	if _rehit_expired.is_empty():
		return
	for key: int in _rehit_expired:
		_rehit.erase(key)
	_rehit_expired.clear()


## Simulación: quema a cada enemigo que un orbe está tocando ahora.
func _touch_enemies() -> void:
	if get_tree().get_first_node_in_group("enemies") == null:
		return
	var reach := hit_radius * area_scale()
	var reach_sq := reach * reach
	# Fase amplia alrededor del centro del anillo. Ningún orbe está más lejos
	# que attack_range en horizontal más orb_height + BOB_HEIGHT en vertical,
	# y ningún contacto pasa de `reach` desde un orbe, así que esta esfera
	# contiene todo lo que la prueba por orbe de abajo puede aceptar.
	var search := attack_range + orb_height + BOB_HEIGHT + reach
	# La posición de cada orbe se lee UNA vez por frame, por el getter (no se
	# toma lo que escribió _update_ring) para que sea idéntica bit a bit; nada
	# de lo que dispara un golpe mueve al portador.
	_orb_positions.resize(_orbs.size())
	for i: int in _orbs.size():
		_orb_positions[i] = _orbs[i].global_position
	var aim_lift := Vector3.UP * orb_height * 0.5
	for body: Node3D in enemies_in_sphere(_ring_center, search):
		if _rehit.has(body.get_instance_id()):
			continue
		# Una vez por cuerpo: el bucle de orbes daña como máximo una vez y
		# corta, así que el cuerpo no puede moverse entre dos lecturas.
		var aim := body.global_position + aim_lift
		for orb_position: Vector3 in _orb_positions:
			if orb_position.distance_squared_to(aim) > reach_sq:
				continue
			var health := Health.find_in(body)
			if health != null and not health.is_dead:
				deal_damage(health)
				_rehit[body.get_instance_id()] = effective_cooldown()
			break


## Rehace los orbes cuando una mejora cambió la cantidad. Solo los nodos
## MeshInstance3D son nuevos; malla y material se comparten.
func _rebuild_orbs() -> void:
	for orb: MeshInstance3D in _orbs:
		orb.queue_free()
	_orbs.clear()
	for i in effective_projectile_count():
		var orb := MeshInstance3D.new()
		orb.mesh = _orb_mesh
		# Un espíritu brillante no proyecta sombra: se leería como ruido y
		# costaría un dibujo en cada cascada de sombras (como todo efecto,
		# ver spawn_fx_mesh).
		orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(orb)
		_orbs.append(orb)
