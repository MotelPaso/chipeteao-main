class_name LobsterTide
extends Node3D
## La MAREA de la Langosta Azul (LobsterTide.tscn, nodo Tide de
## ShipGraveyard.tscn): lo que hace que su arena se sienta bajo el mar además
## de la luz y el paisaje, que son de la escena de la arena.
##   - REFLEJOS de agua sobre el suelo (nodo Caustics: una copia de la malla
##     del terreno que solo suma luz).
##   - CORALES que brotan de la arena por todo el claro (nodos Branches y
##     Bulbs, dos MultiMesh). Son solo decoración: no chocan con nada, y dejan
##     libres el lugar donde aterriza el equipo, el lugar donde aparece la
##     langosta y las coberturas.
##   - BURBUJAS alrededor de cada raider, de pie o caído (el nodo Bubbles es
##     la plantilla). Cada nube es de un raider: si cae uno, las de los demás
##     no cambian de dueño.
## Empieza sola cuando la arena entra al árbol y sube mientras la cinemática
## todavía tiene el mundo congelado (por eso procesa en PAUSABLE): cuando la
## cámara muestra el claro, los corales ya brotaron. Se va con la arena.
## Va después del Terrain en el árbol: copia su malla.
## Contrato por nombre (lo lee el harness): grupo "lobster_tide",
## state_name() y las líneas "Lobster tide:".

enum State { LOW, RISING, HIGH, EBBING }

const GROUP := &"lobster_tide"
## Nombre de cada estado para el harness, en el orden de State.
const STATE_NAMES: Array[StringName] = [&"low", &"rising", &"high", &"ebbing"]

@export_group("Ritmo")
## Segundos que tarda en subir (menos que lo que tarda la cinemática en mostrar el claro).
@export var rise_seconds: float = 4.5
## Segundos que tarda en bajar si alguien le pide ebb(). Hoy nadie lo pide: en el Cementerio de barcos la marea se va con la arena, así que cambiar esto no se nota.
@export var ebb_seconds: float = 3.5

@export_group("Corales")
## Cuántos grupos de corales brotan.
@export var coral_sites: int = 64
## Metros desde el centro de la arena hasta los que brotan.
@export var coral_reach: float = 50.0
## Metros que quedan libres alrededor de donde aterriza el equipo y de donde aparece el jefe (ahí filma la cinemática).
@export var coral_clearance: float = 14.0
## Metros alrededor de cada raider que quedan libres al brotar.
@export var raider_clearance: float = 4.0
## Ramas por grupo, como mínimo.
@export var branches_min: int = 4
## Ramas por grupo, como máximo.
@export var branches_max: int = 7
## Alto mínimo de una rama, en metros.
@export var branch_height_min: float = 0.7
## Alto máximo de una rama, en metros. Más altas que un raider tapan la pelea.
@export var branch_height_max: float = 2.1
## Radio mínimo de una rama, en metros.
@export var branch_radius_min: float = 0.11
## Radio máximo de una rama, en metros.
@export var branch_radius_max: float = 0.24
## Grados que una rama puede inclinarse.
@export var branch_tilt_degrees: float = 26.0
## Radio mínimo del bulbo de la punta, en metros.
@export var bulb_radius_min: float = 0.17
## Radio máximo del bulbo de la punta, en metros.
@export var bulb_radius_max: float = 0.32
## Metros de radio de cada grupo (cuánto se separan sus ramas).
@export var site_radius: float = 0.7

@export_group("Burbujas")
## Metros sobre los pies de cada raider donde se centra su nube de burbujas.
@export var bubble_height: float = 1.5

var _state: State = State.LOW
var _clock: float = 0.0
## Cuánta marea hay ahora (0-1).
var _amount: float = 0.0
## La nube de burbujas de cada raider, por su id de instancia.
var _bubbles: Dictionary[int, CPUParticles3D] = {}

@onready var _branches: MultiMeshInstance3D = $Branches
@onready var _bulbs: MultiMeshInstance3D = $Bulbs
@onready var _caustics: MeshInstance3D = $Caustics
@onready var _bubble_template: CPUParticles3D = $Bubbles


func _ready() -> void:
	add_to_group(GROUP)
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_caustics.visible = false
	_bubble_template.emitting = false
	_show(0.0)
	set_process(false)
	begin()


func _exit_tree() -> void:
	if _state != State.LOW:
		_state = State.LOW
		# Línea de log para los soaks: la marea se fue con su arena.
		print("Lobster tide: gone at %.1fs" % RunState.stage_time)


func _process(delta: float) -> void:
	_follow_raiders()
	if _state == State.RISING:
		_clock += delta
		_show(smoothstep(0.0, 1.0, clampf(_clock / maxf(rise_seconds, 0.01), 0.0, 1.0)))
		if _clock >= rise_seconds:
			_state = State.HIGH
			# Línea de log para los soaks.
			print("Lobster tide: high at %.1fs" % RunState.stage_time)
	elif _state == State.EBBING:
		_clock += delta
		_show(1.0 - smoothstep(0.0, 1.0, clampf(_clock / maxf(ebb_seconds, 0.01), 0.0, 1.0)))
		if _clock >= ebb_seconds:
			queue_free()


# --- lo que piden la arena y el harness -------------------------------------------

## Sube la marea: los reflejos, los corales por todo el claro y las burbujas.
func begin() -> void:
	if _state != State.LOW:
		return
	_lay_caustics()
	_plant_corals()
	_state = State.RISING
	_clock = 0.0
	set_process(true)
	print("Lobster tide: rising over %.1fs at %.1fs" % [rise_seconds, RunState.stage_time])


## Baja la marea y este nodo se libera al terminar.
func ebb() -> void:
	if _state == State.EBBING or _state == State.LOW:
		return
	for cloud: CPUParticles3D in _bubbles.values():
		cloud.emitting = false
	_state = State.EBBING
	_clock = 0.0
	print("Lobster tide: ebbing over %.1fs at %.1fs" % [ebb_seconds, RunState.stage_time])


## En qué anda: "low", "rising", "high" o "ebbing" (lo lee el harness).
func state_name() -> StringName:
	return STATE_NAMES[_state]


# --- decoración -------------------------------------------------------------------

## Cuánta marea se ve (0-1): los corales, los reflejos y las burbujas.
func _show(amount: float) -> void:
	_amount = amount
	for view: GeometryInstance3D in [_branches, _bulbs]:
		var material := view.material_override as ShaderMaterial
		if material != null:
			material.set_shader_parameter(&"rise", amount)
		view.visible = amount > 0.0
	var water := _caustics.material_override as ShaderMaterial
	if water != null:
		water.set_shader_parameter(&"amount", amount)
	_caustics.visible = amount > 0.0 and _caustics.mesh != null


## Pone los reflejos sobre el suelo: la misma malla del terreno, en su lugar.
func _lay_caustics() -> void:
	var terrain := Terrain.find(get_tree())
	if terrain == null:
		return
	var ground := terrain.get_node_or_null(^"MeshInstance3D") as MeshInstance3D
	if ground == null or ground.mesh == null:
		return
	_caustics.mesh = ground.mesh
	_caustics.global_transform = ground.global_transform


## Reparte los grupos de corales por el claro, en lugares donde se puede poner
## algo (_fits_corals), y arma las dos MultiMesh. Usa su propio azar: no toca
## el RNG de la partida.
func _plant_corals() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var bounds := get_tree().get_first_node_in_group(&"arena_bounds")
	var terrain := Terrain.find(get_tree())
	var keep_clear := _clear_points()
	var branches: Array[Transform3D] = []
	var branch_data: Array[Color] = []
	var bulbs: Array[Transform3D] = []
	var bulb_data: Array[Color] = []
	var planted := 0
	var tries := coral_sites * 12
	while planted < coral_sites and tries > 0:
		tries -= 1
		var angle := rng.randf() * TAU
		var site := global_position + Vector3(cos(angle), 0.0, sin(angle)) \
				* coral_reach * sqrt(rng.randf())
		if bounds != null and not _fits_corals(bounds, site):
			continue
		if _near_any(site, keep_clear, coral_clearance) or _near_raider(site):
			continue
		planted += 1
		for _branch: int in rng.randi_range(branches_min, maxi(branches_max, branches_min)):
			var height := rng.randf_range(branch_height_min, branch_height_max)
			var radius := rng.randf_range(branch_radius_min, branch_radius_max)
			var turn := rng.randf() * TAU
			var tilt := deg_to_rad(rng.randf_range(0.0, branch_tilt_degrees))
			var basis := Basis(Vector3.UP, turn) * Basis(Vector3.RIGHT, tilt)
			var foot := site + Vector3(cos(turn), 0.0, sin(turn)) * rng.randf_range(0.0, site_radius)
			foot.y = terrain.height_at(foot.x, foot.z) if terrain != null else site.y
			var delay := rng.randf()
			# El cilindro mide 1 de alto y 1 de diámetro y va centrado.
			branches.append(Transform3D(
					basis * Basis.from_scale(Vector3(radius * 2.0, height, radius * 2.0)),
					foot + basis.y * height * 0.5))
			branch_data.append(Color(delay, 0.0, rng.randf(), 0.0))
			var bulb := rng.randf_range(bulb_radius_min, bulb_radius_max)
			bulbs.append(Transform3D(Basis.from_scale(Vector3.ONE * bulb * 2.0),
					foot + basis.y * height))
			# El bulbo brota después que su rama y se va antes.
			bulb_data.append(Color(minf(delay + 0.35, 1.0), 1.0, rng.randf(), 0.0))
	_fill(_branches.multimesh, branches, branch_data)
	_fill(_bulbs.multimesh, bulbs, bulb_data)


func _fill(multimesh: MultiMesh, transforms: Array[Transform3D], data: Array[Color]) -> void:
	if multimesh == null:
		return
	multimesh.instance_count = transforms.size()
	for index: int in transforms.size():
		multimesh.set_instance_transform(index, transforms[index])
		multimesh.set_instance_custom_data(index, data[index])


## Los lugares que la cinemática necesita despejados: donde aterriza el equipo
## y donde aparece el jefe (los da la arena, si es una BossArena).
func _clear_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	var arena := get_parent() as BossArena
	if arena != null:
		points.append(arena.spawn_origin())
		points.append(arena.boss_origin())
	return points


func _near_any(point: Vector3, places: Array[Vector3], gap: float) -> bool:
	for place: Vector3 in places:
		if Vector2(place.x - point.x, place.z - point.z).length() < gap:
			return true
	return false


## True si en `site` cabe un grupo de corales: dentro del claro y lejos de las
## coberturas (arena_bounds.can_place con site_radius de margen), o al menos
## sobre suelo caminable si el mapa no tiene esa pregunta.
func _fits_corals(bounds: Node, site: Vector3) -> bool:
	var xz := Vector2(site.x, site.z)
	if bounds.has_method(&"can_place"):
		return bool(bounds.call(&"can_place", xz, site_radius))
	return not bounds.has_method(&"is_walkable") or bool(bounds.call(&"is_walkable", xz))


func _near_raider(point: Vector3) -> bool:
	for group: StringName in [&"player", &"downed_players"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			if body != null and body.global_position.distance_to(point) < raider_clearance:
				return true
	return false


## Cada raider lleva su nube de burbujas, de pie o caído (cada vista de la
## pantalla dividida tiene la suya). La nube va con el raider mismo y no con
## su lugar en el grupo "player", que cambia cuando alguien cae o revive.
func _follow_raiders() -> void:
	var seen: Dictionary[int, bool] = {}
	for group: StringName in [&"player", &"downed_players"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var raider := node as Node3D
			if raider == null:
				continue
			var id := raider.get_instance_id()
			seen[id] = true
			if not _bubbles.has(id):
				var cloud := _bubble_template.duplicate() as CPUParticles3D
				add_child(cloud)
				cloud.emitting = _state != State.EBBING
				_bubbles[id] = cloud
			_bubbles[id].global_position = raider.global_position + Vector3.UP * bubble_height
	# La nube de un raider que ya no está en la partida se va con él.
	for id: int in _bubbles.keys():
		if not seen.has(id):
			_bubbles[id].queue_free()
			_bubbles.erase(id)
