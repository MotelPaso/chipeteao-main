class_name PetBox
extends Interactable
## Caja con una huella: gratis, un solo uso, y una de las dos puertas por las
## que llega un compañero (la otra es el traficante de animales). Tira UNA
## mascota distinta de la que ya sigue al raider y la entrega, o pregunta si
## ya hay compañero, porque el hueco de mascota es uno solo.
##
## Gratis a propósito: el traficante vende una elección de tres por puntos;
## la caja es la que te encuentras, y su precio es caminar hasta ella.

## Títulos de las cartas. La opción 0 es el CAMBIO: el harness siempre aprieta
## la primera, así que la rama interesante tiene que ser esa.
const SWAP_TITLE: String = "Cambiar por %s"
const KEEP_TITLE: String = "Quedarme con %s"
const CHOICE_TITLE: String = "La caja se abre sola"
const NO_PET_LINE: String = "Sin mascota"

@export_group("Caja")
## Color de la huella: tiñe la tapa (Visual/Lid) y el símbolo (Visual/Paw).
@export var paw_color: Color = Color(0.7, 0.95, 0.6)
## Velocidad del vaivén de la tapa, en radianes por segundo.
@export var bob_speed: float = 2.2
## Altura del vaivén de la tapa, en metros.
@export var bob_height: float = 0.05

var _spent: bool = false
var _time: float = 0.0
## Altura de reposo de la tapa, la de la escena.
var _lid_rest_y: float = 0.0

## El material de la tapa es local a la escena: cada caja tiene el suyo.
@onready var _lid: MeshInstance3D = $Visual/Lid
@onready var _paw: Label3D = $Visual/Paw


func _ready() -> void:
	super()
	add_to_group(&"pet_boxes")
	_lid_rest_y = _lid.position.y
	_paint()


func _physics_process(delta: float) -> void:
	_time += delta
	if available:
		_lid.position.y = _lid_rest_y + sin(_time * bob_speed) * bob_height


func _interact(player: Node) -> void:
	if _spent or not available:
		return
	var pet_id := _roll_pet(player)
	if pet_id.is_empty():
		# Todas las mascotas del catálogo son la que ya lo sigue: no hay nada
		# que ofrecer.
		get_tree().call_group("hud", "announce", "La caja está vacía.")
		return
	_spent = true
	_emit_started()
	consume()
	var current: Variant = player.get("pet_id")
	if current == null or String(current).is_empty():
		_grant(player, pet_id)
		return
	# Ya hay compañero: es un CAMBIO, así que se pregunta. open_choice es el
	# único contrato de elección bloqueante y el soak responde la opción 0.
	var offered := PetCatalog.by_id(pet_id)
	var held := PetCatalog.by_id(String(current))
	var options: Array[Dictionary] = [
		{
			"title": SWAP_TITLE % String(offered.display_name),
			"description": _pet_lines(offered),
			"color": offered.get("color", Color.WHITE),
			"pet_id": pet_id,
		},
		{
			"title": KEEP_TITLE % String(held.display_name),
			"description": _pet_lines(held),
			"color": held.get("color", Color.WHITE),
			"pet_id": String(current),
		},
	]
	get_tree().call_group("upgrade_ui", "open_choice", CHOICE_TITLE, options,
			player, _on_choice.bind(player), "pet_box")


func _on_choice(option: Dictionary, player: Node) -> void:
	_grant(player, String(option.get("pet_id", "")))


## Entrega el compañero. Player.set_pet se encarga del cambio, los avisos y
## la línea "Pet joined:", así que aquí solo se informa la caja.
func _grant(player: Node, pet_id: String) -> void:
	# Se imprime ANTES de entregar para que el soak lea causa y luego efecto.
	print("Pet box opened: %s" % pet_id)
	if not pet_id.is_empty() and player.has_method("set_pet"):
		player.call("set_pet", pet_id)
	Juice.sparkle(global_position + Vector3.UP * 1.2)
	_emit_completed()
	sink_away()


## Arma y stat en dos líneas: lo que de verdad distingue a dos compañeros.
static func _pet_lines(row: Dictionary) -> String:
	if row.is_empty():
		return NO_PET_LINE
	return "%s\n%s" % [PetCatalog.weapon_display_name(row),
			String(row.get("stat_label", ""))]


## Una mascota del catálogo que no es la que ya sigue a `player`.
func _roll_pet(player: Node) -> String:
	var current: Variant = player.get("pet_id")
	var held := String(current) if current != null else ""
	var candidates: Array[String] = []
	for row: Dictionary in PetCatalog.PET_LIBRARY:
		if String(row.id) != held:
			candidates.append(String(row.id))
	if candidates.is_empty():
		return ""
	return candidates[randi() % candidates.size()]


## Pinta la tapa y el símbolo de la huella con paw_color.
func _paint() -> void:
	var material := _lid.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = paw_color
		material.emission = paw_color
	_paw.modulate = paw_color
