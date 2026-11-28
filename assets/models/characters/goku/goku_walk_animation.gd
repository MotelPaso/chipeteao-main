extends Node3D
## Animación procedural de caminata (brazos, piernas y torso) para Goku.
##
## El .glb trae esqueleto pero ninguna animación y está en T-pose. Este script
## baja los brazos a una pose relajada (también cuando está quieto) y, cuando el
## personaje se mueve, hace un ciclo de caminata moviendo los huesos directamente.
##
## Uso: adjuntar a la raíz de la escena (GokuCharacter). No hace falta llamar nada:
## detecta solo si el personaje se mueve (por la posición global de este nodo).

@export_group("Modelo")
## Ruta al nodo que contiene el .glb instanciado.
@export var model_path: NodePath = ^"Goku"

@export_group("Movimiento")
## Calcula la velocidad a partir de cuánto se desplaza este nodo.
## Si lo desactivas, llama a set_move_speed(velocidad) tú mismo.
@export var auto_detect_motion := true
## Velocidad (m/s) a la que el balanceo llega al máximo.
@export var full_swing_speed := 5.0
## Metros recorridos en un ciclo completo de paso (pie izquierdo + derecho).
@export var stride_length := 1.5
## Tope de ciclos por segundo, para que a mucha velocidad no se vea frenético.
@export var max_cycle_hz := 2.6
## Por debajo de esta velocidad (m/s) se considera que está quieto.
@export var idle_threshold := 0.1

@export_group("Piernas (grados)")
@export_range(0.0, 50.0) var leg_swing := 22.0
## Flexión máxima de la rodilla cuando la pierna pasa hacia adelante.
@export_range(0.0, 90.0) var knee_bend := 42.0
## Cabeceo del pie: punta arriba al apoyar el talón, punta abajo al despegar.
@export_range(0.0, 40.0) var foot_pitch := 12.0
## Separación lateral de cada pierna respecto a la vertical.
@export_range(0.0, 20.0) var stance_spread := 3.0

@export_group("Brazos (grados)")
@export_range(0.0, 60.0) var arm_swing := 26.0
## Cuánto se separa el brazo del cuerpo (0 = pegado al costado).
@export_range(0.0, 40.0) var arm_hang_out := 9.0
@export_range(0.0, 60.0) var elbow_bend_rest := 10.0
## Flexión extra del codo cuando el brazo va hacia adelante.
@export_range(0.0, 90.0) var elbow_bend_swing := 30.0

@export_group("Torso (grados)")
@export_range(0.0, 20.0) var torso_twist := 7.0
@export_range(0.0, 20.0) var pelvis_twist := 4.0
@export_range(0.0, 15.0) var lean_forward := 3.0
## Ajusta la altura del cuerpo para que el pie más bajo siempre toque el suelo.
@export var ground_feet := true

@export_group("Suavizado")
## Qué tan rápido arranca / frena la animación.
@export var blend_speed := 8.0

const MAX_DETECT_SPEED := 40.0   # por encima de esto asumimos teletransporte

# Huesos (nombres del .glb). "Izquierda" = lado +X del modelo, que mira hacia +Z.
const B_PELVIS := "bone_002_66"
const B_SPINE := "bone_016_65"
const B_THIGH_L := "bone_013_19"
const B_SHANK_L := "bone_014_18"
const B_FOOT_L := "bone_015_17"
const B_THIGH_R := "bone_009_15"
const B_SHANK_R := "bone_010_14"
const B_FOOT_R := "bone_011_13"
const B_UARM_L := "bone_033_47"
const B_FARM_L := "bone_034_46"
const B_HAND_L := "bone_035_45"
const B_UARM_R := "bone_019_33"
const B_FARM_R := "bone_020_32"
const B_HAND_R := "bone_021_31"

var _model: Node3D
var _model_base_y := 0.0
var _skel: Skeleton3D

var _pelvis := -1
var _spine := -1
var _thigh_l := -1
var _shank_l := -1
var _foot_l := -1
var _thigh_r := -1
var _shank_r := -1
var _foot_r := -1
var _uarm_l := -1
var _farm_l := -1
var _uarm_r := -1
var _farm_r := -1

var _rest_basis := {}        # hueso -> orientación global de reposo (Basis)
var _rest_ankle_y := 0.0

var _phase := 0.0
var _speed := 0.0
var _amp := 0.0
var _measured := 0.0
var _external := 0.0
var _last_pos := Vector3.ZERO
var _ready_ok := false
## CharacterBody3D del jugador (si lo hay): su velocity real es la fuente de
## verdad, igual que en storm_cat_walk.gd. Sin cuerpo (preview del selector)
## se cae al desplazamiento del nodo.
var _body: CharacterBody3D = null


## Para usar con auto_detect_motion = false (p. ej. pasando velocity.length()).
func set_move_speed(speed: float) -> void:
	_external = maxf(speed, 0.0)


func _ready() -> void:
	_model = get_node_or_null(model_path) as Node3D
	if _model == null:
		push_error("GokuWalkAnimator: no encuentro el modelo en '%s'." % model_path)
		return
	var found := _model.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		push_error("GokuWalkAnimator: el modelo no tiene Skeleton3D.")
		return
	_skel = found[0] as Skeleton3D
	if not _setup_bones():
		return
	_model_base_y = _model.position.y
	_last_pos = global_position
	var ancestor := get_parent()
	while ancestor != null and ancestor is not CharacterBody3D:
		ancestor = ancestor.get_parent()
	_body = ancestor as CharacterBody3D
	_ready_ok = true
	_apply_pose(0.0)   # pose relajada desde el primer frame


func _physics_process(delta: float) -> void:
	# La velocidad se mide en el tick de física (donde normalmente se mueve el
	# personaje); medirla en _process daría 0 en los frames sin tick de física.
	if not _ready_ok or not auto_detect_motion:
		return
	if _body != null:
		_measured = 0.0
		if _body.is_on_floor():
			_measured = Vector2(_body.velocity.x, _body.velocity.z).length()
		return
	var d := global_position - _last_pos
	d.y = 0.0
	_last_pos = global_position
	var s := d.length() / maxf(delta, 0.0001)
	_measured = s if s < MAX_DETECT_SPEED else 0.0


func _process(delta: float) -> void:
	if not _ready_ok:
		return

	var target_speed := _measured if auto_detect_motion else _external
	var moving := target_speed > idle_threshold

	var k := 1.0 - exp(-blend_speed * delta)
	_speed = lerpf(_speed, target_speed if moving else 0.0, k)
	var amp_target := 0.0
	if moving:
		amp_target = lerpf(0.35, 1.0, clampf(target_speed / full_swing_speed, 0.0, 1.0))
	_amp = lerpf(_amp, amp_target, k)

	var hz := minf(_speed / stride_length, max_cycle_hz)
	_phase = fmod(_phase + TAU * hz * delta, TAU)
	_apply_pose(_phase)


# ----------------------------------------------------------------------------
# Pose
# ----------------------------------------------------------------------------

## Rotación sobre X que lleva algo que apunta hacia abajo hacia ADELANTE (+Z).
func _fwd(angle: float) -> Basis:
	return Basis(Vector3.RIGHT, -angle)


func _apply_pose(phase: float) -> void:
	# Convención: con sin(phase) > 0 la pierna izquierda va adelante y la derecha atrás;
	# cada brazo va opuesto a la pierna de su mismo lado.
	var s := sin(phase)

	# Pelvis y columna (primero: los demás cuelgan de ellas).
	_pose_global(_pelvis, Basis(Vector3.UP, deg_to_rad(-pelvis_twist) * s * _amp))
	_pose_global(_spine, Basis(Vector3.UP, deg_to_rad(torso_twist) * s * _amp) \
			* Basis(Vector3.RIGHT, deg_to_rad(lean_forward) * _amp))

	_pose_leg(1.0, _thigh_l, _shank_l, _foot_l, phase)
	_pose_leg(-1.0, _thigh_r, _shank_r, _foot_r, phase + PI)
	_pose_arm(1.0, _uarm_l, _farm_l, phase + PI)
	_pose_arm(-1.0, _uarm_r, _farm_r, phase)

	if ground_feet:
		var lowest := minf(_ankle_y(_foot_l), _ankle_y(_foot_r))
		_model.position.y = _model_base_y + (_rest_ankle_y - lowest) * _model.scale.y


func _pose_leg(side: float, thigh: int, shank: int, foot: int, p: float) -> void:
	var swing := deg_to_rad(leg_swing) * _amp * sin(p)           # adelante = positivo
	var c := maxf(0.0, cos(p))                                   # > 0 mientras la pierna avanza
	var flex := deg_to_rad(4.0) + deg_to_rad(knee_bend) * _amp * c * c
	var base := _build_leg_base(side)
	_pose_global(thigh, _fwd(swing) * base)
	_pose_global(shank, _fwd(swing - flex) * base)
	# Pie con orientación propia (no hereda la de la pierna): se mantiene "plano".
	_pose_global(foot, _fwd(deg_to_rad(foot_pitch) * _amp * sin(p)))


func _pose_arm(side: float, upper: int, fore: int, p: float) -> void:
	var swing := deg_to_rad(arm_swing) * _amp * sin(p)           # adelante = positivo
	var bend := deg_to_rad(elbow_bend_rest) \
			+ deg_to_rad(elbow_bend_swing) * _amp * (0.5 + 0.5 * sin(p))
	var base: Basis = _build_arm_base(side)
	_pose_global(upper, _fwd(swing) * base)
	_pose_global(fore, _fwd(swing + bend) * base)


## Fija la orientación GLOBAL (espacio del esqueleto) de un hueso como
## `q * orientación_de_reposo`. Así los ángulos se definen en ejes del modelo
## sin importar cómo estén orientados los ejes locales de cada hueso.
func _pose_global(bone: int, q: Basis) -> void:
	var parent := _skel.get_bone_parent(bone)
	var parent_basis := Basis.IDENTITY
	if parent >= 0:
		parent_basis = _skel.get_bone_global_pose(parent).basis.orthonormalized()
	var target: Basis = q * (_rest_basis[bone] as Basis)
	var local := parent_basis.inverse() * target
	_skel.set_bone_pose_rotation(bone, local.get_rotation_quaternion())


func _ankle_y(bone: int) -> float:
	var in_model := _model.global_transform.affine_inverse() * _skel.global_transform
	return (in_model * _skel.get_bone_global_pose(bone).origin).y


# ----------------------------------------------------------------------------
# Preparación
# ----------------------------------------------------------------------------

func _setup_bones() -> bool:
	var names := {
		"_pelvis": B_PELVIS, "_spine": B_SPINE,
		"_thigh_l": B_THIGH_L, "_shank_l": B_SHANK_L, "_foot_l": B_FOOT_L,
		"_thigh_r": B_THIGH_R, "_shank_r": B_SHANK_R, "_foot_r": B_FOOT_R,
		"_uarm_l": B_UARM_L, "_farm_l": B_FARM_L,
		"_uarm_r": B_UARM_R, "_farm_r": B_FARM_R,
	}
	for field in names:
		var idx := _skel.find_bone(names[field])
		if idx < 0:
			push_error("GokuWalkAnimator: no existe el hueso '%s'." % names[field])
			return false
		set(field, idx)

	for i in _skel.get_bone_count():
		_rest_basis[i] = _skel.get_bone_global_rest(i).basis.orthonormalized()

	_rest_ankle_y = _ankle_y(_foot_l)
	_rest_ankle_y = minf(_rest_ankle_y, _ankle_y(_foot_r))
	return true


## Rotación (en ejes del modelo) que deja la pierna vertical, separada `stance_spread`.
func _build_leg_base(side: float) -> Basis:
	var thigh := _thigh_l if side > 0.0 else _thigh_r
	var shank := _shank_l if side > 0.0 else _shank_r
	var a := deg_to_rad(stance_spread)
	return _arc_base(thigh, shank, Vector3(side * sin(a), -cos(a), 0.0))


func _bone_origin(bone: int) -> Vector3:
	return _skel.get_bone_global_rest(bone).origin


## Rotación más corta que lleva la dirección from→to del reposo hacia `target`.
func _arc_base(from_bone: int, to_bone: int, target: Vector3) -> Basis:
	var rest_dir := (_bone_origin(to_bone) - _bone_origin(from_bone)).normalized()
	return Basis(Quaternion(rest_dir, target.normalized()))


func _build_arm_base(side: float) -> Basis:
	# Rotación que baja el brazo desde la T-pose. Se recalcula para que
	# arm_hang_out se pueda ajustar en vivo desde el Inspector.
	var upper := _uarm_l if side > 0.0 else _uarm_r
	var fore := _farm_l if side > 0.0 else _farm_r
	var a := deg_to_rad(arm_hang_out)
	return _arc_base(upper, fore, Vector3(side * sin(a), -cos(a), 0.0))
