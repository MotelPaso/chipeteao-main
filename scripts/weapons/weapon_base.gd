class_name WeaponBase
extends Node3D
## Base de las armas automáticas: cuenta el enfriamiento y llama a fire() con
## el cuerpo más cercano del grupo "enemies" dentro de targeting_range().
## Cada subclase escribe su ataque en fire() y pasa todo golpe por
## deal_damage(), así las stats del portador (multiplicador de daño, crítico,
## robo de vida) se aplican en un solo lugar. El enfriamiento y el alcance de
## área pasan por los helpers effective_*, y los barridos de la horda por los
## helpers enemies_in_* de abajo.

## El enfriamiento efectivo nunca baja de estos segundos.
const MIN_COOLDOWN: float = 0.05
## Por debajo de este largo al cuadrado un vector de puntería no tiene
## dirección usable (el blanco está encima de la boca); se usa el frente.
const DEGENERATE_LENGTH_SQ: float = 0.0001
## Pasado este |dot| con UP una dirección es colineal con el eje vertical, y
## look_at / Basis.looking_at no pueden construir una base con UP.
const UP_COLINEAR_DOT: float = 0.99
## Fracción del enfriamiento en la que cabe una ráfaga entera del Tomo de
## Multitud: el escalonado se comprime para que la cola de una ráfaga no se
## monte sobre la siguiente.
const VOLLEY_WINDOW: float = 0.6
## Altura de puntería, en metros sobre el origen, para un blanco que no es
## un EnemyBase. Cada enemigo lleva la suya en su export aim_height.
const AIM_HEIGHT: float = 0.8
## Multiplicador de crítico que se usa si el arma no tiene PlayerStats (un
## arma probada fuera de un jugador) y aun así saca crítico por su bono propio.
const DEFAULT_CRIT_MULTIPLIER: float = 1.5
## Escalón plano de ascenso, aplicado SOBRE lo que el arma ya es en cada hito
## de EvolutionCatalog.EVOLVE_AT_LEVEL después del primero. Vive aquí y no en
## el catálogo porque no necesita receta: toda arma mejora cada diez niveles.
const ASCEND_MULTS: Dictionary[String, float] = {
	"damage": 1.15, "cooldown_scale": 0.9, "attack_range": 1.1}
## Proyectil extra solo en los tiers PARES (20, 40...): uno por tier haría
## crecer un arma de ráfaga mucho más rápido que los multiplicadores.
const ASCEND_PROJECTILE_TIER_STEP: int = 2
const ASCEND_PROJECTILE_ADD: int = 1

@export_group("Estadísticas")
## Daño por golpe. Valor de respaldo; cada arma fija el suyo en su escena. Lo suben «Afilado», «Temple», «Ritmo de batalla», evoluciones y ascensos.
@export var damage: float = 10.0
## Segundos entre ataques. Valor de respaldo; cada arma fija el suyo en su escena. Lo bajan «Mano rápida» y «Ritmo de batalla».
@export var cooldown: float = 1.0
## Distancia de búsqueda de blanco, en metros. Valor de respaldo; cada arma fija el suyo en su escena. Lo suben «Largo alcance», «Temple» y ascensos.
@export var attack_range: float = 3.0
## Disparos, orbes o golpes por ráfaga (1 salvo que la escena diga otra cosa); el Tomo de Multitud y los ascensos pares suman.
@export var projectile_count: float = 1
## Multiplicador de enfriamiento propio del arma (1 = sin cambio); lo bajan evoluciones, ascensos y cartas como «Ráfaga».
@export var cooldown_scale: float = 1.0
## Prob. de crítico extra del arma, en PUNTOS porcentuales (5 = +5%); se suma a la del portador. La suben las mejoras de arma.
@export var crit_chance_bonus: float = 0.0
## Daño crítico extra del arma, en PUNTOS porcentuales (10 = +0.10 al multiplicador de crítico). La suben las mejoras de arma.
@export var crit_damage_bonus: float = 0.0

@export_group("Impacto")
## Empujón que da cada golpe, en m/s (0 = no empuja). Cada arma fija el suyo en su escena.
@export var hit_push: float = 0.0
## Velocidad que le queda al enemigo durante el frenazo del golpe (1 = sin frenazo, 0.3 = casi parado). Cada arma fija el suyo en su escena.
@export_range(0.05, 1.0) var hit_slow: float = 1.0
## Segundos que dura ese frenazo. Cada arma fija el suyo en su escena.
@export var hit_slow_seconds: float = 0.0

@export_group("Área")
## Escala base del tamaño de área de TODAS las armas (0.8 = 80%): radios, tajos, rayos y charcos. Cámbiala aquí en el script, no en cada escena.
@export var base_area_scale: float = 0.8

@export_group("Robo de vida")
## Cuánto rinde el robo de vida del portador con TODAS las armas (0.5 = cura la mitad de lo que diría su %). Cámbiala aquí en el script, no en cada escena.
@export var lifesteal_scale: float = 0.5

## Cartas de mejora que recibió el arma en la partida (las suma
## UpgradePool.apply); es la puerta de evolución y ascenso (EvolutionCatalog).
var upgrade_level: int = 0
## True cuando evolve() ya corrió; un arma evolucionada no vuelve a evolucionar.
var evolved: bool = false
## Nombre visible de la forma evolucionada ("" hasta evolucionar).
var evolved_name: String = ""
## Hitos de EvolutionCatalog.EVOLVE_AT_LEVEL que pasó el arma: el tier 1 es el
## nivel 10 (evolución si hay receta, ascenso si no) y suma uno por múltiplo.
var ascension_tier: int = 0

var _cooldown_left: float = 0.0
## Blanco del disparo de ráfaga que está saliendo (ver volley_target()).
var _volley_target: Node3D = null

## Capa de stats del jugador que lleva el arma; null = multiplicadores
## neutros (un arma probada fuera de un jugador). Léela siempre con
## _stats_or_null(): el arma puede sobrevivir a su portador.
@onready var _stats: PlayerStats = _find_carrier_stats()
## Bolsa de objetos del portador: ganchos de golpe y de muerte de los objetos.
@onready var _bag: ItemBag = ItemBag.find_in(carrier_player())


# --- portador --------------------------------------------------------------

## El jugador que lleva el arma. Sube por los ancestros, así cada raider en
## co-op lee SUS stats; un montaje de prueba sin Player como ancestro usa el
## primer jugador de la escena.
func carrier_player() -> Node3D:
	var node: Node = self
	while node != null:
		if node is Player:
			return node
		node = node.get_parent()
	return get_tree().get_first_node_in_group("player") as Node3D


## El montaje que lleva el arma: el raider.
## Los efectos anclados al portador (el punto de caída de la baba, el centro
## del anillo de orbes) siguen a ESTE; stats, robo de vida y objetos siguen
## leyendo carrier_player().
func carrier_node() -> Node3D:
	var node: Node = self
	while node != null:
		if node is Player:
			return node as Node3D
		node = node.get_parent()
	return carrier_player()


func _find_carrier_stats() -> PlayerStats:
	var carrier := carrier_player()
	return PlayerStats.find_in(carrier) if carrier != null else null


## Stats del portador, o null si no hay. Suelta una referencia liberada en
## vez de tocarla; cada multiplicador de abajo tiene un camino neutro para null.
func _stats_or_null() -> PlayerStats:
	if _stats != null and not is_instance_valid(_stats):
		_stats = null
	return _stats


# --- ciclo de disparo ------------------------------------------------------

func _physics_process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	if _cooldown_left > 0.0:
		return
	var target := acquire_target()
	if target == null:
		return
	_cooldown_left = effective_cooldown()
	fire(target)


func effective_damage() -> float:
	var stats := _stats_or_null()
	return damage * (stats.damage_multiplier if stats != null else 1.0)


func effective_cooldown() -> float:
	var stats := _stats_or_null()
	var multiplier := stats.cooldown_multiplier if stats != null else 1.0
	return maxf(cooldown * multiplier * cooldown_scale, MIN_COOLDOWN)


## Multiplicador que cada subclase aplica a su alcance de área (radio de
## estallido, alcance del tajo). No se aplica al attack_range de búsqueda,
## salvo en las armas que ensanchan la búsqueda para igualarlo (targeting_range()).
func area_scale() -> float:
	var stats := _stats_or_null()
	return base_area_scale * (stats.area_multiplier if stats != null else 1.0)


## Disparos, orbes o flechas por ráfaga: el conteo propio del arma más el
## bono del portador (Tomo de Multitud), los dos con decimales; el total se
## redondea hacia abajo (1.3 + 1.7 = 3). Las armas leen esto, no
## projectile_count.
func effective_projectile_count() -> int:
	var stats := _stats_or_null()
	# El 0.0001 evita que 2.9999999 (error de float) se quede en 2.
	return floori(projectile_count + (stats.projectile_bonus if stats != null else 0.0)
			+ 0.0001)


## Multiplicador de los efectos con duración que deja un arma (ralentización,
## charcos, veneno); el Tomo de Persistencia lo sube.
func duration_scale() -> float:
	var stats := _stats_or_null()
	return stats.duration_multiplier if stats != null else 1.0


## Distancia de búsqueda de acquire_target(). Las armas de puntería usan
## attack_range tal cual; las de campo cuyo daño cubre attack_range * area_scale()
## (Aura, Hedor) la ensanchan para igualarla, o la franja exterior de su anillo
## nunca dispararía.
func targeting_range() -> float:
	return attack_range


## Cuerpo del grupo "enemies" más cercano dentro de targeting_range(), o null.
func acquire_target() -> Node3D:
	return _nearest_enemy({})


## Como acquire_target(), saltando los cuerpos cuyo instance id está en `skip`.
func _nearest_enemy(skip: Dictionary) -> Node3D:
	# Atajo con la horda vacía: esto corre cada frame de física mientras no
	# hay nadie vivo, así se evita el Array de get_nodes_in_group.
	if get_tree().get_first_node_in_group("enemies") == null:
		return null
	var nearest: Node3D = null
	var search_range := targeting_range()
	var nearest_dist_sq := search_range * search_range
	# Se lee una vez: el bucle solo lee transformadas, así que nuestra
	# posición no cambia mientras corre.
	var origin := global_position
	for enemy in get_tree().get_nodes_in_group("enemies"):
		var body := enemy as Node3D
		if body == null or not body.is_inside_tree():
			continue
		if not skip.is_empty() and skip.has(body.get_instance_id()):
			continue
		var dist_sq := origin.distance_squared_to(body.global_position)
		if dist_sq <= nearest_dist_sq:
			nearest_dist_sq = dist_sq
			nearest = body
	return nearest


## Virtual: el ataque contra el blanco adquirido.
func fire(_target: Node3D) -> void:
	push_warning("%s: fire() not implemented" % name)


# --- ráfagas del Tomo de Multitud ------------------------------------------

## Ráfaga a un solo blanco: `count` disparos hacia `first_target`. El
## primero sale ya por `center_dir`; los extras salen escalonados (ver
## volley_step()) y vuelven a apuntar al mismo blanco al salir, por si se
## movió. Si un disparo anterior lo mató, los que quedan se redirigen al
## enemigo más cercano; sin enemigos al alcance no salen. `shot` recibe la dirección; las
## armas que persiguen leen el blanco de cada disparo con volley_target().
func fire_volley(count: int, first_target: Node3D, center_dir: Vector3, shot: Callable,
		stagger: float) -> void:
	var step := volley_step(count, stagger)
	_volley_target = first_target
	shot.call(center_dir)
	for order: int in range(1, count):
		_schedule_shot(step * float(order), _volley_extra.bind(shot, center_dir, first_target))


## Blanco del disparo de ráfaga que está saliendo, o null si no hubo ninguno.
func volley_target() -> Node3D:
	return _volley_target if is_instance_valid(_volley_target) else null


## Reparto de una ráfaga entre enemigos (lo usa el Arco de caza): el enemigo
## más cercano que no está en `chosen`; con todos elegidos, empieza otra
## vuelta. Lo anota en `chosen`.
func next_volley_target(chosen: Dictionary) -> Node3D:
	var target := _nearest_enemy(chosen)
	if target == null and not chosen.is_empty():
		chosen.clear()
		target = _nearest_enemy(chosen)
	if target != null:
		chosen[target.get_instance_id()] = true
	return target


## `center_dir` rehecho hacia `target`, del mismo tipo: un desplazamiento
## (largo distinto de 1, el Vial de sangre) llega a su posición; una dirección
## plana sigue plana; las demás apuntan al centro de su cuerpo.
func redirect_to(center_dir: Vector3, target: Node3D) -> Vector3:
	if not is_equal_approx(center_dir.length(), 1.0):
		return target.global_position - global_position
	if absf(center_dir.y) < 0.0001:
		return flat_dir_or(target.global_position - global_position, center_dir)
	return aim_dir_or(body_aim_point(target) - global_position, center_dir)


## Un disparo extra de fire_volley(). `target` es Variant: el Callable guarda
## al enemigo y, si se liberó antes de que salga el disparo, un parámetro
## tipado fallaría ANTES de poder comprobar is_instance_valid.
func _volley_extra(shot: Callable, center_dir: Vector3, target: Variant) -> void:
	var live: Node3D = null
	if is_instance_valid(target) and (target as Node3D).is_in_group("enemies"):
		live = target as Node3D
	else:
		live = acquire_target()
	if live == null:
		return
	_volley_target = live
	shot.call(redirect_to(center_dir, live))


## Ráfaga con dos callbacks: `first` sale ya y cada extra llama a `extra`, que
## elige su propio blanco (el primer disparo pudo haber matado al suyo). Con
## `fit_window` en false el escalonado es `stagger` tal cual, sin comprimir.
func fire_volley_retarget(count: int, first: Callable, extra: Callable, stagger: float,
		fit_window: bool = true) -> void:
	var step := volley_step(count, stagger) if fit_window else stagger
	first.call()
	for i: int in range(1, count):
		_schedule_shot(step * float(i), extra)


## Segundos entre disparos de una ráfaga de `count`: `stagger`, comprimido
## para que la ráfaga entera quepa en VOLLEY_WINDOW del enfriamiento efectivo.
func volley_step(count: int, stagger: float) -> float:
	return minf(stagger, effective_cooldown() * VOLLEY_WINDOW / float(maxi(count - 1, 1)))


## Programa un disparo extra. Temporizador pausable y en paso de física: un
## extra no sale con la pantalla de mejoras abierta, y el daño cae en el mismo
## tick que el resto del combate.
func _schedule_shot(delay: float, shot: Callable) -> void:
	get_tree().create_timer(delay, false, true).timeout.connect(_fire_late.bind(shot))


## Un disparo extra llega un poco después de fire(), cuando el arma puede
## haber salido del árbol con un raider quitado o estar congelada por la
## cinemática de un jefe: fuera del árbol o sin poder procesar no dispara.
func _fire_late(shot: Callable) -> void:
	if is_inside_tree() and can_process():
		shot.call()


# --- embudo de daño --------------------------------------------------------

## Embudo de daño compartido: aplica el daño efectivo, tira el crítico y cura
## al portador por robo de vida. Todo golpe de arma pasa por aquí.
## El crítico suma la probabilidad y el daño crítico propios del arma
## (crit_chance_bonus, crit_damage_bonus, en puntos porcentuales) a los del
## portador.
## Devuelve el daño APLICADO, no la tirada: Health resta armadura, ignora un
## cuerpo ya muerto y un golpe letal solo quita la vida que quedaba. Los
## efectos que pagan por daño (robo de vida, drenaje del Vial de sangre) usan
## este valor.
## `allow_kill_hooks` es false para golpes de proyectiles creados por objetos
## (las arañas de ItemBag): si sus muertes crearan más arañas, una muerte se
## volvería una cascada exponencial que vacía el pool de dardos.
func deal_damage(target_health: Health, allow_kill_hooks: bool = true) -> float:
	var stats := _stats_or_null()
	var amount := effective_damage()
	var crit_chance := (stats.crit_chance if stats != null else 0.0) \
			+ crit_chance_bonus * 0.01
	var is_crit := randf() < crit_chance
	if is_crit:
		amount *= (stats.crit_damage if stats != null else DEFAULT_CRIT_MULTIPLIER) \
				+ crit_damage_bonus * 0.01
		Juice.crit_punch()
	Sfx.play(&"hit_crit" if is_crit else &"hit_soft")
	# La vida que el golpe quitó de verdad (0 si lo esquivó o ya estaba muerto).
	var hp_before := target_health.current_hp
	target_health.take_damage(amount, is_crit)
	var applied := maxf(hp_before - target_health.current_hp, 0.0)
	if applied <= 0.0:
		# Esquivado, o el cuerpo ya estaba muerto: los ganchos de objetos no
		# corren, o envenenarían cadáveres y repetirían on_weapon_kill para un
		# cuerpo que otro ya mató.
		return 0.0
	# El medidor de la party anota lo que el golpe quitó y su tirada entera.
	PartyPower.record_weapon_damage(self, target_health, applied, amount)
	if stats != null and stats.lifesteal > 0.0:
		_lifesteal_heal(applied * stats.lifesteal * lifesteal_scale)
	# Ganchos de objetos: veneno al golpear, arañas al matar.
	_hit_impact(target_health)
	if _bag != null and is_instance_valid(_bag):
		var body := target_health.get_parent() as Node3D
		if body != null:
			_bag.on_weapon_hit(body)
			if allow_kill_hooks and target_health.is_dead:
				_bag.on_weapon_kill(body.global_position, self)
	return applied


## Empuja al enemigo golpeado lejos del portador y lo frena un instante
## (hit_push, hit_slow, hit_slow_seconds de esta arma).
func _hit_impact(target_health: Health) -> void:
	if target_health.is_dead or (hit_push <= 0.0 and hit_slow_seconds <= 0.0):
		return
	var enemy := target_health.get_parent() as EnemyBase
	var carrier := carrier_node()
	if enemy == null or carrier == null:
		return
	var away := enemy.global_position - carrier.global_position
	away.y = 0.0
	if away.length_squared() < DEGENERATE_LENGTH_SQ:
		away = -carrier.global_basis.z
	enemy.apply_hit_impact(away.normalized() * hit_push, hit_slow, hit_slow_seconds)


func _lifesteal_heal(amount: float) -> void:
	var player := carrier_player()
	if player == null:
		return
	var player_health := Health.find_in(player)
	if player_health != null:
		player_health.heal(amount)

## Nivel de crítico de un golpe: cada 100% de probabilidad es un nivel seguro,
## y el resto es la probabilidad de un nivel extra. 0.45 -> 0 o 1;
## 1.25 -> 1 seguro y 25% de 2; 4.5 -> 4 seguros y 50% de 5.
static func roll_crit_tier(chance: float) -> int:
	var guaranteed := floori(chance)
	var remainder := chance - float(guaranteed)
	return guaranteed + (1 if randf() < remainder else 0)


## Daña cada cuerpo de `bodies` por el embudo de arriba; devuelve el daño
## total aplicado (el drenaje del Vial de sangre lo lee).
func damage_all(bodies: Array[Node3D]) -> float:
	var total := 0.0
	for body: Node3D in bodies:
		var health := Health.find_in(body)
		if health != null:
			total += deal_damage(health)
	return total


# --- barridos de la horda --------------------------------------------------
# Un solo lugar para "recorre el grupo enemies, quédate con los cuerpos vivos
# y prueba una forma". Cada helper devuelve los cuerpos encontrados; quien
# llama los pasa a damage_all() y suma sus efectos propios (veneno, chispas).
# Todas las formas cuentan el CUERPO entero, no solo su centro: el alcance se
# agranda con body_hit_radius(), así lo que el visual toca, golpea.

## Radio del cuerpo de un enemigo en el plano (EnemyBase.hit_radius), 0 para
## cualquier otra cosa.
static func body_hit_radius(body: Node3D) -> float:
	var enemy := body as EnemyBase
	return enemy.hit_radius() if enemy != null else 0.0

## Enemigos vivos que tocan un disco plano: su cuerpo a `radius` o menos de
## `center` en el plano XZ y a no más de `height_window` por encima o por
## debajo. El filtro de altura evita que un charco en el suelo alcance cuerpos
## sobre una cornisa.
func enemies_in_disc(center: Vector3, radius: float, height_window: float) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var body := node as Node3D
		if body == null or not body.is_inside_tree():
			continue
		var to_body := body.global_position - center
		if absf(to_body.y) > height_window:
			continue
		to_body.y = 0.0
		var reach := radius + body_hit_radius(body)
		if to_body.length_squared() <= reach * reach:
			found.append(body)
	return found


## Enemigos vivos dentro de una esfera de `radius` alrededor de `center`: los
## estallidos que también deben alcanzar cuerpos por encima o por debajo.
func enemies_in_sphere(center: Vector3, radius: float) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var body := node as Node3D
		if body == null or not body.is_inside_tree():
			continue
		var reach := radius + body_hit_radius(body)
		if center.distance_squared_to(body.global_position) <= reach * reach:
			found.append(body)
	return found


## Enemigos vivos dentro de un carril plano desde `origin`: entre 0 y `length`
## a lo largo de `direction` (plana y normalizada) y a no más de `half_width`
## de su eje.
func enemies_in_lane(origin: Vector3, direction: Vector3, length: float,
		half_width: float) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var body := node as Node3D
		if body == null or not body.is_inside_tree():
			continue
		var to_body := body.global_position - origin
		to_body.y = 0.0
		var body_radius := body_hit_radius(body)
		var along := to_body.dot(direction)
		if along < -body_radius or along > length + body_radius:
			continue
		if (to_body - direction * along).length() <= half_width + body_radius:
			found.append(body)
	return found


## Enemigos vivos que tocan un cono plano de `arc_deg` alrededor de
## `center_dir`, hasta `reach` en el plano XZ desde `center` y a no más de
## `height_window` por encima o por debajo (así un tajo a la altura del pecho
## llega igual a los pies). Un cuerpo encima del atacante no tiene dirección
## usable, así que siempre cuenta como dentro.
func enemies_in_arc(center: Vector3, center_dir: Vector3, reach: float,
		arc_deg: float, height_window: float = 2.2) -> Array[Node3D]:
	var found: Array[Node3D] = []
	var half_arc := deg_to_rad(arc_deg * 0.5)
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var body := node as Node3D
		if body == null or not body.is_inside_tree():
			continue
		var to_body := body.global_position - center
		if absf(to_body.y) > height_window:
			continue
		to_body.y = 0.0
		var body_radius := body_hit_radius(body)
		var distance := to_body.length()
		if distance > reach + body_radius:
			continue
		# El borde del cono también cuenta el cuerpo: se abre lo que el radio
		# del cuerpo ocupa visto desde el atacante.
		if distance * distance > DEGENERATE_LENGTH_SQ \
				and center_dir.angle_to(to_body) > half_arc + atan2(body_radius, distance):
			continue
		found.append(body)
	return found


# --- puntería --------------------------------------------------------------

## `vector` normalizado, o `fallback` si es demasiado corto para tener
## dirección (el blanco está justo en la boca del arma).
static func aim_dir_or(vector: Vector3, fallback: Vector3) -> Vector3:
	return vector.normalized() if vector.length_squared() > DEGENERATE_LENGTH_SQ \
			else fallback


## `vector` aplanado al plano XZ y normalizado, o `fallback` si no queda nada
## de él (blanco justo arriba o abajo).
static func flat_dir_or(vector: Vector3, fallback: Vector3) -> Vector3:
	vector.y = 0.0
	return vector.normalized() if vector.length_squared() > DEGENERATE_LENGTH_SQ \
			else fallback


## Punto del cuerpo de `target` al que apuntan las armas y la persecución de
## los proyectiles: EnemyBase.aim_point() si es un enemigo, si no AIM_HEIGHT
## sobre su origen.
static func body_aim_point(target: Node3D) -> Vector3:
	var enemy := target as EnemyBase
	if enemy != null:
		return enemy.aim_point()
	return target.global_position + Vector3.UP * AIM_HEIGHT


## Vector "arriba" válido para construir una base con `direction`: una
## puntería casi vertical (disparar a algo justo debajo de una cornisa) es
## colineal con UP y deja a look_at / Basis.looking_at sin base.
static func safe_up(direction: Vector3) -> Vector3:
	return Vector3.UP if absf(direction.dot(Vector3.UP)) < UP_COLINEAR_DOT \
			else Vector3.RIGHT


# --- efectos de un solo uso ------------------------------------------------

## Cuelga una malla de efecto de un solo uso de la etapa actual (o de la raíz
## del árbol, sin etapa) para que se reproduzca donde nació mientras el
## portador sigue caminando. Quien llama la coloca, la escala y la libera con
## su desvanecido. La malla `mesh` se comparte entre efectos: construir una
## por efecto es el gasto que Pools existe para evitar.
func spawn_fx_mesh(mesh: Mesh) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx_parent().add_child(node)
	return node


## Como spawn_fx_mesh, pero instancia una escena de efecto (LightningBeam.tscn)
## que se coloca y se libera sola.
func spawn_fx_scene(scene: PackedScene) -> Node3D:
	var node := scene.instantiate() as Node3D
	_fx_parent().add_child(node)
	return node


## Dónde cuelgan los efectos de un solo uso: la arena de la etapa actual, o
## la raíz del árbol si no hay etapa.
func _fx_parent() -> Node:
	var parent_node: Node = RunRoot.stage_parent(get_tree())
	if parent_node == null:
		parent_node = get_tree().root
	return parent_node


# --- evolución -------------------------------------------------------------

## Aplica una fila de EvolutionCatalog a esta arma viva: cada entrada de
## "mults" multiplica la propiedad nombrada y cada una de "adds" le suma.
## Idempotente: una segunda llamada no hace nada.
func evolve(row: Dictionary) -> void:
	if evolved:
		return
	evolved = true
	evolved_name = String(row.get("evolved_name", name))
	_apply_stat_tables(row.get("mults", {}), row.get("adds", {}), "evolve")


## Ascenso: la mejora plana, sin receta, que el arma recibe en cada hito de
## EvolutionCatalog.EVOLVE_AT_LEVEL después del primero, así las armas sin
## evolución también siguen mejorando. `tier` es el número de hito
## (1 = nivel 10, 2 = nivel 20...).
func ascend(tier: int) -> void:
	ascension_tier = tier
	var adds: Dictionary[String, int] = {}
	if tier % ASCEND_PROJECTILE_TIER_STEP == 0:
		adds["projectile_count"] = ASCEND_PROJECTILE_ADD
	_apply_stat_tables(ASCEND_MULTS, adds, "ascend")


## Aplica una tabla {propiedad: factor} que multiplica y una
## {propiedad: cantidad} que suma sobre las propiedades de esta arma, por
## nombre con get()/set(), así los ajustes propios de una subclase
## (burst_radius, pierce_count) no necesitan código por arma. La comparten
## evolve() y ascend(); `what` solo nombra al llamador en el aviso.
func _apply_stat_tables(mults: Dictionary, adds: Dictionary, what: String) -> void:
	for property: Variant in mults:
		var current: Variant = get(String(property))
		if current == null:
			push_warning("%s: %s mult on unknown property '%s'" % [name, what, property])
			continue
		# Los ajustes enteros (como pierce_count) se
		# redondean al entero más cercano en vez de truncar: "x1.5" sobre 3
		# da los 5 que promete la carta, no 4.
		if current is int:
			set(String(property), roundi(float(current) * float(mults[property])))
		else:
			set(String(property), float(current) * float(mults[property]))
	for property: Variant in adds:
		var current: Variant = get(String(property))
		if current == null:
			push_warning("%s: %s add on unknown property '%s'" % [name, what, property])
			continue
		if current is int:
			set(String(property), int(current) + int(adds[property]))
		else:
			set(String(property), float(current) + float(adds[property]))
