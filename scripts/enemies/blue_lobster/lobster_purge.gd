class_name LobsterPurge
extends Node
## El barrido con que la Langosta Azul abre la pelea (nodo Purge de
## BlueLobster.tscn). La langosta pelea sola
## (EnemySpawner.mini_boss_fights_alone): en el instante en que termina su
## entrada se lleva a TODA la horda que quedaba en la arena, de una vez, antes
## de que ningún enemigo vuelva a moverse: nadie más llega a pegar. Los
## enemigos normales se van sin pagar nada (EnemyBase.vanish) y caen todos
## juntos mientras un anillo se abre desde ella; otro jefe que siguiera vivo
## muere con su pago de siempre. Los siervos poseídos de la party no se tocan.
## Línea de log para los soaks: "<título> purge: swept=… bosses=… at …".

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
			var health := Health.find_in(body)
			if health != null and not health.is_dead:
				health.take_damage(health.max_hp * boss_damage_factor)
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
	Sfx.play(wave_sfx)
	if ring_scene != null:
		ShockRing.spawn(ring_scene, boss.floor_point(origin), 1.0, ring_radius, ring_speed,
				0.0, 0.0, 0.0, boss)
	# Línea de log para los soaks: cuánta horda se llevó.
	print("%s purge: swept=%d bosses=%d at %.1fs" % [
			boss.boss_title, swept, bosses, RunState.stage_time])


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
