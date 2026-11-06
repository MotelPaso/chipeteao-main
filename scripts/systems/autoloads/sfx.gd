extends Node
## Autoload "Sfx": reproducción con pool del set de sonidos sintetizados de
## assets/audio/sfx (los genera scripts/tools/generate_sfx.gd; todo es audio
## original). Los sonidos de un disparo van por play() a un pool rotativo de
## AudioStreamPlayers, así los golpes que se solapan no se cortan entre sí;
## los bucles (zumbido de santuario, zumbido del láser) tienen UNA voz
## compartida con conteo de referencias por id, vía
## acquire_loop()/release_loop() (play_loop/stop_loop son lo mismo con otro
## nombre). Los ids repetitivos llevan una variación de tono al azar, los
## que se disparan mucho tienen límite por segundo para que la horda no
## sature, y todo sale por un bus "Sfx" creado en código (sin ventana, los
## reproductores mezclan en el driver falso).
## Procesa siempre, para que cartas y avisos finales suenen en pausa.
## Orden del RNG: play() tira randf_range solo para ids con variación de
## tono y solo si pasa el límite por segundo; ese orden lo usan los soaks
## con semilla.

const BUS_NAME := &"Sfx"
## Bus de los fondos ambientales de las arenas (ambient_bed.gd sale por
## él). Se crea aquí junto al bus Sfx para que los buses hechos en código
## tengan un solo dueño; el autoload Settings solo les pone volumen.
const AMBIENT_BUS_NAME := &"Ambient"

const STREAMS: Dictionary[StringName, AudioStream] = {
	&"hit_soft": preload("res://assets/audio/sfx/hit_soft.wav"),
	&"hit_crit": preload("res://assets/audio/sfx/hit_crit.wav"),
	&"enemy_die": preload("res://assets/audio/sfx/enemy_die.wav"),
	&"gem_pickup": preload("res://assets/audio/sfx/gem_pickup.wav"),
	&"heal": preload("res://assets/audio/sfx/heal.wav"),
	&"level_up": preload("res://assets/audio/sfx/level_up.wav"),
	&"card_pick": preload("res://assets/audio/sfx/card_pick.wav"),
	&"player_hurt": preload("res://assets/audio/sfx/player_hurt.wav"),
	&"dodge": preload("res://assets/audio/sfx/dodge.wav"),
	&"slide": preload("res://assets/audio/sfx/slide.wav"),
	&"shrine_channel": preload("res://assets/audio/sfx/shrine_channel.wav"),
	&"shrine_done": preload("res://assets/audio/sfx/shrine_done.wav"),
	&"chest_open": preload("res://assets/audio/sfx/chest_open.wav"),
	&"boss_roar": preload("res://assets/audio/sfx/boss_roar.wav"),
	&"boss_roar_2": preload("res://assets/audio/sfx/boss_roar_2.wav"),
	&"boss_die": preload("res://assets/audio/sfx/boss_die.wav"),
	&"streak": preload("res://assets/audio/sfx/streak.wav"),
	&"laser_hum": preload("res://assets/audio/sfx/laser_hum.wav"),
	&"burrow_pop": preload("res://assets/audio/sfx/burrow_pop.wav"),
	&"secret_fanfare": preload("res://assets/audio/sfx/secret_fanfare.wav"),
}

## Ids para play_loop(): en _ready se hace una copia LOOP_FORWARD de cada
## uno, porque los wav generados no traen metadatos de bucle.
const LOOP_IDS: Array[StringName] = [&"shrine_channel", &"laser_hum"]

## Voces para sonidos de un disparo; los que se solapan rotan entre ellas.
@export var pool_size: int = 12
## Variación de tono al azar por defecto (fracción: 0.08 = ±8%) para
## jittered_ids.
@export var default_pitch_jitter: float = 0.08
## Ids repetitivos que reciben default_pitch_jitter cuando play() se llama
## sin variación explícita.
@export var jittered_ids: Array[StringName] = [
	&"hit_soft", &"hit_crit", &"enemy_die", &"gem_pickup", &"burrow_pop", &"heal",
]
## Tope de reproducciones por segundo móvil, por id; los que no están no
## tienen tope.
@export var rate_limits: Dictionary[StringName, int] = {
	&"hit_soft": 10,
	&"hit_crit": 10,
	&"enemy_die": 12,
	&"gem_pickup": 10,
	&"burrow_pop": 8,
	&"heal": 4,
	&"player_hurt": 6,
}
## Volumen base por id, en dB, para que el hit_soft constante quede muy por
## debajo de los avisos raros; el volume_db_offset de play() se suma encima.
@export var id_volume_db: Dictionary[StringName, float] = {
	&"hit_soft": -14.0,
	&"hit_crit": -7.0,
	&"enemy_die": -10.0,
	&"gem_pickup": -12.0,
	&"heal": -7.0,
	&"level_up": -4.0,
	&"card_pick": -6.0,
	&"player_hurt": -5.0,
	&"dodge": -8.0,
	&"slide": -10.0,
	&"shrine_channel": -10.0,
	&"shrine_done": -5.0,
	&"chest_open": -5.0,
	&"boss_roar": -3.0,
	&"boss_roar_2": -3.0,
	&"boss_die": -2.0,
	&"streak": -6.0,
	&"laser_hum": -16.0,
	&"burrow_pop": -8.0,
	&"secret_fanfare": -3.0,
}


## Ventana móvil de un segundo con las marcas de tiempo de un id con tope.
class RateWindow:
	extends RefCounted
	var times: Array[float] = []


var _pool: Array[AudioStreamPlayer] = []
## Marca de inicio por voz (segundos); decide qué voz se roba (ver abajo).
var _started_at: Array[float] = []
var _next_voice: int = 0
var _rate_state: Dictionary[StringName, RateWindow] = {}
var _loop_players: Dictionary[StringName, AudioStreamPlayer] = {}
## Dueños vivos de cada bucle por id (varios láseres comparten un zumbido).
var _loop_refcounts: Dictionary[StringName, int] = {}
## COPIAS en bucle de los streams de LOOP_IDS; ver _ready.
var _loop_streams: Dictionary[StringName, AudioStream] = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# pool_size se puede ajustar: con 0, play() indexaría un array vacío y
	# _alloc_voice haría un módulo por cero en el primer sonido.
	pool_size = maxi(pool_size, 1)
	_setup_bus()
	for i in pool_size:
		var voice := AudioStreamPlayer.new()
		voice.bus = BUS_NAME
		add_child(voice)
		_pool.append(voice)
		_started_at.append(-1000.0)
	for id: StringName in LOOP_IDS:
		var wav := STREAMS.get(id) as AudioStreamWAV
		if wav == null:
			continue
		# Bucle sobre una COPIA: el stream precargado es la entrada global
		# de ResourceLoader, y forzarle LOOP_FORWARD haría que cada play() de
		# un disparo del mismo archivo sonara en bucle para siempre y se
		# quedara con una voz del pool.
		var looped := wav.duplicate() as AudioStreamWAV
		looped.loop_mode = AudioStreamWAV.LOOP_FORWARD
		looped.loop_begin = 0
		looped.loop_end = int(round(looped.get_length() * float(looped.mix_rate)))
		_loop_streams[id] = looped


## Los autoloads solo salen del árbol al cerrar la app. Lo que siga sonando
## lo libera el hilo de audio, que compite con el cierre del motor y pierde
## ("leaked AudioStreamPlayback" al salir sin ventana): se detiene cada voz y
## se espera un periodo de mezcla del driver falso (~93 ms) antes de seguir.
func _exit_tree() -> void:
	for voice: AudioStreamPlayer in _pool:
		voice.stop()
	stop_all_loops()
	OS.delay_msec(200)


## Dispara un sonido. volume_db_offset se suma al volumen base del id.
## pitch_jitter < 0 significa "el del id" (default_pitch_jitter para
## jittered_ids, ninguno para el resto); pasa una fracción para forzarlo.
func play(id: StringName, volume_db_offset: float = 0.0, pitch_jitter: float = -1.0) -> void:
	var stream := STREAMS.get(id) as AudioStream
	if stream == null:
		push_warning("Sfx: unknown sound id '%s'" % id)
		return
	if _pool.is_empty():
		return
	var now := _now()
	if not _rate_check(id, now):
		return
	var idx := _alloc_voice()
	var voice := _pool[idx]
	voice.stream = stream
	voice.volume_db = _id_volume(id) + volume_db_offset
	voice.pitch_scale = _rolled_pitch(id, pitch_jitter)
	voice.play()
	_started_at[idx] = now


## Toma la voz en bucle compartida de `id` y la arranca con el primer
## dueño. Con conteo de referencias, porque un id puede tener varios dueños
## a la vez (un altar de carga, una calavera zumbante y un altar colocado
## zumban con "shrine_channel"): la voz para solo cuando suelta el ÚLTIMO.
## Cada llamador DEBE emparejar un acquire con exactamente un release (con
## una bandera; suelta en _exit_tree si lo liberan a mitad del bucle).
func acquire_loop(id: StringName) -> void:
	var count := int(_loop_refcounts.get(id, 0))
	_loop_refcounts[id] = count + 1
	if count == 0:
		_start_loop_voice(id)


func release_loop(id: StringName) -> void:
	var count := int(_loop_refcounts.get(id, 0))
	if count <= 0:
		return
	count -= 1
	_loop_refcounts[id] = count
	if count == 0:
		_stop_loop_voice(id)


## Otro nombre de acquire_loop/release_loop que usan los santuarios; mismo
## comportamiento (con conteo de referencias).
func play_loop(id: StringName) -> void:
	acquire_loop(id)


func stop_loop(id: StringName) -> void:
	release_loop(id)


## Cuántos dueños tiene `id` ahora (gancho de pruebas).
func loop_refcount(id: StringName) -> int:
	return int(_loop_refcounts.get(id, 0))


## Las voces en bucle viven fuera del pool de un disparo y nunca se roban.
func _start_loop_voice(id: StringName) -> void:
	var stream := _loop_streams.get(id, STREAMS.get(id)) as AudioStream
	if stream == null:
		push_warning("Sfx: unknown loop id '%s'" % id)
		return
	var player := _loop_players.get(id) as AudioStreamPlayer
	if player == null:
		player = AudioStreamPlayer.new()
		player.bus = BUS_NAME
		player.stream = stream
		player.volume_db = _id_volume(id)
		add_child(player)
		_loop_players[id] = player
	if not player.playing:
		player.play()


func _stop_loop_voice(id: StringName) -> void:
	var player := _loop_players.get(id) as AudioStreamPlayer
	if player != null and player.playing:
		player.stop()


## Seguridad de fin de partida: el gestor procesa en pausa, y un zumbido
## empezado antes de morir seguiría sonando sobre la pantalla final. También
## limpia los conteos: los dueños se liberan con la partida.
func stop_all_loops() -> void:
	for id: StringName in _loop_players:
		_loop_players[id].stop()
	_loop_refcounts.clear()


# --- Asignación de voces ----------------------------------------------------

## Busca en rotación una voz libre desde el cursor. Si todas suenan, se
## reinicia la que EMPEZÓ HACE MÁS (la más cerca de terminar y la que menos
## se nota perder); en empate, el índice más bajo.
func _alloc_voice() -> int:
	for offset in _pool.size():
		var idx := (_next_voice + offset) % _pool.size()
		if not _pool[idx].playing:
			_next_voice = (idx + 1) % _pool.size()
			return idx
	var oldest := 0
	for i in _pool.size():
		if _started_at[i] < _started_at[oldest]:
			oldest = i
	_next_voice = (oldest + 1) % _pool.size()
	return oldest


# --- Ayudantes ---------------------------------------------------------------

## True (y registra la reproducción) si `id` está bajo su tope por segundo
## en el instante `now`. Recibe el reloj como parámetro para que un harness
## pueda probar el tope sobre un segundo simulado.
func _rate_check(id: StringName, now: float) -> bool:
	if not rate_limits.has(id):
		return true
	if not _rate_state.has(id):
		_rate_state[id] = RateWindow.new()
	var window: RateWindow = _rate_state[id]
	var times := window.times
	while not times.is_empty() and now - times[0] > 1.0:
		times.pop_front()
	if times.size() >= rate_limits[id]:
		return false
	times.append(now)
	return true


func _rolled_pitch(id: StringName, override_jitter: float) -> float:
	var jitter := override_jitter
	if jitter < 0.0:
		jitter = default_pitch_jitter if jittered_ids.has(id) else 0.0
	if jitter <= 0.0:
		return 1.0
	return 1.0 + randf_range(-jitter, jitter)


func _id_volume(id: StringName) -> float:
	return id_volume_db[id] if id_volume_db.has(id) else 0.0


## Reloj real (inmune a la pausa y a time_scale) para marcas y ventanas.
func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


## Crea los buses de código y nada más: el autoload Settings es el único
## dueño de su volumen (arranca justo después y aplica los niveles
## guardados), así que cualquier ajuste de volumen aquí sería pisado.
func _setup_bus() -> void:
	_ensure_bus(BUS_NAME)
	_ensure_bus(AMBIENT_BUS_NAME)


static func _ensure_bus(bus_name: StringName) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.get_bus_count() - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, &"Master")
