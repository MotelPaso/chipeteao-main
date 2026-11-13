class_name StageBossSwitches
extends RefCounted
## La mitad de StageBossProbe que ACTÚA sobre la partida. Solo hace algo con
## variables de entorno nuevas; sin ellas no toca nada:
##   BONK_CINEMATIC_SKIP=1  mantiene la acción de saltar apenas pasa un
##                          segundo de cinemática
##   BONK_PAUSE_AT=<s>      a ese segundo abre el menú de pausa, mueve el
##                          slider de Música, espera y lo cierra
##   BONK_EXTRACT_AT=<s>    extrae la party a ese segundo
##   BONK_WIPE_AT=<s>       golpe letal a toda la party a ese segundo
##   BONK_WEATHER_AT=a,b,c  fuerza el clima de BONK_WEATHER_NOW (o
##                          blood_moon) en esos segundos, en lugar de los
##                          30 s de siempre
##   BONK_ADVANCE_AT=a,b,c  cambia de etapa en esos segundos, como si la
##                          party cruzara el portal de salida, esté como
##                          esté la etapa (RunRoot.advance_stage)
##   BONK_UI_DISMISS=1      cierra por código la ruleta o el vendedor que
##                          lleve más de 3 s abierto. Sin ventana se resuelven
##                          solos; con ventana esperan a alguien, y una
##                          corrida larga de capturas se quedaría pausada ahí
## Esos segundos son del RELOJ DEL PROBE (frames de física / 60) y no de
## RunState.run_time, que se detiene durante la calma: con run_time no se
## podría caer en medio de una cinemática.

const SKIP_ENV := "BONK_CINEMATIC_SKIP"
const PAUSE_AT_ENV := "BONK_PAUSE_AT"
const EXTRACT_AT_ENV := "BONK_EXTRACT_AT"
const WIPE_AT_ENV := "BONK_WIPE_AT"
const WEATHER_AT_ENV := "BONK_WEATHER_AT"
const WEATHER_ID_ENV := "BONK_WEATHER_NOW"
const DISMISS_ENV := "BONK_UI_DISMISS"
const ADVANCE_AT_ENV := "BONK_ADVANCE_AT"
const DEFAULT_WEATHER := "blood_moon"

## Segundos de cinemática antes de empezar a mantener el salto.
const SKIP_AFTER: float = 1.0
## Segundos que el menú de pausa queda abierto.
const PAUSE_HOLD: float = 3.0
## Segundos que un panel cerrable puede tener la pausa antes de cerrarlo.
const DISMISS_AFTER: float = 3.0
## Valores (0-100) que prueba el slider de Música con la pausa abierta.
const MUSIC_SLIDER_VALUES: Array[float] = [35.0, 80.0]

enum PauseStep { IDLE, OPENING, HOLDING, CLOSING, DONE }

var _tree: SceneTree = null
var _now: float = 0.0
var _skip: bool = false
var _skip_held: StringName = &""
var _pause_at: float = -1.0
var _pause_step: PauseStep = PauseStep.IDLE
var _pause_left: float = 0.0
var _pause_calm: float = 0.0
var _extract_at: float = -1.0
var _wipe_at: float = -1.0
var _exit_done: bool = false
var _weather_times: Array[float] = []
var _weather_id: String = DEFAULT_WEATHER
var _advance_times: Array[float] = []
var _dismiss: bool = false
var _blocked_for: float = 0.0
## Acciones globales que hay que soltar en el frame siguiente a apretarlas.
var _release_next: Array[StringName] = []


func _init(host: Node) -> void:
	_tree = host.get_tree()
	_skip = OS.get_environment(SKIP_ENV) == "1"
	_pause_at = _env_seconds(PAUSE_AT_ENV)
	_extract_at = _env_seconds(EXTRACT_AT_ENV)
	_wipe_at = _env_seconds(WIPE_AT_ENV)
	_weather_times = _env_times(WEATHER_AT_ENV)
	_advance_times = _env_times(ADVANCE_AT_ENV)
	_dismiss = OS.get_environment(DISMISS_ENV) == "1"
	var weather := OS.get_environment(WEATHER_ID_ENV)
	if not weather.is_empty():
		_weather_id = weather


## True si BONK_WEATHER_AT decide cuándo se fuerza el clima.
func owns_weather_timing() -> bool:
	return not _weather_times.is_empty()


## Un frame de física. `now` es el reloj del probe y `boss_state` el
## fight_state() del jefe de etapa ("" si no hay).
func tick(delta: float, now: float, boss_state: StringName) -> void:
	_now = now
	for action: StringName in _release_next:
		_send_global(action, false)
	_release_next.clear()
	_tick_skip()
	_tick_pause(delta)
	_tick_exits(boss_state)
	_tick_weather()
	_tick_advance(boss_state)
	_tick_dismiss(delta)


func _cinematic() -> Node:
	for node: Node in _tree.get_nodes_in_group(&"boss_cinematic"):
		if node.has_method(&"is_calm_active") and bool(node.call(&"is_calm_active")):
			return node
	return null


## BONK_CINEMATIC_SKIP: mantiene la acción real de saltar del slot 0.
func _tick_skip() -> void:
	if not _skip:
		return
	var cinematic := _cinematic()
	var want := cinematic != null and float(cinematic.call(&"calm_elapsed")) >= SKIP_AFTER
	if want:
		if _skip_held.is_empty():
			_skip_held = Coop.action(0, cinematic.call(&"skip_action"))
			print("Probe skip: holding %s at calm=%.2fs" % [
					_skip_held, float(cinematic.call(&"calm_elapsed"))])
		# Se reafirma cada frame: el recorrido del probe toca y suelta esta
		# misma acción cuando espera junto a un interactuable.
		Input.action_press(_skip_held)
	elif not _skip_held.is_empty():
		Input.action_release(_skip_held)
		_skip_held = &""


## BONK_PAUSE_AT: abre el menú de pausa de verdad (la acción pause_game),
## prueba el slider de Música, espera PAUSE_HOLD y lo cierra. Imprime el
## reloj de la calma antes y después: si la pausa la congela, no cambia.
func _tick_pause(delta: float) -> void:
	match _pause_step:
		PauseStep.IDLE:
			if _pause_at >= 0.0 and _now >= _pause_at:
				_pause_step = PauseStep.OPENING
				_pause_calm = _calm_elapsed()
				_press_global(&"pause_game")
		PauseStep.OPENING:
			_pause_step = PauseStep.HOLDING
			_pause_left = PAUSE_HOLD
			print("Probe pause: opened paused=%s calm=%.2fs song_paused=%s at %.1fs" % [
					_tree.paused, _pause_calm, _song_paused(), _now])
			_test_music_slider()
		PauseStep.HOLDING:
			_pause_left -= delta
			if _pause_left <= 0.0:
				_pause_step = PauseStep.CLOSING
				print("Probe pause: closing paused=%s calm=%.2fs held=%.1fs" % [
						_tree.paused, _calm_elapsed(), PAUSE_HOLD])
				_press_global(&"pause_game")
		PauseStep.CLOSING:
			_pause_step = PauseStep.DONE
			print("Probe pause: closed paused=%s calm=%.2fs song_paused=%s at %.1fs" % [
					_tree.paused, _calm_elapsed(), _song_paused(), _now])


func _calm_elapsed() -> float:
	for node: Node in _tree.get_nodes_in_group(&"boss_cinematic"):
		if node.has_method(&"calm_elapsed"):
			return float(node.call(&"calm_elapsed"))
	return -1.0


func _song_paused() -> String:
	for node: Node in _tree.get_nodes_in_group(&"boss_music"):
		var player := node as AudioStreamPlayer
		if player != null:
			return str(player.stream_paused or not player.can_process())
	return "n/a"


## Mueve el slider de Música del panel de ajustes y lee el bus: prueba que
## el slider llega al volumen. Lo devuelve a donde estaba.
func _test_music_slider() -> void:
	for node: Node in _tree.get_nodes_in_group(BlockingUi.GROUP):
		var panel := node.get_node_or_null("%SettingsPanel")
		if panel == null:
			continue
		var slider := panel.get_node_or_null("%MusicSlider") as HSlider
		if slider == null:
			continue
		var bus := AudioServer.get_bus_index(&"Music")
		var before := slider.value
		for value: float in MUSIC_SLIDER_VALUES:
			slider.value = value
			print("Probe music slider: value=%.0f bus_db=%.1f muted=%s" % [
					slider.value, AudioServer.get_bus_volume_db(bus),
					AudioServer.is_bus_mute(bus)])
		slider.value = before
		return
	print("Probe music slider: not found")


## BONK_EXTRACT_AT y BONK_WIPE_AT: las dos salidas que terminan la partida.
func _tick_exits(boss_state: StringName) -> void:
	if _exit_done:
		return
	if _extract_at >= 0.0 and _now >= _extract_at:
		_exit_done = true
		print("Probe exit: extract at %.1fs state=%s" % [_now, boss_state])
		_tree.call_group("run_manager", "extract_run")
	elif _wipe_at >= 0.0 and _now >= _wipe_at:
		_exit_done = true
		print("Probe exit: wipe at %.1fs state=%s" % [_now, boss_state])
		for group: StringName in [&"player", &"downed_players"]:
			for node: Node in _tree.get_nodes_in_group(group):
				var health := Health.find_in(node)
				if health != null and not health.is_dead:
					health.invulnerable = false
					health.take_damage(health.max_hp * 10.0 + 1000.0)


## BONK_WEATHER_AT: fuerza el clima en cada segundo pedido.
func _tick_weather() -> void:
	while not _weather_times.is_empty() and _now >= _weather_times[0]:
		_weather_times.remove_at(0)
		print("Probe weather: forced %s at %.1fs" % [_weather_id, _now])
		_tree.call_group("world_director", "start_sky_event", _weather_id)


## BONK_ADVANCE_AT: un cambio de etapa en cada segundo pedido.
func _tick_advance(boss_state: StringName) -> void:
	while not _advance_times.is_empty() and _now >= _advance_times[0]:
		_advance_times.remove_at(0)
		print("Probe advance: stage change at %.1fs state=%s" % [_now, boss_state])
		_tree.call_group("run_root", "advance_stage")


## BONK_UI_DISMISS: cierra los paneles cerrables (ruleta, vendedor) que
## lleven DISMISS_AFTER segundos con la pausa tomada.
func _tick_dismiss(delta: float) -> void:
	if not _dismiss:
		return
	var open: Array[Node] = []
	for node: Node in _tree.get_nodes_in_group(BlockingUi.CLOSABLE_GROUP):
		if node.has_method(&"is_blocking") and bool(node.call(&"is_blocking")):
			open.append(node)
	_blocked_for = _blocked_for + delta if not open.is_empty() else 0.0
	if _blocked_for < DISMISS_AFTER:
		return
	_blocked_for = 0.0
	for node: Node in open:
		print("Probe dismiss: closing %s at %.1fs" % [node.name, _now])
		node.call(&"dismiss")


func _press_global(action: StringName) -> void:
	_send_global(action, true)
	_release_next.append(action)


## Una pulsación PARSEADA de una acción sin slot (pause_game): es lo que ve
## _unhandled_input del menú de pausa.
func _send_global(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


## Lista ordenada de segundos de una variable "a,b,c".
static func _env_times(env_name: String) -> Array[float]:
	var times: Array[float] = []
	for entry: String in OS.get_environment(env_name).split(",", false):
		if entry.strip_edges().is_valid_float():
			times.append(entry.strip_edges().to_float())
	times.sort()
	return times


static func _env_seconds(env_name: String) -> float:
	var text := OS.get_environment(env_name)
	return maxf(text.to_float(), 0.0) if text.is_valid_float() else -1.0
