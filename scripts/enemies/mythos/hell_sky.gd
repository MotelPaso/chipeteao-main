class_name HellSky
extends RefCounted
## El cielo de una arena para HellTransformation: el sol, el Environment
## PROPIO de la arena, su Sky y el horizonte (Backdrop). Los encuentra, deja
## copias propias donde hace falta y escribe en ellos un cielo completo
## (HellSky.Palette). No decide ningún color: los pone HellTransformation,
## que es quien los muestra en el Inspector. Lo único suyo es el RESPLANDOR
## del fuego (set_glow): el halo de luz alrededor de todo lo que brilla
## mientras dura el infierno, que sube y baja con el calor del mapa.
##
## NUNCA escribe en un recurso compartido. El Environment es el que entrega
## el director del clima (el mismo que usa SkyTint); el Sky y su material se
## copian, porque la copia del Environment todavía los comparte con la escena
## de la arena. Los materiales del Backdrop ya son de cada instancia.

# --- Edita aquí: resplandor del fuego -------------------------------------------
## Fuerza del resplandor con el infierno a pleno (0 = sin resplandor).
const GLOW_INTENSITY: float = 0.6
## Tamaño del halo alrededor de lo que brilla.
const GLOW_STRENGTH: float = 1.05
## Cuánto resplandece también lo que no brilla tanto (0-1): sube el clima de horno de toda la imagen.
const GLOW_BLOOM: float = 0.05
## Brillo desde el que algo empieza a resplandecer (1 = solo el fuego).
const GLOW_THRESHOLD: float = 1.15


## Un cielo completo: lo que se le cambia al sol, al ambiente, a la niebla y
## al material del cielo.
class Palette:
	extends RefCounted
	var sky_top: Color = Color.BLACK
	var sky_horizon: Color = Color.BLACK
	var ground_horizon: Color = Color.BLACK
	var ground_bottom: Color = Color.BLACK
	var sun_color: Color = Color.WHITE
	var sun_energy: float = 1.0
	var ambient_color: Color = Color.WHITE
	var ambient_energy: float = 1.0
	var fog_color: Color = Color.WHITE
	var fog_density: float = 0.0

	## Un cielo con estos valores: los cuatro colores del cielo de arriba
	## abajo, el sol, el ambiente y la niebla.
	static func make(top: Color, horizon: Color, low_horizon: Color, bottom: Color,
			sun: Color, sun_power: float, ambient: Color, ambient_power: float, fog: Color,
			fog_amount: float) -> Palette:
		var out := Palette.new()
		out.sky_top = top
		out.sky_horizon = horizon
		out.ground_horizon = low_horizon
		out.ground_bottom = bottom
		out.sun_color = sun
		out.sun_energy = sun_power
		out.ambient_color = ambient
		out.ambient_energy = ambient_power
		out.fog_color = fog
		out.fog_density = fog_amount
		return out

	## El cielo a `weight` (0-1) del camino entre este y `to`.
	func blend(to: Palette, weight: float) -> Palette:
		var out := Palette.new()
		out.sky_top = sky_top.lerp(to.sky_top, weight)
		out.sky_horizon = sky_horizon.lerp(to.sky_horizon, weight)
		out.ground_horizon = ground_horizon.lerp(to.ground_horizon, weight)
		out.ground_bottom = ground_bottom.lerp(to.ground_bottom, weight)
		out.sun_color = sun_color.lerp(to.sun_color, weight)
		out.sun_energy = lerpf(sun_energy, to.sun_energy, weight)
		out.ambient_color = ambient_color.lerp(to.ambient_color, weight)
		out.ambient_energy = lerpf(ambient_energy, to.ambient_energy, weight)
		out.fog_color = fog_color.lerp(to.fog_color, weight)
		out.fog_density = lerpf(fog_density, to.fog_density, weight)
		return out


var _sun: DirectionalLight3D = null
var _environment: Environment = null
var _sky_material: ProceduralSkyMaterial = null
## Materiales del Backdrop con su color de partida: {material, from, ground}.
var _backdrop: Array[Dictionary] = []


## Toma el sol, el Environment y el horizonte de `arena`. `weather_base` es
## el cielo al que los climas deben volver desde ahora.
func collect(tree: SceneTree, arena: Node3D, weather_base: Palette) -> void:
	_collect_sky(tree, arena, weather_base)
	_collect_backdrop(tree)


## El cielo tal como se ve ahora (puede traer el tinte de un clima).
func current() -> Palette:
	var look := Palette.new()
	if _sun != null:
		look.sun_color = _sun.light_color
		look.sun_energy = _sun.light_energy
	if _environment != null:
		look.ambient_color = _environment.ambient_light_color
		look.ambient_energy = _environment.ambient_light_energy
		look.fog_color = _environment.fog_light_color
		look.fog_density = _environment.fog_density
	if _sky_material != null:
		look.sky_top = _sky_material.sky_top_color
		look.sky_horizon = _sky_material.sky_horizon_color
		look.ground_horizon = _sky_material.ground_horizon_color
		look.ground_bottom = _sky_material.ground_bottom_color
	return look


## Pone este cielo en el sol, el ambiente, la niebla y el material del cielo.
func write(look: Palette) -> void:
	if _sun != null and is_instance_valid(_sun):
		_sun.light_color = look.sun_color
		_sun.light_energy = look.sun_energy
	if _environment != null:
		_environment.ambient_light_color = look.ambient_color
		_environment.ambient_light_energy = look.ambient_energy
		_environment.fog_light_color = look.fog_color
		_environment.fog_density = look.fog_density
	if _sky_material != null:
		_sky_material.sky_top_color = look.sky_top
		_sky_material.sky_horizon_color = look.sky_horizon
		_sky_material.ground_horizon_color = look.ground_horizon
		_sky_material.ground_bottom_color = look.ground_bottom


## Deja el resplandor del fuego a `amount` (0-1) de su fuerza; 0 lo apaga.
func set_glow(amount: float) -> void:
	if _environment != null:
		style_glow(_environment, amount)


## El resplandor del fuego sobre `environment`, a `amount` (0-1) de su fuerza.
static func style_glow(environment: Environment, amount: float) -> void:
	environment.glow_enabled = amount > 0.01
	environment.glow_intensity = GLOW_INTENSITY * clampf(amount, 0.0, 1.0)
	environment.glow_strength = GLOW_STRENGTH
	environment.glow_bloom = GLOW_BLOOM * clampf(amount, 0.0, 1.0)
	environment.glow_hdr_threshold = GLOW_THRESHOLD
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE


## El horizonte a `weight` (0-1) del camino entre el color que tenía al
## empezar y estos (`ground` para el suelo lejano, `hills` para las colinas).
func blend_backdrop(ground: Color, hills: Color, weight: float) -> void:
	for entry: Dictionary in _backdrop:
		var material := entry["material"] as StandardMaterial3D
		var target := ground if bool(entry["ground"]) else hills
		material.albedo_color = (entry["from"] as Color).lerp(target, weight)


## El horizonte con estos colores, tal cual.
func set_backdrop(ground: Color, hills: Color) -> void:
	blend_backdrop(ground, hills, 1.0)


## Le dice al clima cuál es ahora el cielo «original» de la arena y devuelve
## su Environment propio (null si no hay director de clima).
static func rebase_weather(tree: SceneTree, look: Palette) -> Environment:
	var director := tree.get_first_node_in_group(&"world_director")
	if director == null or not director.has_method(&"rebase_sky"):
		return null
	return director.call(&"rebase_sky", look.sun_color, look.sun_energy,
			look.ambient_color, look.ambient_energy) as Environment


func _collect_sky(tree: SceneTree, arena: Node3D, weather_base: Palette) -> void:
	for node: Node in arena.find_children("*", "DirectionalLight3D", true, false):
		_sun = node as DirectionalLight3D
		break
	var world_environment: WorldEnvironment = null
	for node: Node in arena.find_children("*", "WorldEnvironment", true, false):
		world_environment = node as WorldEnvironment
		break
	if world_environment == null or world_environment.environment == null:
		return
	_environment = rebase_weather(tree, weather_base)
	if _environment == null:
		# Sin director de clima (una prueba suelta): la copia se hace aquí.
		_environment = world_environment.environment.duplicate() as Environment
		world_environment.environment = _environment
	if _environment.sky == null:
		return
	var sky := _environment.sky.duplicate() as Sky
	# Por partes: el cielo cambia cada frame mientras avanza el frente.
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	_sky_material = sky.sky_material as ProceduralSkyMaterial
	if _sky_material != null:
		_sky_material = _sky_material.duplicate() as ProceduralSkyMaterial
		sky.sky_material = _sky_material
	_environment.sky = sky


## El suelo lejano y las colinas del Backdrop, que el Terrain ya sabe
## encontrar.
func _collect_backdrop(tree: SceneTree) -> void:
	var terrain := Terrain.find(tree)
	if terrain == null or terrain.backdrop_path.is_empty():
		return
	var backdrop := terrain.get_node_or_null(terrain.backdrop_path)
	if backdrop == null:
		return
	var seen: Dictionary[int, bool] = {}
	for node: Node in backdrop.find_children("*", "MeshInstance3D", true, false):
		var view := node as MeshInstance3D
		var material := view.material_override as StandardMaterial3D
		if material == null or seen.has(material.get_instance_id()):
			continue
		seen[material.get_instance_id()] = true
		_backdrop.append({"material": material, "from": material.albedo_color,
				"ground": view.mesh is PlaneMesh})
