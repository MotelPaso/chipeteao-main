class_name EnemyFreeze
extends RefCounted
## «Tiempo detenido»: congela a la horda y deja libre a la party. Lo maneja
## EnemySpawner (el nodo que ya conoce a todos los enemigos: cuerpos, jefes y
## proyectiles en vuelo), que lo expone con freeze_enemies, is_frozen y
## frozen_bodies.
##
## Un cuerpo congelado queda en PROCESS_MODE_DISABLED con su velocidad
## guardada y puesta en cero: un CharacterBody3D deshabilitado conserva su
## velocidad, y restaurarla al descongelar evita que un enemigo en carga se
## teletransporte la distancia que "debía".
##
## También queda NO SÓLIDO (collision_layer 0) mientras dura: un cuerpo
## deshabilitado no se puede empujar, y ochenta estatuas alrededor de un
## raider lo dejarían soldado en el sitio. Las armas encuentran blancos por
## el GRUPO "enemies" y una prueba de distancia, nunca por capas de colisión
## (ver WeaponBase.enemies_in_disc), así que un congelado sigue recibiendo
## daño: atraviesas la horda y la sigues golpeando.
##
## Los proyectiles enemigos del pool llevan una BANDERA (EnemyBolt.frozen):
## NodePool guarda is_physics_processing() al liberar y lo restaura al
## adquirir, así que un proyectil congelado con set_physics_process(false)
## volvería inerte del pool para siempre.
##
## No procesa solo: EnemySpawner llama tick() desde su _physics_process.

var _spawner: EnemySpawner = null
## Congelado vivo: id de instancia -> cuerpo, para que un cuerpo liberado a
## mitad del congelado simplemente falte al descongelar.
var _frozen: Dictionary[int, Node3D] = {}
var _frozen_velocity: Dictionary[int, Vector3] = {}
## Capa de colisión de cada cuerpo congelado, restaurada al descongelar (un
## enemigo que quedara en 0 se podría atravesar para siempre).
var _frozen_layer: Dictionary[int, int] = {}
var _freeze_left: float = 0.0


func _init(spawner: EnemySpawner) -> void:
	_spawner = spawner


## Congela por `duration` segundos. Renueva a la más larga de las dos
## ventanas, como todo efecto temporizado del spawner.
func freeze(duration: float) -> void:
	_freeze_left = maxf(_freeze_left, duration)
	_freeze_new_bodies()


func is_frozen() -> bool:
	return _freeze_left > 0.0


## Cuerpos congelados ahora mismo (el soak los muestrea).
func frozen_bodies() -> Array[Node3D]:
	var bodies: Array[Node3D] = []
	for id: int in _frozen:
		var body := _frozen[id]
		if is_instance_valid(body):
			bodies.append(body)
	return bodies


func tick(delta: float) -> void:
	if _freeze_left <= 0.0:
		return
	_freeze_left -= delta
	if _freeze_left > 0.0:
		# Lo que nace (o se invoca) durante el congelado también se congela:
		# una horda que sigue entrando no es tiempo detenido.
		_freeze_new_bodies()
		return
	_thaw_all()


func _freeze_new_bodies() -> void:
	var tree := _spawner.get_tree()
	# "burrowed" no es decorativo: un Duneburrower bajo tierra sale de
	# "enemies" a propósito, y sin este grupo sería el único cuerpo que
	# podría dañar a la party durante un congelado.
	for group: StringName in [&"enemies", &"boss", Duneburrower.BURROWED_GROUP]:
		for node: Node in tree.get_nodes_in_group(group):
			var body := node as Node3D
			if body == null or not body.is_inside_tree():
				continue
			var id := body.get_instance_id()
			if _frozen.has(id):
				continue
			_frozen[id] = body
			var character := body as CharacterBody3D
			if character != null:
				_frozen_velocity[id] = character.velocity
				character.velocity = Vector3.ZERO
			var collider := body as CollisionObject3D
			if collider != null:
				_frozen_layer[id] = collider.collision_layer
				collider.collision_layer = 0
			body.process_mode = Node.PROCESS_MODE_DISABLED
	# Grupo que agrega el script de EnemyBolt (contrato por nombre).
	for node: Node in tree.get_nodes_in_group(&"enemy_projectiles"):
		node.set("frozen", true)


func _thaw_all() -> void:
	for id: int in _frozen:
		var body := _frozen[id]
		if not is_instance_valid(body):
			continue
		body.process_mode = Node.PROCESS_MODE_INHERIT
		var character := body as CharacterBody3D
		if character != null:
			character.velocity = _frozen_velocity.get(id, Vector3.ZERO)
		var collider := body as CollisionObject3D
		if collider != null and _frozen_layer.has(id):
			collider.collision_layer = _frozen_layer[id]
	_frozen.clear()
	_frozen_velocity.clear()
	_frozen_layer.clear()
	var tree := _spawner.get_tree()
	for node: Node in tree.get_nodes_in_group(&"enemy_projectiles"):
		node.set("frozen", false)
	tree.call_group("hud", "announce", _spawner.time_stop_end_text)
