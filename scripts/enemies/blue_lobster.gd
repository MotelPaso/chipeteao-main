class_name BlueLobster
extends LobsterBody
## Langosta Azul: el minijefe del Bosque Hueco. Llega en el hueco del
## minijefe (EnemySpawner.mini_boss_scene) y pelea en medio de la horda, en
## una sola fase.
## Su vida no es un número fijo: el nodo Scaling (StageBossScaling) la calcula
## con el daño real de la party para que la pelea dure lo mismo con cualquier
## build; la vida de Health en BlueLobster.tscn es el PISO. Si la pelea se
## alarga, se desgasta sola (nodo Burnout). Cómo ronda lo lleva el nodo Stalk
## y la llegada, el nodo Arrival.
## El nombre de este archivo es su id de bestiario (kills_blue_lobster): no se
## renombra.
## Contratos por nombre: bar_title / bar_color (BossBar), fight_state y
## move_name (el harness), finish_entrance (el nodo Arrival, al terminar la
## llegada) y las líneas "<título> scaling:", "fight started:" y "fight over:"
## que leen los soaks.

enum Phase { ARRIVAL, STALK, MOVE, DEAD }

## Nombre de cada fase para el harness, en el orden de Phase.
const PHASE_NAMES: Array[StringName] = [&"arrival", &"stalk", &"move", &"dead"]

@export_group("Aspecto")
## Color de su barra de vida.
@export var bar_fill_color: Color = Color(0.2, 0.62, 1.0)
## Color del estallido de esquirlas cuando muere.
@export var burst_color: Color = Color(0.12, 0.45, 1.0)

var _phase: Phase = Phase.ARRIVAL
## Segundos de pelea desde que terminó la llegada, y el daño que le hizo la party.
var _fight_clock: float = 0.0
var _fight_damage: float = 0.0
## Segundos de pelea tras los que empieza a desgastarse (0 = nunca).
var _burnout_after: float = 0.0

@onready var _scaling: StageBossScaling = $Scaling
@onready var _burnout: BossBurnout = $Burnout
@onready var _arrival: LobsterArrival = $Arrival


func _ready() -> void:
	super()
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
	super(delta)


# --- contratos por nombre ---------------------------------------------------------

## En qué anda: "arrival", "stalk", "move" o "dead" (lo lee el harness).
func fight_state() -> StringName:
	return PHASE_NAMES[_phase]


## Nombre del ataque en curso, o "" si no hay ninguno (lo lee el harness).
func move_name() -> StringName:
	return &""


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
	_apply_plan(_scaling.plan_first_life(_health.max_hp, 0.0))
	_health.invulnerable = false
	_phase = Phase.STALK
	show_presence()
	# Línea de log para los soaks: la pelea se mide desde aquí.
	print("%s fight started: entrance=%.2fs skipped=%s at %.1fs" % [
			boss_title, elapsed, skipped, RunState.stage_time])


# --- hooks de EnemyBase -----------------------------------------------------------

func _behavior_tick(delta: float) -> void:
	if not is_fighting():
		return
	_fight_clock += delta
	_burnout.tick(delta, _fight_clock)
	if not is_fighting():
		# El desgaste acaba de terminar la pelea.
		return
	_stalk.tick(delta)


# --- privados ---------------------------------------------------------------------

## Primer frame con la langosta ya ubicada y con su grado: arranca la llegada.
func _begin_arrival() -> void:
	if not is_inside_tree() or _phase != Phase.ARRIVAL:
		return
	_arrival.begin(self)


## Aplica el plan de la pelea: vida máxima, agresividad, desgaste y daño extra.
func _apply_plan(plan: StageBossScaling.LifePlan) -> void:
	_health.max_hp = plan.hp
	_health.heal_full()
	aggression = plan.aggression
	_burnout_after = plan.burnout_after
	_burnout.arm(_health, boss_title, plan.burnout_after, plan.burnout_drain)
	_scale_attack_damage(1.0 + plan.damage_bonus)
	print(_scaling.log_line(boss_title, plan))


## Suma el daño de la party (el del desgaste no cuenta).
func _on_damaged(amount: float, _current: float) -> void:
	if not _burnout.draining:
		_fight_damage += amount


func _on_final_death() -> void:
	# Línea de log para los soaks: cuánto duró la pelea, con qué daño real de
	# la party y si la terminó el desgaste.
	var burned := _burnout_after > 0.0 and _fight_clock >= _burnout_after
	print("%s fight over: took=%.1fs damage=%.0f dps=%.1f burnout=%s at %.1fs" % [
			boss_title, _fight_clock, _fight_damage, _fight_damage / maxf(_fight_clock, 0.1),
			burned, RunState.stage_time])
	_phase = Phase.DEAD
	_arrival.on_boss_dead()
