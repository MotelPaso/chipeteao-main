extends WeaponBase
## Rastro de baba: el portador deja una fila de charcos cáusticos al moverse;
## cada enemigo parado en un charco recibe un golpe cada tick_interval. No
## necesita blanco: el arma "dispara" a su ritmo siempre que el portador se movió.
## Cómo usa los ajustes de WeaponBase:
##   damage        — daño por pulso (por deal_damage)
##   cooldown      — segundos entre charcos mientras se mueve
##   attack_range  — sin uso (Largo alcance igual ensancha los charcos por el área)
## Los charcos son registros SlimePuddle que avanza esta arma (sin escena de
## pool): el visual es un disco emisivo plano por charco que se desvanece al expirar.

@export var puddle_radius: float = 1.4
## Segundos que dura un charco (Tomo de Persistencia y "Baba más espesa" lo alargan).
@export var puddle_life: float = 3.0
@export var tick_interval: float = 0.5
## Distancia mínima, en metros, que el portador debe moverse desde el último charco.
@export var min_drop_distance: float = 0.8
@export var slime_color: Color = Color(0.45, 0.95, 0.3)
## Altura máxima, en metros, por encima o por debajo del charco a la que alcanza.
@export var height_window: float = 1.6
## Cuánto sobre los pies del portador se dibuja el disco: lo justo para despegarlo de la cara superior del piso.
@export var puddle_ground_offset: float = 0.05

## Segundos que tarda un charco en desvanecerse al terminar su vida.
const FADE_TIME: float = 0.3
## Segundos que tarda la animación de caída en llegar al radio completo.
const GROW_TIME: float = 0.2
## Fracción del radio con que nace un charco antes de crecer.
const GROW_FROM: float = 0.3
## Distancia del punto de caída a cada charco que agrega el Tomo de Multitud,
## en radios de charco. Apenas más de 1.0: los extras rodean y tocan el
## charco principal y ensanchan el rastro, en vez de apilarse invisibles en un
## punto y golpear varias veces a los mismos enemigos.
const EXTRA_PUDDLE_SPACING: float = 1.2


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
var _puddle_mesh: CylinderMesh = null


func _ready() -> void:
	# Los VISUALES de los charcos son de la etapa (RunRoot.stage_parent) y
	# estos registros viajan con el raider: un cambio de etapa los suelta, o
	# _tick_puddles seguiría pulsando en las coordenadas de la arena anterior
	# sin nada en pantalla que explique el daño.
	RunState.stage_changed.connect(
			func(_index: int, _map_id: String) -> void: clear_weapon_fields())
	_puddle_mesh = CylinderMesh.new()
	_puddle_mesh.top_radius = 1.0
	_puddle_mesh.bottom_radius = 1.0
	_puddle_mesh.height = 0.06
	# Teselado explícito: una losa de 6 cm no necesita anillos de altura, y los
	# 64 lados del motor serían el grueso de los triángulos de cada charco.
	_puddle_mesh.radial_segments = 24
	_puddle_mesh.rings = 1
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(slime_color, 0.55)
	material.emission_enabled = true
	material.emission = slime_color
	material.emission_energy_multiplier = 0.8
	_puddle_mesh.material = material


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


## La mitad opcional del contrato de caída del Player (Player._clear_weapon_fields
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
## Multitud, `count - 1` más repartidos en anillo a EXTRA_PUDDLE_SPACING
## radios, así el rastro se ensancha en vez de engrosarse.
func _drop_cluster(center: Vector3, count: int) -> void:
	_spawn_puddle(center)
	var extras := count - 1
	if extras <= 0:
		return
	var offset := puddle_radius * area_scale() * EXTRA_PUDDLE_SPACING
	for i: int in extras:
		var angle := TAU * float(i) / float(extras)
		_spawn_puddle(center + Vector3(cos(angle), 0.0, sin(angle)) * offset)


func _spawn_puddle(center: Vector3) -> void:
	var radius := puddle_radius * area_scale()
	var visual := spawn_fx_mesh(_puddle_mesh)
	visual.global_position = center + Vector3.UP * puddle_ground_offset
	visual.scale = Vector3(radius * GROW_FROM, 1.0, radius * GROW_FROM)
	var grow := visual.create_tween()
	grow.tween_property(visual, "scale", Vector3(radius, 1.0, radius), GROW_TIME) \
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
	var fade := visual.create_tween()
	fade.tween_property(visual, "transparency", 1.0, FADE_TIME)
	fade.tween_callback(visual.queue_free)


## Nunca busca blanco: el rastro cae donde camine el portador.
func acquire_target() -> Node3D:
	return null
