class_name ViewWidgets
extends Node
## Minimapa y mapa de Tab de cada vista de jugador. Se crean en código porque
## la cantidad de jugadores se conoce recién al empezar la partida: uno por
## celda de pantalla dividida (SplitScreen.cell_rect), jugador 1 incluido, y
## cada uno en la esquina de SU jugador.
## Todos muestran UN solo MapDraw, que este nodo crea y refresca: la niebla y
## los marcadores se miran una vez por refresco, no una vez por widget.
## El rectángulo del minimapa es el del hijo MinimapSlot (anclado arriba a la
## derecha de la ventana): su tamaño y sus márgenes se repiten en la esquina
## superior derecha de cada celda.

## Precargado y no por class_name: así lo resuelven también las corridas
## headless que no construyeron la caché de clases del editor.
const SplitScreenView := preload("res://scripts/systems/split_screen.gd")
const MINIMAP_SCENE := preload("res://scenes/ui/maps/Minimap.tscn")
const OVERLAY_SCENE := preload("res://scenes/ui/maps/MapOverlay.tscn")

@export_group("Minimapa")
## Margen superior del minimapa, en píxeles, en las celdas que NO tocan el
## borde superior de la ventana (las de arriba usan el de MinimapSlot, que deja
## libre la columna de bajas y FPS).
@export var lower_cell_top_margin: float = 14.0
## Tamaño del minimapa en co-op, como fracción del de MinimapSlot: cada celda
## de pantalla dividida es más chica que la ventana.
@export_range(0.3, 1.0) var coop_size_scale: float = 0.8
@export_group("Mapa")
## Segundos entre refrescos del mapa compartido (niebla y marcadores). La
## vista de cada minimapa sigue a su jugador en cada cuadro; esto es cada
## cuánto se vuelve a mirar qué hay en el mundo.
@export var refresh_seconds: float = 0.1
## Franja de armas y tomos del HUD: el mapa de Tab le pide las fichas de su
## jugador, para mostrarlas igual que el HUD.
@export var build_strip: LoadoutStrip
## Franja de objetos del HUD: el mapa de Tab le pide las fichas de su jugador.
@export var bag_strip: LoadoutStrip

var _map: MapDraw = null
var _refresh_left: float = 0.0
var _minimaps: Array[Minimap] = []
var _overlays: Array[MapOverlay] = []

@onready var _slot: Control = $MinimapSlot


func _process(delta: float) -> void:
	if _map == null:
		return
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = refresh_seconds
	# Un método simple, sin Control: un soak headless ejercita el mapa aunque
	# nada se dibuje.
	_map.refresh()


## Crea los mapas de cada vista; solo la primera llamada hace algo.
func build(player_count: int) -> void:
	if not _minimaps.is_empty():
		return
	_map = MapDraw.new(get_tree())
	_map.build_background()
	var count := maxi(player_count, 1)
	for slot in count:
		var cell := SplitScreenView.cell_rect(slot, count)
		var minimap := _add_minimap(slot, cell, count > 1)
		var overlay := _add_overlay(slot, cell)
		# Con su mapa de Tab abierto, el minimapa de ese jugador sobra y se
		# transparenta bajo los paneles. Por `modulate` y no por `visible`,
		# que es de quien oculta el HUD.
		overlay.visibility_changed.connect(_fade_under.bind(minimap, overlay))


## Gancho de etapa reenviado por el HUD: rehace el suelo del mapa compartido
## con la arena nueva. Los widgets nunca se vuelven a crear.
func on_stage_started(arena: Node3D = null) -> void:
	if _map != null:
		_map.build_background(arena)
	for overlay: MapOverlay in _overlays:
		if is_instance_valid(overlay):
			overlay.on_stage_started(arena)


## Durante una cinemática los minimapas se ocultan y los mapas de Tab se
## cierran y dejan de leer su tecla. Ocultar la capa del HUD no alcanza: una
## CanvasLayer solo oculta a sus hijos directos, y estos cuelgan de este nodo
## (los mapas de Tab, además, en su propia capa).
func set_cinematic(active: bool) -> void:
	for minimap: Minimap in _minimaps:
		if is_instance_valid(minimap):
			minimap.visible = not active
	for overlay: MapOverlay in _overlays:
		if is_instance_valid(overlay):
			overlay.visible = false
			overlay.set_process(not active)


func _anchor_to_cell(control: Control, cell: Rect2) -> void:
	control.anchor_left = cell.position.x
	control.anchor_top = cell.position.y
	control.anchor_right = cell.position.x + cell.size.x
	control.anchor_bottom = cell.position.y + cell.size.y
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0


## El minimapa de `slot`: no llena su celda, cuelga de su esquina superior
## derecha con el tamaño y los márgenes de MinimapSlot.
func _add_minimap(slot: int, cell: Rect2, coop: bool) -> Minimap:
	var minimap_size := Vector2(_slot.offset_right - _slot.offset_left,
			_slot.offset_bottom - _slot.offset_top)
	if coop:
		minimap_size *= coop_size_scale
	var minimap: Minimap = MINIMAP_SCENE.instantiate()
	minimap.slot = slot
	minimap.set_map(_map)
	minimap.anchor_left = cell.position.x + cell.size.x
	minimap.anchor_right = cell.position.x + cell.size.x
	minimap.anchor_top = cell.position.y
	minimap.anchor_bottom = cell.position.y
	minimap.offset_right = _slot.offset_right
	minimap.offset_left = _slot.offset_right - minimap_size.x
	var top := _slot.offset_top if is_zero_approx(cell.position.y) \
			else lower_cell_top_margin
	minimap.offset_top = top
	minimap.offset_bottom = top + minimap_size.y
	add_child(minimap)
	_minimaps.append(minimap)
	return minimap


## El mapa de Tab de `slot`, del tamaño de su celda. Va en su propia
## CanvasLayer (UiLayers.MAP_OVERLAY): dibuja SOBRE el HUD y bajo el selector
## de cartas, y un Control no cruza capas.
func _add_overlay(slot: int, cell: Rect2) -> MapOverlay:
	var layer := CanvasLayer.new()
	layer.layer = UiLayers.MAP_OVERLAY
	add_child(layer)
	var overlay: MapOverlay = OVERLAY_SCENE.instantiate()
	overlay.slot = slot
	overlay.build_strip = build_strip
	overlay.bag_strip = bag_strip
	overlay.set_map(_map)
	_anchor_to_cell(overlay, cell)
	layer.add_child(overlay)
	_overlays.append(overlay)
	return overlay


func _fade_under(minimap: Minimap, overlay: MapOverlay) -> void:
	minimap.modulate.a = 0.0 if overlay.visible else 1.0
