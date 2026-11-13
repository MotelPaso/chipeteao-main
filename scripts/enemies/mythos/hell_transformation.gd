class_name HellTransformation
extends Node3D
## El bosque se vuelve infierno. Mythos instancia esta escena bajo la arena
## cuando llega: un frente de fuego avanza desde su punto de llegada mientras
## dura la calma (begin), el mapa queda ardiendo durante la pelea y, cuando
## Mythos muere, se enfría hasta quedar carbonizado y humeando (cool_down)
## hasta que la party cruza el portal. Como cuelga de la arena, muere con ella.
##
## NUNCA toca un recurso compartido. La escena de la arena y los modelos glb
## comparten sus materiales con la vuelta siguiente, con otros mapas y con el
## fondo del menú, así que todo se hace sobre copias propias de esta arena:
##   suelo     una copia del ShaderMaterial del Terrain (forest_ground.gdshader)
##   props     una copia de prop_material por tipo de superficie, puesta como
##             override en los árboles, rocas, tocones, mesetas y formaciones
##   cielo     el Environment propio de la arena (el mismo que usa SkyTint) y
##             una copia de su Sky y su material
##   horizonte los materiales del Backdrop, que ya son de cada instancia
## El frente de fuego son tres uniforms escritos en esos pocos materiales:
## ningún prop recibe nodos nuevos. Las copias de material las arma
## HellDressing y el cielo lo lleva HellSky (los dos, junto a este archivo);
## los colores y los tiempos se editan aquí.
##
## CLIMA. El tinte de los climas (SkyTint) vuelve a un cielo «original»; esta
## escena lo reemplaza por el suyo (WorldDirector.rebase_sky), así ningún
## clima devuelve el verde. Mientras el cielo está cambiando (el avance del
## fuego y el enfriamiento) lo reemplaza en cada frame, lo que además corta
## cualquier tinte en curso: en esos segundos solo escribe esta escena.
##
## Procesa en PAUSABLE (lo fija la escena): sigue corriendo con la arena
## congelada por la cinemática, y el menú de pausa la detiene.
## Contratos por nombre: grupo "stage_transformation" y state_name() (los
## lee el harness) y las líneas "Hell transformation:" del log.

enum Look { GREEN, IGNITING, HELL, COOLING, CHARRED }

const GROUP := &"stage_transformation"
## Volumen, en dB, que cuenta como silencio para los fundidos de sonido.
const SILENT_DB: float = -60.0


@export_group("Frente de fuego")
## Metros que recorre el frente; tiene que cubrir la arena entera desde cualquier punto.
@export var front_reach: float = 360.0
## Ancho en metros del borde encendido del frente.
@export var front_edge: float = 9.0
## Curva del avance (1 = parejo; más alto = arranca lento y termina rápido).
@export var front_curve: float = 1.7
## Segundos que tarda el bosque en enfriarse cuando el jefe muere.
@export var cool_seconds: float = 8.0
## Material con que arden árboles, rocas, tocones, mesetas y formaciones (burnt_prop.gdshader); sus colores se editan en este recurso.
@export var prop_material: ShaderMaterial

@export_group("Cielo del infierno")
## Color del cielo en lo alto.
@export var hell_sky_top: Color = Color(0.2, 0.03, 0.03)
## Color del cielo en el horizonte.
@export var hell_sky_horizon: Color = Color(0.92, 0.38, 0.1)
## Color del suelo del cielo en el horizonte.
@export var hell_ground_horizon: Color = Color(0.55, 0.16, 0.05)
## Color del suelo del cielo hacia abajo.
@export var hell_ground_bottom: Color = Color(0.1, 0.03, 0.02)
## Color del sol.
@export var hell_sun_color: Color = Color(1.0, 0.5, 0.25)
## Energía del sol.
@export var hell_sun_energy: float = 1.0
## Color de la luz ambiente.
@export var hell_ambient_color: Color = Color(0.85, 0.36, 0.22)
## Energía de la luz ambiente.
@export var hell_ambient_energy: float = 0.7
## Color de la niebla.
@export var hell_fog_color: Color = Color(0.5, 0.16, 0.06)
## Densidad de la niebla.
@export var hell_fog_density: float = 0.011

@export_group("Cielo carbonizado")
## Color del cielo en lo alto.
@export var charred_sky_top: Color = Color(0.22, 0.21, 0.22)
## Color del cielo en el horizonte.
@export var charred_sky_horizon: Color = Color(0.5, 0.45, 0.4)
## Color del suelo del cielo en el horizonte.
@export var charred_ground_horizon: Color = Color(0.4, 0.36, 0.33)
## Color del suelo del cielo hacia abajo.
@export var charred_ground_bottom: Color = Color(0.12, 0.11, 0.1)
## Color del sol.
@export var charred_sun_color: Color = Color(0.9, 0.78, 0.68)
## Energía del sol.
@export var charred_sun_energy: float = 0.75
## Color de la luz ambiente.
@export var charred_ambient_color: Color = Color(0.5, 0.47, 0.46)
## Energía de la luz ambiente.
@export var charred_ambient_energy: float = 0.65
## Color de la niebla (humo).
@export var charred_fog_color: Color = Color(0.4, 0.38, 0.37)
## Densidad de la niebla (humo).
@export var charred_fog_density: float = 0.012

@export_group("Horizonte")
## Color del suelo lejano en el infierno.
@export var hell_backdrop_ground: Color = Color(0.14, 0.07, 0.05)
## Color de las colinas del horizonte en el infierno.
@export var hell_backdrop_hills: Color = Color(0.09, 0.04, 0.03)
## Color del suelo lejano ya carbonizado.
@export var charred_backdrop_ground: Color = Color(0.2, 0.19, 0.18)
## Color de las colinas del horizonte ya carbonizadas.
@export var charred_backdrop_hills: Color = Color(0.11, 0.1, 0.1)

@export_group("Sonido")
## Volumen del fondo de fuego durante el infierno, en dB.
@export var fire_volume_db: float = -14.0
## Volumen del fondo de fuego con el bosque ya carbonizado (brasas), en dB.
@export var smolder_volume_db: float = -30.0

@export_group("Partículas")
## Escena del humo que queda con el bosque carbonizado (HellSmoke.tscn, un GPUParticles3D); una copia por raider.
@export var smoke_scene: PackedScene
## Fracción de las brasas que sigue en el aire con el bosque ya carbonizado (0-1).
@export_range(0.0, 1.0) var charred_ember_ratio: float = 0.15
## Cuánto arde lo verde que no es un árbol (pasto de mesetas, musgo de las formaciones), de 0 a 1.
@export_range(0.0, 1.0) var grass_flame_amount: float = 0.3

var _look: Look = Look.GREEN
var _origin: Vector3 = Vector3.ZERO
var _ignite_seconds: float = 1.0
var _ignite_t: float = 0.0
var _cool_t: float = 0.0
var _dressing: HellDressing = HellDressing.new()
var _sky: HellSky = HellSky.new()
## El cielo que había al empezar (puede traer el tinte de un clima).
var _from_sky: HellSky.Palette = null
## Fondos de viento de la arena con su volumen de bosque: {player, from}.
var _wind: Array[Dictionary] = []
var _embers: Array[GPUParticles3D] = []
var _smokes: Array[GPUParticles3D] = []
## Punto que sigue la primera nube de brasas durante la cinemática (INF = el raider).
var _focus: Vector3 = Vector3.INF

@onready var _fire_bed: AudioStreamPlayer = $FireBed
@onready var _ember_template: GPUParticles3D = $Embers


func _ready() -> void:
	add_to_group(GROUP)
	_fire_bed.volume_db = SILENT_DB
	_ember_template.emitting = false


func _process(delta: float) -> void:
	match _look:
		Look.GREEN:
			return
		Look.IGNITING:
			_ignite_t = minf(_ignite_t + delta / maxf(_ignite_seconds, 0.01), 1.0)
			_apply_ignition(_ignite_t)
			if _ignite_t >= 1.0:
				_look = Look.HELL
				print("Hell transformation: hell at %.1fs" % RunState.stage_time)
		Look.COOLING:
			_cool_t = minf(_cool_t + delta / maxf(cool_seconds, 0.01), 1.0)
			_apply_cooling(_cool_t)
			if _cool_t >= 1.0:
				_look = Look.CHARRED
				print("Hell transformation: charred at %.1fs" % RunState.stage_time)
	_follow_raiders()


# --- lo que piden Mythos y su cinemática ------------------------------------------

## Empieza a quemar el bosque desde `origin`; llega al infierno completo en
## `seconds` de juego.
func begin(origin: Vector3, seconds: float) -> void:
	if _look != Look.GREEN:
		return
	_origin = origin
	_ignite_seconds = seconds
	_ignite_t = 0.0
	var arena := RunRoot.stage_parent(get_tree()) as Node3D
	if arena != null:
		_dressing.dress(get_tree(), arena, prop_material, grass_flame_amount)
		_sky.collect(get_tree(), arena, _hell_sky())
		_from_sky = _sky.current()
		_collect_wind(arena)
	_spawn_particles()
	_dressing.write(&"burn_origin", origin)
	_dressing.write(&"burn_edge", front_edge)
	_dressing.write(&"heat", 1.0)
	_dressing.write(&"ash", 0.0)
	_look = Look.IGNITING
	_apply_ignition(0.0)
	print("Hell transformation: begin seconds=%.2f props=%d materials=%d at %.1fs" % [
			seconds, _dressing.props_dressed(), _dressing.material_count(),
			RunState.stage_time])


## Salta al infierno completo (alguien saltó la cinemática).
func finish_now() -> void:
	if _look != Look.IGNITING:
		return
	_ignite_t = 1.0
	_apply_ignition(1.0)
	_look = Look.HELL
	print("Hell transformation: hell at %.1fs (skipped)" % RunState.stage_time)


## El jefe murió: los fuegos se apagan y el bosque queda carbonizado.
func cool_down() -> void:
	if _look == Look.GREEN or _look == Look.COOLING or _look == Look.CHARRED:
		return
	finish_now()
	_look = Look.COOLING
	_cool_t = 0.0
	HellSky.rebase_weather(get_tree(), _charred_sky())
	for smoke: GPUParticles3D in _smokes:
		smoke.emitting = true
	print("Hell transformation: cooling seconds=%.1f at %.1fs" % [
			cool_seconds, RunState.stage_time])


## "green", "igniting", "hell", "cooling" o "charred" (lo lee el harness).
func state_name() -> StringName:
	match _look:
		Look.IGNITING:
			return &"igniting"
		Look.HELL:
			return &"hell"
		Look.COOLING:
			return &"cooling"
		Look.CHARRED:
			return &"charred"
		_:
			return &"green"


## Durante la cinemática la primera nube de brasas sigue este punto (lo que
## mira la cámara); Vector3.INF la devuelve a su raider.
func set_focus(point: Vector3) -> void:
	_focus = point


# --- aplicar ----------------------------------------------------------------------

## Avance del frente (0-1): bosque -> infierno.
func _apply_ignition(t: float) -> void:
	_dressing.write(&"burn_radius", front_reach * pow(t, front_curve))
	var eased := smoothstep(0.0, 1.0, t)
	if _from_sky != null:
		_own_sky(_from_sky.blend(_hell_sky(), eased))
	_sky.blend_backdrop(hell_backdrop_ground, hell_backdrop_hills, eased)
	for entry: Dictionary in _wind:
		var player := entry["player"] as AudioStreamPlayer
		if is_instance_valid(player):
			player.volume_db = lerpf(float(entry["from"]), SILENT_DB, eased)
			if t >= 1.0:
				player.stop()
	_fire_bed.volume_db = lerpf(SILENT_DB, fire_volume_db, eased)


## Enfriamiento (0-1): infierno -> carbonizado.
func _apply_cooling(c: float) -> void:
	_dressing.write(&"heat", 1.0 - c)
	_dressing.write(&"ash", c)
	_own_sky(_hell_sky().blend(_charred_sky(), c))
	_sky.set_backdrop(hell_backdrop_ground.lerp(charred_backdrop_ground, c),
			hell_backdrop_hills.lerp(charred_backdrop_hills, c))
	_fire_bed.volume_db = lerpf(fire_volume_db, smolder_volume_db, c)
	for embers: GPUParticles3D in _embers:
		embers.amount_ratio = lerpf(1.0, charred_ember_ratio, c)


## Escribe este cielo y le dice al clima que ESE es ahora el cielo de la
## arena. Se usa mientras el cielo cambia: corta cualquier tinte de clima en
## curso, así no hay dos escribiendo el sol y el ambiente a la vez.
func _own_sky(look: HellSky.Palette) -> void:
	_sky.write(look)
	HellSky.rebase_weather(get_tree(), look)


func _hell_sky() -> HellSky.Palette:
	var look := HellSky.Palette.new()
	look.sky_top = hell_sky_top
	look.sky_horizon = hell_sky_horizon
	look.ground_horizon = hell_ground_horizon
	look.ground_bottom = hell_ground_bottom
	look.sun_color = hell_sun_color
	look.sun_energy = hell_sun_energy
	look.ambient_color = hell_ambient_color
	look.ambient_energy = hell_ambient_energy
	look.fog_color = hell_fog_color
	look.fog_density = hell_fog_density
	return look


func _charred_sky() -> HellSky.Palette:
	var look := HellSky.Palette.new()
	look.sky_top = charred_sky_top
	look.sky_horizon = charred_sky_horizon
	look.ground_horizon = charred_ground_horizon
	look.ground_bottom = charred_ground_bottom
	look.sun_color = charred_sun_color
	look.sun_energy = charred_sun_energy
	look.ambient_color = charred_ambient_color
	look.ambient_energy = charred_ambient_energy
	look.fog_color = charred_fog_color
	look.fog_density = charred_fog_density
	return look


## Los fondos de viento de la arena: se apagan mientras entra el de fuego.
func _collect_wind(arena: Node3D) -> void:
	for node: Node in arena.find_children("*", "AudioStreamPlayer", true, false):
		var bed := node as AmbientBed
		if bed != null and bed != _fire_bed:
			_wind.append({"player": bed, "from": bed.volume_db})


# --- partículas -------------------------------------------------------------------

## Una nube de brasas y una de humo por raider: en pantalla dividida cada
## vista tiene las suyas. Las brasas son copias del nodo Embers y el humo,
## instancias de smoke_scene. El humo va en escena aparte porque una escena
## con dos GPUParticles3D deja un shader sin liberar al cerrar sin ventana.
func _spawn_particles() -> void:
	var count := maxi(Coop.player_count, 1)
	for slot: int in count:
		var embers := _ember_template if slot == 0 \
				else _ember_template.duplicate() as GPUParticles3D
		if slot > 0:
			add_child(embers)
		embers.emitting = true
		_embers.append(embers)
		var smoke := smoke_scene.instantiate() as GPUParticles3D \
				if smoke_scene != null else null
		if smoke != null:
			smoke.emitting = false
			add_child(smoke)
			_smokes.append(smoke)


## Cada nube sigue a su raider, esté de pie o caído.
func _follow_raiders() -> void:
	for group: StringName in [&"player", &"downed_players"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var body := node as Node3D
			var slot := int(node.get("player_index"))
			if body == null or slot < 0 or slot >= _embers.size():
				continue
			var at := body.global_position
			if slot == 0 and _focus != Vector3.INF:
				at = _focus
			_embers[slot].global_position = at
			if slot < _smokes.size():
				_smokes[slot].global_position = at
