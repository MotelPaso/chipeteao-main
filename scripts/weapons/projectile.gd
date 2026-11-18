class_name Projectile
extends Area3D
## Bala de arma: vuela por -Z (curvándose un poco hacia el blanco al que se
## disparó) y daña los cuerpos del grupo "enemies" que toca, cada uno como
## máximo una vez, hasta agotar su perforación (1 = dardo clásico).
## El arma la saca de Pools (colgada de la arena, así sobrevive al movimiento
## del jugador); vuelve al pool al gastar la perforación o tras max_distance,
## y pool_reset() rearma perforación, registro de golpes y trazador.
## Rebotes: si el arma fija bounces_left > 0, al gastar la perforación la bala
## sale directa hacia el enemigo más cercano que aún no golpeó, esté vivo o no
## el anterior (ver _bounce_to_next()).

@export_group("Vuelo")
## Velocidad de vuelo, en metros por segundo.
@export var speed: float = 26.0
## Si el vuelo se curva hacia el blanco (las flechas vuelan rectas).
@export var homing_enabled: bool = true
## Radianes por segundo que el vuelo puede girar hacia el blanco; 0 apaga la persecución.
@export var homing_turn_speed: float = 3.5
## Cuántos enemigos distintos puede dañar antes de desaparecer (el Arco de caza lo reemplaza por su pierce_count en cada flecha).
@export var pierce_remaining: int = 1
## El trazador nace estirado este factor a lo largo y vuelve a 1 (sensación de estela).
@export var spawn_stretch: float = 2.4

## Segundos que tarda el estirón inicial en volver a 1.
const TRACER_RELAX_TIME: float = 0.12
## Vida máxima de una bala en segundos. Pasado esto se libera sola: una bala
## que se queda quieta en el aire o en el suelo nunca dura más que esto.
const MAX_LIFETIME: float = 4.0
## Distancia máxima, en metros, a la que un rebote busca el siguiente enemigo.
const BOUNCE_RANGE: float = 15.0
## Giro (rad/s) mínimo tras un rebote: la bala va directa al nuevo blanco.
const BOUNCE_TURN_SPEED: float = 40.0
## Alcance de cada tramo tras un rebote, como múltiplo de BOUNCE_RANGE (un
## margen para que la bala llegue aunque el enemigo se mueva).
const BOUNCE_LEG_FACTOR: float = 1.5

## Alcance, en metros, con que una bala asistida busca nuevo blanco si el suyo
## muere o no existe (ver _retarget_if_lost()).
const RETARGET_RANGE: float = 10.0
## Segundos entre búsquedas de nuevo blanco, para no recorrer la horda cada frame.
const RETARGET_INTERVAL: float = 0.1
## Distancia, en metros, al punto de puntería del blanco a la que una bala
## asistida cuenta el impacto (ver _assist_hit()).
const ASSIST_HIT_RADIUS: float = 0.9

## Puntería asistida: la activa el arma (la Pistola de dardos). La bala comprueba
## ella misma, en cada paso, si alcanzó a su blanco (no depende de que el Area3D
## avise: un enemigo ya pegado al área no vuelve a disparar la señal, y a mucha
## velocidad el área puede saltárselo) y busca otro si el suyo muere.
var assisted: bool = false

## Rebotes que le quedan al vuelo. Lo fija el arma al disparar (después del reinicio del pool, como la perforación del arco);
## pool_reset() lo vuelve a 0.
var bounces_left: int = 0
## Rebotes ya dados en este vuelo. Con esto el límite se calcula contra la
## propiedad `bounces` del arma al impactar (ver _bounces_available), sin
## depender de que bounces_left sobreviva al pool.
var _bounces_done: int = 0
## True cuando la bala ya se entregó al pool (evita liberarla dos veces).
var _finished: bool = false
## Segundos de vida del vuelo actual; red de seguridad contra balas atascadas.
var _age: float = 0.0

@onready var _tracer: MeshInstance3D = $Tracer

var _source: WeaponBase = null
var _max_distance: float = 20.0
var _travelled: float = 0.0
var _target: Node3D = null
## IDs de instancia ya dañados: un cuerpo que vuelve a entrar (o se queda
## pegado) al área de un disparo perforante nunca recibe dos golpes de la
## misma bala.
var _hit_ids: Dictionary[int, bool] = {}
## Perforación de la escena, restaurada al reusar (el arco la cambia por
## disparo DESPUÉS del reinicio del pool).
var _default_pierce: int = 1
## Velocidad de la escena, restaurada al reusar (un arma puede pisarla por
## disparo, como la Pistola de dardos con projectile_speed).
var _default_speed: float = 26.0
## Giro de persecución de la escena, restaurado al reusar.
var _default_turn_speed: float = 3.5
var _retarget_left: float = 0.0
## Segundos que quedan del estirón. Estado plano en vez de un Tween:
## pool_reset() corre una vez por disparo, y un tween ahí sería un objeto por
## bala más un tween pausado registrado por cada bala guardada.
var _stretch_left: float = 0.0
## Callback opcional por disparo, callback(cuerpo), que corre en cada golpe
## DESPUÉS del daño (las arañas de objetos ponen aquí su veneno). Se limpia al
## reiniciar el pool.
var extra_on_hit: Callable = Callable()
var _tint_material: StandardMaterial3D = null


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_default_pierce = pierce_remaining
	_default_speed = speed
	_default_turn_speed = homing_turn_speed


## Contrato del pool: estado de vuelo nuevo y el estirón del trazador otra vez.
func pool_reset() -> void:
	_source = null
	_target = null
	_max_distance = 20.0
	_travelled = 0.0
	_hit_ids.clear()
	pierce_remaining = _default_pierce
	speed = _default_speed
	homing_turn_speed = _default_turn_speed
	bounces_left = 0
	_bounces_done = 0
	_finished = false
	_age = 0.0
	assisted = false
	_retarget_left = 0.0
	extra_on_hit = Callable()
	if _tint_material != null:
		_tracer.material_override = null
	# También la orientación: launch() nunca la escribe, y las arañas de
	# ItemBag saltan su look_at cuando el cadáver y el blanco están en el
	# mismo punto; sin esto saldrían con el rumbo del dardo anterior.
	transform = Transform3D.IDENTITY
	_tracer.scale = Vector3(1.0, 1.0, spawn_stretch)
	_stretch_left = TRACER_RELAX_TIME


## Lo llama el arma justo después de crear y orientar la bala. El daño se
## resuelve al impactar por el embudo deal_damage del arma, así las stats
## globales (crítico, robo de vida) aplican.
func launch(source: WeaponBase, max_distance: float, target: Node3D) -> void:
	_source = source
	_max_distance = max_distance
	_target = target


## Recolorea el trazador solo para este vuelo (arañas); el reinicio lo restaura.
func tint(color: Color) -> void:
	if _tint_material == null:
		_tint_material = StandardMaterial3D.new()
		_tint_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tint_material.albedo_color = color
	_tracer.material_override = _tint_material


func _physics_process(delta: float) -> void:
	# Bala gastada: la liberación del pool es diferida, así que puede llegar
	# otro paso de física antes de que se guarde.
	if pierce_remaining <= 0:
		# Gastada pero sin liberar: se entrega ya en vez de quedarse congelada.
		if not _finished:
			_finish()
		return
	_age += delta
	if _age >= MAX_LIFETIME:
		_finish()
		return
	_relax_tracer(delta)
	if assisted:
		_retarget_if_lost(delta)
	if _homing_active():
		_steer_toward_target(delta)
	var from := global_position
	var step := speed * delta
	global_position += -global_transform.basis.z * step
	_travelled += step
	if assisted:
		_assist_hit(from, global_position)
		if pierce_remaining <= 0:
			return
	if _travelled >= _max_distance:
		# También se gasta la perforación: la liberación de abajo es diferida,
		# así que el Area3D sigue vivo este paso de física y dañaría a un
		# enemigo encontrado más allá de su alcance.
		_finish()


## Devuelve el estirón a 1 sin Tween (ver _stretch_left).
func _relax_tracer(delta: float) -> void:
	if _stretch_left <= 0.0:
		return
	_stretch_left = maxf(_stretch_left - delta, 0.0)
	var progress := 1.0 - _stretch_left / TRACER_RELAX_TIME
	_tracer.scale = Vector3(1.0, 1.0, lerpf(spawn_stretch, 1.0, progress))


func _steer_toward_target(delta: float) -> void:
	var to_target := WeaponBase.body_aim_point(_target) - global_position
	if to_target.length_squared() < WeaponBase.DEGENERATE_LENGTH_SQ:
		return
	var forward := -global_transform.basis.z
	var desired := to_target.normalized()
	var angle := forward.angle_to(desired)
	if angle < 0.001:
		return
	var axis := forward.cross(desired)
	# Direcciones paralelas u opuestas no tienen eje de giro: vuela recto.
	if axis.length_squared() < 0.000001:
		return
	var new_forward := forward.rotated(axis.normalized(), minf(angle, homing_turn_speed * delta))
	# Un vuelo casi vertical (persiguiendo desde una cornisa) es colineal con
	# UP; un "arriba" lateral mantiene la base construible.
	look_at(global_position + new_forward, WeaponBase.safe_up(new_forward))


func _homing_active() -> bool:
	# Un enemigo que muere sale del grupo "enemies": la bala deja de perseguir
	# el cadáver y termina su alcance en línea recta.
	return homing_enabled and homing_turn_speed > 0.0 and _target != null \
			and is_instance_valid(_target) and _target.is_inside_tree() \
			and _target.is_in_group("enemies")


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("enemies"):
		return
	_hit(body)


## Un golpe de esta bala contra `body`: lo comparten el aviso del Area3D y la
## comprobación asistida.
func _hit(body: Node3D) -> void:
	# Perforación gastada: Pools.release() solo difiere el cambio de padre,
	# así que el Area3D sigue reportando cuerpos el resto del paso de física.
	# Sin esta guarda una flecha de perforación 3 dañaría a todos los que
	# encuentre en ese paso.
	if pierce_remaining <= 0:
		return
	var body_id := body.get_instance_id()
	if _hit_ids.has(body_id):
		return
	_hit_ids[body_id] = true
	var health := Health.find_in(body)
	# Un dardo cuya arma se liberó en pleno vuelo se apaga sin daño.
	if health != null and _source != null and is_instance_valid(_source):
		# Un callback por disparo marca un proyectil creado por un objeto (las
		# arañas de ItemBag): sus muertes no crean otra generación.
		_source.deal_damage(health, not extra_on_hit.is_valid())
	if extra_on_hit.is_valid():
		extra_on_hit.call(body)
	pierce_remaining -= 1
	if pierce_remaining <= 0:
		# Perforación gastada: con rebotes pendientes la bala sale DIRECTO hacia
		# otro enemigo, aunque el primero siga vivo.
		if _bounces_available() > 0 and _bounce_to_next():
			return
		_finish()


## Puntería asistida: si el blanco quedó a ASSIST_HIT_RADIUS o menos del tramo
## recorrido este paso, cuenta el impacto sin esperar al Area3D.
func _assist_hit(from: Vector3, to: Vector3) -> void:
	if not _has_live_target():
		return
	var point := WeaponBase.body_aim_point(_target)
	var closest := Geometry3D.get_closest_point_to_segment(point, from, to)
	if closest.distance_squared_to(point) <= ASSIST_HIT_RADIUS * ASSIST_HIT_RADIUS:
		_hit(_target)


## Si el blanco murió (o nunca hubo), busca el enemigo más cercano que aún no
## golpeó, a lo sumo cada RETARGET_INTERVAL segundos.
func _retarget_if_lost(delta: float) -> void:
	if _has_live_target():
		return
	_retarget_left -= delta
	if _retarget_left > 0.0:
		return
	_retarget_left = RETARGET_INTERVAL
	_target = _nearest_unhit(RETARGET_RANGE)


func _has_live_target() -> bool:
	return _target != null and is_instance_valid(_target) and _target.is_inside_tree() \
			and _target.is_in_group("enemies")


## El enemigo más cercano a `max_range` metros o menos que esta bala aún no golpeó.
func _nearest_unhit(max_range: float) -> Node3D:
	var best: Node3D = null
	var best_dist_sq := max_range * max_range
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as Node3D
		if enemy == null or not enemy.is_inside_tree():
			continue
		if _hit_ids.has(enemy.get_instance_id()):
			continue
		var dist_sq := global_position.distance_squared_to(enemy.global_position)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best = enemy
	return best


## Salta al enemigo más cercano (a BOUNCE_RANGE o menos) que esta bala aún no
## golpeó: gasta un rebote, rearma la perforación, gira hacia él y le da un
## tramo nuevo de vuelo. Devuelve false si no hay a quién saltar. El impacto
## contra el nuevo blanco lo cuenta _assist_hit(), así funciona aunque ya
## esté pegado a la bala.
func _bounce_to_next() -> bool:
	var best := _nearest_unhit(BOUNCE_RANGE)
	if best == null:
		return false
	bounces_left = maxi(bounces_left - 1, 0)
	_bounces_done += 1
	pierce_remaining = _default_pierce
	_target = best
	_travelled = 0.0
	_max_distance = BOUNCE_RANGE * BOUNCE_LEG_FACTOR
	# Directo: gira de golpe hacia el nuevo blanco y lo persigue con giro alto,
	# sin curvas lentas.
	homing_turn_speed = maxf(homing_turn_speed, BOUNCE_TURN_SPEED)
	var to_next := WeaponBase.body_aim_point(best) - global_position
	if to_next.length_squared() > WeaponBase.DEGENERATE_LENGTH_SQ:
		var direction := to_next.normalized()
		look_at(global_position + direction, WeaponBase.safe_up(direction))
	return true


## Rebotes que aún puede dar esta bala. Si el arma tiene la propiedad `bounces`
## (la Pistola de dardos), manda ella: lo que dice el arma AHORA menos los
## rebotes ya dados. Si no, vale bounces_left, como antes. Los dardos de
## objetos (extra_on_hit) nunca rebotan.
func _bounces_available() -> int:
	if extra_on_hit.is_valid():
		return 0
	if _source != null and is_instance_valid(_source):
		var from_weapon: Variant = _source.get(&"bounces")
		if from_weapon != null:
			return maxi(int(from_weapon) - _bounces_done, 0)
	return bounces_left


## Entrega la bala al pool UNA sola vez y la deja sin perforación, así ningún
## paso de física posterior la mueve ni la hace dañar.
func _finish() -> void:
	if _finished:
		return
	_finished = true
	pierce_remaining = 0
	Pools.release(self)
