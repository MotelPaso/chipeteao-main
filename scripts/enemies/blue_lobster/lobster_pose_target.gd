class_name LobsterPoseTarget
extends RefCounted
## Lo que una pose le pide al rig de la Langosta Azul (LobsterRig). El rig
## guarda dos: lo que pide la pose de ahora y los valores actuales, que la
## persiguen. LobsterPoses rellena el primero.
## Ángulos en grados; `height` en unidades del modelo; `fan` y `tuck` de 0 a 1.

## Los campos que se mezclan, por nombre.
const FIELDS: Array[StringName] = [
	&"height", &"pitch", &"roll", &"yaw",
	&"raise_left", &"raise_right", &"spread_left", &"spread_right",
	&"elbow_left", &"elbow_right", &"wrist_left", &"wrist_right",
	&"claw_left", &"claw_right",
	&"tail_curl", &"tail_yaw", &"fan", &"antenna", &"maw", &"tuck",
]

## Altura del centro del tórax sobre el suelo.
var height: float = 0.78
## Inclinación del tórax (positivo = cabeza arriba), ladeo y giro de todo el
## cuerpo sobre sí mismo (positivo = hacia su izquierda).
var pitch: float = 0.0
var roll: float = 0.0
var yaw: float = 0.0
## Cada brazo: cuánto se levanta, cuánto se abre hacia afuera, cuánto dobla
## el codo hacia adentro (negativo = lo estira) y cuánto levanta la muñeca.
var raise_left: float = 0.0
var raise_right: float = 0.0
var spread_left: float = 0.0
var spread_right: float = 0.0
var elbow_left: float = 0.0
var elbow_right: float = 0.0
var wrist_left: float = 0.0
var wrist_right: float = 0.0
## Cuánto abre cada pinza.
var claw_left: float = 0.0
var claw_right: float = 0.0
## Cola: grados que cada segmento se enrosca hacia abajo (negativo = la
## levanta) y hacia un lado; y cuánto abre el abanico (0-1).
var tail_curl: float = 0.0
var tail_yaw: float = 0.0
var fan: float = 0.3
## Grados que las antenas se echan hacia atrás.
var antenna: float = 0.0
## Grados que abre la boca.
var maw: float = 0.0
## Cuánto recoge las patas en vez de apoyarlas (0 = apoyadas, 1 = recogidas).
var tuck: float = 0.0


## Vuelve todos los campos a cero (la pose los rellena después).
func reset() -> void:
	for field: StringName in FIELDS:
		set(field, 0.0)


## Acerca cada campo al de `target`; `weight` (0-1) es cuánto en este frame.
func blend_toward(target: LobsterPoseTarget, weight: float) -> void:
	for field: StringName in FIELDS:
		set(field, lerpf(float(get(field)), float(target.get(field)), weight))


## Copia todos los campos de `source`.
func copy_from(source: LobsterPoseTarget) -> void:
	for field: StringName in FIELDS:
		set(field, source.get(field))


## Pone los dos brazos iguales: levantados `raise`, abiertos `spread`, con el
## codo en `elbow` y las pinzas abiertas `claw`.
func set_arms(raise: float, spread: float, elbow: float, claw: float) -> void:
	raise_left = raise
	raise_right = raise
	spread_left = spread
	spread_right = spread
	elbow_left = elbow
	elbow_right = elbow
	claw_left = claw
	claw_right = claw


## Pone UN brazo (`left` o el derecho) y deja el otro como estaba.
func set_arm(left: bool, raise: float, spread: float, elbow: float, claw: float) -> void:
	if left:
		raise_left = raise
		spread_left = spread
		elbow_left = elbow
		claw_left = claw
	else:
		raise_right = raise
		spread_right = spread
		elbow_right = elbow
		claw_right = claw
