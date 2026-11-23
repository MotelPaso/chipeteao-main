class_name BossOmen
extends Node
## El PRESAGIO de un jefe con arena propia (campo omen_scene de su fila en
## BossArenaCatalog): unos segundos antes del viaje la luz del mapa se tiñe y
## una tarjeta avisa quién viene y cuánto falta. BossArenaHost lo cuelga de sí
## mismo y llama a begin(); cuando el mapa deja de verse (o el viaje se
## cancela) llama a release(), que devuelve el cielo tal como estaba.
##
## El cielo se escribe con HellSky, el mismo camino que usa el infierno de
## Mythos: nunca toca un recurso compartido. Mientras dura, el clima vuelve a
## ESTE cielo; al soltarlo vuelve al de antes, y si hay un clima en curso su
## tinte vuelve con él.
## La tarjeta es el nodo Notice (StickerNotice): cómo se ve vive ahí.
## Contratos por nombre: begin, release y la línea "Boss omen:".

@export_group("Cielo")
## Cielo del presagio a pleno: los cuatro colores del cielo, de arriba abajo.
@export var sky_top: Color = Color(0.02, 0.1, 0.3)
@export var sky_horizon: Color = Color(0.1, 0.38, 0.66)
@export var ground_horizon: Color = Color(0.06, 0.26, 0.48)
@export var ground_bottom: Color = Color(0.01, 0.05, 0.15)
## Color y fuerza del sol con el presagio a pleno.
@export var sun_color: Color = Color(0.62, 0.82, 1.0)
@export var sun_energy: float = 1.0
## Color y fuerza de la luz ambiente con el presagio a pleno.
@export var ambient_color: Color = Color(0.36, 0.52, 0.96)
@export var ambient_energy: float = 1.15
## Color y espesor de la niebla con el presagio a pleno.
@export var fog_color: Color = Color(0.08, 0.32, 0.62)
@export var fog_density: float = 0.016
## Color del suelo lejano y de las colinas del horizonte con el presagio a pleno.
@export var backdrop_ground: Color = Color(0.05, 0.2, 0.38)
@export var backdrop_hills: Color = Color(0.07, 0.27, 0.5)
## Cuánto de ese cielo toma el mapa (0 = nada, 1 = entero).
@export_range(0.0, 1.0) var strength: float = 0.85
## Segundos que tarda el mapa en teñirse (si el presagio dura menos, lo que dure).
@export var tint_seconds: float = 12.0

@export_group("Aviso")
## Título de la tarjeta; %s es el nombre del jefe.
@export var notice_text: String = "Se acerca la %s"
## Segunda línea de la tarjeta; %d son los segundos que faltan.
@export var countdown_text: String = "La marea sube · %d s"
## Segunda línea cuando la cuenta llegó a cero y el viaje todavía no empieza.
@export var arriving_text: String = "La marea llegó"
## Sonido con que empieza el presagio (fila de Sfx.SOUND_LIBRARY; vacío = ninguno).
@export var begin_sfx: StringName = &"omen_swell"

var _sky: HellSky = null
## El cielo de antes (sin el tinte de un clima), el que se veía al empezar y
## el del presagio a pleno.
var _from: HellSky.Palette = null
var _shown: HellSky.Palette = null
var _target: HellSky.Palette = null
## Segundo de etapa en que le toca al viaje, y los que tarda en teñirse.
var _due: float = 0.0
var _rise: float = 0.0
var _rising: float = 0.0
var _title: String = ""

@onready var _notice: StickerNotice = $Notice


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	if _sky != null and _rising < _rise:
		_rising = minf(_rising + delta, _rise)
		_write(_rising / maxf(_rise, 0.01))
	_show_countdown()


# --- lo que pide BossArenaHost -----------------------------------------------------

## Empieza el presagio de `boss_title`: el viaje llega en `seconds` segundos de juego.
func begin(boss_title: String, seconds: float) -> void:
	_title = boss_title
	_due = RunState.stage_time + maxf(seconds, 0.0)
	_take_sky(minf(tint_seconds, maxf(seconds, 0.0)))
	_notice.show_notice(notice_text % boss_title if notice_text.contains("%s")
			else notice_text, _countdown())
	Sfx.play(begin_sfx)
	set_process(true)
	# Línea de log para los soaks: el presagio y cuánto cambia el sol.
	print("Boss omen: %s in=%.1fs sun=%s->%s at %.1fs" % [
			boss_title, maxf(seconds, 0.0), _color_text(_from.sun_color if _from != null else Color.BLACK),
			_color_text(_target.sun_color if _target != null else Color.BLACK), RunState.stage_time])


## Termina el presagio: el cielo del mapa vuelve a como estaba antes y la
## tarjeta se va. Se puede llamar siempre.
func release() -> void:
	set_process(false)
	_notice.hide_notice()
	if _sky == null:
		return
	# El clima vuelve desde ahora al cielo de antes.
	HellSky.rebase_weather(get_tree(), _from)
	_sky.write(_with_weather(_from))
	_sky.blend_backdrop(backdrop_ground, backdrop_hills, 0.0)
	_sky = null


# --- cielo ------------------------------------------------------------------------

## Toma el cielo del mapa vivo y arma el del presagio; se tiñe en `rise` segundos.
func _take_sky(rise: float) -> void:
	var arena := RunRoot.stage_parent(get_tree()) as Node3D
	if arena == null:
		return
	var director := get_tree().get_first_node_in_group(&"world_director")
	var base: Dictionary = director.call(&"sky_base") if director != null \
			and director.has_method(&"sky_base") else {}
	var deep := HellSky.Palette.make(sky_top, sky_horizon, ground_horizon, ground_bottom,
			sun_color, sun_energy, ambient_color, ambient_energy, fog_color, fog_density)
	_sky = HellSky.new()
	_sky.collect(get_tree(), arena, deep)
	_shown = _sky.current()
	# El cielo de antes es el «original» de la arena: lo que se ve ahora puede
	# traer el tinte de un clima en el sol y el ambiente.
	_from = _sky.current()
	if not base.is_empty():
		_from.sun_color = base["sun_color"]
		_from.sun_energy = float(base["sun_energy"])
		_from.ambient_color = base["ambient_color"]
		_from.ambient_energy = float(base["ambient_energy"])
	_target = _from.blend(deep, strength)
	HellSky.rebase_weather(get_tree(), _target)
	_rise = rise
	_rising = 0.0
	if _rise <= 0.0:
		_write(1.0)


## El cielo a `weight` (0-1) del camino entre el que se veía y el del presagio.
func _write(weight: float) -> void:
	var eased := smoothstep(0.0, 1.0, weight)
	_sky.write(_shown.blend(_target, eased))
	_sky.blend_backdrop(backdrop_ground, backdrop_hills, eased * strength)


## `look` con el tinte del clima que esté en curso (el clima tiñe solo el sol
## y el ambiente): así el mapa vuelve como estaba, también a mitad de un clima.
func _with_weather(look: HellSky.Palette) -> HellSky.Palette:
	var out := look.blend(look, 0.0)
	var director := get_tree().get_first_node_in_group(&"world_director")
	var active: Variant = director.get("active_weather") if director != null else null
	if not active is Dictionary or (active as Dictionary).is_empty():
		return out
	var row := WeatherCatalog.by_id(String((active as Dictionary).get("id", "")))
	if row.has("sun_color"):
		out.sun_color = row["sun_color"]
		out.sun_energy = look.sun_energy * float(row["sun_energy"])
		out.ambient_color = row["ambient_color"]
	return out


# --- tarjeta ----------------------------------------------------------------------

## La cuenta regresiva, con el reloj de la etapa (una cinemática lo detiene).
## Con el viaje ya empezado la tarjeta se va: lo que sigue es la cinemática.
func _show_countdown() -> void:
	var host := get_parent() as BossArenaHost
	if host != null and host.is_busy():
		_notice.hide_notice()
		return
	_notice.set_subtitle(_countdown())


func _countdown() -> String:
	var left := ceili(_due - RunState.stage_time)
	return countdown_text % left if left > 0 else arriving_text


func _color_text(color: Color) -> String:
	return "(%.2f,%.2f,%.2f)" % [color.r, color.g, color.b]
