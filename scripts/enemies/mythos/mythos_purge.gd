class_name MythosPurge
extends Node
## El barrido de fuego con que Mythos abre la pelea (nodo Purge de
## Mythos.tscn). Mythos pelea solo (EnemySpawner.stage_boss_fights_alone):
## cuando termina la calma, una ola sale de él y quema a la horda que quedaba
## en la arena, de cerca a lejos. Los enemigos normales se van sin pagar nada
## (EnemyBase.vanish); otro jefe que siguiera vivo muere con su pago de
## siempre. Los siervos poseídos de la party no se tocan.

@export_group("Barrido")
## Segundos entre el fin de la calma y la salida de la ola.
@export var start_delay: float = 0.35
## Metros por segundo a los que avanza la ola.
@export var wave_speed: float = 34.0
## Segundos que como mucho tarda la ola en alcanzar al enemigo más lejano.
@export var max_seconds: float = 2.5
## Tope de enemigos quemados por frame de física (reparte el costo de una horda grande).
@export var max_per_frame: int = 16
## Uno de cada cuántos quemados suelta un estallido de brasas (1 = todos).
@export var burst_every: int = 3
## Color de esos estallidos.
@export var burst_color: Color = Color(1.0, 0.5, 0.12)
## Brasas de cada estallido.
@export var burst_amount: int = 8
## Daño con que mata a otro jefe, en veces su vida máxima.
@export var boss_damage_factor: float = 10.0
## Sonido de la ola al salir (fila de Sfx.SOUND_LIBRARY).
@export var wave_sfx: StringName = &"fire_whoosh"

var _boss: Mythos = null
var _origin: Vector3 = Vector3.ZERO
var _clock: float = 0.0
var _started: bool = false
## Lo que falta quemar, de cerca a lejos: cada entrada es [metros, cuerpo].
var _queue: Array[Array] = []
var _burned: int = 0
var _bosses: int = 0


func _ready() -> void:
	set_physics_process(false)


## Arranca el barrido desde `boss`. Con la horda permitida no hace nada.
func begin(boss: Mythos) -> void:
	if not EnemySpawner.is_holding(get_tree()):
		return
	_boss = boss
	_origin = boss.global_position
	_clock = -start_delay
	_started = false
	_burned = 0
	_bosses = 0
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	_clock += delta
	if _clock < 0.0:
		return
	if not _started:
		_started = true
		_collect()
		Sfx.play(wave_sfx)
	var reach := _clock * wave_speed if _clock < max_seconds else INF
	var budget := max_per_frame
	while budget > 0 and not _queue.is_empty() and float(_queue[0][0]) <= reach:
		var entry: Array = _queue.pop_front()
		budget -= 1
		_burn(entry[1])
	if _queue.is_empty():
		# Línea de log para los soaks: cuánta horda se llevó la ola.
		print("%s purge: burned=%d bosses=%d took=%.2fs" % [
				_boss.boss_title if is_instance_valid(_boss) else "Boss",
				_burned, _bosses, _clock])
		set_physics_process(false)


## Junta a los enemigos vivos, ordenados por distancia, y devuelve al pool las
## saetas enemigas que venían en vuelo.
func _collect() -> void:
	_queue.clear()
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		var body := node as EnemyBase
		if body == null or body == _boss:
			continue
		var offset := body.global_position - _origin
		offset.y = 0.0
		_queue.append([offset.length(), body])
	_queue.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for node: Node in get_tree().get_nodes_in_group(&"enemy_projectiles"):
		var bolt := node as Node3D
		if bolt != null:
			Pools.release(bolt)


func _burn(body: Variant) -> void:
	if not is_instance_valid(body):
		return
	var enemy := body as EnemyBase
	if enemy == null or not enemy.is_inside_tree():
		return
	var at := enemy.aim_point()
	if enemy is BossBase:
		var health := Health.find_in(enemy)
		if health != null and not health.is_dead:
			health.take_damage(health.max_hp * boss_damage_factor)
			# Solo cuenta si lo mató: a uno invulnerable el golpe no le hace nada.
			if health.is_dead:
				_bosses += 1
		return
	enemy.vanish()
	_burned += 1
	if burst_every > 0 and _burned % burst_every == 0:
		Juice.burst(at, burst_color, burst_amount)
