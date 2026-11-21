class_name LobsterEntranceShot
extends Node
## Un PLANO de la entrada de la Langosta Azul (los hijos Shot del nodo Camera
## de LobsterEntrance.tscn, en orden). Cada plano entra de golpe en un golpe de
## la canción (at_seconds) y dura hasta el siguiente. Dice dónde se para la
## cámara respecto de la langosta, qué mira y qué hace ella mientras tanto.
## Los valores de cada plano se editan en su nodo de la escena.

## Qué mira la cámara: la cara, la pinza grande, el lomo o la cola.
enum Focus { FACE, CLAW, BODY, TAIL }

@export_group("Cuándo")
## Segundo de la canción en que entra este plano (uno de sus golpes).
@export var at_seconds: float = 0.0

@export_group("Cámara")
## Qué mira la cámara.
@export var focus: Focus = Focus.FACE
## Metros de la cámara a lo que mira.
@export var distance: float = 3.0
## Giro de la cámara alrededor de la langosta, en grados: 0 = de frente, 90 = desde su izquierda, 180 = desde atrás.
@export var around_degrees: float = 0.0
## Altura de la cámara sobre lo que mira, en metros (negativo = desde abajo).
@export var height: float = 0.0
## Metros que sube (o baja) el punto al que apunta la cámara.
@export var look_lift: float = 0.0
## Apertura de la cámara, en grados (menos = más teleobjetivo).
@export var fov: float = 40.0
## Metros que la cámara se acerca de a poco mientras dura el plano.
@export var push_in: float = 0.0
## Grados que la cámara queda ladeada.
@export var roll_degrees: float = 0.0
## Sola contra el fondo oscuro (encendido) o en el mundo, con la horda congelada (apagado).
@export var isolated: bool = true
## Temblor de cámara (0-1) en el golpe con que entra el plano.
@export_range(0.0, 1.0) var hit_shake: float = 0.0

@export_group("La langosta")
## Pose que toma en este plano: un nombre de LobsterRig.Pose en mayúsculas (vacío = sigue como estaba).
@export var pose: StringName = &""
## Gesto que hace al entrar el plano (ver LobsterGestures; vacío = ninguno).
@export var gesture: StringName = &""
## Sonido de la langosta al entrar el plano (fila de Sfx.SOUND_LIBRARY; vacío = ninguno).
@export var sfx: StringName = &""
