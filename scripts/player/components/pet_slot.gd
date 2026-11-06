class_name PetSlot
extends Node
## Espacio de mascota de un raider. Hay uno solo: una mascota nueva
## reemplaza a la anterior, arma y stat incluidos. Solo lo llenan la caja de
## mascotas y el traficante de animales, nunca un cofre ni la ruleta. Es el
## nodo PetSlot de Player.tscn; el resto del juego usa Player.pet_id y
## Player.set_pet() por nombre.

@export_group("Avisos")
## Texto del aviso cuando llega una mascota; va después de su nombre ("Doki se une").
@export var joins_text: String = "se une"
## Texto del aviso cuando se va una mascota; va después de su nombre ("Doki se despide").
@export var leaves_text: String = "se despide"

## Mascota actual ("" = ninguna); Player.pet_id la lee.
var pet_id: String = ""

@onready var _body: Player = get_parent() as Player


## Cambia la mascota: libera el nodo Pet anterior, crea el nuevo como hijo
## del raider, avisa los dos cambios con el toast de botín y recalcula los
## stats, que leen pet_id. Con "" solo vacía el espacio.
func set_pet(new_pet_id: String) -> void:
	if new_pet_id == pet_id:
		return
	var leaving := PetCatalog.by_id(pet_id)
	# Por TIPO y no por nombre: queue_free deja el nodo como hijo hasta el
	# final del frame, y con dos set_pet en el mismo frame add_child
	# renombraría la mascota nueva y quedarían dos siguiendo al raider.
	for child: Node in _body.get_children():
		var old_pet := child as Pet
		if old_pet != null:
			old_pet.queue_free()
	pet_id = new_pet_id
	if not leaving.is_empty():
		_announce(_title(leaving, leaves_text),
				PetCatalog.weapon_display_name(leaving), leaving)
	if not pet_id.is_empty():
		var row := PetCatalog.by_id(pet_id)
		if row.is_empty():
			push_warning("Player: unknown pet '%s'" % pet_id)
			pet_id = ""
		else:
			var pet := Pet.new()
			pet.setup(row)
			_body.add_child(pet)
			_announce(_title(row, joins_text),
					String(row.get("stat_label", "")), row)
			# Log de una línea. Va aquí y no en los vendedores: es la única
			# puerta de entrada de una mascota.
			print("Pet joined: %s" % pet_id)
	var stats := PlayerStats.find_in(_body)
	if stats != null:
		stats.recompute()


## Título del toast: el nombre de la mascota y el texto del cambio, para
## que un cambio se lea como cambio y no como regalo.
func _title(row: Dictionary, change_text: String) -> String:
	return "%s %s" % [String(row.display_name), change_text]


func _announce(title: String, description: String, row: Dictionary) -> void:
	get_tree().call_group("hud", "show_loot", title, description,
			row.get("color", Color.WHITE) as Color, _body.player_index)
