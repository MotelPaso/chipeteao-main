class_name PortalShrine
extends Interactable
## Altar portal: el WorldDirector pone portales por el mapa al inicio de
## cada etapa y los une en PARES al azar. Con [E] dentro de uno, el jugador
## aparece junto a su pareja; los dos se recargan `cooldown` segundos (las
## copias del Gusano Cósmico del viajero lo acortan).
## Se construye en código (anillo, pilar de luz y forma de detección).

## Segundos de recarga de los dos portales tras un viaje.
@export var cooldown: float = 30.0
## Cuánto acorta la recarga cada Gusano Cósmico del viajero:
## recarga = cooldown / (1 + esto x copias).
@export var worm_cooldown_per_copy: float = 0.25
## Radio (metros) del anillo donde hay que pararse.
@export var ring_radius: float = 1.6
## Cuánto más allá del anillo de la pareja aparece el viajero (metros),
## para no volver a activar el portal por el que acaba de salir.
@export var exit_margin: float = 1.2

## Aspecto en reposo del anillo y el pilar.
const RING_SPIN: float = 0.8
const IDLE_PULSE_HZ: float = 3.0
const IDLE_PULSE_AMOUNT: float = 0.05
const PILLAR_HEIGHT: float = 6.0
const PILLAR_TOP_RADIUS: float = 0.9
## Cilindro de detección = anillo + esto (metros), para que el aviso
## aparezca un paso antes.
const DETECT_MARGIN: float = 0.6
## Ángulos de salida que se prueban alrededor de la pareja antes de
## aparecer encima de ella.
const EXIT_ANGLE_TRIES: int = 8
## Altura (metros) a la que se pone al viajero, sobre el suelo.
const EXIT_LIFT: float = 0.2

var twin: PortalShrine = null
var pair_color: Color = Color(0.5, 0.9, 1.0)
var _cooldown_left: float = 0.0
var _pillar: MeshInstance3D = null
var _ring: MeshInstance3D = null
var _time: float = 0.0


func _init() -> void:
	prompt_text = "[E] Atravesar"
	marker_kind = &"portal"
	prompt_height = 3.0
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
	cylinder.height = 3.0
	shape.shape = cylinder
	shape.position.y = 1.5
	add_child(shape)
	super()
	_build_visual()


func _build_visual() -> void:
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = ring_radius - 0.12
	torus.outer_radius = ring_radius + 0.12
	# Teselado explícito (el del motor es 64 x 32): 32 cortes mantienen
	# redondo un anillo de 1.6 m y 8 lados bastan para un tubo de 12 cm.
	torus.rings = 32
	torus.ring_segments = 8
	_ring.mesh = torus
	_ring.position.y = 0.06
	_ring.material_override = _glow_material(0.9)
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
	_pillar.material_override = _glow_material(0.28, true)
	add_child(_pillar)
	var light := OmniLight3D.new()
	light.light_color = pair_color
	light.light_energy = 1.8
	light.omni_range = 7.0
	light.position.y = 1.5
	add_child(light)


## Material propio de esta instancia: así el pulso no pasa a otro portal.
func _glow_material(alpha: float, additive: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(pair_color, alpha)
	material.emission_enabled = true
	material.emission = pair_color
	material.emission_energy_multiplier = 1.4
	return material


## Verdadero si está recargado y tiene pareja.
func is_ready() -> bool:
	return _cooldown_left <= 0.0 and twin != null and is_instance_valid(twin)


func _physics_process(delta: float) -> void:
	_time += delta
	if _ring != null:
		_ring.rotate_y(delta * RING_SPIN)
	if _cooldown_left > 0.0:
		# Mientras recarga, el pilar se estrecha y vuelve a crecer.
		_cooldown_left = maxf(_cooldown_left - delta, 0.0)
		var fraction := 1.0 - _cooldown_left / maxf(cooldown, 0.01)
		if _pillar != null:
			_pillar.scale = Vector3(0.3 + 0.7 * fraction, 1.0, 0.3 + 0.7 * fraction)
		if player_in_range:
			set_prompt(_recharging_text())
	elif _pillar != null:
		_pillar.scale = Vector3.ONE * (1.0 + sin(_time * IDLE_PULSE_HZ) * IDLE_PULSE_AMOUNT)


func _recharging_text() -> String:
	return "Recargando... %d s" % ceili(_cooldown_left)


func _on_range_entered() -> void:
	set_prompt("[E] Atravesar" if is_ready() else _recharging_text())


func _interact(player: Node) -> void:
	if not is_ready():
		Sfx.play(&"dodge")
		return
	var body := player as Node3D
	if body == null:
		return
	var worms := 0
	var bag := ItemBag.find_in(player)
	if bag != null:
		worms = bag.count("cosmic_worm")
	var recharge := cooldown / (1.0 + worm_cooldown_per_copy * float(worms))
	body.global_position = _exit_position()
	if body is CharacterBody3D:
		(body as CharacterBody3D).velocity = Vector3.ZERO
	start_cooldown(recharge)
	twin.start_cooldown(recharge)
	Juice.sparkle(global_position + Vector3.UP * 1.0)
	Juice.sparkle(twin.global_position + Vector3.UP * 1.0)
	Sfx.play(&"burrow_pop")
	SaveData.bump("portals_used")
	print("Portal used: %s -> %s (recharge %.0fs)" % [name, twin.name, recharge])


## Punto de llegada justo fuera del anillo de la pareja (para no volver a
## activarla) y en una celda CAMINABLE: la máscara de la arena puede
## tapar una celda entera junto a un portal. Si ningún ángulo sirve, cae
## sobre la pareja, cuya celda está abierta.
func _exit_position() -> Vector3:
	var bounds := get_tree().get_first_node_in_group("arena_bounds")
	var start := randf() * TAU
	for i in EXIT_ANGLE_TRIES:
		var angle := start + TAU * float(i) / float(EXIT_ANGLE_TRIES)
		var candidate := twin.global_position \
				+ Vector3.FORWARD.rotated(Vector3.UP, angle) * (ring_radius + exit_margin) \
				+ Vector3.UP * EXIT_LIFT
		if bounds == null or not bounds.has_method("is_walkable") \
				or bool(bounds.call("is_walkable", Vector2(candidate.x, candidate.z))):
			return candidate
	return twin.global_position + Vector3.UP * EXIT_LIFT


## Empieza la recarga de este portal (también la llama su pareja).
func start_cooldown(seconds: float) -> void:
	_cooldown_left = seconds
	if player_in_range:
		set_prompt(_recharging_text())
