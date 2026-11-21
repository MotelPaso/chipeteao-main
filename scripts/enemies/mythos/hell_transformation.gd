class_name HellTransformation
extends Node3D
## El bosque se vuelve infierno. Mythos instancia esta escena bajo la arena
## cuando llega: un frente de fuego avanza desde su punto de llegada mientras
## dura la calma (begin), el mapa queda ardiendo durante la pelea y, cuando
## Mythos muere, se enfría hasta quedar carbonizado y humeando (cool_down)
## hasta que la party cruza el portal. Como cuelga de la arena, muere con ella.
## Cuando Mythos renace, otro frente recorre el mapa y todo el fuego pasa al
## color de su segunda fase (ascend): el suelo y los props con sus colores
## «Renacido», el cielo con el de «Cielo renacido» y los ataques con FireTint.
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

enum Look { GREEN, IGNITING, HELL, ASCENDING, REBORN, COOLING, CHARRED }

## Nombre de cada estado para el harness, en el orden de Look. El infierno de
## la segunda fase sigue siendo "hell": cambia de color, no de estado.
const LOOK_NAMES: Array[StringName] = [&"green", &"igniting", &"hell", &"hell", &"hell",
		&"cooling", &"charred"]

const GROUP := &"stage_transformation"


@export_group("Frente de fuego")
## Metros que recorre el frente; tiene que cubrir la arena entera desde cualquier punto.
@export var front_reach: float = 360.0
## Ancho en metros del borde encendido del frente.
@export var front_edge: float = 9.0
## Curva del avance (1 = parejo; más alto = arranca lento y termina rápido).
@export var front_curve: float = 1.7
## Segundos que tarda el bosque en enfriarse cuando el jefe muere.
@export var cool_seconds: float = 8.0
## Segundos que tarda el fuego de los ataques en pasar al color de la segunda fase cuando el jefe renace.
@export var ascend_tint_seconds: float = 0.9
## Cuánto arde el mapa mientras el jefe parece muerto (0-1): las llamas bajan hasta que renace.
@export_range(0.0, 1.0) var falter_heat: float = 0.3
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

@export_group("Cielo renacido")
## Color del cielo en lo alto, en la segunda fase del jefe.
@export var reborn_sky_top: Color = Color(0.02, 0.03, 0.14)
## Color del cielo en el horizonte.
@export var reborn_sky_horizon: Color = Color(0.12, 0.42, 0.95)
## Color del suelo del cielo en el horizonte.
@export var reborn_ground_horizon: Color = Color(0.06, 0.2, 0.6)
## Color del suelo del cielo hacia abajo.
@export var reborn_ground_bottom: Color = Color(0.02, 0.03, 0.1)
## Color del sol.
@export var reborn_sun_color: Color = Color(0.5, 0.78, 1.0)
## Energía del sol.
@export var reborn_sun_energy: float = 1.0
## Color de la luz ambiente.
@export var reborn_ambient_color: Color = Color(0.3, 0.5, 0.95)
## Energía de la luz ambiente.
@export var reborn_ambient_energy: float = 0.7
## Color de la niebla.
@export var reborn_fog_color: Color = Color(0.05, 0.16, 0.5)
## Densidad de la niebla.
@export var reborn_fog_density: float = 0.011

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
## Color del suelo lejano en la segunda fase del jefe.
@export var reborn_backdrop_ground: Color = Color(0.05, 0.07, 0.15)
## Color de las colinas del horizonte en la segunda fase del jefe.
@export var reborn_backdrop_hills: Color = Color(0.03, 0.04, 0.1)
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
## Avance de la calma (0-1) desde el que el frente de fuego empieza a correr.
var _front_from: float = 0.0
var _cool_t: float = 0.0
## El frente de la segunda fase: avance (0-1), lo que tarda y si ya pasó.
var _ascend_t: float = 0.0
var _ascend_seconds: float = 1.0
var _reborn: bool = false
## Cuánto arde el mapa ahora (0-1) y el tween que lo baja mientras el jefe parece muerto.
var _heat: float = 1.0
var _falter_tween: Tween = null
var _dressing: HellDressing = HellDressing.new()
var _sky: HellSky = HellSky.new()
var _particles: HellEmbers = HellEmbers.new()
## El cielo que había al empezar (puede traer el tinte de un clima).
var _from_sky: HellSky.Palette = null
var _sound: HellSound = HellSound.new()
## Punto que sigue la primera nube de brasas durante la cinemática (INF = el raider).
var _focus: Vector3 = Vector3.INF

@onready var _fire_bed: AudioStreamPlayer = $FireBed
@onready var _ember_template: GPUParticles3D = $Embers


func _ready() -> void:
	add_to_group(GROUP)
	_sound.setup(_fire_bed)
	_ember_template.emitting = false


func _exit_tree() -> void:
	# El fuego de la próxima arena empieza con su color de siempre.
	FireTint.set_amount(0.0)


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
		Look.ASCENDING:
			_ascend_t = minf(_ascend_t + delta / maxf(_ascend_seconds, 0.01), 1.0)
			_apply_ascension(_ascend_t)
			if _ascend_t >= 1.0:
				_look = Look.REBORN
				print("Hell transformation: reborn at %.1fs" % RunState.stage_time)
		Look.COOLING:
			_cool_t = minf(_cool_t + delta / maxf(cool_seconds, 0.01), 1.0)
			_apply_cooling(_cool_t)
			if _cool_t >= 1.0:
				_look = Look.CHARRED
				print("Hell transformation: charred at %.1fs" % RunState.stage_time)
	_particles.follow(get_tree(), _focus)


# --- lo que piden Mythos y su cinemática ------------------------------------------

## Empieza a quemar el bosque desde `origin`; llega al infierno completo en
## `seconds` de juego. El cielo cambia desde el principio; el frente de fuego
## del suelo espera `front_delay` segundos (el golpe de Mythos contra el
## suelo) y recorre el mapa en lo que queda.
func begin(origin: Vector3, seconds: float, front_delay: float = 0.0) -> void:
	if _look != Look.GREEN:
		return
	_origin = origin
	_ignite_seconds = seconds
	_ignite_t = 0.0
	_front_from = clampf(front_delay / maxf(seconds, 0.01), 0.0, 0.95)
	var arena := RunRoot.stage_parent(get_tree()) as Node3D
	if arena != null:
		_dressing.dress(get_tree(), arena, prop_material, grass_flame_amount)
		_sky.collect(get_tree(), arena, _hell_sky())
		_from_sky = _sky.current()
		_sound.collect(arena)
	_particles.spawn(self, _ember_template, smoke_scene)
	FireTint.set_amount(0.0)
	_reborn = false
	_dressing.write(&"ascend_radius", 0.0)
	_dressing.write(&"burn_origin", origin)
	_dressing.write(&"burn_edge", front_edge)
	_heat = 1.0
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


## El jefe parece haber muerto: las llamas del mapa bajan durante `seconds`.
## Vuelven con todo cuando renace (ascend).
func falter(seconds: float) -> void:
	if _look != Look.HELL or seconds <= 0.0:
		return
	_falter_tween = create_tween()
	_falter_tween.tween_method(_set_heat, _heat, falter_heat, seconds)


## El jefe renació: un frente sale de `origin` y en `seconds` de juego deja
## el mapa entero con el fuego de su segunda fase; el de sus ataques cambia
## enseguida (ascend_tint_seconds). Con 0 segundos queda listo para ascend_now.
func ascend(origin: Vector3, seconds: float) -> void:
	if _look != Look.HELL and _look != Look.IGNITING:
		return
	finish_now()
	if _falter_tween != null and _falter_tween.is_valid():
		_falter_tween.kill()
	_ascend_seconds = seconds
	_ascend_t = 0.0
	_reborn = true
	_dressing.write(&"ascend_origin", origin)
	_look = Look.ASCENDING
	_apply_ascension(0.0)
	print("Hell transformation: ascending seconds=%.2f at %.1fs" % [
			seconds, RunState.stage_time])


## Salta al fuego de la segunda fase completo (alguien saltó el renacer).
func ascend_now() -> void:
	if _look != Look.ASCENDING:
		return
	_ascend_t = 1.0
	_apply_ascension(1.0)
	_look = Look.REBORN
	print("Hell transformation: reborn at %.1fs (skipped)" % RunState.stage_time)


## El jefe murió: los fuegos se apagan y el bosque queda carbonizado.
func cool_down() -> void:
	if _look == Look.GREEN or _look == Look.COOLING or _look == Look.CHARRED:
		return
	finish_now()
	ascend_now()
	_look = Look.COOLING
	_cool_t = 0.0
	HellSky.rebase_weather(get_tree(), _charred_sky())
	_particles.start_smoke()
	print("Hell transformation: cooling seconds=%.1f at %.1fs" % [
			cool_seconds, RunState.stage_time])


## "green", "igniting", "hell", "cooling" o "charred" (lo lee el harness).
func state_name() -> StringName:
	return LOOK_NAMES[_look]


## Durante la cinemática la primera nube de brasas sigue este punto (lo que
## mira la cámara); Vector3.INF la devuelve a su raider.
func set_focus(point: Vector3) -> void:
	_focus = point


# --- aplicar ----------------------------------------------------------------------

## Avance del frente (0-1): bosque -> infierno.
func _apply_ignition(t: float) -> void:
	var front := clampf((t - _front_from) / (1.0 - _front_from), 0.0, 1.0)
	_dressing.write(&"burn_radius", front_reach * pow(front, front_curve))
	var eased := smoothstep(0.0, 1.0, t)
	if _from_sky != null:
		_own_sky(_from_sky.blend(_hell_sky(), eased))
	_sky.blend_backdrop(hell_backdrop_ground, hell_backdrop_hills, eased)
	# El resplandor llega con el cielo del infierno: a pleno desde la primera fase.
	_sky.set_glow(_heat * eased)
	_sound.ignite(eased, t >= 1.0, fire_volume_db)


## Avance del fuego de la segunda fase (0-1): el frente recorre el mapa, el
## cielo cambia con él y el fuego de los ataques pasa de color al principio.
func _apply_ascension(t: float) -> void:
	_dressing.write(&"ascend_radius", front_reach * pow(t, front_curve))
	# Las llamas que habían bajado vuelven enseguida.
	_set_heat(1.0 if t >= 1.0 else move_toward(_heat, 1.0, 0.1))
	var tinted := t * _ascend_seconds / maxf(ascend_tint_seconds, 0.01)
	FireTint.set_amount(1.0 if t >= 1.0 else tinted)
	var eased := smoothstep(0.0, 1.0, t)
	_own_sky(_hell_sky().blend(_reborn_sky(), eased))
	_sky.set_backdrop(hell_backdrop_ground.lerp(reborn_backdrop_ground, eased),
			hell_backdrop_hills.lerp(reborn_backdrop_hills, eased))


func _set_heat(value: float) -> void:
	_heat = value
	_dressing.write(&"heat", value)
	_sky.set_glow(value)


## Enfriamiento (0-1): infierno (el de la fase en que murió) -> carbonizado.
func _apply_cooling(c: float) -> void:
	_set_heat(1.0 - c)
	_dressing.write(&"ash", c)
	var hot := _reborn_sky() if _reborn else _hell_sky()
	_own_sky(hot.blend(_charred_sky(), c))
	var ground := reborn_backdrop_ground if _reborn else hell_backdrop_ground
	var hills := reborn_backdrop_hills if _reborn else hell_backdrop_hills
	_sky.set_backdrop(ground.lerp(charred_backdrop_ground, c),
			hills.lerp(charred_backdrop_hills, c))
	_sound.set_fire(lerpf(fire_volume_db, smolder_volume_db, c))
	_particles.set_ember_ratio(lerpf(1.0, charred_ember_ratio, c))


## Escribe este cielo y le dice al clima que ESE es ahora el cielo de la
## arena. Se usa mientras el cielo cambia: corta cualquier tinte de clima en
## curso, así no hay dos escribiendo el sol y el ambiente a la vez.
func _own_sky(look: HellSky.Palette) -> void:
	_sky.write(look)
	HellSky.rebase_weather(get_tree(), look)


func _hell_sky() -> HellSky.Palette:
	return HellSky.Palette.make(hell_sky_top, hell_sky_horizon, hell_ground_horizon,
			hell_ground_bottom, hell_sun_color, hell_sun_energy, hell_ambient_color,
			hell_ambient_energy, hell_fog_color, hell_fog_density)


func _reborn_sky() -> HellSky.Palette:
	return HellSky.Palette.make(reborn_sky_top, reborn_sky_horizon, reborn_ground_horizon,
			reborn_ground_bottom, reborn_sun_color, reborn_sun_energy, reborn_ambient_color,
			reborn_ambient_energy, reborn_fog_color, reborn_fog_density)


func _charred_sky() -> HellSky.Palette:
	return HellSky.Palette.make(charred_sky_top, charred_sky_horizon,
			charred_ground_horizon, charred_ground_bottom, charred_sun_color,
			charred_sun_energy, charred_ambient_color, charred_ambient_energy,
			charred_fog_color, charred_fog_density)
