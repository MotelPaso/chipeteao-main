class_name MythosRing
extends MythosMove
## Cerco de brasas: marca un anillo de zonas de fuego alrededor del raider.
## Ninguna nace encima de nadie y entre dos vecinas siempre queda un paso
## libre para salir; con agresividad el anillo trae más zonas y se abre para
## que ese paso no se cierre.

@export_group("Cerco")
## Zonas del anillo con agresividad 0.
@export var zone_count: int = 5
## Zonas extra con agresividad 1.
@export var extra_zones_at_full_aggression: int = 3
## Radio de cada zona, en metros.
@export var zone_radius: float = 2.6
## Distancia mínima del raider al centro de cada zona, en metros.
@export var ring_radius: float = 7.5
## Metros libres que quedan entre dos zonas vecinas.
@export var escape_gap: float = 2.4
## Segundos de aviso antes de que cada zona se encienda.
@export var warn_seconds: float = 1.3
## Segundos que arde cada zona.
@export var burn_seconds: float = 7.0
## Daño por segundo de cada zona (valor base).
@export var zone_dps: float = 16.0
## Segundos que Mythos se queda marcando el cerco.
@export var cast_time: float = 0.8

var _timer: float = 0.0


func scale_damage(multiplier: float) -> void:
	zone_dps *= multiplier


func begin(target: Node3D) -> void:
	_timer = cast_time
	boss.rig.set_pose(MythosRig.Pose.CAST)
	var count := maxi(aggression_count(zone_count, extra_zones_at_full_aggression), 1)
	# El anillo crece con la cantidad: cada zona ocupa su diámetro más el paso libre.
	var radius := maxf(ring_radius, float(count) * (zone_radius * 2.0 + escape_gap) / TAU)
	var center := target.global_position
	var start := randf() * TAU
	for i: int in count:
		var angle := start + TAU * float(i) / float(count)
		boss.spawn_fire_zone(center + Vector3(cos(angle), 0.0, sin(angle)) * radius,
				zone_radius, warn_seconds, burn_seconds, zone_dps)


func tick(delta: float) -> bool:
	_timer -= delta
	if _timer > 0.0:
		return false
	boss.rig.set_pose(MythosRig.Pose.FLY)
	return true


func cancel() -> void:
	boss.rig.set_pose(MythosRig.Pose.FLY)
