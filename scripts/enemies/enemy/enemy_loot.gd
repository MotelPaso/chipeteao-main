class_name EnemyLoot
extends RefCounted
## Lo que paga un enemigo al morir además de la gema de XP y los orbes de
## vida (esos dos siguen siendo hooks virtuales de EnemyBase porque BossBase
## los cambia): puntos, power-up, charco de lluvia ácida y cofres. Todo
## estático; EnemyBase._on_died lo llama en un orden fijo (orden del RNG).

const CHEST_SCENE := preload("res://scenes/world/chests/Chest.tscn")
## Máximo de cofres de recompensa shiny SIN abrir a la vez en el mapa. Edita
## aquí. No caducan y su probabilidad crece con la dificultad; cada uno es un
## Area3D, una caja sólida que la horda trepa y un marcador de mapa. Pasado
## el tope, una baja shiny no suelta cofre hasta que se abra uno o cambie la
## etapa (el patrón de HealthOrb.at_soft_cap). Los anillos de jefe no
## cuentan. ArenaProbe lo lee como EnemyBase.BOUNTY_CHEST_CAP.
const BOUNTY_CHEST_CAP: int = 30
const BOUNTY_CHEST_GROUP: StringName = &"bounty_chests"
## Suerte extra del cofre shiny por punto de dificultad de la partida. Edita aquí.
const ELITE_CHEST_LUCK_PER_DIFFICULTY: float = 15.0

## Cofres que el tope se tragó en este proceso; limita la frecuencia del log.
static var _capped_drops: int = 0


## Los puntos de partida van al raider en pie MÁS CERCANO (en co-op, quien
## estaba en lo más denso), nunca repartidos: la economía es por jugador.
static func award_points(body: EnemyBase) -> void:
	if body.points_value <= 0:
		return
	var player := Coop.nearest_player(body.get_tree(), body.global_position)
	if player != null and player.has_method("add_points"):
		player.call("add_points", body.points_value)


## Lluvia radiactiva: todo cadáver deja un charco mientras dura. El director
## lo pasa a su nodo Weather (WeatherDirector.spawn_acid_pool), que lleva el
## tope y el espaciado y se niega solo si el clima no está activo.
static func drop_acid_pool(body: Node3D) -> void:
	var director := body.get_tree().get_first_node_in_group("world_director")
	if director != null and director.has_method("spawn_acid_pool"):
		director.call("spawn_acid_pool", body.global_position)


## Power-up temporal. La probabilidad base es mínima a propósito (tiene que
## sentirse como un evento, no como botín) y la mueve la stat
## powerup_drop_chance («Fortuna menor») del raider más cercano, que es dueño
## de la tirada. Los shiny tiran un múltiplo. La ESTRELLA nunca cae aquí: se
## encuentra rondando el mapa (star_sighting del WorldDirector).
static func drop_powerup(body: EnemyBase) -> void:
	var tree := body.get_tree()
	var spawner := tree.get_first_node_in_group("enemy_spawner")
	if spawner == null or not spawner.has_method("roll_powerup_drop"):
		return
	var player := Coop.nearest_player(tree, body.global_position)
	if not bool(spawner.call("roll_powerup_drop", player, body.is_elite)):
		return
	spawner.call("spawn_powerup_pickup", body.global_position + Vector3.UP * 0.8,
			PowerUpCatalog.roll_id(true))


## Cofre de recompensa shiny junto a `body`: gratis, con una inclinación de
## suerte que crece con la dificultad. Se salta en BOUNTY_CHEST_CAP.
static func drop_bounty_chest(body: EnemyBase) -> void:
	if bounty_chests_at_cap(body.get_tree()):
		_capped_drops += 1
		# Una línea cada 25 cofres tragados: tarde en la partida el tope puede
		# saltar varias veces por segundo, y el harness busca la primera línea.
		if _capped_drops % 25 == 1:
			print("Elite chest capped: %d unopened (x%d)" % [
					BOUNTY_CHEST_CAP, _capped_drops])
		return
	var chest := spawn_chest(body,
			body.global_position + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)),
			ELITE_CHEST_LUCK_PER_DIFFICULTY * RunState.difficulty_bonus)
	if chest != null:
		chest.add_to_group(BOUNTY_CHEST_GROUP)
		# Un cofre gratis no tiene rareza todavía (la tira al abrirse), así que
		# el log dice lo que ES en vez de una cadena vacía.
		print("Elite chest dropped: free")


## Cofres de recompensa sin abrir en el mapa. Uno abierto sigue en el grupo
## mientras se hunde (Chest._sink lo libera al terminar su tween), así que
## decide `available`, no la pertenencia.
static func unopened_bounty_chests(tree: SceneTree) -> int:
	var count := 0
	for node: Node in tree.get_nodes_in_group(BOUNTY_CHEST_GROUP):
		var chest := node as Interactable
		if chest != null and chest.available:
			count += 1
	return count


static func bounty_chests_at_cap(tree: SceneTree) -> bool:
	return unopened_bounty_chests(tree) >= BOUNTY_CHEST_CAP


## Suelta un cofre gratis en `at`, colgado de la RAÍZ de la escena para
## sobrevivir al cadáver de `body`; devuelve null si no hay escena donde
## soltarlo (cierre de la partida) o si la raíz de Chest.tscn no es un Chest.
## Por aquí pasan el cofre shiny y el anillo del jefe (EnemyBase.spawn_chest).
## Todo cofre soltado por un CUERPO es gratis: ya se pagó al matarlo.
## `min_rarity` vacío conserva el piso de la escena.
static func spawn_chest(body: Node, at: Vector3, luck_bonus: float,
		min_rarity: String = "") -> Chest:
	var parent := RunRoot.stage_parent(body.get_tree())
	if parent == null:
		parent = body.get_parent()
	if parent == null:
		return null
	var chest := CHEST_SCENE.instantiate() as Chest
	if chest == null:
		push_warning("EnemyBase: Chest scene root is not a Chest.")
		return null
	if not min_rarity.is_empty():
		chest.min_rarity = min_rarity
	chest.luck_bonus = luck_bonus
	chest.free_open = true
	parent.add_child(chest)
	chest.global_position = at
	return chest


## Un orbe de vida del pool en `at`, salvo en el tope global de orbes vivos.
## Se comprueba por orbe, así el pago múltiple de un jefe llena justo hasta
## el tope.
static func spawn_health_orb(tree: SceneTree, at: Vector3) -> void:
	if HealthOrb.at_soft_cap(tree):
		return
	var orb := Pools.acquire_scene(Pools.HEALTH_ORB_SCENE) as HealthOrb
	if orb == null:
		return
	orb.global_position = at
