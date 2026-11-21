class_name ViewShots
extends RefCounted
## Fotos desde PUNTOS FIJOS en momentos elegidos de una partida viva. La
## cámara del soak (ShotCamera) solo ve lo que el raider tenga delante, y
## para juzgar cómo cambia el MAPA hacen falta los mismos encuadres antes y
## después. La usa StageBossProbe con BONK_VIEW_SHOTS=1 y BONK_SHOT_DIR.
##
## Cada llamada a shoot("<momento>") guarda:
##   view_aerial_<momento>.png   3/4 de la arena desde lo alto, SIN niebla
##                               (de lejos la niebla tapa el mapa entero)
##   view_spawn_<momento>.png    a la altura de los ojos desde el spawn
##   view_raider_<momento>.png   desde arriba y atrás del raider líder
## Las fotos salen de un SubViewport propio con su cámara: mira el mismo
## mundo 3D que la partida, pero no dibuja nada 2D (ni HUD ni mapa de Tab) y
## no le quita la cámara a nadie, así la partida y la cinemática siguen
## igual mientras dispara. Nunca en headless: ahí no se dibuja nada.

## Frames dibujados entre mover la cámara y guardar: las cascadas de sombra
## van uno o dos frames atrasadas.
const SETTLE_FRAMES: int = 4
## Tamaño de cada foto, en píxeles.
const SIZE := Vector2i(1280, 720)
const AERIAL_FROM := Vector3(0.0, 95.0, 135.0)
const AERIAL_LOOK := Vector3(0.0, 0.0, 10.0)
## Altura de los ojos sobre el suelo, en metros (como en TerrainShots).
const EYE_HEIGHT: float = 3.2
## Desde dónde mira al raider líder: metros hacia atrás (+Z) y hacia arriba.
const RAIDER_BACK: float = 15.0
const RAIDER_UP: float = 10.0
const FOV: float = 70.0

var _host: Node = null
var _dir: String = ""
var _on: bool = false
var _viewport: SubViewport = null
var _camera: Camera3D = null
var _queue: Array[String] = []
var _busy: bool = false


func _init(host: Node, dir: String, wanted: bool) -> void:
	_host = host
	_dir = dir
	if not wanted or dir.is_empty():
		return
	if DisplayServer.get_name() == "headless":
		print("View shots skipped: headless")
		return
	_on = true
	print("View shots on: dir=%s" % _dir)


func enabled() -> bool:
	return _on


## Encola las fotos de `moment`; se toman de a una tanda.
func shoot(moment: String) -> void:
	if not _on:
		return
	_queue.append(moment)
	if not _busy:
		_run()


func _run() -> void:
	_busy = true
	_ensure_viewport()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	while not _queue.is_empty():
		await _shoot_moment(_queue.pop_front())
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_busy = false


## El SubViewport de las fotos: sin mundo propio, así que dibuja el de la
## partida. Solo se actualiza mientras hay fotos pendientes.
func _ensure_viewport() -> void:
	if _viewport != null:
		return
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.msaa_3d = _host.get_viewport().msaa_3d
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_camera = Camera3D.new()
	_camera.fov = FOV
	_camera.far = 900.0
	_viewport.add_child(_camera)
	_host.add_child(_viewport)
	_camera.make_current()


func _shoot_moment(moment: String) -> void:
	var tree := _host.get_tree()
	var terrain := Terrain.find(tree)
	var ground := terrain.height_at(0.0, 0.0) if terrain != null else 0.0
	_camera.look_at_from_position(AERIAL_FROM, AERIAL_LOOK)
	# Sin niebla solo para ESTA cámara: una copia del Environment de la arena
	# puesta como override de la cámara, sin tocar el de la partida.
	_camera.environment = _fogless_environment(tree)
	await _save("view_aerial_%s" % moment)
	_camera.environment = null
	_camera.look_at_from_position(Vector3(0.0, ground + EYE_HEIGHT, 6.0),
			Vector3(0.0, ground + 2.0, -30.0))
	await _save("view_spawn_%s" % moment)
	var raider := _lead_raider(tree)
	if raider != null:
		var at := raider.global_position
		_camera.look_at_from_position(at + Vector3(0.0, RAIDER_UP, RAIDER_BACK),
				at + Vector3.UP * 1.5)
		await _save("view_raider_%s" % moment)


func _save(stem: String) -> void:
	for frame: int in SETTLE_FRAMES:
		await RenderingServer.frame_post_draw
	var image := _viewport.get_texture().get_image()
	var path := "%s/%s.png" % [_dir, stem]
	if image == null or image.save_png(path) != OK:
		push_warning("ViewShots: cannot write '%s'" % path)
		return
	print("View shot saved: %s" % path)


func _lead_raider(tree: SceneTree) -> Node3D:
	for group: StringName in [&"player", &"downed_players"]:
		for node: Node in tree.get_nodes_in_group(group):
			var body := node as Node3D
			if body != null and int(body.get("player_index")) == 0:
				return body
	return null


## Una copia sin niebla del Environment que está usando la arena viva, o
## null si no hay.
func _fogless_environment(tree: SceneTree) -> Environment:
	var arena := RunRoot.stage_parent(tree)
	if arena == null:
		return null
	for node: Node in arena.find_children("*", "WorldEnvironment", true, false):
		var source := (node as WorldEnvironment).environment
		if source == null:
			return null
		var copy := source.duplicate() as Environment
		copy.fog_enabled = false
		return copy
	return null
