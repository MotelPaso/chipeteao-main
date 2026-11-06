extends Node
## Autoload "Pools": un NodePool por escena de mucho recambio (gemas de XP,
## orbes, proyectiles, proyectiles enemigos, ráfagas, números de daño,
## discos de aviso) para que las hordas tardías no paguen reservar y liberar
## en cada spawn.
## Los llamadores cambian instantiate/add_child por acquire_scene() y
## queue_free() por release(); lo demás del nodo (transform, parámetros de
## lanzamiento) sigue siendo cosa del llamador.
## acquire_scene() cuelga los nodos de la ARENA de la etapa actual: los que
## están en vuelo mueren con el mapa y los guardados (fuera del árbol)
## cruzan limpios; release_all_live() recupera los que están en vuelo antes
## de que un cambio de etapa libere la arena.
##
## Edita aquí: sumar una escena al pool es UNA fila en POOLS.

const XP_GEM_SCENE: PackedScene = preload("res://scenes/systems/XpGem.tscn")
const HEALTH_ORB_SCENE: PackedScene = preload("res://scenes/systems/HealthOrb.tscn")
const DART_SCENE: PackedScene = preload("res://scenes/weapons/Projectile.tscn")
const ARROW_SCENE: PackedScene = preload("res://scenes/weapons/Arrow.tscn")
const BOOMERANG_SCENE: PackedScene = preload("res://scenes/weapons/BoomerangProjectile.tscn")
const ENEMY_BOLT_SCENE: PackedScene = preload("res://scenes/enemies/EnemyBolt.tscn")
const DEATH_BURST_SCENE: PackedScene = preload("res://scenes/fx/DeathBurst.tscn")
const DAMAGE_POPUP_SCENE: PackedScene = preload("res://scenes/fx/DamagePopup.tscn")
const TELEGRAPH_DISC_SCENE: PackedScene = preload("res://scenes/fx/TelegraphDisc.tscn")
const SLASH_ARC_SCENE: PackedScene = preload("res://scenes/fx/SlashArc.tscn")
const MUZZLE_FLASH_SCENE: PackedScene = preload("res://scenes/fx/MuzzleFlash.tscn")
const WHIP_CRACK_SCENE: PackedScene = preload("res://scenes/fx/WhipCrack.tscn")
const EMBER_BURST_SCENE: PackedScene = preload("res://scenes/fx/EmberBurst.tscn")
const BLOOD_POOL_SCENE: PackedScene = preload("res://scenes/fx/BloodPool.tscn")
const ACID_POOL_SCENE: PackedScene = preload("res://scenes/fx/AcidPool.tscn")

## La lista de pools: name, scene, `warm` (instancias creadas al arrancar
## para que los primeros spawns no tironeen) y `cap` (máximo guardado, que
## acota la memoria tras un pico). Una fila por escena.
const POOLS: Array[Dictionary] = [
	{"name": "gem", "scene": XP_GEM_SCENE, "warm": 48, "cap": 256},
	{"name": "health_orb", "scene": HEALTH_ORB_SCENE, "warm": 4, "cap": 16},
	{"name": "dart", "scene": DART_SCENE, "warm": 16, "cap": 96},
	{"name": "arrow", "scene": ARROW_SCENE, "warm": 16, "cap": 96},
	{"name": "boomerang", "scene": BOOMERANG_SCENE, "warm": 4, "cap": 24},
	{"name": "enemy_bolt", "scene": ENEMY_BOLT_SCENE, "warm": 16, "cap": 96},
	{"name": "death_burst", "scene": DEATH_BURST_SCENE, "warm": 12, "cap": 64},
	{"name": "damage_popup", "scene": DAMAGE_POPUP_SCENE, "warm": 48, "cap": 256},
	{"name": "telegraph_disc", "scene": TELEGRAPH_DISC_SCENE, "warm": 6, "cap": 32},
	{"name": "slash_arc", "scene": SLASH_ARC_SCENE, "warm": 8, "cap": 32},
	{"name": "muzzle_flash", "scene": MUZZLE_FLASH_SCENE, "warm": 6, "cap": 24},
	{"name": "whip_crack", "scene": WHIP_CRACK_SCENE, "warm": 4, "cap": 16},
	{"name": "ember_burst", "scene": EMBER_BURST_SCENE, "warm": 4, "cap": 16},
	{"name": "blood_pool", "scene": BLOOD_POOL_SCENE, "warm": 4, "cap": 16},
	{"name": "acid_pool", "scene": ACID_POOL_SCENE, "warm": 8, "cap": 48},
]

## Override opcional (warm, cap) por nombre para experimentos; las filas que
## no aparecen usan los valores de POOLS.
@export var pool_size_overrides: Dictionary[String, Vector2i] = {}

var _pools_by_path: Dictionary[String, NodePool] = {}


## Gancho del cambio de etapa (RunRoot): cada pool recupera lo que tiene en
## el mundo, para que la arena que se libera no se lleve nada del pool.
func release_all_live() -> void:
	for path: String in _pools_by_path:
		_pools_by_path[path].release_all_live()


func _ready() -> void:
	for row: Dictionary in POOLS:
		_register(String(row["name"]), row["scene"] as PackedScene,
				Vector2i(int(row["warm"]), int(row["cap"])))


## Reemplazo con pool de scene.instantiate() + add_child(): devuelve una
## instancia viva y reiniciada, ya dentro del árbol, o null solo si no hay
## árbol. Una escena sin pool registrado cae a un instantiate normal, así el
## llamador no tiene que saberlo.
func acquire_scene(packed: PackedScene) -> Node3D:
	if packed == null:
		return null
	var parent := _spawn_parent()
	if parent == null:
		return null
	var pool: NodePool = _pools_by_path.get(packed.resource_path, null)
	if pool != null:
		return pool.acquire(parent)
	var node := packed.instantiate() as Node3D
	if node != null:
		parent.add_child(node)
		# El respaldo cumple el mismo contrato que un acquire con pool:
		# XpGem/HealthOrb entran a su grupo vivo dentro de pool_reset(), y sin
		# esto una variante sin pool sería invisible para el imán y el tope.
		if node.has_method(&"pool_reset"):
			node.call(&"pool_reset")
	return node


## Reemplazo con pool de queue_free(): devuelve el nodo al pool que lo creó
## (seguro ante doble liberación); los nodos sin pool solo hacen queue_free.
func release(node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	var pool := node.get_meta(NodePool.META_OWNER, null) as NodePool
	if pool != null and is_instance_valid(pool):
		pool.release(node)
	elif not node.is_queued_for_deletion():
		node.queue_free()


## name -> NodePool.stats() de cada pool (sonda de rendimiento y soaks).
func pool_stats() -> Dictionary[String, Dictionary]:
	var out: Dictionary[String, Dictionary] = {}
	for path: String in _pools_by_path:
		var pool: NodePool = _pools_by_path[path]
		out[String(pool.name)] = pool.stats()
	return out


## Lectura compacta de una línea "nombre creados/guardados" para la sonda.
func stats_line() -> String:
	var parts := PackedStringArray()
	for path: String in _pools_by_path:
		var pool: NodePool = _pools_by_path[path]
		parts.append("%s %d/%d" % [pool.name, pool.total_created, pool.parked_count()])
	return " | ".join(parts)


func _register(pool_name: String, packed: PackedScene, size: Vector2i) -> void:
	if packed == null:
		push_error("Pools: pool '%s' has no scene; skipped." % pool_name)
		return
	if pool_size_overrides.has(pool_name):
		size = pool_size_overrides[pool_name]
	var pool := NodePool.new()
	pool.name = pool_name
	pool.scene = packed
	pool.preload_count = size.x
	pool.max_free = size.y
	add_child(pool)
	_pools_by_path[packed.resource_path] = pool


## Dónde se cuelgan los nodos del pool: la ARENA de la etapa actual, así un
## dardo en vuelo muere con el mapa donde se disparó en vez de seguir a la
## party al siguiente. Sin raíz de partida (los menús) usa current_scene.
func _spawn_parent() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var root := tree.get_first_node_in_group("run_root")
	if root != null and root.has_method("arena_root"):
		var arena: Variant = root.call("arena_root")
		if arena is Node3D and is_instance_valid(arena):
			return arena
	return tree.current_scene if tree.current_scene != null else tree.root
