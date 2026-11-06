class_name AcidPool
extends Node3D
## Charco ácido del pool que deja la lluvia radiactiva: un disco verde que
## daña SOLO a los raiders y se desvanece solo.
##
## A diferencia de BloodPoolFx (solo visual: blood_vial.gd maneja su daño),
## este maneja su propio tick. No hay un arma detrás: el clima lo suelta y se
## olvida, y un charco que necesitara un ticker externo obligaría al director
## a llevar una lista que se filtraría al cambiar de etapa.
##
## Nunca daña enemigos: la lluvia es un peligro para el grupo, no control de
## masas gratis.

## Radio en que daña el charco y cuánto dura. Los dos los escribe quien llama
## por play(); estos son solo los respaldos.
@export var radius: float = 2.0
@export var lifetime: float = 6.0
@export var damage_per_second: float = 4.0
## Segundos entre aplicaciones de daño. No por frame: sesenta golpecitos por
## segundo enterrarían los números de daño y la barra de vida en ruido.
@export var tick_interval: float = 0.5

const FADE_TIME: float = 0.35
const DISC_COLOR := Color(0.45, 0.95, 0.3)
## El disco se construye con radio 1 y se escala, así una malla sirve para
## todos los tamaños de charco.
const BASE_RADIUS: float = 1.0

var _left: float = 0.0
var _tick_left: float = 0.0
var _disc: MeshInstance3D = null
var _material: StandardMaterial3D = null
var _fade: Tween = null
## True entre el inicio del desvanecido y la liberación al pool, así una
## segunda expiración no encola otra liberación para un nodo que quizá ya se
## volvió a adquirir.
var _expiring: bool = false


func _ready() -> void:
	# En grupo para que el director cuente los charcos vivos contra su tope y
	# separe los nuevos, sin guardar una lista que un cambio de etapa dejaría
	# con nodos liberados.
	add_to_group(&"acid_pools")
	_build_visual()
	set_physics_process(false)


## Contrato del pool: charco nuevo en cada adquisición.
func pool_reset() -> void:
	if not is_in_group(&"acid_pools"):
		add_to_group(&"acid_pools")
	_kill_fade()
	_expiring = false
	_left = 0.0
	_tick_left = 0.0
	scale = Vector3.ONE
	if _material != null:
		_material.albedo_color = Color(DISC_COLOR, 0.55)


func _build_visual() -> void:
	_disc = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = BASE_RADIUS
	mesh.bottom_radius = BASE_RADIUS
	mesh.height = 0.08
	# Teselado explícito: una losa de 8 cm no necesita anillos de altura, y 24
	# lados alcanzan para un disco de un par de metros.
	mesh.radial_segments = 24
	mesh.rings = 1
	_disc.mesh = mesh
	# Material por instancia: el desvanecido escribe el alfa, y un recurso
	# compartido desvanecería todos los charcos del mapa a la vez.
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = Color(DISC_COLOR, 0.55)
	_material.emission_enabled = true
	_material.emission = DISC_COLOR
	_material.emission_energy_multiplier = 1.2
	_disc.material_override = _material
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_disc)


## Forma el charco en `center`. `pool_radius`, `seconds` y `dps` vienen del
## clima (WorldDirector), así un solo bloque de exports ajusta todos los charcos.
func play(center: Vector3, pool_radius: float, seconds: float, dps: float) -> void:
	global_position = center
	radius = pool_radius
	lifetime = seconds
	damage_per_second = dps
	_left = seconds
	_tick_left = tick_interval
	_expiring = false
	scale = Vector3(pool_radius, 1.0, pool_radius)
	if _material != null:
		_material.albedo_color = Color(DISC_COLOR, 0.55)
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if _expiring:
		return
	_left -= delta
	if _left <= 0.0:
		_expire()
		return
	_tick_left -= delta
	if _tick_left > 0.0:
		return
	_tick_left = tick_interval
	_burn_raiders()


## Raiders dentro del charco, de pie o caídos: un cuerpo tirado en ácido
## sigue en ácido, y a un raider caído hay que sacarlo arrastrando.
func _burn_raiders() -> void:
	var amount := damage_per_second * tick_interval
	var radius_sq := radius * radius
	for group: String in ["player", "downed_players"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body == null or not body.is_inside_tree():
				continue
			var to_body := body.global_position - global_position
			to_body.y = 0.0
			if to_body.length_squared() > radius_sq:
				continue
			var health := Health.find_in(body)
			if health != null and not health.is_dead:
				# Sin atacante: el ácido no tiene a quién devolverle las espinas.
				health.take_damage(amount)


func _expire() -> void:
	if _expiring:
		return
	_expiring = true
	set_physics_process(false)
	_fade = create_tween()
	_fade.tween_property(_material, "albedo_color", Color(DISC_COLOR, 0.0), FADE_TIME)
	_fade.tween_callback(_release)


func _release() -> void:
	Pools.release(self)


func _kill_fade() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = null
