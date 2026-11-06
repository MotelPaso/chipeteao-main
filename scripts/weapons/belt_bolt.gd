class_name BeltBolt
extends WeaponBase
## Brazo de daño del Cinturón eléctrico. Es un WeaponBase solo para usar
## deal_damage: crítico, robo de vida y los ganchos de objetos al golpear y al
## matar llegan gratis, y un objeto que tirara su propio daño sería la única
## fuente del juego donde no puede caer un crítico.
##
## Es hijo de la BOLSA DE OBJETOS, nunca del montaje "Weapons" del Player:
## todo lo que enumera armas (la tira del HUD, el tope de armas, el pool de
## mejoras) recorre ese montaje, y un rayo ahí aparecería como un arma que el
## raider nunca eligió y contaría contra el tope.
##
## Nunca dispara solo: fire() está vacío y el proceso de física apagado. La
## bolsa llama a zap_chain() cuando el raider derrapa; ese es todo el gatillo.

## Daño del primer golpe sin copias extra; cada copia extra suma el 35%.
@export var belt_damage: float = 25.0
@export var damage_per_extra_copy: float = 0.35
## Rebotes después del primer blanco: 2 + copias.
@export var base_bounces: int = 2
## Qué tan lejos del raider puede estar el primer blanco, y cuánto alcanza
## cada rebote desde el último cuerpo golpeado.
@export var first_range: float = 10.0
@export var bounce_range: float = 8.0

## Aspecto del rayo: mismo desvanecido que el del Pararrayos.
@export var beam_radius: float = 0.05
@export var beam_fade_time: float = 0.22
@export var beam_fade_scale: float = 3.0
const BEAM_COLOR := Color(1.0, 0.95, 0.45)
## Por debajo de este largo un rayo es un punto: no se dibuja.
const MIN_BEAM_LENGTH: float = 0.2
## Altura a la que se dibuja el rayo, para que se lea como un relámpago a la
## altura del pecho y no como una línea que raspa el suelo.
const BEAM_HEIGHT: float = 0.9

var _beam_mesh: CylinderMesh = null


func _ready() -> void:
	# Nunca con reloj propio: WeaponBase._physics_process buscaría blanco cada
	# enfriamiento y llamaría a fire(), y esta arma solo existe para el derrape.
	set_physics_process(false)
	_beam_mesh = CylinderMesh.new()
	_beam_mesh.top_radius = beam_radius
	_beam_mesh.bottom_radius = beam_radius
	_beam_mesh.height = 1.0
	_beam_mesh.radial_segments = 6
	_beam_mesh.rings = 0
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = BEAM_COLOR
	material.emission_enabled = true
	material.emission = BEAM_COLOR
	material.emission_energy_multiplier = 2.4
	_beam_mesh.material = material


## Contrato de WeaponBase. Vacío a propósito: ver el comentario de la clase.
func fire(_target: Node3D) -> void:
	pass


## EL gatillo: ItemBag lo llama en cada derrape. Devuelve cuántos cuerpos
## golpeó la cadena, para que la bolsa imprima una línea por derrape.
## `origin` llega como parámetro porque ItemBag extiende Node y NO tiene
## transformada: un Node3D hijo suyo está en el origen del mundo, y leer la
## posición propia apuntaría cada cadena desde el centro del mapa.
func zap_chain(origin: Vector3, copies: int) -> int:
	var hits := 0
	var struck: Array[Node3D] = []
	var from := origin
	var reach := first_range
	var remaining := base_bounces + copies + 1
	damage = belt_damage * (1.0 + damage_per_extra_copy * float(maxi(copies - 1, 0)))
	while remaining > 0:
		var target := _nearest_unstruck(from, reach, struck)
		if target == null:
			break
		struck.append(target)
		_spawn_beam(from, target.global_position)
		var health := Health.find_in(target)
		if health != null and not health.is_dead:
			# Por deal_damage, así el cinturón hace crítico, roba vida y
			# alimenta los ganchos de muerte como un arma real.
			deal_damage(health)
			hits += 1
		from = target.global_position
		reach = bounce_range
		remaining -= 1
	return hits


## Enemigo vivo más cercano a `from` dentro de `reach` que esta cadena aún no
## golpeó. Usa el grupo como todo barrido de blanco, así los cuerpos poseídos
## (que salen del grupo "enemies") nunca reciben el rayo del grupo.
func _nearest_unstruck(from: Vector3, reach: float, struck: Array[Node3D]) -> Node3D:
	var best: Node3D = null
	var best_distance := reach * reach
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var body := node as Node3D
		if body == null or not body.is_inside_tree() or struck.has(body):
			continue
		var distance := from.distance_squared_to(body.global_position)
		if distance <= best_distance:
			best_distance = distance
			best = body
	return best


## Un segmento de rayo que se desvanece y se libera. El eje del cilindro es Y:
## se apunta -Z al punto lejano y luego se dobla Y sobre él, con la guarda de
## "arriba" degenerado compartida.
func _spawn_beam(from: Vector3, to: Vector3) -> void:
	var start := from + Vector3.UP * BEAM_HEIGHT
	var end := to + Vector3.UP * BEAM_HEIGHT
	var span := end - start
	var length := span.length()
	if length < MIN_BEAM_LENGTH:
		return
	var beam := spawn_fx_mesh(_beam_mesh)
	beam.global_position = (start + end) * 0.5
	var direction := span / length
	beam.look_at(end, safe_up(direction))
	beam.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	beam.scale = Vector3(1.0, length, 1.0)
	beam.transparency = 0.0
	var tween := beam.create_tween()
	tween.tween_property(beam, "transparency", 1.0, beam_fade_time)
	tween.parallel().tween_property(beam, "scale",
			Vector3(beam_fade_scale, length, beam_fade_scale), beam_fade_time)
	tween.tween_callback(beam.queue_free)
