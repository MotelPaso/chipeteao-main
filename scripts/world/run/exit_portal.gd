class_name ExitPortal
extends Interactable
## La salida de una etapa (ExitPortal.tscn). Hay uno por etapa: el
## WorldDirector lo levanta lejos del grupo en cuanto RunState.stage_cleared
## pasa a true (meta cumplida y jefe de etapa muerto). Es permanente: no se
## recarga y solo se gasta al usarlo. Su aspecto (más alto y dorado que un
## PortalShrine) está en el nodo Visual de la escena. No sube contador de
## SaveData (meta_stat_id vacío): los de etapa viven en RunState.
##
## Cualquier jugador vivo dentro del anillo puede tomarlo y viaja TODO el
## grupo, caídos incluidos: RunRoot.advance_stage() mueve a todos, así una
## partida co-op nunca queda repartida en dos mapas.
##
## No hereda de PortalShrine: solo comparten el aspecto (PortalVisual), y
## heredar traería la pareja, la recarga y el descuento del Gusano Cósmico,
## que aquí no existen.

@export_group("Aspecto")
## Color del portal; el director también lo usa para su baliza.
@export var portal_color: Color = Color(1.0, 0.82, 0.35)

@export_group("Anillo")
## Radio (metros) del anillo donde hay que pararse.
@export var ring_radius: float = 2.2
## Cuánto más ancha que el anillo es la zona de detección (metros), para que el aviso aparezca un paso antes.
@export var detect_margin: float = 0.8
## Altura (metros) de la zona de detección.
@export var detect_height: float = 4.0

## True desde que alguien lo usa hasta que el cambio de etapa toma el
## control: un segundo jugador en el mismo frame no pide otro cambio.
var _taken: bool = false

@onready var _visual: PortalVisual = $Visual


func _ready() -> void:
	# La zona de detección ANTES de super(), que conecta body_entered.
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = ring_radius + detect_margin
	cylinder.height = detect_height
	shape.shape = cylinder
	shape.position.y = detect_height * 0.5
	add_child(shape)
	super()
	_visual.build(ring_radius, portal_color)


func _interact(_player: Node) -> void:
	if _taken:
		return
	var root := get_tree().get_first_node_in_group("run_root")
	if root == null or not root.has_method("advance_stage"):
		push_warning("ExitPortal: no run root to advance the stage.")
		return
	# Se pregunta ANTES de gastar el portal: advance_stage se niega durante
	# un fundido o con la partida terminada, y el portal tiene que seguir
	# usable en ese caso.
	if not bool(root.call("can_advance_stage")):
		return
	_taken = true
	consume()
	_emit_completed()
	# Mismo prefijo que los portales del mapa, con el tipo escrito: el
	# contador de interacciones del soak ignora la salida a propósito.
	print("Portal used: exit")
	root.call("advance_stage")
