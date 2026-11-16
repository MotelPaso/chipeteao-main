class_name MythosTornados
extends MythosMove
## Jaula de tornados: levanta un anillo de tornados de fuego alrededor de
## cada raider. Primero se forman (el aviso, sin dañar), después el anillo
## gira y se cierra sobre el lugar donde estaba el raider y, al cerrarse,
## estalla en una onda de fuego. Se esquiva corriendo por un hueco antes de
## que se cierre; quien llega tarde cruza el muro quemándose, o se queda en
## el ojo (el hueco del medio) y salta la onda justo cuando estalla. Con
## agresividad salen más tornados y la jaula gira y se cierra más rápido. En
## co-op cada raider en pie recibe la suya, hasta max_live tornados entre
## todas.

@export_group("Jaula")
## Escena del tornado (FireTornado, sale de Pools). Su altura y su aspecto están en esa escena.
@export var tornado_scene: PackedScene = preload("res://scenes/fx/FireTornado.tscn")
## Segundos de carga antes de levantarlos.
@export var windup: float = 0.9
## Tornados alrededor de cada raider, con agresividad 0.
@export var count: int = 10
## Tornados extra por raider con agresividad 1.
@export var extra_at_full_aggression: int = 4
## Tope de tornados vivos a la vez, entre todas las jaulas.
@export var max_live: int = 30
## Radio de daño de cada tornado, en metros.
@export var radius: float = 3.0
## Hueco entre dos tornados vecinos al formarse, en metros (por ahí se sale sin quemarse; la jaula se agranda para que entren todos).
@export var gap: float = 1.6
## Radio en metros hasta el que se cierra la jaula (más que el radio de un tornado: queda un ojo en el medio).
@export var closed_radius: float = 4.6
## Segundos que tarda en formarse (el aviso): mientras tanto no daña.
@export var warn_seconds: float = 1.3
## Metros por segundo a los que se cierra, con agresividad 0.
@export var closing_speed: float = 3.0
## Radianes por segundo a los que gira la jaula, con agresividad 0.
@export var spin_speed: float = 0.7
## Multiplicador de esas dos velocidades con agresividad 1.
@export var speed_at_full_aggression: float = 1.35
## Segundos que sigue girando ya cerrada antes de deshacerse.
@export var hold_seconds: float = 0.3
## Daño por segundo de cada tornado a quien toque (valor base).
@export var dps: float = 26.0
## Segundos quieto después de levantarlos.
@export var recover: float = 0.6

@export_group("Estallido")
## Escena de la onda de fuego con que estalla la jaula al cerrarse (FireWave, sale de Pools). Vacío = sin estallido.
@export var blast_scene: PackedScene = preload("res://scenes/fx/FireWave.tscn")
## Radio en metros hasta el que llega la onda (nunca menos que la jaula al formarse).
@export var blast_radius: float = 13.0
## Metros por segundo a los que se abre.
@export var blast_speed: float = 14.0
## Daño de la onda a cada raider que alcance en el suelo (valor base).
@export var blast_damage: float = 30.0
## Metros sobre el suelo desde los que un raider ya no es alcanzado (se esquiva saltando).
@export var blast_height_window: float = 1.0
## Ancho del anillo que golpea, en metros.
@export var blast_band: float = 1.6
## Sonido del estallido (fila de Sfx.SOUND_LIBRARY).
@export var blast_sfx: StringName = &"fireball_blast"

var _timer: float = 0.0
var _cast: bool = false
## Jaulas que todavía no estallaron: {center, radius, left} (dónde, hasta
## dónde llega su onda y cuántos segundos faltan).
var _cages: Array[Dictionary] = []


func _ready() -> void:
	set_physics_process(false)


## Cuenta lo que falta para que estalle cada jaula. Corre aparte de tick():
## la jaula sigue viva cuando Mythos ya pasó a otro ataque.
func _physics_process(delta: float) -> void:
	# Si Mythos cayó en cenizas o murió, sus tornados ya se deshicieron.
	if not is_instance_valid(boss) or not boss.is_fighting():
		_cages.clear()
	for index: int in range(_cages.size() - 1, -1, -1):
		var cage := _cages[index]
		cage["left"] = float(cage["left"]) - delta
		if float(cage["left"]) <= 0.0:
			_cages.remove_at(index)
			_blast(cage["center"], float(cage["radius"]))
	if _cages.is_empty():
		set_physics_process(false)


func scale_damage(multiplier: float) -> void:
	dps *= multiplier
	blast_damage *= multiplier


func begin(_target: Node3D) -> void:
	_timer = windup
	_cast = false
	boss.rig.set_pose(MythosRig.Pose.CAST)
	boss.rig.gesture(&"spin")


func tick(delta: float) -> bool:
	_timer -= delta
	if _timer > 0.0:
		return false
	if _cast:
		return true
	_cast = true
	_raise()
	boss.rig.gesture(&"slam")
	_timer = recover
	boss.rig.set_pose(boss.rest_pose())
	return false


func cancel() -> void:
	boss.rig.set_pose(boss.rest_pose())


## Levanta una jaula alrededor de cada raider en pie, repartiendo lo que deja
## el tope de tornados vivos.
func _raise() -> void:
	var raiders := Coop.alive_players(get_tree())
	if tornado_scene == null or raiders.is_empty():
		return
	var room := max_live - get_tree().get_node_count_in_group(FireTornado.GROUP)
	var each := mini(aggression_count(count, extra_at_full_aggression),
			room / raiders.size())
	if each < 3:
		return
	# Una jaula gira para un lado y la siguiente para el otro.
	var turn := 1.0 if randf() < 0.5 else -1.0
	for raider: Node3D in raiders:
		_raise_cage(raider.global_position, each, turn)
		turn = -turn


## Una jaula de `amount` tornados alrededor de `center`, girando hacia `turn`
## (1 o -1).
func _raise_cage(center: Vector3, amount: int, turn: float) -> void:
	var haste := aggression_lerp(1.0, speed_at_full_aggression)
	var closing := closing_speed * haste
	# El anillo mide lo justo para que entren todos con su hueco.
	var ring := maxf(float(amount) * (radius * 2.0 + gap) / TAU, closed_radius)
	var closing_seconds := (ring - closed_radius) / maxf(closing, 0.01)
	var life := closing_seconds + hold_seconds
	var reach := maxf(blast_radius, ring)
	if blast_scene != null:
		# El disco grande es la cuenta regresiva del estallido.
		boss.warn_disc(boss.floor_point(center), reach, warn_seconds + closing_seconds)
		_cages.append({"center": center, "radius": reach,
				"left": warn_seconds + closing_seconds})
		set_physics_process(true)
	var start := randf() * TAU
	for index: int in amount:
		var angle := start + TAU * float(index) / float(amount)
		var at := boss.floor_point(center + Vector3(cos(angle), 0.0, sin(angle)) * ring)
		var tornado := Pools.acquire_scene(tornado_scene) as FireTornado
		if tornado == null:
			return
		Telegraph.spawn_disc(boss, at, radius, warn_seconds, boss.telegraph_color)
		tornado.start(at, radius, warn_seconds, life, dps, 0.0, false)
		tornado.orbit(center, spin_speed * haste * turn, closing, closed_radius)


## La jaula terminó de cerrarse: estalla en una onda que nace en el ojo.
func _blast(center: Vector3, reach: float) -> void:
	FireWave.spawn(blast_scene, boss.floor_point(center), 0.5, reach, blast_speed,
			blast_damage, blast_height_window, blast_band, boss)
	boss.blast(boss.floor_point(center), closed_radius)
	boss.feel.shock(MythosFeel.Shock.HEAVY, center)
	Sfx.play(blast_sfx)
