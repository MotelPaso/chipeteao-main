class_name OutsideRelief
extends RefCounted
## El suelo de AFUERA del muro de una arena con relieve por zonas: sale del
## nivel del borde y sube en lomas hasta el horizonte. Es una sola función de
## altura (height_at) que leen el Terrain (la franja de pasto que sigue pasado
## el muro, en su misma malla: OutsideApron) y ForestEdge (los árboles de esa
## franja y el manto del bosque profundo).
##
## Concuerda con el trazado de la etapa: detrás de una zona elevada pegada a
## un muro el afuera sube más (la montaña sigue del otro lado), y donde un
## cañón apunta a un muro se abre un valle que lo continúa.
##
## La distancia al cuadrado de la arena se redondea en las esquinas: las
## curvas de nivel del afuera son arcos y nada se lee como la esquina de un
## cuadrado. Todo sale de la semilla de partida con su propia sal y no saca
## números de ningún RNG.

## Edita aquí (no hay Inspector); los valores de diseño están en ReliefSettings
## (grupo «Borde del mapa»).
##
## Sal de los ruidos del afuera.
const SEED_SALT: int = 0x4F555453
## Metros entre dos muestras del contorno de la arena (cuánto sube y cuánto
## se hunde el afuera frente a cada tramo de muro).
const PERIMETER_STEP: float = 4.0
## Metros desde su contorno hasta los que una zona elevada levanta el afuera.
const FOLLOW_REACH: float = 70.0
## Medio ancho, en metros, del valle que continúa un cañón afuera del muro.
const VALLEY_HALF: float = 34.0
## Metros que se busca hacia afuera, desde la punta de un cañón, el muro al
## que apunta (más lejos, el cañón no apunta a ningún muro).
const VALLEY_AIM: float = 90.0
## Longitud de onda del detalle cercano y de las lomas lejanas, en metros.
const DETAIL_SIZE: float = 26.0
const HILL_SIZE: float = 150.0
## Metros desde el muro en que el detalle llega a su fuerza.
const DETAIL_RAMP: float = 8.0
## Metros pasada la franja en que las lomas lejanas llegan a su altura.
const FAR_RAMP: float = 120.0
## Exponente de la subida de la franja: sale plana del muro y se empina.
const RISE_CURVE: float = 1.6

## Mitad del lado de la arena y ancho de la franja de pasto, en metros.
var half: float = 0.0
var reach: float = 0.0

var _settings: ReliefSettings = null
var _detail := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
## Por muestra del contorno: cuánto se levanta el afuera (1 = nada) y qué
## fracción se hunde (0 = nada).
var _lift := PackedFloat32Array()
var _valley := PackedFloat32Array()
var _perimeter: float = 0.0


func _init(layout: ReliefLayout, run_seed: int) -> void:
	_settings = layout.settings
	half = layout.half
	reach = _settings.outside_reach
	_perimeter = half * 8.0
	for noise: FastNoiseLite in [_detail, _hills]:
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.fractal_octaves = 2
	_detail.seed = run_seed ^ SEED_SALT
	_detail.frequency = 1.0 / DETAIL_SIZE
	_hills.seed = (run_seed ^ SEED_SALT) + 1
	_hills.frequency = 1.0 / HILL_SIZE
	_sample_layout(layout)


## Metros de `xz` al cuadrado de la arena, con las esquinas redondeadas: 0
## adentro.
func distance_out(x: float, z: float) -> float:
	return Vector2(maxf(absf(x) - half, 0.0), maxf(absf(z) - half, 0.0)).length()


## Altura del suelo de afuera en (x, z): 0 adentro y sobre el muro.
func height_at(x: float, z: float) -> float:
	var d := distance_out(x, z)
	if d <= 0.0:
		return 0.0
	var t := perimeter_param(x, z)
	var lift := _read(_lift, t)
	var sink := 1.0 - _read(_valley, t)
	var near := _settings.outside_rise * pow(minf(d / maxf(reach, 0.001), 1.0), RISE_CURVE)
	var far_t := smoothstep(reach, reach + FAR_RAMP, d)
	var far := _settings.outside_far_rise * far_t
	var hills := (_hills.get_noise_2d(x, z) * 0.5 + 0.5) * _settings.outside_hills * far_t
	var detail := (_detail.get_noise_2d(x, z) * 0.5 + 0.5) * _settings.outside_detail \
			* smoothstep(0.0, DETAIL_RAMP, d)
	return ((near + far + hills) * lift + detail) * sink


## Posición, en metros, del punto del muro más cercano a (x, z) a lo largo del
## contorno de la arena: 0 en la esquina noroeste y creciendo hacia el este
## por el muro norte (norte = -Z), como el reloj visto desde arriba.
func perimeter_param(x: float, z: float) -> float:
	var b := Vector2(clampf(x, -half, half), clampf(z, -half, half))
	if is_equal_approx(b.y, -half):
		return b.x + half
	if is_equal_approx(b.x, half):
		return half * 2.0 + b.y + half
	if is_equal_approx(b.y, half):
		return half * 4.0 + half - b.x
	return half * 6.0 + half - b.y


## El punto del muro a `t` metros del contorno (ver perimeter_param).
func perimeter_point(t: float) -> Vector2:
	var at := fposmod(t, _perimeter)
	var side := half * 2.0
	if at < side:
		return Vector2(-half + at, -half)
	if at < side * 2.0:
		return Vector2(half, -half + at - side)
	if at < side * 3.0:
		return Vector2(half - (at - side * 2.0), half)
	return Vector2(-half, half - (at - side * 3.0))


## Largo del contorno de la arena, en metros.
func perimeter() -> float:
	return _perimeter


## Lectura interpolada de una tabla del contorno en `t` metros.
func _read(table: PackedFloat32Array, t: float) -> float:
	var at := fposmod(t, _perimeter) / PERIMETER_STEP
	var index := int(at) % table.size()
	return lerpf(table[index], table[(index + 1) % table.size()], at - floorf(at))


## Llena las tablas del contorno desde el trazado: la subida detrás de cada
## zona elevada cercana y el valle donde apunta cada punta de cañón.
func _sample_layout(layout: ReliefLayout) -> void:
	var count := ceili(_perimeter / PERIMETER_STEP)
	_lift.resize(count)
	_valley.resize(count)
	var aims := _valley_aims(layout)
	for index in count:
		var wall := perimeter_point(float(index) * PERIMETER_STEP)
		var lift := 0.0
		for zone: ReliefLayout.Zone in layout.zones:
			# Lo que está bajo el llano (una isla en un lago) no levanta nada.
			if zone.floor < 0.0:
				continue
			var gap := ReliefQueries.zone_distance(layout, zone, wall, FOLLOW_REACH)
			if gap < FOLLOW_REACH:
				lift = maxf(lift, (zone.floor + zone.height) / 6.0 * (1.0 - gap / FOLLOW_REACH))
		_lift[index] = 1.0 + _settings.outside_follow * lift
		var valley := 0.0
		for aim: Vector2 in aims:
			valley = maxf(valley, 1.0 - smoothstep(0.0, VALLEY_HALF, wall.distance_to(aim)))
		_valley[index] = valley * _settings.outside_valley


## Los puntos del muro a los que apunta cada punta del cañón (si llega a
## alguno a menos de VALLEY_AIM metros de su punta).
func _valley_aims(layout: ReliefLayout) -> PackedVector2Array:
	var aims := PackedVector2Array()
	var ravine := layout.ravine
	if ravine == null or ravine.points.size() < 2:
		return aims
	var last := ravine.points.size() - 1
	var tips: Array[PackedVector2Array] = [
		PackedVector2Array([ravine.points[0], ravine.points[0] - ravine.points[1]]),
		PackedVector2Array([ravine.points[last], ravine.points[last] - ravine.points[last - 1]]),
	]
	for tip: PackedVector2Array in tips:
		var out := tip[1].normalized()
		var walked := 0.0
		while walked <= VALLEY_AIM:
			var at := tip[0] + out * walked
			if absf(at.x) >= half or absf(at.y) >= half:
				aims.append(Vector2(clampf(at.x, -half, half), clampf(at.y, -half, half)))
				break
			walked += 2.0
	return aims
