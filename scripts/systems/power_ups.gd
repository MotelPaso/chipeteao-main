class_name PowerUps
extends Node
## Power-ups de un raider, montado en el Player junto a ItemBag y Stats. Sabe
## QUÉ está activo y por cuánto tiempo; los efectos usan canales que ya
## existen siempre que se puede:
##   filas de stats -> PlayerStats.add_timed_boon, con etiqueta para que una
##                     renovación se reemplace a sí misma y no se acumule
##   immortal       -> Health.invulnerable
##   reflect        -> Health.reflect_fraction
##   gold           -> Player.set_points_source (un factor con nombre, no
##                     una segunda billetera)
##   vampire        -> boon de robo de vida + permanent_max_hp guardado AQUÍ
##   flight         -> el Player lee has("flight") en cada tick de física
##   time_stop      -> EnemySpawner.freeze_enemies por el grupo
##   star           -> todas las demás filas a la vez, con el reloj de la
##                     ESTRELLA
##
## Power-ups distintos se ACUMULAN; el mismo se RENUEVA. Por eso cada
## consumidor por tipo se resincroniza desde has(kind) tras cualquier cambio
## en vez de apagarse al expirar: con acumulación, "se acabó la inmortalidad"
## y "ya no soy inmortal" son preguntas distintas (puede seguir una estrella).
##
## Sin nada activo no hay trabajo por frame: el sondeo de expiración vuelve
## de inmediato con la lista vacía.

signal active_changed

## Nombre con que «Fiebre del oro» registra su multiplicador de puntos en el
## Player (fuentes con nombre). Los números de cada power-up (multiplicador
## de oro, HP por baja del vampiro, fracción de Reflejo) viven en su fila de
## PowerUpCatalog.
const POINTS_SOURCE := "powerup_gold"
## Prefijo de etiqueta de los boons temporales de una fila, para que volver a
## tomarla limpie los suyos y solo los suyos.
const BOON_TAG_PREFIX := "powerup:"

## HP máx. permanente guardado por «Modo vampiro». Es un TOTAL GUARDADO que
## PlayerStats.recompute vuelve a sumar en cada reconstrucción; nunca se suma
## sobre un valor derivado, que _reset_derived borraría.
var permanent_max_hp: float = 0.0

## Filas vivas: {id, kind, expires_at}, en orden de recolección.
var _active: Array[Dictionary] = []
## Lo levanta RunState.stage_changed y se consume en el siguiente frame de
## física: para entonces la arena nueva ya existe, y _sync escribe en el
## spawner vivo y no en el que se acaba de liberar.
var _stage_changed: bool = false
## Un recompute por frame, por muchas bajas que caigan en él.
var _recompute_queued: bool = false
## Detección de flanco para el único consumidor que necesita el momento
## "recién terminó" y no un estado (el raider puede estar sobre una roca
## cuando se acaba el vuelo).
var _was_flying: bool = false


## El componente cruza el cambio de etapa con el raider; los nodos a los que
## publica no. Se marca en vez de sincronizar en el acto porque la arena aún
## se está construyendo cuando llega la señal.
func _ready() -> void:
	RunState.stage_changed.connect(func(_index: int, _map_id: String) -> void:
		_stage_changed = true)


## El componente PowerUps de un cuerpo, o null.
static func find_in(body: Node) -> PowerUps:
	if body == null:
		return null
	for child in body.get_children():
		if child is PowerUps:
			return child
	return null


## Otorga un power-up. LA puerta: el aviso, el log y el anuncio viven aquí,
## así una fuente nueva (drop, manantial, vendedor, ruleta) solo llama a
## esto. La estrella aplica cada fila componente, y por eso el anuncio se
## hace aquí y no en _apply_row.
func apply(powerup_id: String) -> void:
	var row := PowerUpCatalog.by_id(powerup_id)
	if row.is_empty():
		push_warning("PowerUps: unknown power-up '%s'" % powerup_id)
		return
	var duration := float(row.duration) * _duration_multiplier()
	if String(row.get("kind", "")) == "star":
		# Todo a la vez y con el reloj corto de la estrella: la estrella ES el
		# premio gordo, no una forma de tener buffs de veinte segundos.
		for component: Dictionary in PowerUpCatalog.star_components():
			_apply_row(component, duration)
	_apply_row(row, duration)
	_sync()
	_announce(row, duration)
	# Log de una línea (convención de RunManager) para los soaks headless.
	print("Power-up picked: %s" % powerup_id)


## Power-ups vivos como {id, kind, time_left}, en orden de recolección (los
## leen la fila del HUD y el mapa de Tab).
func active() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for entry: Dictionary in _active:
		rows.append({
			"id": String(entry.id), "kind": String(entry.kind),
			"time_left": maxf(float(entry.expires_at) - RunState.run_time, 0.0)})
	return rows


## Segundos que le quedan a la fila viva más larga de `kind`, o 0.0 si no
## corre ninguna. Es la contraparte de has() para quien necesita el reloj.
func _remaining(kind: String) -> float:
	var left := 0.0
	for entry: Dictionary in _active:
		if String(entry.get("kind", "")) == kind:
			left = maxf(left, float(entry.expires_at) - RunState.run_time)
	return left


## True mientras alguna fila viva tenga este tipo de comportamiento. La
## estrella los enciende todos, así que los consumidores preguntan esto y
## nunca "¿corre la estrella?".
func has(kind: String) -> bool:
	for entry: Dictionary in _active:
		if String(entry.kind) == kind:
			return true
	return false


func is_active(powerup_id: String) -> bool:
	for entry: Dictionary in _active:
		if String(entry.id) == powerup_id:
			return true
	return false


func count() -> int:
	return _active.size()


## ItemBag.on_weapon_kill reenvía cada baja de las armas de este raider. Hoy
## solo escucha «Modo vampiro».
func on_kill() -> void:
	if not has("vampire"):
		return
	permanent_max_hp += _live_value("vampire", "max_hp_per_kill")
	_request_recompute()


func _physics_process(_delta: float) -> void:
	if _active.is_empty():
		return
	if _stage_changed:
		# La arena (y su spawner) se reemplazó: vuelve a publicar cada estado
		# por tipo en los nodos recién construidos.
		_stage_changed = false
		_sync()
	var expired := false
	for i in range(_active.size() - 1, -1, -1):
		if RunState.run_time >= float(_active[i].expires_at):
			_active.remove_at(i)
			expired = true
	if expired:
		_sync()


## Registra (o renueva) una fila por `duration` segundos y emite sus boons
## de stats. Renovar NUNCA acorta: tomar el mismo power-up con ocho segundos
## restantes y una duración menor sería una pérdida.
func _apply_row(row: Dictionary, duration: float) -> void:
	var powerup_id := String(row.id)
	var expires_at := RunState.run_time + duration
	var found := -1
	for i in _active.size():
		if String(_active[i].id) == powerup_id:
			found = i
			break
	if found >= 0:
		_active[found].expires_at = maxf(float(_active[found].expires_at), expires_at)
		expires_at = float(_active[found].expires_at)
	else:
		_active.append({"id": powerup_id, "kind": String(row.get("kind", "")),
				"expires_at": expires_at})
	var stats := PlayerStats.find_in(get_parent())
	if stats != null:
		var tag := BOON_TAG_PREFIX + powerup_id
		# Primero sus propios boons: sin esto una renovación sumaría una
		# segunda copia de cada efecto y la primera expiración quitaría la mitad.
		stats.clear_timed_boons(tag)
		for effect: Dictionary in row.get("effects", [] as Array):
			stats.add_timed_boon(String(effect.stat), float(effect.amount),
					expires_at - RunState.run_time, tag)
	if String(row.get("kind", "")) == "time_stop":
		# Por el grupo, como toda llamada entre escenas aquí; el spawner es
		# dueño del conjunto congelado, de su reloj de deshielo y de los dos
		# avisos (true = anunciar el comienzo).
		get_tree().call_group("enemy_spawner", "freeze_enemies", duration, true)


## Publica cada estado por tipo desde el conjunto ACTUAL de filas vivas.
## Idempotente y barato, y se llama tras cualquier cambio: apagar los
## consumidores al expirar quitaría la inmortalidad con una estrella activa.
func _sync() -> void:
	var body := get_parent()
	var health := Health.find_in(body)
	if health != null:
		health.invulnerable = has("immortal")
		health.reflect_fraction = _live_value("reflect", "reflect_fraction") \
				if has("reflect") else 0.0
	if body != null and body.has_method("set_points_source"):
		if has("gold"):
			body.call("set_points_source", POINTS_SOURCE, _live_value("gold", "points_multiplier"))
		else:
			body.call("clear_points_source", POINTS_SOURCE)
	# time_stop vive en un nodo que NO sobrevive al cambio de etapa: el
	# spawner se libera con su arena y el siguiente nace con el reloj de
	# congelado vacío, mientras este componente (y la casilla del HUD) cruzan
	# con el raider. Se vuelve a empujar desde la fila viva para que el
	# congelado cruce con la party; freeze_enemies toma el MÁXIMO, así que
	# repetirlo no cuesta nada.
	var freeze_left := _remaining("time_stop")
	if freeze_left > 0.0:
		get_tree().call_group("enemy_spawner", "freeze_enemies", freeze_left)
	var flying := has("flight")
	if _was_flying and not flying and body != null and body.has_method("end_flight"):
		# Un flanco, no un estado: el raider puede estar sobre una celda
		# bloqueada y hay que dejarlo en un lugar caminable.
		body.call("end_flight")
	_was_flying = flying
	active_changed.emit()


## Un número de la fila de catálogo del primer power-up vivo de este tipo
## (la estrella enciende las filas normales, así que también vale con ella);
## 0.0 si no hay ninguno.
func _live_value(kind: String, field: String) -> float:
	for entry: Dictionary in _active:
		if String(entry.kind) == kind:
			return float(PowerUpCatalog.by_id(String(entry.id)).get(field, 0.0))
	return 0.0


func _announce(row: Dictionary, duration: float) -> void:
	get_tree().call_group("hud", "show_loot", String(row.display_name),
			"%s (%d s)" % [String(row.get("description", "")), roundi(duration)],
			row.get("color", Color.WHITE) as Color, _player_index())


func _player_index() -> int:
	var body := get_parent()
	if body == null:
		return 0
	var index: Variant = body.get("player_index")
	return int(index) if index != null else 0


func _duration_multiplier() -> float:
	var stats := PlayerStats.find_in(get_parent())
	return stats.duration_multiplier if stats != null else 1.0


## Agrupado: un arma de área puede sumar una docena de bajas vampiro en un
## frame, y cada una reconstruiría toda la capa de stats.
func _request_recompute() -> void:
	if _recompute_queued:
		return
	_recompute_queued = true
	_flush_recompute.call_deferred()


func _flush_recompute() -> void:
	_recompute_queued = false
	var stats := PlayerStats.find_in(get_parent())
	if stats != null:
		stats.recompute()
