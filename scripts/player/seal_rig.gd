class_name SealRig
extends Node3D
## Rig visual del cuerpo del raider; solo cosmético (la colisión vive en
## Player). El modelo sale de la fila del personaje (setup(), lo llama
## Player._apply_character) y sin modelo es la foca (assets/models/foca.glb).
## Maneja el tinte del personaje, oculta el piso horneado SUELO del modelo y
## suma movimiento procedural al hijo Model: respiración, inclinación y
## rebote al moverse, estiramiento al saltar, aplastado al derrapar y la
## caída de cara al morir (ignora la pausa). Ningún modelo trae animaciones:
## todo es matemática de transformaciones, sin reservar memoria por frame.

## Prefijo del resource_name del material que recibe el tinte (el exportador
## de GLB agrega sufijos, p. ej. "Azul personaje.001"). Cada modelo nombra
## los suyos; una fila de personaje lo cambia con tint_material_prefix.
const TINT_MATERIAL_PREFIX := "Azul personaje"

## Cuerpo cuando la fila no nombra modelo: la escena envoltorio de la foca,
## que ya trae su giro y su escala 0.6 (un .glb crudo pediría model_scale).
const DEFAULT_MODEL_SCENE := "res://assets/models/foca_character.tscn"

## Nombre del nodo basura que se oculta (el piso horneado de la foca); otros
## modelos pueden no tenerlo.
const HIDDEN_NODE_NAME := "SUELO"

@export_group("Idle")
## Amplitud de la respiración sobre la escala Y (0.02 = ±2 %).
@export var breathe_amount: float = 0.02
## Velocidad de la respiración, en radianes por segundo.
@export var breathe_speed: float = 2.2

@export_group("Movement")
## Inclinación máxima hacia donde se mueve, en radianes, a velocidad completa.
@export var lean_max: float = 0.14
## Altura del rebote a velocidad completa sobre el suelo, en metros.
@export var bob_amount: float = 0.05
## Velocidad del rebote, en radianes por segundo.
@export var bob_speed: float = 9.0
## Velocidad horizontal (m/s) que cuenta como "completa" para inclinación y rebote; no sigue a Player.move_speed.
@export var reference_speed: float = 6.0
## Velocidad vertical (m/s) que da el estiramiento máximo al saltar o caer; no sigue a Player.jump_velocity.
@export var stretch_reference: float = 8.0
## Estiramiento máximo de la escala Y en el aire (0.12 = +12 %; el ancho se achica a la par).
@export var stretch_max: float = 0.12

@export_group("Slide")
## Escala Y durante el derrape (más plana que la cápsula: se lee mejor en la foca ancha).
@export var slide_squash: float = 0.55
## Ensanchamiento en X/Z durante el aplastado (multiplicador).
@export var slide_spread: float = 1.15
## Inclinación de la nariz hacia abajo durante el derrape, en radianes.
@export var slide_pitch: float = 0.22

@export_group("Death")
## Cuánto se levanta el cuerpo al caer de cara, en metros sobre el origen del modelo (0.55 apoya bien la foca).
@export var death_lift: float = 0.55

## Ritmos de suavizado, en "fracción cerrada por segundo" (ver _damp):
## inclinación, rebote y estiramiento se asientan rápido; el aplastado del
## derrape un poco más, para que se lea como un golpe.
const MOTION_DAMP_RATE: float = 10.0
const SQUASH_DAMP_RATE: float = 14.0

@onready var _model: Node3D = $Model

## Cuerpo cuya velocidad mueve la inclinación y el rebote; null fuera de un
## jugador (harness de prueba) deja el rig solo respirando.
var _body: CharacterBody3D = null
## La única instancia del material de tinte, compartida por las superficies
## con el prefijo.
var _tint_material: StandardMaterial3D = null
## Prefijo de resource_name de los materiales teñibles del modelo ACTUAL.
var _tint_prefix: String = TINT_MATERIAL_PREFIX
var _slide_ratio: float = 1.0
var _phase: float = 0.0
var _dead: bool = false
## Estado de movimiento suavizado (se acerca a su objetivo cada frame).
var _lean: Vector2 = Vector2.ZERO
var _bob: float = 0.0
var _stretch: float = 0.0
var _squash_blend: float = 0.0
## Tween de la caída de cara (ignora la pausa), guardado para que revivir lo
## cancele: escribe las mismas propiedades de _model que _process.
var _death_tween: Tween = null


## Peso de suavizado independiente del framerate para
## `lerp(a, b, _damp(rate, d))`. `rate * delta` es su aproximación de Euler:
## su error crece con delta y el rig respondería distinto según los fps.
static func _damp(rate: float, delta: float) -> float:
	return 1.0 - exp(-rate * delta)


func _ready() -> void:
	_body = get_parent() as CharacterBody3D


## Cambia el cuerpo por el modelo de una fila de CharacterCatalog. Ruta
## vacía = la foca; la escala MULTIPLICA la que ya trae la escena del modelo
## (1.0 o no positiva = sin cambio); prefijo vacío = "Azul personaje".
func setup(model_scene: String, model_scale: float, tint_prefix: String) -> void:
	_clear_model()
	_tint_material = null
	_tint_prefix = tint_prefix if not tint_prefix.is_empty() else TINT_MATERIAL_PREFIX
	var path := model_scene if not model_scene.is_empty() else DEFAULT_MODEL_SCENE
	var packed := load(path) as PackedScene
	if packed == null:
		# Solo cosmético: el cuerpo de juego no depende del rig, así que una
		# ruta rota cuesta un personaje invisible y un aviso.
		push_warning("SealRig: model scene '%s' does not load" % path)
		return
	var model := packed.instantiate()
	if model == null:
		push_warning("SealRig: '%s' instantiates to nothing" % path)
		return
	var body := model as Node3D
	if body == null:
		push_warning("SealRig: root of '%s' is not a Node3D" % path)
		model.free()
		return
	if model_scale > 0.0 and model_scale != 1.0:
		body.scale = body.scale * model_scale
	_model.add_child(body)
	for node: Node in _model.find_children(HIDDEN_NODE_NAME, "MeshInstance3D", true, false):
		(node as MeshInstance3D).visible = false


## Descarta el cuerpo anterior para que un nuevo setup cambie limpio.
## queue_free y no free: setup corre dentro de la cadena de _ready del spawn.
func _clear_model() -> void:
	for child: Node in _model.get_children():
		child.queue_free()


## Tinte del personaje: UN duplicado del material compartido con el prefijo,
## recoloreado y puesto en cada superficie que lo usaba (cuerpo, base y
## brazos de la foca). Ojos, colmillos y gel mantienen sus materiales.
func apply_tint(tint: Color) -> void:
	for node: Node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		for surface: int in mesh_node.mesh.get_surface_count():
			var material := mesh_node.mesh.surface_get_material(surface)
			if material == null \
					or not material.resource_name.begins_with(_tint_prefix):
				continue
			if _tint_material == null:
				_tint_material = material.duplicate() as StandardMaterial3D
			mesh_node.set_surface_override_material(surface, _tint_material)
	if _tint_material != null:
		_tint_material.albedo_color = tint


## Color de tinte actual (para los harness), o negro transparente antes de teñir.
func tint_color() -> Color:
	return _tint_material.albedo_color if _tint_material != null else Color(0, 0, 0, 0)


## Gancho del derrape de Player: ratio = altura de la cápsula / altura
## normal (1 = sin derrape). Se traduce en aplastado y nariz hacia abajo.
func set_slide_ratio(ratio: float) -> void:
	_slide_ratio = clampf(ratio, 0.1, 1.0)


func _process(delta: float) -> void:
	if _dead:
		return
	_phase += delta
	var smoothing := _damp(MOTION_DAMP_RATE, delta)

	# Objetivos según el movimiento (todos en cero quieto o fuera de un jugador).
	var target_lean := Vector2.ZERO
	var speed_factor := 0.0
	var target_stretch := 0.0
	if _body != null:
		var local_velocity := _body.global_transform.basis.inverse() * _body.velocity
		var horizontal := Vector2(local_velocity.x, local_velocity.z)
		speed_factor = clampf(horizontal.length() / reference_speed, 0.0, 1.0)
		if speed_factor > 0.01:
			target_lean = horizontal.normalized() * lean_max * speed_factor
		if not _body.is_on_floor():
			target_stretch = clampf(absf(local_velocity.y) / stretch_reference, 0.0, 1.0) \
					* stretch_max
			speed_factor = 0.0  # sin rebote en el aire
	_lean = _lean.lerp(target_lean, smoothing)
	_stretch = lerpf(_stretch, target_stretch, smoothing)
	_bob = lerpf(_bob, bob_amount * speed_factor, smoothing)
	# Ratio 0.5 (la cápsula agachada) da el aplastado completo.
	_squash_blend = lerpf(_squash_blend, clampf((1.0 - _slide_ratio) * 2.0, 0.0, 1.0),
			_damp(SQUASH_DAMP_RATE, delta))

	# Escala final: respiración * estiramiento * aplastado (conserva más o
	# menos el volumen).
	var breathe := 1.0 + sin(_phase * breathe_speed) * breathe_amount
	var scale_y := breathe * (1.0 + _stretch) * lerpf(1.0, slide_squash, _squash_blend)
	var scale_xz := (1.0 - _stretch * 0.5) * lerpf(1.0, slide_spread, _squash_blend)
	_model.scale = Vector3(scale_xz, scale_y, scale_xz)

	# Inclinación HACIA el movimiento (avanzar baja la nariz, el lateral rola
	# hacia ese lado) más la nariz del derrape; el rebote va encima en el suelo.
	# Signos: la nariz apunta a -Z, así que una inclinación NEGATIVA la baja
	# (igual que el derrape), y avanzar da local_velocity.z < 0: _lean.y va
	# directo. Moverse a la derecha da _lean.x > 0 y pide un giro negativo.
	_model.rotation.x = _lean.y - slide_pitch * _squash_blend
	_model.rotation.z = -_lean.x
	_model.position.y = absf(sin(_phase * bob_speed)) * _bob


## Caída de cara al morir: el modelo pivota en su origen a ras del suelo,
## cae de nariz con rebote y se levanta lo justo para apoyarse en el piso.
## Ignora la pausa: RunManager pausa el árbol justo después de morir.
func play_death() -> void:
	if _dead:
		return
	_dead = true
	_kill_death_tween()
	_death_tween = create_tween()
	_death_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_death_tween.set_parallel(true)
	_death_tween.tween_property(_model, "rotation:x", -TAU * 0.25, 0.5) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	_death_tween.tween_property(_model, "position:y", death_lift, 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_death_tween.tween_property(_model, "scale", Vector3(1.0, 1.0, 0.8), 0.5) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Revivir en co-op: deshace la caída y devuelve el modelo al movimiento
## procedural (que reescribe rotación, escala y posición cada frame).
func reset_death() -> void:
	if not _dead:
		return
	_dead = false
	# Matar el tween PRIMERO: ignora la pausa y dura 0.5 s, así que tras un
	# rescate rápido seguiría escribiendo encima y la foca parpadearía.
	_kill_death_tween()
	_model.rotation = Vector3.ZERO
	_model.position.y = 0.0
	_model.scale = Vector3.ONE


func _kill_death_tween() -> void:
	if _death_tween != null and _death_tween.is_valid():
		_death_tween.kill()
	_death_tween = null
