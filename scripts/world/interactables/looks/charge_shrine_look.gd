class_name ChargeShrineLook
extends Node3D
## Cómo se ve el altar de carga: un zócalo de piedra escalonado, una columna
## con capitel, una cuna de bronce donde flota el cristal (que el altar hace
## girar y latir) y un círculo de piedras con runas que marca el borde de la
## zona donde se carga. Va como hijo de Visual en ChargeShrine.tscn; el
## anillo y el disco de progreso siguen siendo del altar.
##
## Las piedras del círculo se apoyan cada una en el suelo de su lugar, así
## que se arman cuando el altar ya está en su sitio. No tienen colisión.

@export_group("Zócalo y columna")
## Radio del escalón de abajo del zócalo, en metros (igual a la colisión del altar).
@export var plinth_radius: float = 1.5
## Escalones del zócalo.
@export_range(1, 4) var plinth_tiers: int = 3
## Alto de cada escalón del zócalo, en metros.
@export var plinth_step: float = 0.32
## Alto de la columna, en metros.
@export var column_height: float = 2.0
## Radio de la columna, en metros.
@export var column_radius: float = 0.5
## Brazos de bronce de la cuna del cristal.
@export_range(2, 8) var prongs: int = 4

@export_group("Cristal")
## Alto del cristal que flota, en metros.
@export var crystal_height: float = 1.4
## Radio del cristal que flota, en metros.
@export var crystal_radius: float = 0.36

@export_group("Círculo de piedras")
## Piedras con runa alrededor de la zona (0 = ninguna).
@export_range(0, 16) var marker_count: int = 8
## Metros más allá del borde de la zona donde se paran.
@export var marker_gap: float = 0.8
## Alto mínimo de cada piedra, en metros.
@export var marker_height_min: float = 1.2
## Alto máximo de cada piedra, en metros.
@export var marker_height_max: float = 1.7
## Ancho de cada piedra, en metros.
@export var marker_width: float = 0.7

@export_group("Colores")
## Piedra del zócalo, la columna y las piedras del círculo.
@export var stone_color: Color = Color(0.6, 0.6, 0.58)
## Cara de arriba de los escalones.
@export var top_color: Color = Color(0.7, 0.69, 0.64)
## Basa y capitel de la columna.
@export var trim_color: Color = Color(0.78, 0.75, 0.68)
## Musgo.
@export var moss_color: Color = Color(0.36, 0.5, 0.3)
## Bronce de la cuna.
@export var bronze_color: Color = Color(0.62, 0.45, 0.22)
## Cristal y runas.
@export var glow_color: Color = Color(0.45, 0.93, 1.0)

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_restyle_crystal()
	_build.call_deferred()


## El cristal del altar pasa a ser uno facetado que brilla y sube hasta la
## cuna. Va en _ready y no después: el altar lee la altura del cristal en el
## suyo, que corre después del de este nodo.
func _restyle_crystal() -> void:
	var crystal := get_parent().get_node_or_null("Crystal") as MeshInstance3D
	if crystal == null:
		return
	crystal.position.y = plinth_step * float(plinth_tiers) + column_height + crystal_height * 0.5
	var mesh := LowPolyMesh.new(5)
	ShrineKit.crystal(mesh, Vector3.ZERO, crystal_height, crystal_radius, glow_color, 6)
	crystal.mesh = mesh.commit()
	crystal.material_override = ShrineKit.glow_material()
	crystal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build() -> void:
	_rng.seed = hash(Vector3i(roundi(global_position.x * 10.0), 21, roundi(global_position.z * 10.0)))
	var stone := LowPolyMesh.new(int(_rng.seed))
	var glow := LowPolyMesh.new(int(_rng.seed) + 1)
	var top := ShrineKit.plinth(stone, Vector3.ZERO, plinth_radius, plinth_tiers, plinth_step,
			0.8, 8, stone_color, top_color, PI / 8.0)
	var crown := ShrineKit.column(stone, Vector3.UP * top, column_height, column_radius, 8,
			stone_color, trim_color, PI / 8.0)
	_cradle(stone, crown)
	for index in 3:
		var angle := _rng.randf() * TAU
		ShrineKit.crystal(glow, Vector3(cos(angle), 0.0, sin(angle)) * plinth_radius * 0.9
				+ Vector3.UP * (plinth_step + 0.12), 0.45, 0.1, glow_color, 5, _rng.randf())
	var spots := PackedVector3Array()
	for index in 5:
		var angle := _rng.randf() * TAU
		spots.append(Vector3(cos(angle), 0.0, sin(angle)) * plinth_radius * 0.92
				+ Vector3.UP * plinth_step)
	ShrineKit.moss(stone, spots, 0.3, moss_color, _rng)
	_markers(stone, glow)
	ShrineKit.hang(self, stone, glow)


## Los brazos de bronce que salen del capitel y rodean la mitad de abajo del cristal.
func _cradle(stone: LowPolyMesh, crown: Vector3) -> void:
	var crystal := get_parent().get_node_or_null("Crystal") as Node3D
	var heart := crystal.position.y if crystal != null else crown.y + 0.9
	for index in prongs:
		var out := Vector3.FORWARD.rotated(Vector3.UP, TAU * float(index) / float(prongs) + PI / 4.0)
		var foot := crown + out * column_radius * 1.2
		var elbow := Vector3(0.0, (crown.y + heart) * 0.5, 0.0) + out * (crystal_radius + 0.35)
		var tip := Vector3(0.0, heart + 0.05, 0.0) + out * (crystal_radius + 0.08)
		ShrineKit.strut(stone, foot, elbow, 0.09, bronze_color)
		ShrineKit.strut(stone, elbow, tip, 0.07, bronze_color)


## El círculo de piedras con runa, justo afuera de la zona de carga.
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
				_rng.randf_range(marker_height_min, marker_height_max), marker_width, stone_color,
				moss_color, glow_color, _rng)
