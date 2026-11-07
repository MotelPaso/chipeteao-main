class_name EnemyBase
extends CharacterBody3D
## Chasis común de todos los enemigos (arena plana, sin navmesh): gravedad,
## persecución del raider con empuje de separación de los vecinos, giro,
## trepada, y el flujo de muerte por el hijo Health (crédito de la baja,
## pagos, caída final). Las subclases cambian el comportamiento con los hooks
## virtuales. make_elite() lo vuelve shiny, apply_variant() le aplica una
## variante del cielo y make_possessed() lo vuelve siervo de un raider.
## Piezas en scripts/enemies/enemy/: EnemySeparation (empuje de la horda),
## EnemyOverlays (capas de color), EnemyStatus (ralentización y veneno),
## EnemyPossession (siervos) y EnemyLoot (pagos al morir).

## Grupo de los siervos poseídos. También lo leen el bastón nigromante,
## RunRoot y ArenaProbe.
const POSSESSED_GROUP: StringName = &"possessed"
## Color de los siervos poseídos (su capa y el estallido al expirar). También
## lo lee el bastón nigromante.
const POSSESSED_TINT := Color(0.65, 0.35, 0.95)
## Tope de cofres shiny sin abrir; el valor se edita en EnemyLoot. ArenaProbe
## lo lee aquí.
const BOUNTY_CHEST_CAP: int = EnemyLoot.BOUNTY_CHEST_CAP
## Aspecto compartido por todos los enemigos (shiny, veneno, poseído,
## muerte): se edita en assets/enemies/enemy_look.tres desde el Inspector.
const LOOK: EnemyLookPalette = preload("res://assets/enemies/enemy_look.tres")
## Variantes del cielo que el spawner aplica durante un evento. Edita aquí
## sus valores: speed, damage, separation y hp multiplican (1.0 = sin
## cambio), reward multiplica la XP y los puntos, y albedo / emission /
## energy son su capa de color.
const VARIANTS: Dictionary = {
	# Luna de sangre: más rápido, pega más fuerte, ignora a la multitud.
	"berserker": {
		"speed": 1.4, "damage": 1.3, "separation": 0.2, "hp": 1.0, "reward": 2,
		"albedo": Color(1.0, 0.15, 0.1, 0.45), "emission": Color(1.0, 0.2, 0.1),
		"energy": 2.0,
	},
	# Eclipse: mucho más resistente, casi negro.
	"shade": {
		"speed": 1.0, "damage": 1.0, "separation": 1.0, "hp": 1.6, "reward": 2,
		"albedo": Color(0.05, 0.02, 0.1, 0.8), "emission": Color(0.3, 0.1, 0.5),
		"energy": 0.6,
	},
}
## Margen en metros entre un trepador y el borde de la arena, para que el
## recorte nunca lo meta dentro del muro (los jefes usan arena_clamp_margin).
const ARENA_CLAMP_MARGIN: float = 1.5

@export_group("Movimiento")
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

@export_group("Recompensa")
## Escena de la gema de XP que suelta al morir.
@export var xp_gem_scene: PackedScene
## Puntos de partida que paga al raider más cercano al morir. Los shiny lo
## multiplican como la XP; los jefes guardan el suyo (25) en su escena.
@export var points_value: int = 1

@export_group("Shiny")
## Multiplicador de vida máxima al volverse shiny.
@export var elite_hp_multiplier: float = 3.0
## Multiplicador de velocidad al volverse shiny.
@export var elite_speed_multiplier: float = 1.3
## Multiplicador de daño al volverse shiny.
@export var elite_damage_multiplier: float = 1.5
## Escala del cuerpo al volverse shiny (rig y colisión).
@export var elite_body_scale: float = 1.35
## Multiplica la XP de la gema y los puntos de un shiny.
@export var elite_xp_multiplier: int = 5
## Probabilidad (0-1) de que un shiny suelte un orbe de vida al morir (los
## comunes nunca sueltan; los jefes tienen su propio pago).
@export var elite_health_orb_chance: float = 0.4
## Probabilidad (0-1) de que un shiny suelte un cofre al morir; la dificultad
## de la partida la escala.
@export var elite_chest_chance: float = 0.3

@export_group("Trepar")
## Si trepa paredes y props al empujar contra ellos, así el relieve nunca
## encierra a la horda. Los muros del perímetro igual no se cruzan.
@export var can_climb: bool = true
## Velocidad de subida al trepar, en m/s.
@export var climb_speed: float = 5.5
## Altura máxima en metros de UNA trepada, desde donde empezó: sin tope, un
## cuerpo atascado sube para siempre fuera de alcance. Por encima de los
## muros de máscara (formaciones de roca: max_height en
## assets/world/rock_style_<mapa>.tres) para que los sigan cruzando.
@export var max_climb_height: float = 10.0

@export_group("Posesión")
## Si el bastón nigromante puede levantarlo como siervo. Solo los que pelean
## por contacto (su _combat_tick daña cualquier Health que reciba); los que
## disparan o golpean en área lo tienen apagado en su escena, porque poseídos
## seguirían atacando al equipo.
@export var possessable: bool = true

@export_group("Puntería")
## Altura en metros sobre los pies a la que apuntan las armas del raider (ver
## aim_point()).
@export var aim_height: float = 0.8

## True desde make_elite(): este cuerpo es shiny.
var is_elite: bool = false
## Variante del cielo aplicada ("" | "berserker" | "shade").
var variant: String = ""
## Celda de este cuerpo en la grilla de EnemySeparation y el frame de física
## de esa grilla (-1: nunca repartido). Solo los escribe EnemySeparation.
var separation_key: int = 0
var separation_key_frame: int = -1

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8)
var _xp_multiplier: int = 1
## Factor del valor de la gema por grado del mapa (ver apply_tier_scaling); 1.0 = base.
var _tier_xp_multiplier: float = 1.0
## Límite de la arena para los trepadores (del nodo "arena_bounds"; INF = sin límite).
var _arena_limit: float = INF
## Último empuje de separación calculado, reusado en los ticks alternos.
var _separation_cache: Vector3 = Vector3.ZERO
## Altura donde empezó la trepada actual y si hay una en curso; juntas
## limitan cada trepada a max_climb_height. ArenaProbe lee "_climbing" por
## nombre.
var _climb_start_y: float = 0.0
var _climbing: bool = false
var _overlays: EnemyOverlays = EnemyOverlays.new()
## null hasta la primera ralentización o veneno.
var _status: EnemyStatus = null
## null salvo mientras es siervo de un raider.
var _possession: EnemyPossession = null

@onready var _health: Health = $Health
@onready var _visual: Node3D = $Visual
@onready var _collision: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	_health.died.connect(_on_died)
	_health.damaged.connect(_on_damaged_flash)
	_overlays.cache_meshes(_visual)
	var bounds := get_tree().get_first_node_in_group("arena_bounds") as Node3D
	if bounds != null:
		# Con guarda: un nodo de límites sin la propiedad devuelve null, y
		# float(null) es un error de script.
		var extent: Variant = bounds.get("arena_half_extent")
		if extent is float or extent is int:
			_arena_limit = float(extent) - ARENA_CLAMP_MARGIN


## El bucle más caliente del juego (corre por cada enemigo en cada tick de
## física), por eso queda entero y sin reservar memoria.
func _physics_process(delta: float) -> void:
	# Primero, antes de que algo mueva este cuerpo: la grilla de separación
	# recoge el movimiento del cuerpo anterior y anota este.
	EnemySeparation.follow(self)
	if is_elite:
		_overlays.tick_shiny(delta)
	if not is_on_floor():
		velocity.y -= _gravity * delta
	if _status != null:
		_status.tick(delta)
	# Un pulso de veneno puede MATAR dentro de este frame, y
	# set_physics_process(false) recién rige en el próximo tick: sin esta
	# guarda el cadáver seguiría actuando (un excavador muerto que erupciona,
	# un esbirro muerto que pega, un hostigador muerto que dispara).
	if _health.is_dead:
		return
	if _possession != null:
		if _possession.tick(delta):
			end_possession()
		if _possession.expiring:
			return
	_behavior_tick(delta)

	var steer := Vector3.ZERO
	var seek := Vector3.ZERO
	# NO Coop.nearest_player directo: un siervo caza enemigos, y todo lo de
	# abajo (la persecución, el giro y _combat_tick, que daña cualquier Health
	# que reciba) no depende de quién es el objetivo.
	var player := _pick_target()
	if player != null:
		var to_player := player.global_position - global_position
		to_player.y = 0.0
		var distance := to_player.length()
		if distance > 0.001:
			seek = to_player / distance
		steer = _movement_intent(seek, distance)
		_combat_tick(player, distance)

	# Cada enemigo recalcula la separación cada 2 ticks (alternados por la
	# paridad del instance id, así calcula media horda por tick) y reusa su
	# empuje guardado entre medio. Los cuerpos sin separation_strength (jefes,
	# un excavador enterrado) calculan igual a propósito: un excavador que
	# erupciona en un tick alterno lee el empuje que guardó enterrado, ahora
	# con fuerza completa; saltarlos cambiaría dónde aparece.
	if (Engine.get_physics_frames() + get_instance_id()) & 1 == 0:
		_separation_cache = EnemySeparation.push(self)
	steer += _separation_cache * separation_strength
	steer.y = 0.0
	if steer.length_squared() > 1.0:
		steer = steer.normalized()
	var slow := 1.0 if _status == null else _status.slow_multiplier()
	var slowed_speed := move_speed * slow
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


# --- estado público --------------------------------------------------------------

## Punto al que apuntan las armas del raider: aim_height metros sobre los pies.
func aim_point() -> Vector3:
	return global_position + Vector3.UP * aim_height


## El overlay que este cuerpo debería llevar ahora, o null si ninguno.
## Juice.flash lo busca por nombre para restaurar el estado COMPUESTO tras
## cada destello de daño.
func current_overlay() -> Material:
	return _overlays.current()


## Color del estallido de muerte (ver EnemyOverlays.death_burst_color).
func death_burst_color() -> Color:
	return _overlays.death_burst_color()


## Aplica una ralentización: este enemigo se mueve a speed_multiplier de su
## velocidad durante `duration` segundos. Reaplicar REFRESCA en vez de
## acumular, así latigazos repetidos nunca la llevan a cero; como en
## apply_poison, ganan la ralentización MÁS FUERTE y el reloj MÁS LARGO.
## Lo llaman las armas (Látigo de espinas, Hedor) y el spawner.
func apply_slow(speed_multiplier: float, duration: float) -> void:
	if duration <= 0.0:
		return
	_ensure_status().apply_slow(speed_multiplier, duration)


## Multiplicador de velocidad externo actual: 1.0 sin ralentización activa.
func active_slow_multiplier() -> float:
	return 1.0 if _status == null else _status.slow_multiplier()


## Aplica un veneno de `dps` durante `duration` segundos (Bolsa de pedos,
## arañas, Hedor). Al refrescar ganan el dps más fuerte y el reloj más
## largo, así un veneno débil nunca pisa uno fuerte.
func apply_poison(dps: float, duration: float) -> void:
	if dps <= 0.0 or duration <= 0.0 or _health.is_dead:
		return
	_ensure_status().apply_poison(dps, duration)


# --- shiny, grados y variantes ---------------------------------------------------

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
	_overlays.apply_elite_glow(get_instance_id())


## Aplica la variante del cielo `kind` (una fila de VARIANTS) a lo que
## aparece durante un evento. Idempotente por cuerpo.
func apply_variant(kind: String) -> void:
	if not variant.is_empty() or kind.is_empty():
		return
	if not VARIANTS.has(kind):
		push_warning("EnemyBase: unknown variant '%s'" % kind)
		return
	variant = kind
	var row: Dictionary = VARIANTS[kind]
	var hp_factor := float(row["hp"])
	if hp_factor != 1.0:
		_health.max_hp *= hp_factor
		_health.heal_full()
	var speed_factor := float(row["speed"])
	if speed_factor != 1.0:
		move_speed *= speed_factor
	var damage_factor := float(row["damage"])
	if damage_factor != 1.0:
		_apply_elite_damage(damage_factor)
	var separation_factor := float(row["separation"])
	if separation_factor != 1.0:
		separation_strength *= separation_factor
	var albedo: Color = row["albedo"]
	var emission: Color = row["emission"]
	_overlays.set_variant(albedo, emission, float(row["energy"]))
	var reward := int(row["reward"])
	_xp_multiplier *= reward
	points_value *= reward


# --- posesión --------------------------------------------------------------------

## Vuelve a este cuerpo siervo de `carrier` por `duration` segundos (ver
## EnemyPossession). Lo llama el bastón nigromante.
func make_possessed(carrier: Node3D, duration: float) -> void:
	_possession = EnemyPossession.new(carrier, duration)
	EnemyPossession.switch_sides(self)
	# Por la capa de poseído, no escribiendo material_overlay a mano:
	# Juice.flash restaura current_overlay() tras cada destello, y un tinte
	# fuera de las capas se borraría con el primer golpe.
	_overlays.set_possessed(POSSESSED_TINT)
	print("Possessed spawned: %s" % _script_name())


## El raider al que sirve este siervo, o null si no está poseído.
func possession_carrier() -> Node3D:
	return _possession.carrier if _possession != null else null


## Termina la posesión antes de tiempo (hizo falta lugar en el tope, murió
## el portador o se acabó el reloj). Un siervo NO paga nada: ya pagó una vez
## como el cadáver del que se levantó.
func end_possession() -> void:
	if _possession == null or _possession.expiring:
		return
	_possession.expiring = true
	print("Possessed expired: %s" % _script_name())
	Juice.burst(global_position + Vector3.UP * 0.8, POSSESSED_TINT,
			LOOK.possessed_expire_burst)
	queue_free()


# --- daño de área avisado (la puerta que conoce a todo el equipo) ----------------

## Resuelve UN disco de suelo avisado contra todo el equipo. El disco se
## dibuja para todos, así que daña a todos los que estén encima: es el único
## resolvedor que usan los ataques de área. Devuelve los cuerpos golpeados,
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


## Suelta un cofre gratis en `at` (ver EnemyLoot.spawn_chest). BossBase lo
## usa para su anillo de cofres.
func spawn_chest(at: Vector3, luck_bonus: float, min_rarity: String = "") -> Chest:
	return EnemyLoot.spawn_chest(self, at, luck_bonus, min_rarity)


## Cofres shiny sin abrir en el mapa (ver EnemyLoot). Lo lee ArenaProbe.
static func unopened_bounty_chests(tree: SceneTree) -> int:
	return EnemyLoot.unopened_bounty_chests(tree)


# --- hooks virtuales -------------------------------------------------------------

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


## Virtual: copia a `servant` (el siervo que se levanta del cadáver de este
## cuerpo, de su misma escena) lo que lo hace pegar como él. Pensado para el
## bastón nigromante; Grunt suma su contact_damage.
func _copy_combat_stats_to(servant: EnemyBase) -> void:
	servant.move_speed = move_speed


## Virtual: reacción a la muerte (sacudida chica y estallido de esquirlas
## del color del cuerpo); el jefe la cambia por su momento grande.
func _death_feedback() -> void:
	Juice.enemy_died(global_position + Vector3.UP * 0.8, death_burst_color())


## Virtual: gema de XP de esta muerte; BossBase paga un anillo de gemas.
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


## Virtual: orbes de vida de esta muerte. Regla base: solo los shiny tiran
## (elite_health_orb_chance de un orbe) y además tiran cofre; BossBase lo
## cambia por pagos garantizados. La curación es la fracción fija del orbe:
## los factores de grado nunca la tocan.
func _drop_health_orbs() -> void:
	if is_elite and randf() < elite_health_orb_chance:
		EnemyLoot.spawn_health_orb(get_tree(), global_position + Vector3.UP * 0.6)
	if is_elite and randf() < elite_chest_chance * (1.0 + RunState.difficulty_bonus):
		EnemyLoot.drop_bounty_chest(self)


# --- privados --------------------------------------------------------------------

## Contra quién pelea este cuerpo. La respuesta base es el raider en pie más
## cercano; un siervo responde con el ENEMIGO más cercano. Todo lo de abajo
## no depende del objetivo, así que este es todo el cambio de bando.
func _pick_target() -> Node3D:
	if _possession != null:
		return EnemyPossession.nearest_enemy(get_tree(), global_position)
	return Coop.nearest_player(get_tree(), global_position)


func _ensure_status() -> EnemyStatus:
	if _status == null:
		_status = EnemyStatus.new(_health, _overlays)
	return _status


func _script_name() -> String:
	var script_resource := get_script() as Script
	if script_resource == null:
		return "enemy"
	return script_resource.resource_path.get_file().get_basename()


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
## ellos (collision_mask 3), y una horda apretada leería a sus vecinos, o al
## raider que muerde, como pared y se les subiría encima, fuera de alcance.
## Solo cuentan los colisionadores que no son personajes.
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


## Agranda este cuerpo por `factor`: se escala el rig VISUAL y se
## REDIMENSIONA una copia propia de la forma de colisión. Nunca
## `scale *= factor` sobre el CharacterBody3D: Godot no soporta escalar un
## cuerpo físico (contactos inestables y saltos de despenetración, peores
## justo donde los cuerpos se aprietan). La forma se duplica porque un
## [sub_resource] de .tscn es UN objeto compartido por todas las instancias.
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
		# se hundiría medio cuerpo en el suelo.
		shape_node.position *= factor


## Redimensiona una forma por `factor`, en el sitio. Devuelve false para un
## tipo de forma que no sabe agrandar, así quien llama deja la original en
## vez de un colisionador que ya no coincide con el cuerpo.
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


func _on_damaged_flash(_amount: float, _current: float) -> void:
	Juice.flash(_visual)


## Orden fijo (el RNG de los pagos depende de él): crédito, gema, orbes,
## power-up, charco, puntos, reacción y caída.
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
	if _possession != null:
		# Un siervo muerto en el campo NO paga nada: ni crédito, ni XP, ni
		# puntos, ni orbes, ni tirada de cofre, ni contador del bestiario. Solo
		# queda la muerte visual. Sale del grupo de poseídos en el mismo
		# momento: un cadáver que siguiera ahí durante su tween contaría contra
		# el max_possessed del portador, y el bastón podría "expirar" un cuerpo
		# ya muerto (un Possessed expired: falso en el log que lee el harness).
		_possession = null
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
	EnemyLoot.drop_powerup(self)
	EnemyLoot.drop_acid_pool(self)
	EnemyLoot.award_points(self)
	_death_feedback()
	_death_tween()


## La caída que comparten todos los cadáveres, siervos incluidos.
func _death_tween() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_visual, "rotation:x", LOOK.death_tilt, LOOK.death_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_visual, "scale", Vector3.ONE * LOOK.death_end_scale,
			LOOK.death_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)
