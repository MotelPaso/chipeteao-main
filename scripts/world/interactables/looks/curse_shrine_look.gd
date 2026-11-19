class_name CurseShrineLook
extends Node3D
## Cómo se ve el altar maldito: un obelisco negro retorcido y roto, con
## grietas que brillan en rojo, un trozo de su punta que flota encima,
## púas de hierro que salen del zócalo, calaveras y un círculo de piedras
## oscuras con runas rojas en el borde de su zona. Va como hijo de Visual
## en CurseShrine.tscn; la luz y el disco de progreso siguen siendo del altar.
##
## Las piedras del círculo se apoyan cada una en el suelo de su lugar, así
## que se arman cuando el altar ya está en su sitio. No tienen colisión.

## Tramos del obelisco de abajo arriba.
const SEGMENTS: int = 6

@export_group("Obelisco")
## Radio del zócalo, en metros (igual a la colisión del altar).
@export var plinth_radius: float = 1.35
## Alto del obelisco sobre el zócalo, en metros.
@export var spire_height: float = 4.3
## Medio ancho del obelisco abajo, en metros.
@export var spire_base: float = 0.75
## Medio ancho del obelisco arriba, en metros.
@export var spire_top: float = 0.16
## Cuánto se retuerce de abajo arriba, en grados.
@export var twist_degrees: float = 28.0
## Púas de hierro alrededor del zócalo.
@export_range(0, 12) var spikes: int = 6
## Largo de cada púa, en metros.
@export var spike_length: float = 1.6
## Calaveras sobre el zócalo.
@export_range(0, 6) var skulls: int = 3

@export_group("Círculo de piedras")
## Piedras con runa alrededor de la zona (0 = ninguna).
@export_range(0, 16) var marker_count: int = 8
## Metros más allá del borde de la zona donde se paran.
@export var marker_gap: float = 0.6
## Alto mínimo de cada piedra, en metros.
@export var marker_height_min: float = 1.0
## Alto máximo de cada piedra, en metros.
@export var marker_height_max: float = 1.5

@export_group("Colores")
## Piedra negra del obelisco y del zócalo.
@export var stone_color: Color = Color(0.17, 0.15, 0.17)
## Cara de arriba del zócalo.
@export var top_color: Color = Color(0.25, 0.21, 0.23)
## Grietas y runas que brillan.
@export var crack_color: Color = Color(1.0, 0.26, 0.14)
## Hierro de las púas.
@export var iron_color: Color = Color(0.12, 0.11, 0.12)
## Hueso de las calaveras.
@export var bone_color: Color = Color(0.85, 0.82, 0.72)
## Musgo seco de las piedras del círculo.
@export var moss_color: Color = Color(0.3, 0.27, 0.22)

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_build.call_deferred()


func _build() -> void:
	_rng.seed = hash(Vector3i(roundi(global_position.x * 10.0), 23, roundi(global_position.z * 10.0)))
	var stone := LowPolyMesh.new(int(_rng.seed))
	var glow := LowPolyMesh.new(int(_rng.seed) + 1)
	var top := ShrineKit.plinth(stone, Vector3.ZERO, plinth_radius, 2, 0.3, 0.78, 5, stone_color,
			top_color, _rng.randf() * TAU)
	_spire(stone, glow, top)
	for index in spikes:
		var out := Vector3.FORWARD.rotated(Vector3.UP, TAU * (float(index) + 0.5) / float(spikes))
		var foot := out * plinth_radius * 0.82 + Vector3.UP * (top - 0.3)
		var tip := foot + (out * 0.55 + Vector3.UP).normalized() * spike_length
		_spike(stone, foot, tip)
	for index in skulls:
		var out := Vector3.FORWARD.rotated(Vector3.UP, TAU * float(index) / float(maxi(skulls, 1)) + 0.4)
		ShrineKit.skull(stone, glow, out * plinth_radius * 0.62 + Vector3.UP * (top + 0.12), out,
				0.3, bone_color, crack_color)
	_markers(stone, glow)
	ShrineKit.hang(self, stone, glow)


## El obelisco: cuatro caras que se afinan y se retuercen, grietas rojas en
## cada una, la punta rota y un trozo que flota encima.
func _spire(stone: LowPolyMesh, glow: LowPolyMesh, foot: float) -> void:
	var rings: Array[PackedVector3Array] = []
	for step in SEGMENTS + 1:
		var t := float(step) / float(SEGMENTS)
		var half := lerpf(spire_base, spire_top, t)
		var y := foot - 0.1 + spire_height * t
		rings.append(stone.ring(Vector3(0.0, y, 0.0), half * sqrt(2.0), 4,
				PI / 4.0 + deg_to_rad(twist_degrees) * t))
	for step in SEGMENTS:
		stone.band(rings[step], rings[step + 1], stone_color.lightened(0.04 * float(step % 2)))
	var tip := rings[SEGMENTS]
	# La punta rota: una cara inclinada en vez de la punta.
	var cut := PackedVector3Array()
	for index in 4:
		cut.append(tip[index] + Vector3.UP * (0.18 if index < 2 else -0.05))
	stone.band(tip, cut, stone_color)
	stone.cap(cut, top_color, Vector3(0.0, foot + spire_height * 0.5, 0.0))
	var shard_y := foot + spire_height + 0.75
	stone.triangle(Vector3(0.0, shard_y - 0.45, 0.0), Vector3(0.16, shard_y, 0.05),
			Vector3(-0.1, shard_y + 0.05, 0.14), stone_color, Vector3(0.0, shard_y - 0.1, 0.05))
	stone.triangle(Vector3(0.0, shard_y - 0.45, 0.0), Vector3(-0.1, shard_y + 0.05, 0.14),
			Vector3(-0.04, shard_y + 0.02, -0.17), stone_color, Vector3(0.0, shard_y - 0.1, 0.0))
	stone.triangle(Vector3(0.0, shard_y - 0.45, 0.0), Vector3(-0.04, shard_y + 0.02, -0.17),
			Vector3(0.16, shard_y, 0.05), stone_color, Vector3(0.0, shard_y - 0.1, 0.0))
	glow.cap(PackedVector3Array([Vector3(0.16, shard_y, 0.05), Vector3(-0.1, shard_y + 0.05, 0.14),
			Vector3(-0.04, shard_y + 0.02, -0.17)]), crack_color, Vector3(0.0, shard_y - 1.0, 0.0))
	# Una grieta en zigzag por cada cara, un poco afuera de la piedra.
	for face in 4:
		var points := PackedVector3Array()
		var steps := 5
		for step in steps + 1:
			var t := 0.08 + 0.8 * float(step) / float(steps)
			var row := int(t * float(SEGMENTS))
			var blend := t * float(SEGMENTS) - float(row)
			var a := rings[row][face].lerp(rings[mini(row + 1, SEGMENTS)][face], blend)
			var b := rings[row][(face + 1) % 4].lerp(rings[mini(row + 1, SEGMENTS)][(face + 1) % 4],
					blend)
			points.append(a.lerp(b, 0.5 + (0.18 if step % 2 == 0 else -0.18)))
		for index in steps:
			var a := points[index]
			var b := points[index + 1]
			var normal := (a + b) * 0.5
			normal = Vector3(normal.x, 0.0, normal.z).normalized()
			var side := (b - a).cross(normal).normalized() * 0.045
			glow.plate(a + normal * 0.03 - side, b + normal * 0.03 - side, b + normal * 0.03 + side,
					a + normal * 0.03 + side, crack_color, (a + b) * 0.5 - normal)


## Una púa de hierro: una pirámide fina de cuatro caras de `foot` a `tip`.
func _spike(stone: LowPolyMesh, foot: Vector3, tip: Vector3) -> void:
	var base := stone.ring(foot, 0.08, 4, _rng.randf() * TAU)
	for index in 4:
		stone.triangle(base[index], base[(index + 1) % 4], tip, iron_color, foot + (foot - tip) * 0.1)


## El círculo de piedras oscuras con runa roja, justo afuera de la zona.
func _markers(stone: LowPolyMesh, glow: LowPolyMesh) -> void:
	var shrine := get_parent().get_parent()
	var zone := shrine.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var cylinder := zone.shape as CylinderShape3D if zone != null else null
	if cylinder == null or marker_count <= 0:
		return
	var reach := cylinder.radius + marker_gap
	var turn := _rng.randf() * TAU
	for index in marker_count:
		var angle := turn + TAU * float(index) / float(marker_count)
		var foot := Vector3(cos(angle), 0.0, sin(angle)) * reach
		foot.y = ShrineKit.ground_offset(self, foot)
		ShrineKit.rune_stone(stone, glow, foot, Vector3(0.0, foot.y, 0.0),
				_rng.randf_range(marker_height_min, marker_height_max), 0.5, stone_color.lightened(0.08),
				moss_color, crack_color, _rng)
