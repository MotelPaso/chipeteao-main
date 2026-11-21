class_name EnemyStage
extends SubViewport
## Escenario 3D de un enemigo para la Colección (EnemyStage.tscn): un
## SubViewport con luces, cámara y un pivote donde se para el cuerpo del
## enemigo. Lo usan EnemyStudio (saca UNA foto por enemigo para las cartas) y
## EnemyPortrait (lo muestra girando en el detalle).
##
## Del enemigo solo entra su nodo Visual (las mallas): la escena se instancia
## fuera del árbol, se le saca ese nodo y el resto se libera, así su IA, su
## vida y su colisión nunca corren aquí. Lo que sí corre es el rig que viva
## bajo Visual (el de un jefe), que anima el modelo. Una escena que no existe
## o que no tiene Visual deja el escenario vacío, sin errores.

## Nombre del nodo con las mallas en cada escena de enemigo.
const VISUAL_NODE := "Visual"

@export_group("Encuadre")
## Aire alrededor del cuerpo: 1.0 lo ajusta justo al borde.
@export var framing_margin: float = 1.25
## Cuánto sube la cámara sobre el centro del cuerpo, como fracción de su alto.
@export var camera_lift: float = 0.18

var _body: Node3D = null

@onready var _camera: Camera3D = $Stage/Camera
@onready var _pivot: Node3D = $Stage/Pivot


## Para en el escenario el cuerpo del enemigo de esa escena y lo encuadra.
## Devuelve false si no hay cuerpo que mostrar.
func show_enemy(scene_path: String) -> bool:
	clear()
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path, "PackedScene"):
		return false
	var scene := load(scene_path) as PackedScene
	var enemy: Node = scene.instantiate() if scene != null else null
	if enemy == null:
		return false
	var visual := enemy.get_node_or_null(VISUAL_NODE) as Node3D
	if visual != null:
		_adopt_parts(visual, enemy)
		enemy.remove_child(visual)
	enemy.free()
	if visual == null:
		return false
	_body = visual
	_pivot.add_child(visual)
	return _frame_camera()


## Saca el cuerpo del escenario.
func clear() -> void:
	if _body != null and is_instance_valid(_body):
		_pivot.remove_child(_body)
		_body.queue_free()
	_body = null


## Gira el cuerpo a ese ángulo (grados): 0 = de frente a la cámara.
func set_angle(degrees: float) -> void:
	_pivot.rotation = Vector3(0.0, deg_to_rad(degrees), 0.0)


## Pasa a `visual` los nodos de su rama que eran de `enemy`. Un rig con
## script (Mythos, la Langosta) busca sus piezas con %Nombre, que se resuelve
## por el owner: sin esto quedarían sin owner al liberar al enemigo.
func _adopt_parts(visual: Node, enemy: Node) -> void:
	for part: Node in visual.find_children("*", "", true, false):
		if part.owner == enemy:
			part.owner = visual


## Aleja la cámara hasta que el cuerpo entero quepa, lo mida lo que mida.
func _frame_camera() -> bool:
	var turned := _pivot.rotation
	_pivot.rotation = Vector3.ZERO
	var bounds := BodyBounds.of(_body, _pivot, 0.0)
	_pivot.rotation = turned
	if bounds.size.is_zero_approx():
		return false
	# El cuerpo gira: su ancho en pantalla llega hasta la diagonal de su base.
	var width := Vector2(bounds.size.x, bounds.size.z).length()
	var height := bounds.size.y
	var aspect := float(size.x) / float(maxi(size.y, 1))
	var half_extent := maxf(height * 0.5, width * 0.5 / aspect) * framing_margin
	var distance := half_extent / tan(deg_to_rad(_camera.fov) * 0.5)
	var target := Vector3(0.0, bounds.get_center().y, 0.0)
	_camera.position = target + Vector3(0.0, height * camera_lift, -distance)
	_camera.look_at(target)
	return true
