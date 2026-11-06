extends Node
## Autoload "Juice": la capa de sensación de juego. Ayudantes centrales y
## baratos que todo sistema llama directo: sacudida de cámara por trauma,
## hit-stop con resguardo, destellos de golpe con material compartido,
## ráfagas de partículas de muerte, viñeta de daño, anillo de subida de
## nivel y el empujón de FOV al derrapar. Todo sigue andando en pausa (este
## nodo procesa siempre; las restauraciones corren con el árbol pausado) y
## sin ventana (las búsquedas de cámara y escena están resguardadas).

const VIGNETTE_SHADER: String = """
shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.82, 0.06, 0.05, 1.0);

void fragment() {
	float edge = smoothstep(0.3, 0.75, length(UV - vec2(0.5)));
	COLOR = vec4(tint.rgb, edge * intensity);
}
"""

@export_group("Camera Shake")
## Desplazamiento máximo de la cámara, en metros, con trauma completo.
@export var shake_max_offset: float = 0.4
## Velocidad de muestreo del ruido de la sacudida; más alto = más nervioso.
@export var shake_noise_speed: float = 10.0
@export var kill_shake_strength: float = 0.05
## Las muertes de la horda acumulan trauma solo hasta este techo (0-1),
## así una matanza se siente como un retumbe y no como un terremoto.
@export var kill_shake_cap: float = 0.18
@export var hurt_shake_strength: float = 0.08
@export var hurt_shake_cap: float = 0.3
@export var boss_death_shake_strength: float = 0.35

@export_group("Hit Stop")
@export var crit_stop_scale: float = 0.3
@export var crit_stop_duration: float = 0.05
@export var crit_shake_strength: float = 0.1
## Segundos mínimos entre golpes de crítico: una build de críticos rápidos
## no debe encadenar el juego en cámara lenta permanente.
@export var crit_punch_cooldown: float = 0.35
@export var boss_death_stop_scale: float = 0.4
@export var boss_death_stop_duration: float = 0.5

@export_group("Hit Flash")
@export var flash_duration: float = 0.08

@export_group("Damage Vignette")
@export var vignette_strength: float = 0.5
@export var vignette_fade_time: float = 0.45

@export_group("Slide FOV")
@export var fov_kick_amount: float = 5.0
@export var fov_kick_in_time: float = 0.1
@export var fov_kick_out_time: float = 0.15

@export_group("Bursts")
@export var death_burst_min: int = 4
@export var death_burst_max: int = 6
## No lo subas por encima del `amount` de DeathBurst.tscn (24): la ráfaga
## se recorta a su buffer en vez de reasignarlo a mitad de la muerte.
@export var boss_burst_amount: int = 24
@export var sparkle_amount: int = 6
@export var sparkle_color: Color = Color(1.0, 0.84, 0.3)

@export_group("Level Pulse")
@export var level_pulse_color: Color = Color(0.35, 0.95, 0.6)
@export var level_pulse_duration: float = 0.5


## Cámaras que mueve la capa de sensación. La pantalla dividida registra
## aquí la cámara propia (origen) de cada jugador, que es la que SplitScreen
## copia en la SubViewport que dibuja; con el grupo vacío (solo) se usa la
## cámara activa del viewport raíz.
const FEEL_CAMERA_GROUP: StringName = &"feel_camera"


## Registro de destello por dueño: las mallas tocadas y los overlays a
## devolver. Una entrada por cuerpo; golpes repetidos solo renuevan el tiempo.
class FlashState:
	extends RefCounted
	var meshes: Array[MeshInstance3D] = []
	var prev: Array[Material] = []
	## Nodo dueño del overlay COMPUESTO (EnemyBase.current_overlay), si lo hay:
	## preguntarle es mejor que devolver `prev`, que resucitaría un overlay
	## que el cuerpo soltó durante el destello.
	var overlay_owner: Node = null
	var time_left: float = 0.0


## Un empujón de FOV vivo. Uno por cámara, para que raiders de co-op que
## derrapan a la vez no se peleen por un solo FOV base.
class FovKick:
	extends RefCounted
	var camera: Camera3D = null
	var base_fov: float = 0.0
	var tween: Tween = null


# --- Estado de la sacudida ---
var _trauma: float = 0.0
var _trauma_decay: float = 0.0
var _shake_time: float = 0.0
## Cámaras desplazadas ahora, con el desplazamiento h/v en que reposaba cada una.
var _shake_cameras: Array[Camera3D] = []
var _shake_rest: Dictionary[int, Vector2] = {}
var _noise_x: FastNoiseLite = FastNoiseLite.new()
var _noise_y: FastNoiseLite = FastNoiseLite.new()
## Caché por frame de proceso de _feel_cameras() (la sacudida pregunta en
## cada tick).
var _feel_cameras_cache: Array[Camera3D] = []
var _feel_cameras_frame: int = -1

# --- Estado del hit-stop (un solo acumulador: se extiende, nunca se apila) ---
var _stop_left: float = 0.0
var _crit_cd_left: float = 0.0

# --- Estado del destello ---
var _flash_material: StandardMaterial3D
var _flashes: Dictionary[int, FlashState] = {}
var _expired_flash_keys: Array[int] = []

# --- Estado de la viñeta ---
var _vignette_material: ShaderMaterial
var _vignette_tween: Tween

# --- Estado del empujón de FOV (una entrada por cámara empujada) ---
var _fov_kicks: Dictionary[int, FovKick] = {}
## Lista reusada para el barrido por tick, como _expired_flash_keys: no se
## puede borrar de un diccionario mientras se recorre.
var _expired_fov_keys: Array[int] = []

# --- Estado del pulso de nivel ---
## Frame de proceso del último anillo/sonido de nivel: RunState emite
## leveled_up una vez POR NIVEL, y una gema gorda puede dispararlo tres veces
## en un mismo frame.
var _level_pulse_frame: int = -1
## Malla del anillo de nivel, armada en la primera subida y compartida por
## todos los anillos siguientes. El material sí es uno por anillo
## (duplicado de _level_ring_material) porque el desvanecimiento escribe su
## alfa: GeometryInstance3D.transparency evitaría la copia, pero solo
## funciona en Forward+, y en el renderer Compatibility el anillo dejaría de
## desvanecerse.
var _level_ring_mesh: TorusMesh = null
var _level_ring_material: StandardMaterial3D = null


func _ready() -> void:
	# Las restauraciones (time_scale, sacudida, viñeta) deben seguir corriendo
	# mientras la UI de cartas o la pantalla final pausan el árbol.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_noise_x.seed = 1337
	_noise_y.seed = 7331
	_noise_x.frequency = 3.0
	_noise_y.frequency = 3.0
	_flash_material = StandardMaterial3D.new()
	_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_material.albedo_color = Color(1.0, 1.0, 1.0, 0.7)
	_flash_material.emission_enabled = true
	_flash_material.emission = Color(1.0, 1.0, 1.0)
	_flash_material.emission_energy_multiplier = 2.2
	_build_vignette()
	RunState.leveled_up.connect(_on_leveled_up)


func _process(delta: float) -> void:
	# El hit-stop también escala el delta de _process; se divide de vuelta
	# para que la ventana del stop y el enfriamiento de crítico cuenten tiempo
	# real (sin escalar).
	var unscaled := delta / maxf(Engine.time_scale, 0.001)
	_crit_cd_left = maxf(_crit_cd_left - unscaled, 0.0)
	if _stop_left > 0.0:
		_stop_left -= unscaled
		if _stop_left <= 0.0:
			_stop_left = 0.0
			Engine.time_scale = 1.0
	_tick_flashes(delta)
	_tick_shake(delta)
	_tick_fov_kicks()


# --- Sacudida de cámara -----------------------------------------------------

## Suma `strength` de trauma, que se disipa del todo en unos `duration`
## segundos. trauma_cap < 1 limita cuánto puede acumular ESTE tipo de
## sacudida (fuentes repetitivas); sacudidas mayores sin techo igual pasan.
func shake(strength: float, duration: float = 0.3, trauma_cap: float = 1.0) -> void:
	if strength <= 0.0 or duration <= 0.0:
		return
	if _trauma >= trauma_cap:
		return
	# La disipación se lleva como "tiempo que falta para vaciarse", no como
	# una tasa máxima pegajosa: si no, una sacudida rápida (la muerte de un
	# jefe) recortaría todas las siguientes a su tasa.
	var time_left := _trauma / _trauma_decay if _trauma_decay > 0.0 else 0.0
	_trauma = minf(_trauma + strength, clampf(trauma_cap, 0.0, 1.0))
	_trauma_decay = _trauma / maxf(time_left, duration)


func _tick_shake(delta: float) -> void:
	if _trauma <= 0.0:
		return
	_shake_time += delta * shake_noise_speed
	_sync_shake_cameras(_feel_cameras())
	# h/v_offset sobreviven al SpringArm3D (que reescribe el transform del
	# hijo cada frame) y nunca rotan el rig.
	var amount := pow(_trauma, 1.5) * shake_max_offset
	var offset_h := _noise_x.get_noise_1d(_shake_time) * amount
	var offset_v := _noise_y.get_noise_1d(_shake_time) * amount
	for camera: Camera3D in _shake_cameras:
		if not is_instance_valid(camera):
			continue
		var rest: Vector2 = _shake_rest.get(camera.get_instance_id(), Vector2.ZERO)
		camera.h_offset = rest.x + offset_h
		camera.v_offset = rest.y + offset_v
	_trauma = maxf(_trauma - _trauma_decay * delta, 0.0)
	if _trauma == 0.0:
		_trauma_decay = 0.0
		_release_shake_cameras()


## Empieza a mover las cámaras que se acaban de sumar y devuelve las que
## salieron (una vista que se cierra a mitad de sacudida no debe quedar
## desplazada).
func _sync_shake_cameras(cameras: Array[Camera3D]) -> void:
	for i in range(_shake_cameras.size() - 1, -1, -1):
		var tracked := _shake_cameras[i]
		if cameras.has(tracked) and is_instance_valid(tracked):
			continue
		_rest_camera(tracked)
		_shake_cameras.remove_at(i)
	for camera: Camera3D in cameras:
		if _shake_cameras.has(camera):
			continue
		_shake_cameras.append(camera)
		_shake_rest[camera.get_instance_id()] = Vector2(camera.h_offset, camera.v_offset)


func _release_shake_cameras() -> void:
	for camera: Camera3D in _shake_cameras:
		_rest_camera(camera)
	_shake_cameras.clear()
	_shake_rest.clear()


func _rest_camera(camera: Camera3D) -> void:
	if camera == null:
		return
	if not is_instance_valid(camera):
		# Una cámara liberada a mitad de sacudida se lleva su id (preguntarle
		# algo a un objeto liberado es un error), así que su entrada se busca
		# resolviendo los ids. El registro TIENE que irse: esto es un autoload,
		# y cada cambio de etapa o salida de co-op retira una cámara por vista.
		for key: int in _shake_rest.keys():
			if not is_instance_id_valid(key):
				_shake_rest.erase(key)
		return
	var key := camera.get_instance_id()
	var rest: Vector2 = _shake_rest.get(key, Vector2.ZERO)
	camera.h_offset = rest.x
	camera.v_offset = rest.y
	_shake_rest.erase(key)


# --- Hit-stop -----------------------------------------------------------------

## Baja breve de Engine.time_scale. Llamadas que se solapan toman la escala
## más lenta y el final más lejano en UN acumulador, y _process siempre
## restaura exactamente 1.0: el juego nunca queda lento.
func hit_stop(scale: float, duration: float) -> void:
	if duration <= 0.0:
		return
	var clamped := clampf(scale, 0.05, 1.0)
	if _stop_left > 0.0:
		Engine.time_scale = minf(Engine.time_scale, clamped)
		_stop_left = maxf(_stop_left, duration)
	else:
		Engine.time_scale = clamped
		_stop_left = duration


# --- Destello de golpe ---------------------------------------------------------

## Destello blanco en cada malla bajo mesh_owner (pasa el rig visual del
## enemigo). Un solo material de overlay compartido — nunca duplicado por
## golpe; los overlays previos (el brillo de élite) vuelven al terminar.
func flash(mesh_owner: Node3D) -> void:
	if mesh_owner == null or not is_instance_valid(mesh_owner):
		return
	var key := mesh_owner.get_instance_id()
	if _flashes.has(key):
		var active: FlashState = _flashes[key]
		active.time_left = flash_duration  # solo renueva: sin rebuscar ni reservar
		return
	var entry := FlashState.new()
	var owner_mesh := mesh_owner as MeshInstance3D
	if owner_mesh != null:
		entry.meshes.append(owner_mesh)
	for node: Node in mesh_owner.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh != null:
			entry.meshes.append(mesh)
	if entry.meshes.is_empty():
		return
	entry.overlay_owner = _overlay_owner(mesh_owner)
	for mesh: MeshInstance3D in entry.meshes:
		entry.prev.append(mesh.material_overlay)
		mesh.material_overlay = _flash_material
	entry.time_left = flash_duration
	_flashes[key] = entry


## El nodo dueño del overlay compuesto de `mesh_owner`, o null si nadie lo
## reclama. EnemyBase expone current_overlay() en el cuerpo y los
## llamadores pasan su hijo Visual, así que también se mira un nivel arriba.
static func _overlay_owner(mesh_owner: Node3D) -> Node:
	if mesh_owner.has_method(&"current_overlay"):
		return mesh_owner
	var parent := mesh_owner.get_parent()
	if parent != null and parent.has_method(&"current_overlay"):
		return parent
	return null


func _tick_flashes(delta: float) -> void:
	if _flashes.is_empty():
		return
	_expired_flash_keys.clear()
	for key: int in _flashes:
		var entry: FlashState = _flashes[key]
		entry.time_left -= delta
		if entry.time_left <= 0.0:
			_restore_flash(entry)
			_expired_flash_keys.append(key)
	for key: int in _expired_flash_keys:
		_flashes.erase(key)


## Termina un destello. Si el cuerpo compone su propio overlay (tinte de
## veneno, brillo de élite) se le pide la respuesta ACTUAL en vez de repetir
## la capturada al empezar: un veneno que termina durante el destello no
## debe volver con la restauración.
func _restore_flash(entry: FlashState) -> void:
	var composed: Material = null
	var owned := entry.overlay_owner != null and is_instance_valid(entry.overlay_owner)
	if owned:
		composed = entry.overlay_owner.call(&"current_overlay") as Material
	for i in entry.meshes.size():
		var mesh := entry.meshes[i]
		if is_instance_valid(mesh):
			mesh.material_overlay = composed if owned else entry.prev[i]


# --- Ráfagas de partículas ----------------------------------------------------

## Reproduce un DeathBurst de un disparo en `at`, teñido `color`. Va en pool:
## la ráfaga se devuelve sola a Pools al terminar.
func burst(at: Vector3, color: Color, amount: int) -> void:
	var fx := Pools.acquire_scene(Pools.DEATH_BURST_SCENE) as DeathBurst
	if fx == null:
		return
	fx.global_position = at
	fx.fire(color, maxi(amount, 1))


# --- Momentos de sensación (ajustes arriba; las llamadas son de una línea) --

func enemy_died(at: Vector3, color: Color) -> void:
	shake(kill_shake_strength, 0.25, kill_shake_cap)
	burst(at, color, randi_range(death_burst_min, death_burst_max))
	Sfx.play(&"enemy_die")


func boss_died(at: Vector3, color: Color) -> void:
	shake(boss_death_shake_strength, 0.6)
	hit_stop(boss_death_stop_scale, boss_death_stop_duration)
	burst(at, color, boss_burst_amount)
	Sfx.play(&"boss_die")


## Crítico: micro hit-stop y una sacudida algo mayor, con límite de ritmo
## para que una build de muchos críticos puntúe en vez de zumbar.
func crit_punch() -> void:
	if _crit_cd_left > 0.0:
		return
	_crit_cd_left = crit_punch_cooldown
	shake(crit_shake_strength, 0.25)
	hit_stop(crit_stop_scale, crit_stop_duration)


func player_hurt() -> void:
	shake(hurt_shake_strength, 0.3, hurt_shake_cap)
	_pulse_vignette()
	Sfx.play(&"player_hurt")


## Destello dorado de completado para cofres y santuarios.
func sparkle(at: Vector3) -> void:
	burst(at, sparkle_color, sparkle_amount)


# --- Empujón de FOV al derrapar ------------------------------------------------

## Abre `camera` mientras dura un derrape. Pasa la cámara PROPIA de quien
## derrapa: en pantalla dividida no hay cámara activa en el viewport raíz,
## así que la forma sin argumento no tiene qué empujar (y empujar todas las
## vistas abriría el FOV de quien no derrapa). SplitScreen copia el fov de
## la cámara origen a la vista que dibuja.
func fov_kick_begin(camera: Camera3D = null) -> void:
	var target := camera if camera != null else _active_camera()
	if target == null or not is_instance_valid(target):
		return
	var key := target.get_instance_id()
	var kick: FovKick = _fov_kicks.get(key, null)
	if kick == null:
		# Primer empujón en esta cámara: se guarda su FOV de reposo. Mientras
		# el tween de vuelta de la MISMA cámara sigue en curso, la base
		# guardada sigue valiendo: nunca se relee un fov en movimiento.
		kick = FovKick.new()
		kick.camera = target
		kick.base_fov = target.fov
		_fov_kicks[key] = kick
	_kill_fov_tween(kick)
	kick.tween = create_tween()
	kick.tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	kick.tween.tween_property(target, "fov", kick.base_fov + fov_kick_amount,
			fov_kick_in_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func fov_kick_end(camera: Camera3D = null) -> void:
	var target := camera if camera != null else _active_camera()
	if target == null:
		return
	var key := target.get_instance_id()
	var kick: FovKick = _fov_kicks.get(key, null)
	if kick == null:
		return
	if not is_instance_valid(kick.camera):
		_kill_fov_tween(kick)
		_fov_kicks.erase(key)
		return
	_kill_fov_tween(kick)
	kick.tween = create_tween()
	kick.tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	kick.tween.tween_property(kick.camera, "fov", kick.base_fov, fov_kick_out_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	kick.tween.tween_callback(_on_fov_restored.bind(key))


## Las entradas solo salen por los caminos normales (termina el tween de
## vuelta, o fov_kick_end encuentra la cámara ya liberada), y un raider cuya
## cámara muere A MITAD de un derrape no pasa por ninguno: la entrada
## quedaría en este autoload con una Camera3D muerta. Se barren aquí; el
## diccionario está vacío salvo durante un derrape, así que cuesta un if.
func _tick_fov_kicks() -> void:
	if _fov_kicks.is_empty():
		return
	_expired_fov_keys.clear()
	for key: int in _fov_kicks:
		var kick: FovKick = _fov_kicks[key]
		if is_instance_valid(kick.camera):
			continue
		_kill_fov_tween(kick)
		_expired_fov_keys.append(key)
	for key: int in _expired_fov_keys:
		_fov_kicks.erase(key)


func _on_fov_restored(key: int) -> void:
	_fov_kicks.erase(key)


func _kill_fov_tween(kick: FovKick) -> void:
	if kick.tween != null and kick.tween.is_valid():
		kick.tween.kill()


# --- Viñeta de daño -------------------------------------------------------------

func _build_vignette() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 4  # sobre la escena 3D y bajo el HUD (capa 5 en HUD.tscn)
	add_child(layer)
	var shader := Shader.new()
	shader.code = VIGNETTE_SHADER
	_vignette_material = ShaderMaterial.new()
	_vignette_material.shader = shader
	_vignette_material.set_shader_parameter("intensity", 0.0)
	var rect := ColorRect.new()
	rect.material = _vignette_material
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)


func _pulse_vignette() -> void:
	if _vignette_material == null:
		return
	if _vignette_tween != null and _vignette_tween.is_valid():
		_vignette_tween.kill()
	_vignette_material.set_shader_parameter("intensity", vignette_strength)
	_vignette_tween = create_tween()
	_vignette_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_vignette_tween.tween_property(_vignette_material, "shader_parameter/intensity",
			0.0, vignette_fade_time).set_delay(0.05)


# --- Pulso de subida de nivel ---------------------------------------------------

func _on_leveled_up(_new_level: int) -> void:
	# RunState emite una vez POR NIVEL: una gema que vale tres niveles
	# dispararía esto tres veces en un frame (tres sonidos apilados y tres
	# anillos encimados). Uno por frame.
	var frame := Engine.get_process_frames()
	if frame == _level_pulse_frame:
		return
	_level_pulse_frame = frame
	Sfx.play(&"level_up")
	# Nivel compartido por la party: el anillo late a los pies de CADA
	# raider en pie (uno solo en solitario).
	for node: Node in get_tree().get_nodes_in_group(&"player"):
		var player := node as Node3D
		if player != null and player.is_inside_tree():
			_spawn_level_ring(player.global_position + Vector3.UP * 0.15)


## Anillo emisivo que se expande a los pies del jugador. Su tween ignora la
## pausa para que el pulso se vea bajo la UI de cartas.
func _spawn_level_ring(at: Vector3) -> void:
	var scene_root := RunRoot.stage_parent(get_tree())
	if scene_root == null:
		return
	if _level_ring_mesh == null:
		_build_level_ring_assets()
	var ring := MeshInstance3D.new()
	ring.mesh = _level_ring_mesh
	var material := _level_ring_material.duplicate() as StandardMaterial3D
	ring.material_override = material
	# Un material con alfa nunca llega a la pasada de sombras; decirlo
	# también lo saca del descarte de sombras.
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene_root.add_child(ring)
	ring.global_position = at
	ring.scale = Vector3(0.4, 0.55, 0.4)
	# Atado al ANILLO, no a este autoload: el anillo muere con la escena, y un
	# tween de Juice lo sobreviviría (salir al menú durante el pulso
	# animaría un objeto liberado).
	var tween := ring.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(4.6, 0.25, 4.6), level_pulse_duration) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(material, "albedo_color:a", 0.0, level_pulse_duration) \
			.set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(ring.queue_free)


## Arma la malla compartida del anillo de nivel y el material que copia cada
## anillo (ver _level_ring_mesh). Perezoso: se arma en la primera subida de
## nivel.
func _build_level_ring_assets() -> void:
	_level_ring_mesh = TorusMesh.new()
	_level_ring_mesh.inner_radius = 0.42
	_level_ring_mesh.outer_radius = 0.55
	# Teselado explícito: el anillo crece a ~2.5 m, donde 32 cortes aún se
	# ven redondos; 8 lados alcanzan para el tubo delgado.
	_level_ring_mesh.rings = 32
	_level_ring_mesh.ring_segments = 8
	_level_ring_material = StandardMaterial3D.new()
	_level_ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_level_ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_level_ring_material.albedo_color = Color(level_pulse_color.r, level_pulse_color.g,
			level_pulse_color.b, 0.85)
	_level_ring_material.emission_enabled = true
	_level_ring_material.emission = level_pulse_color
	_level_ring_material.emission_energy_multiplier = 2.4


# --- Matemática compartida -----------------------------------------------------

## Peso de suavizado independiente del framerate para
## `lerp(a, b, Juice.damp(r, d))`. El obvio `rate * delta` es su aproximación
## de Euler: su error crece con delta y el tiempo de respuesta cambiaría con
## el framerate (bajo 10 fps se satura en 1.0 y deja de suavizar).
static func damp(rate: float, delta: float) -> float:
	return 1.0 - exp(-rate * delta)


# --- Búsquedas compartidas -----------------------------------------------------

## Cada cámara que la capa de sensación debe mover. En pantalla dividida el
## viewport raíz NO tiene cámara activa (la de cada jugador se desactiva a
## favor de una cámara seguidora dentro de una SubViewport), así que
## SplitScreen registra en FEEL_CAMERA_GROUP las cámaras origen que copia.
## Con caché por frame de proceso: la sacudida pregunta en cada tick.
func _feel_cameras() -> Array[Camera3D]:
	var frame := Engine.get_process_frames()
	if frame == _feel_cameras_frame:
		return _feel_cameras_cache
	_feel_cameras_frame = frame
	_feel_cameras_cache.clear()
	var tree := get_tree()
	if tree != null:
		for node: Node in tree.get_nodes_in_group(FEEL_CAMERA_GROUP):
			var camera := node as Camera3D
			if camera != null and camera.is_inside_tree():
				_feel_cameras_cache.append(camera)
	if _feel_cameras_cache.is_empty():
		var single := _active_camera()
		if single != null:
			_feel_cameras_cache.append(single)
	return _feel_cameras_cache


func _active_camera() -> Camera3D:
	var viewport := get_viewport()
	if viewport == null:
		return null
	return viewport.get_camera_3d()
