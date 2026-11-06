extends WeaponBase
## Kamehameha: un rayo de energía de enfriamiento largo lanzado hacia el
## enemigo más cercano, que golpea fuerte a TODO enemigo dentro de un carril
## largo y ancho. Cómo usa los ajustes de WeaponBase:
##   damage        — daño por enemigo atrapado en el rayo (por deal_damage)
##   cooldown      — tiempo de carga entre rayos (largo a propósito)
##   attack_range  — alcance para elegir blanco; el rayo mide beam_length
## Visual: un cilindro brillante tendido a lo largo del carril que destella y
## se desvanece, más una sacudida y una pausa breve al soltarlo.

@export var beam_length: float = 18.0
@export var beam_width: float = 2.4
@export var beam_color: Color = Color(0.45, 0.75, 1.0)
@export var flash_time: float = 0.45
@export var muzzle_height: float = 1.1

@export_group("Multitud")
## Segundos entre los rayos extra del Tomo de Multitud; dos solapados en el mismo carril serían un solo rayo más grueso.
@export var extra_stagger: float = 0.12
## Grados entre rayos vecinos; el carril es largo, así que un abanico estrecho ya separa varios metros las puntas.
@export var extra_fan_deg: float = 14.0

## El rayo usa el rugido de jefe mientras el catálogo de sonidos no tenga uno
## propio; bajado fuerte porque ese sonido está mezclado para una entrada por
## partida y esta arma dispara cada pocos segundos.
const BEAM_VOLUME_DB: float = -12.0


var _beam_mesh: CylinderMesh = null


func _ready() -> void:
	_beam_mesh = CylinderMesh.new()
	_beam_mesh.top_radius = 1.0
	_beam_mesh.bottom_radius = 1.0
	_beam_mesh.height = 1.0
	# Teselado explícito: un rayo recto no gana nada con anillos de altura, y
	# 16 lados se ven redondos a su ancho.
	_beam_mesh.radial_segments = 16
	_beam_mesh.rings = 1
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(beam_color, 0.85)
	material.emission_enabled = true
	material.emission = beam_color
	material.emission_energy_multiplier = 2.5
	_beam_mesh.material = material


func fire(target: Node3D) -> void:
	var origin := global_position + Vector3.UP * muzzle_height
	var center_dir := flat_dir_or(target.global_position + Vector3.UP * 0.8 - origin,
			-global_transform.basis.z)
	fire_volley(maxi(effective_projectile_count(), 1), center_dir, _blast,
			extra_stagger, extra_fan_deg)
	# Un rugido y una sacudida por ráfaga, salgan los rayos que salgan; van
	# aquí, con el disparo, y no en el helper visual.
	Sfx.play(&"boss_roar_2", BEAM_VOLUME_DB)
	Juice.shake(0.2, 0.35)


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
		Juice.hit_stop(0.1, 0.05)


func _play_beam(origin: Vector3, direction: Vector3, length: float, half_width: float) -> void:
	var beam := spawn_fx_mesh(_beam_mesh)
	# El eje del cilindro es Y: se tiende a lo largo del carril, centrado a mitad de camino.
	beam.global_position = origin + direction * length * 0.5
	beam.look_at(beam.global_position + direction, safe_up(direction))
	beam.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	beam.scale = Vector3(half_width * 0.3, length, half_width * 0.3)
	var tween := beam.create_tween()
	tween.set_parallel(true)
	tween.tween_property(beam, "scale", Vector3(half_width, length, half_width), flash_time * 0.3) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(beam, "transparency", 1.0, flash_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(beam.queue_free)
