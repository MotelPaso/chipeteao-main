class_name MythosRing
extends MythosMove
## Cerco de brasas: encierra al raider en un anillo de zonas de fuego con una
## sola salida y, poco después, hace estallar el centro. Hay que salir por el
## hueco (o pagar el peaje de cruzar el fuego, o saltarlo) antes del estallido.

@export_group("Cerco")
## Radio del anillo, en metros: del raider al centro de cada zona.
@export var ring_radius: float = 6.2
## Radio de cada zona, en metros.
@export var zone_radius: float = 2.3
## Separación entre zonas vecinas, en diámetros (1 = se tocan apenas; menos = se pisan y no dejan pasar).
@export_range(0.5, 1.0) var zone_spacing: float = 0.94
## Zonas que faltan en el anillo: el hueco por donde se sale.
@export var gap_zones: int = 1
## Segundos de aviso antes de que el anillo se encienda.
@export var warn_seconds: float = 0.8
## Segundos que arde el anillo.
@export var burn_seconds: float = 6.0
## Daño por segundo de cada zona (valor base).
@export var zone_dps: float = 22.0

@export_group("Estallido del centro")
## Segundos entre que marca el cerco y estalla el centro, con agresividad 0.
@export var blast_delay: float = 2.5
## Multiplicador de esa espera con agresividad 1.
@export var blast_delay_at_full_aggression: float = 0.8
## Radio del estallido y de su disco de aviso, en metros.
@export var blast_radius: float = 4.4
## Daño del estallido a cada raider dentro del disco (valor base).
@export var blast_damage: float = 45.0
## Metros sobre el suelo por encima de los cuales el estallido no alcanza.
@export var blast_height_window: float = 1.8
## Segundos quieto después del estallido.
@export var recover: float = 0.5
## Sonido del estallido (fila de Sfx.SOUND_LIBRARY).
@export var blast_sfx: StringName = &"fire_whoosh"
## Escena de la columna de fuego del estallido (FireBurst, sale de Pools). Vacío = sin columna.
@export var burst_scene: PackedScene = preload("res://scenes/fx/FireBurst.tscn")
## Alto de esa columna, en metros.
@export var burst_height: float = 10.0
## Radio de la columna, en veces el radio del estallido.
@export var burst_radius_factor: float = 0.6

var _center: Vector3 = Vector3.ZERO
var _timer: float = 0.0
var _blasted: bool = false


func scale_damage(multiplier: float) -> void:
	zone_dps *= multiplier
	blast_damage *= multiplier


func begin(target: Node3D) -> void:
	_center = boss.floor_point(target.global_position)
	_blasted = false
	_timer = blast_delay * aggression_lerp(1.0, blast_delay_at_full_aggression)
	boss.rig.set_pose(MythosRig.Pose.CAST)
	boss.rig.gesture(&"screech")
	# Las zonas que caben en el anillo, pisándose apenas; las primeras
	# gap_zones no salen y dejan el hueco.
	var count := maxi(ceili(TAU * ring_radius / (zone_radius * 2.0 * zone_spacing)), 3)
	var start := randf() * TAU
	for i: int in range(gap_zones, count):
		var angle := start + TAU * float(i) / float(count)
		boss.spawn_fire_zone(_center + Vector3(cos(angle), 0.0, sin(angle)) * ring_radius,
				zone_radius, warn_seconds, burn_seconds, zone_dps, true)
	Telegraph.spawn_disc(boss, _center, blast_radius, _timer, boss.telegraph_color)


func tick(delta: float) -> bool:
	_timer -= delta
	if _timer > 0.0:
		return false
	if _blasted:
		return true
	_blasted = true
	boss.strike_ground([_center], blast_radius, blast_height_window, blast_damage)
	FireBurst.spawn(burst_scene, _center, blast_radius * burst_radius_factor, burst_height)
	boss.feel.shock(MythosFeel.Shock.HEAVY, _center)
	Sfx.play(blast_sfx)
	boss.rig.gesture(&"slam")
	boss.rig.set_pose(boss.rest_pose())
	_timer = recover
	return false


func cancel() -> void:
	boss.rig.set_pose(boss.rest_pose())
