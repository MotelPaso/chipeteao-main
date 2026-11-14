class_name MythosCinematic
extends Node3D
## Las cinemáticas de Mythos. Mythos instancia esta escena bajo la arena
## cuando llega; como cuelga de la arena, muere con ella. Tiene dos ACTOS, y
## en los dos pasa lo mismo: el MUNDO se congela (WorldFreeze: arena,
## raiders, director y reloj), el HUD se oculta, en co-op queda una sola
## vista a pantalla completa y arranca la canción de esa fase.
##   LA LLEGADA (play). Lo que hace el fénix lo lleva el nodo Entrance y los
##     planos, el nodo Camera. Suena la canción de la primera fase (nodo
##     Music) y dura calm_seconds.
##   EL RENACER (play_rebirth), entre la primera fase y la segunda. Lo lleva
##     el nodo Rebirth con su cámara, suena la canción de la segunda fase
##     (nodo MusicReborn) y dura rebirth_seconds.
## Cada acto dura lo que la calma con que empieza su canción: cuando termina,
## Mythos pelea justo en el golpe de la música. El cartel (franjas, nombre,
## saltar y destellos) lo dibuja el nodo Overlay.
##
## EL RELOJ es tiempo de juego: un acto dura lo mismo en toda partida, con
## canción o sin ella, y la canción sigue ese reloj (BossSong.follow).
## Este nodo es PAUSABLE: el menú de pausa detiene el acto y la canción.
##
## SALTAR. Cualquier raider mantiene su acción de saltar (skip_action_name):
## la pelea sigue ya, la canción salta al final de su calma y el mapa a como
## queda al terminar el acto.
##
## SALIDAS. Fin de partida (muerte de toda la party o extracción), cambio de
## etapa y «Salir al menú» pasan todas por _teardown(): devuelve el mundo, el
## HUD, la pantalla dividida y la cámara, y para las canciones.
## Contratos por nombre (los lee el harness): grupos "boss_cinematic" y
## "cinematic_camera"; is_calm_active, calm_elapsed, calm_progress y
## skip_action; y las líneas "Boss cinematic:".

enum Act { ARRIVAL, REBIRTH }

const GROUP := &"boss_cinematic"
const CAMERA_GROUP := &"cinematic_camera"
const SPLIT_SCREEN_GROUP := &"split_screen"
## Metros sobre el jefe alrededor de los que flotan las brasas del mapa
## durante un acto.
const EMBER_FOCUS_HEIGHT: float = 3.0
## Nombre de cada acto en el log, en el orden de Act.
const ACT_NAMES: Array[String] = ["arrival", "rebirth"]

@export_group("Calma")
## Segundos de calma al principio de la canción de la primera fase: lo que dura la llegada.
@export var calm_seconds: float = 15.24
## Segundos de calma al principio de la canción de la segunda fase: lo que dura el renacer.
@export var rebirth_seconds: float = 9.7

@export_group("Saltar")
## Acción que cada raider mantiene para saltar una cinemática.
@export var skip_action_name: StringName = &"interact"
## Segundos que hay que mantenerla.
@export var skip_hold_seconds: float = 0.8
## Texto de la indicación de saltar.
@export var skip_hint_text: String = "Mantén para saltar"

@export_group("Cartel")
## Texto bajo el nombre del jefe en la llegada.
@export var subtitle_text: String = "El fénix de las brasas"
## Texto bajo su nombre nuevo en el renacer.
@export var reborn_subtitle_text: String = "Renacido de sus cenizas"

var _boss: Mythos = null
var _transformation: HellTransformation = null
var _freeze: WorldFreeze = WorldFreeze.new()
var _act: Act = Act.ARRIVAL
## Lo que dura el acto en curso y la canción que lo acompaña.
var _act_seconds: float = 8.0
var _song: BossSong = null
var _active: bool = false
var _elapsed: float = 0.0
## True mientras este nodo tiene tomados el mundo, el HUD y la cámara.
var _taken_over: bool = false
var _previous_camera: Camera3D = null
var _skip_held: float = 0.0
var _skip_armed: bool = false

@onready var _camera: MythosCinematicCamera = $Camera
@onready var _entrance: MythosEntrance = $Entrance
@onready var _rebirth: MythosRebirthAct = $Rebirth
@onready var _rebirth_camera: MythosRebirthCamera = $Rebirth/Camera
@onready var _music: BossSong = $Music
@onready var _music_reborn: BossSong = $MusicReborn
@onready var _overlay: MythosCinematicOverlay = $Overlay


func _ready() -> void:
	add_to_group(GROUP)
	_camera.add_to_group(CAMERA_GROUP)
	_rebirth_camera.add_to_group(CAMERA_GROUP)
	_entrance.shake_requested.connect(_camera.shake)
	_entrance.flash_requested.connect(_overlay.flash)
	_rebirth.shake_requested.connect(_rebirth_camera.shake)
	_rebirth.flash_requested.connect(_overlay.flash)
	_overlay.set_skip_hint(String(Coop.action(0, skip_action_name)), skip_hint_text)
	_song = _music
	set_process(false)


func _exit_tree() -> void:
	_teardown("exit_tree")


func _process(delta: float) -> void:
	if not _active:
		return
	if not is_instance_valid(_boss) or not _boss.is_inside_tree():
		_teardown("boss_gone")
		return
	_elapsed += delta
	_advance_act(calm_progress(), delta)
	_overlay.show_progress(_elapsed, _title_fraction() * _act_seconds,
			_skip_held / maxf(skip_hold_seconds, 0.01))
	_song.follow(_elapsed, delta)
	if _tick_skip(delta):
		_finish(true)
	elif _elapsed >= _act_seconds:
		_finish(false)


# --- lo que piden Mythos y el harness ---------------------------------------------

## La llegada: congela el mundo, toma la pantalla y pone la canción de la
## primera fase. Al terminar llama a Mythos.finish_calm().
func play(boss: Mythos, transformation: HellTransformation) -> void:
	if _active:
		return
	_boss = boss
	_transformation = transformation
	_begin_act(Act.ARRIVAL, calm_seconds, _music)


## El renacer, con Mythos ya en cenizas: la canción de la primera fase le
## deja el lugar a la de la segunda. True si esta cinemática lo lleva; al
## terminar llama a Mythos.finish_rebirth().
func play_rebirth(boss: Mythos) -> bool:
	if _active or not is_inside_tree() or not RunState.run_active:
		return false
	_boss = boss
	if _music_reborn.has_song():
		_music.hand_over()
	_begin_act(Act.REBIRTH, rebirth_seconds, _music_reborn)
	return true


func is_calm_active() -> bool:
	return _active


## Segundos de juego que lleva el acto en curso.
func calm_elapsed() -> float:
	return _elapsed


## Avance del acto en curso (0-1).
func calm_progress() -> float:
	return clampf(_elapsed / maxf(_act_seconds, 0.01), 0.0, 1.0)


## Segundos de la llegada que pasan hasta que Mythos golpea el suelo: desde
## ahí arde el bosque.
func impact_seconds() -> float:
	return calm_seconds * _entrance.impact_fraction


## Nombre base de la acción de saltar (el harness la mantiene).
func skip_action() -> StringName:
	return skip_action_name


## El jefe murió: la canción que esté sonando se apaga de a poco. Si en
## `rebirth_in` segundos va a renacer, la de la segunda fase queda avisada.
func fade_out_song(rebirth_in: float = -1.0) -> void:
	_music_reborn.fade_out()
	_music.fade_out(_music_reborn.cue(rebirth_in, rebirth_seconds) if rebirth_in >= 0.0 else INF)


## Destello a pantalla completa: el del golpe con que termina un acto.
## Mythos lo pide de nuevo en su ataque más fuerte.
func flash() -> void:
	_overlay.flash_end()


# --- actos ------------------------------------------------------------------------

## Arranca un acto de `seconds` segundos con la canción `song`.
func _begin_act(act: Act, seconds: float, song: BossSong) -> void:
	_act = act
	_act_seconds = seconds
	_song = song
	_elapsed = 0.0
	_skip_held = 0.0
	_skip_armed = false
	_active = true
	# El encuadre mide la escenografía: tiene que pasar antes de congelarla.
	_stage_act()
	_take_over()
	_song.set_pausable(true)
	_song.start(seconds)
	var manager := get_tree().get_first_node_in_group("run_manager")
	if manager != null and manager.has_signal("run_ended") \
			and not manager.is_connected("run_ended", _on_run_ended):
		manager.connect("run_ended", _on_run_ended)
	set_process(true)
	_advance_act(0.0, 0.0)
	print("Boss cinematic: started calm=%.2fs song=%s audio=%s act=%s" % [
			seconds, _song.has_song(), AudioServer.get_driver_name(), ACT_NAMES[_act]])


## Fija el encuadre del acto y arranca lo que hace el fénix: dónde está el
## jefe y de qué lado está la party.
func _stage_act() -> void:
	var boss_point := _boss.global_position
	var toward := _party_offset(boss_point)
	var away := toward.normalized() if toward.length_squared() > 0.01 else Vector3.BACK
	# Queda de frente al plano héroe (-Z es su frente), con las alas abiertas
	# hacia la cámara.
	var facing := away
	if _act == Act.ARRIVAL:
		var radius := _entrance.ring_radius_for(toward.length())
		_camera.frame(boss_point, away, radius, _entrance.impact_fraction, _act_seconds)
		facing = _camera.hero_side()
		_entrance.begin(_boss, boss_point, _camera.side(), radius, _act_seconds)
	else:
		_rebirth_camera.frame(boss_point, away)
		facing = _rebirth_camera.hero_side()
		_rebirth.begin(_boss, _transformation, boss_point, _act_seconds)
	_boss.rotation.y = atan2(-facing.x, -facing.z)


## Un frame del acto: lo que hace el fénix, la cámara y hacia dónde mira.
## Las brasas del mapa se quedan alrededor del jefe.
func _advance_act(progress: float, delta: float) -> void:
	var view := _act_camera()
	if _act == Act.ARRIVAL:
		_entrance.advance(progress)
		_camera.shoot(progress, _entrance.bird_point(), _boss.rig.body_height(), delta)
	else:
		_rebirth.advance(progress)
		_rebirth_camera.shoot(progress, _boss.rig.body_height(), delta)
	if progress >= _title_fraction():
		# Ya a la vista, no le saca los ojos de encima a la cámara.
		_boss.rig.gaze_at(view.global_position)
	if _transformation != null and is_instance_valid(_transformation):
		_transformation.set_focus(_boss.global_position + Vector3.UP * EMBER_FOCUS_HEIGHT)


func _act_camera() -> Camera3D:
	return _camera if _act == Act.ARRIVAL else _rebirth_camera


## Fracción del acto (0-1) en que aparece el nombre: con el grito.
func _title_fraction() -> float:
	return _entrance.roar_fraction if _act == Act.ARRIVAL else _rebirth.roar_fraction


func _stop_act() -> void:
	if _entrance != null:
		_entrance.stop()
	if _rebirth != null:
		_rebirth.stop()


## El acto terminó (o alguien lo saltó): devuelve la pantalla y avisa al jefe.
func _finish(skipped: bool) -> void:
	_active = false
	set_process(false)
	_stop_act()
	var song_target := _elapsed + _song.lead_seconds
	if skipped:
		if _transformation != null and is_instance_valid(_transformation):
			_transformation.finish_now()
			if _act == Act.REBIRTH and is_instance_valid(_boss):
				# Si el fuego de la segunda fase todavía no había salido, sale ya.
				_transformation.ascend(_boss.global_position, 0.0)
			_transformation.ascend_now()
		song_target = _act_seconds + _song.lead_seconds
		_song.jump_to(_act_seconds)
	_release()
	# Desde aquí la canción ya no sigue a la cinemática: no se corta con las
	# pausas del juego (subidas de nivel, vendedor, menú de pausa).
	_song.set_pausable(false)
	_overlay.flash_end()
	print(("Boss cinematic: ended after=%.2fs skipped=%s song_target=%.2f song_actual=%s"
			+ " resyncs=%d act=%s") % [_elapsed, skipped, song_target, _song.position_text(),
			_song.resyncs(), ACT_NAMES[_act]])
	if not is_instance_valid(_boss):
		return
	if _act == Act.ARRIVAL:
		_boss.finish_calm(_elapsed, skipped)
	else:
		_boss.finish_rebirth(_elapsed, skipped)


## Toma el mundo y la pantalla. Lo que se toma aquí se devuelve en _release().
func _take_over() -> void:
	var keep: Array[Node] = [self, _boss]
	if _transformation != null and is_instance_valid(_transformation):
		keep.append(_transformation)
	_freeze.freeze(get_tree(), keep)
	# Los números de daño que estaban en el aire quedarían ahí todo el acto.
	Pools.release_live_of(Pools.DAMAGE_POPUP_SCENE)
	get_tree().call_group(&"hud", "set_cinematic", true)
	for node: Node in get_tree().get_nodes_in_group(SPLIT_SCREEN_GROUP):
		var split := node as CanvasItem
		if split != null:
			split.visible = false
	_previous_camera = get_viewport().get_camera_3d()
	_act_camera().make_current()
	if _act == Act.ARRIVAL:
		_overlay.open(_boss.boss_title, subtitle_text, false)
	else:
		_overlay.open(_boss.reborn_title(), reborn_subtitle_text, true)
	_taken_over = true


## Devuelve el mundo, el HUD, la pantalla dividida y la cámara. Se puede
## llamar siempre.
func _release() -> void:
	if not _taken_over:
		return
	_taken_over = false
	_freeze.thaw()
	if is_inside_tree():
		get_tree().call_group(&"hud", "set_cinematic", false)
		for node: Node in get_tree().get_nodes_in_group(SPLIT_SCREEN_GROUP):
			var split := node as CanvasItem
			if split != null:
				split.visible = true
	# El viewport raíz vuelve a tener la MISMA cámara que tenía antes de la
	# cinemática, en solitario y en co-op. clear_current(false) para que
	# Godot no elija otra por su cuenta: cuando una cámara activa se suelta
	# (o sale del árbol), le pasa el turno a cualquier otra del viewport.
	_act_camera().clear_current(false)
	if _previous_camera != null and is_instance_valid(_previous_camera) \
			and _previous_camera.is_inside_tree():
		_previous_camera.make_current()
	_previous_camera = null
	_overlay.close()
	if _transformation != null and is_instance_valid(_transformation):
		_transformation.set_focus(Vector3.INF)


## La única salida de emergencia: fin de partida, arena que se va, jefe que
## desaparece. Deja todo como lo espera una partida recién empezada.
func _teardown(reason: String) -> void:
	var was_busy := _active or _taken_over \
			or (_music != null and (_music.is_live() or _music_reborn.is_live()))
	_active = false
	set_process(false)
	_stop_act()
	_release()
	if _overlay != null:
		_overlay.clear()
	if _music != null:
		_music.halt()
		_music_reborn.halt()
	if was_busy:
		print("Boss cinematic: teardown reason=%s" % reason)


func _on_run_ended(_victory: bool) -> void:
	_teardown("run_ended")


# --- privados ---------------------------------------------------------------------

## Desde `point` hasta el centro de la party (raiders en pie y caídos), a ras
## de suelo.
func _party_offset(point: Vector3) -> Vector3:
	var centroid := Vector3.ZERO
	var count := 0
	for group: StringName in [&"player", &"downed_players"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body != null:
				centroid += body.global_position
				count += 1
	var toward := (centroid / float(maxi(count, 1))) - point
	toward.y = 0.0
	return toward


## True cuando algún raider mantuvo la acción de saltar lo suficiente. Quien
## ya la venía manteniendo al empezar (cargando un altar, reanimando) primero
## tiene que soltarla: así nadie salta la cinemática por accidente.
func _tick_skip(delta: float) -> bool:
	var pressed := false
	for slot: int in maxi(Coop.player_count, 1):
		if Input.is_action_pressed(Coop.action(slot, skip_action_name)):
			pressed = true
	if not _skip_armed:
		_skip_armed = not pressed
		pressed = false
	_skip_held = _skip_held + delta if pressed else 0.0
	return _skip_held >= skip_hold_seconds
