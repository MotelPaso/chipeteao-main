class_name LobsterEntranceShot
extends Node
## Un PLANO de la cinemática de la Langosta Azul (los hijos Shot del nodo
## Camera de LobsterEntrance.tscn, en orden). Cada plano entra de golpe en su
## segundo (at_seconds, del reloj de su acto) y dura hasta el siguiente. Dice
## a quién encuadra, dónde se para la cámara, cómo se mueve mientras dura y
## qué pasa en la escena cuando entra.
## Los valores de cada plano se editan en su nodo de la escena.

## En qué acto va: el rapto en el mapa (sin canción) o el fondo del mar (cada
## plano entra en un golpe de la canción).
enum Act { ABDUCTION, SEABED }
## A quién encuadra: a la langosta, al equipo o al centro de la arena.
enum Subject { BOSS, PARTY, ARENA }
## Qué mira de la langosta: la cara, la pinza grande, el lomo o la cola.
enum Focus { FACE, CLAW, BODY, TAIL }

@export_group("Cuándo")
## Acto al que pertenece el plano.
@export var act: Act = Act.SEABED
## Segundo de su acto en que entra el plano (en el fondo del mar, un golpe de la canción).
@export var at_seconds: float = 0.0

@export_group("Cámara")
## A quién encuadra el plano.
@export var subject: Subject = Subject.BOSS
## Qué mira de la langosta (solo con subject = BOSS).
@export var focus: Focus = Focus.FACE
## Metros de la cámara a lo que mira. Con el equipo, se aleja lo que haga falta para que entren todos.
@export var distance: float = 3.0
## Giro de la cámara alrededor de lo que mira, en grados: 0 = de frente, 90 = desde su izquierda, 180 = desde atrás. El frente del equipo es hacia donde mira (en la arena, hacia el jefe); el de la arena, hacia donde aterriza el equipo.
@export var around_degrees: float = 0.0
## Altura de la cámara sobre lo que mira, en metros (negativo = desde abajo).
@export var height: float = 0.0
## Metros que sube (o baja) el punto al que apunta la cámara.
@export var look_lift: float = 0.0
## Apertura de la cámara, en grados (menos = más teleobjetivo).
@export var fov: float = 40.0
## Metros que la cámara se acerca de a poco mientras dura el plano.
@export var push_in: float = 0.0
## Metros que la cámara sube (positivo) o baja (negativo) mientras dura el plano.
@export var rise: float = 0.0
## Grados que la cámara gira alrededor de lo que mira mientras dura el plano.
@export var orbit_degrees: float = 0.0
## Grados que la cámara queda ladeada.
@export var roll_degrees: float = 0.0
## Solo con la langosta: sola contra el fondo oscuro (encendido) o en el mundo (apagado).
@export var isolated: bool = false
## Temblor de cámara (0-1) en el golpe con que entra el plano.
@export_range(0.0, 1.0) var hit_shake: float = 0.0

@export_group("La escena")
## Lo que pasa en la escena cuando entra el plano: "bury" (la langosta espera enterrada bajo su montículo), "erupt" (sale de la arena de golpe), "land" (el equipo toca fondo); vacío = nada.
@export var event: StringName = &""
## Pose que toma la langosta en este plano: un nombre de LobsterRig.Pose en mayúsculas (vacío = sigue como estaba).
@export var pose: StringName = &""
## Gesto que hace la langosta al entrar el plano (ver LobsterGestures; vacío = ninguno).
@export var gesture: StringName = &""
## Sonido al entrar el plano (fila de Sfx.SOUND_LIBRARY; vacío = ninguno).
@export var sfx: StringName = &""
