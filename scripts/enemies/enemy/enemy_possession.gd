class_name EnemyPossession
extends RefCounted
## Estado de un enemigo poseído: siervo de un raider por un tiempo. Pelea
## contra los enemigos, ellos lo ignoran y no paga nada al morir (ya pagó
## como el cadáver del que se levantó). Lo crea EnemyBase.make_possessed y
## dura mientras dura la posesión; EnemyBase._pick_target es el único cambio
## de bando.

## Capa de colisión del siervo: fuera de la de enemigos (2) y de la de mundo
## y jugadores (1).
const LAYER: int = 8
## Distancia en metros a la que un siervo busca con quién pelear. Edita aquí.
const SEEK_RANGE: float = 30.0

## El raider al que sirve.
var carrier: Node3D
## Segundos de posesión que le quedan.
var time_left: float
## Lo marca EnemyBase.end_possession para que los dos caminos que llegan ahí
## (el reloj y la muerte del portador en el mismo frame) no liberen el
## cuerpo dos veces.
var expiring: bool = false


func _init(owner_carrier: Node3D, duration: float) -> void:
	carrier = owner_carrier
	time_left = duration


## Pasa a `body` al bando del equipo. SALE del grupo "enemies" (declarado en
## la raíz de su escena), así dejan de verlo las armas del raider, la cuenta
## viva del spawner y el tiempo detenido: los tres recorren ese grupo. Pasa
## a su propia capa y suma una excepción de colisión por raider: los
## jugadores comparten la capa 1 con el mundo, y una máscara que lo dejara
## atravesar raiders también lo dejaría atravesar el terreno.
static func switch_sides(body: CharacterBody3D) -> void:
	body.remove_from_group("enemies")
	body.add_to_group(EnemyBase.POSSESSED_GROUP)
	body.collision_layer = LAYER
	body.collision_mask = 1
	for group: String in ["player", "downed_players"]:
		for node: Node in body.get_tree().get_nodes_in_group(group):
			var other := node as CollisionObject3D
			if other != null:
				body.add_collision_exception_with(other)


## Enemigo vivo más cercano a `from` dentro de SEEK_RANGE. El grupo VIVO a
## propósito, no la foto del tick: un cuerpo que entra a "enemies" a mitad
## del tick (uno recién aparecido, un gusano que sale) tiene que ser
## objetivo en este mismo tick.
static func nearest_enemy(tree: SceneTree, from: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance := SEEK_RANGE * SEEK_RANGE
	for node: Node in tree.get_nodes_in_group(&"enemies"):
		var body := node as Node3D
		if body == null or not body.is_inside_tree():
			continue
		var distance := from.distance_squared_to(body.global_position)
		if distance <= best_distance:
			best_distance = distance
			best = body
	return best


## Avanza el reloj; true cuando la posesión tiene que terminar (se acabó el
## tiempo o el portador ya no está en el árbol).
func tick(delta: float) -> bool:
	time_left -= delta
	return time_left <= 0.0 or not is_instance_valid(carrier) \
			or not carrier.is_inside_tree()
