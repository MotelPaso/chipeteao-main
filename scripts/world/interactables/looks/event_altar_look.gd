class_name EventAltarLook
extends Node3D
## Cómo se ve el altar de eventos: un zócalo cuadrado de dos escalones, un
## bloque de altar con runas doradas en sus cuatro caras, tres garras de
## bronce que sostienen el orbe (que el altar tiñe y hace latir) y velas en
## las esquinas. Va como hijo de Visual en EventAltar.tscn; el orbe (Glass)
## y la luz siguen siendo del altar. No tiene colisión, igual que antes.

@export_group("Medidas")
## Medio lado del escalón de abajo, en metros.
@export var base_half: float = 1.0
## Alto de cada escalón, en metros.
@export var step: float = 0.2
## Medio lado y alto del bloque del altar, en metros.
@export var block_half: float = 0.45
@export var block_height: float = 0.58
## Garras de bronce alrededor del orbe.
@export_range(2, 6) var claws: int = 3
## Velas en cada esquina.
@export_range(0, 6) var candles_per_corner: int = 3

@export_group("Colores")
## Piedra del zócalo y del bloque.
@export var stone_color: Color = Color(0.58, 0.57, 0.55)
## Cara de arriba de los escalones y losa del altar.
@export var top_color: Color = Color(0.72, 0.7, 0.65)
## Bronce de las garras.
@export var bronze_color: Color = Color(0.62, 0.45, 0.22)
## Runas talladas.
@export var rune_color: Color = Color(1.0, 0.8, 0.35)
## Cera y llama de las velas.
@export var wax_color: Color = Color(0.92, 0.88, 0.76)
@export var flame_color: Color = Color(1.0, 0.7, 0.3)
## Musgo.
@export var moss_color: Color = Color(0.36, 0.5, 0.3)

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_build.call_deferred()


func _build() -> void:
	_rng.seed = hash(Vector3i(roundi(global_position.x * 10.0), 25, roundi(global_position.z * 10.0)))
	var stone := LowPolyMesh.new(int(_rng.seed))
	var glow := LowPolyMesh.new(int(_rng.seed) + 1)
	var top := ShrineKit.plinth(stone, Vector3.ZERO, base_half * sqrt(2.0), 2, step, 0.8, 4,
			stone_color, top_color, PI / 4.0)
	stone.block(Transform3D(Basis.IDENTITY, Vector3.UP * (top + block_height * 0.5)),
			Vector3(block_half * 2.0, block_height, block_half * 2.0), stone_color)
	var slab := top + block_height
	stone.block(Transform3D(Basis.IDENTITY, Vector3.UP * (slab + 0.06)),
			Vector3(block_half * 2.5, 0.12, block_half * 2.5), top_color)
	for face in 4:
		var out := Vector3.FORWARD.rotated(Vector3.UP, PI * 0.5 * float(face))
		ShrineKit.glyph(glow, out * (block_half + 0.02) + Vector3.UP * (top + block_height * 0.5),
				out, Vector3.UP, block_height * 0.62, rune_color)
	_claws(stone, slab + 0.12)
	for corner in 4:
		var spot := Vector3(1, 0, 1).rotated(Vector3.UP, PI * 0.5 * float(corner)) * base_half * 0.82
		ShrineKit.candles(stone, glow, spot + Vector3.UP * step, candles_per_corner, 0.14, wax_color,
				flame_color, _rng)
	var spots := PackedVector3Array()
	for index in 4:
		spots.append(Vector3(1, 0, 0).rotated(Vector3.UP, _rng.randf() * TAU) * base_half * 0.95
				+ Vector3.UP * step)
	ShrineKit.moss(stone, spots, 0.25, moss_color, _rng)
	ShrineKit.hang(self, stone, glow)


## Las garras: salen de la losa, abrazan el orbe por fuera y se cierran arriba.
func _claws(stone: LowPolyMesh, slab: float) -> void:
	var orb := get_parent().get_node_or_null("Glass") as MeshInstance3D
	var heart := orb.position.y if orb != null else slab + 0.45
	var sphere := orb.mesh as SphereMesh if orb != null else null
	var reach := sphere.radius if sphere != null else 0.45
	for index in claws:
		var out := Vector3.FORWARD.rotated(Vector3.UP, TAU * float(index) / float(claws))
		var foot := Vector3(0.0, slab, 0.0) + out * reach * 0.55
		var waist := Vector3(0.0, heart, 0.0) + out * (reach + 0.12)
		var tip := Vector3(0.0, heart + reach * 0.75, 0.0) + out * reach * 0.55
		ShrineKit.strut(stone, foot, waist, 0.08, bronze_color)
		ShrineKit.strut(stone, waist, tip, 0.06, bronze_color)
