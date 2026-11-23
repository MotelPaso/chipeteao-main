extends WeaponBase
## Rastro de baba: el portador deja una fila de charcos cáusticos al moverse.
## Como el Aura, un enemigo recibe el golpe en cuanto su cuerpo toca un
## charco y otra vez cada tick_interval mientras siga encima (uno por enemigo,
## aunque pise varios charcos), y va frenado todo el rato que está encima. No
## necesita blanco: el arma "dispara" a su ritmo siempre que el portador se movió.
## Cómo usa los ajustes de WeaponBase:
##   damage        — daño de cada golpe (por deal_damage)
##   cooldown      — segundos entre charcos mientras se mueve
##   attack_range  — sin uso (Largo alcance igual ensancha los charcos por el área)
## Los charcos son registros SlimePuddle que avanza esta arma (sin escena de
## pool): el visual es un disco plano por charco (puddle_mesh) que se
## desvanece al expirar.
## La evolución «Marea ácida» multiplica damage, puddle_radius y puddle_life.

@export_group("Charco")
## Radio del charco, en metros (los tomos de área lo escalan); la evolución «Marea ácida» lo multiplica.
@export var puddle_radius: float = 1.4
## Segundos que dura un charco; la carta «Baba más espesa», la evolución y el Tomo de Persistencia lo alargan.
@export var puddle_life: float = 3.0
## Segundos entre dos golpes al MISMO enemigo mientras sigue en la baba.
@export var tick_interval: float = 0.5
## Segundos que le dura el frenazo de la baba (hit_slow) al salir de ella; encima, va frenado siempre.
@export var slow_linger: float = 0.2
## Distancia mínima, en metros, que el portador debe moverse desde el último charco.
@export var min_drop_distance: float = 0.8
## Altura máxima, en metros, por encima o por debajo del charco a la que alcanza.
@export var height_window: float = 1.6
## Capas de colisión que cuentan como suelo para el rayo que baja el charco al piso. Ajústalo a la capa de tu terreno (no incluyas enemigos ni al jugador).
@export_flags_3d_physics var ground_collision_mask: int = 1
## Hasta cuántos metros por debajo de los pies busca el suelo; si no hay nada, el charco cae en los pies.
@export var ground_probe_depth: float = 50.0

@export_group("Visual")
## Malla y material del charco (color y opacidad en albedo_color); disco de radio 1 que se escala al radio del charco.
@export var puddle_mesh: Mesh
## Cuánto sobre los pies del portador se dibuja el disco, en metros: lo justo para despegarlo del piso.
@export var puddle_ground_offset: float = 0.05
## Segundos que tarda un charco en desvanecerse al terminar su vida.
@export var fade_time: float = 0.3
## Segundos que tarda la animación de caída en llegar al radio completo.
@export var grow_time: float = 0.2
## Fracción del radio (0-1) con que nace un charco antes de crecer.
@export var grow_from: float = 0.3

@export_group("Multitud")
## Distancia, en radios de charco, de cada charco extra del Tomo de Multitud al de los pies; apenas más de 1 para que se toquen sin apilarse.
@export var extra_puddle_spacing: float = 1.2


## Un charco vivo. Un registro en vez de un Dictionary suelto: el `visual` es
## un nodo que cruza frames, y con campos tipados el compilador atrapa una
## clave mal escrita.
class SlimePuddle extends RefCounted:
	var center: Vector3 = Vector3.ZERO
	var radius: float = 0.0
	var life_left: float = 0.0
	var visual: MeshInstance3D = null


var _puddles: Array[SlimePuddle] = []
var _last_drop: Vector3 = Vector3.INF
var _drop_timer: float = 0.0
## id de instancia del enemigo -> segundos hasta que puede volver a recibir golpe.
var _rehit: Dictionary[int, float] = {}


func _ready() -> void:
	# Los VISUALES de los charcos son de la etapa (RunRoot.stage_parent) y
	# estos registros viajan con el raider: un cambio de etapa los suelta, o
	# _tick_puddles seguiría pulsando en las coordenadas de la arena anterior
	# sin nada en pantalla que explique el daño.
	RunState.stage_changed.connect(
			func(_index: int, _map_id: String) -> void: clear_weapon_fields())


func _physics_process(delta: float) -> void:
	_drop_timer = maxf(_drop_timer - delta, 0.0)
	var carrier := carrier_node()
	if carrier != null and _drop_timer <= 0.0:
		var feet := _ground_point(carrier)
		if _last_drop == Vector3.INF or feet.distance_to(_last_drop) >= min_drop_distance:
			_drop_timer = effective_cooldown()
			_last_drop = feet
			_drop_cluster(feet, maxi(effective_projectile_count(), 1))
	_tick_puddles(delta)
	_touch_enemies(delta)

## El punto del suelo justo bajo el portador. Un rayo hacia abajo desde sus
## pies: si salta, el charco se queda en el piso y no flota en el aire. Si el
## rayo no encuentra nada, usa la posición del portador como antes.
func _ground_point(carrier: Node3D) -> Vector3:
	var from := carrier.global_position + Vector3.UP * 0.2
	var to := from + Vector3.DOWN * ground_probe_depth
	var query := PhysicsRayQueryParameters3D.create(from, to, ground_collision_mask)
	if carrier is CollisionObject3D:
		query.exclude = [(carrier as CollisionObject3D).get_rid()]
	var hit := carrier.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return carrier.global_position
	return hit.position

## Los visuales de los charcos cuelgan de la arena, no de esta arma, así que
## nada los libera cuando el arma se va: se sueltan a mano. Se liberan al
## instante y sin desvanecer: el tween se crearía sobre un nodo que puede estar
## saliendo del árbol con nosotros.
func _exit_tree() -> void:
	clear_weapon_fields()


## La mitad opcional del contrato de caída del Player (PlayerRevive
## la llama por nombre), y el gancho de etapa: los VISUALES son de la arena y
## los registros viajan con el raider, así que sin esto _tick_puddles seguiría
## pulsando en las coordenadas de la arena anterior.
func clear_weapon_fields() -> void:
	for puddle: SlimePuddle in _puddles:
		if puddle.visual != null and is_instance_valid(puddle.visual):
			puddle.visual.queue_free()
		puddle.visual = null
	_puddles.clear()


## Una caída: el charco bajo los pies del portador y, con el Tomo de
## Multitud, `count - 1` más repartidos en anillo a extra_puddle_spacing
## radios, así el rastro se ensancha en vez de engrosarse.
func _drop_cluster(center: Vector3, count: int) -> void:
	_spawn_puddle(center)
	var extras := count - 1
	if extras <= 0:
		return
	var offset := puddle_radius * area_scale() * extra_puddle_spacing
	for i: int in extras:
		var angle := TAU * float(i) / float(extras)
		_spawn_puddle(center + Vector3(cos(angle), 0.0, sin(angle)) * offset)


func _spawn_puddle(center: Vector3) -> void:
	var radius := puddle_radius * area_scale()
	var visual := spawn_fx_mesh(puddle_mesh)
	visual.global_position = center + Vector3.UP * puddle_ground_offset
	# Sigue la pendiente: en una ladera el charco no queda medio enterrado.
	GroundAlign.align_to_ground(visual, radius)
	visual.scale = Vector3(radius * grow_from, 1.0, radius * grow_from)
	var grow := visual.create_tween()
	grow.tween_property(visual, "scale", Vector3(radius, 1.0, radius), grow_time) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var puddle := SlimePuddle.new()
	puddle.center = center
	puddle.radius = radius
	puddle.life_left = puddle_life * duration_scale()
	puddle.visual = visual
	_puddles.append(puddle)


func _tick_puddles(delta: float) -> void:
	for i in range(_puddles.size() - 1, -1, -1):
		var puddle := _puddles[i]
		puddle.life_left -= delta
		if puddle.life_left <= 0.0:
			_expire(puddle)
			_puddles.remove_at(i)


## Cada enemigo que toca algún charco va frenado (hit_slow, con slow_linger al
## salir) y, si su espera terminó, recibe el golpe al instante.
func _touch_enemies(delta: float) -> void:
	for id: int in _rehit.keys():
		_rehit[id] -= delta
		if _rehit[id] <= 0.0:
			_rehit.erase(id)
	if _puddles.is_empty():
		return
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as EnemyBase
		if enemy == null or not enemy.is_inside_tree() or not _on_slime(enemy):
			continue
		enemy.apply_slow(hit_slow, slow_linger)
		var id := enemy.get_instance_id()
		if _rehit.has(id):
			continue
		var health := Health.find_in(enemy)
		if health == null or health.is_dead:
			continue
		deal_damage(health)
		_rehit[id] = tick_interval


## Verdadero si el cuerpo de `enemy` toca algún charco vivo (mismo criterio
## que WeaponBase.enemies_in_disc: el cuerpo entero, con ventana de altura).
func _on_slime(enemy: EnemyBase) -> bool:
	var at := enemy.global_position
	var body_radius := enemy.hit_radius()
	for puddle: SlimePuddle in _puddles:
		var to_body := at - puddle.center
		if absf(to_body.y) > height_window:
			continue
		to_body.y = 0.0
		var reach := puddle.radius + body_radius
		if to_body.length_squared() <= reach * reach:
			return true
	return false


func _expire(puddle: SlimePuddle) -> void:
	var visual := puddle.visual
	puddle.visual = null
	if visual == null or not is_instance_valid(visual):
		return
	# Se anima la transparencia del nodo, no el material compartido de la escena.
	var fade := visual.create_tween()
	fade.tween_property(visual, "transparency", 1.0, fade_time)
	fade.tween_callback(visual.queue_free)


## Nunca busca blanco: el rastro cae donde camine el portador.
func acquire_target() -> Node3D:
	return null
