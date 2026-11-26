class_name MiniBossCalm
extends RefCounted
## Lo que MiniBossProbe mide de la CALMA de la cinemática de un minijefe: con
## el mundo congelado ninguna vida cambia y nada nace. La calma es lo que dura
## la cinemática (su is_calm_active()), del rapto en el mapa al principio de
## la pelea, y a mitad de camino el mapa de la etapa sale del árbol.
##
## Por eso las vidas se guardan POR REFERENCIA en el primer frame de la calma
## y se vuelven a leer esas mismas en el ÚLTIMO frame en que la cinemática
## seguía en curso, estén dentro o fuera del árbol: lo que el minijefe haga
## en el instante en que empieza a pelear (barrer a la horda) ya no es la
## calma. Una vida que no estaba en el primer frame cuenta como nacida, salvo
## la del propio minijefe, que nace con la cinemática ya empezada.
## Líneas de log:
##   "Probe mini calm: frames=… seconds=… healths=… changed=… born=…
##   enemies=a->b bolts=a->b shots=a->b". `frames` son frames de proceso (60
##   por segundo de juego con --fixed-fps 60); los conteos a->b son los
##   cuerpos y proyectiles del primer frame y cuántos de ESOS siguen existiendo.
##   "Probe mini frames: over_33ms=… covered_silent=… worst=…ms detail=…": los
##   frames de la cinemática que tardaron más de SLOW_FRAME_MS de reloj real y
##   cuántos cayeron con la pantalla tapada y sin canción. Tienen que ser
##   todos: ahí va el cambio de mundo, y un tirón en cualquier otro momento
##   atrasaría un corte respecto de la canción.

## Grupos de cuerpos con Health de la partida.
const HEALTH_GROUPS: Array[StringName] = [&"player", &"downed_players", &"enemies", &"boss",
		&"possessed"]
## Grupos que se cuentan aparte: enemigos, saetas enemigas y disparos.
const COUNT_GROUPS: Array[StringName] = [&"enemies", &"enemy_projectiles", &"player_shots"]
## Grupo del minijefe vivo (BossSchedule.MINI_BOSS_GROUP).
const MINI_BOSS_GROUP: StringName = &"mini_boss"
## Un frame más lento que esto (ms) es un tirón que el jugador nota (dos vsync de 60 Hz).
const SLOW_FRAME_MS: float = 33.3

var _tree: SceneTree = null
## Las vidas del primer frame, con lo que marcaban entonces y en la última muestra.
var _healths: Array[Health] = []
var _first_hp: Array[float] = []
var _last_hp: Array[float] = []
## Los cuerpos y proyectiles del primer frame, por grupo de COUNT_GROUPS.
var _counted: Array[Array] = []
var _last_alive: Array[int] = []
var _born: int = 0
var _first_frame: int = 0
var _last_frame: int = 0
var _seconds: float = 0.0
## Reloj real del último frame dibujado de la cinemática y sus frames lentos:
## cada uno es [ms, paso, pantalla tapada, canción sonando].
var _frame_usec: int = 0
var _slow_frames: Array[Array] = []


func _init(tree: SceneTree) -> void:
	_tree = tree


## Primer frame de la calma.
func begin() -> void:
	_healths = _live_healths()
	_first_hp.clear()
	for health: Health in _healths:
		_first_hp.append(health.current_hp)
	_last_hp = _first_hp.duplicate()
	_counted.clear()
	_last_alive.clear()
	for group: StringName in COUNT_GROUPS:
		var nodes := _tree.get_nodes_in_group(group)
		_counted.append(nodes)
		_last_alive.append(nodes.size())
	_born = 0
	_first_frame = Engine.get_process_frames()
	_last_frame = _first_frame
	_seconds = 0.0
	_slow_frames.clear()


## Un frame más con la cinemática en curso; lleva `seconds` segundos de juego.
func sample(seconds: float) -> void:
	_last_frame = Engine.get_process_frames()
	_seconds = seconds
	for index: int in _healths.size():
		# NAN: una vida que ya no existe cambió (nada se libera durante la calma).
		_last_hp[index] = _healths[index].current_hp if is_instance_valid(_healths[index]) else NAN
	for index: int in _counted.size():
		var alive := 0
		for node: Variant in _counted[index]:
			if is_instance_valid(node):
				alive += 1
		_last_alive[index] = alive
	_born = 0
	for health: Health in _live_healths():
		if not _healths.has(health):
			_born += 1


## La calma terminó: imprime qué cambió entre su primer frame y el último.
func report() -> void:
	var changed := 0
	for index: int in _first_hp.size():
		if is_nan(_last_hp[index]) or not is_equal_approx(_last_hp[index], _first_hp[index]):
			changed += 1
	print(("Probe mini calm: frames=%d seconds=%.2f healths=%d changed=%d born=%d"
			+ " enemies=%d->%d bolts=%d->%d shots=%d->%d") % [
			_last_frame - _first_frame + 1, _seconds, _first_hp.size(), changed, _born,
			(_counted[0] as Array).size(), _last_alive[0], (_counted[1] as Array).size(),
			_last_alive[1], (_counted[2] as Array).size(), _last_alive[2]])
	var hidden := 0
	var worst := 0.0
	var detail := PackedStringArray()
	for entry: Array in _slow_frames:
		worst = maxf(worst, float(entry[0]))
		if bool(entry[2]) and not bool(entry[3]):
			hidden += 1
		detail.append("%s:%.0fms:covered=%s:song=%s" % [entry[1], float(entry[0]), entry[2],
				entry[3]])
	print("Probe mini frames: over_33ms=%d covered_silent=%d worst=%.1fms detail=%s" % [
			_slow_frames.size(), hidden, worst,
			",".join(detail) if not detail.is_empty() else "none"])


## Un frame dibujado, con `cinematic` en curso (null = ninguna) y si la
## canción suena. Mide con el reloj real y anota los frames lentos. El frame
## en que la cinemática toma la pantalla no cuenta: se mide desde el siguiente.
func frame(cinematic: Node, song_playing: bool) -> void:
	if cinematic == null:
		_frame_usec = 0
		return
	var now := Time.get_ticks_usec()
	if _frame_usec != 0:
		var ms := float(now - _frame_usec) / 1000.0
		if ms > SLOW_FRAME_MS:
			_slow_frames.append([ms, String(cinematic.call(&"act_name")),
					bool(cinematic.call(&"is_screen_covered")), song_playing])
	_frame_usec = now


## Las vidas de los cuerpos de la partida que están en el árbol, menos la del
## minijefe.
func _live_healths() -> Array[Health]:
	var found: Array[Health] = []
	for group: StringName in HEALTH_GROUPS:
		for node: Node in _tree.get_nodes_in_group(group):
			if node.is_in_group(MINI_BOSS_GROUP):
				continue
			var health := Health.find_in(node)
			if health != null and not found.has(health):
				found.append(health)
	return found
