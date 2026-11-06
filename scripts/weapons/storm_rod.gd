extends WeaponBase
## Pararrayos: electrocuta al enemigo más cercano y el rayo salta a los
## enemigos aún no golpeados más próximos, en cadena. Cada eslabón pasa por
## deal_damage (crítico y robo de vida por eslabón). El visual es un rayo
## emisivo por eslabón que se libera solo: no hay proyectil, el golpe es
## instantáneo.
##   damage       — daño por eslabón
##   cooldown     — tiempo entre lanzamientos
##   attack_range — alcance para elegir el primer blanco
##   chain_count  — eslabones extra tras el primer golpe

@export var chain_count: int = 2
## Un eslabón salta como máximo a esta distancia del anterior, en metros.
@export var chain_range: float = 6.5
## Radio de un segmento del rayo; el largo va en la escala Y del nodo, así una
## sola malla sirve para todos los eslabones.
@export var beam_radius: float = 0.05
## Segundos que tarda un segmento en adelgazarse y desaparecer.
@export var beam_fade_time: float = 0.22
## Fracción de su radio a la que se encoge un segmento al desvanecerse.
@export var beam_fade_scale: float = 0.3
## Por debajo de este largo un eslabón no se dibuja (dos cuerpos en el mismo punto).
@export var min_beam_length: float = 0.05

const BEAM_COLOR := Color(0.55, 0.75, 1.0)
## Lados del cilindro del rayo: es una raya fina que se ve un quinto de
## segundo, seis alcanzan.
const BEAM_SEGMENTS: int = 6

## Segundos entre los rayos que agrega el Tomo de Multitud. Escalonados y no
## simultáneos: dos lanzamientos en el mismo frame saltarían por los mismos
## cuerpos y dibujarían las dos cadenas una encima de la otra.
const EXTRA_BOLT_STAGGER: float = 0.1
## La cadena escalonada entera termina dentro de esta fracción de un
## enfriamiento, o el último rayo de una ráfaga caería después del siguiente.
const BOLT_CHAIN_WINDOW: float = 0.6

## Una malla y un material para todos los rayos: construir un cilindro y un
## material por eslabón es el gasto por efecto que Pools existe para evitar.
var _beam_mesh: CylinderMesh = null


func _ready() -> void:
	_beam_mesh = CylinderMesh.new()
	_beam_mesh.top_radius = beam_radius
	_beam_mesh.bottom_radius = beam_radius
	# Altura unitaria: _spawn_beam guarda el largo real en scale.y.
	_beam_mesh.height = 1.0
	_beam_mesh.radial_segments = BEAM_SEGMENTS
	# Una raya recta: los anillos de altura solo suman vértices colineales.
	_beam_mesh.rings = 1
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = BEAM_COLOR
	material.emission_enabled = true
	material.emission = BEAM_COLOR
	material.emission_energy_multiplier = 2.4
	_beam_mesh.material = material


func fire(target: Node3D) -> void:
	var count := maxi(effective_projectile_count(), 1)
	var step := minf(EXTRA_BOLT_STAGGER,
			effective_cooldown() * BOLT_CHAIN_WINDOW / float(maxi(count - 1, 1)))
	_zap(target)
	for i: int in range(1, count):
		# Temporizador pausable y en paso de física: un rayo extra no sale con
		# la pantalla de mejoras abierta, y el daño cae en el mismo tick que el
		# resto del combate.
		get_tree().create_timer(step * float(i), false, true).timeout \
				.connect(_refork)


## Un rayo extra del Tomo de Multitud. Elige su PROPIO primer blanco en vez
## de reusar el de la ráfaga: la cadena inicial pudo haberlo matado, y así el
## rayo extra salta por otra parte de la horda. Llega un poco después de
## fire(), cuando el arma puede haber salido del árbol con un raider quitado.
func _refork() -> void:
	if not is_inside_tree():
		return
	var target := acquire_target()
	if target != null:
		_zap(target)


## Un rayo: el primer golpe más sus chain_count saltos.
func _zap(target: Node3D) -> void:
	var previous_point := global_position + Vector3.UP * 1.1
	var current := target
	var hit_ids: Dictionary[int, bool] = {}
	var links := 1 + chain_count
	var fork_range := chain_range * area_scale()
	for link in links:
		if current == null:
			return
		hit_ids[current.get_instance_id()] = true
		var strike_point := current.global_position + Vector3.UP * 0.8
		_spawn_beam(previous_point, strike_point)
		var health := Health.find_in(current)
		if health != null and not health.is_dead:
			deal_damage(health)
		previous_point = strike_point
		current = _next_link(current, hit_ids, fork_range)


## Enemigo vivo más cercano a `from` dentro de `fork_range` que aún no recibió el rayo.
func _next_link(from: Node3D, hit_ids: Dictionary[int, bool],
		fork_range: float) -> Node3D:
	var nearest: Node3D = null
	var nearest_dist_sq := fork_range * fork_range
	# Se lee una vez: el bucle solo lee, así que `from` no se mueve mientras corre.
	var from_position := from.global_position
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var body := enemy as Node3D
		if body == null or not body.is_inside_tree():
			continue
		if hit_ids.has(body.get_instance_id()):
			continue
		var dist_sq := from_position.distance_squared_to(body.global_position)
		if dist_sq <= nearest_dist_sq:
			nearest_dist_sq = dist_sq
			nearest = body
	return nearest


## Un segmento emisivo entre dos puntos que destella y se desvanece solo. El
## largo va en scale.y para que todos compartan la malla unitaria de _ready;
## el desvanecido usa la transparencia del nodo porque el material es
## compartido y animar su alfa apagaría todos los rayos vivos.
func _spawn_beam(from: Vector3, to: Vector3) -> void:
	var span := to - from
	var length := span.length()
	if length < min_beam_length:
		return
	var beam := spawn_fx_mesh(_beam_mesh)
	beam.global_position = (from + to) * 0.5
	# El eje del cilindro es Y: se apunta -Z al punto lejano y luego se dobla Y
	# sobre él (con la guarda de "arriba" degenerado).
	var direction := span / length
	beam.look_at(to, safe_up(direction))
	beam.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	beam.scale = Vector3(1.0, length, 1.0)
	beam.transparency = 0.0
	var tween := beam.create_tween()
	tween.tween_property(beam, "transparency", 1.0, beam_fade_time)
	tween.parallel().tween_property(beam, "scale",
			Vector3(beam_fade_scale, length, beam_fade_scale), beam_fade_time)
	tween.tween_callback(beam.queue_free)
