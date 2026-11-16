class_name MythosDawn
extends MythosMove
## Amanecer: el golpe más fuerte de Mythos. Se eleva, se enciende como un sol
## y marca unos pocos CÍRCULOS A SALVO; al estallar quema a todo raider en pie
## que no esté dentro de uno. No se salta ni se esquiva corriendo lejos: hay
## que llegar a un círculo. Mientras carga, le lanza plumas a quien todavía
## no llegó. Dentro de un círculo no arde nada (las zonas de fuego que lo
## pisan se apagan) y un raider caído siempre queda dentro de uno, para que
## se lo pueda reanimar.

enum Step { CHARGE, REST }

@export_group("Amanecer")
## Segundos de carga antes del estallido, con agresividad 0.
@export var charge_seconds: float = 3.4
## Multiplicador de la carga con agresividad 1 (nunca carga menos que esto).
@export var charge_at_full_aggression: float = 0.8
## Radio del estallido, en metros, desde Mythos.
@export var blast_radius: float = 40.0
## Daño del estallido a cada raider fuera de los círculos (valor base).
@export var damage: float = 75.0
## Segundos quieto después del estallido.
@export var recover: float = 1.4
## Aviso en el HUD al empezar a cargar.
@export var announce_text: String = "¡Amanecer! Corre a un círculo a salvo"
## Sonido al empezar a cargar (fila de Sfx.SOUND_LIBRARY).
@export var charge_sfx: StringName = &"phoenix_cry"
## Sonido del estallido (fila de Sfx.SOUND_LIBRARY).
@export var blast_sfx: StringName = &"phoenix_nova"

@export_group("Círculos a salvo")
## Escena del círculo a salvo (SafeCircle, sale de Pools). Su color y su columna de luz están en esa escena.
@export var safe_scene: PackedScene = preload("res://scenes/fx/SafeCircle.tscn")
## Círculos a salvo para un raider solo.
@export var safe_circles: int = 2
## Círculos extra por cada raider de la party además del primero.
@export var extra_circles_per_player: int = 1
## Radio de cada círculo, en metros.
@export var safe_radius: float = 3.2
## Distancia mínima de un círculo a su raider, en metros.
@export var safe_min_distance: float = 7.0
## Distancia máxima de un círculo a su raider, en metros.
@export var safe_max_distance: float = 12.0

@export_group("Plumas mientras carga")
## Escena de la pluma (un EnemyBolt; sale de Pools).
@export var bolt_scene: PackedScene = preload("res://scenes/enemies/FireFeather.tscn")
## Segundos entre un abanico y el siguiente mientras carga (0 = no lanza plumas).
@export var harass_interval: float = 1.0
## Plumas de cada abanico.
@export var harass_bolts: int = 3
## Ancho de cada abanico, en grados.
@export var harass_spread_degrees: float = 26.0
## Daño de cada pluma (valor base).
@export var harass_bolt_damage: float = 12.0

var _step: Step = Step.CHARGE
var _timer: float = 0.0
var _charge_total: float = 0.0
var _harass_left: float = 0.0
## Centros de los círculos a salvo de esta carga.
var _circles: Array[Vector3] = []


func scale_damage(multiplier: float) -> void:
	damage *= multiplier
	harass_bolt_damage *= multiplier


func begin(_target: Node3D) -> void:
	_step = Step.CHARGE
	_charge_total = charge_seconds * aggression_lerp(1.0, charge_at_full_aggression)
	_timer = _charge_total
	_harass_left = harass_interval
	_place_circles()
	boss.rig.set_pose(MythosRig.Pose.NOVA)
	boss.rig.gesture(&"screech")
	boss.rig.set_nova(0.0)
	Sfx.play(charge_sfx)
	get_tree().call_group("boss_ui", "announce", announce_text)
	# Línea de log para los soaks.
	print("%s dawn: circles=%d charge=%.2fs" % [
			boss.boss_title, _circles.size(), _charge_total])


func tick(delta: float) -> bool:
	_timer -= delta
	if _step == Step.REST:
		return _timer <= 0.0
	var charge := 1.0 - clampf(_timer / maxf(_charge_total, 0.01), 0.0, 1.0)
	boss.rig.set_nova(charge)
	boss.feel.dread(charge)
	_tick_harass(delta)
	if _timer <= 0.0:
		_detonate()
	return false


func cancel() -> void:
	boss.rig.set_nova(-1.0)
	boss.rig.set_pose(boss.rest_pose())


## Un círculo cerca de cada raider en pie (se reparten por turnos) y uno
## sobre cada raider caído.
func _place_circles() -> void:
	_circles.clear()
	var raiders := Coop.alive_players(get_tree())
	var count := safe_circles + extra_circles_per_player * maxi(Coop.player_count - 1, 0)
	var start := randf() * TAU
	for i: int in count:
		if raiders.is_empty():
			break
		var anchor := raiders[i % raiders.size()].global_position
		var angle := start + TAU * float(i) / float(maxi(count, 1))
		var distance := randf_range(safe_min_distance, safe_max_distance)
		_add_circle(boss.safe_point(anchor + Vector3(cos(angle), 0.0, sin(angle)) * distance))
	for node: Node in get_tree().get_nodes_in_group(&"downed_players"):
		var body := node as Node3D
		if body != null and body.is_inside_tree():
			_add_circle(boss.floor_point(body.global_position))


func _add_circle(at: Vector3) -> void:
	var circle := Pools.acquire_scene(safe_scene) as SafeCircle
	if circle == null:
		return
	circle.show_circle(at, safe_radius, _charge_total)
	_circles.append(at)
	# Dentro de un círculo no arde nada: las zonas que lo pisan se apagan.
	for node: Node in get_tree().get_nodes_in_group(FireZone.GROUP):
		var zone := node as FireZone
		if zone == null:
			continue
		var offset := zone.global_position - at
		offset.y = 0.0
		if offset.length() < zone.zone_radius() + safe_radius:
			zone.extinguish()


func _is_safe(point: Vector3) -> bool:
	for center: Vector3 in _circles:
		var offset := point - center
		offset.y = 0.0
		if offset.length_squared() <= safe_radius * safe_radius:
			return true
	return false


## Abanicos de plumas contra los raiders que todavía no llegaron a un círculo.
func _tick_harass(delta: float) -> void:
	if harass_interval <= 0.0:
		return
	_harass_left -= delta
	if _harass_left > 0.0:
		return
	_harass_left = harass_interval
	for raider: Node3D in Coop.alive_players(get_tree()):
		if not _is_safe(raider.global_position):
			MythosBolts.fan(boss, bolt_scene, boss.muzzle_point(), raider, harass_bolts,
					deg_to_rad(harass_spread_degrees), harass_bolt_damage)


## El estallido: daña a los raiders en pie dentro del radio y fuera de todo
## círculo. No mira la altura: saltar no lo esquiva.
func _detonate() -> void:
	var hit := 0
	var origin := boss.global_position
	for raider: Node3D in Coop.alive_players(get_tree()):
		var offset := raider.global_position - origin
		offset.y = 0.0
		if offset.length() > blast_radius or _is_safe(raider.global_position):
			continue
		var health := Health.find_in(raider)
		if health != null and not health.is_dead:
			health.take_damage(damage, false, boss)
			hit += 1
	print("%s dawn blast: hit=%d circles=%d" % [boss.boss_title, hit, _circles.size()])
	boss.rig.set_nova(-1.0)
	boss.rig.gesture(&"slam")
	boss.feel.shock(MythosFeel.Shock.CATACLYSM, origin)
	Sfx.play(blast_sfx)
	get_tree().call_group(SafeCircle.GROUP, "dismiss")
	boss.rig.set_pose(boss.rest_pose())
	_step = Step.REST
	_timer = recover
