class_name Bridge
extends StaticBody3D
## Puente fijo sobre un cañón: un tablero de madera sobre una CALZADA
## MACIZA de piedra que baja hasta el fondo. Escena:
## scenes/world/props/Bridge.tscn.
##
## Por qué maciza: un enemigo que cae al cañón persigue en línea recta y
## termina bajo el tablero. Sin nada contra qué empujar no trepa, y el
## puente sería un refugio. Contra el costado de la calzada sí trepa, como
## contra cualquier pared, y sale al tablero.
##
## El origen está en el centro de la cara de arriba del tablero; el tablero
## corre a lo largo de X. Quien lo coloca le da `span` y `drop` ANTES de
## add_child: _ready dimensiona las piezas. Las dos mallas y la forma de
## colisión son de cada instancia (resource_local_to_scene en la escena):
## este script les cambia el tamaño.
##
## Sin costados que sobresalgan ni barandas: lo que se ve es lo que bloquea,
## y un alero bajo el tablero le cortaría la trepada a la horda.

@export_group("Medidas")
## Largo del puente, en metros: de dentro de una cabecera a dentro de la otra.
@export var span: float = 23.0
## Ancho del tablero y de la calzada, en metros.
@export var width: float = 5.0
## Metros que la calzada baja desde la cara de arriba del tablero. Tiene que
## pasar el fondo del cañón.
@export var drop: float = 8.0
## Grosor del tablero de madera, en metros.
@export var deck_thickness: float = 0.3

@onready var _deck: MeshInstance3D = $Deck
@onready var _body: MeshInstance3D = $Body
@onready var _collision: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	var deck_mesh := _deck.mesh as BoxMesh
	deck_mesh.size = Vector3(span, deck_thickness, width)
	_deck.position = Vector3(0.0, -deck_thickness * 0.5, 0.0)
	var body_height := maxf(drop - deck_thickness, 0.1)
	var body_mesh := _body.mesh as BoxMesh
	body_mesh.size = Vector3(span, body_height, width)
	_body.position = Vector3(0.0, -deck_thickness - body_height * 0.5, 0.0)
	var box := _collision.shape as BoxShape3D
	box.size = Vector3(span, drop, width)
	_collision.position = Vector3(0.0, -drop * 0.5, 0.0)


## Los dos extremos del tablero, en el mundo, a la altura donde se pisa.
func deck_ends() -> PackedVector3Array:
	var reach := global_transform.basis.x * (span * 0.5)
	return PackedVector3Array([global_position - reach, global_position + reach])
