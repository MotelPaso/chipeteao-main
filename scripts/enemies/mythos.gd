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
## nodo Visual). Alterna dos posturas (nodo Flight): EN VUELO gira alrededor
## del raider y EN TIERRA, tras una Picada, lo persigue a pie hasta despegar.
## Sus ataques cuelgan del nodo Moves (MythosMoveset), cada uno con sus
## valores, y sus gritos los lleva el nodo Voice.
##
## La vida de cada fase, la agresividad y el daño extra salen del nodo
## Scaling (StageBossScaling); la vida de Health en Mythos.tscn es el PISO.
## Las zonas de fuego las saca el nodo Zones, la llegada (cinemática y mapa
## en llamas) el nodo Arrival, y si una fase se alarga demasiado se consume
## solo (nodo Burnout).
## Contratos por nombre: lives_changed / lives_left / lives_total /
## bar_title / bar_color (BossBar), fight_state (arena_probe) y las líneas
## "<título> scaling:", "life over:", "fight started:", "fight over:" y
## "move:" que leen los soaks.

## Cambió la cantidad de vidas que le quedan (la barra del HUD la escucha).
signal lives_changed(left: int, total: int)

enum Phase { ARRIVAL, FLIGHT, MOVE, ASHES, DEAD }

## Nombre de cada fase para el harness, en el orden de Phase.
const PHASE_NAMES: Array[StringName] = [&"arrival", &"flight", &"move", &"ashes", &"dead"]

@export_group("Ritmo de ataques")
## Segundos de pausa entre un ataque y el siguiente, con agresividad 0.
@export var attack_pause: float = 1.5
## Multiplicador de esa pausa con agresividad 1.
@export var attack_pause_at_full_aggression: float = 0.35
## Multiplicador de la pausa mientras está posado en tierra (de cerca ataca más seguido).
@export var ground_pause_factor: float = 0.5

@export_group("Forma renacida")
## Vida desde la que pelea en su forma renacida (más grande y de otro color).
@export var ascend_from_life: int = 2
## Nombre en la barra de vida cuando renace.
@export var ascended_title: String = "Mythos renacido"
## Color de su barra de vida en la primera forma.
@export var bar_fill_color: Color = Color(1.0, 0.52, 0.12)
## Color de su barra de vida en la forma renacida.
@export var ascended_bar_color: Color = Color(0.45, 0.85, 1.0)

## Agresividad actual (0-1); la leen los ataques.
var aggression: float = 0.0
## El rig que vuela (nodo Visual); los ataques le piden poses y gestos.
var rig: MythosRig = null

var _phase: Phase = Phase.ARRIVAL
var _guard: GuardedHealth = null
var _lives_total: int = 1
## Vida actual, desde 1.
var _life: int = 1
## Segundos vulnerables y daño recibido en la vida actual.
var _life_clock: float = 0.0
var _life_damage: float = 0.0
## Segundos de pelea desde que terminó la calma, renaceres incluidos.
var _fight_clock: float = 0.0
var _ashes_left: float = 0.0
var _pause_left: float = 0.0
var _move: MythosMove = null
## Factor de daño por poder ya aplicado a los ataques (ver _apply_plan).
var _power_damage_applied: float = 1.0

@onready var _scaling: StageBossScaling = $Scaling
@onready var _zones: MythosZones = $Zones
@onready var _flight: MythosFlight = $Flight
@onready var _arrival: MythosArrival = $Arrival
@onready var _purge: MythosPurge = $Purge
@onready var _reborn: MythosRebirth = $Rebirth
@onready var _burnout: BossBurnout = $Burnout
@onready var _moveset: MythosMoveset = $Moves
@onready var _voice: MythosVoice = $Voice


func _ready() -> void:
	# Antes de super(): BossBase anuncia el jefe a la barra del HUD en su
	# _ready, y la barra ya pregunta cuántas vidas tiene.
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
	super(delta)


# --- contratos por nombre ---------------------------------------------------------

## Vidas que le quedan, contando la que está peleando.
func lives_left() -> int:
	if _phase == Phase.DEAD:
		return 0
	return _lives_total - _life + (0 if _phase == Phase.ASHES else 1)


func lives_total() -> int:
	return _lives_total


## En qué anda: "arrival", "flight", "move", "ashes" o "dead" (lo lee el harness).
func fight_state() -> StringName:
	return PHASE_NAMES[_phase]


## True mientras pelea (ni llegando, ni en cenizas, ni muerto).
func is_fighting() -> bool:
	return _phase == Phase.FLIGHT or _phase == Phase.MOVE


## Nombre para la barra de vida: cambia cuando renace.
func bar_title() -> String:
	return ascended_title if _is_ascended() else boss_title


## Color para la barra de vida: cambia cuando renace.
func bar_color() -> Color:
	return ascended_bar_color if _is_ascended() else bar_fill_color


## Avance de la calma de llegada (0-1): el fénix baja del cielo.
func set_calm_progress(progress: float) -> void:
	rig.set_arrival_progress(progress)


## Termina la calma y empieza la pelea. `elapsed` son los segundos de juego
## que duró la calma y `skipped` si alguien la saltó.
func finish_calm(elapsed: float, skipped: bool) -> void:
	if _phase != Phase.ARRIVAL:
		return
	rig.end_arrival()
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

## Punto del que salen sus plumas y sus bolas de fuego: el pico.
func muzzle_point() -> Vector3:
	return rig.beak_point()


## Marca una zona de fuego si cae en suelo caminable y el nodo Zones la deja
## salir. Con `on_raiders` puede nacer bajo un raider en pie (siempre avisa
## antes de arder); nunca nace junto a uno caído. Devuelve true si salió.
func spawn_fire_zone(center: Vector3, radius: float, warn_seconds: float,
		burn_seconds: float, dps: float, on_raiders: bool = false) -> bool:
	var at := _clamp_to_arena(center)
	if not _is_walkable(at):
		return false
	at.y = _ground_height(at)
	return _zones.mark(at, radius, warn_seconds, burn_seconds, dps, on_raiders)


## Lo posa en tierra (la Picada, al caer): desde ahí usa sus ataques de tierra.
func land() -> void:
	_flight.land(aggression)
	rig.set_pose(MythosRig.Pose.PERCH)


## Lo devuelve al vuelo (el Aletazo, al terminar).
func take_off() -> void:
	_flight.take_off()
	rig.set_pose(MythosRig.Pose.FLY)


## La pose de descanso de su postura: posado o volando. Los ataques vuelven
## a ella al terminar.
func rest_pose() -> MythosRig.Pose:
	return MythosRig.Pose.PERCH if _flight.is_grounded() else MythosRig.Pose.FLY


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
	_flight.tick(delta)
	_voice.tick(delta)
	_moveset.tick(delta, _life)
	if _phase == Phase.FLIGHT:
		_pause_left = maxf(_pause_left - delta, 0.0)
	elif _move == null or _move.tick(delta):
		_end_move()


func _pick_target() -> Node3D:
	return _flight.pick_target(get_tree())


func _movement_intent(seek: Vector3, distance: float) -> Vector3:
	if _phase != Phase.FLIGHT:
		return Vector3.ZERO
	return _flight.intent(seek, distance)


func _facing_direction(steer: Vector3, seek: Vector3) -> Vector3:
	if not is_fighting():
		return Vector3.ZERO
	if _face_along.length_squared() > 0.0001:
		return _face_along
	return seek if seek.length_squared() > 0.0001 else steer


func _combat_tick(player: Node3D, distance: float) -> void:
	if _phase != Phase.FLIGHT or _pause_left > 0.0:
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
	_apply_plan(_scaling.plan_first_life(_health.max_hp, _reborn.rebirth_seconds))
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
	rig.set_pose(MythosRig.Pose.ASHES)
	rig.burst()
	_reborn.enter_ashes(self)
	lives_changed.emit(lives_left(), _lives_total)


## Renace: vida nueva calculada con el daño que la party le hizo de verdad
## y, desde ascend_from_life, en su forma renacida.
func _rebirth() -> void:
	var plan := _scaling.plan_next_life(_life + 1, _life_damage, _life_clock, _fight_clock)
	_life += 1
	_life_clock = 0.0
	_life_damage = 0.0
	_apply_plan(plan)
	rig.ascend(_is_ascended())
	rig.set_pose(MythosRig.Pose.FLY)
	rig.gesture(&"roar")
	_reborn.burst(self)
	_health.invulnerable = false
	_phase = Phase.FLIGHT
	_pause_left = _reborn.post_rebirth_pause
	_moveset.reset_cooldowns()
	lives_changed.emit(lives_left(), _lives_total)


## Su última muerte (la única que emite Health.died): se apagan sus fuegos.
func _on_final_death() -> void:
	print("%s life over: life=%d took=%.1fs" % [boss_title, _life, _life_clock])
	print("%s fight over: took=%.1fs lives=%d" % [boss_title, _fight_clock, _lives_total])
	_cancel_move()
	_phase = Phase.DEAD
	_clear_hazards()
	_reborn.cancel()
	_voice.died()
	_arrival.on_boss_dead()
	lives_changed.emit(0, _lives_total)


# --- privados ---------------------------------------------------------------------

func _is_ascended() -> bool:
	return _life >= ascend_from_life


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
	if _move != null:
		_move.start_cooldown()
	_move = null
	_face_along = Vector3.ZERO
	_phase = Phase.FLIGHT
	_pause_left = attack_pause * lerpf(1.0, attack_pause_at_full_aggression, aggression) \
			* (ground_pause_factor if _flight.is_grounded() else 1.0)


func _cancel_move() -> void:
	if _move != null:
		_move.cancel()
	_move = null
	_face_along = Vector3.ZERO
	rig.set_trail(false)
	rig.set_nova(-1.0)


## Apaga todo lo que sus ataques dejaron en la arena.
func _clear_hazards() -> void:
	_zones.extinguish_all()
	var tree := get_tree()
	tree.call_group(SafeCircle.GROUP, "dismiss")
	tree.call_group(Fireball.GROUP, "fizzle")
	tree.call_group(FireTornado.GROUP, "dissipate")
	tree.call_group(FireWave.GROUP, "dissipate")
