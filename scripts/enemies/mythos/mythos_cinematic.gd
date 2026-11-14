class_name MythosCinematic
extends Node3D
## Cinemática de llegada de Mythos. Mythos instancia esta escena bajo la
## arena cuando llega y llama a play(); como cuelga de la arena, muere con
## ella. La CANCIÓN la toca su nodo Music (BossSong), que tiene el archivo, el
## volumen y el fundido; aquí solo se le marca el reloj. Lo que el fénix HACE
## en pantalla (cae como un cometa, deja un anillo de fuego, sube, cae a plomo
## y sale de una columna de fuego) lo lleva el nodo Entrance (MythosEntrance)
## y los planos, el nodo Camera.
##
## LA CALMA. La canción tiene unos segundos de calma antes de arrancar:
## calm_seconds. Durante ellos corre la cinemática con el MUNDO CONGELADO
## (WorldFreeze: arena, raiders, director y reloj), el HUD oculto y, en
## co-op, una sola vista a pantalla completa en vez de la pantalla dividida.
## Cuando la calma termina, Mythos empieza a pelear justo en el golpe de la
## canción.
##
## EL RELOJ es tiempo de juego: la calma dura calm_seconds segundos de juego
## en toda partida, con canción o sin ella. La canción arranca con la calma y
## sigue ese reloj (BossSong.follow).
## Este nodo es PAUSABLE: el menú de pausa detiene la calma y la canción.
##
## SALTAR. Cualquier raider mantiene su acción de saltar (skip_action_name):
## la pelea empieza ya, la canción salta al final de la calma y el mapa a su
## infierno completo.
##
## SALIDAS. Fin de partida (muerte de toda la party o extracción), cambio de
## etapa y «Salir al menú» pasan todas por _teardown(): devuelve el mundo, el
## HUD, la pantalla dividida y la cámara, y para la canción.
## Contratos por nombre (los lee el harness): grupos "boss_cinematic" y
## "cinematic_camera"; is_calm_active, calm_elapsed, calm_progress y
## skip_action; y las líneas "Boss cinematic:".

const GROUP := &"boss_cinematic"
const CAMERA_GROUP := &"cinematic_camera"
const SPLIT_SCREEN_GROUP := &"split_screen"
## Metros sobre el punto de llegada alrededor de los que flotan las brasas
## del mapa durante la calma.
const EMBER_FOCUS_HEIGHT: float = 3.0

@export_group("Calma")
## Segundos de calma al principio de la canción: lo que dura la cinemática.
@export var calm_seconds: float = 8.0

@export_group("Saltar")
## Acción que cada raider mantiene para saltar la cinemática.
@export var skip_action_name: StringName = &"interact"
## Segundos que hay que mantenerla.
@export var skip_hold_seconds: float = 0.8
## Texto de la indicación de saltar.
@export var skip_hint_text: String = "Mantén para saltar"

@export_group("Cartel")
## Fracción de la calma (0-1) en que aparece el nombre del jefe (junto con su grito: roar_fraction del nodo Entrance).
@export_range(0.0, 1.0) var title_fraction: float = 0.83
## Segundos que tarda el nombre en aparecer.
@export var title_fade_seconds: float = 0.6
## Texto bajo el nombre del jefe.
@export var subtitle_text: String = "El fénix de las brasas"
## Espacio extra entre las letras del nombre, en píxeles.
@export var title_letter_spacing: int = 10
## Alto de cada franja negra, como fracción del alto de la pantalla.
@export_range(0.0, 0.3) var bar_height_ratio: float = 0.11
## Segundos que tardan las franjas negras en entrar.
@export var bar_seconds: float = 0.7
## Color de los destellos a pantalla completa (el golpe contra el suelo y el final de la calma).
@export var flash_color: Color = Color(1.0, 0.82, 0.5)
## Segundos que dura cada destello.
@export var flash_seconds: float = 0.45
## Opacidad del destello con que termina la calma (0-1).
@export_range(0.0, 1.0) var end_flash_alpha: float = 0.85

var _boss: Mythos = null
var _transformation: HellTransformation = null
var _freeze: WorldFreeze = WorldFreeze.new()
var _active: bool = false
var _elapsed: float = 0.0
## True mientras este nodo tiene tomados el mundo, el HUD y la cámara.
var _taken_over: bool = false
var _previous_camera: Camera3D = null
var _skip_held: float = 0.0
var _skip_armed: bool = false
var _flash_tween: Tween = null

@onready var _camera: MythosCinematicCamera = $Camera
@onready var _entrance: MythosEntrance = $Entrance
@onready var _music: BossSong = $Music
@onready var _overlay: CanvasLayer = $Overlay
@onready var _bar_top: ColorRect = %BarTop
@onready var _bar_bottom: ColorRect = %BarBottom
@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _skip_hint: BoxContainer = %SkipHint
@onready var _skip_bar: ProgressBar = %SkipBar
@onready var _flash: ColorRect = %Flash


func _ready() -> void:
	add_to_group(GROUP)
	_camera.add_to_group(CAMERA_GROUP)
	_entrance.shake_requested.connect(_camera.shake)
	_entrance.flash_requested.connect(_play_flash)
	_overlay.visible = false
	_title.add_theme_font_override("font", UiTheme.spaced_font(title_letter_spacing))
	_subtitle.text = subtitle_text
	_skip_hint.add_child(InputHints.build(
			[[String(Coop.action(0, skip_action_name)), skip_hint_text]]))
	_skip_hint.move_child(_skip_bar, -1)
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
	var progress := calm_progress()
	_entrance.advance(progress)
	_update_camera(progress, delta)
	_update_overlay(progress)
	_music.follow(_elapsed, delta)
	if _tick_skip(delta):
		_finish(true)
	elif _elapsed >= calm_seconds:
		_finish(false)


# --- lo que piden Mythos y el harness ---------------------------------------------

## Arranca la calma: congela el mundo, toma la pantalla y pone la canción.
func play(boss: Mythos, transformation: HellTransformation) -> void:
	if _active:
		return
	_boss = boss
	_transformation = transformation
	_elapsed = 0.0
	_skip_held = 0.0
	_skip_armed = false
	_active = true
	_title.text = boss.boss_title
	_frame_shot()
	_take_over()
	_music.set_pausable(true)
	_music.start(calm_seconds)
	var manager := get_tree().get_first_node_in_group("run_manager")
	if manager != null and manager.has_signal("run_ended") \
			and not manager.is_connected("run_ended", _on_run_ended):
		manager.connect("run_ended", _on_run_ended)
	set_process(true)
	_update_camera(0.0, 0.0)
	_update_overlay(0.0)
	print("Boss cinematic: started calm=%.2fs song=%s audio=%s" % [
			calm_seconds, _music.has_song(), AudioServer.get_driver_name()])


func is_calm_active() -> bool:
	return _active


## Segundos de juego que lleva la calma.
func calm_elapsed() -> float:
	return _elapsed


## Avance de la calma (0-1).
func calm_progress() -> float:
	return clampf(_elapsed / maxf(calm_seconds, 0.01), 0.0, 1.0)


## Segundos de calma que pasan hasta que Mythos golpea el suelo: desde ahí
## arde el bosque.
func impact_seconds() -> float:
	return calm_seconds * _entrance.impact_fraction


## Nombre base de la acción de saltar (el harness la mantiene).
func skip_action() -> StringName:
	return skip_action_name


## El jefe murió: la canción se apaga de a poco.
func fade_out_song() -> void:
	_music.fade_out()


## Destello a pantalla completa: el del golpe con que termina la calma.
## Mythos lo pide de nuevo en su ataque más fuerte.
func flash() -> void:
	_play_flash(end_flash_alpha)


# --- calma ------------------------------------------------------------------------

## La calma terminó (o alguien la saltó): devuelve la pantalla y avisa al jefe.
func _finish(skipped: bool) -> void:
	_active = false
	set_process(false)
	_entrance.stop()
	var song_target := _elapsed
	if skipped:
		if _transformation != null and is_instance_valid(_transformation):
			_transformation.finish_now()
		song_target = calm_seconds
		_music.jump_to(calm_seconds)
	_release()
	# Desde aquí la canción ya no sigue a la cinemática: no se corta con las
	# pausas del juego (subidas de nivel, vendedor, menú de pausa).
	_music.set_pausable(false)
	_play_flash(end_flash_alpha)
	print(("Boss cinematic: ended after=%.2fs skipped=%s song_target=%.2f song_actual=%s"
			+ " resyncs=%d") % [_elapsed, skipped, song_target, _music.position_text(),
			_music.resyncs()])
	if is_instance_valid(_boss):
		_boss.finish_calm(_elapsed, skipped)


## Toma el mundo y la pantalla. Lo que se toma aquí se devuelve en _release().
func _take_over() -> void:
	var keep: Array[Node] = [self, _boss]
	if _transformation != null:
		keep.append(_transformation)
	_freeze.freeze(get_tree(), keep)
	# Los números de daño que estaban en el aire quedarían ahí toda la calma.
	Pools.release_live_of(Pools.DAMAGE_POPUP_SCENE)
	get_tree().call_group(&"hud", "set_cinematic", true)
	for node: Node in get_tree().get_nodes_in_group(SPLIT_SCREEN_GROUP):
		var split := node as CanvasItem
		if split != null:
			split.visible = false
	_previous_camera = get_viewport().get_camera_3d()
	_camera.make_current()
	_bar_top.visible = true
	_bar_bottom.visible = true
	_title.visible = true
	_subtitle.visible = true
	_skip_hint.visible = true
	_title.modulate.a = 0.0
	_subtitle.modulate.a = 0.0
	_flash.color = Color(flash_color, 0.0)
	_overlay.visible = true
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
	_camera.clear_current(false)
	if _previous_camera != null and is_instance_valid(_previous_camera) \
			and _previous_camera.is_inside_tree():
		_previous_camera.make_current()
	_previous_camera = null
	_bar_top.visible = false
	_bar_bottom.visible = false
	_title.visible = false
	_subtitle.visible = false
	_skip_hint.visible = false
	if _transformation != null and is_instance_valid(_transformation):
		_transformation.set_focus(Vector3.INF)


## La única salida de emergencia: fin de partida, arena que se va, jefe que
## desaparece. Deja todo como lo espera una partida recién empezada.
func _teardown(reason: String) -> void:
	var was_busy := _active or _taken_over or (_music != null and _music.is_live())
	_active = false
	set_process(false)
	if _entrance != null:
		_entrance.stop()
	_release()
	_kill_tween(_flash_tween)
	if _overlay != null:
		_overlay.visible = false
	if _music != null:
		_music.halt()
	if was_busy:
		print("Boss cinematic: teardown reason=%s" % reason)


func _on_run_ended(_victory: bool) -> void:
	_teardown("run_ended")


# --- cámara -----------------------------------------------------------------------

## Fija el encuadre y arranca la entrada: dónde aterriza el jefe, de qué
## lado está la party y qué tan grande es el anillo de fuego.
func _frame_shot() -> void:
	var boss_point := _boss.global_position
	var centroid := Vector3.ZERO
	var count := 0
	for group: StringName in [&"player", &"downed_players"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body != null:
				centroid += body.global_position
				count += 1
	var toward := (centroid / float(maxi(count, 1))) - boss_point
	toward.y = 0.0
	var away := toward.normalized() if toward.length_squared() > 0.01 else Vector3.BACK
	var radius := _entrance.ring_radius_for(toward.length())
	_camera.frame(boss_point, away, radius)
	# Queda de frente al plano héroe (-Z es su frente): así sale de la columna
	# de fuego con las alas abiertas hacia la cámara.
	var facing := _camera.hero_side()
	_boss.rotation.y = atan2(-facing.x, -facing.z)
	_entrance.begin(_boss, boss_point, _camera.side(), radius, calm_seconds)


## Los planos los arma la cámara; aquí solo se le pasa el avance y dónde va
## el fénix. Las brasas del mapa se quedan alrededor del punto de llegada.
func _update_camera(progress: float, delta: float) -> void:
	_camera.shoot(progress, _entrance.bird_point(), _boss.rig.body_height(), delta)
	if progress >= _entrance.reveal_fraction:
		# Ya fuera de la columna, no le saca los ojos de encima a la cámara.
		_boss.rig.gaze_at(_camera.global_position)
	if _transformation != null and is_instance_valid(_transformation):
		_transformation.set_focus(_boss.global_position + Vector3.UP * EMBER_FOCUS_HEIGHT)


# --- cartel -----------------------------------------------------------------------

func _update_overlay(progress: float) -> void:
	var bars := clampf(_elapsed / maxf(bar_seconds, 0.01), 0.0, 1.0)
	var height := bar_height_ratio * smoothstep(0.0, 1.0, bars)
	_bar_top.anchor_bottom = height
	_bar_bottom.anchor_top = 1.0 - height
	var title_at := title_fraction * calm_seconds
	var shown := clampf((_elapsed - title_at) / maxf(title_fade_seconds, 0.01), 0.0, 1.0)
	if progress < title_fraction:
		shown = 0.0
	_title.modulate.a = shown
	_subtitle.modulate.a = shown
	_skip_bar.value = clampf(_skip_held / maxf(skip_hold_seconds, 0.01), 0.0, 1.0) \
			* _skip_bar.max_value


## Un destello a pantalla completa de opacidad `alpha` (0-1): el del golpe
## contra el suelo y el del final de la calma.
func _play_flash(alpha: float) -> void:
	_kill_tween(_flash_tween)
	_overlay.visible = true
	_flash.color = Color(flash_color, alpha)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash, "color:a", 0.0, flash_seconds)
	_flash_tween.tween_callback(_hide_overlay)


## Con el destello apagado el overlay se va, salvo en plena calma: ahí
## siguen las franjas y el cartel.
func _hide_overlay() -> void:
	if not _taken_over:
		_overlay.visible = false


# --- saltar -----------------------------------------------------------------------

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


func _kill_tween(tween: Tween) -> void:
	if tween != null and tween.is_valid():
		tween.kill()
