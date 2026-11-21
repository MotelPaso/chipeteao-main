class_name GreedShrineLook
extends Node3D
## Cómo se ve el altar de la codicia: un altar de piedra negra con borde de
## oro sobre un escalón, una calavera con cuernos dorados y ojos rojos que
## brillan, montones de monedas arriba y al pie, gemas, una runa de oro al
## frente y dos candelabros altos. Va como hijo de Visual en
## GreedShrine.tscn; la luz sigue siendo del altar.

@export_group("Medidas")
## Medio ancho, alto y medio fondo del bloque del altar, en metros (la
## colisión del altar es un poco más grande).
@export var block_half: Vector3 = Vector3(0.9, 0.8, 0.6)
## Alto de los candelabros, en metros.
@export var candelabra_height: float = 1.5
## Montones de monedas al pie del altar.
@export_range(0, 6) var ground_piles: int = 3

@export_group("Colores")
## Piedra negra del altar.
@export var stone_color: Color = Color(0.15, 0.13, 0.15)
## Escalón.
@export var step_color: Color = Color(0.24, 0.22, 0.23)
## Oro del borde, los cuernos y las monedas.
@export var gold_color: Color = Color(0.96, 0.74, 0.22)
## Hueso de la calavera.
@export var bone_color: Color = Color(0.88, 0.85, 0.74)
## Ojos de la calavera.
@export var eye_color: Color = Color(1.0, 0.2, 0.12)
## Gemas entre las monedas.
@export var gem_colors: Array[Color] = [Color(0.95, 0.15, 0.3), Color(0.2, 0.95, 0.5),
		Color(0.3, 0.6, 1.0)]
## Color del hierro de los candelabros.
@export var iron_color: Color = Color(0.14, 0.13, 0.14)
## Color de la cera de las velas de los candelabros.
@export var wax_color: Color = Color(0.9, 0.85, 0.72)
## Color de la llama de las velas de los candelabros.
@export var flame_color: Color = Color(1.0, 0.62, 0.22)

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_build.call_deferred()


func _build() -> void:
	_rng.seed = hash(Vector3i(roundi(global_position.x * 10.0), 27, roundi(global_position.z * 10.0)))
	var stone := LowPolyMesh.new(int(_rng.seed))
	var glow := LowPolyMesh.new(int(_rng.seed) + 1)
	stone.block(Transform3D(Basis.IDENTITY, Vector3.UP * 0.02),
			Vector3(block_half.x * 2.8, 0.34, block_half.z * 3.0), step_color)
	var low := 0.19
	stone.block(Transform3D(Basis.IDENTITY, Vector3.UP * (low + block_half.y * 0.5)),
			Vector3(block_half.x * 2.0, block_half.y, block_half.z * 2.0), stone_color)
	var top := low + block_half.y
	stone.block(Transform3D(Basis.IDENTITY, Vector3.UP * (top + 0.07)),
			Vector3(block_half.x * 2.2, 0.14, block_half.z * 2.25), gold_color.darkened(0.15))
	top += 0.14
	ShrineKit.glyph(glow, Vector3(0.0, low + block_half.y * 0.5, block_half.z + 0.02), Vector3.BACK,
			Vector3.UP, block_half.y * 0.7, gold_color)
	ShrineKit.skull(stone, glow, Vector3(0.0, top + 0.24, 0.05), Vector3.BACK, 0.48, bone_color,
			eye_color)
	for turn: float in [-1.0, 1.0]:
		var root := Vector3(turn * 0.17, top + 0.38, 0.0)
		var bend := root + Vector3(turn * 0.2, 0.18, -0.05)
		ShrineKit.strut(stone, root, bend, 0.07, gold_color)
		ShrineKit.strut(stone, bend, bend + Vector3(turn * 0.05, 0.22, -0.1), 0.05, gold_color)
	for turn: float in [-1.0, 1.0]:
		var pile := Vector3(turn * block_half.x * 0.62, top, 0.08)
		ShrineKit.coins(stone, pile, 0.22, 4, gold_color, _rng)
		ShrineKit.crystal(glow, pile + Vector3.UP * 0.12, 0.2, 0.06,
				gem_colors[_rng.randi() % gem_colors.size()], 5, _rng.randf())
	for index in ground_piles:
		# Al pie del escalón, en el suelo.
		var spot := Vector3(_rng.randf_range(-1.3, 1.3), 0.0,
				block_half.z * 1.5 + _rng.randf_range(0.2, 0.5))
		ShrineKit.coins(stone, spot, _rng.randf_range(0.18, 0.3), 5, gold_color, _rng)
	for turn: float in [-1.0, 1.0]:
		_candelabra(stone, glow, Vector3(turn * (block_half.x * 1.4 + 0.2), 0.0, -block_half.z * 0.4))
	ShrineKit.hang(self, stone, glow)


## Un candelabro de hierro con tres velas.
func _candelabra(stone: LowPolyMesh, glow: LowPolyMesh, foot: Vector3) -> void:
	var top := foot + Vector3.UP * candelabra_height
	ShrineKit.strut(stone, foot, top, 0.07, iron_color)
	stone.block(Transform3D(Basis.IDENTITY, foot + Vector3.UP * 0.04), Vector3(0.36, 0.08, 0.36),
			iron_color)
	ShrineKit.strut(stone, top + Vector3(-0.28, 0.0, 0.0), top + Vector3(0.28, 0.0, 0.0), 0.05,
			iron_color)
	for offset: float in [-0.28, 0.0, 0.28]:
		var holder := top + Vector3(offset, 0.03 if offset != 0.0 else 0.1, 0.0)
		var tall := 0.22 if offset != 0.0 else 0.3
		var low_ring := stone.ring(holder, 0.05, 6)
		var high_ring := stone.ring(holder + Vector3.UP * tall, 0.05, 6)
		stone.band(low_ring, high_ring, wax_color)
		stone.cap(high_ring, wax_color.lightened(0.1), holder)
		glow.blob(holder + Vector3.UP * (tall + 0.08), Vector3(0.05, 0.1, 0.05), flame_color, 4, 3,
				0.1)
