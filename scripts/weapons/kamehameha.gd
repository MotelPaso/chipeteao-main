extends WeaponBase
## Kamehameha: un rayo de energía de enfriamiento largo lanzado hacia el
## enemigo más cercano, que golpea fuerte a TODO enemigo dentro de un carril
## largo y ancho. Cómo usa los ajustes de WeaponBase:
##   damage        — daño por enemigo atrapado en el rayo (por deal_damage)
##   cooldown      — tiempo de carga entre rayos (largo a propósito)
##   attack_range  — alcance para elegir blanco; el rayo mide beam_length
## La evolución «Resplandor Final» multiplica damage, beam_width y cooldown.
## Visual: un cilindro brillante (beam_mesh, en Kamehameha.tscn) tendido a lo
## largo del carril que destella y se desvanece, más una sacudida y una pausa
## breve al soltarlo.

## El rayo usa el rugido de jefe mientras el catálogo de sonidos no tenga uno
## propio; bajado fuerte porque ese sonido está mezclado para una entrada por
## partida y esta arma dispara cada pocos segundos.
const BEAM_VOLUME_DB: float = -12.0

@export_group("Rayo")
## Largo del carril, en metros; la carta «Rayo más largo» lo sube.
@export var beam_length: float = 18.0
## Ancho total del carril, en metros; la evolución «Resplandor Final» lo multiplica.
@export var beam_width: float = 2.4
## Segundos que dura el destello del rayo.
@export var flash_time: float = 0.45
## Altura sobre el montaje desde la que sale el rayo, en metros.
@export var muzzle_height: float = 1.1
## Malla y material del rayo (color, transparencia, brillo); cilindro unitario que se estira al carril.
@export var beam_mesh: Mesh
## Grosor con que nace el rayo, como fracción de su ancho final.
@export var beam_start_width: float = 0.3
## Fracción de flash_time que tarda el rayo en llegar a su ancho final.
@export var beam_grow_fraction: float = 0.3

@export_group("Sensación")
## Fuerza de la sacudida de cámara por ráfaga.
@export var shake_strength: float = 0.2
## Segundos de la sacudida de cámara por ráfaga.
@export var shake_time: float = 0.35
## Escala de tiempo de la pausa breve cuando el rayo golpea a alguien (0-1).
@export var hit_stop_scale: float = 0.1
## Segundos de la pausa breve cuando el rayo golpea a alguien.
@export var hit_stop_time: float = 0.05

@export_group("Multitud")
## Segundos entre los rayos extra del Tomo de Multitud; dos solapados en el mismo carril serían un solo rayo más grueso.
@export var extra_stagger: float = 0.12
## Grados entre rayos vecinos; el carril es largo, así que un abanico estrecho ya separa varios metros las puntas.
@export var extra_fan_deg: float = 14.0


func fire(target: Node3D) -> void:
	var origin := global_position + Vector3.UP * muzzle_height
	var center_dir := flat_dir_or(body_aim_point(target) - origin,
			-global_transform.basis.z)
	fire_volley(maxi(effective_projectile_count(), 1), center_dir, _blast,
			extra_stagger, extra_fan_deg)
	# Un rugido y una sacudida por ráfaga, salgan los rayos que salgan; van
	# aquí, con el disparo, y no en el helper visual.
	Sfx.play(&"boss_roar_2", BEAM_VOLUME_DB)
	Juice.shake(shake_strength, shake_time)


## Un rayo por `direction`.
func _blast(direction: Vector3) -> void:
	var origin := global_position + Vector3.UP * muzzle_height
	var length := beam_length * area_scale()
	var half_width := beam_width * 0.5 * area_scale()
	var hits := 0
	# El carril se mide desde el cuerpo, no desde la boca: el rayo barre la
	# línea del suelo donde está parado el jugador.
	for body: Node3D in enemies_in_lane(global_position, direction, length, half_width):
		var health := Health.find_in(body)
		if health != null:
			deal_damage(health)
			hits += 1
	_play_beam(origin, direction, length, half_width)
	if hits > 0:
		Juice.hit_stop(hit_stop_scale, hit_stop_time)


func _play_beam(origin: Vector3, direction: Vector3, length: float, half_width: float) -> void:
	var beam := spawn_fx_mesh(beam_mesh)
	# El eje del cilindro es Y: se tiende a lo largo del carril, centrado a mitad de camino.
	beam.global_position = origin + direction * length * 0.5
	beam.look_at(beam.global_position + direction, safe_up(direction))
	beam.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	beam.scale = Vector3(half_width * beam_start_width, length, half_width * beam_start_width)
	# Se anima la transparencia del nodo, no el material compartido de la escena.
	var tween := beam.create_tween()
	tween.set_parallel(true)
	tween.tween_property(beam, "scale", Vector3(half_width, length, half_width),
			flash_time * beam_grow_fraction) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(beam, "transparency", 1.0, flash_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(beam.queue_free)
