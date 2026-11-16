class_name MythosFireballs
extends MythosMove
## Bolas de fuego: lanza una tras otra varias bolas enormes en arco. Cada una
## avisa con un disco dónde va a caer (apunta adonde el raider VA a estar),
## estalla al caer y deja el suelo ardiendo. Con from_sky no salen de su
## pico: caen del cielo sobre toda la zona (el Diluvio de fuego de la segunda
## fase), y con passive_from_life además cae una sola cada tanto, de fondo.
## En co-op reparte las bolas entre los raiders.

@export_group("Bolas de fuego")
## Escena de la bola (Fireball, sale de Pools). Su tamaño y su arco están en esa escena.
@export var ball_scene: PackedScene = preload("res://scenes/fx/Fireball.tscn")
## Segundos de carga antes de la primera bola.
@export var windup: float = 0.75
## Bolas con agresividad 0.
@export var count: int = 3
## Bolas extra con agresividad 1.
@export var extra_at_full_aggression: int = 3
## Segundos entre una bola y la siguiente, con agresividad 0.
@export var interval: float = 0.4
## Multiplicador de esa espera con agresividad 1.
@export var interval_at_full_aggression: float = 0.7
## Segundos que tarda cada bola en caer (lo que dura su aviso), con agresividad 0.
@export var flight_seconds: float = 1.15
## Multiplicador de ese tiempo con agresividad 1 (nunca avisa menos que esto).
@export var flight_at_full_aggression: float = 0.8
## Radio del estallido y de su disco de aviso, en metros.
@export var blast_radius: float = 4.6
## Daño del estallido a cada raider dentro del disco (valor base).
@export var damage: float = 45.0
## Metros sobre el suelo por encima de los cuales el estallido no alcanza (alto: un salto no lo esquiva).
@export var height_window: float = 2.6
## Cuánto se adelanta al raider (0 = le apunta donde está, 1 = donde va a estar cuando caiga).
@export_range(0.0, 1.0) var lead: float = 0.9
## Tope de ese adelanto, en metros, para un raider a velocidad base (crece si corre más rápido).
@export var max_lead: float = 8.0
## Metros al azar que se corre cada bola alrededor de ese punto.
@export var scatter: float = 1.6
## Segundos quieto después de la última bola.
@export var recover: float = 0.5
## Sonido de cada lanzamiento (fila de Sfx.SOUND_LIBRARY).
@export var launch_sfx: StringName = &"fireball_cast"

@export_group("Fuego que dejan")
## Radio de la zona de fuego que queda donde cae cada bola, en metros (0 = no deja fuego).
@export var zone_radius: float = 3.0
## Segundos que arde esa zona.
@export var zone_burn_seconds: float = 4.5
## Daño por segundo de esa zona (valor base).
@export var zone_dps: float = 22.0

@export_group("Desde el cielo")
## Con esto las bolas caen del cielo en vez de salir del pico de Mythos.
@export var from_sky: bool = false
## Altura desde la que caen, en metros.
@export var sky_height: float = 32.0
## Metros que el punto de salida se corre hacia un lado, para que caigan inclinadas.
@export var sky_drift: float = 9.0
## Radio en metros alrededor de cada raider donde caen las bolas que no van apuntadas (0 = todas apuntadas).
@export var area_radius: float = 0.0
## Una de cada cuántas bolas va apuntada al raider (el resto cae al azar en el área).
@export var aimed_every: int = 3

@export_group("De fondo")
## Vida desde la que cae una bola sola cada tanto, sin que Mythos la lance (0 = nunca).
@export var passive_from_life: int = 0
## Segundos entre una bola de fondo y la siguiente sobre cada raider.
@export var passive_interval: float = 3.0

var _timer: float = 0.0
var _left: int = 0
var _launched: int = 0
var _recovering: bool = false
var _passive_left: float = 0.0


func scale_damage(multiplier: float) -> void:
	damage *= multiplier
	zone_dps *= multiplier


func begin(_target: Node3D) -> void:
	_timer = windup
	_left = maxi(aggression_count(count, extra_at_full_aggression), 1)
	_launched = 0
	_recovering = false
	boss.rig.set_pose(MythosRig.Pose.CAST)
	if from_sky:
		# Las llama del cielo con un grito.
		boss.rig.gesture(&"roar")


func tick(delta: float) -> bool:
	_timer -= delta
	if _timer > 0.0:
		return false
	if _recovering:
		return true
	var raiders := Coop.alive_players(get_tree())
	if not raiders.is_empty():
		_launch_at(raiders[_launched % raiders.size()], _launched)
	_launched += 1
	_left -= 1
	if _left > 0:
		_timer = interval * aggression_lerp(1.0, interval_at_full_aggression)
		return false
	_recovering = true
	_timer = recover
	boss.rig.set_pose(boss.rest_pose())
	return false


func tick_always(delta: float, life: int) -> void:
	if passive_from_life <= 0 or life < passive_from_life:
		return
	_passive_left -= delta
	if _passive_left > 0.0:
		return
	_passive_left = passive_interval
	for raider: Node3D in Coop.alive_players(get_tree()):
		_launch_at(raider, 0)


func cancel() -> void:
	boss.rig.set_pose(boss.rest_pose())


## Lanza una bola contra `raider`. `index` decide si va apuntada o al área.
func _launch_at(raider: Node3D, index: int) -> void:
	if ball_scene == null or not is_instance_valid(raider) or not raider.is_inside_tree():
		return
	var seconds := flight_seconds * aggression_lerp(1.0, flight_at_full_aggression)
	var angle := randf() * TAU
	var aimed := area_radius <= 0.0 or index % maxi(aimed_every, 1) == 0
	var spread := randf() * scatter if aimed else sqrt(randf()) * area_radius
	var base := MythosBolts.predicted(raider, seconds * lead, max_lead) if aimed \
			else raider.global_position
	var to := boss.floor_point(base + Vector3(cos(angle), 0.0, sin(angle)) * spread)
	var from := boss.muzzle_point()
	if from_sky:
		var side := randf() * TAU
		from = to + Vector3(cos(side) * sky_drift, sky_height, sin(side) * sky_drift)
	var ball := Pools.acquire_scene(ball_scene) as Fireball
	if ball == null:
		return
	Telegraph.spawn_disc(boss, to, blast_radius, seconds, boss.telegraph_color)
	ball.launch(from, to, blast_radius, seconds, damage, height_window, boss, _on_landed)
	boss.rig.gesture(&"spit")
	Sfx.play(launch_sfx)


## Donde cayó una bola queda el suelo ardiendo.
func _on_landed(at: Vector3) -> void:
	if zone_radius > 0.0 and is_instance_valid(boss) and boss.is_fighting():
		boss.spawn_fire_zone(at, zone_radius, 0.0, zone_burn_seconds, zone_dps, true)
