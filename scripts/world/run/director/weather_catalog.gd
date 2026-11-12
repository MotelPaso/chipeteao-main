class_name WeatherCatalog
extends RefCounted
## Catálogo de climas: lunas, lluvias y desastres, una fila por clima. El
## nodo Weather (WeatherDirector) los sortea y los hace correr; aquí solo
## están sus datos. Los números de cada clima (daño, radios, frecuencias)
## son exports de ese nodo: RunSystems.tscn > WorldDirector > Weather.
##
## Se puede cambiar libremente: display_name, announce, weight, duration,
## sun_color, sun_energy, ambient_color, fx_color, impact_color,
## scorch_color, altar_ok, follow_up (debe ser el id de otra fila) y
## follow_up_only.
## Llaves internas, NUNCA las cambies: id (lo usan el spawner, el probe,
## BONK_WEATHER_NOW y los logs "Weather started:"), group (el código y el
## chip del HUD comparan moon | rain | disaster) y start/tick/stop (nombres
## de método de WeatherDirector que se llaman con call(); catalog_lint.gd
## revisa que existan).
##
## Campos de cada fila:
##   id, group:     llaves internas (ver arriba).
##   display_name:  nombre que muestra el chip del HUD.
##   weight:        peso del sorteo DENTRO de su grupo.
##   duration:      segundos, antes de weather_duration_overrides y, en
##                  lunas y lluvias, de RunState.sky_duration_multiplier
##                  (los pactos no alargan los desastres).
##   announce:      aviso en el HUD al empezar; %s = dato que pone el
##                  clima. El del tsunami necesita su %s: de dónde viene
##                  la ola (ver COMPASS_WORDS).
##   sun_color, sun_energy, ambient_color: tinte del cielo; van los tres
##                  juntos o ninguno. sun_energy multiplica la energía
##                  original del sol. Sin ellos el cielo no cambia.
##   fx_color:      color de los avisos en el suelo y las partículas;
##                  obligatorio en las filas que ya lo tienen.
##   impact_color, scorch_color: explosión y marca de cada meteorito;
##                  obligatorios en meteor_shower.
##   altar_ok:      el altar de evento puede invocarlo.
##   start/tick/stop: métodos de WeatherDirector; tick y stop pueden ir
##                  vacíos.
##   follow_up:     la fila que empieza en cuanto esta termina, sin pausa
##                  (las lunas malas -> luna llena; las dos lluvias ->
##                  lluvia dorada, el premio por aguantar la mala).
##   follow_up_only: nunca sale por sorteo, solo como follow_up.

const WEATHER_CATALOG: Array[Dictionary] = [
	{
		"id": "blood_moon", "group": "moon", "display_name": "Luna de sangre",
		"weight": 1.0, "duration": 45.0,
		"announce": "LUNA DE SANGRE — ¡la horda enloquece!",
		"sun_color": Color(1.0, 0.25, 0.2), "sun_energy": 0.9,
		"ambient_color": Color(0.5, 0.1, 0.1), "altar_ok": true,
		"start": &"_weather_start_dark_moon", "tick": &"", "stop": &"",
		"follow_up": "full_moon",
	},
	{
		"id": "eclipse", "group": "moon", "display_name": "Eclipse",
		"weight": 1.0, "duration": 45.0,
		"announce": "ECLIPSE — las sombras entran por todos lados",
		"sun_color": Color(0.35, 0.3, 0.5), "sun_energy": 0.35,
		"ambient_color": Color(0.12, 0.1, 0.2), "altar_ok": true,
		"start": &"_weather_start_dark_moon", "tick": &"", "stop": &"",
		"follow_up": "full_moon",
	},
	{
		"id": "full_moon", "group": "moon", "display_name": "Luna llena",
		"weight": 1.0, "duration": 40.0,
		"announce": "LUNA LLENA — la fortuna y la sabiduría te sonríen",
		"sun_color": Color(0.85, 0.9, 1.0), "sun_energy": 1.3,
		"ambient_color": Color(0.6, 0.65, 0.9), "altar_ok": false,
		"start": &"_weather_start_full_moon", "tick": &"", "stop": &"",
		"follow_up_only": true,
	},
	{
		"id": "enemy_rain", "group": "rain", "display_name": "Lluvia de enemigos",
		"weight": 1.0, "duration": 35.0,
		"announce": "LLUVIA DE ENEMIGOS — ¡caen del cielo!",
		"sun_color": Color(0.6, 0.8, 1.0), "sun_energy": 0.8,
		"ambient_color": Color(0.35, 0.45, 0.6), "fx_color": Color(0.6, 0.85, 1.0),
		"altar_ok": true,
		"start": &"_weather_start_enemy_rain", "tick": &"_weather_tick_enemy_rain",
		"stop": &"", "follow_up": "golden_rain",
	},
	{
		# Sin stop: los charcos sobreviven a la lluvia a propósito; cada uno
		# caduca solo y el cambio de etapa recoge los que queden.
		"id": "radioactive_rain", "group": "rain", "display_name": "Lluvia radiactiva",
		"weight": 1.0, "duration": 40.0,
		"announce": "LLUVIA RADIACTIVA — el suelo se vuelve ácido",
		"sun_color": Color(0.5, 1.0, 0.4), "sun_energy": 0.85,
		"ambient_color": Color(0.2, 0.4, 0.15), "altar_ok": true,
		"start": &"_weather_start_radioactive_rain",
		"tick": &"_weather_tick_radioactive_rain", "stop": &"",
		"follow_up": "golden_rain",
	},
	{
		"id": "golden_rain", "group": "rain", "display_name": "Lluvia dorada",
		"weight": 1.0, "duration": 40.0,
		"announce": "LLUVIA DORADA — todo brilla y todo vale la mitad",
		"sun_color": Color(1.0, 0.85, 0.4), "sun_energy": 1.2,
		"ambient_color": Color(0.6, 0.5, 0.2), "altar_ok": false,
		"start": &"_weather_start_golden_rain", "tick": &"",
		"stop": &"_weather_stop_golden_rain", "follow_up_only": true,
	},
	{
		# Una sola ola: su tick la vierte en tres segundos y termina el
		# desastre él mismo. Puede volver a salir más tarde.
		"id": "enemy_tsunami", "group": "disaster", "display_name": "Tsunami",
		"weight": 1.0, "duration": 3.0,
		"announce": "¡TSUNAMI DE ENEMIGOS! %s", "altar_ok": true,
		"start": &"_weather_start_tsunami", "tick": &"_weather_tick_tsunami",
		"stop": &"",
	},
	{
		"id": "earthquake", "group": "disaster", "display_name": "Terremoto",
		"weight": 1.0, "duration": 25.0,
		"announce": "¡TERREMOTO! El suelo no se queda quieto",
		"fx_color": Color(0.6, 0.55, 0.45), "altar_ok": true,
		"start": &"_weather_start_earthquake", "tick": &"_weather_tick_earthquake",
		"stop": &"_weather_stop_earthquake",
	},
	{
		# fx_color es el aviso en el suelo; impact_color, la explosión;
		# scorch_color, la marca que deja.
		"id": "meteor_shower", "group": "disaster", "display_name": "Lluvia de meteoritos",
		"weight": 1.0, "duration": 30.0,
		"announce": "¡LLUVIA DE METEORITOS! Sal de los círculos",
		"sun_color": Color(1.0, 0.6, 0.35), "sun_energy": 0.95,
		"ambient_color": Color(0.4, 0.25, 0.15), "fx_color": Color(1.0, 0.55, 0.2),
		"impact_color": Color(1.0, 0.6, 0.25), "scorch_color": Color(0.35, 0.2, 0.15),
		"altar_ok": true,
		"start": &"_weather_start_meteors", "tick": &"_weather_tick_meteors",
		"stop": &"",
	},
]

## Grupos que un pacto demoníaco puede alargar (RunState.sky_duration_multiplier).
const STRETCHABLE_GROUPS: Array[String] = ["moon", "rain"]

## Edita aquí: de dónde viene la ola del tsunami, el %s de su aviso. Cuatro
## rumbos bastan para saber hacia dónde correr. Orden fijo: este, sur,
## oeste, norte (el ángulo crece en ese sentido).
const COMPASS_WORDS: Array[String] = [
	"desde el este", "desde el sur", "desde el oeste", "desde el norte",
]


## La fila con ese id, o vacío.
static func by_id(id: String) -> Dictionary:
	for row: Dictionary in WEATHER_CATALOG:
		if String(row.id) == id:
			return row
	return {}


## Un id al azar del grupo, por peso, sin las filas follow_up_only. Tira un
## randf() del RNG de la partida.
static func roll_group(group: String) -> String:
	var total := 0.0
	for row: Dictionary in WEATHER_CATALOG:
		if String(row.group) == group and not bool(row.get("follow_up_only", false)):
			total += float(row.weight)
	if total <= 0.0:
		return ""
	var roll := randf() * total
	for row: Dictionary in WEATHER_CATALOG:
		if String(row.group) != group or bool(row.get("follow_up_only", false)):
			continue
		roll -= float(row.weight)
		if roll <= 0.0:
			return String(row.id)
	return ""


## La tirada del altar de evento: cualquier fila con altar_ok, por peso.
## Tira un randf() del RNG de la partida.
static func roll_altar() -> String:
	var total := 0.0
	for row: Dictionary in WEATHER_CATALOG:
		if bool(row.get("altar_ok", true)):
			total += float(row.weight)
	if total <= 0.0:
		return ""
	var roll := randf() * total
	for row: Dictionary in WEATHER_CATALOG:
		if not bool(row.get("altar_ok", true)):
			continue
		roll -= float(row.weight)
		if roll <= 0.0:
			return String(row.id)
	return ""


## El rumbo de COMPASS_WORDS que corresponde a un ángulo (radianes).
static func compass_word(angle: float) -> String:
	var turns := fposmod(angle / TAU, 1.0)
	if turns < 0.125 or turns >= 0.875:
		return COMPASS_WORDS[0]
	if turns < 0.375:
		return COMPASS_WORDS[1]
	if turns < 0.625:
		return COMPASS_WORDS[2]
	return COMPASS_WORDS[3]
