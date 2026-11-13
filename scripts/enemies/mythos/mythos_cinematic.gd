class_name MythosCinematic
extends Node3D
## Cinemática de llegada de Mythos. Mythos instancia esta escena bajo la
## arena cuando llega y llama a play(); como cuelga de la arena, muere con
## ella. La CANCIÓN la toca su nodo Music (BossSong), que tiene el archivo, el
## volumen y el fundido; aquí solo se le marca el reloj.
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

@export_group("Cámara")
## Fracción de la calma (0-1) que dura el plano general del bosque.
@export_range(0.0, 1.0) var wide_shot_fraction: float = 0.5
## Altura de la cámara en el plano general, en metros sobre el jefe.
@export var wide_height: float = 30.0
## Distancia al jefe al empezar el plano general, en metros.
@export var wide_distance: float = 52.0
## Metros que la cámara avanza hacia el jefe durante el plano general.
@export var wide_push: float = 14.0
## Distancia al jefe en el plano cercano, en metros.
@export var close_distance: float = 16.0
## Altura de la cámara en el plano cercano, en metros sobre el jefe.
@export var close_height: float = 4.0
## Grados que la cámara gira alrededor del jefe durante el plano cercano.
@export var close_orbit_degrees: float = 36.0
## Metros mínimos entre la cámara y el suelo.
@export var ground_clearance: float = 2.0
## Campo de visión de la cámara, en grados.
@export var camera_fov: float = 60.0

@export_group("Cartel")
## Fracción de la calma (0-1) en que aparece el nombre del jefe.
@export_range(0.0, 1.0) var title_fraction: float = 0.58
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
## Color del destello con que termina la calma.
@export var flash_color: Color = Color(1.0, 0.82, 0.5)
## Segundos que dura ese destello.
@export var flash_seconds: float = 0.45

var _boss: Mythos = null
var _transformation: HellTransformation = null
var _freeze: WorldFreeze = WorldFreeze.new()
var _active: bool = false
var _elapsed: float = 0.0
## True mientras este nodo tiene tomados el mundo, el HUD y la cámara.
var _taken_over: bool = false
var _previous_camera: Camera3D = null
var _boss_point: Vector3 = Vector3.ZERO
## Dirección plana desde el jefe hacia la party: de ahí mira la cámara.
var _away: Vector3 = Vector3.BACK
var _skip_held: float = 0.0
var _skip_armed: bool = false
var _flash_tween: Tween = null

@onready var _camera: Camera3D = $Camera
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
	_boss.set_calm_progress(progress)
	_update_camera(progress)
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
	_music.start(calm_seconds)
	var manager := get_tree().get_first_node_in_group("run_manager")
	if manager != null and manager.has_signal("run_ended") \
			and not manager.is_connected("run_ended", _on_run_ended):
		manager.connect("run_ended", _on_run_ended)
	set_process(true)
	_update_camera(0.0)
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


## Nombre base de la acción de saltar (el harness la mantiene).
func skip_action() -> StringName:
	return skip_action_name


## El jefe murió: la canción se apaga de a poco.
func fade_out_song() -> void:
	_music.fade_out()


# --- calma ------------------------------------------------------------------------

## La calma terminó (o alguien la saltó): devuelve la pantalla y avisa al jefe.
func _finish(skipped: bool) -> void:
	_active = false
	set_process(false)
	var song_target := _elapsed
	if skipped:
		if _transformation != null and is_instance_valid(_transformation):
			_transformation.finish_now()
		song_target = calm_seconds
		_music.jump_to(calm_seconds)
	_release()
	_play_flash()
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
	get_tree().call_group(&"hud", "set_cinematic", true)
	for node: Node in get_tree().get_nodes_in_group(SPLIT_SCREEN_GROUP):
		var split := node as CanvasItem
		if split != null:
			split.visible = false
	_previous_camera = get_viewport().get_camera_3d()
	_camera.fov = camera_fov
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
	# clear_current(false): sin pasarle el turno a otra cámara del viewport
	# raíz. En co-op las cámaras de los raiders viven ahí, y con una activa el
	# viewport raíz dibujaría el mundo entero detrás de la pantalla dividida.
	_camera.clear_current(false)
	# En solitario la cámara del raider vuelve a ser la activa; en co-op el
	# viewport raíz se queda sin cámara y pinta la pantalla dividida.
	if not Coop.is_coop() and _previous_camera != null \
			and is_instance_valid(_previous_camera) and _previous_camera.is_inside_tree():
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
	var was_busy := _active or _taken_over or (_music != null and _music.playing)
	_active = false
	set_process(false)
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

## Fija el encuadre: dónde está el jefe y de qué lado está la party.
func _frame_shot() -> void:
	_boss_point = _boss.global_position
	var centroid := Vector3.ZERO
	var count := 0
	for group: StringName in [&"player", &"downed_players"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body != null:
				centroid += body.global_position
				count += 1
	var toward := (centroid / float(maxi(count, 1))) - _boss_point
	toward.y = 0.0
	_away = toward.normalized() if toward.length_squared() > 0.01 else Vector3.BACK


## Plano general que avanza sobre el bosque y después plano cercano que gira
## alrededor del jefe mientras baja.
func _update_camera(progress: float) -> void:
	var from := Vector3.ZERO
	var look := _boss_point + Vector3.UP * 5.0
	if progress < wide_shot_fraction:
		var u := progress / maxf(wide_shot_fraction, 0.01)
		from = _boss_point + _away * (wide_distance - wide_push * u) + Vector3.UP * wide_height
	else:
		var u := (progress - wide_shot_fraction) / maxf(1.0 - wide_shot_fraction, 0.01)
		var angle := deg_to_rad(lerpf(-0.5, 0.5, u) * close_orbit_degrees)
		from = _boss_point + _away.rotated(Vector3.UP, angle) * close_distance \
				+ Vector3.UP * close_height
		look = _boss_point + Vector3.UP * clampf(_boss.rig.body_height(), 2.0, 12.0)
	var terrain := Terrain.find(get_tree())
	if terrain != null:
		from.y = maxf(from.y, terrain.height_at(from.x, from.z) + ground_clearance)
	_camera.look_at_from_position(from, look)
	if _transformation != null and is_instance_valid(_transformation):
		_transformation.set_focus(look)


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


## El destello del golpe con que termina la calma.
func _play_flash() -> void:
	_kill_tween(_flash_tween)
	_overlay.visible = true
	_flash.color = Color(flash_color, 0.85)
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash, "color:a", 0.0, flash_seconds)
	_flash_tween.tween_callback(_hide_overlay)


func _hide_overlay() -> void:
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
