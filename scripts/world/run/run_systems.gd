extends Node3D
## Raíz de RunSystems.tscn: el bloque de la partida que no depende del
## mapa (Player, RunManager, WorldDirector, cartas, HUD, pantalla final,
## menú de pausa y niebla), con run_ended ya conectado a la pantalla final
## dentro de esta escena. Cada arena trae su propio EnemySpawner y
## AmbientBed.
##
## Run.tscn lo instancia UNA vez y sobrevive a cada cambio de etapa: por
## eso nivel, armas, tomos, objetos y puntos pasan de un mapa a otro sin
## copiar nada. No sabe qué mapa se juega: RunRoot lo publica en GameConfig.

## Radio (metros) del anillo donde aparecen los jugadores 2 a 4 en co-op,
## alrededor del punto de aparición del jugador 1.
@export var coop_spawn_radius: float = 1.8

## Con preload y no por class_name, para que las corridas headless que
## nunca construyeron la caché de clases del editor lo encuentren.
const SplitScreenView := preload("res://scripts/systems/split_screen.gd")
const PLAYER_SCENE := preload("res://scenes/player/Player.tscn")


## El bloque de la partida reinicia RunState. Entra al árbol ANTES de la
## arena que RunRoot construye después, así el scatter y el director de
## cada etapa ven un RunState limpio, y la semilla de la Cacería Diaria se
## fija en un solo punto. reset() es idempotente: la llamada del menú de
## selección no estorba.
func _enter_tree() -> void:
	RunState.reset()


func _ready() -> void:
	# Los objetos, los altares y RunRoot llegan a este bloque por el grupo
	# (vacuum_pickups, place_party).
	add_to_group("run_systems")
	if Coop.is_coop():
		_spawn_party()
	get_tree().call_group("hud", "show_stage_tag", RunState.stage_index, RunState.lap)
	# Subir de nivel no aspira el suelo: los vacuum() de gemas y orbes
	# quedan para el objeto Imán (ver vacuum_pickups).


## Entrada de etapa (RunRoot, por el grupo "run_systems"): pone a todo el
## grupo en el punto de aparición de la arena nueva, de pie o caídos (un
## caído viaja con el grupo). Usa el mismo anillo que el arranque co-op,
## así nadie cae encima de otro, y vuelve a anclar el rescate del vacío de
## cada cuerpo: el ancla anterior es de un mapa que ya no existe.
func place_party(origin: Vector3) -> void:
	var bodies: Array[Node] = []
	for group: String in ["player", "downed_players"]:
		bodies.append_array(get_tree().get_nodes_in_group(group))
	bodies.sort_custom(func(a: Node, b: Node) -> bool:
		return int(a.get("player_index")) < int(b.get("player_index")))
	for i: int in bodies.size():
		var body := bodies[i] as Node3D
		if body == null:
			continue
		# El anillo mueve el cuerpo hacia un lado, así que la altura del
		# suelo se vuelve a leer en ese punto.
		var at := origin + _coop_spawn_offset(i)
		var terrain := Terrain.find(get_tree())
		if terrain != null:
			at.y = terrain.height_at(at.x, at.z)
		body.global_position = at
		if body.has_method("anchor_here"):
			body.call("anchor_here")


## Entrada del objeto Imán (y de cualquier efecto que aspire el suelo):
## toda gema de XP y orbe de vida vivos van al jugador más cercano, sin
## importar el radio de recogida. No afecta a las gemas que ya van en camino.
func vacuum_pickups() -> void:
	get_tree().call_group(XpGem.LIVE_GROUP, "vacuum")
	get_tree().call_group(HealthOrb.LIVE_GROUP, "vacuum")


## Arranque co-op: el Player de la escena es el puesto 0; los puestos
## 1..N-1 son instancias extra de Player.tscn alrededor del mismo punto, y
## la pantalla pasa a ser un SplitScreen con una vista por jugador. Corre
## dentro de este _ready (el padre está listo después de los hijos), así
## RunManager y el HUD ven al grupo completo en el mismo frame.
func _spawn_party() -> void:
	var first := get_node("Player") as Player
	var players: Array = [first]
	for slot in range(1, Coop.player_count):
		var extra := PLAYER_SCENE.instantiate() as Player
		extra.name = "Player%d" % (slot + 1)
		extra.player_index = slot
		# La posición va ANTES de add_child: Player._ready guarda su punto
		# de aparición (ancla del rescate del vacío) al entrar al árbol.
		extra.position = first.position + _coop_spawn_offset(slot)
		add_child(extra)
		players.append(extra)
	add_child(SplitScreenView.build(players))


## Desplazamiento del puesto `slot` en el anillo de aparición. El puesto 0
## cae justo en el punto; los demás se reparten el círculo en partes
## iguales, así dos puestos nunca coinciden.
func _coop_spawn_offset(slot: int) -> Vector3:
	if slot <= 0:
		return Vector3.ZERO
	var angle := TAU * float(slot) / float(maxi(Coop.player_count, 1))
	return Vector3(cos(angle), 0.0, sin(angle)) * coop_spawn_radius
