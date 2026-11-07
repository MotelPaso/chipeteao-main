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
## Edita aquí: altura sobre el origen de un enemigo a la que apuntan todas
## las armas y la persecución de los proyectiles, en metros (el cuerpo, no
## los pies).
const AIM_HEIGHT: float = 0.8

@export_group("Estadísticas")
## Daño por golpe. Valor de respaldo; cada arma fija el suyo en su escena. Lo suben «Afilado», «Temple», «Ritmo de batalla», evoluciones y ascensos.
@export var damage: float = 10.0
## Segundos entre ataques. Valor de respaldo; cada arma fija el suyo en su escena. Lo bajan «Mano rápida» y «Ritmo de batalla».
@export var cooldown: float = 1.0
## Distancia de búsqueda de blanco, en metros. Valor de respaldo; cada arma fija el suyo en su escena. Lo suben «Largo alcance», «Temple» y ascensos.
@export var attack_range: float = 3.0
## Disparos, orbes o golpes por ráfaga (1 salvo que la escena diga otra cosa); el Tomo de Multitud y los ascensos pares suman.
@export var projectile_count: int = 1
## Multiplicador de enfriamiento propio del arma (1 = sin cambio); lo bajan evoluciones, ascensos y cartas como «Ráfaga».
@export var cooldown_scale: float = 1.0

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

## Escalón plano de ascenso, aplicado SOBRE lo que el arma ya es en cada hito
## de EvolutionCatalog.EVOLVE_AT_LEVEL después del primero. Vive aquí y no en
## el catálogo porque no necesita receta: toda arma mejora cada diez niveles.
const ASCEND_MULTS: Dictionary[String, float] = {
	"damage": 1.15, "cooldown_scale": 0.9, "attack_range": 1.1}
## Proyectil extra solo en los tiers PARES (20, 40...): uno por tier haría
## crecer un arma de ráfaga mucho más rápido que los multiplicadores.
const ASCEND_PROJECTILE_TIER_STEP: int = 2
const ASCEND_PROJECTILE_ADD: int = 1

var _cooldown_left: float = 0.0

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


## El montaje que lleva el arma: la mascota si la lleva una, si no el raider.
## Los efectos anclados al portador (el punto de caída de la baba, el centro
## del anillo de orbes) siguen a ESTE; stats, robo de vida y objetos siguen
## leyendo carrier_player().
func carrier_node() -> Node3D:
	var node: Node = self
	while node != null:
		if node is Pet or node is Player:
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
	return stats.area_multiplier if stats != null else 1.0


## Disparos, orbes o flechas por ráfaga: el conteo propio del arma más el
## bono plano del portador (Tomo de Multitud). Las armas leen esto, no
## projectile_count.
func effective_projectile_count() -> int:
	var stats := _stats_or_null()
	return projectile_count + (stats.projectile_bonus if stats != null else 0)


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
		var dist_sq := origin.distance_squared_to(body.global_position)
		if dist_sq <= nearest_dist_sq:
			nearest_dist_sq = dist_sq
			nearest = body
	return nearest


## Virtual: el ataque contra el blanco adquirido.
func fire(_target: Node3D) -> void:
	push_warning("%s: fire() not implemented" % name)


# --- ráfagas del Tomo de Multitud ------------------------------------------

## Ráfaga en abanico: `count` disparos, el del medio hacia `center_dir` y los
## demás girados `fan_deg` grados entre vecinos alrededor de UP. El primero
## sale ya y los demás escalonados (ver volley_step()); `shot` recibe la
## dirección de cada disparo, calculada al disparar.
func fire_volley(count: int, center_dir: Vector3, shot: Callable, stagger: float,
		fan_deg: float) -> void:
	var step := volley_step(count, stagger)
	for i: int in count:
		var yaw := deg_to_rad(fan_deg) * (float(i) - float(count - 1) * 0.5)
		var direction := center_dir.rotated(Vector3.UP, yaw)
		if i == 0:
			shot.call(direction)
		else:
			_schedule_shot(step * float(i), shot.bind(direction))


## Ráfaga sin abanico: `first` sale ya y cada extra llama a `extra`, que
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
## haber salido del árbol con un raider quitado: fuera del árbol no dispara.
func _fire_late(shot: Callable) -> void:
	if is_inside_tree():
		shot.call()


# --- embudo de daño --------------------------------------------------------

## Embudo de daño compartido: aplica el daño efectivo, tira el crítico y cura
## al portador por robo de vida. Todo golpe de arma pasa por aquí.
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
	var is_crit := stats != null and randf() < stats.crit_chance
	if is_crit:
		amount *= stats.crit_damage
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
	if stats != null and stats.lifesteal > 0.0:
		_lifesteal_heal(applied * stats.lifesteal)
	# Ganchos de objetos: veneno al golpear, arañas al matar.
	if _bag != null and is_instance_valid(_bag):
		var body := target_health.get_parent() as Node3D
		if body != null:
			_bag.on_weapon_hit(body)
			if allow_kill_hooks and target_health.is_dead:
				_bag.on_weapon_kill(body.global_position, self)
	return applied


func _lifesteal_heal(amount: float) -> void:
	var player := carrier_player()
	if player == null:
		return
	var player_health := Health.find_in(player)
	if player_health != null:
		player_health.heal(amount)


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

## Enemigos vivos dentro de un disco plano: a `radius` o menos de `center` en
## el plano XZ y a no más de `height_window` por encima o por debajo. El filtro
## de altura evita que un charco en el suelo alcance cuerpos sobre una cornisa.
func enemies_in_disc(center: Vector3, radius: float, height_window: float) -> Array[Node3D]:
	var found: Array[Node3D] = []
	var radius_sq := radius * radius
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var body := node as Node3D
		if body == null or not body.is_inside_tree():
			continue
		var to_body := body.global_position - center
		if absf(to_body.y) > height_window:
			continue
		to_body.y = 0.0
		if to_body.length_squared() <= radius_sq:
			found.append(body)
	return found


## Enemigos vivos dentro de una esfera de `radius` alrededor de `center`: los
## estallidos que también deben alcanzar cuerpos por encima o por debajo.
func enemies_in_sphere(center: Vector3, radius: float) -> Array[Node3D]:
	var found: Array[Node3D] = []
	var radius_sq := radius * radius
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var body := node as Node3D
		if body == null or not body.is_inside_tree():
			continue
		if center.distance_squared_to(body.global_position) <= radius_sq:
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
		var along := to_body.dot(direction)
		if along < 0.0 or along > length:
			continue
		if (to_body - direction * along).length() <= half_width:
			found.append(body)
	return found


## Enemigos vivos dentro de un cono plano de `arc_deg` alrededor de
## `center_dir`, hasta `reach` (medido en 3D desde `center`). Un cuerpo encima
## del atacante no tiene dirección usable, así que siempre cuenta como dentro.
func enemies_in_arc(center: Vector3, center_dir: Vector3, reach: float,
		arc_deg: float) -> Array[Node3D]:
	var found: Array[Node3D] = []
	var reach_sq := reach * reach
	var half_arc := deg_to_rad(arc_deg * 0.5)
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var body := node as Node3D
		if body == null or not body.is_inside_tree():
			continue
		var body_position := body.global_position
		if center.distance_squared_to(body_position) > reach_sq:
			continue
		var to_body := body_position - center
		to_body.y = 0.0
		if to_body.length_squared() > DEGENERATE_LENGTH_SQ \
				and center_dir.angle_to(to_body) > half_arc:
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


## Punto del cuerpo de `target` al que se apunta: AIM_HEIGHT sobre su origen.
static func body_aim_point(target: Node3D) -> Vector3:
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
		# Los ajustes enteros (projectile_count, pierce_count, chain_count) se
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
