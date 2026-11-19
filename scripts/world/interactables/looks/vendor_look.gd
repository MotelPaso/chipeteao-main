class_name VendorLook
extends Node3D
## Cómo se ve el puesto del vendedor: un mostrador de tablas con pociones,
## monedas y un libro, cuatro postes, una repisa con frascos detrás del
## vendedor, sacos y cajones a los costados, un farol colgado, una alfombra
## al frente y un sombrero para el vendedor. El toldo es el nodo Sign del
## puesto, que lo tiñe con el color de su tipo y lo mece apenas: este script
## solo le da la forma. Va como hijo de Vendor.tscn; la figura, el toldo y
## la luz siguen siendo del puesto. No tiene colisión, igual que antes.

@export_group("Medidas")
## Ancho, alto y fondo del mostrador, en metros.
@export var counter_size: Vector3 = Vector3(2.4, 1.0, 0.8)
## Ancho del toldo, en metros.
@export var canopy_width: float = 3.0
## Alto del borde de atrás del toldo, en metros.
@export var canopy_back_height: float = 2.85
## Alto del borde de adelante del toldo, en metros.
@export var canopy_front_height: float = 2.4
## Fondo del toldo hacia atrás del mostrador, en metros.
@export var canopy_back: float = 1.4
## Fondo del toldo hacia adelante del mostrador, en metros.
@export var canopy_front: float = 0.9
## Ondas que cuelgan del borde de adelante del toldo.
@export_range(2, 12) var scallops: int = 6

@export_group("Colores")
## Madera del mostrador, los postes y la repisa.
@export var wood_color: Color = Color(0.42, 0.3, 0.2)
## Tablas claras del mostrador.
@export var plank_color: Color = Color(0.55, 0.4, 0.27)
## Sacos.
@export var sack_color: Color = Color(0.72, 0.62, 0.44)
## Color de la alfombra.
@export var rug_color: Color = Color(0.62, 0.2, 0.18)
## Color del borde de la alfombra.
@export var rug_trim_color: Color = Color(0.95, 0.78, 0.35)
## Líquido de las pociones, en orden.
@export var potion_colors: Array[Color] = [Color(0.95, 0.25, 0.3), Color(0.3, 0.6, 1.0),
		Color(0.4, 0.95, 0.45), Color(0.85, 0.5, 1.0)]
## Color del vidrio de los frascos.
@export var glass_color: Color = Color(0.82, 0.9, 0.92)
## Color del oro de las monedas.
@export var gold_color: Color = Color(0.96, 0.74, 0.22)
## Color de la luz del farol.
@export var lantern_color: Color = Color(1.0, 0.78, 0.4)
## Sombrero del vendedor.
@export var hat_color: Color = Color(0.25, 0.18, 0.15)

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	# El toldo va primero y sin esperar: el puesto lee la altura del cartel en su _ready.
	_shape_canopy()
	_build.call_deferred()


## Le da forma de toldo al cartel del puesto: un paño inclinado con ondas al
## frente, con el origen donde el cartel ya estaba.
func _shape_canopy() -> void:
	var sign := get_parent().get_node_or_null("Sign") as MeshInstance3D
	if sign == null:
		return
	var origin := (canopy_back_height + canopy_front_height) * 0.5
	sign.position = Vector3(0.0, origin, 0.0)
	var mesh := LowPolyMesh.new(3)
	var half := canopy_width * 0.5
	var back := Vector3(0.0, canopy_back_height - origin, -canopy_back)
	var front := Vector3(0.0, canopy_front_height - origin, canopy_front)
	var under := Vector3(0.0, -2.0, 0.0)
	for lift: float in [0.0, 0.05]:
		mesh.quad(back + Vector3(-half, lift, 0.0), back + Vector3(half, lift, 0.0),
				front + Vector3(half, lift, 0.0), front + Vector3(-half, lift, 0.0), Color.WHITE,
				under if lift > 0.0 else Vector3(0.0, 3.0, 0.0))
	var wave := canopy_width / float(scallops)
	for index in scallops:
		var left := front + Vector3(-half + wave * float(index), 0.0, 0.0)
		var right := left + Vector3(wave, 0.0, 0.0)
		var tip := (left + right) * 0.5 + Vector3(0.0, -0.28, 0.02)
		mesh.triangle(left, right, tip, Color.WHITE, tip + Vector3(0.0, 0.0, -1.0))
		mesh.triangle(left, right, tip, Color.WHITE, tip + Vector3(0.0, 0.0, 1.0))
	sign.mesh = mesh.commit()


func _build() -> void:
	_rng.seed = hash(Vector3i(roundi(global_position.x * 10.0), 33, roundi(global_position.z * 10.0)))
	var wood := LowPolyMesh.new(int(_rng.seed))
	var glow := LowPolyMesh.new(int(_rng.seed) + 1)
	_counter(wood, glow)
	_posts(wood)
	_shelf(wood, glow)
	_sides(wood)
	_rug(wood)
	_lantern(wood, glow)
	_hat(wood)
	ShrineKit.hang(self, wood, glow)


## El mostrador de tablas con su tapa, y lo que hay encima.
func _counter(wood: LowPolyMesh, glow: LowPolyMesh) -> void:
	var planks := 3
	for index in planks:
		var tall := counter_size.y / float(planks)
		wood.block(Transform3D(Basis.IDENTITY, Vector3(0.0, tall * (float(index) + 0.5), 0.0)),
				Vector3(counter_size.x, tall * 0.94, counter_size.z),
				plank_color.lerp(wood_color, _rng.randf_range(0.0, 0.5)))
	wood.block(Transform3D(Basis.IDENTITY, Vector3(0.0, counter_size.y + 0.04, 0.02)),
			Vector3(counter_size.x + 0.2, 0.08, counter_size.z + 0.15), wood_color)
	var top := counter_size.y + 0.08
	for index in 3:
		_potion(wood, glow, Vector3(-0.85 + 0.28 * float(index), top, 0.15),
				potion_colors[index % potion_colors.size()])
	ShrineKit.coins(wood, Vector3(0.55, top, 0.1), 0.16, 5, gold_color, _rng)
	wood.block(Transform3D(Basis(Vector3.UP, 0.3), Vector3(0.05, top + 0.05, -0.05)),
			Vector3(0.36, 0.1, 0.26), rug_color.darkened(0.3))


## Los cuatro postes del toldo.
func _posts(wood: LowPolyMesh) -> void:
	var half := canopy_width * 0.5 - 0.1
	for turn: float in [-1.0, 1.0]:
		ShrineKit.strut(wood, Vector3(turn * half, -0.1, -canopy_back + 0.1),
				Vector3(turn * half, canopy_back_height, -canopy_back + 0.1), 0.12, wood_color)
		ShrineKit.strut(wood, Vector3(turn * half, -0.1, canopy_front - 0.1),
				Vector3(turn * half, canopy_front_height, canopy_front - 0.1), 0.12, wood_color)


## La repisa de atrás con frascos.
func _shelf(wood: LowPolyMesh, glow: LowPolyMesh) -> void:
	var z := -canopy_back + 0.25
	for level: float in [0.9, 1.5]:
		wood.block(Transform3D(Basis.IDENTITY, Vector3(0.0, level, z)),
				Vector3(canopy_width - 0.5, 0.06, 0.35), wood_color.lightened(0.05))
		for index in 5:
			_potion(wood, glow, Vector3(-1.0 + 0.5 * float(index) + _rng.randf_range(-0.08, 0.08),
					level + 0.03, z), potion_colors[_rng.randi() % potion_colors.size()])


## Un frasco: vidrio, el líquido que brilla y un corcho.
func _potion(wood: LowPolyMesh, glow: LowPolyMesh, foot: Vector3, liquid: Color) -> void:
	var size := _rng.randf_range(0.07, 0.1)
	glow.blob(foot + Vector3.UP * size, Vector3(size, size, size), liquid, 6, 3, 0.05)
	var neck_low := wood.ring(foot + Vector3.UP * size * 1.8, size * 0.35, 5)
	var neck_high := wood.ring(foot + Vector3.UP * size * 2.6, size * 0.35, 5)
	wood.band(neck_low, neck_high, glass_color)
	wood.cap(neck_high, plank_color, foot)


## Sacos y cajones a los costados del mostrador.
func _sides(wood: LowPolyMesh) -> void:
	for turn: float in [-1.0, 1.0]:
		var x := turn * (counter_size.x * 0.5 + 0.55)
		var crate := 0.55
		wood.block(Transform3D(Basis(Vector3.UP, _rng.randf_range(-0.2, 0.2)),
				Vector3(x, crate * 0.5, -0.1)), Vector3.ONE * crate, plank_color.darkened(0.1))
		wood.blob(Vector3(x + turn * 0.1, crate + 0.18, -0.15), Vector3(0.24, 0.22, 0.22),
				sack_color, 6, 4, 0.12)
		wood.blob(Vector3(x - turn * 0.05, 0.25, 0.5), Vector3(0.28, 0.27, 0.26), sack_color, 6, 4,
				0.12)


## La alfombra al frente del puesto.
func _rug(wood: LowPolyMesh) -> void:
	var y := 0.025
	var a := Vector3(-1.1, y, counter_size.z * 0.5 + 0.15)
	var depth := 1.3
	wood.plate(a, a + Vector3(2.2, 0.0, 0.0), a + Vector3(2.2, 0.0, depth), a + Vector3(0.0, 0.0, depth),
			rug_color, a + Vector3(1.1, -1.0, 0.5))
	wood.plate(a + Vector3(0.2, 0.004, 0.2), a + Vector3(2.0, 0.004, 0.2),
			a + Vector3(2.0, 0.004, depth - 0.2), a + Vector3(0.2, 0.004, depth - 0.2),
			rug_trim_color, a + Vector3(1.1, -1.0, 0.5))
	wood.plate(a + Vector3(0.35, 0.008, 0.35), a + Vector3(1.85, 0.008, 0.35),
			a + Vector3(1.85, 0.008, depth - 0.35), a + Vector3(0.35, 0.008, depth - 0.35),
			rug_color.darkened(0.15), a + Vector3(1.1, -1.0, 0.5))


## El farol colgado del poste de adelante, con su luz.
func _lantern(wood: LowPolyMesh, glow: LowPolyMesh) -> void:
	var hook := Vector3(-(canopy_width * 0.5 - 0.1) + 0.32, canopy_front_height - 0.35,
			canopy_front - 0.1)
	ShrineKit.strut(wood, Vector3(hook.x - 0.32, hook.y + 0.3, hook.z), hook + Vector3.UP * 0.3,
			0.04, wood_color)
	ShrineKit.strut(wood, hook + Vector3.UP * 0.3, hook + Vector3.UP * 0.12, 0.02, wood_color)
	wood.block(Transform3D(Basis.IDENTITY, hook + Vector3.UP * 0.1), Vector3(0.2, 0.04, 0.2),
			wood_color.darkened(0.3))
	wood.block(Transform3D(Basis.IDENTITY, hook - Vector3.UP * 0.12), Vector3(0.2, 0.04, 0.2),
			wood_color.darkened(0.3))
	glow.block(Transform3D(Basis.IDENTITY, hook), Vector3(0.14, 0.2, 0.14), lantern_color)


## El sombrero del vendedor, sobre la cabeza de la figura.
func _hat(wood: LowPolyMesh) -> void:
	var figure := get_parent().get_node_or_null("Figure") as MeshInstance3D
	var capsule := figure.mesh as CapsuleMesh if figure != null else null
	if capsule == null:
		return
	var crown := figure.position + Vector3.UP * (capsule.height * 0.5 - 0.06)
	ShrineKit.annulus(wood, crown, capsule.radius * 0.5, capsule.radius * 1.4, 10, hat_color)
	var low := wood.ring(crown, capsule.radius * 0.72, 8)
	var high := wood.ring(crown + Vector3.UP * 0.28, capsule.radius * 0.42, 8)
	wood.band(low, high, hat_color)
	wood.cap(high, hat_color, crown)
