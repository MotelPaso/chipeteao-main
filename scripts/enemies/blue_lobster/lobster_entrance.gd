class_name LobsterEntrance
extends Node3D
## LA CINEMÁTICA de la Langosta Azul, de una sola pieza: del rapto en el mapa
## al cartel con su nombre en el fondo del mar. Es la escena `cinematic_scene`
## de su fila en BossArenaCatalog: BossArenaHost la cuelga de sí mismo cuando
## empieza el viaje y llama a play().
##
## DOS ACTOS, con los planos del nodo Camera (hijos Shot) de cada uno:
##   1. EL RAPTO, en el mapa y sin canción (abduction_seconds): el agua brota
##      del suelo, un remolino se cierra sobre el equipo y la pantalla se inunda.
##   2. EL FONDO DEL MAR, con la canción (intro_seconds): el equipo cae entre
##      rayos de luz, toca fondo, la langosta sale de la arena y entra el
##      cartel. Cada plano entra en un golpe de la introducción, y la pelea
##      empieza cuando la canción entra de lleno.
## Entre los dos, con la pantalla tapada por el agua, va EL CAMBIO DE MUNDO
## (BossArenaHost.enter_arena) y unos frames para que lo nuevo se dibuje una
## vez: ahí no corre ningún reloj ni suena la canción, así un tirón no atrasa
## ningún corte.
## Este nodo es el DIRECTOR: lleva el reloj y decide qué plano entra. Cada
## hijo hace lo suyo: Camera encuadra, Actors mueve a la langosta y al equipo,
## Fx pone el agua del mundo, Overlay la de la pantalla y el cartel, y Music
## la canción.
##
## Mientras dura, el MUNDO está congelado (WorldFreeze), el HUD oculto y en
## co-op queda una sola vista a pantalla completa. EL RELOJ es tiempo de
## juego; la canción lo sigue (BossSong.follow) y, si un frame tarda de más,
## es la cinemática la que salta a alcanzarla (catch_up_after). Este nodo es
## PAUSABLE: el menú de pausa detiene la cinemática y la canción juntas.
##
## SALTAR. Cualquier raider mantiene su acción de saltar: desde cualquier
## punto, el equipo queda en el fondo del mar con la pelea empezada y la
## canción al final de su introducción.
## SALIDAS. Fin de partida, cambio de etapa y «Salir al menú» pasan todas por
## _teardown(): devuelve el mundo, el HUD, la pantalla y la cámara, y para la
## canción.
## Contratos por nombre (los lee el harness): grupos "boss_cinematic" y
## "cinematic_camera"; is_calm_active, calm_elapsed, calm_progress, act_name,
## is_screen_covered, skip_action, shot_times y title_seconds; y las líneas
## "Boss cinematic:".

enum Step { IDLE, ABDUCTION, SWAP, SEABED }

const GROUP := &"boss_cinematic"
const CAMERA_GROUP := &"cinematic_camera"
## Nombre de cada paso para el harness, en el orden de Step.
const STEP_NAMES: Array[StringName] = [&"idle", &"abduction", &"swap", &"seabed"]
## El HUD, la pantalla dividida y la cámara, compartidos con la otra cinemática de jefe.
const BossScreen := preload("res://scripts/enemies/mythos/boss_screen.gd")
const Act := LobsterEntranceShot.Act

@export_group("Rapto")
## Segundos del rapto en el mapa, del primer chorro a la pantalla inundada. Va sin canción.
@export var abduction_seconds: float = 5.2
## Sonido con que empieza el rapto (fila de Sfx.SOUND_LIBRARY; vacío = ninguno).
@export var start_sfx: StringName = &"lobster_rumble"

@export_group("Fondo del mar")
## Segundos de introducción de la canción: lo que dura el acto del fondo del mar. La pelea empieza cuando la canción entra de lleno.
@export var intro_seconds: float = 12.76
## Plano del fondo del mar con el que entra el cartel con su nombre (1 = el primero de ese acto).
@export var title_shot: int = 7
## Frames con la pantalla ya tapada y el equipo todavía en el mapa, antes del cambio de mundo. Ahí vuelve a verse lo que los planos del rapto escondieron, el mapa recupera su cielo y terminan de irse los enemigos que estaban cayendo: todo eso tiene que asentarse antes de que el mapa salga del árbol.
@export var cover_frames: int = 2
## Frames con la pantalla tapada, ya en el fondo del mar, antes de que arranquen la canción y el reloj. Lo que se dibuja por primera vez ahí (la arena entera) cuesta un tirón: con la canción ya sonando, los cortes quedarían atrasados respecto de sus golpes.
@export var warmup_frames: int = 6
## Segundos que la canción puede adelantarse al reloj antes de que la cinemática salte a alcanzarla. 0 = no la alcanza (la canción se reacomoda sola).
@export var catch_up_after: float = 0.06

@export_group("Saltar")
## Acción que cada raider mantiene para saltar la cinemática.
@export var skip_action_name: StringName = &"interact"
## Segundos que hay que mantenerla.
@export var skip_hold_seconds: float = 0.8
## Texto de la indicación de saltar.
@export var skip_hint_text: String = "Mantén para saltar"

var _host: BossArenaHost = null
var _boss: BlueLobster = null
var _freeze: WorldFreeze = WorldFreeze.new()
var _step: Step = Step.IDLE
var _active: bool = false
## Segundos del acto en curso y de toda la cinemática (tiempo de juego).
var _clock: float = 0.0
var _elapsed: float = 0.0
## Frames que faltan con la pantalla tapada: antes del cambio de mundo y después.
var _cover_left: int = 0
var _warmup_left: int = 0
## El plano en curso (-1 = ninguno todavía).
var _shot_index: int = -1
## True mientras este nodo tiene tomados el HUD y la cámara.
var _taken_over: bool = false
var _skip_held: float = 0.0
var _skip_armed: bool = false
## True desde que alguien saltó la cinemática hasta que termina.
var _skipping: bool = false
var _title: String = ""

@onready var _camera: LobsterEntranceCamera = $Camera
@onready var _actors: LobsterEntranceActors = $Actors
@onready var _music: BossSong = $Music
@onready var _overlay: LobsterEntranceOverlay = $Overlay
@onready var _fx: LobsterAbductionFx = $Fx


func _ready() -> void:
	add_to_group(GROUP)
	_camera.add_to_group(CAMERA_GROUP)
	_overlay.set_skip_hint(String(Coop.action(0, skip_action_name)), skip_hint_text)
	set_process(false)


func _exit_tree() -> void:
	_teardown("exit_tree")


func _process(delta: float) -> void:
	if not _active:
		return
	match _step:
		Step.ABDUCTION:
			_tick_abduction(delta)
		Step.SWAP:
			_tick_swap()
		Step.SEABED:
			_tick_seabed(delta)


# --- lo que piden el anfitrión, la langosta y el harness -------------------------

## Arranca la cinemática del viaje que lleva `host`: congela el mundo, toma la
## pantalla y empieza el rapto. Al terminar llama a BlueLobster.finish_entrance().
func play(host: BossArenaHost) -> void:
	if _active:
		return
	_host = host
	_title = host.boss_title()
	_active = true
	_step = Step.ABDUCTION
	_clock = 0.0
	_elapsed = 0.0
	_shot_index = -1
	_skip_held = 0.0
	_skip_armed = false
	_skipping = false
	var party := host.party().bodies()
	# El encuadre mide el mapa: tiene que pasar antes de congelarlo.
	_camera.stage(Act.ABDUCTION, RunRoot.stage_parent(get_tree()) as Node3D, party, null)
	var keep: Array[Node] = [self]
	_freeze.freeze(get_tree(), keep)
	# Los números de daño que estaban en el aire quedarían ahí toda la cinemática.
	Pools.release_live_of(Pools.DAMAGE_POPUP_SCENE)
	_music.set_pausable(true)
	var manager := get_tree().get_first_node_in_group("run_manager")
	if manager != null and manager.has_signal("run_ended") \
			and not manager.is_connected("run_ended", _on_run_ended):
		manager.connect("run_ended", _on_run_ended)
	var spots: Array[Vector3] = []
	for raider: Node3D in party:
		spots.append(raider.global_position)
	_fx.begin_abduction(spots)
	set_process(true)
	print("Boss cinematic: started calm=%.2fs song=%s audio=%s act=abduction" % [
			abduction_seconds + intro_seconds, _music.has_song(), AudioServer.get_driver_name()])
	BossScreen.take(self, _camera)
	_overlay.open(_title)
	_taken_over = true
	Sfx.play(start_sfx)
	_enter_shot(_camera.shot_at(Act.ABDUCTION, 0.0))


func is_calm_active() -> bool:
	return _active


## Segundos de juego que lleva la cinemática (el rapto y el fondo del mar).
func calm_elapsed() -> float:
	return _elapsed


## Avance de la cinemática (0-1).
func calm_progress() -> float:
	return clampf(_elapsed / maxf(abduction_seconds + intro_seconds, 0.01), 0.0, 1.0)


## En qué paso anda: "idle", "abduction" (en el mapa), "swap" (el cambio de
## mundo, con la pantalla tapada) o "seabed" (en el fondo del mar).
func act_name() -> StringName:
	return STEP_NAMES[_step]


## True mientras el agua tapa la pantalla entera.
func is_screen_covered() -> bool:
	return _overlay.is_covered()


## Nombre base de la acción de saltar (el harness la mantiene).
func skip_action() -> StringName:
	return skip_action_name


## Los segundos de cinemática en que entra cada plano, de los dos actos.
func shot_times() -> PackedFloat32Array:
	var times := _camera.shot_times(Act.ABDUCTION)
	for seconds: float in _camera.shot_times(Act.SEABED):
		times.append(abduction_seconds + seconds)
	return times


## El segundo de cinemática en que entra el cartel con su nombre.
func title_seconds() -> float:
	var times := _camera.shot_times(Act.SEABED)
	if times.is_empty():
		return abduction_seconds
	return abduction_seconds + times[clampi(title_shot - 1, 0, times.size() - 1)]


## La langosta murió: su canción se apaga de a poco.
func fade_out_song() -> void:
	_music.fade_out()


# --- los pasos --------------------------------------------------------------------

func _tick_abduction(delta: float) -> void:
	_clock += delta
	_elapsed += delta
	_follow_shots(Act.ABDUCTION, delta)
	_fx.show_abduction(_clock)
	_overlay.flood_rising(_clock, abduction_seconds)
	_overlay.show_progress(_elapsed, INF, _skip_held / maxf(skip_hold_seconds, 0.01))
	if _tick_skip(delta):
		_skipping = true
	if _skipping or _clock >= abduction_seconds:
		_begin_swap()


## El agua tapó la pantalla: el rapto se apaga y, unos frames después, va el
## cambio de mundo.
func _begin_swap() -> void:
	_step = Step.SWAP
	_overlay.show_flood(1.0, 0.0)
	_fx.end_abduction()
	_camera.show_hidden()
	if _host != null:
		_host.prepare_departure()
	_cover_left = maxi(cover_frames, 1)
	_warmup_left = 0


## El cambio de mundo, con la pantalla tapada: el mapa se va, entra la arena y
## nace la langosta, que espera escondida.
func _enter_world() -> void:
	var boss := _host.enter_arena() as BlueLobster if _host != null else null
	if boss == null:
		_teardown("no_arena")
		return
	_boss = boss
	_freeze.keep(boss)
	var party := _host.party().bodies()
	_actors.enter(boss, party)
	_camera.stage(Act.SEABED, _host.boss_arena(), party, boss)
	# La cámara ya mira el primer plano del fondo: lo que se dibuja bajo el
	# agua en estos frames es lo que se va a ver.
	_camera.cut_to(_camera.first_shot(Act.SEABED))
	_warmup_left = maxi(warmup_frames, 1)


func _tick_swap() -> void:
	if _cover_left > 0:
		_cover_left -= 1
		if _cover_left == 0:
			_enter_world()
		return
	_warmup_left -= 1
	if _warmup_left > 0:
		return
	_music.start(intro_seconds)
	if _skipping:
		_finish(true)
		return
	_step = Step.SEABED
	_clock = 0.0
	_shot_index = -1
	_fx.set_descent(true)
	_tick_seabed(0.0)


func _tick_seabed(delta: float) -> void:
	if not is_instance_valid(_boss) or not _boss.is_inside_tree():
		_teardown("boss_gone")
		return
	_clock += delta
	_elapsed += delta
	_catch_up_with_song()
	_follow_shots(Act.SEABED, delta)
	_fx.follow(_camera)
	_actors.tick(delta, _camera.global_position)
	_overlay.flood_clearing(_clock)
	_overlay.show_progress(_elapsed, title_seconds(), _skip_held / maxf(skip_hold_seconds, 0.01))
	_music.follow(_clock, delta)
	if _tick_skip(delta):
		_finish(true)
	elif _clock >= intro_seconds:
		_finish(false)


## Entra el plano que le toca al segundo de ahora de `act` y corre el que está.
func _follow_shots(act: Act, delta: float) -> void:
	var index := _camera.shot_at(act, _clock)
	if index >= 0 and index != _shot_index:
		_enter_shot(index)
	_camera.shoot(delta)


## Si la canción quedó adelante del reloj (un frame tardó de más: el motor le
## cuenta al juego solo una parte de ese tiempo, y la canción lo suena
## entero), la cinemática salta hasta donde va la canción. Sin driver de
## audio real la canción no avanza: ahí manda solo el reloj del juego.
func _catch_up_with_song() -> void:
	if catch_up_after <= 0.0 or not _music.playing \
			or AudioServer.get_driver_name() == "Dummy":
		return
	var heard := _music.get_playback_position() + AudioServer.get_time_since_last_mix() \
			- AudioServer.get_output_latency()
	if heard - _clock > catch_up_after and heard < intro_seconds:
		_elapsed += heard - _clock
		_clock = heard


## Entra el plano `index`: lo que pasa en la escena, la cámara y su línea de log.
func _enter_shot(index: int) -> void:
	var shot := _camera.shot(index)
	if shot == null:
		return
	_shot_index = index
	if shot.act == Act.SEABED:
		# El primer corte del fondo del mar destapa la pantalla.
		_overlay.begin_uncover(_clock)
	_actors.play(shot.event, _fx, _host.boss_arena() if _host != null else null)
	if _boss != null and not shot.pose.is_empty() and LobsterRig.Pose.has(String(shot.pose)):
		_boss.rig.set_pose(LobsterRig.Pose[String(shot.pose)])
		_boss.rig.snap_to_pose()
	_camera.cut_to(index)
	if _boss != null and not shot.gesture.is_empty():
		_boss.rig.gesture(shot.gesture)
	if not shot.sfx.is_empty():
		Sfx.play(shot.sfx)
	var view := _camera.party_in_view()
	print(("Boss cinematic: shot=%d at=%.2fs song=%s isolated=%s hidden=%d act=%s"
			+ " blocking=%d view=%d/%d") % [index + 1, _clock, _music.position_text(),
			shot.isolated, _camera.hidden_count(), act_name(), _camera.blocking_count(),
			view.x, view.y])


## La cinemática terminó (o alguien la saltó): devuelve todo y avisa a la langosta.
func _finish(skipped: bool) -> void:
	_active = false
	_step = Step.IDLE
	set_process(false)
	var song_target := _clock
	if skipped:
		song_target = intro_seconds
		_music.jump_to(intro_seconds)
	_release()
	# Desde aquí la canción ya no sigue a la cinemática: no se corta con las
	# pausas del juego (subidas de nivel, vendedor, menú de pausa).
	_music.set_pausable(false)
	_overlay.close()
	print(("Boss cinematic: ended after=%.2fs skipped=%s song_target=%.2f song_actual=%s"
			+ " resyncs=%d act=seabed") % [_elapsed, skipped, song_target,
			_music.position_text(), _music.resyncs()])
	if is_instance_valid(_boss):
		_boss.finish_entrance(_elapsed, skipped)


## Devuelve el mundo, el HUD, la pantalla dividida, la cámara, al equipo y a
## la langosta como estaban. Se puede llamar siempre.
func _release() -> void:
	_freeze.thaw()
	if _fx != null:
		_fx.clear()
	if _actors != null:
		_actors.release()
	if not _taken_over:
		return
	_taken_over = false
	# El viewport raíz vuelve a tener la MISMA cámara que tenía antes de la
	# cinemática, en solitario y en co-op, y el HUD vuelve con la última
	# cinemática de jefe que suelta la pantalla (BossScreen).
	BossScreen.release(self, _camera)
	_camera.release()


## La única salida de emergencia: fin de partida, mundo que se va, langosta
## que desaparece. Deja todo como lo espera una partida recién empezada.
func _teardown(reason: String) -> void:
	var was_busy := _active or _taken_over or _freeze.is_frozen() \
			or (_music != null and _music.is_live())
	_active = false
	_step = Step.IDLE
	set_process(false)
	_release()
	if _overlay != null:
		_overlay.clear()
	if _music != null:
		_music.halt()
	if was_busy:
		print("Boss cinematic: teardown reason=%s" % reason)


func _on_run_ended(_victory: bool) -> void:
	_teardown("run_ended")


# --- privados ---------------------------------------------------------------------

## True cuando algún raider mantuvo la acción de saltar lo suficiente. Quien
## la venía manteniendo desde antes (cargando un altar, reanimando) primero
## tiene que soltarla: nadie salta la cinemática por accidente.
func _tick_skip(delta: float) -> bool:
	if not _taken_over:
		return false
	var pressed := false
	for slot: int in maxi(Coop.player_count, 1):
		if Input.is_action_pressed(Coop.action(slot, skip_action_name)):
			pressed = true
	if not _skip_armed:
		_skip_armed = not pressed
		pressed = false
	_skip_held = _skip_held + delta if pressed else 0.0
	return _skip_held >= skip_hold_seconds
