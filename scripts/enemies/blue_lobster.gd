class_name BlueLobster
extends LobsterBody
## Langosta Azul: el minijefe del Bosque Hueco. Llega en el hueco del
## minijefe (EnemySpawner.mini_boss_scene) y pelea SOLA, en una sola fase: al
## empezar se lleva de una vez a la horda (nodo Purge) y mientras vive no
## aparece nadie más, y el mapa queda bajo su marea azul (la trae el nodo
## Arrival). Ronda al raider y cada tanto le suelta uno de sus cinco ataques
## en cadena (los hijos del nodo Moves; cada uno con sus propios valores).
## Su vida no es un número fijo: el nodo Life la calcula con el daño real de
## la party (nodo Scaling) para que la pelea dure lo mismo con cualquier
## build, y la vida de Health en BlueLobster.tscn es el PISO. Si la pelea se
## alarga, se desgasta sola (nodo Burnout). Cómo ronda lo lleva el nodo Stalk,
## la llegada el nodo Arrival, su voz el nodo Voice y su modelo el rig (Visual).
## El nombre de este archivo es su id de bestiario (kills_blue_lobster): no se
## renombra.
## Contratos por nombre: bar_title / bar_color (BossBar), fight_state y
## move_name (el harness), finish_entrance (el nodo Arrival, al terminar la
## llegada) y las líneas "<título> scaling:", "fight started:", "move:" y
## "fight over:" que leen los soaks.

enum Phase { ARRIVAL, STALK, MOVE, DEAD }

## Nombre de cada fase para el harness, en el orden de Phase.
const PHASE_NAMES: Array[StringName] = [&"arrival", &"stalk", &"move", &"dead"]
## Metros sobre los pies del raider a los que le mira (su cabeza).
const GAZE_HEIGHT: float = 1.2

@export_group("Aspecto")
## Color de su barra de vida.
@export var bar_fill_color: Color = Color(0.2, 0.62, 1.0)
## Color del estallido de esquirlas cuando muere.
@export var burst_color: Color = Color(0.12, 0.45, 1.0)

@export_group("Ritmo de la pelea")
## Segundos que ronda antes del primer ataque.
@export var first_attack_delay: float = 0.9
## Segundos que ronda entre un ataque y el siguiente, con agresividad 0: el respiro del raider.
@export var attack_pause: float = 2.2
## Multiplicador de esa pausa con agresividad 1 (0.6 = 40 % menos de pausa).
@export var attack_pause_at_full_aggression: float = 0.6

@export_group("Atasco")
## Segundos trabada contra algo (sin poder avanzar mientras ronda) tras los que sale del paso con un ataque que la saca de ahí.
@export var stuck_seconds: float = 1.2
## Ataques con los que sale de un atasco, turnándose (nombres de nodos hijos de Moves).
@export var escape_moves: Array[StringName] = [&"Leap", &"Burrow"]

@export_group("Muerte")
## Segundos que se retuerce panza arriba antes de deshacerse.
@export var death_seconds: float = 1.5
## Segundos que tarda después en deshacerse.
@export var death_fade_seconds: float = 0.5

var _phase: Phase = Phase.ARRIVAL
## El ataque en curso (null mientras ronda) y los segundos de ronda que faltan
## para poder empezar el próximo.
var _move: LobsterMove = null
var _pause_left: float = 0.0
## Cuál de escape_moves toca la próxima vez que se trabe.
var _escape_turn: int = 0

@onready var _life: LobsterLife = $Life
@onready var _purge: LobsterPurge = $Purge
@onready var _arrival: LobsterArrival = $Arrival
@onready var _moveset: LobsterMoveset = $Moves
@onready var _voice: LobsterVoice = $Voice


func _ready() -> void:
	super()
	_moveset.setup(self)
	_health.invulnerable = true
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_final_death)
	# Diferido: BossSchedule la ubica y le aplica el grado DESPUÉS de este
	# _ready, y el piso de vida es el que queda tras ese grado.
	_begin_arrival.call_deferred()


func _physics_process(delta: float) -> void:
	if _phase == Phase.ARRIVAL:
		# Quieta mientras llega: no pelea ni recibe daño hasta que empieza.
		_arrival.tick(delta)
		return
	var before := global_position
	super(delta)
	_watch_stuck(before, delta)


func _notification(what: int) -> void:
	# La detuvieron a mitad de un ataque (un «tiempo detenido», la cinemática
	# de otro jefe): el ataque se corta. Sus avisos y sus ondas corren con su
	# propio reloj y se cumplirían sin ella.
	if what == NOTIFICATION_DISABLED and is_node_ready() and _phase == Phase.MOVE:
		_interrupt_move()


# --- contratos por nombre ---------------------------------------------------------

## En qué anda: "arrival", "stalk", "move" o "dead" (lo lee el harness).
func fight_state() -> StringName:
	return PHASE_NAMES[_phase]


## Nombre del ataque en curso, o "" si no hay ninguno (lo lee el harness).
func move_name() -> StringName:
	return _move.state_name() if _move != null else &""


func is_fighting() -> bool:
	return _phase == Phase.STALK or _phase == Phase.MOVE


func is_attacking() -> bool:
	return _phase == Phase.MOVE


## Nombre para la barra de vida.
func bar_title() -> String:
	return boss_title


## Color para la barra de vida.
func bar_color() -> Color:
	return bar_fill_color


func death_burst_color() -> Color:
	return burst_color


## La llegada simple de un jefe: un anillo de `ring_radius` metros y la
## silueta que crece (lo pide el nodo Arrival).
func pop_in(ring_radius: float) -> void:
	_play_boss_entrance(ring_radius, impact_color)


## Termina la llegada y empieza la pelea. `elapsed` son los segundos de juego
## que duró y `skipped` si alguien la saltó.
func finish_entrance(elapsed: float, skipped: bool) -> void:
	if _phase != Phase.ARRIVAL:
		return
	var plan := _life.begin(_health, boss_title)
	aggression = plan.aggression
	_scale_attack_damage(1.0 + plan.damage_bonus)
	_health.invulnerable = false
	_phase = Phase.STALK
	_pause_left = first_attack_delay
	show_presence()
	# Pelea sola: se lleva ya a la horda que quedaba en la arena.
	_purge.begin(self)
	_voice.fight_started()
	rig.gesture(&"roar")
	# Línea de log para los soaks: la pelea se mide desde aquí.
	print("%s fight started: entrance=%.2fs skipped=%s at %.1fs" % [
			boss_title, elapsed, skipped, RunState.stage_time])


# --- hooks de EnemyBase y BossBase ------------------------------------------------

func _behavior_tick(delta: float) -> void:
	if not is_fighting():
		return
	_life.tick(delta)
	if not is_fighting():
		# El desgaste acaba de terminar la pelea.
		return
	_voice.tick(delta)
	_moveset.tick(delta)
	if _move != null:
		if _move.tick(delta):
			_end_move()
		return
	_pause_left = maxf(_pause_left - delta, 0.0)
	_stalk.tick(delta)


## Con un raider a la vista: lo sigue con los ojos y, si ya rondó lo suyo,
## le suelta el próximo ataque que esté listo para esa distancia. Trabada
## contra algo no espera: sale del paso con un ataque que la saca de ahí.
func _combat_tick(player: Node3D, distance: float) -> void:
	if not is_fighting():
		return
	rig.gaze_at(player.global_position + Vector3.UP * GAZE_HEIGHT)
	if _phase != Phase.STALK:
		return
	var move: LobsterMove = null
	if stuck_time() >= stuck_seconds:
		move = _escape_move()
	elif _pause_left <= 0.0:
		move = _moveset.next_ready(distance)
	if move != null:
		_start_move(move, player)


func _scale_attack_damage(multiplier: float) -> void:
	_moveset.scale_damage(multiplier)


## Su muerte: suelta lo que estuviera haciendo, se retuerce panza arriba y
## recién después se deshace.
func _death_tween() -> void:
	_cancel_move()
	# Lo que dejó en el suelo se va con ella: nadie recibe un golpe de un jefe muerto.
	_clear_ground()
	feel.clear()
	_voice.died()
	rig.set_pose(LobsterRig.Pose.DEAD)
	rig.gesture(&"throes")
	var tween := create_tween()
	tween.tween_interval(death_seconds)
	tween.tween_property(_visual, "scale", Vector3.ONE * LOOK.death_end_scale,
			death_fade_seconds).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)


# --- privados ---------------------------------------------------------------------

## Primer frame con la langosta ya ubicada y con su grado: arranca la llegada.
func _begin_arrival() -> void:
	if not is_inside_tree() or _phase != Phase.ARRIVAL:
		return
	_arrival.begin(self)


## El ataque que le toca para salir de un atasco (sin mirar su espera ni la
## distancia), o null si escape_moves no nombra ninguno de sus ataques.
func _escape_move() -> LobsterMove:
	for _attempt: int in escape_moves.size():
		var move := _moveset.by_name(escape_moves[_escape_turn % escape_moves.size()])
		_escape_turn += 1
		if move != null:
			_moveset.mark_used(move)
			return move
	return null


func _start_move(move: LobsterMove, target: Node3D) -> void:
	_move = move
	_phase = Phase.MOVE
	clear_stuck()
	set_pace(1.0)
	_voice.move_started(move)
	# Línea de log para los soaks: qué ataque y cuándo.
	print("%s move: %s at %.1fs" % [boss_title, move.state_name(), RunState.stage_time])
	move.begin(target)


## El ataque terminó: vuelve a rondar, para el otro lado, y espera su pausa.
func _end_move() -> void:
	_move.start_cooldown()
	_move = null
	_phase = Phase.STALK
	_pause_left = attack_pause * lerpf(1.0, attack_pause_at_full_aggression, aggression)
	set_pace(1.0)
	face_along(Vector3.ZERO)
	# Un ataque puede terminar con su última pose puesta (aplastada, clavada).
	rig.set_pose(LobsterRig.Pose.STALK)
	_stalk.flip()


## Corta el ataque en curso sin terminarlo (la langosta muere o la detienen).
func _cancel_move() -> void:
	if _move == null:
		return
	_move.cancel()
	_move = null
	set_pace(1.0)


## La detuvieron a mitad de un ataque: lo suelta, apaga lo que dejó en el
## suelo y, cuando vuelva a moverse, ronda su pausa y elige otro.
func _interrupt_move() -> void:
	_cancel_move()
	_clear_ground()
	feel.clear()
	fx.clear()
	_phase = Phase.STALK
	_pause_left = attack_pause * lerpf(1.0, attack_pause_at_full_aggression, aggression)
	face_along(Vector3.ZERO)
	rig.set_pose(LobsterRig.Pose.STALK)


## Apaga las ondas de choque y los carriles de aviso que dejó en el suelo.
func _clear_ground() -> void:
	get_tree().call_group(ShockRing.GROUP, &"dissipate")
	get_tree().call_group(TelegraphLane.GROUP, &"dismiss")


## Lleva la cuenta del daño (nodo Life) y acusa los golpes fuertes.
func _on_damaged(amount: float, _current: float) -> void:
	_life.on_damaged(amount)
	if _voice.hurt(amount, _health.max_hp):
		rig.gesture(&"flinch")


func _on_final_death() -> void:
	# Línea de log para los soaks: cuánto duró la pelea, con qué daño real de
	# la party y si la terminó el desgaste.
	print("%s fight over: took=%.1fs damage=%.0f dps=%.1f burnout=%s at %.1fs" % [
			boss_title, _life.fight_seconds, _life.party_damage,
			_life.party_damage / maxf(_life.fight_seconds, 0.1), _life.burning,
			RunState.stage_time])
	_phase = Phase.DEAD
	_arrival.on_boss_dead()
