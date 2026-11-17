class_name Bridge
extends StaticBody3D
## El Gran Puente del cañón: un puente de piedra de arcos ABIERTOS. Se cruza
## por arriba, entre barandas, y se pasa por debajo; a cada lado de cada
## estribo baja una escalera hasta el fondo. Escena:
## scenes/world/props/Bridge.tscn.
##
## El origen está en el centro de la cara de arriba del tablero; el tablero
## corre a lo largo de X y el cañón a lo largo de Z. Quien lo coloca
## (ReliefDressing) le da `span`, `width`, `drop`, `overlap` y `stair_reach`
## ANTES de add_child: _ready arma la cantería (BridgeMasonry) y las formas
## de colisión.
##
## Bajo el tablero no hay pared que trepar. La horda que persigue a alguien
## parado en el puente entra por las cabeceras: se lo dice ReliefLanes, que
## lee EnemyBase. Los estribos y las escaleras sí son macizos, y la cara de
## afuera de una escalera cae a más de 60 grados: se trepa.

@export_group("Medidas")
## Luz del puente: de un borde del cañón al otro, en metros.
@export var span: float = 26.0
## Ancho de la obra en los estribos, en metros. El tablero mide dos `wing` menos.
@export var width: float = 9.0
## Metros desde la cara de arriba del tablero hasta el fondo del cañón.
@export var drop: float = 6.2
## Metros que el tablero y los estribos se meten en cada orilla.
@export var overlap: float = 3.5
## Metros que cada estribo asoma dentro del cañón desde el borde. Tiene que
## pasar el pie de la pared de roca, que cae inclinada.
@export var nose: float = 3.8
## Metros que la obra baja pasado el fondo del cañón.
@export var footing: float = 2.5
## Lo que cada estribo sobresale del tablero a cada lado, en metros.
@export var wing: float = 0.6
## Grosor del tablero, en metros.
@export var deck_thickness: float = 0.9

@export_group("Arcos")
## Pilas dentro del cañón (los arcos son uno más).
@export_range(0, 4) var pier_count: int = 2
## Grosor de cada pila, en metros.
@export var pier_thickness: float = 1.9
## Largo del tajamar, la punta de cada pila, en metros.
@export var cutwater: float = 1.6
## Metros de piedra entre la clave de cada arco y el tablero.
@export var crown_cover: float = 0.5
## Metros de pila que quedan a la vista bajo el arranque de los arcos, como mínimo.
@export var pier_stand: float = 1.4

@export_group("Barandas")
## Alto de la baranda, en metros (bajo 1.5: un raider la salta).
@export var parapet_height: float = 0.9
## Grosor de la baranda, en metros.
@export var parapet_thickness: float = 0.55
## Cada cuántos metros va un poste en la baranda.
@export var post_every: float = 2.6

@export_group("Torres")
## Altura de las cuatro torres sobre el tablero, en metros (bajo 10: la
## horda trepa 10 de una vez).
@export var tower_height: float = 8.6
## Radio de cada torre, en metros.
@export var tower_radius: float = 1.15
## Metros desde el borde del cañón hacia el medio del puente donde se paran
## las torres.
@export var tower_inset: float = 0.6
## Alto del dintel que une las dos torres de cada cabecera, en metros (0 = sin dintel).
@export var lintel_height: float = 1.1
## Ancho y largo del estandarte que cuelga de cada dintel, en metros.
@export var banner_width: float = 2.2
@export var banner_length: float = 3.6
## Color del paño del estandarte y de su franja.
@export var banner_color: Color = Color(0.72, 0.16, 0.14)
@export var banner_trim_color: Color = Color(0.93, 0.74, 0.28)
## Color de la llama de los braseros.
@export var flame_color: Color = Color(1.0, 0.5, 0.12)
## Fuerza de la luz de cada brasero (0 = sin luz).
@export var flame_light_energy: float = 1.6
## Alcance de la luz de cada brasero, en metros.
@export var flame_light_range: float = 11.0
## Cuánto late la llama: fracción de su tamaño.
@export var flame_flicker: float = 0.12

@export_group("Escaleras")
## Metros a lo largo del cañón que ocupa cada escalera desde el costado del
## estribo, descanso incluido. Con el fondo a `drop` metros, de aquí sale
## la pendiente: tiene que quedar bajo 45 grados.
@export var stair_reach: float = 12.5
## Largo del descanso de arriba de cada escalera, en metros.
@export var stair_landing: float = 3.6
## Metros que el pie de la escalera asoma del borde del cañón: lo que se
## inclina la roca más el ancho que queda para pisar.
@export var stair_out: float = 6.4
## Metros que la escalera se mete en la orilla.
@export var stair_embed: float = 1.2
## Alto de cada peldaño dibujado, en metros. La colisión es una rampa lisa.
@export var step_rise: float = 0.36

@export_group("Colores")
## Piedra de los muros.
@export var stone_color: Color = Color(0.63, 0.61, 0.56)
## Piedra de las hiladas de abajo, más oscura y húmeda.
@export var stone_low_color: Color = Color(0.41, 0.43, 0.42)
## Losas del tablero, de los descansos y de los peldaños.
@export var paving_color: Color = Color(0.74, 0.71, 0.63)
## Dovelas de los arcos, postes y remates.
@export var trim_color: Color = Color(0.8, 0.77, 0.69)
## Musgo de las caras de arriba que nadie pisa.
@export var moss_color: Color = Color(0.36, 0.5, 0.3)

## Semilla del tono de cada sillar; la fija quien coloca el puente.
var shape_seed: int = 0

var _flames: Array[Node3D] = []
var _clock: float = 0.0


func _ready() -> void:
	var masonry := BridgeMasonry.new(self)
	add_child(masonry.build())
	for spot: Vector3 in masonry.flame_spots:
		_add_flame(masonry, spot)
	_build_collision()
	set_process(not _flames.is_empty() and flame_flicker > 0.0)


func _process(delta: float) -> void:
	_clock += delta
	for index in _flames.size():
		var beat := sin(_clock * 9.0 + float(index) * 1.7) + 0.6 * sin(_clock * 23.0 + float(index))
		_flames[index].scale = Vector3.ONE * (1.0 + flame_flicker * beat * 0.6)


# --- medidas que comparte con su cantería ----------------------------------------

## Los dos extremos del tablero, en el mundo, a la altura donde se pisa.
func deck_ends() -> PackedVector3Array:
	var reach := global_transform.basis.x * (span * 0.5 + overlap)
	return PackedVector3Array([global_position - reach, global_position + reach])


## Ancho del tablero entre las caras de afuera de las barandas, en metros.
func deck_width() -> float:
	return width - wing * 2.0


## Luz libre entre los dos estribos, en metros.
func clear_span() -> float:
	return span - nose * 2.0


## Luz de cada arco, en metros.
func arch_span() -> float:
	return (clear_span() - pier_thickness * float(pier_count)) / float(pier_count + 1)


## Posición en X del centro de la pila `index` (0 = la primera).
func pier_x(index: int) -> float:
	return -clear_span() * 0.5 + float(index + 1) * arch_span() \
			+ (float(index) + 0.5) * pier_thickness


## Altura de la clave de los arcos (y negativa: bajo el tablero).
func crown_y() -> float:
	return -deck_thickness - crown_cover


## Altura del arranque de los arcos: medio punto si cabe, rebajado si no.
func spring_y() -> float:
	return maxf(crown_y() - arch_span() * 0.5, -drop + pier_stand)


## Lo que la cara de afuera de cada escalera se abre por metro que baja.
func stair_batter() -> float:
	return (stair_out - nose) / maxf(drop, 0.1)


## Dónde se para la torre de la orilla `side` (-1, +1) y del lado `turn` del
## tablero (-1, +1), a la altura del tablero.
func tower_spot(side: float, turn: float) -> Vector3:
	return Vector3(side * (span * 0.5 - tower_inset), 0.0, turn * (deck_width() * 0.5 + 0.1))


## Los seis puntos del contorno de la pila `index`, con sus dos tajamares,
## repetidos a las alturas `low` y `high`.
func pier_hull(index: int, low: float, high: float) -> PackedVector3Array:
	var x := pier_x(index)
	var half := pier_thickness * 0.5
	var reach := deck_width() * 0.5
	var points := PackedVector3Array()
	for y: float in [low, high]:
		points.append(Vector3(x - half, y, -reach))
		points.append(Vector3(x, y, -reach - cutwater))
		points.append(Vector3(x + half, y, -reach))
		points.append(Vector3(x + half, y, reach))
		points.append(Vector3(x, y, reach + cutwater))
		points.append(Vector3(x - half, y, reach))
	return points


## El macizo de la escalera de la orilla `side` que baja hacia `turn`: el
## descanso, la bajada y el relleno de debajo. Diez puntos, convexo. Orden:
## descanso (4), pie de la bajada (2) y base (4).
func stair_hull(side: float, turn: float) -> PackedVector3Array:
	var rim := span * 0.5
	var inner := side * (rim + stair_embed)
	var top_out := side * (rim - nose)
	var deep := drop + footing
	var foot_out := side * (rim - nose - stair_batter() * drop)
	var base_out := side * (rim - nose - stair_batter() * deep)
	var near := turn * (width * 0.5 - 0.3)
	var landing := turn * (width * 0.5 + stair_landing)
	var far := turn * (width * 0.5 + stair_reach)
	return PackedVector3Array([
		Vector3(inner, 0.0, near), Vector3(top_out, 0.0, near),
		Vector3(top_out, 0.0, landing), Vector3(inner, 0.0, landing),
		Vector3(inner, -drop, far), Vector3(foot_out, -drop, far),
		Vector3(inner, -deep, near), Vector3(base_out, -deep, near),
		Vector3(base_out, -deep, far), Vector3(inner, -deep, far),
	])


# --- colisión y braseros ---------------------------------------------------------

func _build_collision() -> void:
	var deep := drop + footing
	_add_box(Vector3(0.0, -deck_thickness * 0.5, 0.0),
			Vector3(span + overlap * 2.0, deck_thickness, deck_width()))
	for side: float in [-1.0, 1.0]:
		# Estribo: del fondo al tablero, del borde hacia la orilla y hacia el cañón.
		_add_box(Vector3(side * (span * 0.5 + (overlap - nose) * 0.5),
				-deck_thickness - (deep - deck_thickness) * 0.5, 0.0),
				Vector3(nose + overlap, deep - deck_thickness, width))
		_add_box(Vector3(0.0, parapet_height * 0.5,
				side * (deck_width() - parapet_thickness) * 0.5),
				Vector3(span + 1.0, parapet_height, parapet_thickness))
		for turn: float in [-1.0, 1.0]:
			_add_hull(stair_hull(side, turn))
	for index in pier_count:
		_add_hull(pier_hull(index, -deep, spring_y()))
	_build_towers()


## Las torres van en un cuerpo aparte: son un obstáculo que se rodea, no un
## piso del puente (el arnés lee como suelo todo lo que choca del Bridge).
func _build_towers() -> void:
	var towers := StaticBody3D.new()
	towers.name = "Towers"
	add_child(towers)
	for side: float in [-1.0, 1.0]:
		for turn: float in [-1.0, 1.0]:
			var shape := CylinderShape3D.new()
			shape.radius = tower_radius
			shape.height = tower_height
			var holder := CollisionShape3D.new()
			holder.shape = shape
			holder.position = tower_spot(side, turn) + Vector3.UP * tower_height * 0.5
			towers.add_child(holder)


func _add_box(center: Vector3, size: Vector3) -> void:
	var box := BoxShape3D.new()
	box.size = size
	_add_shape(box, center)


func _add_hull(points: PackedVector3Array) -> void:
	var hull := ConvexPolygonShape3D.new()
	hull.points = points
	_add_shape(hull, Vector3.ZERO)


func _add_shape(shape: Shape3D, at: Vector3) -> void:
	var holder := CollisionShape3D.new()
	holder.shape = shape
	holder.position = at
	add_child(holder)


## Una llama en `spot` (local): la malla que late y, si hay energía, su luz.
func _add_flame(masonry: BridgeMasonry, spot: Vector3) -> void:
	var flame := masonry.flame()
	flame.position = spot
	add_child(flame)
	_flames.append(flame)
	if flame_light_energy <= 0.0:
		return
	var light := OmniLight3D.new()
	light.light_color = flame_color
	light.light_energy = flame_light_energy
	light.omni_range = flame_light_range
	light.shadow_enabled = false
	light.position = spot + Vector3.UP * 0.6
	add_child(light)
