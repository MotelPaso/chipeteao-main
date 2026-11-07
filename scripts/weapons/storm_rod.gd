extends WeaponBase
## Pararrayos: electrocuta al enemigo más cercano y el rayo salta a los
## enemigos aún no golpeados más próximos, en cadena. Cada eslabón pasa por
## deal_damage (crítico y robo de vida por eslabón). El visual es un
## LightningBeam por eslabón que se libera solo: no hay proyectil, el golpe es
## instantáneo.
##   damage       — daño por eslabón
##   cooldown     — tiempo entre lanzamientos
##   attack_range — alcance para elegir el primer blanco
##   chain_count  — eslabones extra tras el primer golpe

## Escena del segmento de rayo; su aspecto se edita ahí.
const LIGHTNING_BEAM_SCENE: PackedScene = preload("res://scenes/fx/LightningBeam.tscn")

@export_group("Cadena")
## Saltos extra tras el primer golpe; la carta «Cielo bifurcado» suma 1 y la evolución Corona de tempestad suma 3.
@export var chain_count: int = 2
## Un eslabón salta como máximo a esta distancia del anterior, en metros.
@export var chain_range: float = 6.5
## Por debajo de este largo, en metros, un eslabón no se dibuja (dos cuerpos en el mismo punto).
@export var min_beam_length: float = 0.05

@export_group("Multitud")
## Segundos entre los rayos extra del Tomo de Multitud; dos en el mismo frame saltarían por los mismos cuerpos.
@export var extra_stagger: float = 0.1


func fire(target: Node3D) -> void:
	fire_volley_retarget(maxi(effective_projectile_count(), 1), _zap.bind(target),
			_refork, extra_stagger)


## Un rayo extra del Tomo de Multitud. Elige su PROPIO primer blanco en vez
## de reusar el de la ráfaga: la cadena inicial pudo haberlo matado, y así el
## rayo extra salta por otra parte de la horda.
func _refork() -> void:
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
		var strike_point := body_aim_point(current)
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


## Un segmento de rayo entre dos puntos; su aspecto está en
## scenes/fx/LightningBeam.tscn, grupo «Pararrayos».
func _spawn_beam(from: Vector3, to: Vector3) -> void:
	if (to - from).length() < min_beam_length:
		return
	var beam := spawn_fx_scene(LIGHTNING_BEAM_SCENE) as LightningBeam
	beam.play(from, to, LightningBeam.Style.STORM_ROD)
