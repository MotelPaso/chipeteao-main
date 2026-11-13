extends Node
## Autoload MenuBackdrop: el mapa donde se juega, vivo detrás de los menús.
## Instancia la arena de la primera etapa (el Bosque Hueco) sin enemigos,
## altares, cofres ni sonido, y la mira con una cámara que gira lento desde el
## claro de llegada. Encima, cada pantalla de menú pone su nodo Background con
## assets/ui/menu_backdrop.tres: un oscurecido con viñeta para que el texto se
## lea.
##
## El mundo se arma una vez y sigue vivo al cambiar entre pantallas de menú
## (las del grupo "menu_screen"), así que el fondo no se corta entre ellas.
## Se libera antes de empezar una partida (release, lo llama el selector) y se
## vuelve a armar al regresar a un menú.
##
## Sin mundo (headless, o una escena de prueba que abre un menú suelto), el
## oscurecido queda opaco en el color petróleo de respaldo: la pantalla se ve
## completa igual. En headless nunca se arma, porque nada se dibuja y sus
## líneas de log ("Terrain built", "Arena mask") confundirían a los soaks.
## Es un autoload sin escena: edita los valores aquí.

## Grupo de las pantallas que muestran el mapa de fondo.
const MENU_GROUP := &"menu_screen"
## Material compartido del oscurecido; aquí se le cambia `reveal` en vivo.
const SCRIM_MATERIAL: ShaderMaterial = preload("res://assets/ui/menu_backdrop.tres")
## Hijos de la arena que el fondo no usa: enemigos, altares y cofres, viento
## y los muros invisibles.
const STRIPPED_NODES: Array[String] = [
	"EnemySpawner", "Interactables", "AmbientBed", "Perimeter",
]

## Altura de la cámara sobre el suelo del claro, en metros.
const CAMERA_HEIGHT := 3.4
## Inclinación de la cámara, en grados (negativo mira hacia abajo).
const CAMERA_PITCH := -3.0
## Campo de visión de la cámara, en grados.
const CAMERA_FOV := 58.0
## Velocidad del giro, en grados por segundo (2.5 = una vuelta en 2,4 minutos).
const CAMERA_TURN_SPEED := 2.5
## Vaivén vertical de la cámara: altura (metros) y duración de un ciclo (segundos).
const CAMERA_BOB_HEIGHT := 0.12
const CAMERA_BOB_PERIOD := 9.0
## Segundos que tarda el mapa en aparecer tras el color de respaldo.
const REVEAL_TIME := 0.6
## Alcance de las sombras del sol en el menú, en metros: lo lejano queda bajo
## el oscurecido. En calidad Baja (2) el menú no dibuja sombras.
const SHADOW_DISTANCE := 60.0
const NO_SHADOW_QUALITY := 2

var _world: Node3D = null
var _camera: Camera3D = null
var _camera_base: Vector3 = Vector3.ZERO
var _time: float = 0.0
var _reveal_tween: Tween = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	_set_reveal(0.0)
	get_tree().scene_changed.connect(_sync)
	_sync.call_deferred()


func _process(delta: float) -> void:
	_time += delta
	_camera.rotation_degrees = Vector3(CAMERA_PITCH, _time * CAMERA_TURN_SPEED, 0.0)
	_camera.position = _camera_base + Vector3.UP * CAMERA_BOB_HEIGHT \
			* sin(_time * TAU / CAMERA_BOB_PERIOD)


## True mientras el mapa está armado detrás del menú.
func has_world() -> bool:
	return _world != null


## Libera el mapa YA, antes de que entre la escena de partida: la partida
## busca su arena y su terreno por grupo, y no debe encontrar los del menú.
func release() -> void:
	if _reveal_tween != null and _reveal_tween.is_valid():
		_reveal_tween.kill()
	_set_reveal(0.0)
	set_process(false)
	if _world != null:
		_world.free()
	_world = null
	_camera = null


## Tras cada cambio de escena: mapa armado si la escena es un menú, liberado
## si no.
func _sync() -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.is_in_group(MENU_GROUP):
		_build()
	else:
		release()


func _build() -> void:
	if _world != null or DisplayServer.get_name() == "headless":
		return
	var packed := load(String(MapCatalog.by_id(MapCatalog.DEFAULT_ID).scene_path)) as PackedScene
	if packed == null:
		return
	var arena := packed.instantiate() as Node3D
	if arena == null:
		return
	for node_name: String in STRIPPED_NODES:
		var node := arena.get_node_or_null(node_name)
		if node != null:
			arena.remove_child(node)
			node.free()
	_world = Node3D.new()
	_world.name = "MenuWorld"
	_world.add_child(arena)
	add_child(_world)
	_tame_sun(arena)
	_place_camera(arena)
	set_process(true)
	if _reveal_tween != null and _reveal_tween.is_valid():
		_reveal_tween.kill()
	_reveal_tween = create_tween()
	_reveal_tween.set_ignore_time_scale(true)
	_reveal_tween.tween_method(_set_reveal, 0.0, 1.0, REVEAL_TIME) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## Sombras del sol más baratas que en la partida (ver SHADOW_DISTANCE).
func _tame_sun(arena: Node3D) -> void:
	for node: Node in arena.find_children("*", "DirectionalLight3D", true, false):
		var sun := node as DirectionalLight3D
		if SaveData.graphics_quality >= NO_SHADOW_QUALITY:
			sun.shadow_enabled = false
			continue
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = minf(
				sun.directional_shadow_max_distance, SHADOW_DISTANCE)


## La cámara se para en el claro de llegada (el scatter no pone props ahí) y
## solo gira: sin trasladarse, nunca atraviesa un árbol ni una roca.
func _place_camera(arena: Node3D) -> void:
	var at := Vector3.ZERO
	var marker := arena.get_node_or_null(Arena.SPAWN_POINT_NAME) as Node3D
	if marker != null:
		at = marker.global_position
	var terrain := Terrain.find(get_tree())
	if terrain != null:
		at.y = terrain.height_at(at.x, at.z)
	_camera_base = at + Vector3.UP * CAMERA_HEIGHT
	_camera = Camera3D.new()
	_camera.fov = CAMERA_FOV
	_camera.position = _camera_base
	_world.add_child(_camera)
	_camera.make_current()


func _set_reveal(value: float) -> void:
	SCRIM_MATERIAL.set_shader_parameter(&"reveal", value)
