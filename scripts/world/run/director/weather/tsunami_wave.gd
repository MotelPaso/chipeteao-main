class_name TsunamiWave
extends RefCounted
## La ola del tsunami: un muro de enemigos que llega surfeando desde un lado,
## gira para perseguir al jugador, lo arrolla (sin daño, con un gran empujón)
## y suelta a los enemigos un poco más allá. Los cuerpos viajan
## apagados (sin IA ni colisión) pegados al terreno, así ninguno queda en el
## aire; solo su dibujo sube para formar la cresta. A quien alcanza la
## cresta lo lanza por el aire. Los números son exports del nodo Weather
## (grupo «Tsunami»); este ayudante solo los lee.

## Enemigos que se crean por frame: cuarenta en un solo frame dan un tirón.
const SPAWN_PER_FRAME: int = 6
## Intentos por enemigo de encontrarle un hueco caminable en la ola.
const SLOT_TRIES: int = 4
## Parte del camino hasta el jugador en que la ola deja de sumar enemigos,
## para que ninguno nazca encima de él.
const SPAWN_UNTIL: float = 0.5

var _host: WeatherDirector
var _layout: StageLayout
## Cada jinete: {"enemy", "lateral", "row", "offset", "phase"}.
var _riders: Array[Dictionary] = []
var _dir: Vector2 = Vector2.ZERO
var _side: Vector2 = Vector2.ZERO
var _front: Vector2 = Vector2.ZERO
var _traveled: float = 0.0
var _travel: float = 0.0
var _time: float = 0.0
var _to_spawn: int = 0
var _foam_left: float = 0.0
var _color: Color = Color.WHITE
var _hit: Array[Node3D] = []
## El jugador al que persigue la ola; deja de girar cuando lo arrolla.
var _target: Node3D = null


func _init(host: WeatherDirector, layout: StageLayout) -> void:
	_host = host
	_layout = layout


## Arma la ola: viene desde `angle` (radianes, visto desde `target`), lo
## persigue y lleva `count` enemigos.
func start(target: Node3D, angle: float, count: int, color: Color) -> void:
	var out := Vector2(cos(angle), sin(angle))
	_target = target
	_dir = -out
	_side = Vector2(-_dir.y, _dir.x)
	var origin := target.global_position if target != null else Vector3.ZERO
	_front = Vector2(origin.x, origin.z) + out * _host.tsunami_start_distance
	_travel = _host.tsunami_max_travel
	_to_spawn = count
	_color = color


func is_done() -> bool:
	return _to_spawn <= 0 and _riders.is_empty()


func tick(delta: float) -> void:
	if is_done():
		return
	_spawn_some()
	_time += delta
	_steer(delta)
	var step := _host.tsunami_speed * delta
	_front += _dir * step
	_traveled += step
	_move_riders()
	_hit_raiders()
	_foam(delta)
	if _traveled >= _travel:
		release_all()


## Gira la ola hacia su jugador, con tope de giro por segundo.
func _steer(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var to_target := Vector2(_target.global_position.x, _target.global_position.z) - _front
	if to_target.length_squared() < 0.01:
		return
	var turn := clampf(_dir.angle_to(to_target), -_host.tsunami_turn_speed * delta,
			_host.tsunami_turn_speed * delta)
	_dir = _dir.rotated(turn)
	_side = Vector2(-_dir.y, _dir.x)


## Suelta a todos donde estén: el dibujo vuelve a su sitio y despiertan.
func release_all() -> void:
	for rider: Dictionary in _riders:
		var enemy := _enemy_of(rider)
		if enemy != null:
			enemy.set_visual_lift(0.0)
			enemy.process_mode = Node.PROCESS_MODE_INHERIT
	_riders.clear()
	_to_spawn = 0


func _spawn_some() -> void:
	if _to_spawn <= 0:
		return
	if _traveled > _host.tsunami_start_distance * SPAWN_UNTIL:
		_to_spawn = 0
		return
	var spawner := _host.get_tree().get_first_node_in_group(&"enemy_spawner") as EnemySpawner
	if spawner == null:
		_to_spawn = 0
		return
	var rows := maxi(_host.tsunami_rows, 1)
	var points: Array[Vector3] = []
	var slots: Array[Vector2] = []
	var wanted := mini(_to_spawn, SPAWN_PER_FRAME)
	for i in wanted * SLOT_TRIES:
		if points.size() >= wanted:
			break
		var slot := Vector2(randf_range(-0.5, 0.5) * _host.tsunami_width, randi() % rows)
		var pos := _slot_xz(slot)
		if _layout.walkable(Vector3(pos.x, 0.0, pos.y)):
			points.append(Vector3(pos.x, 0.0, pos.y))
			slots.append(slot)
	var made := spawner.spawn_bodies_at(points, true)
	_to_spawn -= made.size()
	for i in made.size():
		var enemy := made[i]
		var ground := _layout.terrain_height(Vector2(enemy.global_position.x, enemy.global_position.z))
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
		_riders.append({
			"enemy": enemy, "lateral": slots[i].x, "row": int(slots[i].y),
			"offset": enemy.global_position.y - ground, "phase": randf() * TAU,
		})
	# Tope de vivos alcanzado: la ola sale con los que ya lleva.
	if made.size() < points.size():
		_to_spawn = 0


## Punto XZ de un hueco de la ola: `slot.x` metros al costado y la fila
## `slot.y` (0 = la de adelante) hacia atrás.
func _slot_xz(slot: Vector2) -> Vector2:
	return _front + _side * slot.x - _dir * (slot.y * _host.tsunami_row_gap)


func _move_riders() -> void:
	var rows := maxi(_host.tsunami_rows, 1)
	for i in range(_riders.size() - 1, -1, -1):
		var rider := _riders[i]
		var enemy := _enemy_of(rider)
		if enemy == null or not enemy.is_inside_tree():
			_riders.remove_at(i)
			continue
		var xz := _slot_xz(Vector2(float(rider["lateral"]), float(rider["row"])))
		var y := _layout.terrain_height(xz) + float(rider["offset"])
		enemy.global_position = Vector3(xz.x, y, xz.y)
		enemy.look_at(enemy.global_position + Vector3(_dir.x, 0.0, _dir.y), Vector3.UP)
		# Las filas de atrás van más alto: así se ve la cresta de la ola.
		var row_t := float(rider["row"]) / float(maxi(rows - 1, 1))
		var bob := sin(_time * _host.tsunami_bob_speed + float(rider["phase"])) * _host.tsunami_bob
		enemy.set_visual_lift(lerpf(_host.tsunami_crest_low, _host.tsunami_crest_high, row_t) + bob)


func _hit_raiders() -> void:
	for body: Node3D in _host.get_tree().get_nodes_in_group(&"player"):
		if _hit.has(body) or not is_instance_valid(body):
			continue
		var rel := Vector2(body.global_position.x, body.global_position.z) - _front
		var ahead := rel.dot(_dir)
		var across := absf(rel.dot(_side))
		if ahead > 0.6 or ahead < -_host.tsunami_row_gap * _host.tsunami_rows \
				or across > _host.tsunami_width * 0.5:
			continue
		_hit.append(body)
		# Arrolló a su jugador: deja de perseguir y sigue derecho un tramo.
		if body == _target:
			_target = null
			_travel = minf(_travel, _traveled + _host.tsunami_pass_distance)
		var knockback := body.get_node_or_null(^"Knockback") as PlayerKnockback
		if knockback != null:
			var behind := body.global_position - Vector3(_dir.x, 0.0, _dir.y) * 2.0
			knockback.launch_from(behind, _host.tsunami_push_speed, _host.tsunami_push_lift)
		Juice.shake(_host.tsunami_hit_shake)


## Espuma: chispas del color de la ola sobre jinetes al azar.
func _foam(delta: float) -> void:
	_foam_left -= delta
	if _foam_left > 0.0 or _riders.is_empty():
		return
	_foam_left = _host.tsunami_foam_interval
	var enemy := _enemy_of(_riders[randi() % _riders.size()])
	if enemy != null:
		Juice.burst(enemy.global_position + Vector3.UP * _host.tsunami_crest_high,
				_color, _host.tsunami_foam_count)


## El enemigo del jinete, o null si ya murió: un arma puede matarlo en
## plena ola, y convertir un objeto liberado con `as` es un error.
func _enemy_of(rider: Dictionary) -> EnemyBase:
	var enemy: Variant = rider["enemy"]
	if not is_instance_valid(enemy):
		return null
	return enemy as EnemyBase
