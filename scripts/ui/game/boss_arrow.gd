extends Node2D
## Indicador de objetivo en el borde de la pantalla: mientras un cuerpo del
## grupo "boss" vive fuera de la pantalla (o detrás de la cámara), una flecha
## ámbar pegada a los bordes apunta hacia él, para volver a encontrar una
## pelea que quedó atrás. Sigue al jefe vivo más cercano (un jefe muerto sale
## del grupo al morir, lo que oculta la flecha sin más cables) y sirve para
## los minijefes ocultos (mismo grupo). Vive en la capa del HUD; toda consulta
## de cámara o viewport está protegida, así que las corridas headless y las
## escenas sin cámara no fallan.
##
## Hoy una sola flecha sirve a toda la ventana. SplitScreen podría darle una a
## cada celda con bind_view(camera, carrier); mientras no lo haga, en co-op
## apunta con la primera cámara de pantalla dividida que encuentra y desplaza
## el resultado por la esquina de esa celda.

## Distancia (px) que la punta de la flecha guarda de los bordes de la pantalla.
@export var edge_margin: float = 56.0
## Margen (px) dentro del viewport que aún cuenta como "en pantalla": evita
## que la flecha parpadee mientras un jefe va justo por el borde.
@export var on_screen_inset: float = 24.0
## Altura (metros) sobre el origen del jefe a la que se apunta (pecho, no pies).
@export var aim_height: float = 1.2

## Segundos entre intentos de encontrar una cámara de pantalla dividida
## mientras no hay ninguna. La búsqueda recorre el árbol, así que nunca corre
## cada cuadro, y en solo no corre nunca (el viewport raíz tiene su cámara).
const CAMERA_RESCAN := 0.5

## Vista inyectada (ver bind_view): la cámara por la que apunta esta flecha y
## el jugador desde el que mide distancias. Ambos nulos = respaldos de solo.
var _camera: Camera3D = null
var _carrier: Node3D = null
## Cámara de respaldo en co-op, buscada a lo más cada CAMERA_RESCAN.
var _fallback_camera: Camera3D = null
var _rescan_left: float = 0.0
## Objetivo que no es jefe, mostrado mientras no vive ninguno (ver track_objective).
var _objective: Node3D = null


func _ready() -> void:
	visible = false


## Entrada para pantalla dividida: una flecha por vista, cada una apunta con
## la cámara de ESA vista y mide desde SU jugador. Sin ella la flecha usa la
## cámara del viewport raíz (solo) y el jugador de pie con la ranura más baja.
func bind_view(camera: Camera3D, carrier: Node3D) -> void:
	_camera = camera
	_carrier = carrier


## Apunta la flecha a algo que no es un jefe (el portal de salida de la
## etapa). Un jefe vivo siempre gana (una pelea pendiente pesa más que una
## puerta que puedes usar cuando quieras), así que esto es un objetivo de
## respaldo, no un reemplazo. Se borra pasando null, y se suelta solo cuando
## el nodo desaparece (el portal se consume al usarse).
func track_objective(node: Node3D) -> void:
	_objective = node


func _process(delta: float) -> void:
	var camera := _resolve_camera(delta)
	if camera == null:
		visible = false
		return
	var view := camera.get_viewport()
	var marked := _current_target()
	if marked == null or view == null:
		visible = false
		return
	var target := marked.global_position + Vector3.UP * aim_height
	var placement := compute_placement(camera.unproject_position(target),
			camera.is_position_behind(target), view.get_visible_rect().size)
	visible = bool(placement["visible"])
	if visible:
		# La posición está en el espacio del viewport de la CÁMARA; en
		# pantalla dividida eso es una celda de la ventana, así que se desplaza
		# por el origen de la celda.
		position = (placement["position"] as Vector2) + _view_origin(view)
		rotation = float(placement["angle"])


## La cámara con la que apuntar: la inyectada; si no, la del viewport raíz
## (solo); si no, la primera vista de pantalla dividida viva. Ese último
## respaldo mantiene viva la flecha en co-op: cada cámara de jugador se
## desactiva en favor de una cámara por SubViewport (player.gd/SplitScreen),
## así que el viewport raíz NO tiene cámara activa en toda la partida.
func _resolve_camera(delta: float) -> Camera3D:
	if is_instance_valid(_camera):
		return _camera
	var viewport := get_viewport()
	var camera := viewport.get_camera_3d() if viewport != null else null
	if camera != null:
		return camera
	if is_instance_valid(_fallback_camera) and _fallback_camera.is_inside_tree():
		return _fallback_camera
	_rescan_left -= delta
	if _rescan_left > 0.0:
		return null
	_rescan_left = CAMERA_RESCAN
	_fallback_camera = _find_split_view_camera()
	return _fallback_camera


func _find_split_view_camera() -> Camera3D:
	var tree := get_tree()
	if tree == null:
		return null
	for node: Node in tree.root.find_children("*", "SubViewport", true, false):
		var camera := (node as SubViewport).get_camera_3d()
		if camera != null:
			return camera
	return null


## Origen de un viewport en la ventana: cero para el raíz, la esquina de la
## celda para un SubViewport dentro de un SubViewportContainer.
func _view_origin(view: Viewport) -> Vector2:
	var container := view.get_parent() as SubViewportContainer
	return container.global_position if container != null else Vector2.ZERO


## El cuerpo desde el que se miden distancias: el inyectado; si no, el jugador
## DE PIE con la ranura más baja. Nunca get_first_node_in_group("player"): un
## jugador caído sale del grupo y uno reanimado vuelve al final, así que ese
## orden cambia en la partida y la flecha saltaría entre jefes sin razón visible.
func _resolve_reference() -> Node3D:
	if is_instance_valid(_carrier):
		return _carrier
	var tree := get_tree()
	if tree == null:
		return null
	var best: Node3D = null
	var best_slot := Coop.MAX_PLAYERS
	for node: Node in tree.get_nodes_in_group(&"player"):
		var body := node as Node3D
		if body == null:
			continue
		var slot := int(body.get("player_index"))
		if slot < best_slot:
			best_slot = slot
			best = body
	return best


## Matemática de pantalla pura, aparte para que un arnés headless la
## verifique. Recibe el objetivo proyectado por la cámara, si está detrás del
## plano de la cámara y el tamaño del viewport; devuelve {"visible": bool,
## "position": Vector2, "angle": float}. Un objetivo fuera de pantalla se
## recorta al rectángulo de edge_margin sobre el rayo desde el centro; el arte
## de la flecha apunta a +X, así que el ángulo del rayo es también la rotación
## del nodo.
func compute_placement(unprojected: Vector2, behind: bool,
		viewport_size: Vector2) -> Dictionary:
	var center := viewport_size * 0.5
	var pos := unprojected
	if behind:
		# unproject refleja los objetivos detrás del plano de la cámara; se
		# reflejan de vuelta por el centro para que la flecha apunte hacia
		# donde girarías.
		pos = center * 2.0 - pos
	if not behind and Rect2(Vector2.ZERO, viewport_size) \
			.grow(-on_screen_inset).has_point(pos):
		return {"visible": false, "position": Vector2.ZERO, "angle": 0.0}
	var dir := pos - center
	if dir.length_squared() < 0.0001:
		dir = Vector2.DOWN  # justo detrás de la cámara: "está detrás de ti"
	dir = dir.normalized()
	# Escala el rayo central hasta el primer borde del rectángulo de margen que cruza.
	var half := center - Vector2(edge_margin, edge_margin)
	half.x = maxf(half.x, 4.0)
	half.y = maxf(half.y, 4.0)
	var t := INF
	if absf(dir.x) > 0.0001:
		t = minf(t, half.x / absf(dir.x))
	if absf(dir.y) > 0.0001:
		t = minf(t, half.y / absf(dir.y))
	return {"visible": true, "position": center + dir * t, "angle": dir.angle()}


## Lo que la flecha señala ahora: el jefe vivo más cercano; si no hay, el
## objetivo seguido mientras exista. La referencia solo ordena a los jefes
## entre sí, así que con el grupo "boss" vacío (casi toda la partida) no se
## busca ni al jugador de referencia ni a los jefes.
func _current_target() -> Node3D:
	if get_tree().get_node_count_in_group(&"boss") > 0:
		var boss := _nearest_live_boss(_resolve_reference())
		if boss != null:
			return boss
	if _objective != null and not is_instance_valid(_objective):
		_objective = null
	if _objective != null and not _objective.is_inside_tree():
		return null
	return _objective


## Miembro del grupo "boss" dentro del árbol más cercano a `reference`, si la
## hay (dos jefes vivos es raro pero posible: minijefe más el jefe del
## horario). Con referencia nula todos están a distancia 0 y gana el primero
## del grupo, suficiente para un arnés sin cámara.
func _nearest_live_boss(reference: Node3D) -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
	var best: Node3D = null
	var best_distance := INF
	for node: Node in tree.get_nodes_in_group(&"boss"):
		var boss := node as Node3D
		if boss == null or not boss.is_inside_tree():
			continue
		var distance := 0.0
		if reference != null:
			distance = boss.global_position.distance_squared_to(reference.global_position)
		if distance < best_distance:
			best_distance = distance
			best = boss
	return best
