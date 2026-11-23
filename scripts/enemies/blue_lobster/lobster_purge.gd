class_name LobsterPurge
extends Node
## El barrido con que la Langosta Azul abre la pelea (nodo Purge de
## BlueLobster.tscn). La langosta pelea sola: en el instante en que termina su
## entrada se lleva a TODA la horda que quedaba, de una vez, antes de que
## ningún enemigo vuelva a moverse: nadie más llega a pegar. Si pelea en su
## arena propia (BossArenaHost), esa horda es la que quedó en el mapa de la
## etapa: cuando el equipo vuelve, ya no está. Los
## enemigos normales se van sin pagar nada (EnemyBase.vanish) y caen todos
## juntos mientras un anillo se abre desde ella; otro jefe que siguiera vivo
## muere con su pago de siempre, salvo el jefe de etapa y un jefe de varias
## vidas (GuardedHealth): el barrido nunca le quita una vida a nadie ni le
## salta su pelea. Los siervos poseídos de la party no se tocan.
## Línea de log para los soaks: "<título> purge: swept=… bosses=… at …", donde
## bosses son los jefes que el golpe mató (uno invulnerable no cuenta).

@export_group("Barrido")
## Cuántos de los enemigos barridos, los más cercanos a ella, sueltan un salpicón.
@export var max_bursts: int = 24
## Color de esos salpicones.
@export var burst_color: Color = Color(0.45, 0.85, 1.0)
## Gotas de cada salpicón.
@export var burst_amount: int = 8
## Daño con que mata a otro jefe, en veces su vida máxima.
@export var boss_damage_factor: float = 10.0
## Sonido del barrido (fila de Sfx.SOUND_LIBRARY).
@export var wave_sfx: StringName = &"lobster_rumble"
## Escena del anillo que dibuja el barrido (ShockRing sin daño, sale de Pools). Vacío = sin anillo.
@export var ring_scene: PackedScene = preload("res://scenes/fx/ShockRing.tscn")
## Radio en metros hasta el que se abre el anillo.
@export var ring_radius: float = 46.0
## Metros por segundo a los que se abre.
@export var ring_speed: float = 42.0


## Barre la arena desde `boss`, ya. Con la horda permitida no hace nada.
func begin(boss: BlueLobster) -> void:
	if not EnemySpawner.is_holding(get_tree()):
		return
	var origin := boss.global_position
	var swept := 0
	var bosses := 0
	for body: EnemyBase in _horde(boss, origin):
		if body is BossBase:
			if _strike_boss(body as BossBase):
				bosses += 1
			continue
		var at := body.aim_point()
		body.vanish()
		swept += 1
		if swept <= max_bursts:
			Juice.burst(at, burst_color, burst_amount)
	# Las saetas enemigas que venían en vuelo vuelven al pool.
	for node: Node in get_tree().get_nodes_in_group(&"enemy_projectiles"):
		var bolt := node as Node3D
		if bolt != null:
			Pools.release(bolt)
	# En su arena propia la horda quedó en el mapa de la etapa, que espera
	# fuera del árbol: el anfitrión se la lleva de ahí, y los jefes que
	# murieron cuando el equipo partió cuentan igual.
	var host := BossArenaHost.find(get_tree())
	if host != null and host.is_away():
		swept += host.sweep_stage_horde()
		bosses += host.rivals_slain()
	Sfx.play(wave_sfx)
	if ring_scene != null:
		ShockRing.spawn(ring_scene, boss.floor_point(origin), 1.0, ring_radius, ring_speed,
				0.0, 0.0, 0.0, boss)
	# Línea de log para los soaks: cuánta horda se llevó.
	print("%s purge: swept=%d bosses=%d at %.1fs" % [
			boss.boss_title, swept, bosses, RunState.stage_time])


## Mata a otro jefe con su pago de siempre. Al jefe de etapa y a uno de varias
## vidas no los toca: el golpe le quitaría una vida entera. True si el golpe
## lo mató (a uno invulnerable no le hace nada).
func _strike_boss(body: BossBase) -> bool:
	if body.is_in_group(BossSchedule.STAGE_BOSS_GROUP):
		return false
	var health := Health.find_in(body)
	if health == null or health.is_dead or health is GuardedHealth:
		return false
	health.take_damage(health.max_hp * boss_damage_factor)
	return health.is_dead


## Los enemigos vivos menos `boss`, de más cerca a más lejos de `origin`.
func _horde(boss: BlueLobster, origin: Vector3) -> Array[EnemyBase]:
	var rows: Array[Array] = []
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		var body := node as EnemyBase
		if body == null or body == boss or not body.is_inside_tree():
			continue
		var offset := body.global_position - origin
		offset.y = 0.0
		rows.append([offset.length_squared(), body])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var horde: Array[EnemyBase] = []
	for row: Array in rows:
		horde.append(row[1])
	return horde
