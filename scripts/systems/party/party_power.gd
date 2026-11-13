class_name PartyPower
extends Node
## Poder de la party en la partida actual: cuánto daño hacen sus armas por
## segundo y un puntaje de sus «poderes» (armas, tomos, objetos, power-ups y
## mascotas), cada uno con su peso. Es el nodo RunSystems.tscn > PartyPower:
## nace y muere con la partida, y sus pesos se editan en su Inspector.
## El daño llega desde WeaponBase.deal_damage (record_weapon_damage). El
## veneno, las espinas, los siervos y el clima no pasan por ahí y no cuentan.
## Lo leen los jefes de etapa (StageBossScaling) por el grupo "party_power".
##
## Lleva DOS medidas del mismo embudo:
##   dps()        la vida que los golpes quitaron de verdad a la horda. Un
##                golpe que sobra sobre un cuerpo casi muerto solo cuenta lo
##                que quedaba, y un pulso de área cuenta una vez por cuerpo.
##   focus_dps()  lo que esas mismas armas le harían a UN cuerpo con mucha
##                vida: la tirada entera de cada golpe y, de un arma que
##                golpea a varios cuerpos en el mismo frame, solo el golpe
##                más fuerte. Es la que sirve para presupuestar un jefe.

## Cada golpe de arma que quitó vida: el arma, el cuerpo golpeado y la vida
## que quitó. El harness de soak la escucha.
signal weapon_damage_dealt(weapon: WeaponBase, target: Node3D, amount: float)

const GROUP := &"party_power"
## Segundos de historia que guarda el medidor, un cubo por segundo de
## partida. Ninguna ventana pedida a dps() puede pasar de aquí.
const HISTORY_SECONDS: int = 180

@export_group("Peso de las armas")
## Puntos de poder por cada arma equipada.
@export var weapon_weight: float = 2.0
## Puntos de poder por cada carta de mejora que recibió un arma.
@export var weapon_level_weight: float = 0.35
## Puntos de poder extra por un arma evolucionada.
@export var weapon_evolved_weight: float = 3.0
## Puntos de poder por cada ascenso de un arma (cada diez niveles tras el primero).
@export var weapon_ascension_weight: float = 2.0

@export_group("Peso del resto")
## Puntos de poder por cada tomo distinto.
@export var tome_weight: float = 1.0
## Puntos de poder por cada nivel de tomo (cada vez que se eligió).
@export var tome_stack_weight: float = 0.35
## Puntos de poder por cada objeto que lleva un raider (cada copia cuenta).
@export var item_weight: float = 0.6
## Puntos de poder por cada power-up activo en este momento.
@export var powerup_weight: float = 2.0
## Puntos de poder por llevar mascota.
@export var pet_weight: float = 2.0

@export_group("Registro")
## Segundos de partida entre líneas "Party power:" del log (0 = nunca).
@export var log_interval: float = 60.0
## Ventana, en segundos, del DPS que muestra esa línea.
@export var log_window: float = 30.0

## El nodo de la partida viva: deal_damage corre cientos de veces por
## segundo y no puede buscar un grupo en cada golpe.
static var _live: PartyPower = null

## Segundo de partida al que pertenece cada cubo (-1 = vacío), el daño real
## sumado en él y el daño a un solo cuerpo. Se reusan en anillo: el índice es
## el segundo módulo HISTORY_SECONDS.
var _bucket_second: PackedInt32Array = PackedInt32Array()
var _bucket_damage: PackedFloat32Array = PackedFloat32Array()
var _bucket_focus: PackedFloat32Array = PackedFloat32Array()
## Por arma (id de instancia): el frame de física de su último golpe y la
## tirada más alta de ese frame, para contar un pulso de área una sola vez.
var _focus_frame: Dictionary[int, int] = {}
var _focus_peak: Dictionary[int, float] = {}
var _next_log: float = 0.0


func _enter_tree() -> void:
	_live = self
	add_to_group(GROUP)


func _exit_tree() -> void:
	if _live == self:
		_live = null


func _ready() -> void:
	_bucket_second.resize(HISTORY_SECONDS)
	_bucket_second.fill(-1)
	_bucket_damage.resize(HISTORY_SECONDS)
	_bucket_damage.fill(0.0)
	_bucket_focus.resize(HISTORY_SECONDS)
	_bucket_focus.fill(0.0)
	_next_log = log_interval


func _physics_process(_delta: float) -> void:
	if log_interval <= 0.0 or not RunState.run_active or RunState.run_time < _next_log:
		return
	_next_log += log_interval
	print(log_line())


## El nodo de la partida, o null fuera de una partida.
static func find(tree: SceneTree) -> PartyPower:
	return tree.get_first_node_in_group(GROUP) as PartyPower if tree != null else null


## Puerta del embudo de daño (WeaponBase.deal_damage): `applied` es la vida
## que el golpe quitó de verdad y `rolled` la tirada entera (con crítico).
## Estática para que el arma no busque nada.
static func record_weapon_damage(weapon: WeaponBase, target: Health, applied: float,
		rolled: float) -> void:
	if _live == null or applied <= 0.0:
		return
	_live._add(weapon, applied, rolled)
	_live.weapon_damage_dealt.emit(weapon, target.get_parent() as Node3D, applied)


## Daño de armas por segundo que la party le quitó de verdad a la horda en
## los últimos `window_seconds` de partida. Con menos partida que ventana,
## promedia sobre lo jugado.
func dps(window_seconds: float) -> float:
	return _window_average(_bucket_damage, window_seconds)


## Daño por segundo que esas mismas armas le harían a un solo cuerpo con
## mucha vida, en los últimos `window_seconds` de partida.
func focus_dps(window_seconds: float) -> float:
	return _window_average(_bucket_focus, window_seconds)


## Puntaje de poder de toda la party (de pie y caídos).
func score() -> float:
	return breakdown()["total"]


## El puntaje por tipo de poder: weapons, tomes, items, powerups, pets y total.
func breakdown() -> Dictionary[String, float]:
	var parts: Dictionary[String, float] = {
		"weapons": 0.0, "tomes": 0.0, "items": 0.0, "powerups": 0.0, "pets": 0.0,
	}
	for group: String in ["player", "downed_players"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var raider := node as Player
			if raider == null:
				continue
			parts["weapons"] += _weapons_score(raider)
			parts["tomes"] += _tomes_score(raider)
			parts["items"] += _items_score(raider)
			var powerups := PowerUps.find_in(raider)
			if powerups != null:
				parts["powerups"] += powerup_weight * float(powerups.count())
			if not raider.pet_id.is_empty():
				parts["pets"] += pet_weight
	parts["total"] = parts["weapons"] + parts["tomes"] + parts["items"] \
			+ parts["powerups"] + parts["pets"]
	return parts


## Línea de log con el DPS y el puntaje desglosado (los soaks la leen).
func log_line() -> String:
	var parts := breakdown()
	return ("Party power: t=%.0fs players=%d dps=%.1f focus=%.1f score=%.1f weapons=%.1f"
			+ " tomes=%.1f items=%.1f powerups=%.1f pets=%.1f") % [
			RunState.run_time, maxi(Coop.player_count, 1), dps(log_window),
			focus_dps(log_window), parts["total"], parts["weapons"], parts["tomes"],
			parts["items"], parts["powerups"], parts["pets"]]


func _add(weapon: WeaponBase, applied: float, rolled: float) -> void:
	var second := int(RunState.run_time)
	var index := second % HISTORY_SECONDS
	if _bucket_second[index] != second:
		_bucket_second[index] = second
		_bucket_damage[index] = 0.0
		_bucket_focus[index] = 0.0
	_bucket_damage[index] += applied
	# A un solo cuerpo: de los golpes de un arma en el mismo frame solo cuenta
	# el más fuerte, así un pulso que alcanza a veinte cuerpos vale por uno.
	var id := weapon.get_instance_id()
	var frame := Engine.get_physics_frames()
	if _focus_frame.get(id, -1) != frame:
		_focus_frame[id] = frame
		_focus_peak[id] = rolled
		_bucket_focus[index] += rolled
	elif rolled > _focus_peak[id]:
		_bucket_focus[index] += rolled - _focus_peak[id]
		_focus_peak[id] = rolled


## Promedio por segundo de `buckets` sobre los últimos `window_seconds`.
func _window_average(buckets: PackedFloat32Array, window_seconds: float) -> float:
	var now := RunState.run_time
	var span := minf(clampf(window_seconds, 1.0, float(HISTORY_SECONDS - 1)), maxf(now, 1.0))
	var newest := int(now)
	var oldest := maxi(newest - ceili(span) + 1, 0)
	var total := 0.0
	for second: int in range(oldest, newest + 1):
		var index := second % HISTORY_SECONDS
		if _bucket_second[index] == second:
			total += buckets[index]
	return total / span


func _weapons_score(raider: Player) -> float:
	var total := 0.0
	for child: Node in raider.weapons_mount.get_children():
		var weapon := child as WeaponBase
		if weapon == null:
			continue
		total += weapon_weight + weapon_level_weight * float(weapon.upgrade_level) \
				+ weapon_ascension_weight * float(weapon.ascension_tier)
		if weapon.evolved:
			total += weapon_evolved_weight
	return total


func _tomes_score(raider: Player) -> float:
	var stats := PlayerStats.find_in(raider)
	if stats == null:
		return 0.0
	var stacks := 0
	for tome_id: String in stats.carried_tome_ids():
		stacks += stats.stack_count(tome_id)
	return tome_weight * float(stats.distinct_tome_count()) + tome_stack_weight * float(stacks)


func _items_score(raider: Player) -> float:
	var bag := ItemBag.find_in(raider)
	if bag == null:
		return 0.0
	var copies := 0
	for item_id: String in bag.carried_ids():
		copies += bag.count(item_id)
	return item_weight * float(copies)
