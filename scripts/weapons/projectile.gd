class_name Projectile
extends Area3D
## Bala de arma: vuela por -Z (curvándose un poco hacia el blanco al que se
## disparó) y daña los cuerpos del grupo "enemies" que toca, cada uno como
## máximo una vez, hasta agotar su perforación (1 = dardo clásico).
## El arma la saca de Pools (colgada de la arena, así sobrevive al movimiento
## del jugador); vuelve al pool al gastar la perforación o tras max_distance,
## y pool_reset() rearma perforación, registro de golpes y trazador.

## Velocidad de vuelo, en metros por segundo.
@export var speed: float = 26.0
## Si el vuelo se curva hacia el blanco (las flechas vuelan rectas).
@export var homing_enabled: bool = true
## Radianes por segundo que el vuelo puede girar hacia el blanco; 0 apaga la persecución.
@export var homing_turn_speed: float = 3.5
## Cuántos enemigos distintos puede dañar antes de desaparecer (el Arco de caza lo sube por disparo).
@export var pierce_remaining: int = 1
## El trazador nace estirado este factor a lo largo y vuelve a 1 (sensación de estela).
@export var spawn_stretch: float = 2.4

## Segundos que tarda el estirón inicial en volver a 1.
const TRACER_RELAX_TIME: float = 0.12

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


## Contrato del pool: estado de vuelo nuevo y el estirón del trazador otra vez.
func pool_reset() -> void:
	_source = null
	_target = null
	_max_distance = 20.0
	_travelled = 0.0
	_hit_ids.clear()
	pierce_remaining = _default_pierce
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
		_tint_material.emission_enabled = true
	_tint_material.albedo_color = color
	_tint_material.emission = color
	_tint_material.emission_energy_multiplier = 1.6
	_tracer.material_override = _tint_material


func _physics_process(delta: float) -> void:
	_relax_tracer(delta)
	if _homing_active():
		_steer_toward_target(delta)
	var step := speed * delta
	global_position += -global_transform.basis.z * step
	_travelled += step
	if _travelled >= _max_distance:
		# También se gasta la perforación: la liberación de abajo es diferida,
		# así que el Area3D sigue vivo este paso de física y dañaría a un
		# enemigo encontrado más allá de su alcance.
		pierce_remaining = 0
		Pools.release(self)


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
	# Perforación gastada: Pools.release() solo difiere el cambio de padre,
	# así que el Area3D sigue reportando cuerpos el resto del paso de física.
	# Sin esta guarda una flecha de perforación 3 dañaría a todos los que
	# encuentre en ese paso.
	if pierce_remaining <= 0:
		return
	if not body.is_in_group("enemies"):
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
		Pools.release(self)
