class_name BeltBolt
extends WeaponBase
## Brazo de daño del Cinturón eléctrico. Es un WeaponBase solo para usar
## deal_damage: crítico, robo de vida y los ganchos de objetos al golpear y al
## matar llegan gratis, y un objeto que tirara su propio daño sería la única
## fuente del juego donde no puede caer un crítico.
##
## Es hijo de la BOLSA DE OBJETOS, nunca del montaje "Weapons" del Player:
## todo lo que enumera armas (la tira del HUD, el tope de armas, el pool de
## mejoras) recorre ese montaje, y un rayo ahí aparecería como un arma que el
## raider nunca eligió y contaría contra el tope.
##
## Nunca dispara solo: fire() está vacío y el proceso de física apagado. La
## bolsa llama a zap_chain() cuando el raider derrapa; ese es todo el gatillo.

# --- edita aquí --------------------------------------------------------------
# BeltBolt no tiene escena (ItemBag lo crea con BeltBolt.new()), así que sus
# ajustes son estas constantes y no aparecen en el Inspector. El aspecto del
# rayo está en scenes/fx/LightningBeam.tscn, grupo «Cinturón eléctrico».

## Daño del primer golpe con una sola copia del cinturón.
const BELT_DAMAGE: float = 25.0
## Alcance desde el raider hasta el primer blanco, en metros.
const FIRST_RANGE: float = 10.0
## Daño extra por cada copia después de la primera (0.35 = +35%).
const DAMAGE_PER_EXTRA_COPY: float = 0.35
## Rebotes después del primer blanco; cada copia del cinturón suma uno más.
const BASE_BOUNCES: int = 2
## Alcance de cada rebote desde el último cuerpo golpeado, en metros.
const BOUNCE_RANGE: float = 8.0
## Por debajo de este largo, en metros, un rayo es un punto y no se dibuja.
const MIN_BEAM_LENGTH: float = 0.2
## Altura a la que se dibuja el rayo, en metros: a la altura del pecho y no raspando el suelo.
const BEAM_HEIGHT: float = 0.9
# --- fin de edita aquí -------------------------------------------------------

const LIGHTNING_BEAM_SCENE: PackedScene = preload("res://scenes/fx/LightningBeam.tscn")


func _ready() -> void:
	# Nunca con reloj propio: WeaponBase._physics_process buscaría blanco cada
	# enfriamiento y llamaría a fire(), y esta arma solo existe para el derrape.
	set_physics_process(false)


## Contrato de WeaponBase. Vacío a propósito: ver el comentario de la clase.
func fire(_target: Node3D) -> void:
	pass


## EL gatillo: ItemBag lo llama en cada derrape. Devuelve cuántos cuerpos
## golpeó la cadena, para que la bolsa imprima una línea por derrape.
## `origin` llega como parámetro porque ItemBag extiende Node y NO tiene
## transformada: un Node3D hijo suyo está en el origen del mundo, y leer la
## posición propia apuntaría cada cadena desde el centro del mapa.
func zap_chain(origin: Vector3, copies: int) -> int:
	var hits := 0
	var struck: Array[Node3D] = []
	var from := origin
	var reach := FIRST_RANGE
	var remaining := BASE_BOUNCES + copies + 1
	# deal_damage lee `damage`: se fija en cada derrape según las copias.
	damage = BELT_DAMAGE * (1.0 + DAMAGE_PER_EXTRA_COPY * float(maxi(copies - 1, 0)))
	while remaining > 0:
		var target := _nearest_unstruck(from, reach, struck)
		if target == null:
			break
		struck.append(target)
		_spawn_beam(from, target.global_position)
		var health := Health.find_in(target)
		if health != null and not health.is_dead:
			# Por deal_damage, así el cinturón hace crítico, roba vida y
			# alimenta los ganchos de muerte como un arma real.
			deal_damage(health)
			hits += 1
		from = target.global_position
		reach = BOUNCE_RANGE
		remaining -= 1
	return hits


## Enemigo vivo más cercano a `from` dentro de `reach` que esta cadena aún no
## golpeó. Usa el grupo como todo barrido de blanco, así los cuerpos poseídos
## (que salen del grupo "enemies") nunca reciben el rayo del grupo.
func _nearest_unstruck(from: Vector3, reach: float, struck: Array[Node3D]) -> Node3D:
	var best: Node3D = null
	var best_distance := reach * reach
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var body := node as Node3D
		if body == null or not body.is_inside_tree() or struck.has(body):
			continue
		var distance := from.distance_squared_to(body.global_position)
		if distance <= best_distance:
			best_distance = distance
			best = body
	return best


## Un segmento de rayo a la altura del pecho entre dos cuerpos.
func _spawn_beam(from: Vector3, to: Vector3) -> void:
	var start := from + Vector3.UP * BEAM_HEIGHT
	var end := to + Vector3.UP * BEAM_HEIGHT
	if (end - start).length() < MIN_BEAM_LENGTH:
		return
	var beam := spawn_fx_scene(LIGHTNING_BEAM_SCENE) as LightningBeam
	beam.play(start, end, LightningBeam.Style.BELT)
