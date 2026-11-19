class_name LobsterTide
extends Node3D
## La MAREA de la Langosta Azul (LobsterTide.tscn): mientras ella vive, el
## mapa queda como bajo el mar. La langosta la instancia bajo la arena cuando
## llega (nodo Arrival de BlueLobster.tscn) y le pide ebb() cuando muere.
##   - El CIELO se va al azul: sol, ambiente, niebla, colores del cielo y
##     horizonte. Usa el mismo ayudante de cielo de arena que el infierno de
##     Mythos (HellSky) y le dice al clima cuál es ahora el cielo «original»
##     (WorldDirector.rebase_sky), así una luna o una lluvia que termine en
##     plena pelea vuelve al azul. Al bajar la marea devuelve el de antes.
##   - REFLEJOS de agua sobre el suelo (nodo Caustics: una copia de la malla
##     del terreno que solo suma luz).
##   - CORALES que brotan del suelo alrededor (nodos Branches y Bulbs, dos
##     MultiMesh). Son solo decoración: no chocan con nada.
##   - BURBUJAS alrededor de cada raider (el nodo Bubbles es la plantilla).
## Nunca toca un recurso compartido: el cielo es la copia propia de la arena,
## y todo lo demás cuelga de este nodo y se va con él.
## Procesa aunque el mundo esté congelado: sube durante la entrada de la
## langosta, así cuando la cámara muestra el mapa ya está azul.
## Si el mapa ya tiene otra transformación (el infierno de Mythos), no le
## toca el cielo: solo retira lo suyo.
## Contrato por nombre (lo lee el harness): grupo "lobster_tide" y
## state_name().

enum State { LOW, RISING, HIGH, EBBING }

const GROUP := &"lobster_tide"
## Grupo de la transformación de mapa de un jefe de etapa (HellTransformation).
const OTHER_TRANSFORMATION_GROUP := &"stage_transformation"
## Nombre de cada estado para el harness, en el orden de State.
const STATE_NAMES: Array[StringName] = [&"low", &"rising", &"high", &"ebbing"]

@export_group("Ritmo")
## Segundos que tarda en subir (menos que lo que tarda la entrada en mostrar el mapa).
@export var rise_seconds: float = 4.5
## Segundos que tarda en bajar cuando la langosta muere.
@export var ebb_seconds: float = 3.5

@export_group("Cielo de la marea")
## Color del cielo arriba.
@export var sky_top: Color = Color(0.02, 0.1, 0.3)
## Color del cielo en el horizonte.
@export var sky_horizon: Color = Color(0.1, 0.38, 0.66)
## Color del suelo lejano en el horizonte (parte baja del cielo).
@export var ground_horizon: Color = Color(0.06, 0.26, 0.48)
## Color de la parte más baja del cielo.
@export var ground_bottom: Color = Color(0.01, 0.05, 0.15)
## Color del sol. Con poco rojo los raiders y lo que brilla en tonos cálidos se apagan: no lo bajes de 0.5.
@export var sun_color: Color = Color(0.62, 0.82, 1.0)
## Energía del sol.
@export var sun_energy: float = 1.0
## Color de la luz ambiente. Igual que el sol: con muy poco rojo todo lo cálido se ve gris.
@export var ambient_color: Color = Color(0.36, 0.52, 0.96)
## Energía de la luz ambiente.
@export var ambient_energy: float = 1.15
## Color de la niebla.
@export var fog_color: Color = Color(0.08, 0.32, 0.62)
## Densidad de la niebla (el bosque trae 0.007).
@export var fog_density: float = 0.016
## Color del suelo lejano del horizonte.
@export var backdrop_ground: Color = Color(0.05, 0.2, 0.38)
## Color de las colinas del horizonte.
@export var backdrop_hills: Color = Color(0.07, 0.27, 0.5)

@export_group("Corales")
## Cuántos grupos de corales brotan.
@export var coral_sites: int = 64
## Metros alrededor de donde llegó la langosta hasta los que brotan.
@export var coral_reach: float = 60.0
## Metros alrededor de donde llegó la langosta que quedan libres (ahí filma la entrada).
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
var _sky: HellSky = null
## El cielo del que parte el cambio en curso, el de la marea y el de antes.
var _from: HellSky.Palette = null
var _deep: HellSky.Palette = null
var _original: HellSky.Palette = null
## False si otra transformación del mapa ya es dueña del cielo.
var _owns_sky: bool = false
## Una nube de burbujas por raider.
var _bubbles: Array[CPUParticles3D] = []

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


func _exit_tree() -> void:
	# Si este nodo se va con la marea puesta y la arena sigue, el cielo vuelve.
	if _owns_sky and _sky != null and _amount > 0.0 and not _other_transformation():
		_sky.write(_original)


func _process(delta: float) -> void:
	_follow_raiders()
	if _state == State.RISING:
		_clock += delta
		var raised := smoothstep(0.0, 1.0, clampf(_clock / maxf(rise_seconds, 0.01), 0.0, 1.0))
		_write_sky(_deep, raised)
		_show(raised)
		if _clock >= rise_seconds:
			_state = State.HIGH
			# Línea de log para los soaks.
			print("Lobster tide: high at %.1fs" % RunState.stage_time)
	elif _state == State.EBBING:
		_clock += delta
		var lowered := smoothstep(0.0, 1.0, clampf(_clock / maxf(ebb_seconds, 0.01), 0.0, 1.0))
		_write_sky(_original, lowered)
		_show(1.0 - lowered)
		if _clock >= ebb_seconds:
			_owns_sky = false
			print("Lobster tide: gone at %.1fs" % RunState.stage_time)
			queue_free()


# --- lo que piden la langosta y el harness ----------------------------------------

## Sube la marea. `origin` es donde llegó la langosta: los corales brotan a su
## alrededor, dejando libre el lugar donde la filma la entrada.
func begin(origin: Vector3) -> void:
	if _state != State.LOW:
		return
	_take_sky()
	_lay_caustics()
	_plant_corals(origin)
	_state = State.RISING
	_clock = 0.0
	set_process(true)
	print("Lobster tide: rising over %.1fs sky=%s at %.1fs" % [
			rise_seconds, _owns_sky, RunState.stage_time])


## Baja la marea (la langosta murió) y este nodo se libera al terminar.
func ebb() -> void:
	if _state == State.EBBING or _state == State.LOW:
		return
	_owns_sky = _owns_sky and not _other_transformation()
	if _owns_sky:
		_from = _sky.current()
	for cloud: CPUParticles3D in _bubbles:
		cloud.emitting = false
	_state = State.EBBING
	_clock = 0.0
	print("Lobster tide: ebbing over %.1fs sky=%s at %.1fs" % [
			ebb_seconds, _owns_sky, RunState.stage_time])


## En qué anda: "low", "rising", "high" o "ebbing" (lo lee el harness).
func state_name() -> StringName:
	return STATE_NAMES[_state]


# --- cielo ------------------------------------------------------------------------

## Toma el cielo de la arena y guarda el de antes, sin el tinte del clima que
## esté en curso, para poder devolverlo.
func _take_sky() -> void:
	var arena := RunRoot.stage_parent(get_tree()) as Node3D
	if arena == null or _other_transformation():
		return
	# Antes de collect(): ahí el cielo «original» del clima pasa a ser el de la marea.
	var base := _weather_base()
	_deep = HellSky.Palette.make(sky_top, sky_horizon, ground_horizon, ground_bottom,
			sun_color, sun_energy, ambient_color, ambient_energy, fog_color, fog_density)
	_sky = HellSky.new()
	_sky.collect(get_tree(), arena, _deep)
	_from = _sky.current()
	_original = _sky.current()
	if not base.is_empty():
		_original.sun_color = base["sun_color"]
		_original.sun_energy = base["sun_energy"]
		_original.ambient_color = base["ambient_color"]
		_original.ambient_energy = base["ambient_energy"]
	_owns_sky = true


## El cielo a `weight` (0-1) del camino entre el de partida y `target`. En
## esos segundos el sol y el ambiente tienen un solo dueño: el clima que
## estuviera tiñendo o volviendo queda cortado y vuelve después a `target`.
func _write_sky(target: HellSky.Palette, weight: float) -> void:
	if not _owns_sky:
		return
	if _other_transformation():
		_owns_sky = false
		return
	HellSky.rebase_weather(get_tree(), target)
	_sky.write(_from.blend(target, weight))
	_sky.blend_backdrop(backdrop_ground, backdrop_hills,
			weight if target == _deep else 1.0 - weight)


## El cielo «original» que guarda el clima ahora, o vacío si no hay director.
func _weather_base() -> Dictionary:
	var director := get_tree().get_first_node_in_group(&"world_director")
	if director == null or not director.has_method(&"sky_base"):
		return {}
	return director.call(&"sky_base") as Dictionary


func _other_transformation() -> bool:
	return get_tree().get_first_node_in_group(OTHER_TRANSFORMATION_GROUP) != null


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


## Reparte los grupos de corales alrededor de `origin`, en lugares donde se
## puede poner algo (_fits_corals), y arma las dos MultiMesh. Usa su propio azar: no toca el
## RNG de la partida.
func _plant_corals(origin: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var bounds := get_tree().get_first_node_in_group(&"arena_bounds")
	var terrain := Terrain.find(get_tree())
	var branches: Array[Transform3D] = []
	var branch_data: Array[Color] = []
	var bulbs: Array[Transform3D] = []
	var bulb_data: Array[Color] = []
	var planted := 0
	var tries := coral_sites * 12
	while planted < coral_sites and tries > 0:
		tries -= 1
		var angle := rng.randf() * TAU
		var reach := lerpf(coral_clearance, coral_reach, sqrt(rng.randf()))
		var site := origin + Vector3(cos(angle), 0.0, sin(angle)) * reach
		if bounds != null and not _fits_corals(bounds, site):
			continue
		if _near_raider(site):
			continue
		planted += 1
		for _branch: int in rng.randi_range(branches_min, maxi(branches_max, branches_min)):
			var height := rng.randf_range(branch_height_min, branch_height_max)
			var radius := rng.randf_range(branch_radius_min, branch_radius_max)
			var turn := rng.randf() * TAU
			var tilt := deg_to_rad(rng.randf_range(0.0, branch_tilt_degrees))
			var basis := Basis(Vector3.UP, turn) * Basis(Vector3.RIGHT, tilt)
			var foot := site + Vector3(cos(turn), 0.0, sin(turn)) * rng.randf_range(0.0, site_radius)
			foot.y = terrain.height_at(foot.x, foot.z) if terrain != null else origin.y
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


## True si en `site` cabe un grupo de corales: lejos de cortes, rampas,
## puentes y props (arena_bounds.can_place con site_radius de margen), o al
## menos sobre una celda caminable si el mapa no tiene esa pregunta.
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


## Cada raider lleva su nube de burbujas (cada vista de la pantalla dividida
## tiene la suya).
func _follow_raiders() -> void:
	var raiders := get_tree().get_nodes_in_group(&"player")
	while _bubbles.size() < raiders.size():
		var cloud := _bubble_template.duplicate() as CPUParticles3D
		add_child(cloud)
		cloud.emitting = _state != State.EBBING
		_bubbles.append(cloud)
	for index: int in _bubbles.size():
		if index < raiders.size():
			var raider := raiders[index] as Node3D
			if raider != null:
				_bubbles[index].global_position = raider.global_position \
						+ Vector3.UP * bubble_height
