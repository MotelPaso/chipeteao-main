class_name CoverPerch
extends RefCounted
## LA REGLA DE LAS COBERTURAS de una arena de jefe (la aplica BossField en
## cada frame de física): una cobertura es para esconderse detrás, no para
## pararse encima. Un raider que queda de pie (o caído) sobre una, más alto
## que la arena, baja pasado un instante al lugar libre más cercano. Así nadie
## pelea desde donde el jefe no alcanza, y a un caído se lo reanima desde el
## suelo.
## Llega a los raiders por sus grupos ("player" y "downed_players").

var _field: BossField = null
## Segundos que lleva cada raider (por id de instancia) parado sobre una cobertura.
var _on_top: Dictionary[int, float] = {}


func _init(field: BossField) -> void:
	_field = field


## Mide a cada raider y baja al que ya pasó `seconds` sobre una cobertura, a
## más de `height` metros de la arena. `margin`: metros que guarda al bajar.
func tick(delta: float, seconds: float, height: float, margin: float) -> void:
	var tree := _field.get_tree()
	var terrain := Terrain.find(tree)
	var still_on_top: Dictionary[int, float] = {}
	for group: StringName in [&"player", &"downed_players"]:
		for node: Node in tree.get_nodes_in_group(group):
			var body := node as CharacterBody3D
			if body == null or not _is_on_top(body, terrain, height):
				continue
			var id := body.get_instance_id()
			var held: float = _on_top.get(id, 0.0) + delta
			if held >= seconds:
				_step_down(body, terrain, margin)
				continue
			still_on_top[id] = held
	_on_top = still_on_top


## True si `body` está apoyado dentro de la huella de una cobertura y más de
## `height` metros sobre la arena: encima de ella.
func _is_on_top(body: CharacterBody3D, terrain: Terrain, height: float) -> bool:
	if not body.is_on_floor():
		return false
	var at := body.global_position
	if _field.cover_distance(Vector2(at.x, at.z)) > 0.0:
		return false
	var ground := terrain.height_at(at.x, at.z) if terrain != null else 0.0
	return at.y - ground > height


func _step_down(body: CharacterBody3D, terrain: Terrain, margin: float) -> void:
	var at := body.global_position
	var spot := _field.nearest_place(Vector2(at.x, at.z), margin)
	var y := terrain.height_at(spot.x, spot.y) if terrain != null else at.y
	body.global_position = Vector3(spot.x, y, spot.y)
	body.velocity = Vector3.ZERO
	if body.has_method(&"anchor_here"):
		body.call(&"anchor_here")
	# Línea de log para los soaks: un raider bajó de una cobertura.
	print("Boss field: raider stepped off a cover at (%.1f, %.1f) to (%.1f, %.1f) at %.1fs" % [
			at.x, at.z, spot.x, spot.y, RunState.stage_time])
