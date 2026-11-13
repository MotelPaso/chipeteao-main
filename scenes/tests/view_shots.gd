class_name ViewShots
extends RefCounted
## Fotos desde PUNTOS FIJOS en momentos elegidos de una partida viva. La
## cámara del soak (ShotCamera) solo ve lo que el raider tenga delante, y
## para juzgar cómo cambia el MAPA hacen falta los mismos encuadres antes y
## después. La usa StageBossProbe con BONK_VIEW_SHOTS=1 y BONK_SHOT_DIR.
##
## Cada llamada a shoot("<momento>") guarda, sin HUD:
##   view_aerial_<momento>.png   3/4 de la arena desde lo alto, SIN niebla
##                               (de lejos la niebla tapa el mapa entero)
##   view_spawn_<momento>.png    a la altura de los ojos desde el spawn
##   view_raider_<momento>.png   desde arriba y atrás del raider líder
## Mientras dispara, la partida sigue: toma prestada la cámara activa unos
## frames y la devuelve. Solo en solitario (en co-op el viewport raíz no
## tiene cámara y la pantalla es de SplitScreen) y nunca en headless.

## Frames dibujados entre mover la cámara y guardar: las cascadas de sombra
## van uno o dos frames atrasadas.
const SETTLE_FRAMES: int = 4
## Frames dibujados antes de tomar la cámara: la foto normal del mismo
## momento (ShotCamera) se guarda un frame después de pedirse, y tiene que
## salir con la cámara del juego.
const LEAD_FRAMES: int = 8
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
	if Coop.is_coop():
		print("View shots skipped: co-op")
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
	while not _queue.is_empty():
		for frame: int in LEAD_FRAMES:
			await RenderingServer.frame_post_draw
		await _shoot_moment(_queue.pop_front())
	_busy = false


func _shoot_moment(moment: String) -> void:
	var tree := _host.get_tree()
	var viewport := _host.get_viewport()
	var previous := viewport.get_camera_3d()
	var hidden := _hide_canvas_roots(tree.root)
	if _camera == null:
		_camera = Camera3D.new()
		_camera.fov = FOV
		_camera.far = 900.0
		_host.add_child(_camera)
	_camera.make_current()
	var terrain := Terrain.find(tree)
	var ground := terrain.height_at(0.0, 0.0) if terrain != null else 0.0
	_camera.look_at_from_position(AERIAL_FROM, AERIAL_LOOK)
	var environment := _environment(tree)
	var had_fog := environment != null and environment.fog_enabled
	if environment != null:
		environment.fog_enabled = false
	await _save(viewport, "view_aerial_%s" % moment)
	if environment != null and is_instance_valid(environment):
		environment.fog_enabled = had_fog
	_camera.look_at_from_position(Vector3(0.0, ground + EYE_HEIGHT, 6.0),
			Vector3(0.0, ground + 2.0, -30.0))
	await _save(viewport, "view_spawn_%s" % moment)
	var raider := _lead_raider(tree)
	if raider != null:
		var at := raider.global_position
		_camera.look_at_from_position(at + Vector3(0.0, RAIDER_UP, RAIDER_BACK),
				at + Vector3.UP * 1.5)
		await _save(viewport, "view_raider_%s" % moment)
	for item: CanvasItem in hidden:
		if is_instance_valid(item):
			item.visible = true
	_restore_camera(tree, previous)


## Devuelve la cámara que estaba activa. Si era la de una cinemática que ya
## terminó, la del raider líder: reactivar una cámara vieja dejaría la
## pantalla mirando donde ya no pasa nada.
func _restore_camera(tree: SceneTree, previous: Camera3D) -> void:
	_camera.clear_current(false)
	var stale := previous == null or not is_instance_valid(previous) \
			or not previous.is_inside_tree()
	if not stale and previous.is_in_group(&"cinematic_camera"):
		stale = true
		for node: Node in tree.get_nodes_in_group(&"boss_cinematic"):
			if node.has_method(&"is_calm_active") and bool(node.call(&"is_calm_active")):
				stale = false
	if not stale:
		previous.make_current()
		return
	var raider := _lead_raider(tree) as Player
	if raider != null and raider.view_camera() != null:
		raider.view_camera().make_current()


func _save(viewport: Viewport, stem: String) -> void:
	for frame: int in SETTLE_FRAMES:
		await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
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


## El Environment que está usando la arena viva, o null.
func _environment(tree: SceneTree) -> Environment:
	var arena := RunRoot.stage_parent(tree)
	if arena == null:
		return null
	for node: Node in arena.find_children("*", "WorldEnvironment", true, false):
		return (node as WorldEnvironment).environment
	return null


## Oculta todo lo 2D que se ve: cada CanvasItem visible que no cuelga de
## otro CanvasItem (los hijos lo siguen). Devuelve lo que ocultó, para
## volver a mostrarlo. Ocultar las CanvasLayer no alcanza: solo tapan a sus
## hijos directos, y los minimapas cuelgan de un Node intermedio.
func _hide_canvas_roots(node: Node) -> Array[CanvasItem]:
	var hidden: Array[CanvasItem] = []
	var item := node as CanvasItem
	if item != null:
		if item.visible and not node.get_parent() is CanvasItem:
			item.visible = false
			hidden.append(item)
		return hidden
	for child: Node in node.get_children():
		hidden.append_array(_hide_canvas_roots(child))
	return hidden
