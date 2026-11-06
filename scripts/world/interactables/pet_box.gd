class_name PetBox
extends Interactable
## Caja con una huella: gratis, un solo uso, y una de las dos puertas por las
## que llega un compañero (la otra es el traficante de animales). Tira UNA
## mascota distinta de la que ya sigue al raider y la entrega, o pregunta si
## ya hay compañero, porque el hueco de mascota es uno solo.
##
## Gratis a propósito: el traficante vende una elección de tres por puntos;
## la caja es la que te encuentras, y su precio es caminar hasta ella.

@export var paw_color: Color = Color(0.7, 0.95, 0.6)

## Títulos de las cartas. La opción 0 es el CAMBIO: el harness siempre aprieta
## la primera, así que la rama interesante tiene que ser esa.
const SWAP_TITLE: String = "Cambiar por %s"
const KEEP_TITLE: String = "Quedarme con %s"
const CHOICE_TITLE: String = "La caja se abre sola"
const NO_PET_LINE: String = "Sin mascota"

var _spent: bool = false
var _lid: MeshInstance3D = null
var _time: float = 0.0


func _ready() -> void:
	# El anillo de detección va ANTES de super(), que conecta body_entered.
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 2.0
	cylinder.height = 3.0
	shape.shape = cylinder
	shape.position.y = 1.5
	add_child(shape)
	super()
	add_to_group(&"pet_boxes")
	_build_visual()


func _build_visual() -> void:
	var crate := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.3, 1.0, 1.3)
	crate.mesh = box
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.3, 0.2)
	crate.material_override = wood
	crate.position.y = 0.5
	add_child(crate)
	_lid = MeshInstance3D.new()
	var lid_mesh := BoxMesh.new()
	lid_mesh.size = Vector3(1.42, 0.16, 1.42)
	_lid.mesh = lid_mesh
	var lid_material := StandardMaterial3D.new()
	lid_material.albedo_color = paw_color
	lid_material.emission_enabled = true
	lid_material.emission = paw_color
	lid_material.emission_energy_multiplier = 0.8
	_lid.material_override = lid_material
	_lid.position.y = 1.05
	add_child(_lid)
	var paw := Label3D.new()
	paw.text = "●"
	paw.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	paw.no_depth_test = true
	paw.font_size = 44
	paw.outline_size = 10
	paw.modulate = paw_color
	paw.position.y = 1.5
	add_child(paw)


func _physics_process(delta: float) -> void:
	_time += delta
	if _lid != null and available:
		_lid.position.y = 1.05 + sin(_time * 2.2) * 0.05


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

