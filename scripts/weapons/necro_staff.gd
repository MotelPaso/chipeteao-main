class_name NecroStaff
extends WeaponBase
## Báculo de nigromante: un rayo de alma lento que persigue al enemigo más
## cercano, y lo que MATA se levanta de tu lado.
##
## El cadáver muere entero primero (gema de XP, puntos, orbes de vida, la
## tirada de cofre de élite y el bestiario pagan), porque `Health.died` es
## síncrona y `EnemyBase._on_died` ya corrió cuando `deal_damage` vuelve. El
## siervo es una copia nueva de la misma escena creada en el cadáver: la
## muerte cuenta Y además hay siervo.
##
## Un siervo no paga NADA al expirar: ya pagó una vez como cadáver.
##
## Solo se poseen luchadores de contacto (EnemyBase.possessable): un lanzador
## poseído necesitaría que sus proyectiles y rayos cambiaran de bando, y esos
## apuntan al grupo "player" en todo su recorrido.

@export var possess_duration: float = 8.0
## Siervos vivos a la vez por portador. El más viejo expira antes para hacer
## lugar: un tope que rechazara nuevos haría sentir el arma rota justo cuando funciona.
@export var max_possessed: int = 12
@export var bolt_speed: float = 9.0
@export var bolt_lifetime: float = 2.5
@export var bolt_radius: float = 0.28
## Segundos entre los rayos extra que agrega el Tomo de Multitud. Escalonados:
## rayos lanzados en el mismo frame comparten trayectoria y golpean dos veces el mismo cuerpo.
@export var extra_bolt_stagger: float = 0.1

const BOLT_COLOR := Color(0.65, 0.35, 0.95)
## Qué tan cerca tiene que llegar un rayo para contar como golpe, en metros.
const BOLT_HIT_RADIUS: float = 0.9
## Grupo de los siervos vivos, para leer el tope del portador desde afuera (el
## soak imprime possessed=a/b con esto).
const POSSESSED_GROUP: StringName = &"possessed"

var _bolt_mesh: SphereMesh = null
## Un rayo de alma en vuelo. Un registro en vez de un Dictionary suelto: su
## `visual` cruza frames, y con campos el compilador atrapa un error de tipeo.
class SoulBolt extends RefCounted:
	var visual: MeshInstance3D = null
	var target: Node3D = null
	var left: float = 0.0

var _bolts: Array[SoulBolt] = []


func _ready() -> void:
	_bolt_mesh = SphereMesh.new()
	_bolt_mesh.radius = bolt_radius
	_bolt_mesh.height = bolt_radius * 2.0
	_bolt_mesh.radial_segments = 8
	_bolt_mesh.rings = 4
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(BOLT_COLOR, 0.9)
	material.emission_enabled = true
	material.emission = BOLT_COLOR
	material.emission_energy_multiplier = 2.2
	_bolt_mesh.material = material


func fire(target: Node3D) -> void:
	var shots := effective_projectile_count()
	_launch(target)
	for i in range(1, shots):
		# Escalonados, y cada uno vuelve a buscar blanco: cuando sale el
		# tercero, el primero puede haber matado al suyo.
		var delay := extra_bolt_stagger * float(i)
		# En paso de física, como las demás armas de ráfaga: el daño cae en el
		# mismo tick que el resto del combate.
		get_tree().create_timer(delay, false, true).timeout.connect(_launch_at_fresh_target)


func _launch_at_fresh_target() -> void:
	if not is_inside_tree():
		return
	_launch(acquire_target())


func _launch(target: Node3D) -> void:
	if target == null or not is_instance_valid(target):
		return
	var bolt := SoulBolt.new()
	bolt.visual = spawn_fx_mesh(_bolt_mesh)
	bolt.visual.global_position = global_position + Vector3.UP * 1.0
	bolt.target = target
	bolt.left = bolt_lifetime
	_bolts.append(bolt)


func _physics_process(delta: float) -> void:
	super(delta)
	_tick_bolts(delta)


## Los rayos persiguen su blanco y se resuelven al contacto. Se recorren
## hacia atrás para poder quitar un rayo dentro del bucle, y cada blanco se
## revisa de nuevo: el cuerpo pudo liberarse en pleno vuelo (otro lo mató) o
## ser poseído por otro rayo nuestro.
func _tick_bolts(delta: float) -> void:
	for i in range(_bolts.size() - 1, -1, -1):
		var bolt := _bolts[i]
		bolt.left -= delta
		# Un cuerpo que salió del grupo "enemies" ya no es blanco aunque siga
		# vivo: otro portador lo levantó como siervo, y un siervo es invisible
		# para las armas de los jugadores.
		var target_gone := bolt.target == null or not is_instance_valid(bolt.target) \
				or not bolt.target.is_inside_tree() \
				or not bolt.target.is_in_group(&"enemies")
		if bolt.left <= 0.0 or target_gone:
			_kill_bolt(i)
			continue
		var aim := bolt.target.global_position + Vector3.UP * 0.8
		var span := aim - bolt.visual.global_position
		var step := bolt_speed * delta
		if span.length() <= maxf(step, BOLT_HIT_RADIUS):
			_strike(bolt.target)
			_kill_bolt(i)
			continue
		bolt.visual.global_position += span.normalized() * step


## Un rayo impacta. La muerte y la posesión son dos hechos separados: el
## cuerpo muere normal (paga todo lo que debe) y solo ENTONCES, si murió por
## este golpe y se puede levantar, se levanta un siervo en su lugar.
func _strike(target: Node3D) -> void:
	var health := Health.find_in(target)
	if health == null or health.is_dead:
		return
	var enemy := target as EnemyBase
	# Se lee ANTES del golpe: _on_died corre síncrono dentro de take_damage y
	# deja el cadáver a medio desmontar, pero sus exports y su transformada
	# siguen legibles los 0.3 s que dura su tween de muerte.
	var scene_path := enemy.get_scene_file_path() if enemy != null else ""
	var at := target.global_position
	var can_raise := enemy != null and enemy.possessable and not scene_path.is_empty()
	if deal_damage(health) <= 0.0:
		return
	if not health.is_dead or not can_raise:
		return
	_raise_servant(scene_path, at, enemy)


func _raise_servant(scene_path: String, at: Vector3, corpse: EnemyBase) -> void:
	var carrier := carrier_player()
	if carrier == null:
		return
	_trim_servants()
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return
	var servant := scene.instantiate() as EnemyBase
	if servant == null:
		return
	# Se copia del cadáver para que un tanque poseído siga pegando como
	# tanque; lo demás son los valores de la escena, así esto no necesita
	# conocer los exports de cada enemigo.
	var contact: Variant = corpse.get("contact_damage")
	if contact != null:
		servant.set("contact_damage", contact)
	servant.move_speed = corpse.move_speed
	RunRoot.stage_parent(get_tree()).add_child(servant)
	servant.global_position = at
	servant.make_possessed(carrier, possess_duration * duration_scale())


## Con el tope lleno se va el siervo más viejo, no el más nuevo: el recién
## levantado es el que está donde ocurre la pelea.
func _trim_servants() -> void:
	var mine: Array[Node] = []
	for node: Node in get_tree().get_nodes_in_group(POSSESSED_GROUP):
		var servant := node as EnemyBase
		if servant != null and servant.possession_carrier() == carrier_player():
			mine.append(servant)
	# maxi(..., 1) y la prueba de vacío juntos: con un max_possessed de 0 (las
	# filas de evolución escriben propiedades por NOMBRE y podrían llevarlo a
	# cero) el bucle sin esto no terminaría y colgaría el hilo de física.
	while not mine.is_empty() and mine.size() >= maxi(max_possessed, 1):
		var oldest := mine.pop_front() as EnemyBase
		if oldest != null and is_instance_valid(oldest):
			oldest.end_possession()


## Siervos que tiene ahora este portador; el soak imprime possessed=a/b con
## esto y el tope, y a>b significaría que el tope no se cumple.
func possessed_count() -> int:
	var mine := 0
	for node: Node in get_tree().get_nodes_in_group(POSSESSED_GROUP):
		var servant := node as EnemyBase
		if servant != null and servant.possession_carrier() == carrier_player():
			mine += 1
	return mine


func _kill_bolt(index: int) -> void:
	var bolt := _bolts[index]
	if bolt.visual != null and is_instance_valid(bolt.visual):
		bolt.visual.queue_free()
	_bolts.remove_at(index)


## Los rayos cuelgan de la arena, no de esta arma, así sobreviven si el
## raider muere en pleno vuelo; pero no deben sobrevivir al ARMA (evolución,
## fin de partida) sin nadie que los avance.
func _exit_tree() -> void:
	for i in range(_bolts.size() - 1, -1, -1):
		_kill_bolt(i)
