class_name PowerUpPickup
extends Area3D
## Un power-up en el suelo: una gema de color que flota con el glifo de dos
## letras de su fila encima; se recoge caminando hacia ella. La sueltan las
## bajas o, solo la estrella, la echa a rondar el avistamiento del
## WorldDirector.
##
## De alcance de etapa: su padre es RunRoot.stage_parent y está en el grupo
## `powerup_pickups`, para que el cambio de etapa la libere y el barrido de
## etapa la cuente. NO va en pool: hay pocas a la vez y viven segundos.
##
## Su vida es corta a propósito: al final de una etapa el mapa ya tiene
## docenas de marcadores, y uno que esperara para siempre solo sumaría ruido.
##
## La forma, el tamaño, la altura, el brillo y la luz se ajustan en
## PowerUpPickup.tscn (nodos CollisionShape3D, Gem, Glyph y Light); el script
## solo los tiñe con el color y el glifo de la fila.

@export_group("Vida")
## Segundos antes de que se desvanezca sin recoger.
@export var lifetime: float = 45.0
## Segundos de vida de la estrella: más larga porque se mueve y hay que alcanzarla.
@export var star_lifetime: float = 60.0
## Segundos del desvanecimiento antes de que el nodo se libere.
@export var fade_time: float = 0.45

@export_group("Ronda de la estrella")
## Velocidad de ronda de la estrella, en m/s (las demás filas no se mueven).
@export var roam_speed: float = 6.0
## Altura del salto mientras ronda, en metros.
@export var hop_height: float = 0.9
## Saltos por segundo mientras ronda, en Hz.
@export var hop_hz: float = 1.6
## Distancia, en metros, que mira adelante la estrella buscando un muro en
## el que rebotar.
@export var roam_probe: float = 3.0
## Ciclo arcoíris del tinte de la estrella, en vueltas por segundo.
@export var star_hue_hz: float = 0.55

@export_group("Flotación y giro")
## Altura de la flotación en reposo, en metros.
@export var bob_height: float = 0.22
## Frecuencia de la flotación en reposo, en Hz.
@export var bob_hz: float = 1.4
## Giro de la gema, en radianes por segundo.
@export var spin_speed: float = 1.8
@export_group("")

var powerup_id: String = ""
## True para la fila de la estrella: ronda, salta y rebota en vez de quedarse.
var roaming: bool = false

var _row: Dictionary = {}
var _color: Color = Color.WHITE
## Material propio de esta instancia (resource_local_to_scene en la
## escena): la estrella anima su albedo sin teñir a los demás power-ups.
var _material: StandardMaterial3D = null
## Altura de reposo de la gema, la que guarda la escena; la flotación oscila
## alrededor de ella.
var _gem_rest_y: float = 0.0
var _time: float = 0.0
var _left: float = 0.0
var _ground_y: float = 0.0
## False hasta que el drop está colocado y _ground_y vale algo.
var _ground_captured: bool = false
var _heading: Vector2 = Vector2.RIGHT
var _bounces: int = 0
var _taken: bool = false
var _bounds: Node = null

@onready var _gem: MeshInstance3D = $Gem
@onready var _glyph: Label3D = $Glyph
@onready var _light: OmniLight3D = $Light


## DEBE correr antes de que el nodo entre al árbol: todo lo de abajo se
## arma con la fila.
func setup(id: String) -> void:
	powerup_id = id
	_row = PowerUpCatalog.by_id(id)
	roaming = String(_row.get("kind", "")) == "star"


func _ready() -> void:
	add_to_group(&"powerup_pickups")
	add_to_group(&"map_markers")
	if _row.is_empty():
		_row = PowerUpCatalog.by_id(powerup_id)
	if _row.is_empty():
		push_warning("PowerUpPickup: unknown power-up '%s'" % powerup_id)
		queue_free()
		return
	_color = _row.get("color", Color.WHITE)
	_left = star_lifetime if roaming else lifetime
	# NO se captura aquí: todo camino de spawn fija la posición DESPUÉS de
	# add_child, así que en _ready se leería el origen del PADRE. Se toma en
	# el primer frame de física, con el drop ya colocado (solo es el
	# respaldo para una escena sin Terrain).
	_ground_captured = false
	# Las capas y `monitorable` están en PowerUpPickup.tscn, NO aquí: un drop
	# nace dentro de EnemyBase._on_died, que corre dentro de un Health.died
	# emitido por take_damage — a menudo en medio del body_entered de alguna
	# Area3D. Godot rechaza escribirlas mientras hay una señal en vuelo, y la
	# escena ya las aplicó cuando corre _ready. (No choca con nada y solo
	# detecta la capa del jugador: nunca empuja a un raider ni frena un tiro.)
	_tint_visual()
	_heading = Vector2(randf() * 2.0 - 1.0, randf() * 2.0 - 1.0).normalized()
	if _heading.length_squared() < 0.01:
		_heading = Vector2.RIGHT
	_bounds = get_tree().get_first_node_in_group("arena_bounds")
	body_entered.connect(_on_body_entered)


## Pinta la gema, el glifo y la luz con la fila; todo lo demás viene de la
## escena.
func _tint_visual() -> void:
	_gem_rest_y = _gem.position.y
	_material = _gem.material_override as StandardMaterial3D
	_material.albedo_color = _color
	_material.emission = _color
	_glyph.text = String(_row.get("glyph", "?"))
	_light.light_color = _color


func _physics_process(delta: float) -> void:
	if _taken:
		return
	_capture_ground()
	_time += delta
	_left -= delta
	if _left <= 0.0:
		_expire()
		return
	_gem.rotate_y(spin_speed * delta)
	if roaming:
		_tick_roam(delta)
		_tick_star_tint()
	else:
		_gem.position.y = _gem_rest_y + sin(_time * TAU * bob_hz) * bob_height


## La estrella cruza el mapa en vez de esperar. Rebota en todo lo que la
## máscara de la arena marca como no caminable y en el borde — la misma
## prueba que usa todo spawn —, así nunca termina dentro de las rocas.
func _tick_roam(delta: float) -> void:
	var step := roam_speed * delta
	var here := Vector2(global_position.x, global_position.z)
	var ahead := here + _heading * maxf(roam_probe, step)
	if not _walkable(ahead):
		# Refleja en el eje bloqueado; si lo están los dos, da media vuelta.
		var flip_x := not _walkable(Vector2(ahead.x, here.y))
		var flip_z := not _walkable(Vector2(here.x, ahead.y))
		if not flip_x and not flip_z:
			flip_x = true
			flip_z = true
		if flip_x:
			_heading.x = -_heading.x
		if flip_z:
			_heading.y = -_heading.y
		_bounces += 1
		here += _heading * step
	else:
		here += _heading * step
	global_position.x = here.x
	global_position.z = here.y
	var ground := _ground_height(here)
	_ground_y = ground
	global_position.y = ground + absf(sin(_time * PI * hop_hz)) * hop_height


func _tick_star_tint() -> void:
	var tint := Color.from_hsv(fmod(_time * star_hue_hz, 1.0), 0.75, 1.0)
	_material.albedo_color = tint
	_material.emission = tint
	_light.light_color = tint


func _walkable(xz: Vector2) -> bool:
	if _bounds == null or not _bounds.has_method("is_walkable"):
		return true
	return bool(_bounds.call("is_walkable", xz))


## Altura del suelo bajo el drop, tomada con el spawn ya colocado. Solo se
## lee cuando no hay Terrain a quien preguntar.
func _capture_ground() -> void:
	if _ground_captured:
		return
	_ground_captured = true
	_ground_y = global_position.y


func _ground_height(xz: Vector2) -> float:
	var terrain := Terrain.find(get_tree())
	return terrain.height_at(xz.x, xz.y) if terrain != null else _ground_y


func _on_body_entered(body: Node3D) -> void:
	if _taken or not body.is_in_group("player"):
		return
	var powerups := PowerUps.find_in(body)
	if powerups == null:
		return
	_taken = true
	powerups.apply(powerup_id)
	Juice.sparkle(global_position + Vector3.UP * 0.8)
	Sfx.play(&"gem_pickup")
	if roaming:
		print("Star roam: bounces=%d" % _bounces)
	_vanish()


## Se acabó el tiempo: el mismo desvanecimiento, y la estrella informa su
## recorrido.
func _expire() -> void:
	_taken = true
	if roaming:
		print("Star roam: bounces=%d" % _bounces)
	_vanish()


func _vanish() -> void:
	set_physics_process(false)
	# DIFERIDO: _vanish corre dentro de body_entered, y Godot rechaza
	# escribir monitoring mientras el área despacha esa señal.
	set_deferred("monitoring", false)
	remove_from_group(&"map_markers")
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.05, fade_time) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)


## Contrato de marcador de mapa (grupo "map_markers"): vale la pena
## caminar hasta un power-up, así que se muestra — solo donde se levantó la
## niebla, como todo lo encontrado.
func map_marker_kind() -> StringName:
	return &"powerup"


## Su propio color en el mapa, para que la estrella se distinga de un drop.
func map_marker_color() -> Color:
	return _color
