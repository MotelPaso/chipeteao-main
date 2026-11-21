class_name Mythos
extends MythosBody
## Mythos, el fénix de fuego: jefe de etapa del Bosque Hueco. Llega en el
## lugar de la revancha Ancestral (EnemySpawner.stage_boss_scene) y pelea
## SOLO: al empezar quema a la horda que quedaba (nodo Purge) y, mientras
## vive, el spawner no saca nada.
## Pelea en DOS FASES, que son dos vidas: al agotar la primera cae en
## cenizas, invulnerable, y renace más grande, con otra forma y ataques más
## rápidos (nodo Rebirth; el rig toma su forma renacida). Solo su última
## muerte emite Health.died, que es lo que abre la puerta de etapa.
##
## Vuela bajo: el CUERPO va por el suelo como el de todo enemigo (las armas
## le pegan igual que a cualquiera) y lo que flota es el rig (MythosRig, el
## nodo Visual). Alterna dos posturas (nodo Flight): EN VUELO gira rápido
## alrededor del raider, también mientras ataca, y EN TIERRA, tras una
## Picada, lo persigue a pie hasta despegar. Sus ataques cuelgan del nodo
## Moves (MythosMoveset), cada uno con sus valores; algunos salen
## encadenados, sin pausa. Sus gritos los lleva el nodo Voice y lo que se
## siente de sus golpes (temblor, viñeta de peligro), el nodo Feel.
## La vida de cada fase, la agresividad y el daño extra salen del nodo
## Scaling (StageBossScaling); la vida de Health en Mythos.tscn es el PISO.
## Las zonas de fuego las saca el nodo Zones (MythosBody), la llegada el
## nodo Arrival, y una fase que se alarga demasiado se consume sola (Burnout).
## Nada en la primera fase avisa que tiene otra: al agotarla parece morir
## (su barra se va, la música se apaga, nadie le apunta) y recién después
## renace.
## Contratos por nombre: bar_visible_changed / bar_title / bar_color
## (BossBar), fight_state (arena_probe), finish_calm y finish_rebirth (la
## cinemática o el nodo Arrival, al terminar cada acto) y las líneas
## "<título> scaling:", "life over:", "fight started:", "fight over:" y
## "move:" que leen los soaks.

## Su barra de vida tiene que irse (parece muerto) o volver (renació).
signal bar_visible_changed(shown: bool)

enum Phase { ARRIVAL, FLIGHT, MOVE, ASHES, DEAD }

## Nombre de cada fase para el harness, en el orden de Phase.
const PHASE_NAMES: Array[StringName] = [&"arrival", &"flight", &"move", &"ashes", &"dead"]
## Metros sobre los pies del raider a los que le mira (el pecho).
const GAZE_HEIGHT: float = 1.2

@export_group("Ritmo de ataques")
## Segundos de pausa entre un ataque y el siguiente, con agresividad 0.
@export var attack_pause: float = 1.2
## Multiplicador de esa pausa con agresividad 1.
@export var attack_pause_at_full_aggression: float = 0.35
## Multiplicador de la pausa mientras está posado en tierra (de cerca ataca más seguido).
@export var ground_pause_factor: float = 0.5

var _phase: Phase = Phase.ARRIVAL
var _guard: GuardedHealth = null
var _lives_total: int = 1
## Vida actual (desde 1) y sus segundos vulnerables y daño recibido.
var _life: int = 1
var _life_clock: float = 0.0
var _life_damage: float = 0.0
## Segundos de pelea desde que terminó la calma, renaceres incluidos.
var _fight_clock: float = 0.0
var _ashes_left: float = 0.0
## Segundos que le quedan haciéndose el muerto antes de empezar a renacer.
var _fakeout_left: float = 0.0
## True si el renacer lo lleva la cinemática (ella avisa con finish_rebirth).
var _ashes_staged: bool = false
var _pause_left: float = 0.0
## El ataque en curso, y si salió encadenado a otro (entonces no encadena más).
var _move: MythosMove = null
var _in_combo: bool = false
## Factor de daño por poder ya aplicado a los ataques (ver _apply_plan).
var _power_damage_applied: float = 1.0

@onready var _scaling: StageBossScaling = $Scaling
@onready var _arrival: MythosArrival = $Arrival
@onready var _purge: MythosPurge = $Purge
@onready var _reborn: MythosRebirth = $Rebirth
@onready var _burnout: BossBurnout = $Burnout
@onready var _moveset: MythosMoveset = $Moves
@onready var _voice: MythosVoice = $Voice


func _ready() -> void:
	_lives_total = _scaling.lives()
	super()
	_guard = _health as GuardedHealth
	if _guard == null:
		push_error("Mythos: the Health node must use guarded_health.gd")
	rig = _visual as MythosRig
	_moveset.setup(self)
	_health.invulnerable = true
	_health.damaged.connect(_on_damaged)
	_health.died.connect(_on_final_death)
	if _guard != null:
		_guard.guard_reached.connect(_on_life_spent)
	# Diferido: BossSchedule lo ubica y le aplica el grado DESPUÉS de este
	# _ready, y el piso de vida es el que queda tras ese grado.
	_begin_arrival.call_deferred()


func _physics_process(delta: float) -> void:
	if _phase == Phase.ARRIVAL:
		# Quieto mientras llega: no pelea ni recibe daño hasta que la calma
		# termina, y durante la cinemática el suelo está fuera de la física.
		_arrival.tick(delta)
		return
	if _phase == Phase.ASHES and _ashes_staged:
		# Igual en el renacer: lo lleva la cinemática, con el mundo congelado.
		return
	super(delta)


# --- contratos por nombre ---------------------------------------------------------

## En qué anda: "arrival", "flight", "move", "ashes" o "dead" (lo lee el harness).
func fight_state() -> StringName:
	return PHASE_NAMES[_phase]


## True mientras pelea (ni llegando, ni en cenizas, ni muerto).
func is_fighting() -> bool:
	return _phase == Phase.FLIGHT or _phase == Phase.MOVE


## Nombre para la barra de vida: cambia cuando renace.
func bar_title() -> String:
	return _reborn.ascended_title if _is_ascended() else boss_title


## Color para la barra de vida: cambia cuando renace.
func bar_color() -> Color:
	return _reborn.ascended_bar_color if _is_ascended() else _reborn.bar_fill_color


## Su nombre en la forma renacida (el cartel del renacer).
func reborn_title() -> String:
	return _reborn.ascended_title


## Termina el renacer que llevaba la cinemática: `elapsed` son los segundos
## de juego que duró y `skipped` si alguien lo saltó.
func finish_rebirth(_elapsed: float, _skipped: bool) -> void:
	if _phase == Phase.ASHES and _ashes_staged:
		_rebirth()


## El fuego de la segunda fase recorre el mapa desde `origin` en `seconds`.
func ascend_world(origin: Vector3, seconds: float) -> void:
	_arrival.ascend_world(origin, seconds)


## Termina la calma y empieza la pelea. `elapsed` son los segundos de juego
## que duró la calma y `skipped` si alguien la saltó.
func finish_calm(elapsed: float, skipped: bool) -> void:
	if _phase != Phase.ARRIVAL:
		return
	rig.stop_flying()
	rig.set_trail(false)
	rig.set_pose(MythosRig.Pose.FLY)
	rig.gesture(&"roar")
	_health.invulnerable = false
	_phase = Phase.FLIGHT
	_pause_left = attack_pause
	_voice.fight_started()
	Juice.shake(impact_shake_strength, impact_shake_duration)
	# Línea de log para los soaks: la pelea se mide desde aquí.
	print("%s fight started: calm=%.2fs skipped=%s at %.1fs" % [
			boss_title, elapsed, skipped, RunState.stage_time])
	_purge.begin(self)


# --- lo que piden los ataques (nodos Moves) ---------------------------------------

## Destello a pantalla completa (lo piden sus golpes más fuertes).
func screen_flash() -> void:
	_arrival.flash()


# --- hooks de EnemyBase -----------------------------------------------------------

func _scale_attack_damage(multiplier: float) -> void:
	_reborn.scale_damage(multiplier)
	_moveset.scale_damage(multiplier)


func _behavior_tick(delta: float) -> void:
	_fight_clock += delta
	if _phase == Phase.ASHES:
		if _fakeout_left > 0.0:
			_fakeout_left -= delta
			if _fakeout_left <= 0.0:
				_begin_rebirth()
			return
		_ashes_left -= delta
		if _ashes_left <= 0.0:
			_rebirth()
		return
	if not is_fighting():
		return
	_life_clock += delta
	_burnout.tick(delta, _life_clock)
	if not is_fighting():
		# El desgaste acaba de agotar esta vida.
		return
	_flight.tick(delta, _phase == Phase.MOVE)
	if _voice.tick(delta):
		rig.gesture(&"screech")
	_moveset.tick(delta, _life)
	if _phase == Phase.FLIGHT:
		_pause_left = maxf(_pause_left - delta, 0.0)
	elif _move == null or _move.tick(delta):
		_end_move()


func _flight_share() -> float:
	if _phase == Phase.FLIGHT:
		return 1.0
	# En medio de un ataque sigue volando lo que ese ataque le deje.
	return _move.flight_factor if _phase == Phase.MOVE and _move != null else 0.0


func _combat_tick(player: Node3D, distance: float) -> void:
	if not is_fighting():
		return
	# No le saca los ojos de encima al raider que tiene de blanco.
	rig.gaze_at(player.global_position + Vector3.UP * GAZE_HEIGHT)
	if _phase != Phase.FLIGHT or _pause_left > 0.0 or _flight.is_crossing():
		return
	if _flight.wants_takeoff():
		if _moveset.takeoff() != null:
			_start_move(_moveset.takeoff(), player)
		else:
			take_off()
		return
	var move := _moveset.next_ready(_life, distance, _flight.is_grounded())
	if move != null:
		_start_move(move, player)


# --- vidas ------------------------------------------------------------------------

## Primer frame con Mythos ya ubicado y con su grado: calcula la primera
## vida y arranca la calma.
func _begin_arrival() -> void:
	if not is_inside_tree() or _phase != Phase.ARRIVAL:
		return
	_apply_plan(_scaling.plan_first_life(_health.max_hp,
			_reborn.interlude_seconds(_arrival.stages_rebirth())))
	rig.set_trail(true)
	_arrival.begin(self)


## Aplica el plan de una vida: vida máxima, guarda, agresividad y daño extra.
func _apply_plan(plan: StageBossScaling.LifePlan) -> void:
	_health.max_hp = plan.hp
	_health.heal_full()
	if _guard != null:
		if plan.life < _lives_total:
			_guard.arm_guard()
		else:
			_guard.drop_guard()
	aggression = plan.aggression
	_burnout.arm(_health, boss_title, plan.burnout_after, plan.burnout_drain)
	# El daño por poder se aplica como razón contra lo ya aplicado: el poder
	# de la party cambia entre vidas y no debe componerse.
	var wanted := 1.0 + plan.damage_bonus
	_scale_attack_damage(wanted / _power_damage_applied)
	_power_damage_applied = wanted
	print(_scaling.log_line(boss_title, plan))


## La vida actual se agotó y queda otra: cae en cenizas, invulnerable, y el
## nodo Rebirth prepara el renacer.
func _on_life_spent() -> void:
	if _phase == Phase.DEAD or _phase == Phase.ASHES:
		return
	print("%s life over: life=%d took=%.1fs" % [boss_title, _life, _life_clock])
	_cancel_move()
	_clear_hazards()
	_flight.take_off()
	_health.invulnerable = true
	_phase = Phase.ASHES
	_ashes_left = _reborn.rebirth_seconds
	# Cae girando sobre sí mismo.
	rig.gaze_ahead()
	rig.gesture(&"spin")
	rig.set_pose(MythosRig.Pose.ASHES)
	rig.burst()
	# Parece su muerte: grita, estalla, su barra se va y la música se apaga.
	_ashes_staged = false
	_fakeout_left = _reborn.fall(self)
	_voice.died()
	_arrival.feign_death(_fakeout_left)
	play_dead()
	bar_visible_changed.emit(false)
	if _fakeout_left <= 0.0:
		_begin_rebirth()


## Terminó de hacerse el muerto: empieza el renacer. Con cinemática lo lleva
## ella (avisa con finish_rebirth); sin ella corre el reloj de _ashes_left.
func _begin_rebirth() -> void:
	_fakeout_left = 0.0
	_ashes_staged = _arrival.play_rebirth(self)
	_reborn.enter_ashes(self, _ashes_staged)


## Renace: vida nueva calculada con el daño que la party le hizo de verdad
## y, desde ascend_from_life, en su forma renacida.
func _rebirth() -> void:
	var plan := _scaling.plan_next_life(_life + 1, _life_damage, _life_clock, _fight_clock)
	_life += 1
	_life_clock = 0.0
	_life_damage = 0.0
	_apply_plan(plan)
	rig.ascend(_is_ascended())
	_flight.reborn = _is_ascended()
	rig.set_nova(-1.0)
	rig.set_pose(MythosRig.Pose.FLY)
	if _is_ascended():
		telegraph_color = _reborn.ascended_telegraph_color
		impact_color = _reborn.ascended_impact_color
	if _ashes_staged:
		_ashes_staged = false
	else:
		# Sin cinemática, el estallido del renacer pasa en plena pelea.
		rig.gesture(&"roar")
		_reborn.burst(self)
	_health.invulnerable = false
	_phase = Phase.FLIGHT
	_pause_left = _reborn.post_rebirth_pause
	_moveset.reset_cooldowns()
	rise_again()
	bar_visible_changed.emit(true)


## Su última muerte (la única que emite Health.died): se apagan sus fuegos.
func _on_final_death() -> void:
	print("%s life over: life=%d took=%.1fs" % [boss_title, _life, _life_clock])
	print("%s fight over: took=%.1fs lives=%d" % [boss_title, _fight_clock, _lives_total])
	_cancel_move()
	_phase = Phase.DEAD
	rig.gaze_ahead()
	_clear_hazards()
	_reborn.cancel()
	_voice.died()
	_arrival.on_boss_dead()


# --- privados ---------------------------------------------------------------------

func _is_ascended() -> bool:
	return _life >= _reborn.ascend_from_life


## Suma el daño de la party a la vida actual (el del desgaste no cuenta) y
## se sacude si el golpe le dolió.
func _on_damaged(amount: float, _current: float) -> void:
	if _burnout.draining:
		return
	_life_damage += amount
	if _voice.hurt(amount, _health.max_hp):
		rig.gesture(&"flinch")


func _start_move(move: MythosMove, target: Node3D) -> void:
	_move = move
	_phase = Phase.MOVE
	# Línea de log para los soaks: qué ataque usa y cuándo.
	print("%s move: %s life=%d at %.1fs" % [boss_title, move.name, _life, _fight_clock])
	_voice.move_started(move)
	move.begin(target)


func _end_move() -> void:
	var done := _move
	if done != null:
		done.start_cooldown()
	_move = null
	_face_along = Vector3.ZERO
	rig.lift = 0.0
	_phase = Phase.FLIGHT
	_pause_left = attack_pause * lerpf(1.0, attack_pause_at_full_aggression, aggression) \
			* (ground_pause_factor if _flight.is_grounded() else 1.0)
	# Combo: el ataque que este encadena sale ya, sin pausa. Uno solo por vez.
	var next: MythosMove = null if _in_combo \
			else _moveset.follow_up(done, _life, _flight.is_grounded())
	var target: Node3D = _pick_target() if next != null else null
	_in_combo = target != null
	if _in_combo:
		_start_move(next, target)


func _cancel_move() -> void:
	if _move != null:
		_move.cancel()
	_move = null
	_in_combo = false
	_face_along = Vector3.ZERO
	rig.lift = 0.0
	rig.set_trail(false)
	rig.set_nova(-1.0)

