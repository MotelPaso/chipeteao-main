class_name PortalShrine
extends Interactable
## Altar portal (PortalShrine.tscn): StageFixtures pone varios por el mapa al
## inicio de cada etapa, lejos unos de otros. No tienen pareja fija: con [E]
## dentro de uno, el jugador aparece junto a OTRO portal al azar (de los que
## estén recargados). Los dos se recargan `cooldown` segundos (las copias
## del Gusano Cósmico del viajero lo acortan). Su aspecto está en el nodo
## Visual de la escena.

## Grupo de todos los portales de la etapa; el viaje elige destino aquí.
const GROUP: StringName = &"portals"
## Ángulos de salida que se prueban alrededor del destino antes de
## aparecer encima de él.
const EXIT_ANGLE_TRIES: int = 8

## Altura (metros) a la que se pone al viajero, sobre el suelo.
const EXIT_LIFT: float = 0.2
## Kind del Gusano cósmico; su fila de ItemCatalog lleva recharge_percent.
const WORM_KIND: String = "portal_recharge"

@export_group("Recarga")
## Segundos de recarga de los dos portales (el de salida y el de llegada) tras un viaje.
@export var cooldown: float = 30.0
## Aviso mientras recarga; %d son los segundos que faltan. El aviso listo es prompt_text (grupo «Aviso flotante»).
@export var recharging_prompt: String = "Recargando... %d s"

@export_group("Anillo")
## Radio (metros) del anillo donde hay que pararse.
@export var ring_radius: float = 1.6
## Cuánto más allá del anillo del destino aparece el viajero (metros), para no volver a activarlo al llegar.
@export var exit_margin: float = 1.2
## Cuánto más ancha que el anillo es la zona de detección (metros), para que el aviso aparezca un paso antes.
@export var detect_margin: float = 0.6
## Altura (metros) de la zona de detección.
@export var detect_height: float = 3.0

@export_group("Color")
## Color del portal (anillo, pilar y luz).
@export var portal_color: Color = Color(0.5, 0.9, 1.0)

var _cooldown_left: float = 0.0
## El aviso de portal listo (prompt_text de la escena): set_prompt pisa
## prompt_text con el de recarga, así que se guarda al entrar.
var _ready_prompt: String = ""

@onready var _visual: PortalVisual = $Visual


func _ready() -> void:
	_ready_prompt = prompt_text
	# La zona de detección ANTES de super(), que conecta body_entered.
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = ring_radius + detect_margin
	cylinder.height = detect_height
	shape.shape = cylinder
	shape.position.y = detect_height * 0.5
	add_child(shape)
	add_to_group(GROUP)
	super()
	_visual.build(ring_radius, portal_color)


func _physics_process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(_cooldown_left - delta, 0.0)
		# El visual estrecha el pilar mientras recarga.
		_visual.recharge_fraction = 1.0 - _cooldown_left / maxf(cooldown, 0.01)
		if player_in_range:
			set_prompt(_recharging_text())
	else:
		_visual.recharge_fraction = -1.0


## Metros que ocupa alrededor de su centro: el marco de piedra (se arma un
## frame después, así que se calcula) o, si llega más lejos, el punto donde
## aparece quien llega.
func footprint_reach() -> float:
	return maxf(_visual.footprint(ring_radius), ring_radius + exit_margin)


## Verdadero si está recargado.
func is_ready() -> bool:
	return _cooldown_left <= 0.0


## Empieza la recarga del portal (también la llama el portal de salida).
func start_cooldown(seconds: float) -> void:
	_cooldown_left = seconds
	if player_in_range:
		set_prompt(_recharging_text())


func _recharging_text() -> String:
	return recharging_prompt % ceili(_cooldown_left)


func _on_range_entered() -> void:
	set_prompt(_ready_prompt if is_ready() else _recharging_text())


func _interact(player: Node) -> void:
	var body := player as Node3D
	var target := _pick_destination()
	if not is_ready() or body == null or target == null:
		Sfx.play(&"dodge")
		return
	var worms := 0
	var bag := ItemBag.find_in(player)
	if bag != null:
		worms = bag.count_kind(WORM_KIND)
	# Cada Gusano cósmico del viajero acorta la recarga: recarga = cooldown /
	# (1 + recharge_percent/100 x copias), con recharge_percent de su fila.
	var row := ItemCatalog.kind_row(WORM_KIND)
	var per_worm := float(row.get("recharge_percent", 0.0)) / 100.0
	var recharge := cooldown / (1.0 + per_worm * float(worms))
	body.global_position = target.exit_position()
	if body is CharacterBody3D:
		(body as CharacterBody3D).velocity = Vector3.ZERO
	start_cooldown(recharge)
	target.start_cooldown(recharge)
	Juice.sparkle(global_position + Vector3.UP * 1.0)
	Juice.sparkle(target.global_position + Vector3.UP * 1.0)
	Sfx.play(&"burrow_pop")
	SaveData.bump("portals_used")
	print("Portal used: %s -> %s (recharge %.0fs)" % [name, target.name, recharge])


## Punto de llegada justo fuera del anillo de este portal (para no volver a
## activarlo) y en una celda CAMINABLE: la máscara de la arena puede tapar
## una celda entera junto a un portal. Si ningún ángulo sirve, cae encima.
func exit_position() -> Vector3:
	var bounds := get_tree().get_first_node_in_group("arena_bounds")
	var start := randf() * TAU
	for i in EXIT_ANGLE_TRIES:
		var angle := start + TAU * float(i) / float(EXIT_ANGLE_TRIES)
		var candidate := global_position \
				+ Vector3.FORWARD.rotated(Vector3.UP, angle) * (ring_radius + exit_margin) \
				+ Vector3.UP * EXIT_LIFT
		if bounds == null or not bounds.has_method("is_walkable") \
				or bool(bounds.call("is_walkable", Vector2(candidate.x, candidate.z))):
			return candidate
	return global_position + Vector3.UP * EXIT_LIFT


## Otro portal al azar de la etapa, de los recargados; si todos recargan,
## cualquiera de los otros. null si este es el único.
func _pick_destination() -> PortalShrine:
	var ready_ones: Array[PortalShrine] = []
	var others: Array[PortalShrine] = []
	for node: Node in get_tree().get_nodes_in_group(GROUP):
		var portal := node as PortalShrine
		if portal == null or portal == self or portal.is_queued_for_deletion():
			continue
		others.append(portal)
		if portal.is_ready():
			ready_ones.append(portal)
	if not ready_ones.is_empty():
		return ready_ones.pick_random()
	return others.pick_random() if not others.is_empty() else null
