class_name BossSchedule
extends RefCounted
## Horario de jefes de una etapa, sobre RunState.stage_time: el jefe del bioma
## en boss_spawn_minute, el jefe de etapa en elder_spawn_minute y luego
## un jefe recurrente cada boss_repeat_minutes, cada uno más fuerte. También
## lleva el ritmo más lento de los spawns mientras vive un jefe y el respiro
## tras su muerte.
## Cada arena trae su propio spawner, así que este estado empieza limpio en
## cada etapa y el reloj es el de la etapa, no el de la partida.
## Los valores son exports del spawner (grupo «Jefes»): cada arena los guarda
## en su nodo EnemySpawner.
## No procesa solo: EnemySpawner llama tick_relief() y tick() desde su
## _physics_process, así que detener al spawner (run_root.gd,
## run_manager.gd) también lo detiene.
## Una arena puede traer su propio jefe de etapa (stage_boss_scene): llega
## en el lugar del Ancestral y, mientras vive, los recurrentes esperan. Si
## además pelea solo (stage_boss_fights_alone), tampoco sale ningún enemigo
## normal hasta que muere y pasa el respiro (spawns_held).
## Una arena puede traer además un MINIJEFE (mini_boss_scene): llega en
## mini_boss_spawn_minute, sin aviso, y el jefe del bioma espera a que muera
## y pase su respiro.

## Interruptor del harness: BONK_STAGE_BOSS_AT=<segundos> trae al jefe de
## etapa en ese segundo de la etapa y no en elder_spawn_minute. Solo
## pruebas; nada del juego lo pone.
const STAGE_BOSS_AT_ENV: String = "BONK_STAGE_BOSS_AT"
## Grupo del jefe de etapa mientras vive (lo lee el harness).
const STAGE_BOSS_GROUP: StringName = &"stage_boss"
## Interruptor del harness: BONK_MINI_BOSS_AT=<segundos> trae al minijefe en
## ese segundo de la etapa y no en mini_boss_spawn_minute. Solo pruebas; nada
## del juego lo pone.
const MINI_BOSS_AT_ENV: String = "BONK_MINI_BOSS_AT"
## Grupo del minijefe (lo lee el harness; nunca es el del jefe de etapa).
const MINI_BOSS_GROUP: StringName = &"mini_boss"

var _spawner: EnemySpawner = null
var _boss_spawned: bool = false
var _elder_spawned: bool = false
var _repeat_bosses_spawned: int = 0
var _bosses_alive: int = 0
var _relief_timer: float = 0.0
## Segundo de etapa forzado por el harness para el jefe de etapa (-1 = sin forzar).
var _stage_boss_at: float = -1.0
## True mientras vive un jefe de etapa PROPIO (stage_boss_scene).
var _own_stage_boss_alive: bool = false
## Segundo de etapa antes del cual no sale otro recurrente. Solo lo mueven
## las arenas con jefe de etapa propio: si su pelea pasó de largo varios
## turnos, los recurrentes atrasados llegan de a uno y no todos juntos.
var _next_repeat_not_before: float = 0.0
## Segundos de respiro SIN spawns que quedan tras la muerte del jefe de etapa
## que peleó solo.
var _alone_breather_left: float = 0.0
## El minijefe de esta etapa: si ya llegó, quién es y el segundo de etapa
## forzado por el harness (-1 = sin forzar).
var _mini_boss_spawned: bool = false
var _mini_boss: BossBase = null
var _mini_boss_at: float = -1.0


func _init(spawner: EnemySpawner) -> void:
	_spawner = spawner
	var forced := OS.get_environment(STAGE_BOSS_AT_ENV)
	if forced.is_valid_float():
		_stage_boss_at = maxf(forced.to_float(), 0.0)
		print("BossSchedule: stage boss forced at %.0fs" % _stage_boss_at)
	var forced_mini := OS.get_environment(MINI_BOSS_AT_ENV)
	if forced_mini.is_valid_float():
		_mini_boss_at = maxf(forced_mini.to_float(), 0.0)
		print("BossSchedule: mini boss forced at %.0fs" % _mini_boss_at)


## Factor del intervalo de los spawns regulares: más lento con un jefe vivo
## y durante el respiro tras su muerte; 1.0 si no hay ninguno de los dos.
func interval_factor() -> float:
	if _bosses_alive > 0:
		return _spawner.boss_alive_interval_multiplier
	if _relief_timer > 0.0:
		return _spawner.boss_relief_interval_multiplier
	return 1.0


## Descuenta el reloj del respiro.
func tick_relief(delta: float) -> void:
	_relief_timer = maxf(_relief_timer - delta, 0.0)
	if _alone_breather_left > 0.0:
		_alone_breather_left -= delta
		if _alone_breather_left <= 0.0:
			# Log de una línea para los soaks: la horda vuelve desde aquí.
			print("Spawns resumed at %.1fs" % RunState.stage_time)


## True mientras el jefe de etapa propio pelea solo
## (EnemySpawner.stage_boss_fights_alone) y durante el respiro tras su
## muerte: el spawner no saca nada.
func spawns_held() -> bool:
	return _spawner.stage_boss_fights_alone \
			and (_own_stage_boss_alive or _alone_breather_left > 0.0)


## Dispara cada entrada del horario que ya venció. Cada una se dispara una
## vez por etapa, y la bandera solo se marca si el jefe llegó de verdad:
## spawn_boss aborta con toda la party derribada (sin ancla de anillo), y un
## hueco marcado como gastado perdería ese jefe para siempre.
func tick() -> void:
	var spawner := _spawner
	_tick_mini_boss()
	if spawner.boss_scene == null:
		return
	# Con el jefe de etapa peleando solo, o con el minijefe por llegar o en la
	# arena, el jefe del bioma espera su turno.
	if not _boss_spawned and not spawns_held() and not _mini_boss_holds_boss() \
			and RunState.stage_time >= spawner.boss_spawn_minute * 60.0:
		_boss_spawned = spawn_boss(1.0) != null
	if not _elder_spawned and RunState.stage_time >= _stage_boss_due():
		var elder := _spawn_stage_boss()
		_elder_spawned = elder != null
		if elder != null:
			_watch_stage_boss(elder)
	# Después del jefe de etapa los jefes siguen volviendo, cada uno más fuerte.
	if _elder_spawned and not _repeats_held() and spawner.boss_repeat_minutes > 0.0 \
			and RunState.stage_time >= _next_repeat_not_before:
		var due := (spawner.elder_spawn_minute
				+ spawner.boss_repeat_minutes * float(_repeat_bosses_spawned + 1)) * 60.0
		if RunState.stage_time >= due:
			var rank := _repeat_bosses_spawned + 1
			if spawn_boss(spawner.elder_stat_multiplier
					* pow(spawner.boss_repeat_growth, float(rank)),
					spawner.boss_repeat_title_template % [spawner.elder_title, rank]) != null:
				_repeat_bosses_spawned = rank
				if spawner.stage_boss_scene != null:
					_next_repeat_not_before = RunState.stage_time \
							+ spawner.boss_repeat_minutes * 60.0


## El jefe que entró a la arena, o null si algo abortó, para que el llamador
## reintente el hueco en otro tick. Devuelve la instancia porque la muerte
## del Ancestral abre la puerta de etapa. Con `warn` apagado llega sin el
## aviso del HUD.
func spawn_boss(stat_multiplier: float, title_override: String = "",
		scene_override: PackedScene = null, warn: bool = true) -> BossBase:
	var spawner := _spawner
	var player := Coop.random_player(spawner.get_tree())
	if player == null:
		return null
	# Se ubica ANTES de que el jefe exista: un anillo sin punto libre
	# reintenta en el próximo tick en vez de anunciar un jefe que no vino.
	var at := spawner.ring_position(player)
	if not spawner.has_player_clearance(at):
		spawner.register_clearance_skip()
		return null
	var scene := scene_override if scene_override != null else spawner.boss_scene
	var node := scene.instantiate()
	var boss := node as BossBase
	if boss == null:
		node.free()
		push_warning("EnemySpawner: boss scene root does not extend BossBase.")
		return null
	if not title_override.is_empty():
		# Antes de add_child: el jefe anuncia su título al HUD en _ready.
		boss.boss_title = title_override
	spawner.add_child(boss)
	boss.global_position = at
	# Todos los factores entran en UNA llamada a apply_tier, así
	# tier_body_scale se aplica una vez por jefe y un jefe base (todo 1.0)
	# queda exactamente base. Los tres canales son distintos a propósito:
	#   HP     — revancha x vuelta x dificultad x tamaño de party. Un jefe es
	#            una pelea larga, para la party que lo esperó.
	#   daño   — lo mismo SIN la party: cuatro cuerpos ya reparten golpes.
	#   pago   — revancha x vuelta: RunState.difficulty_xp_multiplier() ya
	#            paga la parte de dificultad al recoger las gemas.
	var payout_multiplier := stat_multiplier * spawner.lap_xp_factor()
	var damage_multiplier := stat_multiplier * spawner.lap_damage_factor() \
			* (1.0 + RunState.difficulty_bonus)
	var hp_multiplier := stat_multiplier * spawner.lap_hp_factor() \
			* (1.0 + RunState.difficulty_bonus) \
			* (1.0 + spawner.coop_boss_hp_per_extra_player * spawner.coop_extra())
	# is_equal_approx y no "> 1.0": un factor puede quedar legítimamente bajo
	# 1.0 y no debe ignorarse.
	if not (is_equal_approx(hp_multiplier, 1.0) and is_equal_approx(damage_multiplier, 1.0)
			and is_equal_approx(payout_multiplier, 1.0)):
		boss.apply_tier(hp_multiplier, damage_multiplier, payout_multiplier)
	_bosses_alive += 1
	var health := Health.find_in(boss)
	if health != null:
		health.died.connect(_on_boss_died)
	if warn:
		spawner.get_tree().call_group("boss_ui", "announce", spawner.boss_warning_text)
	# Log de una línea (convención de RunManager) para que los soaks
	# confirmen que el horario de jefes se disparó.
	print("Boss spawned: %s at %.1fs" % [boss.boss_title, RunState.stage_time])
	return boss


## El minijefe de la arena: llega una vez por etapa y sin aviso. Como el
## jefe del bioma, espera mientras un jefe de etapa pelea solo.
func _tick_mini_boss() -> void:
	var spawner := _spawner
	if spawner.mini_boss_scene == null or _mini_boss_spawned or spawns_held() \
			or RunState.stage_time < _mini_boss_due():
		return
	var boss := spawn_boss(1.0, "", spawner.mini_boss_scene, false)
	if boss == null:
		return
	_mini_boss_spawned = true
	_mini_boss = boss
	boss.add_to_group(MINI_BOSS_GROUP)


## Segundo de etapa en que llega el minijefe.
func _mini_boss_due() -> float:
	return _mini_boss_at if _mini_boss_at >= 0.0 else _spawner.mini_boss_spawn_minute * 60.0


## True mientras el jefe del bioma tiene que esperar al minijefe: ya le toca
## llegar y todavía no llegó, sigue vivo, o corre el respiro tras su muerte.
func _mini_boss_holds_boss() -> bool:
	if _spawner.mini_boss_scene == null:
		return false
	if not _mini_boss_spawned:
		return RunState.stage_time >= _mini_boss_due()
	return _mini_boss_alive() or _relief_timer > 0.0


func _mini_boss_alive() -> bool:
	if _mini_boss == null or not is_instance_valid(_mini_boss) \
			or not _mini_boss.is_inside_tree():
		return false
	var health := Health.find_in(_mini_boss)
	return health != null and not health.is_dead


## Segundo de etapa en que llega el jefe de etapa.
func _stage_boss_due() -> float:
	return _stage_boss_at if _stage_boss_at >= 0.0 else _spawner.elder_spawn_minute * 60.0


## El jefe de etapa: el propio de la arena si trae uno (con su título y sin
## multiplicador de revancha: los números de su escena ya son los de esta
## pelea), o la revancha Ancestral del jefe del bioma.
func _spawn_stage_boss() -> BossBase:
	if _spawner.stage_boss_scene != null:
		return spawn_boss(1.0, "", _spawner.stage_boss_scene)
	return spawn_boss(_spawner.elder_stat_multiplier, _spawner.elder_title)


## Un jefe de etapa propio pelea solo: mientras vive, y durante el respiro
## tras su muerte, los recurrentes esperan. Las arenas sin stage_boss_scene
## conservan su horario de siempre.
func _repeats_held() -> bool:
	return _spawner.stage_boss_scene != null \
			and (_own_stage_boss_alive or _relief_timer > 0.0)


## El jefe de etapa es LA mitad de jefe de la puerta de etapa. Se ata a esa
## instancia y no al contador de jefes muertos, porque los jefes recurrentes
## posteriores no deben reabrir la puerta.
func _watch_stage_boss(boss: BossBase) -> void:
	boss.add_to_group(STAGE_BOSS_GROUP)
	var health := Health.find_in(boss)
	if health == null:
		RunState.stage_boss_dead = true
		return
	_own_stage_boss_alive = _spawner.stage_boss_scene != null
	if spawns_held():
		print("Spawns held: stage boss fights alone at %.1fs" % RunState.stage_time)
	# El título viaja en la conexión: la línea nombra al jefe que cayó.
	health.died.connect(_on_stage_boss_died.bind(boss.boss_title), CONNECT_ONE_SHOT)


func _on_stage_boss_died(title: String) -> void:
	RunState.stage_boss_dead = true
	if spawns_held():
		_alone_breather_left = _spawner.boss_relief_duration
	_own_stage_boss_alive = false
	# Log de una línea (convención de RunManager) para los soaks headless.
	print("Stage boss slain: %s at %.1fs" % [title, RunState.stage_time])


func _on_boss_died() -> void:
	_bosses_alive = maxi(_bosses_alive - 1, 0)
	_relief_timer = _spawner.boss_relief_duration
	# Contador meta para misiones de jefes; se guarda al final de la partida.
	SaveData.bump("bosses_killed")
