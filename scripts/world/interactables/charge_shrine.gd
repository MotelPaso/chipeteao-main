class_name ChargeShrine
extends Interactable
## Altar de carga: se carga SOLO mientras algún raider está dentro del anillo,
## sin botón. Salir del anillo pausa la carga y volver a entrar la reanuda;
## un altar que nadie toca espera para siempre. Con un raider cerca
## (approach_band_scale radios) el anillo brilla y late para invitar desde lejos.
##
## Al completar abre una elección de tres dones en el selector de cartas: tres
## stats DISTINTAS de ALTAR_BOONS (cualquiera del jugador); la cantidad de
## cada una es un valor al azar de la lista `values` del tomo de esa stat
## (Tome.TOME_LIBRARY). La elige
## el raider que sostuvo el anillo y el don llega a toda la party
## (PlayerStats.add_altar_boon). Cada Llave maestra de la party agranda el
## don un boon_percent (20%). Todo altar se hunde tras pagar (spent_lifetime).

## Dones ofrecidos al completar (la UI de cartas tiene tres huecos).
const ALTAR_CHOICE_COUNT: int = 3
## Radio de respaldo si la escena no trae una zona cilíndrica, en metros.
const DEFAULT_ZONE_RADIUS: float = 9.3
## Kind del objeto que agranda los dones del altar de carga (Llave maestra);
## su fila de ItemCatalog lleva el porcentaje por copia (boon_percent).
const MASTER_KEY_KIND: String = "charge_boost"

## Dones que puede dar un altar, edita aquí: una fila por stat del jugador
## (id de PlayerStats). `label` es el título de la carta, sin nombre propio:
## la stat y exactamente un "%d" con la cantidad. La cantidad es un valor al azar de la lista
## `values` del tomo que sube esa stat; las stats sin tomo llevan aquí su
## propia lista `values` de cantidades posibles.
const ALTAR_BOONS: Array[Dictionary] = [
	{"stat": "damage", "label": "Daño +%d%%"},
	{"stat": "cooldown", "label": "Velocidad de ataque +%d%%"},
	{"stat": "area", "label": "Área +%d%%"},
	{"stat": "projectiles", "label": "Proyectiles +%d"},
	{"stat": "crit_chance", "label": "Prob. de crítico +%d%%"},
	{"stat": "crit_damage", "label": "Daño crítico +%d%%",
		"values": [15, 20, 25, 30]},
	{"stat": "lifesteal", "label": "Robo de vida +%d%%"},
	{"stat": "duration", "label": "Duración de efectos +%d%%"},
	{"stat": "max_hp", "label": "HP máx. +%d"},
	{"stat": "armor", "label": "Armadura +%d%%"},
	{"stat": "evasion", "label": "Evasión +%d%%"},
	{"stat": "thorns", "label": "Espinas +%d",
		"values": [3, 5, 7, 10]},
	{"stat": "move_speed", "label": "Velocidad +%d%%"},
	# PlayerStats limita los saltos (MAX_EXTRA_JUMPS).
	{"stat": "jumps", "label": "Saltos +%d",
		"values": [1, 1, 2, 2]},
	{"stat": "luck", "label": "Suerte +%d"},
	{"stat": "xp_gain", "label": "Ganancia de XP +%d%%"},
	{"stat": "pickup_radius", "label": "Radio de recogida +%d%%",
		"values": [20, 25, 30, 40]},
	{"stat": "powerup_chance", "label": "Prob. de power-up +%d%%",
		"values": [10, 15, 20, 30]},
]

@export_group("Carga")
## Segundos dentro del anillo para completar la carga.
@export var channel_time: float = 8.0
## Segundos que espera un altar gastado antes de hundirse.
@export var spent_lifetime: float = 8.0
## Loop de Sfx mientras se carga; va con contador (_hold_loop) porque el Cráneo zumbante usa la misma voz.
@export var channel_loop: StringName = &"shrine_channel"
## Multiplicador del tamaño del don (el altar demoníaco paga más).
@export var boon_scale: float = 1.0
## Dificultad, en %, que suma SIEMPRE cada uso del altar. El de carga usa este valor; el demoníaco pone el suyo en CurseShrine.tscn.
@export var difficulty_per_use: float = 5.0
@export_group("Textos")
## Aviso mientras carga; %d%% es el porcentaje.
@export var charging_prompt: String = "Cargando... %d%%"
## Aviso tras salir a mitad de carga; %d%% es el porcentaje guardado (no hay botón: manda de vuelta al anillo).
@export var resume_prompt: String = "Vuelve a entrar para reanudar (%d%%)"
## Título de la elección que abre el altar en el selector de cartas.
@export var choice_title: String = "El altar te ofrece un don"
## Etiqueta (cinta) de las cartas de la elección.
@export var choice_tag: String = "Bendición"
## Anuncio al recibir el don; %s es la etiqueta del don.
@export var completed_text: String = "El altar zumba: %s"
@export_group("Anillo")
## Color del anillo, del disco de progreso y de las cartas; tiñe los materiales de Ring y ProgressDisc (el resto del material sale de la escena).
@export var accent_color: Color = Color(0.4, 0.8, 1.0)
## Un raider en pie a menos de estos radios de zona marca el altar (brilla y late).
@export var approach_band_scale: float = 2.0
## Velocidad del latido del anillo marcado, en radianes por segundo.
@export var mark_pulse_speed: float = 3.4
## Energía de emisión del anillo y del disco en reposo.
@export var ring_energy_idle: float = 1.1
## Energía máxima del latido con un raider cerca.
@export var ring_energy_marked: float = 3.0
## Energía mientras carga.
@export var ring_energy_channel: float = 3.6
## Opacidad del anillo en reposo (0-1).
@export_range(0.0, 1.0) var ring_alpha_idle: float = 0.55
## Opacidad máxima del anillo marcado o cargando (0-1).
@export_range(0.0, 1.0) var ring_alpha_marked: float = 0.85
## Opacidad del disco de progreso (0-1).
@export_range(0.0, 1.0) var disc_alpha: float = 0.26
@export_group("Cristal")
## Giro del cristal, en radianes por segundo.
@export var crystal_spin_speed: float = 1.4
## Velocidad del vaivén del cristal, en radianes por segundo.
@export var crystal_bob_speed: float = 2.1
## Altura del vaivén del cristal, en metros.
@export var crystal_bob_height: float = 0.12
## Velocidad del pulso del cristal mientras carga, en radianes por segundo.
@export var crystal_pulse_speed: float = 9.0
## Cuánto crece el cristal en el pulso, como fracción de su tamaño.
@export var crystal_pulse_amount: float = 0.12

var channeling: bool = false
var progress: float = 0.0
var _time: float = 0.0
var _leaving: bool = false
## Suerte de quien recibe la elección en curso: inclina la rareza de las
## cantidades (_reward_options la lee).
var _offer_luck: float = 0.0
var _crystal_rest_y: float = 0.0
## Radio de la zona de este altar; de él sale la banda de acercamiento.
var _zone_radius: float = DEFAULT_ZONE_RADIUS
## Materiales propios del anillo y el disco (ver _own_material).
var _ring_material: StandardMaterial3D = null
var _disc_material: StandardMaterial3D = null
## Última energía/alfa escritas por _tick_marking (NAN = nunca). Un altar
## quieto repite los mismos valores por minutos y cada escritura vuelve a
## subir el material; saltar la escritura repetida dibuja lo mismo.
var _marked_energy: float = NAN
var _marked_alpha: float = NAN

## El altar demoníaco no tiene cristal ni anillo; el disco está en las dos escenas.
@onready var _crystal: MeshInstance3D = get_node_or_null("Visual/Crystal") as MeshInstance3D
@onready var _ring: MeshInstance3D = get_node_or_null("Visual/Ring") as MeshInstance3D
@onready var _progress_disc: MeshInstance3D = $Visual/ProgressDisc


## Grupo de este tipo de altar (el demoníaco lo cambia).
func type_group() -> StringName:
	return &"charge_altars"


func _ready() -> void:
	super()
	# El WorldDirector limita los altares SIN GASTAR a la vez y encuentra los
	# de la arena por este grupo.
	add_to_group("altars")
	# Grupo por tipo: el director lo usa para el tope de altares de cada tipo.
	add_to_group(type_group())
	_zone_radius = _measure_zone_radius()
	if _crystal != null:
		_crystal_rest_y = _crystal.position.y
	_ring_material = _own_material(_ring, ring_alpha_idle, ring_energy_idle)
	_disc_material = _own_material(_progress_disc, disc_alpha, ring_energy_idle)


func _physics_process(delta: float) -> void:
	if _leaving:
		return
	_time += delta
	if _crystal != null:
		_crystal.rotate_y(delta * crystal_spin_speed)
		_crystal.position.y = _crystal_rest_y + sin(_time * crystal_bob_speed) * crystal_bob_height
		var pulse := crystal_pulse_amount * sin(_time * crystal_pulse_speed) if channeling else 0.0
		_crystal.scale = Vector3.ONE * (1.0 + pulse)
	_tick_marking()
	if not channeling:
		# Una carga pausada se reanuda por cercanía, y body_entered NO vuelve
		# a dispararse para un raider reanimado en el sitio (su cuerpo nunca
		# salió del área). Por eso se sondea el anillo aquí. player_in_range
		# va primero: si es false, la lista de vivos está vacía seguro y se
		# evita armarla en cada frame.
		if available and player_in_range and not live_players_in_range().is_empty():
			_on_range_entered()
		return
	# Un raider caído nunca sale del Area3D: sin esta comprobación un cuerpo
	# sostendría el ritual.
	if live_players_in_range().is_empty():
		_on_range_exited()
		return
	progress += delta
	_progress_disc.visible = true
	var fraction := clampf(progress / channel_time, 0.001, 1.0)
	_progress_disc.scale = Vector3(fraction, 1.0, fraction)
	set_prompt(charging_prompt % roundi(fraction * 100.0))
	if progress >= channel_time:
		_complete()


## Tamaño de un don: la cantidad base, la escala de este altar y las Llaves
## maestras de quien carga. Nunca menos de 1.
func boon_amount(base: float, keys: int) -> float:
	var per_key := _master_key_fraction("boon_percent")
	var amount := base * _effective_boon_scale() * (1.0 + per_key * float(keys))
	return maxf(roundf(amount), 1.0)


## Don plano para toda la party. Los caídos también cuentan (dejan el grupo
## "player" al caer, pero el don es para toda la partida).
func grant_boon(stat: String, amount: float) -> void:
	for group: String in ["player", "downed_players"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var stats := PlayerStats.find_in(node)
			if stats != null:
				stats.add_altar_boon(stat, amount)


func _interact(_player: Node) -> void:
	pass  # la cercanía hace todo; el botón no hace nada


## Sin botón: entrar empieza (o reanuda) la carga.
func _on_range_entered() -> void:
	if not available or channeling or _leaving:
		return
	channeling = true
	# Con contador: otro altar o el Cráneo zumbante pueden sostener la misma
	# voz a la vez.
	_hold_loop(channel_loop)
	_emit_started()


## Salir a mitad de carga solo la PAUSA: el progreso se guarda y volver a
## entrar la reanuda.
func _on_range_exited() -> void:
	if not channeling:
		return
	channeling = false
	_drop_loop()
	_emit_cancelled()
	set_prompt(resume_prompt % roundi(clampf(progress / channel_time, 0.0, 1.0) * 100.0))


## Radio de la zona de carga, leído de la forma de la escena para que la
## banda de acercamiento coincida con el área real.
func _measure_zone_radius() -> float:
	for child: Node in get_children():
		var shape_node := child as CollisionShape3D
		if shape_node == null:
			continue
		var cylinder := shape_node.shape as CylinderShape3D
		if cylinder != null:
			return cylinder.radius
	return DEFAULT_ZONE_RADIUS


## Copia propia del material de la escena de `target`, teñida con
## accent_color (el resto del material sale de la escena). Cada altar
## necesita la suya: el anillo y el disco laten por instancia, y un
## [sub_resource] de la escena lo comparten todas las instancias.
func _own_material(target: MeshInstance3D, alpha: float,
		energy: float) -> StandardMaterial3D:
	if target == null:
		return null
	var source := target.get_active_material(0) as StandardMaterial3D
	if source == null:
		push_warning("ChargeShrine: %s has no StandardMaterial3D to tint" % target.name)
		return null
	var material := source.duplicate() as StandardMaterial3D
	material.albedo_color = Color(accent_color, alpha)
	material.emission = accent_color
	material.emission_energy_multiplier = energy
	target.material_override = material
	return material


## El anillo se lee a tres distancias: tenue en reposo, brillante y latiendo
## con un raider dentro de la banda de acercamiento, y al máximo cargando.
func _tick_marking() -> void:
	if _ring_material == null and _disc_material == null:
		return
	var energy := ring_energy_idle
	var alpha := ring_alpha_idle
	if channeling:
		energy = ring_energy_channel
		alpha = ring_alpha_marked
	elif available and _player_near():
		var beat := 0.5 + 0.5 * sin(_time * mark_pulse_speed)
		energy = lerpf(ring_energy_idle, ring_energy_marked, beat)
		alpha = lerpf(ring_alpha_idle, ring_alpha_marked, beat)
	if energy == _marked_energy and alpha == _marked_alpha:
		return
	_marked_energy = energy
	_marked_alpha = alpha
	if _ring_material != null:
		_ring_material.emission_energy_multiplier = energy
		_ring_material.albedo_color.a = alpha
	if _disc_material != null:
		_disc_material.emission_energy_multiplier = energy


## Algún raider en pie dentro de la banda de acercamiento (un cuerpo caído
## en la banda no es alguien que se acerca).
func _player_near() -> bool:
	var band := _zone_radius * approach_band_scale
	var band_sq := band * band
	# "Alguien dentro de la banda" equivale a "el más cercano está dentro".
	var nearest := Coop.nearest_player(get_tree(), global_position)
	return nearest != null \
			and global_position.distance_squared_to(nearest.global_position) <= band_sq


## Llaves maestras de la party: cuenta la de quien lleva más, esté donde
## esté (el don le llega a toda la party). El altar demoníaco no las usa.
func _party_keys() -> int:
	if not _uses_master_key():
		return 0
	var best := 0
	for node: Node in get_tree().get_nodes_in_group("player"):
		var bag := ItemBag.find_in(node)
		if bag != null:
			best = maxi(best, bag.count_kind(MASTER_KEY_KIND))
	return best


## Virtual: si las Llaves maestras agrandan los dones de este altar (solo el
## de carga).
func _uses_master_key() -> bool:
	return true


## Un porcentaje por copia de la fila de la Llave maestra, como fracción
## (20 -> 0.2).
func _master_key_fraction(field: String) -> float:
	return float(ItemCatalog.kind_row(MASTER_KEY_KIND).get(field, 0.0)) / 100.0


func _complete() -> void:
	channeling = false
	_drop_loop()
	progress = channel_time
	var keys := _party_keys()
	# Se resuelve ANTES de consume(): el premio es de quien sostuvo el anillo,
	# y en co-op el selector de cartas tiene que saberlo.
	var recipient := nearest_live_player()
	consume()
	set_physics_process(false)
	if _crystal != null:
		_crystal.scale = Vector3.ONE
	_progress_disc.visible = false
	dim_visuals()
	_offer_reward(keys, recipient)
	_emit_completed()
	if spent_lifetime > 0.0:
		# Sin process_always: la elección pausa el árbol, y un temporizador
		# que ignorara la pausa hundiría el altar con su menú abierto.
		get_tree().create_timer(spent_lifetime, false).timeout.connect(
				_leave.bind("se apaga: ya rindió su premio"))


## Abre la elección en el selector de cartas (grupo "upgrade_ui"), dueño de la
## pausa, la cola y el título co-op. No es un menú propio: una segunda UI
## bloqueante es otra forma de trabar la partida, y el harness solo sabe
## responder esta.
func _offer_reward(keys: int, recipient: Node) -> void:
	var stats := PlayerStats.find_in(recipient) if recipient != null else null
	_offer_luck = stats.luck if stats != null else 0.0
	var options := _reward_options(keys)
	if options.is_empty():
		return
	get_tree().call_group("upgrade_ui", "open_choice", choice_title, options,
			recipient, _on_choice_picked.bind(keys, recipient), choice_tag)


## Virtual: las opciones de este altar. El de carga saca ALTAR_CHOICE_COUNT
## stats DISTINTAS, cada una con una cantidad al azar; el demoníaco ofrece
## pactos.
func _reward_options(keys: int) -> Array[Dictionary]:
	var pool := ALTAR_BOONS.duplicate()
	pool.shuffle()
	var options: Array[Dictionary] = []
	for i in mini(ALTAR_CHOICE_COUNT, pool.size()):
		var boon: Dictionary = pool[i]
		# La rareza se sortea con la curva de suerte de todo el juego (la suerte
		# de quien recibe); la cantidad es el valor de esa rareza en la lista
		# `values` (una por rareza, en el orden de Rarity.TIERS).
		var values := boon_values(boon)
		var rarity := Rarity.roll(_offer_luck)
		var index := mini(Rarity.index_of(String(rarity.name)), values.size() - 1)
		var amount := boon_amount(float(values[index]), keys)
		var label := String(boon.label) % roundi(amount)
		options.append({
			# Solo la stat y su cantidad: ni nombre propio, ni la party, ni la
			# dificultad que suma el altar (se aplican igual).
			"title": label,
			"description": "",
			"color": rarity.color as Color,
			"ribbon": Rarity.display_name(String(rarity.name)),
			"label": label,
			"stat": String(boon.stat),
			"amount": amount,
		})
	return options


## Cantidades posibles de un don: la lista `values` de la fila si la tiene;
## si no, la del tomo que sube esa stat. Sin ninguna, [1]. También la usan el
## altar demoníaco y el Tomo del Azar.
static func boon_values(boon: Dictionary) -> Array:
	var values: Array = boon.get("values", [])
	if not values.is_empty():
		return values
	var stat := String(boon.stat)
	for tome: Dictionary in Tome.TOME_LIBRARY:
		for effect: Dictionary in tome.get("effects", []) as Array:
			if String(effect.get("stat", "")) == stat and effect.has("values"):
				return effect.values
	return [1]


## El selector de cartas devuelve aquí la opción elegida.
func _on_choice_picked(option: Dictionary, keys: int, recipient: Node) -> void:
	if not is_inside_tree():
		return
	var label := _grant_choice(option, keys, recipient)
	if label.is_empty():
		return
	get_tree().call_group("hud", "announce", completed_text % label)
	# Línea de log para los soaks (verificar.sh cuenta "Altar charged:").
	print("Altar charged: %s -> %s" % [name, label])


## Virtual: aplica la opción elegida y devuelve el texto a anunciar. El
## altar demoníaco paga el beneficio Y el costo del pacto.
func _grant_choice(option: Dictionary, _keys: int, _recipient: Node) -> String:
	grant_boon(String(option.stat), float(option.amount))
	RunState.add_difficulty(difficulty_per_use / 100.0, "altars")
	return String(option.label)


## Escala del don al entregarlo. Virtual para que el altar demoníaco sume la
## Sangre de demonio sin escribir en el export.
func _effective_boon_scale() -> float:
	return boon_scale


## Se hunde, se encoge y se libera (sink_away). Solo lo toma un altar gastado.
func _leave(reason: String) -> void:
	if _leaving:
		return
	_leaving = true
	available = false
	_refresh_prompt()
	sink_away()
	print("Altar left: %s %s" % [name, reason])
