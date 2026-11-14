class_name MythosFireRing
extends MultiMeshInstance3D
## El anillo de fuego que Mythos deja en el suelo al dar la vuelta en su
## cinemática de llegada (nodo Ring, bajo Entrance, en MythosCinematic.tscn).
## Son tramos de llama (el mismo muro de las ondas de fuego,
## fire_wall.gdshader) puestos en círculo sobre el relieve: cada tramo crece
## cuando el fénix le pasa por encima. Es solo un efecto: no quema a nadie.

@export_group("Aspecto")
## Tramos de llama del anillo.
@export var segments: int = 110
## Alto de las llamas, en metros.
@export var wall_height: float = 6.0
## Cuánto se pisan dos tramos vecinos (1 = se tocan justo).
@export var segment_overlap: float = 1.25
## Segundos que tarda cada tramo en crecer del todo.
@export var grow_seconds: float = 0.45
## Segundos que tarda el anillo entero en apagarse.
@export var fade_seconds: float = 1.3

var _radius: float = 0.0
## De cada tramo: su base (en el espacio de este nodo) y su lado de afuera.
var _bases: Array[Vector3] = []
var _outwards: Array[Vector3] = []


func _ready() -> void:
	# Copia propia del MultiMesh de la escena (que trae la malla del tramo),
	# con la cantidad de tramos de aquí.
	var own := multimesh.duplicate() as MultiMesh
	own.instance_count = maxi(segments, 3)
	# El anillo llega lejos de su centro: una caja fija evita que se recorte.
	own.custom_aabb = AABB(Vector3(-90.0, -12.0, -90.0), Vector3(180.0, 40.0, 180.0))
	multimesh = own
	visible = false


## Tiende el anillo, todavía sin llamas: centro `center` y radio `radius`. El
## primer tramo queda a la izquierda de `toward` (visto desde ahí) y los
## siguientes avanzan hacia `toward`, igual que el fénix.
func lay(center: Vector3, radius: float, toward: Vector3) -> void:
	_radius = radius
	global_transform = Transform3D(Basis.IDENTITY, center)
	var right := Vector3.UP.cross(toward).normalized()
	var terrain := Terrain.find(get_tree())
	var count := multimesh.instance_count
	_bases.clear()
	_outwards.clear()
	for index: int in count:
		var turn := TAU * float(index) / float(count)
		var outward := toward * sin(turn) - right * cos(turn)
		var at := outward * radius
		if terrain != null:
			at.y = terrain.height_at(center.x + at.x, center.z + at.z) - center.y
		_bases.append(at)
		_outwards.append(outward)
	draw(0.0, 1.0)
	fade_out(0.0)
	visible = true


## Dibuja el anillo con `laps` vueltas ya dadas por el fénix (1 = entero);
## `lap_seconds` es lo que tarda en dar una.
func draw(laps: float, lap_seconds: float) -> void:
	var count := _bases.size()
	var width := TAU * _radius / float(maxi(count, 1)) * segment_overlap
	for index: int in count:
		var since := (laps - float(index) / float(count)) * lap_seconds
		var grown := clampf(since / maxf(grow_seconds, 0.01), 0.0, 1.0)
		# Crece rápido al principio y se asienta.
		var height := maxf(wall_height * (1.0 - pow(1.0 - grown, 2.0)), 0.001)
		var outward := _outwards[index]
		var tangent := Vector3(-outward.z, 0.0, outward.x)
		multimesh.set_instance_transform(index, Transform3D(
				Basis(tangent * width, Vector3.UP * height, outward),
				_bases[index] + Vector3.UP * height * 0.5))


## Lo apaga de a poco: `seconds` son los que lleva apagándose (0 o menos =
## encendido del todo).
func fade_out(seconds: float) -> void:
	set_instance_shader_parameter(&"fade",
			1.0 - clampf(seconds / maxf(fade_seconds, 0.01), 0.0, 1.0))


## Lo quita de la vista.
func clear() -> void:
	visible = false
