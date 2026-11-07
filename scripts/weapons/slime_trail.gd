extends WeaponBase
## Rastro de baba: el portador deja una fila de charcos cáusticos al moverse;
## cada enemigo parado en un charco recibe un golpe cada tick_interval. No
## necesita blanco: el arma "dispara" a su ritmo siempre que el portador se movió.
## Cómo usa los ajustes de WeaponBase:
##   damage        — daño por pulso (por deal_damage)
##   cooldown      — segundos entre charcos mientras se mueve
##   attack_range  — sin uso (Largo alcance igual ensancha los charcos por el área)
## Los charcos son registros SlimePuddle que avanza esta arma (sin escena de
## pool): el visual es un disco emisivo plano por charco (puddle_mesh) que se
## desvanece al expirar.
## La evolución «Marea ácida» multiplica damage, puddle_radius y puddle_life.

@export_group("Charco")
## Radio del charco, en metros (los tomos de área lo escalan); la evolución «Marea ácida» lo multiplica.
@export var puddle_radius: float = 1.4
## Segundos que dura un charco; la carta «Baba más espesa», la evolución y el Tomo de Persistencia lo alargan.
@export var puddle_life: float = 3.0
## Segundos entre pulsos de daño de cada charco.
@export var tick_interval: float = 0.5
## Distancia mínima, en metros, que el portador debe moverse desde el último charco.
@export var min_drop_distance: float = 0.8
## Altura máxima, en metros, por encima o por debajo del charco a la que alcanza.
@export var height_window: float = 1.6

@export_group("Visual")
## Malla y material del charco (color, transparencia, brillo); disco de radio 1 que se escala al radio del charco.
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
	var tick_timer: float = 0.0
	var visual: MeshInstance3D = null


var _puddles: Array[SlimePuddle] = []
var _last_drop: Vector3 = Vector3.INF
var _drop_timer: float = 0.0


func _ready() -> void:
	# Los VISUALES de los charcos son de la etapa (RunRoot.stage_parent) y
	# estos registros viajan con el raider: un cambio de etapa los suelta, o
	# _tick_puddles seguiría pulsando en las coordenadas de la arena anterior
	# sin nada en pantalla que explique el daño.
	RunState.stage_changed.connect(
			func(_index: int, _map_id: String) -> void: clear_weapon_fields())


func _physics_process(delta: float) -> void:
	_drop_timer = maxf(_drop_timer - delta, 0.0)
	# El rastro sigue al montaje que lleva el arma: una mascota deja SU propio
	# rastro en vez de pintar uno bajo el jugador al que sigue.
	var carrier := carrier_node()
	if carrier != null and _drop_timer <= 0.0:
		var feet := carrier.global_position
		if _last_drop == Vector3.INF or feet.distance_to(_last_drop) >= min_drop_distance:
			_drop_timer = effective_cooldown()
			_last_drop = feet
			# Esta arma nunca llama a fire(), así que el Tomo de Multitud se lee
			# aquí: la caída del charco es el ataque.
			_drop_cluster(feet, maxi(effective_projectile_count(), 1))
	_tick_puddles(delta)


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
	visual.scale = Vector3(radius * grow_from, 1.0, radius * grow_from)
	var grow := visual.create_tween()
	grow.tween_property(visual, "scale", Vector3(radius, 1.0, radius), grow_time) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var puddle := SlimePuddle.new()
	puddle.center = center
	puddle.radius = radius
	puddle.life_left = puddle_life * duration_scale()
	puddle.tick_timer = tick_interval * 0.5
	puddle.visual = visual
	_puddles.append(puddle)


func _tick_puddles(delta: float) -> void:
	for i in range(_puddles.size() - 1, -1, -1):
		var puddle := _puddles[i]
		puddle.life_left -= delta
		puddle.tick_timer -= delta
		if puddle.tick_timer <= 0.0:
			puddle.tick_timer = tick_interval
			_pulse(puddle)
		if puddle.life_left <= 0.0:
			_expire(puddle)
			_puddles.remove_at(i)


func _pulse(puddle: SlimePuddle) -> void:
	damage_all(enemies_in_disc(puddle.center, puddle.radius, height_window))


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
