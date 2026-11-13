class_name Mythos
extends BossBase
## Mythos, el fénix de fuego: jefe de etapa del Bosque Hueco. Llega en el
## lugar de la revancha Ancestral (EnemySpawner.stage_boss_scene) y pelea en
## varias VIDAS: al agotar una cae en cenizas, invulnerable, y renace con un
## estallido avisado. Solo su última muerte emite Health.died, que es lo que
## abre la puerta de etapa.
##
## Vuela bajo: el CUERPO va por el suelo como el de todo enemigo (las armas
## le pegan igual que a cualquiera) y lo que flota es el rig (MythosRig, el
## nodo Visual). Alterna entre acosar pegado al raider y sobrevolarlo de
## lejos, y entre tanto usa los ataques que cuelgan de Moves (cada uno con
## sus valores): Plumas ardientes, Picada, Cerco de brasas y Lluvia de brasas.
##
## La vida de cada vida, la agresividad y el daño extra salen del nodo
## Scaling (StageBossScaling); la vida de Health en Mythos.tscn es el PISO.
## Las zonas de fuego las saca el nodo Zones (MythosZones), que nunca deja
## nacer una encima de un raider.
## Contratos por nombre: lives_changed / lives_left / lives_total (BossBar),
## fight_state (arena_probe) y las líneas "<título> scaling:", "life over:",
## "fight started:" y "fight over:" que leen los soaks.

## Cambió la cantidad de vidas que le quedan (la barra del HUD la escucha).
signal lives_changed(left: int, total: int)

enum Phase { ARRIVAL, FLIGHT, MOVE, ASHES, DEAD }

@export_group("Llegada")
## Escena de la cinemática de llegada (MythosCinematic.tscn): es la dueña de la calma y de la canción. Sin escena, llega con la entrada simple.
@export var cinematic_scene: PackedScene
## Escena que quema el mapa mientras llega (HellTransformation.tscn). Sin escena, el mapa no cambia.
@export var transformation_scene: PackedScene
## Segundos de la entrada simple cuando Mythos llega sin cinemática.
@export var plain_arrival_seconds: float = 1.2
## Grito al empezar la pelea (fila de Sfx.SOUND_LIBRARY).
@export var arrival_sfx: StringName = &"phoenix_cry"

@export_group("Vuelo")
## Distancia al raider, en metros, a la que se queda mientras lo acosa de cerca (las armas cortas llegan).
@export var close_distance: float = 1.9
## Segundos que acosa de cerca antes de alejarse.
@export var close_seconds: float = 5.0
## Distancia al raider, en metros, a la que lo sobrevuela de lejos.
@export var far_distance: float = 9.0
## Segundos que sobrevuela de lejos antes de volver a acercarse.
@export var far_seconds: float = 4.0
## Margen en metros alrededor de far_distance dentro del cual solo gira.
@export var far_band: float = 1.5
## Fracción de su velocidad a la que gira alrededor del raider (0-1).
@export_range(0.0, 1.0) var orbit_speed_factor: float = 0.55
## Segundos que persigue al mismo raider antes de elegir otro al azar.
@export var focus_seconds: float = 8.0
## Altura en metros desde la que salen sus plumas.
@export var muzzle_height: float = 2.7

@export_group("Ritmo de ataques")
## Segundos de pausa entre un ataque y el siguiente, con agresividad 0.
@export var attack_pause: float = 2.2
## Multiplicador de esa pausa con agresividad 1.
@export var attack_pause_at_full_aggression: float = 0.45

@export_group("Renacer")
## Segundos que pasa en cenizas, invulnerable, entre una vida y la siguiente.
@export var rebirth_seconds: float = 4.0
## Radio del estallido al renacer y de su disco de aviso, en metros.
@export var rebirth_radius: float = 6.0
## Daño del estallido al renacer (valor base).
@export var rebirth_damage: float = 35.0
## Metros sobre el suelo por encima de los cuales el estallido no alcanza.
@export var rebirth_height_window: float = 1.8
## Segundos sin atacar justo después de renacer.
@export var post_rebirth_pause: float = 1.2
## Sonido al renacer (fila de Sfx.SOUND_LIBRARY).
@export var rebirth_sfx: StringName = &"phoenix_rebirth"

## Agresividad actual (0-1); la leen los ataques.
var aggression: float = 0.0
## El rig que vuela (nodo Visual); los ataques le piden poses.
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
var _arrival_left: float = 0.0
var _calm_seconds: float = 0.0
var _ashes_left: float = 0.0
var _pause_left: float = 0.0
var _stance_close: bool = true
var _stance_left: float = 0.0
var _orbit_sign: float = 1.0
var _focus: Node3D = null
var _focus_left: float = 0.0
var _moves: Array[MythosMove] = []
var _move: MythosMove = null
var _next_move: int = 0
## Factor de daño por poder ya aplicado a los ataques (ver _apply_plan).
var _power_damage_applied: float = 1.0
## La cinemática y la transformación del mapa que trajo consigo. Cuelgan de
## la arena y no de este cuerpo: siguen ahí cuando Mythos ya murió.
var _cinematic: MythosCinematic = null
var _transformation: HellTransformation = null

@onready var _scaling: StageBossScaling = $Scaling
@onready var _zones: MythosZones = $Zones


func _ready() -> void:
	# Antes de super(): BossBase anuncia el jefe a la barra del HUD en su
	# _ready, y la barra ya pregunta cuántas vidas tiene.
	_lives_total = _scaling.lives()
	super()
	_guard = _health as GuardedHealth
	if _guard == null:
		push_error("Mythos: the Health node must use guarded_health.gd")
	rig = _visual as MythosRig
	for child: Node in $Moves.get_children():
		var move := child as MythosMove
		if move != null:
			move.setup(self)
			_moves.append(move)
	_stance_left = close_seconds
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
		_tick_plain_arrival(delta)
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
	match _phase:
		Phase.ARRIVAL:
			return &"arrival"
		Phase.FLIGHT:
			return &"flight"
		Phase.MOVE:
			return &"move"
		Phase.ASHES:
			return &"ashes"
		_:
			return &"dead"


## Avance de la calma de llegada (0-1): el fénix baja del cielo.
func set_calm_progress(progress: float) -> void:
	rig.set_arrival_progress(progress)


## Termina la calma y empieza la pelea. `elapsed` son los segundos de juego
## que duró la calma y `skipped` si alguien la saltó.
func finish_calm(elapsed: float, skipped: bool) -> void:
	if _phase != Phase.ARRIVAL:
		return
	rig.end_arrival()
	rig.set_pose(MythosRig.Pose.FLY)
	_health.invulnerable = false
	_phase = Phase.FLIGHT
	_pause_left = attack_pause
	Sfx.play(arrival_sfx)
	Juice.shake(impact_shake_strength, impact_shake_duration)
	# Línea de log para los soaks: la pelea se mide desde aquí.
	print("%s fight started: calm=%.2fs skipped=%s at %.1fs" % [
			boss_title, elapsed, skipped, RunState.stage_time])


# --- lo que piden los ataques (nodos Moves) ---------------------------------------

## Punto del que salen sus plumas.
func muzzle_point() -> Vector3:
	return global_position + Vector3.UP * muzzle_height


## `point` llevado a un lugar de la arena donde cabe el cuerpo, a ras de suelo.
func safe_point(point: Vector3) -> Vector3:
	var safe := _safe_arena_point(point)
	safe.y = _ground_height(safe)
	return safe


## Lleva el cuerpo a `point`, a ras de suelo (el vuelo de la picada).
func glide_to(point: Vector3) -> void:
	global_position = Vector3(point.x, _ground_height(point), point.z)
	velocity = Vector3.ZERO


## Golpe de suelo avisado contra todos los raiders dentro de algún disco.
func strike_ground(spots: Array[Vector3], radius: float, height_window: float,
		damage: float) -> Array[Node3D]:
	return _resolve_ground_hit(spots, radius, height_window, damage)


## Marca una zona de fuego si cae en suelo caminable y el nodo Zones la deja
## salir (tope de zonas y distancia a los raiders). Devuelve true si salió.
func spawn_fire_zone(center: Vector3, radius: float, warn_seconds: float,
		burn_seconds: float, dps: float) -> bool:
	var at := _clamp_to_arena(center)
	if not _is_walkable(at):
		return false
	at.y = _ground_height(at)
	return _zones.mark(at, radius, warn_seconds, burn_seconds, dps)


# --- hooks de EnemyBase -----------------------------------------------------------

func _scale_attack_damage(multiplier: float) -> void:
	rebirth_damage *= multiplier
	for move: MythosMove in _moves:
		move.scale_damage(multiplier)


func _behavior_tick(delta: float) -> void:
	_fight_clock += delta
	_focus_left -= delta
	match _phase:
		Phase.FLIGHT:
			_life_clock += delta
			_pause_left = maxf(_pause_left - delta, 0.0)
			_stance_left -= delta
			if _stance_left <= 0.0:
				_set_stance(not _stance_close)
			for move: MythosMove in _moves:
				move.tick_cooldown(delta)
		Phase.MOVE:
			_life_clock += delta
			if _move == null or _move.tick(delta):
				_end_move()
		Phase.ASHES:
			_ashes_left -= delta
			if _ashes_left <= 0.0:
				_rebirth()


## Persigue a un raider por un rato y después elige otro al azar, así en
## co-op la presión no cae siempre sobre el mismo.
func _pick_target() -> Node3D:
	if _focus_left <= 0.0 or not is_instance_valid(_focus) \
			or not _focus.is_in_group(&"player"):
		_focus = Coop.random_player(get_tree())
		_focus_left = focus_seconds
	return _focus


func _movement_intent(seek: Vector3, distance: float) -> Vector3:
	if _phase != Phase.FLIGHT:
		return Vector3.ZERO
	if _stance_close:
		return seek if distance > close_distance else Vector3.ZERO
	# De lejos: se acomoda a far_distance y gira alrededor del raider.
	var tangent := Vector3(-seek.z, 0.0, seek.x) * _orbit_sign
	if distance > far_distance + far_band:
		return (seek + tangent * 0.5).normalized()
	if distance < far_distance - far_band:
		return (tangent * 0.5 - seek).normalized()
	return tangent * orbit_speed_factor


func _facing_direction(steer: Vector3, seek: Vector3) -> Vector3:
	if _phase != Phase.FLIGHT and _phase != Phase.MOVE:
		return Vector3.ZERO
	return seek if seek.length_squared() > 0.0001 else steer


func _combat_tick(player: Node3D, distance: float) -> void:
	if _phase != Phase.FLIGHT or _pause_left > 0.0:
		return
	# En rotación desde el último usado, para que no repita siempre el primero.
	for offset: int in _moves.size():
		var index := (_next_move + offset) % _moves.size()
		var move := _moves[index]
		if move.is_ready(_life, distance):
			_next_move = (index + 1) % _moves.size()
			_move = move
			_phase = Phase.MOVE
			move.begin(player)
			return


# --- llegada ----------------------------------------------------------------------

## Primer frame con Mythos ya ubicado y con su grado: calcula la primera
## vida y arranca la calma.
func _begin_arrival() -> void:
	if not is_inside_tree() or _phase != Phase.ARRIVAL:
		return
	_apply_plan(_scaling.plan_first_life(_health.max_hp, rebirth_seconds))
	var stage := RunRoot.stage_parent(get_tree())
	if transformation_scene != null and stage != null:
		_transformation = transformation_scene.instantiate() as HellTransformation
		if _transformation != null:
			stage.add_child(_transformation)
	if cinematic_scene != null and stage != null:
		_cinematic = cinematic_scene.instantiate() as MythosCinematic
		if _cinematic != null:
			stage.add_child(_cinematic)
	# Con cinemática, ella lleva el reloj de la calma y llama a finish_calm().
	_calm_seconds = _cinematic.calm_seconds if _cinematic != null else plain_arrival_seconds
	_arrival_left = 0.0 if _cinematic != null else plain_arrival_seconds
	set_calm_progress(0.0)
	print("%s calm started: seconds=%.2f at %.1fs" % [
			boss_title, _calm_seconds, RunState.stage_time])
	if _transformation != null:
		_transformation.begin(global_position, _calm_seconds)
	if _cinematic != null:
		_cinematic.play(self, _transformation)


## La entrada simple, sin cinemática: baja en plain_arrival_seconds.
func _tick_plain_arrival(delta: float) -> void:
	if _arrival_left <= 0.0:
		return
	_arrival_left -= delta
	set_calm_progress(1.0 - _arrival_left / maxf(_calm_seconds, 0.01))
	if _arrival_left <= 0.0:
		finish_calm(_calm_seconds, false)


# --- vidas ------------------------------------------------------------------------

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
	# El daño por poder se aplica como razón contra lo ya aplicado: el poder
	# de la party cambia entre vidas y no debe componerse.
	var wanted := 1.0 + plan.damage_bonus
	_scale_attack_damage(wanted / _power_damage_applied)
	_power_damage_applied = wanted
	print(_scaling.log_line(boss_title, plan))


## La vida actual se agotó y quedan más: cae en cenizas, invulnerable, y
## avisa el estallido con que va a renacer.
func _on_life_spent() -> void:
	if _phase == Phase.DEAD or _phase == Phase.ASHES:
		return
	print("%s life over: life=%d took=%.1fs" % [boss_title, _life, _life_clock])
	_cancel_move()
	_health.invulnerable = true
	_phase = Phase.ASHES
	_ashes_left = rebirth_seconds
	rig.set_pose(MythosRig.Pose.ASHES)
	Telegraph.spawn_disc(self, global_position, rebirth_radius, rebirth_seconds,
			telegraph_color)
	lives_changed.emit(lives_left(), _lives_total)


## Renace: vida nueva calculada con el daño que la party le hizo de verdad.
func _rebirth() -> void:
	var plan := _scaling.plan_next_life(_life + 1, _life_damage, _life_clock, _fight_clock)
	_life += 1
	_life_clock = 0.0
	_life_damage = 0.0
	_apply_plan(plan)
	strike_ground([global_position], rebirth_radius, rebirth_height_window, rebirth_damage)
	Sfx.play(rebirth_sfx)
	rig.set_pose(MythosRig.Pose.FLY)
	_health.invulnerable = false
	_phase = Phase.FLIGHT
	_pause_left = post_rebirth_pause
	_set_stance(false)
	for move: MythosMove in _moves:
		move.reset_cooldown()
	lives_changed.emit(lives_left(), _lives_total)


## Su última muerte (la única que emite Health.died): se apagan sus fuegos.
func _on_final_death() -> void:
	print("%s life over: life=%d took=%.1fs" % [boss_title, _life, _life_clock])
	print("%s fight over: took=%.1fs lives=%d" % [boss_title, _fight_clock, _lives_total])
	_cancel_move()
	_phase = Phase.DEAD
	_zones.extinguish_all()
	if _transformation != null and is_instance_valid(_transformation):
		_transformation.cool_down()
	if _cinematic != null and is_instance_valid(_cinematic):
		_cinematic.fade_out_song()
	lives_changed.emit(0, _lives_total)


# --- privados ---------------------------------------------------------------------

func _on_damaged(amount: float, _current: float) -> void:
	_life_damage += amount


func _end_move() -> void:
	var landed := _move is MythosDive
	if _move != null:
		_move.start_cooldown()
	_move = null
	_phase = Phase.FLIGHT
	_pause_left = attack_pause * lerpf(1.0, attack_pause_at_full_aggression, aggression)
	if landed:
		# La picada lo deja junto al raider: sigue de cerca desde ahí.
		_set_stance(true)


func _cancel_move() -> void:
	if _move != null:
		_move.cancel()
	_move = null


func _set_stance(close: bool) -> void:
	_stance_close = close
	_stance_left = close_seconds if close else far_seconds
	if not close:
		_orbit_sign = 1.0 if randf() < 0.5 else -1.0


func _ground_height(point: Vector3) -> float:
	var terrain := Terrain.find(get_tree())
	return terrain.height_at(point.x, point.z) if terrain != null else point.y

