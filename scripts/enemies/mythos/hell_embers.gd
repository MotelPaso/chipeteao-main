class_name HellEmbers
extends RefCounted
## Las brasas y el humo del infierno para HellTransformation: una nube de
## cada una por raider (en pantalla dividida cada vista tiene las suyas), que
## lo sigue esté de pie o caído. Las brasas son copias del nodo Embers de
## HellTransformation.tscn y el humo, instancias de su smoke_scene: el humo
## va en escena aparte porque una escena con dos GPUParticles3D deja un
## shader sin liberar al cerrar sin ventana.

var _embers: Array[GPUParticles3D] = []
var _smokes: Array[GPUParticles3D] = []


## Crea las nubes bajo `host`: `ember_template` es la primera nube de brasas
## (las demás son copias) y `smoke_scene` la escena del humo.
func spawn(host: Node, ember_template: GPUParticles3D, smoke_scene: PackedScene) -> void:
	for slot: int in maxi(Coop.player_count, 1):
		var embers := ember_template if slot == 0 \
				else ember_template.duplicate() as GPUParticles3D
		if slot > 0:
			host.add_child(embers)
		embers.emitting = true
		_embers.append(embers)
		var smoke := smoke_scene.instantiate() as GPUParticles3D \
				if smoke_scene != null else null
		if smoke != null:
			smoke.emitting = false
			host.add_child(smoke)
			_smokes.append(smoke)


## Cada nube sigue a su raider. Con `focus` distinto de INF la primera nube
## va a ese punto (lo que mira la cinemática).
func follow(tree: SceneTree, focus: Vector3) -> void:
	for group: StringName in [&"player", &"downed_players"]:
		for node: Node in tree.get_nodes_in_group(group):
			var body := node as Node3D
			var slot := int(node.get("player_index"))
			if body == null or slot < 0 or slot >= _embers.size():
				continue
			var at := body.global_position
			if slot == 0 and focus != Vector3.INF:
				at = focus
			_embers[slot].global_position = at
			if slot < _smokes.size():
				_smokes[slot].global_position = at


## Deja en el aire esta fracción de las brasas (0-1).
func set_ember_ratio(ratio: float) -> void:
	for embers: GPUParticles3D in _embers:
		embers.amount_ratio = ratio


## Enciende el humo del bosque carbonizado.
func start_smoke() -> void:
	for smoke: GPUParticles3D in _smokes:
		smoke.emitting = true
