class_name LobsterEntrance
extends Node3D
## La entrada de la Langosta Azul: un SUSTO. La langosta llega sin ningún
## aviso y, en el primer golpe de su canción, la pantalla CORTA de la partida
## a un primer plano de su cara. Después un plano por cada golpe de la
## introducción (los hijos Shot del nodo Camera), el cartel con su nombre, y
## cuando la canción entra de lleno empieza la pelea.
## La langosta instancia esta escena bajo la arena cuando llega (nodo Arrival
## de BlueLobster.tscn); como cuelga de la arena, muere con ella.
##
## Mientras dura, el MUNDO está congelado (WorldFreeze: arena, raiders,
## director y reloj), el HUD oculto y en co-op queda una sola vista a
## pantalla completa. El mundo se congela al llegar; la pantalla se toma
## recién en el corte, así el último frame antes del susto es la partida.
##
## EL RELOJ es tiempo de juego: la entrada dura intro_seconds en toda partida,
## con canción o sin ella, y la canción sigue ese reloj (BossSong.follow).
## Reloj y canción arrancan juntos unos frames después de congelar el mundo
## (warmup_frames), cuando lo que llegó con la langosta ya se dibujó una vez.
## Si un frame tarda de más y la canción queda adelante, es la entrada la que
## salta a alcanzarla (catch_up_after): la música no retrocede.
## Este nodo es PAUSABLE: el menú de pausa detiene la entrada y la canción.
##
## SALTAR. Cualquier raider mantiene su acción de saltar (skip_action_name):
## la pelea empieza ya y la canción salta al final de su introducción.
##
## SALIDAS. Fin de partida (muerte de toda la party o extracción), cambio de
## etapa y «Salir al menú» pasan todas por _teardown(): devuelve el mundo, el
## HUD, la pantalla dividida y la cámara, y para la canción.
## Contratos por nombre (los lee el harness): grupos "boss_cinematic" y
## "cinematic_camera"; is_calm_active, calm_elapsed, calm_progress,
## skip_action, shot_times y title_seconds; y las líneas "Boss cinematic:".

const GROUP := &"boss_cinematic"
const CAMERA_GROUP := &"cinematic_camera"
const SPLIT_SCREEN_GROUP := &"split_screen"

@export_group("Entrada")
## Segundos de introducción de la canción: lo que dura la entrada. La pelea empieza cuando la canción entra de lleno.
@export var intro_seconds: float = 12.76
## Plano con el que entra el cartel con su nombre (1 = el primero).
@export var title_shot: int = 7
## Sonido del susto en el corte cuando NO hay canción puesta (fila de Sfx.SOUND_LIBRARY; vacío = ninguno).
@export var scare_sfx: StringName = &"lobster_scare"
## Frames con el mundo ya congelado antes de que arranquen la canción y el reloj de la entrada. Lo que se dibuja por primera vez en ese instante (la marea) cuesta un tirón: con la canción ya sonando, los cortes quedarían atrasados respecto de sus golpes.
@export var warmup_frames: int = 4
## Segundos que la canción puede adelantarse al reloj de la entrada antes de que la entrada salte a alcanzarla. Un frame que tarda de más le quita tiempo al reloj del juego y no a la canción: así los cortes siguen con sus golpes y la música no retrocede. 0 = no la alcanza (la canción se reacomoda sola).
@export var catch_up_after: float = 0.06

@export_group("Saltar")
## Acción que cada raider mantiene para saltar la entrada.
@export var skip_action_name: StringName = &"interact"
## Segundos que hay que mantenerla.
@export var skip_hold_seconds: float = 0.8
## Texto de la indicación de saltar.
@export var skip_hint_text: String = "Mantén para saltar"

var _boss: BlueLobster = null
var _freeze: WorldFreeze = WorldFreeze.new()
var _active: bool = false
## True desde que play() arrancó la entrada.
var _played: bool = false
var _elapsed: float = 0.0
## Frames que faltan para que arranquen la canción y el reloj.
var _warmup_left: int = 0
## El plano en curso (-1 = todavía no cortó).
var _shot_index: int = -1
## True mientras este nodo tiene tomados el HUD y la cámara.
var _taken_over: bool = false
var _previous_camera: Camera3D = null
var _skip_held: float = 0.0
var _skip_armed: bool = false

@onready var _camera: LobsterEntranceCamera = $Camera
@onready var _music: BossSong = $Music
@onready var _overlay: LobsterEntranceOverlay = $Overlay


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
	if not is_instance_valid(_boss) or not _boss.is_inside_tree():
		_teardown("boss_gone")
		return
	if _warmup_left > 0:
		_warmup_left -= 1
		if _warmup_left == 0:
			_music.start(intro_seconds)
		return
	_elapsed += delta
	_catch_up_with_song()
	var index := _camera.shot_at(_elapsed)
	if index != _shot_index:
		_enter_shot(index)
	if _taken_over:
		_camera.shoot(delta)
		# No le saca los ojos de encima a quien mira.
		_boss.rig.gaze_at(_camera.global_position)
	_overlay.show_progress(_elapsed, title_seconds(),
			_skip_held / maxf(skip_hold_seconds, 0.01))
	_music.follow(_elapsed, delta)
	if _tick_skip(delta):
		_finish(true)
	elif _elapsed >= intro_seconds:
		_finish(false)


# --- lo que piden la langosta y el harness ----------------------------------------

## Arranca la entrada de `boss`, ya ubicada en la arena: congela el mundo, la
## esconde hasta el corte y pone la canción. Al terminar llama a
## BlueLobster.finish_entrance().
func play(boss: BlueLobster) -> void:
	if _active:
		return
	_boss = boss
	_played = true
	_elapsed = 0.0
	_shot_index = -1
	_skip_held = 0.0
	_skip_armed = false
	_active = true
	_face_party()
	# El encuadre mide el mapa: tiene que pasar antes de congelarlo.
	_camera.stage(boss)
	boss.rig.visible = false
	boss.rig.fidgets = false
	boss.rig.add_visual_layer(LobsterEntranceCamera.ISOLATION_LAYER)
	var keep: Array[Node] = [self, boss]
	_freeze.freeze(get_tree(), keep)
	# Los números de daño que estaban en el aire quedarían ahí toda la entrada.
	Pools.release_live_of(Pools.DAMAGE_POPUP_SCENE)
	_music.set_pausable(true)
	_warmup_left = maxi(warmup_frames, 0)
	if _warmup_left == 0:
		_music.start(intro_seconds)
	var manager := get_tree().get_first_node_in_group("run_manager")
	if manager != null and manager.has_signal("run_ended") \
			and not manager.is_connected("run_ended", _on_run_ended):
		manager.connect("run_ended", _on_run_ended)
	set_process(true)
	print("Boss cinematic: started calm=%.2fs song=%s audio=%s act=entrance" % [
			intro_seconds, _music.has_song(), AudioServer.get_driver_name()])
	# Un plano que entra en el segundo 0 corta en este mismo frame.
	var first := _camera.shot_at(0.0)
	if first >= 0:
		_enter_shot(first)


func is_calm_active() -> bool:
	return _active


## Segundos de juego que lleva la entrada.
func calm_elapsed() -> float:
	return _elapsed


## Avance de la entrada (0-1).
func calm_progress() -> float:
	return clampf(_elapsed / maxf(intro_seconds, 0.01), 0.0, 1.0)


## Nombre base de la acción de saltar (el harness la mantiene).
func skip_action() -> StringName:
	return skip_action_name


## Los segundos en que entra cada plano (el primero es el corte).
func shot_times() -> PackedFloat32Array:
	return _camera.shot_times()


## El segundo en que entra el cartel con su nombre.
func title_seconds() -> float:
	var times := _camera.shot_times()
	if times.is_empty():
		return 0.0
	return times[clampi(title_shot - 1, 0, times.size() - 1)]


## La langosta murió: su canción se apaga de a poco.
func fade_out_song() -> void:
	_music.fade_out()


## True cuando esta entrada ya no tiene nada que hacer: no está en curso y la
## langosta ya no existe (el nodo Music/Yield la libera cuando calla la canción).
func is_spent() -> bool:
	return _played and not _active and not is_instance_valid(_boss)


# --- la entrada -------------------------------------------------------------------

## Si la canción quedó adelante del reloj de la entrada (un frame tardó de
## más: el motor le cuenta al juego solo una parte de ese tiempo, y la canción
## lo suena entero), la entrada salta hasta donde va la canción. Sin driver de
## audio real la canción no avanza: ahí manda solo el reloj del juego.
func _catch_up_with_song() -> void:
	if catch_up_after <= 0.0 or not _music.playing \
			or AudioServer.get_driver_name() == "Dummy":
		return
	var heard := _music.get_playback_position() + AudioServer.get_time_since_last_mix() \
			- AudioServer.get_output_latency()
	if heard - _elapsed > catch_up_after and heard < intro_seconds:
		_elapsed = heard


## Entra el plano `index`. El primero es EL CORTE: recién ahí se toma la
## pantalla y la langosta se deja ver.
func _enter_shot(index: int) -> void:
	_shot_index = index
	var shot := _camera.shot(index)
	if shot == null:
		return
	if not _taken_over:
		_cut_in()
	if not shot.pose.is_empty() and LobsterRig.Pose.has(String(shot.pose)):
		_boss.rig.set_pose(LobsterRig.Pose[String(shot.pose)])
		_boss.rig.snap_to_pose()
	_camera.cut_to(index)
	if not shot.gesture.is_empty():
		_boss.rig.gesture(shot.gesture)
	if not shot.sfx.is_empty():
		Sfx.play(shot.sfx)
	print("Boss cinematic: shot=%d at=%.2fs song=%s isolated=%s hidden=%d" % [
			index + 1, _elapsed, _music.position_text(), shot.isolated,
			_camera.hidden_count()])


## El corte: toma el HUD, la pantalla dividida y la cámara. Lo que se toma
## aquí se devuelve en _release().
func _cut_in() -> void:
	get_tree().call_group(&"hud", "set_cinematic", true)
	for node: Node in get_tree().get_nodes_in_group(SPLIT_SCREEN_GROUP):
		var split := node as CanvasItem
		if split != null:
			split.visible = false
	_previous_camera = get_viewport().get_camera_3d()
	_camera.make_current()
	_boss.rig.visible = true
	_boss.rig.set_near_fade(false)
	_overlay.open(_boss.boss_title)
	if not _music.has_song() and not scare_sfx.is_empty():
		Sfx.play(scare_sfx)
	_taken_over = true


## La entrada terminó (o alguien la saltó): devuelve todo y avisa a la langosta.
func _finish(skipped: bool) -> void:
	_active = false
	set_process(false)
	var song_target := _elapsed
	if skipped:
		song_target = intro_seconds
		_music.jump_to(intro_seconds)
	_release()
	# Desde aquí la canción ya no sigue a la entrada: no se corta con las
	# pausas del juego (subidas de nivel, vendedor, menú de pausa).
	_music.set_pausable(false)
	_overlay.close()
	print(("Boss cinematic: ended after=%.2fs skipped=%s song_target=%.2f song_actual=%s"
			+ " resyncs=%d act=entrance") % [_elapsed, skipped, song_target,
			_music.position_text(), _music.resyncs()])
	if is_instance_valid(_boss):
		_boss.finish_entrance(_elapsed, skipped)


## Devuelve el mundo, el HUD, la pantalla dividida, la cámara y a la langosta
## como estaba. Se puede llamar siempre.
func _release() -> void:
	_freeze.thaw()
	if is_instance_valid(_boss):
		_boss.rig.visible = true
		_boss.rig.fidgets = true
		_boss.rig.set_near_fade(true)
		_boss.rig.gaze_ahead()
	if not _taken_over:
		return
	_taken_over = false
	if is_inside_tree():
		get_tree().call_group(&"hud", "set_cinematic", false)
		for node: Node in get_tree().get_nodes_in_group(SPLIT_SCREEN_GROUP):
			var split := node as CanvasItem
			if split != null:
				split.visible = true
	# El viewport raíz vuelve a tener la MISMA cámara que tenía antes de la
	# entrada, en solitario y en co-op. clear_current(false) para que Godot no
	# elija otra por su cuenta.
	_camera.clear_current(false)
	_camera.release()
	if _previous_camera != null and is_instance_valid(_previous_camera) \
			and _previous_camera.is_inside_tree():
		_previous_camera.make_current()
	_previous_camera = null


## La única salida de emergencia: fin de partida, arena que se va, langosta
## que desaparece. Deja todo como lo espera una partida recién empezada.
func _teardown(reason: String) -> void:
	var was_busy := _active or _taken_over or _freeze.is_frozen() \
			or (_music != null and _music.is_live())
	_active = false
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

## Deja a la langosta mirando hacia la party (raiders en pie y caídos).
func _face_party() -> void:
	var centroid := Vector3.ZERO
	var count := 0
	for group: StringName in [&"player", &"downed_players"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body != null:
				centroid += body.global_position
				count += 1
	if count == 0:
		return
	_boss.snap_facing(centroid / float(count) - _boss.global_position)


## True cuando algún raider mantuvo la acción de saltar lo suficiente, ya con
## la entrada en pantalla. Quien la venía manteniendo desde antes (cargando un
## altar, reanimando) primero tiene que soltarla: nadie la salta por accidente.
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
