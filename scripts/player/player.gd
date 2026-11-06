class_name Player
extends CharacterBody3D
## Raider de un jugador: movimiento relativo a la cámara, salto con
## multisalto, derrape (Shift + moverse), enraizamiento y rescate del vacío.
## Al aparecer aplica la fila de su personaje (CharacterCatalog): arma
## inicial, modelo del cuerpo con su tinte y pasiva por nivel.
##
## Cada parte vive en su nodo hijo de Player.tscn, con sus propios valores:
## SealRig (cuerpo visible), CameraRig (cámara y vista), Revive (caído y
## rescate en co-op, con el cartel RevivePrompt), Flight (power-up Vuelo),
## PetSlot (mascota), Wallet (puntos), además de Health, Stats, ItemBag,
## PowerUps y el montaje Weapons. Player decide el orden de cada tick y
## conserva los nombres que otros scripts llaman (add_points, set_pet,
## view_camera, end_flight…).
##
## Contrato de escena: la CapsuleShape3D de CollisionShape3D lleva
## `resource_local_to_scene` en Player.tscn porque _set_body_height() la
## modifica al derrapar; sin esa marca la comparten todas las instancias y
## el derrape encoge a toda la party.

## Cambiaron los puntos de la partida (reemite la del nodo Wallet); el HUD
## la conecta por nombre.
signal points_changed(total: int)
## Se emite al EMPEZAR un derrape, con su dirección; lo escucha el
## Cinturón eléctrico (ItemBag).
signal slide_started(direction: Vector3)

## Dónde queda un caído rescatado del vacío respecto de su compañero: al
## lado y no encima, para que la física no empuje a ninguno de los dos.
const RESCUE_MATE_OFFSET := Vector3(1.5, 0.5, 0.0)

@export_group("Movimiento")
## Velocidad base al caminar, en metros por segundo; tomos y objetos la multiplican.
@export var move_speed: float = 8.6
## Aceleración en el suelo, en metros por segundo cada segundo.
@export var acceleration: float = 40.0
## Aceleración en el aire, en metros por segundo cada segundo.
@export var air_acceleration: float = 12.0
## Velocidad vertical al saltar, en metros por segundo.
@export var jump_velocity: float = 8.7

@export_group("Derrape")
## Multiplicador de la velocidad efectiva durante el derrape.
@export var slide_speed_multiplier: float = 2.21
## Duración del derrape, en segundos.
@export var slide_duration: float = 0.3
## Espera entre un derrape y el siguiente, en segundos.
@export var slide_cooldown: float = 0.8
## Altura de la cápsula durante el derrape, en metros.
@export var slide_collision_height: float = 0.9
## Fracción de la velocidad efectiva que ya debe llevar el cuerpo para derrapar (0-1; no se derrapa desde quieto).
@export var slide_min_speed_ratio: float = 0.5

@export_group("Inventario")
## Tope de armas simultáneas; al llegar, el pool deja de ofrecer armas nuevas (upgrade_pool.gd lo lee por nombre).
@export var max_weapons: int = 3
## Tope de tomos distintos; al llegar, el pool solo ofrece más niveles de los que ya tiene (upgrade_pool.gd lo lee por nombre).
@export var max_tomes: int = 3

@export_group("Seguridad")
## Altura del mundo (Y, en metros) bajo la cual el raider vuelve a suelo seguro sin daño.
@export var void_rescue_y: float = -10.0

@export_group("Co-op")
## Slot del jugador (0-3): decide qué dispositivo lo controla; RunSystems asigna 1+ a los cuerpos extra.
@export var player_index: int = 0

## Interruptor de prueba (ArenaProbe, BONK_WEAPON): id del arma con que
## empieza el raider en vez de la de su personaje. Pasa por el mismo camino
## de entrega (el node_name que cuenta el pool y el contador used_weapon_).
static var starting_weapon_override: String = ""

## Puntos actuales de la partida (los guarda el nodo Wallet); otros scripts
## los leen con get("points").
var points: int:
	get:
		return _wallet.points if _wallet != null else 0
## Mascota que sigue al raider ("" = ninguna; la guarda el nodo PetSlot).
## Antes del _ready de Player vale "": PlayerStats ya la lee en el suyo.
var pet_id: String:
	get:
		return _pet_slot.pet_id if _pet_slot != null else ""
## Radio de rescate en metros (solo lectura; se edita en el nodo Revive).
var revive_radius: float:
	get:
		return _revive.revive_radius
## Segundos de Interactuar para revivir (solo lectura; se edita en el nodo Revive).
var revive_time: float:
	get:
		return _revive.revive_time

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var seal_rig: SealRig = $SealRig
@onready var weapons_mount: Node3D = $Weapons
@onready var health: Health = $Health
@onready var _stats: PlayerStats = $Stats
@onready var _camera: PlayerCamera = $CameraRig
@onready var _revive: PlayerRevive = $Revive
@onready var _flight: PlayerFlight = $Flight
@onready var _pet_slot: PetSlot = $PetSlot
@onready var _wallet: PlayerWallet = $Wallet

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _default_collision_height: float = 1.8
var _default_collision_radius: float = 0.4

## Nombres de las acciones de este slot, resueltos una vez en _ready:
## Coop.action() arma un String por llamada, y esto se lee varias veces por
## tick y por cada evento de mouse.
var _actions: Dictionary[StringName, StringName] = {}

var _is_sliding: bool = false
var _slide_timer: float = 0.0
var _slide_cooldown_timer: float = 0.0
var _slide_direction: Vector3 = Vector3.ZERO

## Tiempo restante de un enraizamiento externo (Entomb): sin moverse, saltar ni derrapar.
var _root_timer: float = 0.0
## Saltos que quedan antes de volver a pisar suelo: 1 más
## PlayerStats.extra_jumps, recargados cada frame en el suelo. Empieza en 1
## para que un raider que aparece en el aire pueda saltar una vez.
var _jumps_left: int = 1

var _is_dead: bool = false

## Punto de inicio de la etapa: el rescate del vacío devuelve aquí al raider.
var _spawn_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	# Marcador de mapa: los raiders siempre se ven en el mapa, con niebla o
	# sin ella.
	add_to_group(&"map_markers")
	_spawn_position = global_position
	_cache_slot_actions()
	_apply_character(CharacterCatalog.by_id_or_default(Coop.character_for_slot(player_index)))
	health.died.connect(_on_health_died)
	_wallet.points_changed.connect(_on_wallet_points_changed)
	# Después de _apply_character: la cámara pasa el modelo nuevo del rig a
	# la capa visual del slot.
	_camera.setup()
	var capsule := collision_shape.shape as CapsuleShape3D
	if capsule != null:
		_default_collision_height = capsule.height
		_default_collision_radius = capsule.radius


func _unhandled_input(event: InputEvent) -> void:
	if _is_dead:
		return
	_camera.handle_input(event, is_downed())


## Un tick de física en pasos con nombre. El orden importa: temporizadores
## y rescate del vacío corren en TODO estado, la vista corre antes del corte
## de caído (el caído sigue mirando) y solo el movimiento exige estar en pie.
func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	_rescue_from_void()

	# Vuelo manda en el eje vertical mientras dura: con gravedad, la subida y
	# la caída se equilibrarían a una altura cualquiera.
	var flying := _flight.tick()
	if is_on_floor():
		# Pisar suelo recarga los saltos, también volando. Se recarga aquí y
		# no en _try_jump para que quien cae de un borde conserve sus saltos.
		_jumps_left = _max_jumps()
	elif not flying:
		velocity.y -= _gravity * delta

	_camera.apply_stick_look(delta)

	if is_downed():
		# Caído: solo gravedad y la cuenta del rescate.
		velocity.x = 0.0
		velocity.z = 0.0
		_camera.pin_orbit_arm()
		move_and_slide()
		_revive.tick(delta)
		return

	# Tomos y objetos escalan la velocidad base exportada.
	var effective_speed: float = move_speed * _stats.move_speed_multiplier
	var wish_dir := _read_wish_dir()
	_camera.face_movement(wish_dir, delta)
	_camera.pin_orbit_arm()
	_update_slide(delta, wish_dir, effective_speed)
	_apply_horizontal_velocity(delta, wish_dir, effective_speed)
	_try_jump()
	move_and_slide()


## Nombre de una acción base para este slot ("interact" -> "p2_interact" en
## co-op); también lo usan los componentes del raider.
func slot_action(base: StringName) -> StringName:
	return _actions.get(base, base)


## Acción de interactuar de este slot; los interactuables la piden por nombre.
func interact_action() -> StringName:
	return slot_action(&"interact")


## Guarda la posición actual como punto de rescate del vacío.
## RunSystems.place_party la llama en cada cambio de etapa: el punto que se
## tomó en _ready pertenece a un mapa que ya no existe.
func anchor_here() -> void:
	_spawn_position = global_position


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


## Caído en co-op (lo lleva el nodo Revive).
func is_downed() -> bool:
	return _revive.is_downed()


func camera_mode() -> PlayerCamera.CameraMode:
	return _camera.camera_mode()


## Camera3D propia de este raider. En co-op ninguna es la cámara activa del
## viewport (SplitScreen pinta cada una en su SubViewport), así que lo que
## actúa sobre una cámara (FOV, sacudida) debe recibir esta.
func view_camera() -> Camera3D:
	return _camera.view_camera()


## Capa visual del cuerpo propio de este slot (ver PlayerCamera.RIG_LAYER_BASE).
func rig_visual_layer() -> int:
	return _camera.rig_visual_layer()


## Cambia la mascota (la caja de mascotas y el vendedor la llaman por
## nombre; ver PetSlot.set_pet).
func set_pet(new_pet_id: String) -> void:
	_pet_slot.set_pet(new_pet_id)


## PowerUps la llama por nombre cuando termina Vuelo (ver PlayerFlight.end_flight).
func end_flight() -> void:
	_flight.end_flight()


# --- Puntos (nodo Wallet) ---------------------------------------------------
# Enemigos, cofres, santuarios, vendedores, PowerUps y WorldDirector llaman
# a estos métodos por nombre (has_method/call).

func points_multiplier() -> float:
	return _wallet.points_multiplier()


func set_points_source(source_id: String, multiplier: float) -> void:
	_wallet.set_points_source(source_id, multiplier)


func clear_points_source(source_id: String) -> void:
	_wallet.clear_points_source(source_id)


func add_points(amount: int) -> void:
	_wallet.add_points(amount)


func spend_points(amount: int) -> bool:
	return _wallet.spend_points(amount)


## Contrato de marcador de mapa (grupo "map_markers"): la flecha usa el giro
## de este cuerpo, que es hacia donde mira el raider.
func map_marker_kind() -> StringName:
	return &"player"


## Resuelve una vez los nombres de acción de este slot (ver _actions).
func _cache_slot_actions() -> void:
	for base: StringName in Coop.BASE_ACTIONS:
		_actions[base] = Coop.action(player_index, base)


## Temporizadores que bajan en TODO estado. Sobre todo el enraizamiento:
## Sarcognato enraíza y daña en la misma llamada, y si se congelara al caer,
## el revivido volvería con 3 s de enraizamiento nuevos.
func _tick_timers(delta: float) -> void:
	_root_timer = maxf(_root_timer - delta, 0.0)
	_slide_cooldown_timer = maxf(_slide_cooldown_timer - delta, 0.0)


## Rescate del vacío, además de los muros del perímetro: un cuerpo que se
## coló por un hueco vuelve a suelo firme sin derrape ni enraizamiento. Un
## caído va junto al compañero en pie más cercano y no a su inicio, que
## puede estar a 100 m y nadie lo encontraría para revivirlo.
func _rescue_from_void() -> void:
	if global_position.y >= void_rescue_y:
		return
	var destination := _spawn_position
	if is_downed():
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


## Dirección deseada de este tick, plana y normalizada, relativa a la base
## que da la cámara (el cuerpo, o la cámara en órbita libre).
func _read_wish_dir() -> Vector3:
	if is_rooted():
		return Vector3.ZERO
	var input_dir: Vector2 = Input.get_vector(slot_action(&"move_left"), slot_action(&"move_right"),
			slot_action(&"move_forward"), slot_action(&"move_back"))
	var wish_dir: Vector3 = _camera.move_basis() * Vector3(input_dir.x, 0.0, input_dir.y)
	wish_dir.y = 0.0
	return wish_dir.normalized() if wish_dir.length_squared() > 0.0 else Vector3.ZERO


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
	if not Input.is_action_just_pressed(slot_action(&"jump")) or is_rooted():
		return
	# Multisalto: el del suelo más PlayerStats.extra_jumps en el aire; se
	# recargan al pisar suelo (ver _physics_process).
	if _jumps_left <= 0:
		return
	_jumps_left -= 1
	if _is_sliding:
		_end_slide()
	velocity.y = jump_velocity


## Saltos disponibles desde el suelo: el del suelo más los que dan los stats.
func _max_jumps() -> int:
	var stats := PlayerStats.find_in(self)
	return 1 + (stats.extra_jumps if stats != null else 0)


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
	if _is_dead or is_downed():
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


func _on_wallet_points_changed(total: int) -> void:
	points_changed.emit(total)


func _enter_downed() -> void:
	# Un Entomb que llegó con el golpe final (Sarcognato enraíza y daña a la
	# vez) no dura más que la caída: el revivido vuelve pudiendo moverse.
	_root_timer = 0.0
	_revive.set_downed(true)


func _can_start_slide(wish_dir: Vector3, effective_speed: float) -> bool:
	if not Input.is_action_pressed(slot_action(&"sprint")) or wish_dir == Vector3.ZERO:
		return false
	if not is_on_floor() or _slide_cooldown_timer > 0.0:
		return false
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	return horizontal_speed > effective_speed * slide_min_speed_ratio


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
