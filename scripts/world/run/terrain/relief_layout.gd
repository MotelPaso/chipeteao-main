class_name ReliefLayout
extends RefCounted
## El trazado del relieve por zonas de UNA etapa: dónde están las zonas
## elevadas (el macizo, los niveles que lleva encima y los cerros sueltos),
## sus rampas, el cañón, los puentes y las lomas, y las preguntas de
## geometría que todo lo demás le hace (¿este punto está sobre una zona?,
## ¿cuánto sube o baja ahí?, ¿por dónde pasan los cortes?).
##
## Las zonas se APILAN: una zona puede estar entera sobre la meseta de otra
## (su `parent`), y así tres cortes de 6 m hacen una montaña de 18. En
## `zones` un padre va siempre antes que sus hijas.
##
## Es solo geometría en planta: no conoce el ruido ni las alturas finales.
## Lo sortea ReliefPlanner con los valores de ReliefSettings, lo convierte en
## alturas ReliefField y lo consulta el Terrain, que es su dueño.
##
## Dos superficies por corte. Un corte separa un lado ALTO de uno BAJO. El
## colisionador del terreno lleva el escalón corrido LEDGE_INSET metros hacia
## el lado alto, escondido bajo la cornisa de roca (CliffWall); la superficie
## que se pisa llega hasta la línea nominal. Por eso las preguntas de
## pertenencia reciben `inset`: 0 = línea nominal, LEDGE_INSET = colisionador.

## Edita aquí (no hay Inspector): geometría ligada a la rejilla de 1 m del
## colisionador. Lo que se ajusta por arena vive en ReliefSettings.
##
## Muestras del contorno polar de una zona: una cada 2 grados.
const TABLE: int = 180
## Metros que el escalón del colisionador se corre hacia el lado alto de un
## corte. Con la rejilla de 1 m, las caras del escalón quedan a más de 0.1 m
## por dentro de la línea nominal, o sea bajo la cornisa.
const LEDGE_INSET: float = 1.5
## Separación de los puntos de una línea de corte, en metros.
const PATH_STEP: float = 1.6
## Ningún punto de una línea de corte queda a menos de esto de una esquina:
## más cerca, las filas de la cara de roca se pisarían entre sí.
const CORNER_CLEAR: float = 2.6
## Largo de cada tramo recto del eje del barranco, en metros.
const CENTER_STEP: float = 5.0
## Metros de suelo libre que se reservan al pie de cada rampa.
const RAMP_LANDING: float = 5.0
## Metros que el centro del claro de cada cabecera queda detrás del borde.
const HEAD_SETBACK: float = 3.0
## Tolerancia al proyectar sobre un tramo del eje (fracción del tramo): tapa
## las cuñas que quedan entre dos tramos en una curva.
const CHORD_SLACK: float = 0.08
## "Fuera del barranco" para ravine_coords().
const OUTSIDE := Vector2(-1.0, INF)


## Una rampa de tierra que baja de una zona elevada al suelo que la rodea.
class Ramp extends RefCounted:
	## Punto del eje donde la rampa empieza a bajar (u = 0).
	var origin: Vector2
	## Hacia afuera de la zona y hacia abajo.
	var dir: Vector2
	## `dir` girado 90 grados hacia donde crece el ángulo del contorno.
	var perp: Vector2
	## Largo de la bajada, en metros.
	var length: float
	var half_width: float
	## u mínimo (negativo): hasta dónde entra la rampa en la zona.
	var back: float
	## Ángulo del eje en el contorno de su zona.
	var angle: float
	## Ángulos del contorno donde lo cortan los dos costados de la rampa.
	var corner_lo: float
	var corner_hi: float


## Una zona elevada: un contorno polar alrededor de su centro.
class Zone extends RefCounted:
	## Qué es: &"massif" (el nivel ancho donde aparece el equipo), &"tier"
	## (el segundo nivel), &"summit" (la cumbre) o &"butte" (un cerro suelto).
	var kind: StringName = &"butte"
	## Índice de la zona sobre cuya meseta está, o -1 si está sobre el llano.
	var parent: int = -1
	## Cuánto sube ya el suelo donde se apoya: la suma de las alturas de
	## sus ancestros (0 sobre el llano).
	var floor: float = 0.0
	## Pendiente de sus rampas, en grados.
	var ramp_slope: float = 22.0
	var center: Vector2
	## Radio del contorno por ángulo (TABLE muestras).
	var radii: PackedFloat32Array = PackedFloat32Array()
	## Cuánto más que 1 hay que correr un radio para moverse 1 m en
	## perpendicular al contorno (el contorno no es un círculo).
	var oblique: PackedFloat32Array = PackedFloat32Array()
	var r_min: float
	var r_max: float
	## Altura de su acantilado sobre el suelo de alrededor, en metros.
	var height: float
	## Altura de la loma ancha sobre la que se apoya (0 si está sobre otra zona).
	var swell: float
	## True en LA zona más alta de la etapa (la cumbre).
	var top: bool
	var ramps: Array[Ramp] = []


## El cañón: un pasillo hundido a lo largo de un eje de tramos rectos, con
## una rampa en cada extremo. Un COLLADO lo interrumpe: el fondo sube por una
## rampa hasta el borde, sigue plano unos metros y vuelve a bajar. Entre dos
## puentes siempre hay uno, o ese tramo de fondo sería un pozo sin salida
## (un puente es una calzada maciza de pared a pared).
class Ravine extends RefCounted:
	var points: PackedVector2Array = PackedVector2Array()
	## Distancia acumulada a lo largo del eje hasta cada punto.
	var along: PackedFloat32Array = PackedFloat32Array()
	var length: float
	var half_width: float
	var depth: float
	## Largo de la rampa de cada extremo (y de cada lado de un collado), en metros.
	var ramp: float
	## Posición a lo largo del eje del centro de cada collado.
	var saddles: PackedFloat32Array = PackedFloat32Array()
	## Mitad del tramo plano de un collado, en metros.
	var saddle_half: float = 0.0
	## Caja del eje, para descartar rápido los puntos lejanos.
	var bounds: Rect2


## Un cruce del barranco: dónde va un puente.
class Crossing extends RefCounted:
	## Posición a lo largo del eje del barranco.
	var s: float
	var center: Vector2
	## Dirección del tablero, de un borde al otro.
	var axis: Vector2
	## Distancia entre los dos bordes del barranco, en metros.
	var span: float
	var width: float
	## Centros de los claros planos de las dos cabeceras.
	var head_a: Vector2
	var head_b: Vector2
	## Altura del tablero; la fija ReliefField al aplanar las cabeceras.
	var level: float


## Una loma ancha del nivel del bosque.
class Hill extends RefCounted:
	var center: Vector2
	var radius: float
	var height: float


## Una línea de corte: el lado ALTO queda a la izquierda al recorrerla y el
## BAJO a la derecha. `upper` y `lower` son cuánto sube o baja cada lado
## respecto del suelo base en cada punto; donde coinciden, el corte se acabó.
class CutPath extends RefCounted:
	var points: PackedVector2Array = PackedVector2Array()
	## Hacia el lado bajo, unitario.
	var normals: PackedVector2Array = PackedVector2Array()
	var upper: PackedFloat32Array = PackedFloat32Array()
	var lower: PackedFloat32Array = PackedFloat32Array()
	## Factor >= 1 del desplazamiento lateral en cada punto: en una esquina
	## las filas van sobre la bisectriz y más lejos.
	var miter: PackedFloat32Array = PackedFloat32Array()
	## Índice de la zona elevada que bordea, o -1 si es una pared del barranco.
	var zone: int = -1
	## Mayor altura visible del corte, en metros.
	var height: float = 0.0


var settings: ReliefSettings
## Mitad del lado de la arena, en metros.
var half: float
var zones: Array[Zone] = []
## null si la etapa no tiene barranco.
var ravine: Ravine = null
var crossings: Array[Crossing] = []
var hills: Array[Hill] = []
var cuts: Array[CutPath] = []
## True si el sorteo no encontró lugar y se usó el trazado fijo de reserva.
var fallback: bool = false


func _init(p_settings: ReliefSettings, p_half: float) -> void:
	settings = p_settings
	half = p_half


## Radio del contorno de `zone` en `angle` (radianes).
func zone_radius(zone: Zone, angle: float) -> float:
	return polar(zone.radii, angle)


## True si `point` cae en la meseta de `zone` a `margin` metros o más de su
## contorno. Con `margin` negativo, también hasta esa distancia por fuera.
func on_plateau(zone: Zone, point: Vector2, margin: float = 0.0) -> bool:
	var rel := point - zone.center
	var angle := rel.angle()
	return rel.length() <= polar(zone.radii, angle) - margin * polar(zone.oblique, angle)


## Cuánto sube el suelo en `point` por estar sobre `zone` (su meseta o una de
## sus rampas) respecto del suelo donde `zone` se apoya, o -1 si queda fuera.
## `inset` achica la zona esos metros desde sus cortes (ver la cabecera).
func raised_offset(zone: Zone, point: Vector2, inset: float = 0.0) -> float:
	var rel := point - zone.center
	var rho := rel.length()
	if rho <= zone.r_max:
		var angle := rel.angle()
		if rho <= polar(zone.radii, angle) - inset * polar(zone.oblique, angle):
			return zone.height
	for ramp: Ramp in zone.ramps:
		var local := point - ramp.origin
		var u := local.dot(ramp.dir)
		if u < ramp.back or u >= ramp.length:
			continue
		if absf(local.dot(ramp.perp)) > ramp.half_width - inset:
			continue
		return zone.height * clampf(1.0 - u / ramp.length, 0.0, 1.0)
	return -1.0


## (s, v) de `point` respecto del eje del barranco: s = metros a lo largo
## del eje, v = distancia al eje. OUTSIDE si no hay barranco, si el punto
## queda antes o después de sus extremos o lejos de su caja.
func ravine_coords(point: Vector2) -> Vector2:
	if ravine == null or not ravine.bounds.has_point(point):
		return OUTSIDE
	var best := OUTSIDE
	for index in ravine.points.size() - 1:
		var from := ravine.points[index]
		var chord := ravine.points[index + 1] - from
		var span := ravine.along[index + 1] - ravine.along[index]
		var t := (point - from).dot(chord) / (span * span)
		if t < -CHORD_SLACK or t > 1.0 + CHORD_SLACK:
			continue
		var distance := point.distance_to(from + chord * clampf(t, 0.0, 1.0))
		if distance < best.y:
			best = Vector2(ravine.along[index] + span * t, distance)
	if best.x < 0.0 or best.x > ravine.length:
		return OUTSIDE
	return best


## Metros que baja el fondo del cañón a `s` metros de su inicio: 0 en los
## dos extremos y sobre cada collado, la profundidad completa pasadas las rampas.
func ravine_drop(s: float) -> float:
	if ravine == null:
		return 0.0
	var run := minf(s, ravine.length - s)
	for saddle: float in ravine.saddles:
		run = minf(run, absf(s - saddle) - ravine.saddle_half)
	return ravine.depth * clampf(run / ravine.ramp, 0.0, 1.0)


## [punto, tangente unitaria] del eje del barranco a `s` metros de su inicio.
func ravine_frame(s: float) -> PackedVector2Array:
	var last := ravine.points.size() - 2
	var index := 0
	while index < last and ravine.along[index + 1] < s:
		index += 1
	var from := ravine.points[index]
	var chord := ravine.points[index + 1] - from
	var span := ravine.along[index + 1] - ravine.along[index]
	var t := clampf((s - ravine.along[index]) / span, 0.0, 1.0)
	return PackedVector2Array([from + chord * t, chord / span])


## Cuánto sube (zona elevada, rampa) o baja (cañón) el suelo en `point`
## respecto del suelo base; 0 en el llano. Sobre zonas apiladas gana la más
## alta. `inset`: ver la cabecera.
func offset_at(point: Vector2, inset: float = 0.0) -> float:
	var highest := 0.0
	for zone: Zone in zones:
		if absf(point.x - zone.center.x) > zone.r_max + 40.0 \
				or absf(point.y - zone.center.y) > zone.r_max + 40.0:
			continue
		var lift := raised_offset(zone, point, inset)
		if lift >= 0.0:
			highest = maxf(highest, zone.floor + lift)
	if highest > 0.0:
		return highest
	var coords := ravine_coords(point)
	if coords.x >= 0.0 and coords.y <= ravine.half_width + inset:
		return -ravine_drop(coords.x)
	return 0.0


## En qué nivel cae `point` (línea nominal): 0 = el llano, i + 1 = la zona
## elevada i (rampas incluidas; de dos apiladas, la de arriba), -1 = el cañón.
func level_at(point: Vector2) -> int:
	var level := 0
	for index in zones.size():
		if raised_offset(zones[index], point) >= 0.0:
			level = index + 1
	if level != 0:
		return level
	var coords := ravine_coords(point)
	if coords.x >= 0.0 and coords.y <= ravine.half_width:
		return -1
	return 0


## Rampas de entrada de toda la etapa: las de las zonas más las del cañón
## (dos en los extremos y dos por collado).
func ramp_count() -> int:
	var count := 0
	for zone: Zone in zones:
		count += zone.ramps.size()
	if ravine != null:
		count += 2 + ravine.saddles.size() * 2
	return count


## Altura del corte más alto, en metros.
func tallest_cut() -> float:
	var tallest := 0.0
	for cut: CutPath in cuts:
		tallest = maxf(tallest, cut.height)
	return tallest


## Huella del trazado: la misma semilla da la misma, dos semillas no.
func digest() -> String:
	var parts := PackedStringArray()
	for zone: Zone in zones:
		parts.append("z %s %d %d %d %d %d" % [zone.kind, zone.parent,
				roundi(zone.center.x * 100.0), roundi(zone.center.y * 100.0),
				roundi(zone.height * 100.0), roundi(zone.swell * 100.0)])
		for index in range(0, TABLE, 12):
			parts.append(str(roundi(zone.radii[index] * 100.0)))
		for ramp: Ramp in zone.ramps:
			parts.append("r %d %d" % [roundi(ramp.angle * 1000.0), roundi(ramp.length * 100.0)])
	if ravine != null:
		parts.append("v %d %d" % [roundi(ravine.half_width * 100.0), roundi(ravine.depth * 100.0)])
		for saddle: float in ravine.saddles:
			parts.append("s %d" % roundi(saddle * 100.0))
		for point: Vector2 in ravine.points:
			parts.append("%d %d" % [roundi(point.x * 100.0), roundi(point.y * 100.0)])
	for crossing: Crossing in crossings:
		parts.append("c %d" % roundi(crossing.s * 100.0))
	for hill: Hill in hills:
		parts.append("h %d %d %d" % [roundi(hill.center.x * 100.0),
				roundi(hill.center.y * 100.0), roundi(hill.height * 100.0)])
	return " ".join(parts).sha256_text().left(8)


## Lectura interpolada de una tabla polar de TABLE muestras (Zone.radii,
## Zone.oblique) en `angle` radianes.
func polar(table: PackedFloat32Array, angle: float) -> float:
	var at := fposmod(angle, TAU) / TAU * float(TABLE)
	var index := int(at) % TABLE
	return lerpf(table[index], table[(index + 1) % TABLE], at - floorf(at))
