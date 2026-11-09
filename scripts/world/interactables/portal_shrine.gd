class_name PortalShrine
extends Interactable
## Altar portal (PortalShrine.tscn): el WorldDirector pone portales por el
## mapa al inicio de cada etapa y los une en PARES al azar. Con [E] dentro
## de uno, el jugador aparece junto a su pareja; los dos se recargan
## `cooldown` segundos (las copias del Gusano Cósmico del viajero lo
## acortan). Su aspecto está en el nodo Visual de la escena.

## Color que se usa si pair_colors queda vacío.
const FALLBACK_COLOR: Color = Color(0.5, 0.9, 1.0)
## Ángulos de salida que se prueban alrededor de la pareja antes de
## aparecer encima de ella.
const EXIT_ANGLE_TRIES: int = 8
## Altura (metros) a la que se pone al viajero, sobre el suelo.
const EXIT_LIFT: float = 0.2
## Kind del Gusano cósmico; su fila de ItemCatalog lleva recharge_percent.
const WORM_KIND: String = "portal_recharge"

@export_group("Recarga")
## Segundos de recarga de los dos portales tras un viaje.
@export var cooldown: float = 30.0
## Aviso mientras recarga; %d son los segundos que faltan. El aviso listo es prompt_text (grupo «Aviso flotante»).
@export var recharging_prompt: String = "Recargando... %d s"

@export_group("Anillo")
## Radio (metros) del anillo donde hay que pararse.
@export var ring_radius: float = 1.6
## Cuánto más allá del anillo de la pareja aparece el viajero (metros), para no volver a activar el portal por el que acaba de salir.
@export var exit_margin: float = 1.2
## Cuánto más ancha que el anillo es la zona de detección (metros), para que el aviso aparezca un paso antes.
@export var detect_margin: float = 0.6
## Altura (metros) de la zona de detección.
@export var detect_height: float = 3.0

@export_group("Colores")
## Colores de los portales: cada portal toma el de su par (pair_index); si hay más pares que colores, la lista vuelve a empezar.
@export var pair_colors: Array[Color] = [
	Color(0.5, 0.9, 1.0), Color(0.95, 0.6, 1.0), Color(0.6, 1.0, 0.55), Color(1.0, 0.85, 0.4)]

## La pareja de este portal; la pone el director.
var twin: PortalShrine = null
## Índice del par de creación: elige el color de pair_colors. Lo pone el
## director antes de añadir el portal.
var pair_index: int = 0
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
	super()
	_visual.build(ring_radius, pair_color())


## Color de este portal según su par.
func pair_color() -> Color:
	if pair_colors.is_empty():
		return FALLBACK_COLOR
	return pair_colors[pair_index % pair_colors.size()]


## Verdadero si está recargado y tiene pareja.
func is_ready() -> bool:
	return _cooldown_left <= 0.0 and twin != null and is_instance_valid(twin)


func _physics_process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left = maxf(_cooldown_left - delta, 0.0)
		# El visual estrecha el pilar mientras recarga.
		_visual.recharge_fraction = 1.0 - _cooldown_left / maxf(cooldown, 0.01)
		if player_in_range:
			set_prompt(_recharging_text())
	else:
		_visual.recharge_fraction = -1.0


func _recharging_text() -> String:
	return recharging_prompt % ceili(_cooldown_left)


func _on_range_entered() -> void:
	set_prompt(_ready_prompt if is_ready() else _recharging_text())


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
		worms = bag.count_kind(WORM_KIND)
	# Cada Gusano cósmico del viajero acorta la recarga: recarga = cooldown /
	# (1 + recharge_percent/100 x copias), con recharge_percent de su fila.
	var row := ItemCatalog.kind_row(WORM_KIND)
	var per_worm := float(row.get("recharge_percent", 0.0)) / 100.0
	var recharge := cooldown / (1.0 + per_worm * float(worms))
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
