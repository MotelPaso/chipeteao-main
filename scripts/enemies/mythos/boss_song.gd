class_name BossSong
extends AudioStreamPlayer
## Una canción de un jefe (nodos Music y MusicReborn de MythosCinematic.tscn:
## una por fase). La cinemática le dice cuándo arrancar y qué reloj seguir;
## este nodo sabe sonar por el bus de música, volver al final de la calma
## cuando la canción se acaba, quedarse pegado al reloj del juego y apagarse
## de a poco.
##
## EL RELOJ lo lleva la cinemática, en tiempo de juego. Con un driver de audio
## real la canción se reacomoda si se desfasa de ese reloj; con el driver
## "Dummy" (corridas sin ventana) su posición nunca se lee, porque ahí corre
## con el reloj de pared y daría una calma distinta en cada corrida.
## Contratos por nombre (los lee el harness): grupo "boss_music" y las líneas
## "Boss music:".

const GROUP := &"boss_music"
## Segundos mínimos entre dos reacomodos de la canción.
const RESYNC_COOLDOWN: float = 0.5
## Volumen, en dB, al que la canción cuenta como apagada.
const SILENT_DB: float = -60.0

@export_group("Canción")
## Canción del jefe. Vacío = la cinemática y la pelea corren sin música.
@export var song: AudioStream
## Volumen de la canción, en dB (el slider «Música» de Ajustes va encima).
@export var song_volume_db: float = -6.0
## Desfase en segundos entre la canción y el reloj de la calma a partir del cual se reacomoda la canción.
@export var resync_threshold: float = 0.12
## Segundos que tarda la canción en apagarse cuando el jefe muere.
@export var fade_seconds: float = 5.0
## Segundos que tarda en apagarse cuando la reemplaza la canción de otra fase.
@export var handover_seconds: float = 1.2

var _dummy_audio: bool = false
## True desde start() hasta que la canción se corta o termina de apagarse.
var _live: bool = false
var _resync_left: float = 0.0
var _resyncs: int = 0
var _fade_tween: Tween = null


func _ready() -> void:
	add_to_group(GROUP)
	bus = Sfx.MUSIC_BUS_NAME
	_dummy_audio = AudioServer.get_driver_name() == "Dummy"


## True si hay una canción puesta.
func has_song() -> bool:
	return song != null


## True mientras la canción está en curso, aunque el juego esté en pausa
## (`playing` lee false con el árbol pausado).
func is_live() -> bool:
	return _live


## Arranca la canción desde el principio. Cuando se acaba vuelve a
## `loop_from` segundos (el final de la calma), no al principio.
func start(loop_from: float) -> void:
	if song == null:
		return
	_kill_fade()
	stream = _looped_copy(song, loop_from)
	volume_db = song_volume_db
	play(0.0)
	_live = true
	_resyncs = 0
	_resync_left = RESYNC_COOLDOWN


## Mantiene la canción pegada a `clock` (los segundos de juego que lleva la
## calma). Se llama cada frame mientras la calma corre.
func follow(clock: float, delta: float) -> void:
	_resync_left = maxf(_resync_left - delta, 0.0)
	if song == null or _dummy_audio or not playing or _resync_left > 0.0:
		return
	var heard := get_playback_position() + AudioServer.get_time_since_last_mix() \
			- AudioServer.get_output_latency()
	if absf(heard - clock) > resync_threshold:
		seek(clock)
		_resync_left = RESYNC_COOLDOWN
		_resyncs += 1


## Con `on` la canción se detiene cuando el juego se pausa (durante la calma,
## para que siga pegada a la cinemática); sin él sigue sonando aunque el
## juego se pause por una subida de nivel, un vendedor o el menú de pausa.
func set_pausable(on: bool) -> void:
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_ALWAYS


## Lleva la canción a `seconds` (alguien saltó la cinemática).
func jump_to(seconds: float) -> void:
	if song != null and playing:
		seek(seconds)


## Posición de la canción para el log: "n/a" sin canción o sin driver real.
func position_text() -> String:
	if song == null or _dummy_audio:
		return "n/a"
	return "%.2f" % get_playback_position()


## Veces que la canción se reacomodó contra el reloj desde que arrancó.
func resyncs() -> int:
	return _resyncs


## El jefe murió: la canción se apaga de a poco y después se detiene.
func fade_out() -> void:
	_fade(fade_seconds)


## Le deja el lugar a la canción de otra fase: se apaga rápido.
func hand_over() -> void:
	_fade(handover_seconds)


## Corta la canción ya (la arena se va o la partida terminó).
func halt() -> void:
	_kill_fade()
	_live = false
	stop()


## Una copia de la canción que, al terminar, vuelve a `loop_from` y no al
## principio. Sobre una copia: el recurso importado es compartido.
func _looped_copy(source: AudioStream, loop_from: float) -> AudioStream:
	var copy := source.duplicate() as AudioStream
	if copy is AudioStreamMP3:
		(copy as AudioStreamMP3).loop = true
		(copy as AudioStreamMP3).loop_offset = loop_from
	elif copy is AudioStreamOggVorbis:
		(copy as AudioStreamOggVorbis).loop = true
		(copy as AudioStreamOggVorbis).loop_offset = loop_from
	elif copy is AudioStreamWAV:
		var wav := copy as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = int(round(loop_from * float(wav.mix_rate)))
		wav.loop_end = int(round(wav.get_length() * float(wav.mix_rate)))
	return copy


func _fade(seconds: float) -> void:
	if not playing:
		return
	_kill_fade()
	print("Boss music: fading out over %.1fs" % seconds)
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "volume_db", SILENT_DB, seconds)
	_fade_tween.tween_callback(_stop_faded)


func _stop_faded() -> void:
	_live = false
	stop()
	print("Boss music: stopped")


func _kill_fade() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
