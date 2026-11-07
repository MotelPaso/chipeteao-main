class_name ViewWidgets
extends Node
## Minimapa y mapa de Tab de cada vista de jugador. Se crean en código porque
## la cantidad de jugadores se conoce recién al empezar la partida: uno por
## celda de pantalla dividida (SplitScreen.cell_rect), jugador 1 incluido, y
## cada uno en la esquina de SU jugador.
## El rectángulo del minimapa es el del hijo MinimapSlot (anclado arriba a la
## derecha de la ventana): su tamaño y sus márgenes se repiten en la esquina
## superior derecha de cada celda.

## Precargado y no por class_name: así lo resuelven también las corridas
## headless que no construyeron la caché de clases del editor.
const SplitScreenView := preload("res://scripts/systems/split_screen.gd")
const OVERLAY_SCENE := preload("res://scenes/ui/maps/MapOverlay.tscn")

@export_group("Minimapa")
## Margen superior del minimapa, en píxeles, en las celdas que NO tocan el
## borde superior de la ventana (las de arriba usan el de MinimapSlot, que deja
## libre la columna de bajas y FPS).
@export var lower_cell_top_margin: float = 14.0

var _minimaps: Array[Minimap] = []
var _overlays: Array[MapOverlay] = []

@onready var _slot: Control = $MinimapSlot


## Crea los mapas de cada vista; solo la primera llamada hace algo.
func build(player_count: int) -> void:
	if not _minimaps.is_empty():
		return
	var count := maxi(player_count, 1)
	for slot in count:
		var cell := SplitScreenView.cell_rect(slot, count)
		var minimap := Minimap.new()
		# El minimapa no llena su celda: cuelga de la esquina superior derecha
		# de la celda con el rectángulo de MinimapSlot.
		minimap.anchor_left = cell.position.x + cell.size.x
		minimap.anchor_right = cell.position.x + cell.size.x
		minimap.anchor_top = cell.position.y
		minimap.anchor_bottom = cell.position.y
		minimap.offset_left = _slot.offset_left
		minimap.offset_right = _slot.offset_right
		var top := _slot.offset_top if is_zero_approx(cell.position.y) \
				else lower_cell_top_margin
		minimap.offset_top = top
		minimap.offset_bottom = top + _slot.offset_bottom - _slot.offset_top
		add_child(minimap)
		_minimaps.append(minimap)
		# Su propia CanvasLayer (UiLayers.MAP_OVERLAY): el mapa de Tab dibuja
		# SOBRE el HUD y bajo el selector de cartas, y un Control no cruza capas.
		var layer := CanvasLayer.new()
		layer.layer = UiLayers.MAP_OVERLAY
		add_child(layer)
		var overlay: MapOverlay = OVERLAY_SCENE.instantiate()
		overlay.slot = slot
		_anchor_to_cell(overlay, cell)
		layer.add_child(overlay)
		_overlays.append(overlay)


## Gancho de etapa reenviado por el HUD: refresca el contenido de los mapas,
## nunca los vuelve a crear.
func on_stage_started(arena: Node3D = null) -> void:
	for minimap: Minimap in _minimaps:
		if is_instance_valid(minimap):
			minimap.on_stage_started(arena)
	for overlay: MapOverlay in _overlays:
		if is_instance_valid(overlay):
			overlay.on_stage_started(arena)


func _anchor_to_cell(control: Control, cell: Rect2) -> void:
	control.anchor_left = cell.position.x
	control.anchor_top = cell.position.y
	control.anchor_right = cell.position.x + cell.size.x
	control.anchor_bottom = cell.position.y + cell.size.y
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0
