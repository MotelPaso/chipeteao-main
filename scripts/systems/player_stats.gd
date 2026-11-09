class_name PlayerStats
extends Node
## Capa de stats derivadas del jugador y portador de tomos en un solo nodo,
## montado en el Player junto al montaje Weapons. Guarda las copias de tomos
## de esta partida y la pasiva del personaje, y recalcula cada stat derivada
## DESDE CERO en cada cambio (tomo, subida de nivel, objeto, boon), así la
## acumulación nunca se desvía. Los consumidores quedan desacoplados: las
## armas leen los multiplicadores con los helpers de WeaponBase, la armadura
## se empuja al Health hermano y UpgradePool lee la suerte al sortear rarezas.

## Pisos de los multiplicadores que un debuff podría llevar a cero (o
## menos): un raider maldito sigue pegando, moviéndose, ganando XP y con
## sus efectos activos, por muchos boons negativos que se acumulen.
const MIN_DAMAGE_MULTIPLIER: float = 0.1
const MIN_MOVE_MULTIPLIER: float = 0.2
const MIN_DURATION_MULTIPLIER: float = 0.1
const MIN_XP_MULTIPLIER: float = 0.1
## Techo de saltos extra. No es gusto: el raider no tiene más control en el
## aire que air_acceleration, y pasado esto la verticalidad de una arena
## (mesetas, plataformas, el borde) deja de ser un obstáculo.
const MAX_EXTRA_JUMPS: int = 5
## Cada tipo que _apply_character_passive sabe correr; una fila fuera de esta
## lista se rechaza al asignarla, no una vez por recompute.
const PASSIVE_KINDS: Array[String] = ["per_level", "evasion_execute", "speed_to_damage"]

@export_group("Base")
## Multiplicador de daño crítico antes de cualquier bono del Tomo de Ruina.
@export var base_crit_damage: float = 5.0
## Suerte base (puntos de inclinación de rareza) antes de cualquier bono.
@export var base_luck: float = 0.0

@export_group("Topes")
## Por mucha velocidad de ataque acumulada, el multiplicador global de
## enfriamiento nunca baja de esto.
@export var min_cooldown_multiplier: float = 0.25
## La evasión nunca supera esta probabilidad de esquivar (0-1), sumen lo que
## sumen las fuentes.
@export var max_evasion: float = 0.6
## Las pasivas de esquivar-ejecutar matan a un atacante no jefe cuya
## fracción de HP sea menor que esto al esquivar. Hoy ningún personaje usa
## el tipo "evasion_execute", así que no ajusta nada.
@export var execute_threshold: float = 0.25
@export_group("")

# Valores derivados: cámbialos con add_tome()/recompute(), nunca a mano.
var damage_multiplier: float = 1.0
var cooldown_multiplier: float = 1.0
var area_multiplier: float = 1.0
var move_speed_multiplier: float = 1.0
var crit_chance: float = 0.0
## Derivado: recompute() lo parte de base_crit_damage (el valor real, aunque
## aquí diga 2.0 antes del primer recompute en _ready).
var crit_damage: float = 2.0
var lifesteal: float = 0.0
var armor: float = 0.0
var luck: float = 0.0
## Probabilidad (0-1, con techo max_evasion) de esquivar por completo un
## golpe; la tira el Health hermano en cada golpe.
var evasion: float = 0.0
## Daño fijo que se devuelve a un atacante de contacto cada vez que golpean
## al jugador.
var thorns: float = 0.0
## HP máx. por encima del max_hp propio del Health (que las cartas genéricas
## de Corazón robusto también suben); se empuja al Health como DELTA.
var bonus_max_hp: float = 0.0
## Proyectiles extra en toda arma de andanada
## (WeaponBase.effective_projectile_count).
var projectile_bonus: int = 0
## Multiplicador de los efectos temporizados de las armas — ralentizaciones,
## charcos, veneno (WeaponBase.duration_scale).
var duration_multiplier: float = 1.0
## Multiplicador de la XP que recoge este raider (XpGem lo aplica al tomarla).
var xp_multiplier: float = 1.0
## Aporte de este raider a la dificultad DE LA PARTIDA (fracción); se publica
## en RunState con una clave por jugador en cada recompute.
var difficulty_share: float = 0.0
## Copias de Tomo del Azar tomadas; los boons sacados viven en _gamble_boons
## y se repiten en cada recompute.
var gambling_stacks: int = 0
## Saltos extra en el aire antes de volver a tocar el suelo (Player._try_jump).
var extra_jumps: int = 0
## Bono, en %, a la probabilidad de drop de power-ups. Lo lee
## EnemySpawner.roll_powerup_drop y lo venden los altares («Fortuna menor»).
var powerup_drop_chance: float = 0.0

## id de tomo -> una potencia de rareza por copia recogida. recompute()
## deriva todo de aquí: es la única fuente de verdad.
var _tome_stacks: Dictionary[String, PackedFloat32Array] = {}
## Resultados del Tomo del Azar, sacados UNA vez al tomarlo y repetidos por
## recompute(): [{stat, amount}] ya escalados por potencia.
var _gamble_boons: Array[Dictionary] = []
## Boons de altar: efectos fijos permanentes que dan los altares de carga y
## demoníacos y la ruleta, aparte de cartas y tomos.
var _altar_boons: Array[Dictionary] = []


## Boons temporales (manantiales, maldiciones de la ruleta, power-ups):
## {stat, amount, expires_at, tag} en segundos de RunState.run_time; se
## quitan (con un recompute) al expirar. El harness lo lee por nombre
## (arena_probe.gd: stats.get("_timed_boons")).
var _timed_boons: Array[Dictionary] = []

## Pasiva del personaje (datos de la fila de CharacterCatalog). Tipos:
##   "per_level":       _passive_stat gana _passive_base más _passive_amount
##                      por cada nivel pasado el 1.
##   "speed_to_damage": la velocidad de movimiento extra se convierte en daño
##                      extra a razón de _passive_amount (0.6 = +0.6% de daño
##                      por cada +1% de velocidad).
##   "evasion_execute": escala como per_level y además cada esquive ejecuta
##                      a un atacante no jefe debilitado (_on_dodged). Hoy
##                      ningún personaje lo usa.
## Un id de stat vacío con un tipo por nivel = sin pasiva.
var _passive_kind: String = "per_level"
var _passive_stat: String = ""
var _passive_amount: float = 0.0
var _passive_base: float = 0.0

## Parte de bonus_max_hp ya aplicada al Health, para que cada recompute
## ajuste por la diferencia en vez de volver a sumar todo el bono.
var _applied_bonus_max_hp: float = 0.0
## True mientras corre recompute() (ver is_recomputing).
var _recomputing: bool = false


func _ready() -> void:
	# Las pasivas escalan con el nivel de la partida, así que cada subida
	# vuelve a derivar las stats (desde cero, igual que al tomar un tomo).
	RunState.leveled_up.connect(_on_leveled_up)
	# Espinas: el Health hermano nombra a los atacantes de contacto.
	var health := Health.find_in(get_parent())
	if health != null:
		health.damaged_by.connect(_on_damaged_by)
		# Las pasivas de esquivar-ejecutar se resuelven con el esquive que
		# tiró el Health.
		health.dodged.connect(_on_dodged)
	recompute()


## El componente PlayerStats de un cuerpo, o null si no tiene.
static func find_in(body: Node) -> PlayerStats:
	if body == null:
		return null
	for child in body.get_children():
		if child is PlayerStats:
			return child
	return null


func stack_count(tome_id: String) -> int:
	if not _tome_stacks.has(tome_id):
		return 0
	return _tome_stacks[tome_id].size()


## Cantidad de tomos DISTINTOS llevados (el tope de tomos cuenta estos).
func distinct_tome_count() -> int:
	var count := 0
	for tome_id: String in _tome_stacks:
		if _tome_stacks[tome_id].size() > 0:
			count += 1
	return count


## Ids de cada tomo llevado, en orden de recolección (franja del HUD).
func carried_tome_ids() -> Array[String]:
	var ids: Array[String] = []
	for tome_id: String in _tome_stacks:
		if _tome_stacks[tome_id].size() > 0:
			ids.append(tome_id)
	return ids


## Da una copia de un tomo a la potencia de rareza dada. Las copias NO tienen
## techo; solo se limita la cantidad de tomos DISTINTOS (Player.max_tomes, lo
## aplica el pool de ofertas). Devuelve los boons que acaba de sacar un Tomo
## del Azar, para que la carta avise lo que pagó la apuesta; vacío para
## cualquier otro tomo.
func add_tome(tome_id: String, potency: float) -> Array[Dictionary]:
	# Los arrays empaquetados dentro de diccionarios se copian al escribir:
	# se modifica una copia y se vuelve a guardar.
	var stacks: PackedFloat32Array = _tome_stacks.get(tome_id, PackedFloat32Array())
	stacks.append(potency)
	_tome_stacks[tome_id] = stacks
	# Los tomos de azar sacan sus boons aquí, una vez, así el resultado queda
	# fijo para la partida y recompute() solo lo repite.
	var tome := Tome.by_id(tome_id)
	var rolled: Array[Dictionary] = []
	if bool(tome.get("gamble", false)):
		rolled = roll_gamble_boons(potency)
		_gamble_boons.append_array(rolled)
	recompute()
	return rolled


## Tirada del Tomo del Azar: potencia 1 (Común) da un boon de tamaño base;
## cada rareza mayor suma un boon y escala todos por la potencia (Raro
## 1.5x/2 boons, Épico 2x/3, Legendario 3x/4). Stats distintas por tirada.
## Estática y pura, para que un harness pueda verificar la distribución.
## Orden del RNG: un shuffle por tirada, en el momento de tomar el tomo.
static func roll_gamble_boons(potency: float) -> Array[Dictionary]:
	var count := Tome.gamble_boon_count(potency)
	var pool := Tome.GAMBLE_BOONS.duplicate()
	pool.shuffle()
	var boons: Array[Dictionary] = []
	for i in mini(count, pool.size()):
		var boon: Dictionary = pool[i]
		boons.append({
			"stat": String(boon.stat),
			"amount": roundf(float(boon.amount) * potency),
			# Viaja con el boon para que el aviso del HUD lea la tirada.
			"label": String(boon.get("label", "")),
		})
	return boons


## Los boons sacados hasta ahora (HUD/pruebas), en orden de recolección.
func gamble_boons() -> Array[Dictionary]:
	return _gamble_boons


## Boon fijo permanente fuera de cartas y tomos (altares, ruleta).
func add_altar_boon(stat: String, amount: float) -> void:
	_altar_boons.append({"stat": stat, "amount": amount})
	recompute()


func altar_boons() -> Array[Dictionary]:
	return _altar_boons


## Boon temporal por `duration` segundos de partida (amounts negativos son
## debuffs). La expiración se sondea en _physics_process.
##
## `tag` agrupa boons de UNA fuente que se puede volver a dar (un power-up
## tomado otra vez mientras sigue activo). Sin él una renovación se suma a sí
## misma: la segunda Furia sumaría otro +50% de daño y la primera expiración
## quitaría solo la mitad.
func add_timed_boon(stat: String, amount: float, duration: float, tag: String = "") -> void:
	if duration <= 0.0:
		return
	_timed_boons.append({
		"stat": stat, "amount": amount, "expires_at": RunState.run_time + duration,
		"tag": tag})
	recompute()


## Quita todo boon vivo con `tag` (una etiqueta vacía no coincide con nada,
## así los boons sin etiqueta nunca se borran por error). Devuelve true si
## quitó algo.
func clear_timed_boons(tag: String) -> bool:
	if tag.is_empty():
		return false
	var removed := false
	for i in range(_timed_boons.size() - 1, -1, -1):
		if String(_timed_boons[i].get("tag", "")) == tag:
			_timed_boons.remove_at(i)
			removed = true
	if removed:
		recompute()
	return removed


func timed_boon_count() -> int:
	return _timed_boons.size()


func _physics_process(_delta: float) -> void:
	if _timed_boons.is_empty():
		return
	var expired := false
	for i in range(_timed_boons.size() - 1, -1, -1):
		if RunState.run_time >= float(_timed_boons[i].expires_at):
			_timed_boons.remove_at(i)
			expired = true
	if expired:
		recompute()


## Registra la pasiva del personaje elegido (los ids de stat son los de
## _apply_effect; los tipos se documentan en _passive_kind). base_amount ya
## se da en el nivel 1 (el robo de vida inicial de Doc). Lo llama el jugador
## al aparecer con los datos de la fila del catálogo.
func set_character_passive(stat: String, amount: float, kind: String = "per_level",
		base_amount: float = 0.0) -> void:
	if not PASSIVE_KINDS.has(kind):
		# Se valida UNA vez, aquí; en el camino del recompute avisaría varias
		# veces por segundo toda la partida.
		push_warning("PlayerStats: unknown passive kind '%s'" % kind)
		kind = "per_level"
	_passive_kind = kind
	_passive_stat = stat
	_passive_amount = amount
	_passive_base = base_amount
	recompute()


## True mientras corre recompute(). _push_bonus_max_hp_to_health escribe
## max_hp y cura DENTRO de esa llamada, y ambas cosas emiten hp_changed: un
## oyente que puede pedir otro recompute (Zenkai) tiene que distinguir "el
## raider se curó" de "la capa de stats se reconstruyó".
func is_recomputing() -> bool:
	return _recomputing


## Reconstruye cada stat derivada desde los tomos guardados, la pasiva y las
## demás fuentes (recalcular, no acumular). Llámala tras cualquier cambio.
## Cuatro fases, en este orden y no otro: todo a la base, todas las fuentes,
## los techos y el empuje a los consumidores externos.
func recompute() -> void:
	_recomputing = true
	_reset_derived()
	_apply_sources()
	_clamp_derived()
	_publish_derived()
	_recomputing = false


## Cada campo derivado a su base (el valor sin fuentes).
func _reset_derived() -> void:
	damage_multiplier = 1.0
	cooldown_multiplier = 1.0
	area_multiplier = 1.0
	move_speed_multiplier = 1.0
	crit_chance = 0.0
	crit_damage = base_crit_damage
	lifesteal = 0.0
	armor = 0.0
	luck = base_luck
	evasion = 0.0
	thorns = 0.0
	bonus_max_hp = 0.0
	projectile_bonus = 0
	duration_multiplier = 1.0
	xp_multiplier = 1.0
	difficulty_share = 0.0
	gambling_stacks = 0
	extra_jumps = 0
	powerup_drop_chance = 0.0


## Todas las fuentes, en el ÚNICO orden que importa: la pasiva del personaje
## va al final porque los tipos de conversión (speed_to_damage) leen los
## totales que armaron las demás fuentes.
func _apply_sources() -> void:
	_apply_tomes()
	# Los boons de azar se repiten en orden de recolección (ya escalados).
	_apply_boons(_gamble_boons)
	# Objetos: cada copia de un objeto de stats aporta los efectos de su fila
	# por el mismo canal.
	_apply_items()
	# La stat de la mascota: un espacio, una fila, escalada por nivel.
	_apply_pet_stat()
	# Boons de altar y boons temporales vivos.
	_apply_boons(_altar_boons)
	_apply_boons(_timed_boons)
	# Zenkai: un canal permanente de todas las stats, leído de las
	# acumulaciones que guardó la bolsa. Igual que los power-ups de abajo: una
	# cuenta guardada que se vuelve a aplicar en cada reconstrucción, nunca
	# acumulada sobre un valor derivado que _reset_derived borraría.
	_apply_zenkai()
	# Power-ups: el HP máx. permanente del vampiro es un TOTAL GUARDADO en el
	# componente, que se vuelve a sumar aquí en cada recompute.
	_apply_powerups()
	# Reliquias de la Armería: rangos meta permanentes, por el mismo canal de
	# efectos que los tomos para que la acumulación sea idéntica.
	_apply_relics()
	_apply_character_passive()


func _apply_tomes() -> void:
	for tome_id: String in _tome_stacks:
		var tome := Tome.by_id(tome_id)
		if tome.is_empty():
			push_warning("PlayerStats: unknown tome '%s'" % tome_id)
			continue
		# Se cuenta con las copias mismas y no con el amount del efecto: el
		# efecto está escalado por potencia, la cuenta de copias no.
		if bool(tome.get("gamble", false)):
			gambling_stacks += _tome_stacks[tome_id].size()
		var effects: Array = tome.effects
		for potency: float in _tome_stacks[tome_id]:
			for effect: Dictionary in effects:
				# roundf coincide con el texto de la carta: lo mostrado es lo
				# aplicado.
				_apply_effect(String(effect.stat), roundf(float(effect.amount) * potency))


## Una lista de boons {stat, amount} por el canal de efectos. Los boons de
## azar, de altar y temporales comparten esa forma, y por eso el bucle.
func _apply_boons(boons: Array[Dictionary]) -> void:
	for boon: Dictionary in boons:
		_apply_effect(String(boon.stat), float(boon.amount))


## Los techos, después de todas las fuentes: la acumulación es aditiva, y sin
## esto una build profunda llegaría a cero enfriamiento o 100% de esquive.
func _clamp_derived() -> void:
	cooldown_multiplier = maxf(cooldown_multiplier, min_cooldown_multiplier)
	damage_multiplier = maxf(damage_multiplier, MIN_DAMAGE_MULTIPLIER)
	move_speed_multiplier = maxf(move_speed_multiplier, MIN_MOVE_MULTIPLIER)
	crit_chance = clampf(crit_chance, 0.0, 1.0)
	evasion = clampf(evasion, 0.0, max_evasion)
	luck = maxf(luck, 0.0)
	duration_multiplier = maxf(duration_multiplier, MIN_DURATION_MULTIPLIER)
	xp_multiplier = maxf(xp_multiplier, MIN_XP_MULTIPLIER)
	projectile_bonus = maxi(projectile_bonus, 0)


## Empuja los totales a los consumidores que no pueden leerlos solos: el
## Health hermano (armadura, HP máx. extra) y la dificultad de la partida.
func _publish_derived() -> void:
	_push_armor_to_health()
	_push_bonus_max_hp_to_health()
	_publish_difficulty()


## La dificultad es compartida, así que cada raider publica su total con
## una clave por espacio; RunState suma las fuentes (seguro con recompute).
func _publish_difficulty() -> void:
	var parent := get_parent()
	var slot := int(parent.get("player_index")) if parent != null and parent.get("player_index") != null else 0
	RunState.set_difficulty_source("tomes_p%d" % slot, difficulty_share)


## Cuentas del ItemBag hermano x efectos del catálogo (sin bolsa, sin
## objetos). Los efectos de una fila escalan con las copias llevadas.
func _apply_items() -> void:
	var bag := ItemBag.find_in(get_parent())
	if bag == null:
		return
	for item_id: String in bag.carried_ids():
		var row := ItemCatalog.by_id(item_id)
		var copies := bag.count(item_id)
		for effect: Dictionary in row.get("effects", [] as Array):
			_apply_effect(String(effect.stat), float(effect.amount) * float(copies))


## La stat de la mascota, que escala con el nivel de la partida como una
## pasiva. Se lee del espacio único de mascota del raider: tiene un id o
## ninguno, y no hay copias por las que escalar.
func _apply_pet_stat() -> void:
	var body := get_parent()
	if body == null:
		return
	var pet_id: Variant = body.get("pet_id")
	if pet_id == null or String(pet_id).is_empty():
		return
	var pet := PetCatalog.by_id(String(pet_id))
	var stat := String(pet.get("stat", ""))
	if stat.is_empty():
		return
	_apply_effect(stat, float(pet.get("amount_per_level", 0.0)) * float(RunState.level))


## Las acumulaciones de Zenkai suben TODAS las stats que importan un % fijo
## cada una. Amplio a propósito: el objeto es Legendario, solo paga cuando el
## raider volvió desde muy poco HP, y un bono estrecho no se notaría junto a
## los tomos ya acumulados para entonces.
func _apply_zenkai() -> void:
	var bag := ItemBag.find_in(get_parent())
	if bag == null:
		return
	var stacks := bag.zenkai_stacks
	if stacks <= 0:
		return
	# El % por acumulación y las stats viven en la fila de Zenkai
	# (ItemCatalog). max_hp y luck son canales fijos: ahí el mismo número se
	# lee como puntos, no como %.
	var row := ItemCatalog.kind_row("zenkai")
	var percent := float(stacks) * float(row.percent_per_stack)
	for stat: Variant in (row.stats as Array):
		_apply_effect(String(stat), percent)


## Totales permanentes que guardan los power-ups («Modo vampiro» sube el HP
## máx. por baja). El componente es dueño del número; esto solo lo aplica.
func _apply_powerups() -> void:
	var powerups := PowerUps.find_in(get_parent())
	if powerups == null or is_zero_approx(powerups.permanent_max_hp):
		return
	_apply_effect("max_hp", powerups.permanent_max_hp)


## Cada rango de la Armería aporta el efecto de su fila (SaveData guarda los
## rangos; un guardado nuevo no aporta nada).
func _apply_relics() -> void:
	for relic: Dictionary in RelicCatalog.RELIC_LIBRARY:
		var rank := SaveData.relic_rank(String(relic.id))
		if rank > 0:
			_apply_effect(String(relic.stat), float(relic.amount) * float(rank))


## Aplica la pasiva del personaje según su tipo (datos de la fila del
## catálogo; sin ramas por personaje).
func _apply_character_passive() -> void:
	match _passive_kind:
		"per_level", "evasion_execute":
			# El nivel 1 aporta solo la base; cada nivel ganado suma un
			# incremento (sin roundf: los pasos de menos de 1% deben sumarse).
			# "evasion_execute" además mata al esquivar, en _on_dodged.
			if not _passive_stat.is_empty():
				_apply_effect(_passive_stat, _passive_base
						+ _passive_amount * float(maxi(RunState.level - 1, 0)))
		"speed_to_damage":
			# La velocidad extra (multiplicador sobre 1) se convierte en bono
			# directo del multiplicador de daño a la razón configurada.
			damage_multiplier += maxf(move_speed_multiplier - 1.0, 0.0) * _passive_amount


## Un efecto, ya escalado por potencia, sobre los totales en curso. Las stats
## en % se suman (+15% dos veces = +30%); armadura y suerte son fijas.
## Los brazos del match son contrato: el lint de catálogos (catalog_lint.gd)
## lee este bloque del código fuente para validar los ids de stat.
func _apply_effect(stat: String, amount: float) -> void:
	match stat:
		"damage":
			damage_multiplier += amount / 100.0
		"cooldown":
			cooldown_multiplier -= amount / 100.0
		"area":
			area_multiplier += amount / 100.0
		"move_speed":
			move_speed_multiplier += amount / 100.0
		"crit_chance":
			crit_chance += amount / 100.0
		"crit_damage":
			crit_damage += amount / 100.0
		"lifesteal":
			lifesteal += amount / 100.0
		"evasion":
			evasion += amount / 100.0
		"armor":
			armor += amount
		"luck":
			luck += amount
		"thorns":
			thorns += amount
		"max_hp":
			bonus_max_hp += amount
		"projectiles":
			projectile_bonus += roundi(amount)
		"duration":
			duration_multiplier += amount / 100.0
		"xp_gain":
			xp_multiplier += amount / 100.0
		"difficulty":
			difficulty_share += amount / 100.0
		"jumps":
			extra_jumps = mini(extra_jumps + roundi(amount), MAX_EXTRA_JUMPS)
		"powerup_chance":
			powerup_drop_chance += amount
		"gambling":
			# Sin efecto a propósito: los boons se sacaron al tomar el tomo y
			# se repiten desde _gamble_boons, y gambling_stacks cuenta COPIAS,
			# que _apply_tomes lee de la lista de copias (este amount está
			# escalado por potencia: contaría 3 por una copia Legendaria).
			pass
		_:
			push_warning("PlayerStats: unknown effect stat '%s'" % stat)


func _on_leveled_up(_new_level: int) -> void:
	recompute()


## Health aplica la armadura él mismo en take_damage, así la reducción cubre
## también daño que no viene de un arma (golpes de contacto).
func _push_armor_to_health() -> void:
	var health := _sibling_health()
	if health != null:
		health.armor = armor


## Health.max_hp es estado compartido (las cartas de Corazón robusto le suman
## directo), así que el bono se aplica como delta de lo ya empujado. Una
## subida también cura por el delta — con techo en heal(), nunca sobrecura;
## una bajada no necesita nada aquí, porque el setter de Health.max_hp
## recorta current_hp y avisa el cambio (un cuerpo derribado queda en 0 y
## revive con una fracción del máximo que tenga entonces).
func _push_bonus_max_hp_to_health() -> void:
	var health := _sibling_health()
	if health == null:
		return
	var delta := bonus_max_hp - _applied_bonus_max_hp
	if is_zero_approx(delta):
		return
	_applied_bonus_max_hp = bonus_max_hp
	health.max_hp += delta
	if delta > 0.0:
		health.heal(delta)


## Esquivar-ejecutar (tipo "evasion_execute"): un esquive exitoso mata al
## atacante si es un enemigo no jefe por debajo del umbral de ejecución — por
## take_damage, así el flujo normal de muerte (crédito, gema, animación)
## corre igual.
func _on_dodged(attacker: Node3D) -> void:
	if _passive_kind != "evasion_execute":
		return
	if attacker == null or not is_instance_valid(attacker) \
			or attacker.is_in_group("boss"):
		return
	var attacker_health := Health.find_in(attacker)
	if attacker_health == null or attacker_health.is_dead:
		return
	if attacker_health.current_hp >= attacker_health.max_hp * execute_threshold:
		return
	# current_hp más la armadura garantiza que el daño tras armadura mate.
	attacker_health.take_damage(attacker_health.current_hp + attacker_health.armor)


## Espinas: devuelve daño fijo a quien acaba de golpear al jugador por
## contacto. Los golpes reflejados no nombran atacante, así dos parties con
## espinas nunca rebotan entre sí.
func _on_damaged_by(attacker: Node3D) -> void:
	if thorns <= 0.0 or attacker == null or not is_instance_valid(attacker):
		return
	var attacker_health := Health.find_in(attacker)
	if attacker_health != null:
		attacker_health.take_damage(thorns)


func _sibling_health() -> Health:
	var parent := get_parent()
	return Health.find_in(parent) if parent != null else null
