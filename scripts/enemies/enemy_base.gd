class_name EnemyBase
extends CharacterBody3D
## Chasis común de todos los enemigos (arena plana, sin navmesh): gravedad,
## persecución del raider con un empuje de separación de los vecinos (la
## horda se reparte en vez de apilarse), orientación, y el flujo de muerte
## por el hijo Health (crédito de la baja, gema de XP, caída final). Las
## subclases cambian el comportamiento con los hooks virtuales de abajo.
## make_elite() vuelve shiny a cualquier enemigo.

## Velocidad de persecución en m/s. Valor de respaldo: cada enemigo fija el
## suyo en su escena.
@export var move_speed: float = 7.0
## Rapidez de giro hacia su dirección (por segundo). Valor de respaldo: cada
## enemigo fija el suyo en su escena.
@export var turn_speed: float = 10.0
## Radio en metros en el que aparta a los vecinos. Igual para toda la horda.
@export var separation_radius: float = 1.2
## Fuerza con la que se aparta de los vecinos (0 = no se aparta). Valor de
## respaldo: cada enemigo fija el suyo en su escena.
@export var separation_strength: float = 1.5
@export var xp_gem_scene: PackedScene
## Puntos de partida que paga al raider más cercano al morir. Los shiny lo
## multiplican como la XP; los jefes guardan el suyo (25) en su escena.
@export var points_value: int = 1
## Brillo shiny: vueltas de la rueda de matiz por segundo, pulsos de brillo
## por vuelta, y los límites de energía y alfa. Lento a propósito, para que
## se lea como un reflejo y no como un estrobo.
const SHINY_HUE_SPEED: float = 0.28
const SHINY_PULSE_CYCLES: float = 4.0
const SHINY_ENERGY_MIN: float = 1.3
const SHINY_ENERGY_MAX: float = 2.8
const SHINY_SATURATION: float = 0.85
const SHINY_ALPHA: float = 0.3
## Fases iniciales distintas, repartidas por instance id.
const SHINY_PHASE_BUCKETS: int = 997

@export_group("Elite")
@export var elite_hp_multiplier: float = 3.0
@export var elite_speed_multiplier: float = 1.3
@export var elite_damage_multiplier: float = 1.5
@export var elite_body_scale: float = 1.35
@export var elite_xp_multiplier: int = 5
@export_group("Health Orb")
## Probabilidad de que un shiny suelte un orbe de vida al morir (los comunes
## nunca sueltan; los jefes sobrescriben _drop_health_orbs).
@export var elite_health_orb_chance: float = 0.4
## Probabilidad de que un shiny suelte un cofre; la dificultad de la partida
## la escala.
@export var elite_chest_chance: float = 0.3
@export_group("Climbing")
## Un cuerpo que empuja contra una pared o un prop trepa a esta velocidad,
## así el relieve nunca encierra a la horda. Los muros del perímetro siguen
## sin cruzarse (la posición se recorta a los límites de la arena).
@export var can_climb: bool = true
@export var climb_speed: float = 5.5
## Altura máxima de UNA trepada, medida desde donde empezó. Sin tope, un
## cuerpo atascado contra la geometría sube para siempre y queda encaramado
## fuera del alcance de todos. Por encima de los muros de máscara (7 m, ver
## scatter.gd) para que los trepadores los sigan cruzando.
@export var max_climb_height: float = 10.0

const CHEST_SCENE := preload("res://scenes/world/chests/Chest.tscn")
## Margen entre un trepador y el borde de la arena, para que el recorte
## nunca lo meta dentro del muro. Los jefes usan su propio margen, más ancho
## (BossBase.arena_clamp_margin).
const ARENA_CLAMP_MARGIN: float = 1.5
## Suerte extra del cofre de un shiny por punto de dificultad de la partida.
const ELITE_CHEST_LUCK_PER_DIFFICULTY: float = 15.0
## Máximo de cofres de recompensa shiny SIN abrir a la vez en el mapa. No
## caducan y su probabilidad crece con la dificultad; cada uno es un Area3D,
## una caja sólida que la horda trepa y un marcador de mapa. Pasado el tope,
## una baja shiny no suelta cofre hasta que se abra uno o cambie la etapa
## (el patrón de HealthOrb.at_soft_cap). Los anillos de jefe usan
## spawn_chest directo y no cuentan. Lo lee ArenaProbe.
const BOUNTY_CHEST_CAP: int = 30
const BOUNTY_CHEST_GROUP: StringName = &"bounty_chests"
## Cofres que el tope se tragó en este proceso; limita la frecuencia del log.
static var _capped_bounty_drops: int = 0

var is_elite: bool = false
## Variante del cielo aplicada por el spawner ("" | "berserker" | "shade").
var variant: String = ""
## Límite de la arena para los trepadores (del nodo "arena_bounds"; INF = sin límite).
var _arena_limit: float = INF

@onready var _health: Health = $Health
@onready var _visual: Node3D = $Visual
@onready var _collision: CollisionShape3D = $CollisionShape3D

## Una sola foto del grupo "enemies" por tick de física, así una horda de n
## enemigos hace una consulta de grupo por tick en vez de n. Las entradas
## siguen siendo instancias válidas todo el tick (los free son diferidos);
## igual se saltan los cuerpos que salieron del grupo o del árbol.
static var _enemies_snapshot: Array[Node] = []
static var _enemies_snapshot_frame: int = -1

## Grilla de vecinos para la separación: esa foto repartida en celdas
## cuadradas del plano, así cada escaneo visita su celda y el anillo de
## alrededor en vez de toda la horda (O(n) por tick en vez de O(n²)).
## La arma el primer escaneo del tick con posiciones VIVAS y se mantiene
## viva el resto del tick (_follow_separation_grid). El escaneo es el mismo
## que el de la horda completa (posiciones vivas, mismo test de distancia,
## chequeo de grupo, empujón de apilados y caída), así que los vecinos y
## cada contribución son los mismos; solo cambia el orden de la suma
## (redondeo float, ~1e-7).
## Mayor que todo separation_radius en uso (todas las escenas usan 1.2 m).
## Un radio mayor sigue siendo correcto: el escaneo abre más anillos.
const SEPARATION_CELL_SIZE: float = 1.25
## La celda (cx, cz) se empaqueta como cx * STRIDE + cz. Es lineal, así la
## clave de un vecino es una suma; dos celdas solo se confunden pasadas 2^19
## celdas (~650 km), y ahí el escaneo vería candidatos DE MÁS que el test de
## distancia descarta. Nunca de menos.
const SEPARATION_KEY_STRIDE: int = 1 << 20
static var _separation_grid: Dictionary = {}
static var _separation_grid_frame: int = -1
## El cuerpo cuyo movimiento de este tick todavía no está en la grilla: el
## último que corrió _physics_process, si estaba repartido. A lo sumo uno.
static var _separation_grid_pending: EnemyBase = null

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _xp_multiplier: int = 1
## Factor del valor de la gema por grado del mapa (ver apply_tier_scaling); 1.0 = base.
var _tier_xp_multiplier: float = 1.0
# Ralentización temporal (Látigo de espinas, etc.): un multiplicador de
# velocidad activo mientras corre su reloj. Ver apply_slow.
var _slow_multiplier: float = 1.0
var _slow_time_left: float = 0.0
## Veneno: daño cada POISON_TICK segundos; al reaplicar ganan el dps MÁS
## FUERTE y el reloj MÁS LARGO.
const POISON_TICK: float = 0.5
var _poison_dps: float = 0.0
var _poison_time_left: float = 0.0
var _poison_tick_timer: float = 0.0
var _poison_overlay: StandardMaterial3D = null
## Último empuje de separación calculado, reusado en los ticks alternos.
var _separation_cache: Vector3 = Vector3.ZERO
## Clave de celda de este cuerpo en la grilla de separación y el frame de
## física de esa grilla (-1: nunca repartido).
var _separation_key: int = 0
var _separation_key_frame: int = -1
## Capas de overlay por prioridad: el brillo shiny sobre la variante del
## cielo, y esta sobre el veneno. Cada efecto escribe SU capa y llama a
## _refresh_overlay(), así uno temporal nunca borra uno permanente (un
## berserker shiny se lee como ambos, y al pasarse el veneno vuelve la
## variante en vez de la piel desnuda).
## Tipado más estrecho que las demás: el brillo shiny reescribe su albedo y
## su emisión cada frame (_tick_shiny), que Material no expone.
var _overlay_elite: StandardMaterial3D = null
## La posesión manda sobre todo: de qué bando es un cuerpo es lo primero que
## hay que leer, y un siervo nunca es shiny (se levanta sin tirada).
var _overlay_possessed: Material = null
var _overlay_variant: Material = null
var _overlay_status: Material = null
## Mallas del rig visual, resueltas una vez en _ready.
var _meshes: Array[MeshInstance3D] = []
## Altura donde empezó la trepada actual y si hay una en curso; juntas
## limitan cada trepada a max_climb_height.
var _climb_start_y: float = 0.0
var _climbing: bool = false
## Si el bastón nigromante puede levantarlo como siervo. Solo los que pelean
## por contacto (su _combat_tick daña cualquier Health que reciba); los que
## disparan o golpean en área lo tienen apagado en su escena, porque poseídos
## seguirían atacando al equipo.
@export var possessable: bool = true
const POSSESSED_GROUP: StringName = &"possessed"
## Capa de colisión propia, fuera de la de enemigos (2) y de mundo/jugadores (1).
const POSSESSED_LAYER: int = 8
const POSSESSED_TINT := Color(0.65, 0.35, 0.95)
## Distancia a la que un siervo busca con quién pelear.
const POSSESSED_SEEK_RANGE: float = 30.0
var _possessed: bool = false
var _possess_carrier: Node3D = null
var _possess_left: float = 0.0
## Lo marca end_possession para que los dos caminos que llegan ahí (el reloj
## y la muerte del portador en el mismo frame) no liberen el cuerpo dos veces.
var _expiring_possession: bool = false


func _ready() -> void:
	_health.died.connect(_on_died)
	_health.damaged.connect(_on_damaged_flash)
	_cache_meshes()
	var bounds := get_tree().get_first_node_in_group("arena_bounds") as Node3D
	if bounds != null:
		# Con guarda: un nodo de límites sin la propiedad devuelve null, y
		# float(null) es un error de script.
		var extent: Variant = bounds.get("arena_half_extent")
		if extent is float or extent is int:
			_arena_limit = float(extent) - ARENA_CLAMP_MARGIN


func _physics_process(delta: float) -> void:
	# Primero, antes de que algo mueva este cuerpo: pasar a la grilla de
	# separación el movimiento del cuerpo anterior y anotar este.
	if _separation_grid_frame == Engine.get_physics_frames():
		_follow_separation_grid()
	if _overlay_elite != null:
		_tick_shiny(delta)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	_slow_time_left = maxf(_slow_time_left - delta, 0.0)
	if _poison_time_left > 0.0:
		_tick_poison(delta)
	# Un tick de veneno puede MATAR dentro de este frame, y
	# set_physics_process(false) recién rige en el próximo tick: sin esta
	# guarda el cadáver seguiría actuando (un excavador muerto que erupciona,
	# un esbirro muerto que pega, un hostigador muerto que dispara).
	if _health.is_dead:
		return
	if _possessed:
		_tick_possession(delta)
		if _expiring_possession:
			return
	_behavior_tick(delta)

	var steer := Vector3.ZERO
	var seek := Vector3.ZERO
	# NO Coop.nearest_player directo: un poseído lo cambia para cazar
	# enemigos, y todo lo de abajo (la persecución, la orientación y
	# _combat_tick, que daña cualquier Health que reciba) no depende de quién
	# es el objetivo.
	var player := _pick_target()
	if player != null:
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		var distance := to_player.length()
		if distance > 0.001:
			seek = to_player / distance
		steer = _movement_intent(seek, distance)
		_combat_tick(player, distance)

	# Cada enemigo recalcula la separación cada 2 ticks de física (alternados
	# por la paridad del instance id, así calcula media horda por tick) y
	# reusa su empuje guardado entre medio.
	# Los cuerpos sin separation_strength (jefes, un excavador enterrado)
	# calculan igual a propósito: un excavador que erupciona en un tick
	# alterno lee el empuje que guardó enterrado, ahora con fuerza completa;
	# saltarlos cambiaría dónde aparece. En la grilla les cuesta unos pocos
	# vecinos, no la horda.
	if (Engine.get_physics_frames() + get_instance_id()) & 1 == 0:
		_separation_cache = _separation_push()
	steer += _separation_cache * separation_strength
	steer.y = 0.0
	if steer.length_squared() > 1.0:
		steer = steer.normalized()
	var slowed_speed := move_speed * active_slow_multiplier()
	# Una sola escritura de la propiedad en vez de dos get/set: `velocity.x =`
	# lee el vector entero y lo vuelve a escribir. Mismos valores float32.
	velocity = Vector3(steer.x * slowed_speed, velocity.y, steer.z * slowed_speed)

	var face := _facing_direction(steer, seek)
	if face.length_squared() > 0.0001:
		# Mira hacia la dirección elegida (-Z es el frente).
		var target_yaw := atan2(-face.x, -face.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, minf(turn_speed * delta, 1.0))

	_tick_climb(steer)
	move_and_slide()
	_clamp_solver_launch()
	if _arena_limit != INF:
		# Se escribe solo cuando el recorte actúa (rara vez: un trepador en el
		# perímetro). Cada escritura de global_position es un set de transform
		# global completo que se propaga al rig y al servidor de física.
		var at := global_position
		var clamped_x := clampf(at.x, -_arena_limit, _arena_limit)
		var clamped_z := clampf(at.z, -_arena_limit, _arena_limit)
		if clamped_x != at.x or clamped_z != at.z:
			global_position = Vector3(clamped_x, at.y, clamped_z)


## Contra quién pelea este cuerpo. La respuesta base es el raider en pie más
## cercano; un siervo poseído responde con el ENEMIGO más cercano. Todo lo
## de abajo no depende del objetivo, así que este es todo el cambio de bando.
func _pick_target() -> Node3D:
	if _possessed:
		return _nearest_enemy()
	return Coop.nearest_player(get_tree(), global_position)


## Enemigo vivo más cercano dentro de POSSESSED_SEEK_RANGE, para un siervo.
## El grupo VIVO a propósito, no la foto del tick: un cuerpo que entra a
## "enemies" a mitad del tick (uno recién aparecido, un gusano que sale)
## tiene que ser objetivo en este mismo tick.
func _nearest_enemy() -> Node3D:
	var best: Node3D = null
	var best_distance := POSSESSED_SEEK_RANGE * POSSESSED_SEEK_RANGE
	var here := global_position
	for node: Node in get_tree().get_nodes_in_group(&"enemies"):
		var body := node as Node3D
		if body == null or not body.is_inside_tree():
			continue
		var distance := here.distance_squared_to(body.global_position)
		if distance <= best_distance:
			best_distance = distance
			best = body
	return best


## Vuelve a este cuerpo siervo de `carrier` por `duration` segundos.
##
## SALE del grupo "enemies" (declarado en la raíz de la escena), así dejan de
## verlo las armas del raider, la cuenta viva del spawner y el tiempo
## detenido: los tres recorren ese grupo, por eso alcanza con salir de él.
## Pasa a su propia capa fuera de la de enemigos y suma una excepción por
## raider: los jugadores comparten la capa 1 con el mundo, y una máscara que
## lo dejara atravesar raiders también lo dejaría atravesar el terreno.
func make_possessed(carrier: Node3D, duration: float) -> void:
	_possessed = true
	_possess_carrier = carrier
	_possess_left = duration
	remove_from_group("enemies")
	add_to_group(POSSESSED_GROUP)
	collision_layer = POSSESSED_LAYER
	collision_mask = 1
	for group: String in ["player", "downed_players"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var body := node as CollisionObject3D
			if body != null:
				add_collision_exception_with(body)
	_tint_possessed()
	print("Possessed spawned: %s" % _script_name())


## El raider al que sirve este siervo, o null si no está poseído.
func possession_carrier() -> Node3D:
	return _possess_carrier if _possessed else null


## Termina la posesión antes de tiempo (hizo falta lugar en el tope, murió
## el portador o se acabó el reloj). Un siervo NO paga nada: ya pagó una vez
## como el cadáver del que se levantó.
func end_possession() -> void:
	if not _possessed or _expiring_possession:
		return
	_expiring_possession = true
	print("Possessed expired: %s" % _script_name())
	Juice.burst(global_position + Vector3.UP * 0.8, POSSESSED_TINT, 12)
	queue_free()


## Por el protocolo de CAPAS de overlay, no escribiendo material_overlay a
## mano: Juice.flash restaura current_overlay() tras cada destello de daño,
## y un tinte fuera de las capas no está en esa respuesta (el primer golpe
## borraría lo único que dice que el siervo es tuyo). Un solo material para
## todo el rig: no guarda estado por malla.
func _tint_possessed() -> void:
	var overlay := StandardMaterial3D.new()
	overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	overlay.albedo_color = Color(POSSESSED_TINT, 0.35)
	overlay.emission_enabled = true
	overlay.emission = POSSESSED_TINT
	overlay.emission_energy_multiplier = 1.4
	_overlay_possessed = overlay
	_refresh_overlay()


func _script_name() -> String:
	var script_resource := get_script() as Script
	if script_resource == null:
		return "enemy"
	return script_resource.resource_path.get_file().get_basename()


## Contabilidad del siervo: el reloj, y el portador que se va.
func _tick_possession(delta: float) -> void:
	_possess_left -= delta
	if _possess_left <= 0.0 or not is_instance_valid(_possess_carrier) \
			or not _possess_carrier.is_inside_tree():
		end_possession()


## La ÚNICA forma permitida de que un enemigo gane altura es _tick_climb.
## Cualquier otro frame que termina subiendo en el aire viene de la
## despenetración de move_and_slide(): un cuerpo apretado entre ochenta sale
## por el eje más barato, que suele ser hacia arriba, y conservar ese
## impulso es "enemigos volando". Acotado a propósito: en el suelo una
## velocidad hacia arriba es una rampa o un escalón, y trepando es la
## trepada; solo en el aire y sin trepar habla el solver, y se descarta su
## respuesta (el cuerpo cae desde donde lo empujaron).
func _clamp_solver_launch() -> void:
	if _climbing or is_on_floor() or velocity.y <= 0.0:
		return
	velocity.y = 0.0


## Trepar paredes: bloqueado por geometría mientras intenta moverse -> sube,
## pero solo hasta max_climb_height sobre donde empezó. Pisar algo
## caminable rearma la siguiente trepada desde el nuevo apoyo.
func _tick_climb(steer: Vector3) -> void:
	if not (can_climb and steer.length_squared() > 0.01 and _blocked_by_geometry()):
		if _climbing and is_on_floor():
			_climbing = false
		return
	if not _climbing:
		_climbing = true
		_climb_start_y = global_position.y
	if global_position.y - _climb_start_y < max_climb_height:
		velocity.y = climb_speed


## True si un contacto de pared de este frame vino de GEOMETRÍA del nivel.
## is_on_wall() solo no alcanza: los enemigos chocan con el raider y entre
## ellos (collision_mask 3), y cualquier contacto casi vertical lo marca;
## una horda apretada leería a sus vecinos, o al raider que muerde, como
## pared y se les subiría encima, fuera de alcance. Trepar es para paredes y
## cornisas, así que solo cuentan los colisionadores que no son personajes.
func _blocked_by_geometry() -> bool:
	if not is_on_wall():
		return false
	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		# Los suelos y las rampas suaves se caminan, no se trepan.
		if collision.get_normal().y > 0.5:
			continue
		if collision.get_collider() is CharacterBody3D:
			continue
		return true
	return false


## Virtual: tareas por frame (esperas de ataque, etc.) antes de moverse.
func _behavior_tick(_delta: float) -> void:
	pass


## Virtual: hacia dónde moverse dada la dirección plana unitaria al raider y
## la distancia plana. Por defecto persigue en línea recta.
func _movement_intent(seek: Vector3, _distance: float) -> Vector3:
	return seek


## Virtual: oportunidad de ataque de este frame; la distancia es plana.
func _combat_tick(_player: Node3D, _distance: float) -> void:
	pass


## Virtual: dirección hacia la que gira el cuerpo. Por defecto mira hacia
## donde se mueve.
func _facing_direction(steer: Vector3, _seek: Vector3) -> Vector3:
	return steer


## Virtual: escala los números de daño propios de la subclase; lo llaman
## make_elite(), apply_tier_scaling() y las variantes del cielo.
func _apply_elite_damage(_multiplier: float) -> void:
	pass


# --- daño de área avisado (la puerta que conoce a todo el equipo) -------------

## Resuelve UN disco de suelo avisado contra todo el equipo. El disco se
## dibuja para todos, así que daña a todos los que estén encima: es el único
## resolvedor que usan los ataques de área, en vez de que cada uno busque al
## raider más cercano y se olvide del resto. Devuelve los cuerpos golpeados,
## para que quien llama sume efectos (el inmovilizar del Sarcognath) solo a
## esos raiders.
func damage_players_in_disc(center: Vector3, radius: float, height_window: float,
		amount: float, attacker: Node3D = null) -> Array[Node3D]:
	var spots: Array[Vector3] = [center]
	return damage_players_in_discs(spots, radius, height_window, amount, attacker)


## Versión de varios discos (estallidos de raíces, anillos de ataúdes,
## escupitajos): cada raider recibe COMO MÁXIMO un golpe aunque lo cubran
## varios discos. Solo vuelven los raiders a los que el golpe LLEGÓ:
## take_damage informa la vida que quitó, así que un raider que esquivó
## queda fuera de la lista y del efecto extra (eso es esquivar).
func damage_players_in_discs(spots: Array[Vector3], radius: float,
		height_window: float, amount: float, attacker: Node3D = null) -> Array[Node3D]:
	var hit: Array[Node3D] = []
	if spots.is_empty():
		return hit
	for player: Node3D in Coop.alive_players(get_tree()):
		if not _covered_by_any(player, spots, radius, height_window):
			continue
		var player_health := Health.find_in(player)
		if player_health == null or player_health.is_dead:
			continue
		if player_health.take_damage(amount, false, attacker) > 0.0:
			hit.append(player)
	return hit


## Distancia plana dentro de `radius` de algún punto, y no más alto que
## `height_window` sobre él: un salto a tiempo o una cornisa esquivan el ataque.
func _covered_by_any(player: Node3D, spots: Array[Vector3], radius: float,
		height_window: float) -> bool:
	for spot: Vector3 in spots:
		var to_player := player.global_position - spot
		if absf(to_player.y) > height_window:
			continue
		to_player.y = 0.0
		if to_player.length() <= radius:
			return true
	return false


## Aplica una ralentización: este enemigo se mueve a speed_multiplier de su
## velocidad durante `duration` segundos. Reaplicar REFRESCA en vez de
## acumular, así latigazos repetidos nunca la llevan a cero; como en
## apply_poison, ganan la ralentización MÁS FUERTE y el reloj MÁS LARGO.
func apply_slow(speed_multiplier: float, duration: float) -> void:
	if duration <= 0.0:
		return
	var incoming := clampf(speed_multiplier, 0.05, 1.0)
	_slow_multiplier = minf(active_slow_multiplier(), incoming)
	_slow_time_left = maxf(_slow_time_left, duration)


## Multiplicador de velocidad externo actual: 1.0 sin ralentización activa.
func active_slow_multiplier() -> float:
	return _slow_multiplier if _slow_time_left > 0.0 else 1.0


## Aplica un veneno de `dps` durante `duration` segundos (Bolsa de pedos,
## arañas, Hedor). Al refrescar ganan el dps más fuerte y el reloj más
## largo, así un veneno débil nunca pisa uno fuerte.
func apply_poison(dps: float, duration: float) -> void:
	if dps <= 0.0 or duration <= 0.0 or _health.is_dead:
		return
	if _poison_time_left <= 0.0:
		_poison_tick_timer = POISON_TICK
		_apply_poison_tint(true)
	_poison_dps = maxf(_poison_dps, dps)
	_poison_time_left = maxf(_poison_time_left, duration)


func is_poisoned() -> bool:
	return _poison_time_left > 0.0


func _tick_poison(delta: float) -> void:
	_poison_time_left = maxf(_poison_time_left - delta, 0.0)
	_poison_tick_timer -= delta
	if _poison_tick_timer <= 0.0:
		_poison_tick_timer += POISON_TICK
		# Por take_damage, así aplican la armadura, los números y la muerte.
		_health.take_damage(_poison_dps * POISON_TICK)
	if _poison_time_left <= 0.0:
		_poison_dps = 0.0
		_apply_poison_tint(false)


## Capa verde mientras está envenenado. Es la de MENOR prioridad: los shiny
## y las variantes del cielo conservan su tinte y muestran el veneno solo en
## los números de daño, y al pasarse vuelve su capa en vez de borrarse.
func _apply_poison_tint(on: bool) -> void:
	if on and _poison_overlay == null:
		_poison_overlay = StandardMaterial3D.new()
		_poison_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_poison_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_poison_overlay.albedo_color = Color(0.35, 0.9, 0.3, 0.35)
	_overlay_status = _poison_overlay if on else null
	_refresh_overlay()


## El overlay que este cuerpo debería llevar ahora, o null si ninguno.
## Público para que los efectos que toman material_overlay un momento
## (Juice.flash, que lo busca por nombre) restauren el estado COMPUESTO.
func current_overlay() -> Material:
	if _overlay_possessed != null:
		return _overlay_possessed
	if _overlay_elite != null:
		return _overlay_elite
	if _overlay_variant != null:
		return _overlay_variant
	return _overlay_status


func _refresh_overlay() -> void:
	var overlay := current_overlay()
	for mesh: MeshInstance3D in _meshes:
		if is_instance_valid(mesh):
			mesh.material_overlay = overlay


func _cache_meshes() -> void:
	_meshes.clear()
	if _visual == null:
		return
	for node: Node in _visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance != null:
			_meshes.append(mesh_instance)


## Dificultad por grado del mapa (GDD 6/7), la aplica el spawner justo
## después de aparecer: multiplica la vida máxima (y cura al nuevo máximo),
## el daño de ataque (por el mismo virtual que los shiny) y el pago de la
## gema de XP. Distinto de make_elite() y se combina con él en cualquier
## orden. Con todos los factores en 1.0 no cambia nada. Llamar con el
## enemigo ya en el árbol (usa el hijo Health).
func apply_tier_scaling(hp_mult: float, dmg_mult: float, xp_value_mult: float = 1.0) -> void:
	if not is_equal_approx(hp_mult, 1.0):
		_health.max_hp *= hp_mult
		_health.heal_full()
	if not is_equal_approx(dmg_mult, 1.0):
		_apply_elite_damage(dmg_mult)
	# Se compone como todo modificador de aparición (una segunda pasada
	# multiplica en vez de reemplazar).
	_tier_xp_multiplier *= xp_value_mult


## Vuelve shiny a este enemigo: más vida (curada al nuevo máximo), velocidad,
## daño y XP, cuerpo más grande y una capa de brillo. Llamar con el enemigo
## ya en el árbol. Idempotente.
func make_elite() -> void:
	if is_elite:
		return
	is_elite = true
	_health.max_hp *= elite_hp_multiplier
	_health.heal_full()
	move_speed *= elite_speed_multiplier
	_apply_elite_damage(elite_damage_multiplier)
	# Multiplica (como points_value justo abajo) en vez de asignar: el
	# spawner aplica antes la variante del cielo, y un berserker shiny tiene
	# que seguir pagando la XP doble de la variante encima del factor shiny.
	_xp_multiplier *= elite_xp_multiplier
	points_value *= elite_xp_multiplier
	_grow_body(elite_body_scale)
	_apply_elite_glow()


## Variantes del cielo, las aplica el spawner a lo que aparece durante un
## evento. Idempotente por cuerpo.
##   "berserker" (luna de sangre): más rápido, pega más fuerte, ignora a la
##                                 multitud (casi sin separación), tinte rojo;
##                                 paga el doble.
##   "shade"     (eclipse):        mucho más resistente, casi negro; paga el doble.
func apply_variant(kind: String) -> void:
	if not variant.is_empty() or kind.is_empty():
		return
	variant = kind
	match kind:
		"berserker":
			move_speed *= 1.4
			_apply_elite_damage(1.3)
			separation_strength *= 0.2
			_apply_overlay(Color(1.0, 0.15, 0.1, 0.45), Color(1.0, 0.2, 0.1), 2.0)
		"shade":
			_health.max_hp *= 1.6
			_health.heal_full()
			_apply_overlay(Color(0.05, 0.02, 0.1, 0.8), Color(0.3, 0.1, 0.5), 0.6)
		_:
			push_warning("EnemyBase: unknown variant '%s'" % kind)
			variant = ""
			return
	_xp_multiplier *= 2
	points_value *= 2


## Dónde está este cuerpo en el ciclo de matiz shiny (0-1); sin uso hasta
## que _apply_elite_glow lo siembra.
var _shiny_phase: float = 0.0


## Agranda este cuerpo por `factor`: se escala el rig VISUAL y se
## REDIMENSIONA una copia propia de la forma de colisión.
## Nunca `scale *= factor` sobre el CharacterBody3D: Godot no soporta
## escalar un cuerpo físico (la forma escalada da contactos inestables y
## saltos de despenetración, peores justo donde los cuerpos se aprietan).
## La forma se duplica porque un [sub_resource] de .tscn es UN objeto
## compartido por todas las instancias de la escena: agrandar la
## CapsuleShape3D de la escena agrandaría a todos los esbirros de la arena.
func _grow_body(factor: float) -> void:
	if is_equal_approx(factor, 1.0) or factor <= 0.0:
		return
	if _visual != null:
		_visual.scale *= factor
		# Las posiciones también escalan, así un rig con partes desplazadas
		# del origen conserva sus proporciones.
		_visual.position *= factor
	for child: Node in get_children():
		var shape_node := child as CollisionShape3D
		if shape_node == null or shape_node.shape == null:
			continue
		var shape := shape_node.shape.duplicate() as Shape3D
		if not _resize_shape(shape, factor):
			continue
		shape_node.shape = shape
		# Mantiene los pies donde estaban: una cápsula agrandada en el sitio
		# se hundiría medio cuerpo en el suelo y la sacarían de un empujón en
		# el siguiente tick.
		shape_node.position *= factor


## Redimensiona una forma por `factor`, en el sitio. Devuelve false para un
## tipo de forma que no sabe agrandar, así quien llama deja la original en
## vez de dejar un cuerpo cuyo colisionador ya no coincide con él.
func _resize_shape(shape: Shape3D, factor: float) -> bool:
	var capsule := shape as CapsuleShape3D
	if capsule != null:
		capsule.radius *= factor
		capsule.height *= factor
		return true
	var sphere := shape as SphereShape3D
	if sphere != null:
		sphere.radius *= factor
		return true
	var cylinder := shape as CylinderShape3D
	if cylinder != null:
		cylinder.radius *= factor
		cylinder.height *= factor
		return true
	var box := shape as BoxShape3D
	if box != null:
		box.size *= factor
		return true
	push_warning("%s: cannot grow collision shape of type %s"
			% [name, shape.get_class()])
	return false


func _apply_overlay(albedo: Color, emission: Color, energy: float) -> void:
	_overlay_variant = _build_overlay(albedo, emission, energy)
	_refresh_overlay()


## El aspecto SHINY: un overlay autoiluminado cuyo matiz cicla y cuyo brillo
## respira, para que un shiny se lea de un vistazo aun dentro de la horda y
## aun cuando toda la horda es shiny. Solo material, a propósito: sin
## partículas ni FX del pool (cuando todo cuerpo es shiny a la vez, un
## emisor por cuerpo vaciaría los pools). El overlay es propio de cada
## cuerpo (_build_overlay crea uno nuevo), así animarlo nunca toca a otro.
func _apply_elite_glow() -> void:
	_overlay_elite = _build_overlay(
			Color(1.0, 0.62, 0.12, SHINY_ALPHA), Color(1.0, 0.55, 0.1), SHINY_ENERGY_MIN)
	# Cada cuerpo empieza en otro punto del ciclo: una horda que late al
	# unísono se lee como un solo objeto parpadeando.
	_shiny_phase = float(get_instance_id() % SHINY_PHASE_BUCKETS) \
			/ float(SHINY_PHASE_BUCKETS)
	_refresh_overlay()


## Un frame del brillo. Barato a propósito: dos escrituras en un material
## propio, sin reservar memoria ni recorrer grupos.
func _tick_shiny(delta: float) -> void:
	_shiny_phase = fmod(_shiny_phase + delta * SHINY_HUE_SPEED, 1.0)
	var tint := Color.from_hsv(_shiny_phase, SHINY_SATURATION, 1.0)
	_overlay_elite.albedo_color = Color(tint.r, tint.g, tint.b, SHINY_ALPHA)
	_overlay_elite.emission = tint
	var beat := 0.5 + 0.5 * sin(_shiny_phase * TAU * SHINY_PULSE_CYCLES)
	_overlay_elite.emission_energy_multiplier = lerpf(
			SHINY_ENERGY_MIN, SHINY_ENERGY_MAX, beat)


func _build_overlay(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var overlay := StandardMaterial3D.new()
	overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	overlay.albedo_color = albedo
	overlay.emission_enabled = true
	overlay.emission = emission
	overlay.emission_energy_multiplier = energy
	return overlay


func _on_damaged_flash(_amount: float, _current: float) -> void:
	Juice.flash(_visual)


## Virtual: reacción a la muerte (sacudida chica y estallido de esquirlas
## del color del cuerpo); el jefe la cambia por su momento grande.
func _death_feedback() -> void:
	Juice.enemy_died(global_position + Vector3.UP * 0.8, death_burst_color())


## Color del estallido de muerte: el albedo de la primera malla visual, así
## las esquirlas se leen como pedazos del cuerpo. Los shiny conservan su
## piel base (el brillo es un overlay, que get_active_material ignora).
func death_burst_color() -> Color:
	for mesh_instance: MeshInstance3D in _meshes:
		if not is_instance_valid(mesh_instance) or mesh_instance.mesh == null \
				or mesh_instance.mesh.get_surface_count() == 0:
			continue
		var material := mesh_instance.get_active_material(0) as StandardMaterial3D
		if material != null:
			return material.albedo_color
	return Color(0.75, 0.75, 0.78)


## Suma los empujes de los "enemies" vivos dentro de separation_radius, con
## caída (máximo al solaparse, cero en el borde). Solo visita las celdas
## alrededor de este cuerpo (ver SEPARATION_CELL_SIZE); cada test es el del
## escaneo de toda la horda, sobre posiciones vivas.
func _separation_push() -> Vector3:
	var grid := _separation_grid_this_tick(get_tree(), self)
	var push := Vector3.ZERO
	var here := global_position
	# Un vecino pasa el test de distancia solo si está más cerca que
	# separation_radius en cada eje plano, así un anillo de celdas cubre todo
	# radio menor que la celda (con ~4% de margen a 1.2 m, muy por encima del
	# redondeo float del índice); un radio mayor escanea los anillos necesarios.
	var rings := 1
	if separation_radius >= SEPARATION_CELL_SIZE:
		rings = ceili(separation_radius / SEPARATION_CELL_SIZE) + 1
	var cell_x := floori(here.x / SEPARATION_CELL_SIZE)
	var cell_z := floori(here.z / SEPARATION_CELL_SIZE)
	for dx in range(-rings, rings + 1):
		var column_key := (cell_x + dx) * SEPARATION_KEY_STRIDE + cell_z
		for dz in range(-rings, rings + 1):
			var cell: Variant = grid.get(column_key + dz)
			if cell == null:
				continue
			# Bucle tipado: las entradas siguen siendo instancias válidas todo
			# el tick (los free son diferidos), como la foto de la que salen.
			for other: Node3D in cell:
				if other == self or not other.is_inside_tree():
					continue
				var away := here - other.global_position
				away.y = 0.0
				var dist := away.length()
				if dist >= separation_radius:
					continue
				# Solo para vecinos reales: la foto se toma una vez por tick, y un
				# cuerpo que murió ANTES en este tick sigue en ella y empujaría a
				# la horda como cadáver.
				if not other.is_in_group(&"enemies"):
					continue
				if dist < 0.01:
					# Cuerpos apilados exactos: se separan en una dirección estable por instancia.
					away = Vector3.RIGHT.rotated(Vector3.UP, float(get_instance_id() % 64) * TAU / 64.0)
					dist = 0.01
				push += (away / dist) * (1.0 - dist / separation_radius)
	return push


## La grilla de separación de este tick, la arma el primer escaneo que la
## pide. Cada cuerpo de la foto se reparte donde está AHORA: los que ya
## corrieron este tick terminaron de moverse, y al resto se lo sigue
## mientras se mueve (_follow_separation_grid). `builder` es el cuerpo que
## escanea, a mitad de su _physics_process con su movimiento por delante.
static func _separation_grid_this_tick(tree: SceneTree, builder: EnemyBase) -> Dictionary:
	var frame := Engine.get_physics_frames()
	if frame == _separation_grid_frame:
		return _separation_grid
	_separation_grid_frame = frame
	_separation_grid.clear()
	for node: Node in _enemies_this_tick(tree):
		var body := node as Node3D
		# El escaneo igual se salta los cuerpos fuera del árbol, que no tienen posición.
		if body == null or not body.is_inside_tree():
			continue
		var at := body.global_position
		var key := floori(at.x / SEPARATION_CELL_SIZE) * SEPARATION_KEY_STRIDE \
				+ floori(at.z / SEPARATION_CELL_SIZE)
		var cell: Variant = _separation_grid.get(key)
		if cell == null:
			_separation_grid[key] = [body]
		else:
			(cell as Array).append(body)
		var enemy := body as EnemyBase
		if enemy != null:
			enemy._separation_key = key
			enemy._separation_key_frame = frame
	_separation_grid_pending = builder if builder._separation_key_frame == frame else null
	return _separation_grid


## Mantiene la grilla fiel a las posiciones vivas mientras los cuerpos se
## mueven durante el tick. Un cuerpo solo se mueve dentro de su propio
## _physics_process (incluido lo de la subclase: BossBase recorta DESPUÉS de
## super()), y ningún escaneo corre entre el final del _physics_process de
## un cuerpo y el inicio del siguiente. Por eso repartir de nuevo el cuerpo
## ANTERIOR aquí, al inicio del siguiente, llega a ver todo su movimiento
## (un salto del Fenwraith, un brinco del Grubthing, el recorte del jefe) y
## a tiempo para todo escaneo posterior. Solo se llama si la grilla de este
## tick ya existe.
func _follow_separation_grid() -> void:
	if is_instance_valid(_separation_grid_pending):
		_rebucket_separation(_separation_grid_pending)
	_separation_grid_pending = self if _separation_key_frame == _separation_grid_frame else null


static func _rebucket_separation(body: EnemyBase) -> void:
	# Fuera del árbol su entrada vieja no molesta: el escaneo se la salta.
	if not body.is_inside_tree():
		return
	var at := body.global_position
	var key := floori(at.x / SEPARATION_CELL_SIZE) * SEPARATION_KEY_STRIDE \
			+ floori(at.z / SEPARATION_CELL_SIZE)
	if key == body._separation_key:
		return
	var old_cell: Variant = _separation_grid.get(body._separation_key)
	if old_cell != null:
		(old_cell as Array).erase(body)
	var cell: Variant = _separation_grid.get(key)
	if cell == null:
		_separation_grid[key] = [body]
	else:
		(cell as Array).append(body)
	body._separation_key = key


static func _enemies_this_tick(tree: SceneTree) -> Array[Node]:
	var frame := Engine.get_physics_frames()
	if frame != _enemies_snapshot_frame:
		_enemies_snapshot_frame = frame
		_enemies_snapshot = tree.get_nodes_in_group(&"enemies")
	return _enemies_snapshot


func _on_died() -> void:
	# Un cuerpo congelado (tiempo detenido) es PROCESS_MODE_DISABLED, y un
	# nodo desactivado igual recibe llamadas y señales: se lo puede matar
	# congelado. Su tween de muerte quedaría atado a un nodo que no procesa y
	# el cadáver nunca se liberaría. Siempre se descongela primero.
	process_mode = Node.PROCESS_MODE_INHERIT
	# Primero sale del grupo, así las armas y la separación ignoran el cadáver.
	remove_from_group("enemies")
	set_physics_process(false)
	_collision.set_deferred("disabled", true)
	if _possessed:
		# Un siervo muerto en el campo NO paga nada: ni crédito, ni XP, ni
		# puntos, ni orbes, ni tirada de cofre, ni contador del bestiario. Ya
		# pagó todo eso como el cadáver del que se levantó. Solo queda la
		# muerte visual.
		# Sale del grupo de poseídos en el mismo momento: un cadáver que
		# siguiera ahí durante los 0.3 s de su tween contaría contra el
		# max_possessed del portador, y el bastón podría "expirar" un cuerpo
		# ya muerto (un Possessed expired: falso en el log que lee el harness).
		_possessed = false
		remove_from_group(POSSESSED_GROUP)
		_death_feedback()
		_death_tween()
		return
	RunState.add_kill()
	# Contador del bestiario (pantalla Colección): la clave sale del nombre
	# del archivo del script ("kills_grunt", "kills_rotking", ...). No
	# renombres los scripts de enemigos.
	var script_path := (get_script() as Script).resource_path
	if not script_path.is_empty():
		SaveData.bump("kills_" + script_path.get_file().get_basename())
	_drop_xp_gem()
	_drop_health_orbs()
	_drop_powerup()
	_drop_acid_pool()
	_award_points()
	_death_feedback()
	_death_tween()


## La caída que comparten todos los cadáveres, siervos incluidos.
func _death_tween() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_visual, "rotation:x", -TAU * 0.25, 0.3) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_visual, "scale", Vector3.ONE * 0.05, 0.3) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)


## Los puntos de partida van al raider en pie MÁS CERCANO (en co-op, quien
## estaba en lo más denso), nunca repartidos: la economía es por jugador.
func _award_points() -> void:
	if points_value <= 0:
		return
	var player := Coop.nearest_player(get_tree(), global_position)
	if player != null and player.has_method("add_points"):
		player.call("add_points", points_value)


func _drop_xp_gem() -> void:
	if xp_gem_scene == null:
		return
	# Del pool, colgada de la raíz de la escena (no de este enemigo) para
	# sobrevivir al cadáver; pool_reset restauró el xp_value de la escena.
	var gem := Pools.acquire_scene(xp_gem_scene) as XpGem
	if gem == null:
		return
	# Primero el factor shiny (entero), después el del grado del mapa (mínimo
	# 1 XP); ambos valen 1 en una aparición base y dejan el valor de la escena.
	gem.xp_value = maxi(roundi(float(gem.xp_value * _xp_multiplier) * _tier_xp_multiplier), 1)
	gem.global_position = global_position + Vector3.UP * 0.6


## Orbes de vida de esta muerte. Regla base: solo los shiny tiran
## (elite_health_orb_chance de un orbe) y además tiran cofre; BossBase lo
## cambia por pagos garantizados. La curación es la fracción fija del orbe:
## los factores de grado nunca la tocan.
func _drop_health_orbs() -> void:
	if is_elite and randf() < elite_health_orb_chance:
		_spawn_health_orb(global_position + Vector3.UP * 0.6)
	if is_elite and randf() < elite_chest_chance * (1.0 + RunState.difficulty_bonus):
		_drop_chest()


## Lluvia radiactiva: todo cadáver deja un charco mientras dura. El director
## lleva el tope y el espaciado y se niega solo si el clima no está activo,
## así que esto es una llamada sin estado.
func _drop_acid_pool() -> void:
	var director := get_tree().get_first_node_in_group("world_director")
	if director != null and director.has_method("spawn_acid_pool"):
		director.call("spawn_acid_pool", global_position)


## Power-up temporal. La probabilidad base es mínima a propósito (un
## power-up tiene que sentirse como un evento, no como botín) y la mueve la
## stat powerup_drop_chance del raider («Fortuna menor»). Los shiny tiran
## un múltiplo. La ESTRELLA nunca cae aquí: se encuentra rondando el mapa
## (star_sighting del WorldDirector).
func _drop_powerup() -> void:
	var spawner := get_tree().get_first_node_in_group("enemy_spawner")
	if spawner == null or not spawner.has_method("roll_powerup_drop"):
		return
	# El raider más cercano, como en el pago de puntos: es dueño de la
	# tirada, así cuenta su «Fortuna menor».
	var player := Coop.nearest_player(get_tree(), global_position)
	if not bool(spawner.call("roll_powerup_drop", player, is_elite)):
		return
	spawner.call("spawn_powerup_pickup", global_position + Vector3.UP * 0.8,
			PowerUpCatalog.roll_id(true))


## Cofre de recompensa shiny: la rareza se tira con una inclinación de
## suerte que crece con la dificultad. Se salta en BOUNTY_CHEST_CAP.
func _drop_chest() -> void:
	if bounty_chests_at_cap(get_tree()):
		_capped_bounty_drops += 1
		# Una línea cada 25 cofres tragados: tarde en la partida el tope puede
		# saltar varias veces por segundo, y el harness busca la primera línea.
		if _capped_bounty_drops % 25 == 1:
			print("Elite chest capped: %d unopened (x%d)" % [
					BOUNTY_CHEST_CAP, _capped_bounty_drops])
		return
	var chest := spawn_chest(
			global_position + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)),
			ELITE_CHEST_LUCK_PER_DIFFICULTY * RunState.difficulty_bonus)
	if chest != null:
		chest.add_to_group(BOUNTY_CHEST_GROUP)
		# Un cofre gratis no tiene rareza todavía (la tira al abrirse), así
		# que el log dice lo que ES en vez de una cadena vacía.
		print("Elite chest dropped: free")


## Cofres de recompensa sin abrir en el mapa. Uno abierto sigue en el grupo
## mientras se hunde (Chest._sink lo libera al terminar su tween), así que
## decide `available`, no la pertenencia. Lo lee ArenaProbe.
static func unopened_bounty_chests(tree: SceneTree) -> int:
	var count := 0
	for node: Node in tree.get_nodes_in_group(BOUNTY_CHEST_GROUP):
		var chest := node as Interactable
		if chest != null and chest.available:
			count += 1
	return count


static func bounty_chests_at_cap(tree: SceneTree) -> bool:
	return unopened_bounty_chests(tree) >= BOUNTY_CHEST_CAP


## Suelta un cofre en `at`, colgado de la RAÍZ de la escena para sobrevivir
## al cadáver; devuelve null si no hay escena donde soltarlo (cierre de la
## partida) o si la raíz de la escena no es un Chest. El único lugar por el
## que pasan el cofre shiny y el anillo del jefe. Todo cofre soltado por un
## CUERPO es gratis: ya se pagó al matarlo.
func spawn_chest(at: Vector3, luck_bonus: float, min_rarity: String = "") -> Chest:
	var parent := RunRoot.stage_parent(get_tree())
	if parent == null:
		parent = get_parent()
	if parent == null:
		return null
	var chest := CHEST_SCENE.instantiate() as Chest
	if chest == null:
		push_warning("EnemyBase: Chest scene root is not a Chest.")
		return null
	# Vacío conserva el piso que tenga la escena (el cofre shiny tira sin
	# límite; los de jefe pueden forzar un piso).
	if not min_rarity.is_empty():
		chest.min_rarity = min_rarity
	chest.luck_bonus = luck_bonus
	chest.free_open = true
	parent.add_child(chest)
	chest.global_position = at
	return chest


## Un orbe de vida del pool en `at`, salvo en el tope global de orbes vivos.
## Se comprueba por orbe, así el pago múltiple de un jefe llena justo hasta
## el tope.
func _spawn_health_orb(at: Vector3) -> void:
	if HealthOrb.at_soft_cap(get_tree()):
		return
	var orb := Pools.acquire_scene(Pools.HEALTH_ORB_SCENE) as HealthOrb
	if orb == null:
		return
	orb.global_position = at
