class_name BossSchedule
extends RefCounted
## Horario de jefes de una etapa, sobre RunState.stage_time: el jefe del bioma
## en boss_spawn_minute, su revancha Ancestral en elder_spawn_minute y luego
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

var _spawner: EnemySpawner = null
var _boss_spawned: bool = false
var _elder_spawned: bool = false
var _repeat_bosses_spawned: int = 0
var _bosses_alive: int = 0
var _relief_timer: float = 0.0


func _init(spawner: EnemySpawner) -> void:
	_spawner = spawner


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


## Dispara cada entrada del horario que ya venció. Cada una se dispara una
## vez por etapa, y la bandera solo se marca si el jefe llegó de verdad:
## spawn_boss aborta con toda la party derribada (sin ancla de anillo), y un
## hueco marcado como gastado perdería ese jefe para siempre.
func tick() -> void:
	var spawner := _spawner
	if spawner.boss_scene == null:
		return
	if not _boss_spawned and RunState.stage_time >= spawner.boss_spawn_minute * 60.0:
		_boss_spawned = spawn_boss(1.0) != null
	if not _elder_spawned and RunState.stage_time >= spawner.elder_spawn_minute * 60.0:
		var elder := spawn_boss(spawner.elder_stat_multiplier, spawner.elder_title)
		_elder_spawned = elder != null
		if elder != null:
			_watch_stage_boss(elder)
	# Después del Ancestral los jefes siguen volviendo, cada uno más fuerte.
	if _elder_spawned and spawner.boss_repeat_minutes > 0.0:
		var due := (spawner.elder_spawn_minute
				+ spawner.boss_repeat_minutes * float(_repeat_bosses_spawned + 1)) * 60.0
		if RunState.stage_time >= due:
			var rank := _repeat_bosses_spawned + 1
			if spawn_boss(spawner.elder_stat_multiplier
					* pow(spawner.boss_repeat_growth, float(rank)),
					spawner.boss_repeat_title_template % [spawner.elder_title, rank]) != null:
				_repeat_bosses_spawned = rank


## El jefe que entró a la arena, o null si algo abortó, para que el llamador
## reintente el hueco en otro tick. Devuelve la instancia porque la muerte
## del Ancestral abre la puerta de etapa.
func spawn_boss(stat_multiplier: float, title_override: String = "") -> BossBase:
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
	var node := spawner.boss_scene.instantiate()
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
	spawner.get_tree().call_group("boss_ui", "announce", spawner.boss_warning_text)
	# Log de una línea (convención de RunManager) para que los soaks
	# confirmen que el horario de jefes se disparó.
	print("Boss spawned: %s at %.1fs" % [boss.boss_title, RunState.stage_time])
	return boss


## El Ancestral es EL jefe de etapa: su muerte es la mitad de la puerta de
## etapa. Se ata a esa instancia y no al contador de jefes muertos, porque
## los jefes recurrentes posteriores no deben reabrir la puerta.
func _watch_stage_boss(boss: BossBase) -> void:
	var health := Health.find_in(boss)
	if health == null:
		RunState.stage_boss_dead = true
		return
	health.died.connect(_on_stage_boss_died, CONNECT_ONE_SHOT)


func _on_stage_boss_died() -> void:
	RunState.stage_boss_dead = true
	# Log de una línea (convención de RunManager) para los soaks headless.
	print("Stage boss slain: %s at %.1fs" % [_spawner.elder_title, RunState.stage_time])


func _on_boss_died() -> void:
	_bosses_alive = maxi(_bosses_alive - 1, 0)
	_relief_timer = _spawner.boss_relief_duration
	# Contador meta para misiones de jefes; se guarda al final de la partida.
	SaveData.bump("bosses_killed")
