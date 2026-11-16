class_name LobsterGait
extends Node
## Las ocho patas de la Langosta Azul (nodo Gait bajo Visual). Cada pata apoya
## la punta en el suelo y la deja PLANTADA en el mundo mientras el cuerpo
## avanza; cuando queda muy atrás de su lugar da un paso. Así las patas siguen
## el ritmo de la velocidad, también de costado, hacia atrás y al girar, y
## pisan el relieve. Las patas se reparten en dos tandas que pisan alternadas.
## Con la pose en el aire o bajo tierra las patas se recogen (`tuck`).
## Mueve pivotes de nombre único de BlueLobster.tscn: %LegL1-4 / %LegR1-4
## (cadera) y %KneeL1-4 / %KneeR1-4 (rodilla). El fémur y la tibia se
## extienden a lo largo de +X de su pivote.

## Una pata: sus dos pivotes, dónde apoya cuando el cuerpo está quieto (en el
## espacio del modelo) y dónde tiene la punta ahora (en el mundo).
class Leg:
	extends RefCounted
	var hip: Node3D = null
	var knee: Node3D = null
	## Dónde apoya en reposo, relativo al cuerpo (solo cuentan X y Z).
	var home: Vector3 = Vector3.ZERO
	## Giro de reposo de la cadera (hacia dónde apunta la pata recogida).
	var rest_yaw: float = 0.0
	## Tanda a la que pertenece (0 o 1): las dos tandas pisan alternadas.
	var group: int = 0
	## La punta, en el mundo; y, mientras da un paso, de dónde salió y cuánto lleva (0-1).
	var foot: Vector3 = Vector3.ZERO
	var from: Vector3 = Vector3.ZERO
	var step: float = 1.0

@export_group("Patas")
## Largo del fémur, en unidades del modelo (el del modelo armado en la escena).
@export var femur_length: float = 0.62
## Largo de la tibia, en unidades del modelo.
@export var tibia_length: float = 0.92
## Distancia de la cadera a la que apoya cada pata en reposo, en unidades del modelo.
@export var reach: float = 0.95

@export_group("Paso")
## Unidades del modelo que la punta puede quedar atrás de su lugar antes de dar un paso.
@export var step_trigger: float = 0.42
## Segundos que dura un paso cuando camina despacio.
@export var step_seconds: float = 0.16
## Segundos mínimos de un paso, por rápido que corra.
@export var min_step_seconds: float = 0.05
## Altura a la que levanta la punta en cada paso, en unidades del modelo.
@export var step_lift: float = 0.3
## Segundos que la punta se adelanta a su lugar según la velocidad del cuerpo.
@export var lead_seconds: float = 0.07
## Veces el `step_trigger` a partir de las cuales la punta salta a su lugar sin dar el paso (el cuerpo se movió de golpe).
@export var snap_factor: float = 4.0

@export_group("Recogidas")
## Grados que la cadera levanta el fémur con la pata recogida.
@export var tuck_hip_degrees: float = 62.0
## Grados que dobla la rodilla con la pata recogida.
@export var tuck_knee_degrees: float = 148.0

## Unidades del modelo que el cuerpo sube con cada pisada (lo lee el rig).
var bob: float = 0.0

var _legs: Array[Leg] = []
var _root: Node3D = null
var _thorax: Node3D = null
var _scale: float = 1.0
var _terrain: Terrain = null


## El rig lo llama una vez: `root` es el pivote que gira con el cuerpo,
## `thorax` el padre de las caderas y `model_scale` el tamaño del modelo.
func setup(root: Node3D, thorax: Node3D, model_scale: float) -> void:
	_root = root
	_thorax = thorax
	_scale = model_scale
	_terrain = Terrain.find(get_tree())
	_legs.clear()
	for side: String in ["L", "R"]:
		for number: int in range(1, 5):
			var leg := Leg.new()
			leg.hip = get_node("%%Leg%s%d" % [side, number]) as Node3D
			leg.knee = get_node("%%Knee%s%d" % [side, number]) as Node3D
			leg.rest_yaw = leg.hip.rotation.y
			var outward := Vector3(cos(leg.rest_yaw), 0.0, -sin(leg.rest_yaw))
			leg.home = Vector3(leg.hip.position.x, 0.0, leg.hip.position.z) + outward * reach
			# Tandas alternadas: L1, R2, L3, R4 pisan juntas, y las otras cuatro también.
			leg.group = (number + (0 if side == "L" else 1)) % 2
			_legs.append(leg)
	plant()


## Apoya todas las patas en su lugar ya, sin dar el paso (el cuerpo apareció
## o lo llevaron de golpe a otro sitio).
func plant() -> void:
	for leg: Leg in _legs:
		leg.foot = _home_point(leg, Vector3.ZERO)
		leg.step = 1.0


## Un frame, con el cuerpo ya ubicado en su pose. `velocity` es la velocidad
## del cuerpo en el mundo y `tuck` cuánto recoge las patas (0-1).
func tick(delta: float, velocity: Vector3, tuck: float) -> void:
	if _root == null or delta <= 0.0:
		return
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var speed := flat.length()
	var trigger := step_trigger * _scale
	# Cuanto más rápido corre, más corto el paso: las patas no se quedan atrás.
	var seconds := clampf(trigger * 2.0 / maxf(speed, 0.01), min_step_seconds, step_seconds)
	var stepping: Array[int] = [0, 0]
	for leg: Leg in _legs:
		if leg.step < 1.0:
			stepping[leg.group] += 1
	var landed := 0
	var inverse := _thorax.global_transform.affine_inverse()
	for leg: Leg in _legs:
		var home := _home_point(leg, flat * lead_seconds)
		var gap := Vector2(home.x - leg.foot.x, home.z - leg.foot.z).length()
		if leg.step >= 1.0:
			if gap > trigger * snap_factor:
				leg.foot = home
			elif gap > trigger and (stepping[1 - leg.group] == 0 or gap > trigger * 1.7):
				leg.from = leg.foot
				leg.step = 0.0
				stepping[leg.group] += 1
		if leg.step < 1.0:
			leg.step = minf(leg.step + delta / seconds, 1.0)
			leg.foot = leg.from.lerp(home, leg.step)
			leg.foot.y += sin(leg.step * PI) * step_lift * _scale
			if leg.step >= 1.0:
				landed += 1
		else:
			leg.foot.y = _ground(leg.foot)
		_pose_leg(leg, inverse * leg.foot, clampf(tuck, 0.0, 1.0))
	bob = lerpf(bob, 0.02 * float(landed), Juice.damp(18.0, delta))


## Dónde debería apoyar `leg` ahora, en el mundo: su lugar junto al cuerpo,
## adelantado `lead` y a la altura del suelo en ese punto.
func _home_point(leg: Leg, lead: Vector3) -> Vector3:
	var frame := _root.global_transform
	var at := frame.origin + frame.basis * Vector3(leg.home.x, 0.0, leg.home.z) + lead
	at.y = _ground(at)
	return at


func _ground(point: Vector3) -> float:
	if _terrain != null and is_instance_valid(_terrain):
		return _terrain.height_at(point.x, point.z)
	# Sin relieve (una escena de prueba): el suelo está a la altura del cuerpo.
	return (get_parent() as Node3D).global_position.y


## Gira la cadera y la rodilla para que la punta llegue a `target` (en el
## espacio del tórax): un triángulo de dos huesos en el plano de la pata, con
## la rodilla hacia arriba. `tuck` mezcla hacia la pata recogida.
func _pose_leg(leg: Leg, target: Vector3, tuck: float) -> void:
	var to_foot := target - leg.hip.position
	var flat := Vector2(to_foot.x, to_foot.z).length()
	var yaw := atan2(-to_foot.z, to_foot.x)
	var span := clampf(Vector2(flat, to_foot.y).length(),
			absf(femur_length - tibia_length) + 0.02, femur_length + tibia_length - 0.01)
	var down := atan2(to_foot.y, flat)
	var open := acos(clampf((femur_length * femur_length + span * span
			- tibia_length * tibia_length) / (2.0 * femur_length * span), -1.0, 1.0))
	var bend := acos(clampf((femur_length * femur_length + tibia_length * tibia_length
			- span * span) / (2.0 * femur_length * tibia_length), -1.0, 1.0))
	var hip_lift := down + open
	var knee := -(PI - bend)
	if tuck > 0.0:
		yaw = lerp_angle(yaw, leg.rest_yaw, tuck)
		hip_lift = lerpf(hip_lift, deg_to_rad(tuck_hip_degrees), tuck)
		knee = lerpf(knee, -deg_to_rad(tuck_knee_degrees), tuck)
	leg.hip.rotation = Vector3(0.0, yaw, hip_lift)
	leg.knee.rotation = Vector3(0.0, 0.0, knee)
