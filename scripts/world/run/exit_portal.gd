class_name ExitPortal
extends Interactable
## La salida de una etapa. Hay uno por etapa: el WorldDirector lo levanta
## lejos del grupo en cuanto RunState.stage_cleared pasa a true (meta
## cumplida y jefe de etapa muerto). Se construye en código como el
## PortalShrine, pero más alto, dorado y permanente: no se recarga y solo
## se gasta al usarlo.
##
## Cualquier jugador vivo dentro del anillo puede tomarlo y viaja TODO el
## grupo, caídos incluidos: RunRoot.advance_stage() mueve a todos, así una
## partida co-op nunca queda repartida en dos mapas.
##
## No hereda de PortalShrine: solo comparten el aspecto, y heredar traería
## la pareja, la recarga y el descuento del Gusano Cósmico, que aquí no
## existen.

## Radio (metros) del anillo donde hay que pararse.
@export var ring_radius: float = 2.2
## Color del portal; el director también lo usa para su baliza.
@export var portal_color: Color = Color(1.0, 0.82, 0.35)

## Cilindro de detección = anillo + esto (metros), para que el aviso
## aparezca un paso antes.
const DETECT_MARGIN: float = 0.8
## Más alto que los 6 m del PortalShrine a propósito: tiene que leerse
## como "la salida" desde el otro lado de la arena.
const PILLAR_HEIGHT: float = 11.0
const PILLAR_TOP_RADIUS: float = 1.3
const RING_SPIN: float = 0.55
const IDLE_PULSE_HZ: float = 2.2
const IDLE_PULSE_AMOUNT: float = 0.08

var _pillar: MeshInstance3D = null
var _ring: MeshInstance3D = null
var _time: float = 0.0
## True desde que alguien lo usa hasta que el cambio de etapa toma el
## control: un segundo jugador en el mismo frame no pide otro cambio.
var _taken: bool = false


func _init() -> void:
	prompt_text = "[E] Cruzar al siguiente mapa"
	marker_kind = &"exit"
	prompt_height = 4.2
	# Sin contador propio: los contadores de etapa viven en RunState y se
	# suman una vez al final de la partida.
	meta_stat_id = ""
	collision_layer = 0
	collision_mask = 1
	# Nada en el juego detecta áreas como áreas, así que ser detectable
	# solo ocupa la física. Se fija aquí, antes de entrar al árbol.
	monitorable = false


func _ready() -> void:
	# El anillo de detección ANTES de super(), que conecta body_entered.
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = ring_radius + DETECT_MARGIN
	cylinder.height = 4.0
	shape.shape = cylinder
	shape.position.y = 2.0
	add_child(shape)
	super()
	_build_visual()


func _build_visual() -> void:
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = ring_radius - 0.16
	torus.outer_radius = ring_radius + 0.16
	# Teselado explícito (el del motor es 64 x 32): 32 cortes mantienen
	# redondo un anillo de 2.2 m y 8 lados bastan para un tubo de 16 cm.
	torus.rings = 32
	torus.ring_segments = 8
	_ring.mesh = torus
	_ring.position.y = 0.07
	_ring.material_override = _glow_material(0.95)
	add_child(_ring)
	_pillar = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = PILLAR_TOP_RADIUS
	mesh.bottom_radius = ring_radius
	mesh.height = PILLAR_HEIGHT
	# Teselado explícito: un cono recto no necesita anillos en altura.
	mesh.radial_segments = 24
	mesh.rings = 1
	_pillar.mesh = mesh
	_pillar.position.y = PILLAR_HEIGHT * 0.5
	_pillar.material_override = _glow_material(0.3, true)
	add_child(_pillar)
	var light := OmniLight3D.new()
	light.light_color = portal_color
	light.light_energy = 2.4
	light.omni_range = 9.0
	light.position.y = 2.0
	add_child(light)


## Material propio de esta instancia: así el pulso no pasa a otro portal.
func _glow_material(alpha: float, additive: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(portal_color, alpha)
	material.emission_enabled = true
	material.emission = portal_color
	material.emission_energy_multiplier = 1.8
	return material


func _physics_process(delta: float) -> void:
	_time += delta
	if _ring != null:
		_ring.rotate_y(delta * RING_SPIN)
	if _pillar != null:
		_pillar.scale = Vector3.ONE * (1.0 + sin(_time * IDLE_PULSE_HZ) * IDLE_PULSE_AMOUNT)


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
