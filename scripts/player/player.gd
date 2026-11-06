class_name Player
extends CharacterBody3D
## Raider de un jugador: movimiento WASD relativo a la cámara, vista con
## mouse o stick, salto con multisalto y derrape (Shift + moverse).
## Al aparecer aplica la fila de su personaje (CharacterCatalog): arma
## inicial, modelo del cuerpo con su tinte y pasiva por nivel.
## El cuerpo visible es el hijo SealRig; la física la manda la cápsula.
## apply_root() (el Entomb de Sarcognato) bloquea el movimiento sin tocar
## la cámara ni las armas.
##
## Contrato de escena: la CapsuleShape3D de CollisionShape3D lleva
## `resource_local_to_scene` en Player.tscn porque _set_body_height() la
## modifica al derrapar; sin esa marca la comparten todas las instancias y
## el derrape encoge a toda la party.

## Puntos de la partida (por jugador, se reinician cada partida): se ganan
## por baja y se gastan en cofres, ruletas y manantiales.
signal points_changed(total: int)
## Se emite al EMPEZAR un derrape, con su dirección; lo escucha el
## Cinturón eléctrico (ItemBag).
signal slide_started(direction: Vector3)

## Modos de cámara que rota la acción "camera_mode" de cada jugador:
## THIRD_PERSON (por defecto; la vista gira el cuerpo), FIRST_PERSON (brazo
## en los ojos y la foca propia oculta) y FREE_ORBIT (la cámara orbita y el
## cuerpo mira hacia donde camina; las armas apuntan solas).
enum CameraMode { THIRD_PERSON, FIRST_PERSON, FREE_ORBIT }

## Fracción de la velocidad efectiva que el cuerpo ya debe llevar para
## empezar un derrape (no se derrapa desde quieto).
const SLIDE_MIN_SPEED_RATIO: float = 0.5

## Dónde queda un caído rescatado del vacío respecto de su compañero: al
## lado y no encima, para que la física no empuje a ninguno de los dos.
const RESCUE_MATE_OFFSET := Vector3(1.5, 0.5, 0.0)

## Capa visual del rig por slot: RIG_LAYER_BASE + slot + 1 en vez de la
## capa 1, para que la cámara en primera persona oculte solo su propio
## cuerpo y los compañeros lo sigan viendo.
const RIG_LAYER_BASE: int = 10

## Cartel de rescate: las medidas del cartel de los interactuables
## (interactable.gd), más arriba del cuerpo caído.
const PROMPT_FONT_SIZE: int = 52
const PROMPT_OUTLINE_SIZE: int = 14
const PROMPT_HEIGHT: float = 2.6
## Centinela de "el cartel nunca se pintó", distinto de "nadie lo revive" (-1).
const PROMPT_PCT_UNSET: int = -2

## Textos del toast de mascota; los dos llevan el nombre (%s) para que un
## cambio se lea como cambio y no como regalo.
const PET_JOINS: String = "%s se une"
const PET_LEAVES: String = "%s se despide"

## Puntos caminables que se prueban al terminar Vuelo sobre una celda
## bloqueada; gana el más cercano. Cada uno saca números del RNG de la
## arena: cambiar la cantidad cambia las partidas con semilla.
const FLIGHT_LANDING_SAMPLES: int = 24
## Altura sobre el terreno, en metros, desde la que cae el raider al
## aterrizar, para que se asiente sin empezar dentro del suelo.
const FLIGHT_LANDING_CLEARANCE: float = 1.2
## Margen respecto del borde de la arena mientras vuela, en metros.
const FLIGHT_EDGE_MARGIN: float = 2.0

@export_group("Movimiento")
## Velocidad base al caminar, en metros por segundo; tomos y objetos la multiplican.
@export var move_speed: float = 8.6
## Aceleración en el suelo, en metros por segundo cada segundo.
@export var acceleration: float = 40.0
## Aceleración en el aire, en metros por segundo cada segundo.
@export var air_acceleration: float = 12.0
## Velocidad vertical al saltar, en metros por segundo.
@export var jump_velocity: float = 8.7
@export_group("Vuelo (power-up)")
## Vuelo: velocidad de subida mientras se mantiene saltar, en metros por segundo.
@export var flight_rise_speed: float = 9.0
## Vuelo: techo sobre el terreno bajo el raider, en metros (pasa mesetas y rocas, la cámara aún ve el suelo).
@export var flight_ceiling: float = 12.0
## Vuelo: velocidad de descenso al soltar saltar, en metros por segundo (un planeo, no una caída).
@export var flight_fall_speed: float = 4.0

@export_group("Derrape")
## Multiplicador de la velocidad efectiva durante el derrape.
@export var slide_speed_multiplier: float = 2.21
## Duración del derrape, en segundos.
@export var slide_duration: float = 0.3
## Espera entre un derrape y el siguiente, en segundos.
@export var slide_cooldown: float = 0.8
## Altura de la cápsula durante el derrape, en metros.
@export var slide_collision_height: float = 0.9

@export_group("Inventario")
## Tope de armas simultáneas; al llegar, el pool deja de ofrecer armas nuevas (upgrade_pool.gd lo lee por nombre).
@export var max_weapons: int = 3
## Tope de tomos distintos; al llegar, el pool solo ofrece más niveles de los que ya tiene (upgrade_pool.gd lo lee por nombre).
@export var max_tomes: int = 3

@export_group("Seguridad")
## Altura del mundo (Y, en metros) bajo la cual el raider vuelve a suelo seguro sin daño.
@export var void_rescue_y: float = -10.0

@export_group("Cámara")
## Sensibilidad base del mouse, en radianes por píxel; el ajuste de opciones la multiplica.
@export var mouse_sensitivity: float = 0.003
## Inclinación inicial de la cámara, en grados (negativo mira hacia abajo).
@export var initial_pitch_deg: float = -20.0
## Inclinación mínima en tercera persona y órbita libre, en grados.
@export var min_pitch_deg: float = -80.0
## Inclinación máxima en tercera persona y órbita libre, en grados.
@export var max_pitch_deg: float = 10.0
## Inclinación mínima en primera persona, en grados.
@export var first_person_min_pitch_deg: float = -85.0
## Inclinación máxima en primera persona, en grados.
@export var first_person_max_pitch_deg: float = 85.0
## Distancia mínima de la cámara en órbita libre, en metros.
@export var free_orbit_min_distance: float = 2.5
## Distancia máxima de la cámara en órbita libre, en metros.
@export var free_orbit_max_distance: float = 11.0
## Cuánto acerca o aleja cada paso de zoom en órbita libre (rueda o cruceta), en metros.
@export var free_orbit_zoom_step: float = 1.0
## Rapidez con que el cuerpo gira hacia donde camina en órbita libre, por segundo.
@export var free_orbit_turn_speed: float = 10.0

@export_group("Co-op")
## Slot del jugador (0-3): decide qué dispositivo lo controla; RunSystems asigna 1+ a los cuerpos extra.
@export var player_index: int = 0
## Radio de rescate, en metros; arena_probe.gd se acerca a 2 m para revivir.
@export var revive_radius: float = 3.0
## Segundos que un compañero debe mantener Interactuar para revivir.
@export var revive_time: float = 3.0
## Fracción de la vida máxima con que vuelve el revivido (0-1).
@export var revive_heal_fraction: float = 0.5
## Progreso de rescate que se pierde por segundo sin nadie ayudando (0-1 por segundo).
@export var revive_decay_rate: float = 0.5

## Interruptor de prueba (ArenaProbe, BONK_WEAPON): id del arma con que
## empieza el raider en vez de la de su personaje. Pasa por el mismo camino
## de entrega (el node_name que cuenta el pool y el contador used_weapon_).
static var starting_weapon_override: String = ""

## Puntos actuales de la partida; otros scripts los leen con get("points").
var points: int = 0

## Mascota que sigue al raider ("" = ninguna). Hay un solo espacio: una
## nueva reemplaza a la anterior, arma y stat incluidos. Solo la dan la caja
## de mascotas y el traficante de animales, nunca un cofre ni la ruleta.
var pet_id: String = ""

@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var seal_rig: SealRig = $SealRig
@onready var weapons_mount: Node3D = $Weapons
@onready var health: Health = $Health
@onready var _stats: PlayerStats = $Stats
@onready var item_bag: ItemBag = $ItemBag

## Multiplicadores de puntos con nombre (Fiebre del oro, Lluvia dorada): el
## total es su PRODUCTO, así dos fuentes activas a la vez se componen.
var _points_sources: Dictionary[String, float] = {}

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _default_collision_height: float = 1.8
var _default_collision_radius: float = 0.4

var _yaw: float = 0.0
var _pitch: float = 0.0

var _camera_mode: CameraMode = CameraMode.THIRD_PERSON
## Órbita libre: giro de la cámara en el mundo (separado del cuerpo) y
## distancia actual (_ready la toma del largo del brazo en la escena).
var _orbit_yaw: float = 0.0
var _orbit_distance: float = 0.0
## Largo del brazo en tercera persona según la escena; se restaura al volver a ese modo.
var _third_person_arm_length: float = 5.0

## Nombres de las acciones de este slot, resueltos una vez en _ready:
## Coop.action() arma un String por llamada, y esto se lee varias veces por
## tick y por cada evento de mouse.
var _actions: Dictionary[StringName, StringName] = {}

var _is_sliding: bool = false
var _slide_timer: float = 0.0
var _slide_cooldown_timer: float = 0.0
var _slide_direction: Vector3 = Vector3.ZERO

# Tiempo restante de un enraizamiento externo (Entomb): sin moverse, saltar ni derrapar.
var _root_timer: float = 0.0
## Saltos que quedan antes de volver a pisar suelo: 1 más
## PlayerStats.extra_jumps, recargados cada frame en el suelo. Empieza en 1
## para que un raider que aparece en el aire pueda saltar una vez.
var _jumps_left: int = 1

var _is_dead: bool = false

## Co-op: el cuerpo queda en el suelo sin control ni armas hasta que un
## compañero lo revive (ver _tick_downed). Nunca es true en solo.
var _is_downed: bool = false
var _revive_progress: float = 0.0
var _revive_prompt: Label3D = null
var _saved_collision_layer: int = 0
## Último porcentaje entero pintado en el cartel (ver _update_revive_prompt).
var _last_prompt_pct: int = PROMPT_PCT_UNSET

## Punto de inicio de la etapa: el rescate del vacío devuelve aquí al raider.
var _spawn_position: Vector3 = Vector3.ZERO


## Cambia la mascota: libera el nodo Pet anterior, crea el nuevo, avisa los
## dos cambios con el toast de botín y recalcula los stats, que leen
## `pet_id`. Con "" solo vacía el espacio.
func set_pet(new_pet_id: String) -> void:
	if new_pet_id == pet_id:
		return
	var leaving := PetCatalog.by_id(pet_id)
	# Por TIPO y no por nombre: queue_free deja el nodo como hijo hasta el
	# final del frame, y con dos set_pet en el mismo frame add_child
	# renombraría la mascota nueva y quedarían dos siguiendo al raider.
	for child: Node in get_children():
		var old_pet := child as Pet
		if old_pet != null:
			old_pet.queue_free()
	pet_id = new_pet_id
	if not leaving.is_empty():
		_announce_pet(PET_LEAVES % String(leaving.display_name),
				PetCatalog.weapon_display_name(leaving), leaving)
	if not pet_id.is_empty():
		var row := PetCatalog.by_id(pet_id)
		if row.is_empty():
			push_warning("Player: unknown pet '%s'" % pet_id)
			pet_id = ""
		else:
			var pet := Pet.new()
			pet.setup(row)
			add_child(pet)
			_announce_pet(PET_JOINS % String(row.display_name),
					String(row.get("stat_label", "")), row)
			# Log de una línea. Va aquí y no en los vendedores: es la única
			# puerta de entrada de una mascota.
			print("Pet joined: %s" % pet_id)
	var stats := PlayerStats.find_in(self)
	if stats != null:
		stats.recompute()


func _announce_pet(title: String, description: String, row: Dictionary) -> void:
	get_tree().call_group("hud", "show_loot", title, description,
			row.get("color", Color.WHITE) as Color, player_index)


## Multiplicador total de puntos: producto de todas las fuentes activas.
func points_multiplier() -> float:
	var factor := 1.0
	for source_id: String in _points_sources:
		factor *= _points_sources[source_id]
	return factor


## Activa o actualiza una fuente de multiplicador (PowerUps y WorldDirector la llaman por nombre).
func set_points_source(source_id: String, multiplier: float) -> void:
	_points_sources[source_id] = multiplier


## Quita una fuente de multiplicador.
func clear_points_source(source_id: String) -> void:
	_points_sources.erase(source_id)


## Suma puntos con el multiplicador actual.
func add_points(amount: int) -> void:
	if amount <= 0:
		return
	# Redondea hacia arriba: un x1.5 sobre una baja de 1 punto paga 2, no 1.
	points += ceili(float(amount) * points_multiplier())
	points_changed.emit(points)


## Descuenta si alcanza y devuelve true; si no alcanza, false sin cambiar nada.
func spend_points(amount: int) -> bool:
	if amount <= 0:
		# Precio 0 es gratis (true). Un precio negativo es un error del
		# llamador y se rechaza: si no, PAGARÍA al jugador.
		return amount == 0
	if amount > points:
		return false
	points -= amount
	points_changed.emit(points)
	return true


func _ready() -> void:
	# Marcador de mapa: los raiders siempre se ven en el mapa, con niebla o
	# sin ella.
	add_to_group(&"map_markers")
	_spawn_position = global_position
	_cache_slot_actions()
	_apply_character(CharacterCatalog.by_id_or_default(Coop.character_for_slot(player_index)))
	health.died.connect(_on_health_died)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# El brazo de la cámara ignora la cápsula propia; si no, acerca la cámara.
	spring_arm.add_excluded_object(get_rid())
	# ...y la de cada compañero: los raiders comparten la capa 1 con el mundo.
	# Diferido porque RunSystems crea los slots 1+ después de este _ready.
	_exclude_party_from_spring_arm.call_deferred()
	if Coop.is_coop():
		# En pantalla dividida pintan las cámaras de cada viewport; esta solo
		# les presta su transformación.
		($SpringArm3D/Camera3D as Camera3D).current = false
	var capsule := collision_shape.shape as CapsuleShape3D
	if capsule != null:
		_default_collision_height = capsule.height
		_default_collision_radius = capsule.radius
	_yaw = rotation.y
	_pitch = deg_to_rad(clamp(initial_pitch_deg, min_pitch_deg, max_pitch_deg))
	spring_arm.rotation.x = _pitch
	_third_person_arm_length = spring_arm.spring_length
	_orbit_distance = clampf(_third_person_arm_length,
			free_orbit_min_distance, free_orbit_max_distance)
	# Cada malla del rig pasa de la capa 1 a la capa visual del slot (ver
	# RIG_LAYER_BASE), que todas las cámaras ven salvo la propia en primera persona.
	_apply_rig_layer(seal_rig)
	# Lo que se cuelgue del rig después (efectos, accesorios) también recibe
	# la capa; si no, su dueño lo vería flotando en primera persona.
	seal_rig.child_entered_tree.connect(_apply_rig_layer)


## Resuelve una vez los nombres de acción de este slot (ver _actions).
func _cache_slot_actions() -> void:
	for base: StringName in Coop.BASE_ACTIONS:
		_actions[base] = Coop.action(player_index, base)


## Las cápsulas de los compañeros no bloquean el brazo de la cámara.
func _exclude_party_from_spring_arm() -> void:
	for node: Node in get_tree().get_nodes_in_group("player"):
		var mate := node as Player
		if mate != null and mate != self:
			spring_arm.add_excluded_object(mate.get_rid())


## Capa visual del cuerpo propio de este slot (ver RIG_LAYER_BASE).
func rig_visual_layer() -> int:
	return 1 << (RIG_LAYER_BASE + player_index)


## Pasa `root` y todo lo que cuelga de él a la capa visual de este slot.
func _apply_rig_layer(root: Node) -> void:
	var layer := rig_visual_layer()
	var self_visual := root as VisualInstance3D
	if self_visual != null:
		self_visual.layers = layer
	for node: Node in root.find_children("*", "VisualInstance3D", true, false):
		(node as VisualInstance3D).layers = layer


## Nombre de una acción base para este slot ("interact" -> "p2_interact" en co-op).
func _act(base: StringName) -> StringName:
	return _actions.get(base, base)


## Acción de interactuar de este slot; los interactuables la piden por nombre.
func interact_action() -> StringName:
	return _act(&"interact")


## True si este cuerpo usa el mouse: siempre en solo; en co-op, solo el
## slot del teclado.
func _owns_mouse() -> bool:
	return not Coop.is_coop() or Coop.device_for_slot(player_index) == Coop.KEYBOARD_DEVICE


func _unhandled_input(event: InputEvent) -> void:
	if _is_dead:
		return
	# Caído conserva la vista (mirar la pelea y ver llegar al rescatador),
	# pero no el cambio de modo ni el zoom: cambiar de modo gira el cuerpo.
	if not _is_downed:
		# Por eventos, así la rueda del mouse y los botones del pad entran
		# igual, ya filtrados por slot en el set de acciones.
		if event.is_action_pressed(_act(&"camera_mode")):
			_cycle_camera_mode()
			return
		if _camera_mode == CameraMode.FREE_ORBIT:
			if event.is_action_pressed(_act(&"camera_zoom_in")):
				_set_orbit_distance(_orbit_distance - free_orbit_zoom_step)
				return
			if event.is_action_pressed(_act(&"camera_zoom_out")):
				_set_orbit_distance(_orbit_distance + free_orbit_zoom_step)
				return
	if not _owns_mouse():
		return
	# Esc es del PauseMenu (este nodo se pausa con el árbol). Un clic vuelve
	# a capturar el mouse si quedó libre durante la partida.
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_apply_look(event.relative)
	elif event is InputEventMouseButton and event.pressed \
			and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


## Vista con mouse: la sensibilidad de opciones (SaveData.mouse_sensitivity,
## multiplicador 0.3-2.0) escala la base exportada en cada evento. En
## primera y tercera persona el giro mueve el cuerpo; en órbita libre, solo
## la cámara.
func _apply_look(relative: Vector2) -> void:
	var sensitivity: float = mouse_sensitivity * SaveData.mouse_sensitivity
	var wide := _camera_mode == CameraMode.FIRST_PERSON
	_pitch = clamp(_pitch - relative.y * sensitivity,
			deg_to_rad(first_person_min_pitch_deg if wide else min_pitch_deg),
			deg_to_rad(first_person_max_pitch_deg if wide else max_pitch_deg))
	spring_arm.rotation.x = _pitch
	if _camera_mode == CameraMode.FREE_ORBIT:
		_orbit_yaw = wrapf(_orbit_yaw - relative.x * sensitivity, -PI, PI)
	else:
		# Se envuelve igual que la órbita: sin esto el ángulo crece sin límite
		# y la precisión de float32 vuelve escalonado el giro lento.
		_yaw = wrapf(_yaw - relative.x * sensitivity, -PI, PI)
		rotation.y = _yaw


## Un tick de física en pasos con nombre. El orden importa: temporizadores
## y rescate del vacío corren en TODO estado, la vista corre antes del corte
## de caído (el caído sigue mirando) y solo el movimiento exige estar en pie.
func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	_rescue_from_void()

	# Vuelo manda en el eje vertical mientras dura: con gravedad, la subida y
	# la caída se equilibrarían a una altura cualquiera.
	if _tick_flight(delta):
		pass
	elif not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		# Pisar suelo recarga los saltos. Se recarga aquí y no en _try_jump
		# para que quien cae de un borde conserve sus saltos en el aire.
		_jumps_left = _max_jumps()

	_apply_stick_look(delta)

	if _is_downed:
		# Caído: solo gravedad y la cuenta del rescate.
		velocity.x = 0.0
		velocity.z = 0.0
		_pin_orbit_arm()
		move_and_slide()
		_tick_downed(delta)
		return

	# Tomos y objetos escalan la velocidad base exportada.
	var effective_speed: float = move_speed * _stats.move_speed_multiplier
	var wish_dir := _read_wish_dir()
	_face_movement(wish_dir, delta)
	_pin_orbit_arm()
	_update_slide(delta, wish_dir, effective_speed)
	_apply_horizontal_velocity(delta, wish_dir, effective_speed)
	_try_jump()
	move_and_slide()


## Temporizadores que bajan en TODO estado. Sobre todo el enraizamiento:
## Sarcognato enraíza y daña en la misma llamada, y si se congelara al caer,
## el revivido volvería con 3 s de enraizamiento nuevos.
func _tick_timers(delta: float) -> void:
	_root_timer = maxf(_root_timer - delta, 0.0)
	_slide_cooldown_timer = maxf(_slide_cooldown_timer - delta, 0.0)


## Guarda la posición actual como punto de rescate del vacío.
## RunSystems.place_party la llama en cada cambio de etapa: el punto que se
## tomó en _ready pertenece a un mapa que ya no existe.
func anchor_here() -> void:
	_spawn_position = global_position


## Rescate del vacío, además de los muros del perímetro: un cuerpo que se
## coló por un hueco vuelve a suelo firme sin derrape ni enraizamiento. Un
## caído va junto al compañero en pie más cercano y no a su inicio, que
## puede estar a 100 m y nadie lo encontraría para revivirlo.
func _rescue_from_void() -> void:
	if global_position.y >= void_rescue_y:
		return
	var destination := _spawn_position
	if _is_downed:
		var mate := Coop.nearest_player(get_tree(), global_position)
		if mate != null:
			destination = mate.global_position + RESCUE_MATE_OFFSET
	global_position = destination
	velocity = Vector3.ZERO
	if _is_sliding:
		_end_slide()
	_root_timer = 0.0
	# Log de una línea: un soak que atraviesa el suelo deja rastro.
	print("Void rescue: p%d at %.1fs" % [player_index, RunState.run_time])


## Stick derecho (el pad asignado en co-op; cualquiera en solo) por el
## mismo camino que el mouse. Dividir por la sensibilidad base pasa de
## radianes por segundo a las unidades de _apply_look, así el ajuste de
## sensibilidad escala igual al pad.
func _apply_stick_look(delta: float) -> void:
	var stick := Coop.look_vector(player_index)
	if stick == Vector2.ZERO:
		return
	_apply_look(stick * Coop.LOOK_SPEED * delta / maxf(mouse_sensitivity, 0.0001))


## Dirección deseada de este tick, plana y normalizada. En primera y
## tercera persona es relativa al cuerpo (su giro es el de la vista); en
## órbita libre es relativa a la CÁMARA y el cuerpo gira hacia donde camina.
func _read_wish_dir() -> Vector3:
	if is_rooted():
		return Vector3.ZERO
	var input_dir: Vector2 = Input.get_vector(_act(&"move_left"), _act(&"move_right"),
			_act(&"move_forward"), _act(&"move_back"))
	var move_basis := Basis(Vector3.UP, _orbit_yaw) \
			if _camera_mode == CameraMode.FREE_ORBIT else transform.basis
	var wish_dir: Vector3 = move_basis * Vector3(input_dir.x, 0.0, input_dir.y)
	wish_dir.y = 0.0
	return wish_dir.normalized() if wish_dir.length_squared() > 0.0 else Vector3.ZERO


## Solo órbita libre: el cuerpo gira hacia su dirección de movimiento.
func _face_movement(wish_dir: Vector3, delta: float) -> void:
	if _camera_mode != CameraMode.FREE_ORBIT or wish_dir == Vector3.ZERO:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-wish_dir.x, -wish_dir.z),
			minf(free_orbit_turn_speed * delta, 1.0))


## Mantiene el giro del brazo en el MUNDO igual al de la órbita aunque el
## cuerpo gire (el giro del brazo es relativo al cuerpo). También corre
## caído, para que la vista siga moviendo la cámara en órbita libre.
func _pin_orbit_arm() -> void:
	if _camera_mode == CameraMode.FREE_ORBIT:
		spring_arm.rotation.y = wrapf(_orbit_yaw - rotation.y, -PI, PI)


func _update_slide(delta: float, wish_dir: Vector3, effective_speed: float) -> void:
	if _is_sliding:
		_slide_timer -= delta
		if _slide_timer <= 0.0 or not is_on_floor():
			_end_slide()
	elif _can_start_slide(wish_dir, effective_speed):
		_start_slide(wish_dir)


func _apply_horizontal_velocity(delta: float, wish_dir: Vector3,
		effective_speed: float) -> void:
	if is_rooted():
		# Freno en seco, sin desacelerar: el enraizado se planta al instante.
		velocity.x = 0.0
		velocity.z = 0.0
	elif _is_sliding:
		var slide_velocity: Vector3 = _slide_direction * effective_speed * slide_speed_multiplier
		velocity.x = slide_velocity.x
		velocity.z = slide_velocity.z
	else:
		var target: Vector3 = wish_dir * effective_speed
		var accel: float = acceleration if is_on_floor() else air_acceleration
		velocity.x = move_toward(velocity.x, target.x, accel * delta)
		velocity.z = move_toward(velocity.z, target.z, accel * delta)


func _try_jump() -> void:
	if not Input.is_action_just_pressed(_act(&"jump")) or is_rooted():
		return
	# Multisalto: el del suelo más PlayerStats.extra_jumps en el aire; se
	# recargan al pisar suelo (ver _physics_process).
	if _jumps_left <= 0:
		return
	_jumps_left -= 1
	if _is_sliding:
		_end_slide()
	velocity.y = jump_velocity


# --- Vuelo (power-up) --------------------------------------------------------

## Movimiento vertical durante Vuelo; devuelve true si tomó el frame (el
## llamador no aplica gravedad). Mantener saltar sube hasta un techo medido
## SOBRE EL TERRENO (una Y fija enterraría al raider en una loma de un mapa
## y lo dejaría en el cielo en otro); soltar planea hacia abajo. Pisar
## suelo sigue recargando los saltos.
func _tick_flight(delta: float) -> bool:
	var powerups := PowerUps.find_in(self)
	if powerups == null or not powerups.has("flight") or _is_downed:
		return false
	if is_on_floor():
		_jumps_left = _max_jumps()
	var ceiling := _ground_height() + flight_ceiling
	if Input.is_action_pressed(_act(&"jump")) and global_position.y < ceiling:
		velocity.y = flight_rise_speed
	elif global_position.y >= ceiling:
		# Se queda en el techo en vez de rebotar.
		velocity.y = minf(velocity.y, 0.0)
	elif not is_on_floor():
		velocity.y = -flight_fall_speed
	else:
		velocity.y = 0.0
	# El borde de la arena es un muro para quien camina y nada para quien
	# vuela: sin esto se podría salir volando sobre el vacío.
	var limit := _arena_limit()
	if limit > 0.0:
		global_position.x = clampf(global_position.x, -limit, limit)
		global_position.z = clampf(global_position.z, -limit, limit)
	return true


## PowerUps la llama por nombre cuando termina Vuelo. Si el raider quedó
## sobre una celda bloqueada (el único lugar garantizado como NO caminable,
## y el que vigila el probe), lo baja al punto caminable más cercano.
func end_flight() -> void:
	var bounds := get_tree().get_first_node_in_group("arena_bounds")
	if bounds == null or not bounds.has_method("is_walkable"):
		return
	var here := Vector2(global_position.x, global_position.z)
	if bool(bounds.call("is_walkable", here)):
		return
	var best := here
	var best_distance := INF
	if bounds.has_method("random_walkable_point"):
		for attempt in FLIGHT_LANDING_SAMPLES:
			var candidate: Variant = bounds.call("random_walkable_point")
			if candidate is not Vector2:
				continue
			var distance := (candidate as Vector2).distance_squared_to(here)
			if distance < best_distance:
				best_distance = distance
				best = candidate
	if best == here:
		return
	global_position.x = best.x
	global_position.z = best.y
	var terrain := Terrain.find(get_tree())
	if terrain != null:
		global_position.y = terrain.height_at(best.x, best.y) + FLIGHT_LANDING_CLEARANCE
	velocity = Vector3.ZERO
	print("Flight landing: p%d moved to walkable ground" % player_index)


## Altura del terreno bajo el raider, para el techo de Vuelo.
func _ground_height() -> float:
	var terrain := Terrain.find(get_tree())
	return terrain.height_at(global_position.x, global_position.z) if terrain != null else 0.0


## Media extensión a la que se limita el vuelo, o 0 si la arena no la publica.
func _arena_limit() -> float:
	var bounds := get_tree().get_first_node_in_group("arena_bounds")
	if bounds == null:
		return 0.0
	var extent: Variant = bounds.get("arena_half_extent")
	if extent is not float and extent is not int:
		return 0.0
	return float(extent) - FLIGHT_EDGE_MARGIN


## Saltos disponibles desde el suelo: el del suelo más los que dan los stats.
func _max_jumps() -> int:
	var stats := PlayerStats.find_in(self)
	return 1 + (stats.extra_jumps if stats != null else 0)


## Enraizamiento externo (el Entomb de Sarcognato): bloquea movimiento,
## salto y derrape por `duration` segundos; las armas siguen disparando y la
## cámara queda libre. Reaplicarlo extiende el bloqueo, nunca lo acorta.
func apply_root(duration: float) -> void:
	if _is_dead or duration <= 0.0:
		return
	if _is_sliding:
		_end_slide()
	_root_timer = maxf(_root_timer, duration)


func is_rooted() -> bool:
	return _root_timer > 0.0


## Aplica una fila de CharacterCatalog: crea el arma inicial bajo el montaje
## Weapons, cambia el modelo del cuerpo (la foca por defecto), lo tiñe y
## registra la pasiva.
func _apply_character(character: Dictionary) -> void:
	var row := character
	if not starting_weapon_override.is_empty():
		var forced := UpgradePool.weapon_by_id(starting_weapon_override)
		if forced.is_empty():
			push_error("Player: unknown BONK_WEAPON '%s'" % starting_weapon_override)
		else:
			row = character.duplicate()
			row["weapon_scene"] = String(forced.scene)
			row["weapon_node_name"] = String(forced.node_name)
			row["weapon_display_name"] = String(forced.display_name)
	character = row
	var scene := load(String(character.weapon_scene)) as PackedScene
	if scene == null:
		push_warning("Player: bad starting weapon scene '%s'" % character.weapon_scene)
	else:
		var weapon := scene.instantiate() as Node3D
		# El nombre debe coincidir con el node_name de WEAPON_LIBRARY para que
		# el pool de mejoras cuente el arma inicial como propia.
		weapon.name = String(character.weapon_node_name)
		weapons_mount.add_child(weapon)
		# Colección: el arma inicial también cuenta como usada.
		var weapon_id := UpgradePool.weapon_id_for_node(String(character.weapon_node_name))
		if not weapon_id.is_empty():
			SaveData.bump("used_weapon_" + weapon_id)
	# Modelo del cuerpo: datos opcionales de la fila, con la foca por defecto
	# (SealRig.setup). El tinte va DESPUÉS porque setup reinicia el material.
	seal_rig.setup(String(character.get("model_scene", "")),
			float(character.get("model_scale", 1.0)),
			String(character.get("tint_material_prefix", "")))
	# SealRig duplica el material compartido del modelo una vez por raider.
	seal_rig.apply_tint(Color(character.tint))
	_stats.set_character_passive(String(character.passive_stat),
			float(character.passive_amount),
			String(character.get("passive_kind", "per_level")),
			float(character.get("passive_base", 0.0)))


func _on_health_died() -> void:
	if _is_dead or _is_downed:
		return
	if _is_sliding:
		_end_slide()
	if Coop.is_coop():
		# Co-op: el raider queda CAÍDO en vez de terminar la partida y un
		# compañero puede revivirlo. RunManager declara la derrota solo cuando
		# toda la party está caída a la vez.
		_enter_downed()
		return
	_is_dead = true
	# Congela control y física; RunManager pausa el árbol justo después. La
	# caída del rig ignora la pausa y se ve bajo la pantalla de fin.
	set_physics_process(false)
	seal_rig.play_death()


# --- Modos de cámara ---------------------------------------------------------

func _cycle_camera_mode() -> void:
	var was_free := _camera_mode == CameraMode.FREE_ORBIT
	_camera_mode = ((int(_camera_mode) + 1) % CameraMode.size()) as CameraMode
	_apply_camera_mode(was_free)


func camera_mode() -> CameraMode:
	return _camera_mode


## Camera3D propia de este raider. En co-op ninguna es la cámara activa del
## viewport (SplitScreen pinta cada una en su SubViewport), así que lo que
## actúa sobre una cámara (FOV, sacudida) debe recibir esta.
func view_camera() -> Camera3D:
	return spring_arm.get_node_or_null("Camera3D") as Camera3D


func _apply_camera_mode(was_free: bool = false) -> void:
	var camera := view_camera()
	var rig_bit := rig_visual_layer()
	# Cada cambio de modo reinicia el estado transitorio; luego el modo pone el suyo.
	camera.cull_mask |= rig_bit
	spring_arm.rotation.y = 0.0
	if was_free:
		# De órbita libre a un modo atado al cuerpo: el giro de la cámara pasa
		# a ser el del cuerpo, así la vista no salta.
		_yaw = wrapf(_orbit_yaw, -PI, PI)
		rotation.y = _yaw
	match _camera_mode:
		CameraMode.THIRD_PERSON:
			spring_arm.spring_length = _third_person_arm_length
		CameraMode.FIRST_PERSON:
			# Brazo en los ojos; la foca propia se oculta SOLO para esta
			# cámara (el rig está en la capa visual del slot).
			spring_arm.spring_length = 0.05
			camera.cull_mask &= ~rig_bit
		CameraMode.FREE_ORBIT:
			_orbit_yaw = _yaw
			spring_arm.spring_length = _orbit_distance
	# Vuelve a acotar la inclinación al rango del modo (primera persona permite más).
	var wide := _camera_mode == CameraMode.FIRST_PERSON
	_pitch = clamp(_pitch,
			deg_to_rad(first_person_min_pitch_deg if wide else min_pitch_deg),
			deg_to_rad(first_person_max_pitch_deg if wide else max_pitch_deg))
	spring_arm.rotation.x = _pitch


func _set_orbit_distance(distance: float) -> void:
	_orbit_distance = clampf(distance, free_orbit_min_distance, free_orbit_max_distance)
	if _camera_mode == CameraMode.FREE_ORBIT:
		spring_arm.spring_length = _orbit_distance


# --- Co-op: caído y rescate --------------------------------------------------

## Las cinco cosas que cambian juntas al caer o levantarse: grupo (todo el
## targeting usa "player"), colisión fantasma, armas, la caída del rig y el
## cartel flotante. Juntas aquí para que los dos caminos no se separen.
func _set_downed(down: bool) -> void:
	_is_downed = down
	_revive_progress = 0.0
	if down:
		# Fuera del grupo "player", todo sistema que apunta (enemigos, imán
		# de gemas, interactuables, el conteo de vivos de RunManager) ignora
		# este cuerpo sin chequeos extra; revivir lo devuelve.
		remove_from_group("player")
		add_to_group("downed_players")
		# Limpiar ANTES de detener el montaje: un arma que deja campos con
		# tiempo (charcos de sangre o de baba) los avanza en su propio
		# _physics_process, y congelada los dejaría en el suelo sin fin.
		_clear_weapon_fields()
		# Las armas dejan de disparar con el cuerpo (los hijos del montaje
		# procesan física).
		weapons_mount.process_mode = Node.PROCESS_MODE_DISABLED
		# Colisión fantasma: el cuerpo no bloquea a compañeros ni a la horda.
		_saved_collision_layer = collision_layer
		collision_layer = 0
		seal_rig.play_death()
		# Si cayó toda la party, RunManager termina la partida en este mismo
		# frame y pausa el árbol: un cartel mostrado ahora quedaría encima de
		# la pantalla de fin (es no_depth_test).
		if not get_tree().get_nodes_in_group("player").is_empty():
			_show_revive_prompt()
	else:
		remove_from_group("downed_players")
		add_to_group("player")
		weapons_mount.process_mode = Node.PROCESS_MODE_INHERIT
		collision_layer = _saved_collision_layer
		seal_rig.reset_death()
		_hide_revive_prompt()


## Pide a cada arma con campos en el suelo que los suelte. Parte opcional
## del contrato: el arma que deja campos expone clear_weapon_fields().
func _clear_weapon_fields() -> void:
	for weapon: Node in weapons_mount.get_children():
		if weapon.has_method("clear_weapon_fields"):
			weapon.call("clear_weapon_fields")


func _enter_downed() -> void:
	# Un Entomb que llegó con el golpe final (Sarcognato enraíza y daña a la
	# vez) no dura más que la caída: el revivido vuelve pudiendo moverse.
	_root_timer = 0.0
	_set_downed(true)


func is_downed() -> bool:
	return _is_downed


## Mientras está caído: un compañero en pie dentro de revive_radius que
## mantiene SU acción de interactuar llena la barra; soltar la vacía despacio.
func _tick_downed(delta: float) -> void:
	if not RunState.run_active:
		# La partida terminó (derrota total, extracción): se quita el cartel
		# para que no flote sobre la pantalla de fin.
		_hide_revive_prompt()
		return
	var rescuing := false
	# Se guarda QUIÉN rescata: el log lo nombra, y así el soak distingue un
	# rescate real de un raider que volvió solo.
	var rescuer: Player = null
	for node: Node in get_tree().get_nodes_in_group("player"):
		var mate := node as Player
		if mate == null or not mate.is_inside_tree():
			continue
		if global_position.distance_to(mate.global_position) > revive_radius:
			continue
		if Input.is_action_pressed(mate.interact_action()):
			rescuing = true
			rescuer = mate
			break
	if rescuing:
		# Protegido: con revive_time = 0 todo caído se levantaría en el
		# primer frame de contacto.
		_revive_progress += delta / maxf(revive_time, 0.01)
		if _revive_progress >= 1.0:
			_revive(rescuer)
			return
	else:
		_revive_progress = maxf(_revive_progress - revive_decay_rate * delta, 0.0)
	_update_revive_prompt(rescuing)


func _revive(rescuer: Player = null) -> void:
	_set_downed(false)
	health.revive(revive_heal_fraction)
	Juice.sparkle(global_position + Vector3.UP * 1.0)
	Sfx.play(&"heal")
	# Log de una línea: ningún soak en solo llega a caer y revivir, y
	# tools/verificar.sh cuenta las líneas "Player revived:".
	print("Player revived: p%d by p%d" % [
			player_index, rescuer.player_index if rescuer != null else -1])


## Cartel flotante sobre el caído (el mismo esquema Label3D de los
## interactuables), que también muestra el progreso del rescate.
func _show_revive_prompt() -> void:
	if _revive_prompt == null:
		_revive_prompt = Label3D.new()
		_revive_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_revive_prompt.no_depth_test = true
		_revive_prompt.font_size = PROMPT_FONT_SIZE
		_revive_prompt.outline_size = PROMPT_OUTLINE_SIZE
		_revive_prompt.position = Vector3.UP * PROMPT_HEIGHT
		add_child(_revive_prompt)
	_revive_prompt.visible = true
	_last_prompt_pct = PROMPT_PCT_UNSET
	_update_revive_prompt(false)


func _update_revive_prompt(rescuing: bool) -> void:
	if _revive_prompt == null:
		return
	# El texto solo cambia por porcentaje entero (~33 pasos en todo el
	# rescate): los demás ticks no arman el String.
	var pct := roundi(_revive_progress * 100.0) if rescuing else -1
	if pct == _last_prompt_pct:
		return
	_last_prompt_pct = pct
	if rescuing:
		_revive_prompt.text = "Reviviendo... %d%%" % pct
		_revive_prompt.modulate = Color(0.5, 0.95, 0.6)
	else:
		_revive_prompt.text = "CAÍDO — mantén [Interactuar] cerca"
		_revive_prompt.modulate = Color(1.0, 0.42, 0.35)


func _hide_revive_prompt() -> void:
	if _revive_prompt != null:
		_revive_prompt.visible = false


func _can_start_slide(wish_dir: Vector3, effective_speed: float) -> bool:
	if not Input.is_action_pressed(_act(&"sprint")) or wish_dir == Vector3.ZERO:
		return false
	if not is_on_floor() or _slide_cooldown_timer > 0.0:
		return false
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	return horizontal_speed > effective_speed * SLIDE_MIN_SPEED_RATIO


func _start_slide(direction: Vector3) -> void:
	_is_sliding = true
	_slide_timer = slide_duration
	_slide_direction = direction
	_set_body_height(slide_collision_height)
	Juice.fov_kick_begin(view_camera())
	Sfx.play(&"slide")
	slide_started.emit(direction)


func _end_slide() -> void:
	_is_sliding = false
	_slide_cooldown_timer = slide_cooldown
	_set_body_height(_default_collision_height)
	Juice.fov_kick_end(view_camera())


func _set_body_height(height: float) -> void:
	var capsule := collision_shape.shape as CapsuleShape3D
	if capsule == null:
		return
	# Con una altura menor que 2 * radio, Godot achica el radio: se vuelve a
	# poner el radio original (acotado) para restaurar sin pérdida. Se puede
	# modificar porque Player.tscn marca la cápsula resource_local_to_scene.
	capsule.height = height
	capsule.radius = minf(_default_collision_radius, height * 0.5)
	collision_shape.position.y = height * 0.5
	# La foca se aplasta y baja la nariz junto con la cápsula.
	seal_rig.set_slide_ratio(height / _default_collision_height)


## Contrato de marcador de mapa (grupo "map_markers"): la flecha usa el giro
## de este cuerpo, que es hacia donde mira el raider.
func map_marker_kind() -> StringName:
	return &"player"
