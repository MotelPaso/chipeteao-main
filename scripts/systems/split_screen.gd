class_name SplitScreen
extends Control
## Pantalla dividida del co-op local (2-4 jugadores), armada en código por
## RunSystems. Un SubViewportContainer por jugador, cada uno con una
## SubViewport que comparte el mundo 3D y una Camera3D seguidora que copia
## cada frame la cámara (desactivada) del SpringArm de ese jugador: la escena
## del jugador sigue manejando la mirada y la colisión del brazo igual que
## en solitario, y esta capa solo presenta. Distribución: 2 jugadores arriba
## y abajo (conserva lo ancho), 3-4 en grilla de 2x2 (la celda vacía con 3
## muestra un panel de relleno). Va en la capa de canvas por defecto, así
## toda UI en CanvasLayer (HUD 5, cartas, pausa 30) se dibuja encima.
## Las cámaras origen también entran a Juice.FEEL_CAMERA_GROUP: así la
## sacudida y el empujón de FOV llegan a la pantalla dividida, donde el
## viewport raíz no tiene cámara activa.

## La vista de un jugador: la cámara que dibuja en su SubViewport y la
## cámara del jugador que copia cada frame.
class CameraPair:
	extends RefCounted
	var follow: Camera3D = null
	var source: Camera3D = null

	func is_live() -> bool:
		return is_instance_valid(follow) and is_instance_valid(source)

	## Todo lo que la vista hereda de la cámara del jugador. Los
	## desplazamientos h/v importan tanto como el transform: Juice escribe en
	## ellos toda la sacudida (sobreviven a que el nodo CameraRig, un
	## SpringArm3D, reescriba el transform del hijo).
	func sync() -> void:
		follow.global_transform = source.global_transform
		follow.fov = source.fov
		follow.h_offset = source.h_offset
		follow.v_offset = source.v_offset
		# La primera persona oculta al propio sello con la máscara de la cámara
		# origen.
		follow.cull_mask = source.cull_mask


var _pairs: Array[CameraPair] = []


## Arma toda la distribución para `players` (Array de cuerpos Player, en
## orden de espacio). Se llama una vez desde RunSystems tras crear la party.
static func build(players: Array) -> SplitScreen:
	var split := SplitScreen.new()
	split.name = "SplitScreen"
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	split.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var count := players.size()
	for i in count:
		# Tipado como Player, no Node3D: view_camera() es contrato de Player, y
		# un `:=` sobre un Node3D no puede inferir su tipo de retorno — eso es
		# un error de PARSEO que tumbaría todo script que precarga este
		# (run_systems.gd).
		var player := players[i] as Player
		if player == null:
			push_error("SplitScreen: slot %d is not a Player body." % i)
			continue
		var source := player.view_camera()
		if source == null:
			push_error("SplitScreen: player %d has no view camera." % i)
			continue
		var rect := cell_rect(i, count)
		var container := SubViewportContainer.new()
		container.name = "View%d" % (i + 1)
		container.stretch = true
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_apply_rect(container, rect)
		split.add_child(container)
		var viewport := SubViewport.new()
		# Comparte el World3D del viewport padre (raíz) por defecto; solo la
		# cámara es local a esta vista.
		viewport.handle_input_locally = false
		# La escala 3D de la calidad gráfica vive en cada viewport, y la del
		# raíz no llega a una SubViewport: entra al grupo que recorre Settings
		# cuando cambia la calidad, y toma la actual ahora.
		viewport.add_to_group(Settings.WORLD_VIEW_GROUP)
		Settings.apply_render_scale(viewport)
		container.add_child(viewport)
		var follow := Camera3D.new()
		follow.fov = source.fov
		follow.near = source.near
		follow.far = source.far
		follow.keep_aspect = source.keep_aspect
		viewport.add_child(follow)
		follow.current = true
		# La capa de sensación (sacudida, FOV) mueve las cámaras ORIGEN y
		# sync() lleva el resultado a esta vista; sin el grupo, Juice buscaría
		# una cámara activa en el viewport raíz y no encontraría ninguna.
		source.add_to_group(Juice.FEEL_CAMERA_GROUP)
		var pair := CameraPair.new()
		pair.follow = follow
		pair.source = source
		split._pairs.append(pair)
	if count == 3:
		split.add_child(_filler_panel())
	return split


func _process(_delta: float) -> void:
	# Después de la física y antes de dibujar: sin latencia extra frente a
	# una cámara hija.
	for pair: CameraPair in _pairs:
		# Validez ANTES de cualquier uso: el par tiene una cámara de otra
		# escena, y convertir una liberada ya es un error.
		if not pair.is_live():
			continue
		pair.sync()


## Rect de anclas (en espacio 0-1) de la celda `index` de `count`. Pública:
## el HUD ancla un minimapa y un mapa por jugador, y ambos tienen que caer
## justo en la celda donde dibuja la cámara de ese jugador. En solitario
## (count <= 1) es toda la ventana.
static func cell_rect(index: int, count: int) -> Rect2:
	match count:
		2:
			return Rect2(0.0, 0.5 * index, 1.0, 0.5)
		1:
			return Rect2(0.0, 0.0, 1.0, 1.0)
		_:
			return Rect2(0.5 * (index % 2), 0.5 * (index >> 1), 0.5, 0.5)


static func _apply_rect(control: Control, rect: Rect2) -> void:
	control.anchor_left = rect.position.x
	control.anchor_top = rect.position.y
	control.anchor_right = rect.position.x + rect.size.x
	control.anchor_bottom = rect.position.y + rect.size.y
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0


## Panel oscuro y quieto sobre el cuadrante libre con 3 jugadores (abajo a
## la derecha).
static func _filler_panel() -> Control:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_rect(panel, Rect2(0.5, 0.5, 0.5, 0.5))
	panel.add_theme_stylebox_override("panel", UiTheme.flat(Color(0.05, 0.055, 0.08), 0))
	var label := Label.new()
	label.text = "BONKRAIDERS"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.25, 0.27, 0.33))
	label.add_theme_font_size_override("font_size", 28)
	panel.add_child(label)
	return panel
