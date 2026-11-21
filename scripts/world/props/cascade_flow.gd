class_name CascadeFlow
extends Node3D
## La espuma que baja por una caída de agua: unos copos que recorren su
## línea una y otra vez, para que el agua se vea correr. La arma
## ReliefWaters con setup(); no tiene colisión.
##
## Ninguna escena usa este script: lo que alguien podría querer tocar está
## en las constantes de aquí arriba.

# --- edita aquí --------------------------------------------------------------
## Metros por segundo que baja la espuma.
const SPEED: float = 7.5
## Tamaño de un copo, en metros: el más chico y el más grande.
const FLAKE_MIN: float = 0.4
const FLAKE_MAX: float = 0.85
# -----------------------------------------------------------------------------

var _line := PackedVector3Array()
## Metros recorridos hasta cada punto de la línea.
var _marks := PackedFloat32Array()
var _length: float = 0.0
var _side := Vector3.ZERO
var _flakes: Array[MeshInstance3D] = []
var _travelled: float = 0.0


## Prepara `count` copos sobre `line` (de arriba abajo, en el espacio del
## padre), repartidos hasta `half_width` metros a cada lado de ella.
func setup(line: PackedVector3Array, count: int, half_width: float, material: Material) -> void:
	_line = line
	_marks = PackedFloat32Array([0.0])
	for index in range(1, line.size()):
		_marks.append(_marks[index - 1] + line[index].distance_to(line[index - 1]))
	_length = _marks[_marks.size() - 1]
	var ahead := line[line.size() - 1] - line[0]
	_side = Vector3(-ahead.z, 0.0, ahead.x).normalized() * half_width
	var shape := LowPolyMesh.new(count)
	shape.blob(Vector3.ZERO, Vector3(1.0, 0.5, 1.0), Color.WHITE, 5, 3, 0.2)
	var mesh := shape.commit()
	for index in count:
		var flake := MeshInstance3D.new()
		flake.name = "Flake%d" % (index + 1)
		flake.mesh = mesh
		flake.material_override = material
		flake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flake.scale = Vector3.ONE * lerpf(FLAKE_MIN, FLAKE_MAX, fposmod(float(index) * 0.618, 1.0))
		add_child(flake)
		_flakes.append(flake)
	set_process(_length > 0.1 and count > 0)
	_place()


func _process(delta: float) -> void:
	_travelled = fposmod(_travelled + SPEED * delta, _length)
	_place()


## Pone cada copo en su lugar de la línea: todos avanzan juntos, cada uno
## con su desfase y su corrimiento al costado.
func _place() -> void:
	if _length <= 0.1:
		return
	var count := _flakes.size()
	for index in count:
		var along := fposmod(_travelled + _length * float(index) / float(count), _length)
		var mark := 1
		while mark < _marks.size() - 1 and _marks[mark] < along:
			mark += 1
		var span := maxf(_marks[mark] - _marks[mark - 1], 0.001)
		var point := _line[mark - 1].lerp(_line[mark], (along - _marks[mark - 1]) / span)
		_flakes[index].position = point + _side * sin(float(index) * 2.4 + 0.7) * 0.8 \
				+ Vector3.UP * 0.12
