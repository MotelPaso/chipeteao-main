class_name ChargeShrine
extends Interactable
## Altar de carga: se carga SOLO mientras algún raider está dentro del anillo,
## sin botón. Salir del anillo pausa la carga y volver a entrar la reanuda;
## un altar que nadie toca espera para siempre. Cerca del anillo (dos radios)
## el anillo brilla y late para invitar desde lejos.
##
## Al completar abre una elección de tres dones en el selector de cartas: la
## elige el raider que sostuvo el anillo y el don llega a toda la party
## (PlayerStats.add_altar_boon). Las Llaves maestras aceleran la carga y
## agrandan el don. Todo altar se hunde tras pagar (spent_lifetime).

## Segundos dentro del anillo para completar la carga.
@export var channel_time: float = 8.0
## Segundos que espera un altar gastado antes de hundirse.
@export var spent_lifetime: float = 8.0
## Multiplicador del tamaño del don (el altar demoníaco paga más).
@export var boon_scale: float = 1.0
## Anuncio al recibir el don; %s es la etiqueta del don.
@export var completed_text: String = "El altar zumba: %s para todos"
## Título y etiqueta de la carta de la elección que abre este altar.
@export var choice_title: String = "El altar te ofrece un don"
@export var choice_tag: String = "Bendición"
@export_group("Master Key")
## Velocidad de carga extra por cada Llave maestra (0.2 = +20 % por copia).
@export var key_speed_per_copy: float = 0.2
## Tamaño extra del don por cada Llave maestra (0.2 = +20 % por copia).
@export var key_boon_per_copy: float = 0.2

## Loop de Sfx mientras se carga (con contador vía _hold_loop: el Cráneo
## zumbante usa la misma voz a la vez).
const CHANNEL_LOOP: StringName = &"shrine_channel"

## Giro y vaivén del cristal en reposo, y su pulso más rápido al cargar.
const CRYSTAL_SPIN: float = 1.4
const CRYSTAL_BOB_HZ: float = 2.1
const CRYSTAL_BOB_HEIGHT: float = 0.12
const CRYSTAL_PULSE_HZ: float = 9.0
const CRYSTAL_PULSE_AMOUNT: float = 0.12
## Radio de respaldo si la escena no trae una zona cilíndrica (el de
## ChargeShrine.tscn).
const DEFAULT_ZONE_RADIUS: float = 9.3
## El disco de progreso construido en código ocupa esta fracción del radio
## de la zona.
const PROGRESS_DISC_SHARE: float = 0.97
## Un raider a menos de estos radios de anillo marca el altar (más brillo, late).
const APPROACH_BAND_SCALE: float = 2.0
const MARK_PULSE_HZ: float = 3.4
## Emisión del anillo y el disco en reposo, marcado y cargando.
const RING_ENERGY_IDLE: float = 1.1
const RING_ENERGY_MARKED: float = 3.0
const RING_ENERGY_CHANNEL: float = 3.6
const RING_ALPHA_IDLE: float = 0.55
const RING_ALPHA_MARKED: float = 0.85
const PROGRESS_DISC_ALPHA: float = 0.26
## Dones ofrecidos al completar.
const ALTAR_CHOICE_COUNT: int = 3
## Aviso tras una carga interrumpida. El altar no tiene botón, así que la
## línea manda de vuelta al anillo.
const RESUME_TEXT: String = "Vuelve a entrar para reanudar (%d%%)"

## Dones planos que puede dar un altar: {stat, amount, name, label}. `stat`
## es un id de PlayerStats; `name` titula la carta (caja baja tipo oración)
## y `label` lleva exactamente un "%d" con la cantidad ya escalada.
const ALTAR_BOONS: Array[Dictionary] = [
	{"stat": "damage", "amount": 10.0, "name": "Furia", "label": "daño +%d%%"},
	{"stat": "cooldown", "amount": 6.0, "name": "Ritmo",
		"label": "velocidad de ataque +%d%%"},
	{"stat": "area", "amount": 10.0, "name": "Amplitud", "label": "área +%d%%"},
	{"stat": "move_speed", "amount": 6.0, "name": "Ligereza", "label": "velocidad +%d%%"},
	{"stat": "max_hp", "amount": 20.0, "name": "Vigor", "label": "HP máx. +%d"},
	{"stat": "armor", "amount": 2.0, "name": "Coraza", "label": "armadura +%d"},
	{"stat": "luck", "amount": 10.0, "name": "Fortuna", "label": "suerte +%d"},
	{"stat": "crit_chance", "amount": 5.0, "name": "Precisión",
		"label": "prob. de crítico +%d%%"},
	{"stat": "xp_gain", "amount": 8.0, "name": "Sabiduría",
		"label": "ganancia de XP +%d%%"},
	# El altar demoníaco escala este por encima de 1: la etiqueta vale para
	# ambos números.
	{"stat": "projectiles", "amount": 1.0, "name": "Multitud",
		"label": "+%d proyectil(es)"},
	# PlayerStats limita los saltos (MAX_EXTRA_JUMPS).
	{"stat": "jumps", "amount": 1.0, "name": "Impulso", "label": "+%d salto(s)"},
	{"stat": "powerup_chance", "amount": 10.0, "name": "Fortuna menor",
		"label": "prob. de power-up +%d%%"},
]

var channeling: bool = false
var progress: float = 0.0
var _time: float = 0.0
var _leaving: bool = false
var _crystal: MeshInstance3D = null
var _progress_disc: MeshInstance3D = null
var _ring: MeshInstance3D = null
var _crystal_rest_y: float = 0.0
## Radio de la zona de este altar; de él salen la banda de acercamiento y el
## disco construido en código.
var _zone_radius: float = DEFAULT_ZONE_RADIUS
## Materiales propios del anillo y el disco (ver _own_material).
var _ring_material: StandardMaterial3D = null
var _disc_material: StandardMaterial3D = null
## Última energía/alfa escritas por _tick_marking (NAN = nunca). Un altar
## quieto repite los mismos valores por minutos y cada escritura vuelve a
## subir el material; saltar la escritura repetida dibuja lo mismo.
var _marked_energy: float = NAN
var _marked_alpha: float = NAN


func _init() -> void:
	meta_stat_id = "shrines_used"
	marker_kind = &"altar"
	# Sin botón: la carga es por cercanía, así que el aviso no ofrece uno.
	prompt_text = "Quédate dentro para cargar"


func _ready() -> void:
	super()
	# El WorldDirector limita los altares SIN GASTAR a la vez y encuentra los
	# de la arena por este grupo.
	add_to_group("altars")
	_zone_radius = _measure_zone_radius()
	_crystal = get_node_or_null("Visual/Crystal") as MeshInstance3D
	if _crystal != null:
		_crystal_rest_y = _crystal.position.y
	_ring = get_node_or_null("Visual/Ring") as MeshInstance3D
	_ring_material = _own_material(_ring, RING_ALPHA_IDLE, RING_ENERGY_IDLE)
	_progress_disc = get_node_or_null("Visual/ProgressDisc") as MeshInstance3D
	if _progress_disc == null:
		_progress_disc = _build_progress_disc()
	_disc_material = _own_material(_progress_disc, PROGRESS_DISC_ALPHA, RING_ENERGY_IDLE)


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


## Material propio para el anillo o el disco. Laten en cada frame, y un
## [sub_resource] de la escena es UN objeto compartido por todas las
## instancias: escribir en él haría latir todos los altares a la vez.
func _own_material(target: MeshInstance3D, alpha: float,
		energy: float) -> StandardMaterial3D:
	if target == null:
		return null
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(_accent_color(), alpha)
	material.emission_enabled = true
	material.emission = _accent_color()
	material.emission_energy_multiplier = energy
	target.material_override = material
	return material


## Disco plano que crece con la carga, para escenas que no traen uno (el
## obelisco demoníaco).
func _build_progress_disc() -> MeshInstance3D:
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	var radius := _zone_radius * PROGRESS_DISC_SHARE
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.04
	# 64 lados como el ProgressDisc de la escena: un disco de 9 m tiene que
	# verse redondo junto a su anillo.
	mesh.radial_segments = 64
	mesh.rings = 1
	disc.mesh = mesh
	disc.position.y = 0.06
	disc.scale = Vector3(0.001, 1.0, 0.001)
	disc.visible = false
	add_child(disc)
	return disc


## Color del anillo, el disco y las cartas; el altar demoníaco lo cambia a rojo.
func _accent_color() -> Color:
	return Color(0.4, 0.8, 1.0)


func _physics_process(delta: float) -> void:
	if _leaving:
		return
	_time += delta
	if _crystal != null:
		_crystal.rotate_y(delta * CRYSTAL_SPIN)
		_crystal.position.y = _crystal_rest_y + sin(_time * CRYSTAL_BOB_HZ) * CRYSTAL_BOB_HEIGHT
		var pulse := CRYSTAL_PULSE_AMOUNT * sin(_time * CRYSTAL_PULSE_HZ) if channeling else 0.0
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
	progress += delta * _charge_speed()
	_progress_disc.visible = true
	var fraction := clampf(progress / channel_time, 0.001, 1.0)
	_progress_disc.scale = Vector3(fraction, 1.0, fraction)
	set_prompt("Cargando... %d%%" % roundi(fraction * 100.0))
	if progress >= channel_time:
		_complete()


## El anillo se lee a tres distancias: tenue en reposo, brillante y latiendo
## con un raider dentro de la banda de acercamiento, y al máximo cargando.
func _tick_marking() -> void:
	if _ring_material == null and _disc_material == null:
		return
	var energy := RING_ENERGY_IDLE
	var alpha := RING_ALPHA_IDLE
	if channeling:
		energy = RING_ENERGY_CHANNEL
		alpha = RING_ALPHA_MARKED
	elif available and _player_near():
		var beat := 0.5 + 0.5 * sin(_time * MARK_PULSE_HZ)
		energy = lerpf(RING_ENERGY_IDLE, RING_ENERGY_MARKED, beat)
		alpha = lerpf(RING_ALPHA_IDLE, RING_ALPHA_MARKED, beat)
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
	var band := _zone_radius * APPROACH_BAND_SCALE
	var band_sq := band * band
	# "Alguien dentro de la banda" equivale a "el más cercano está dentro".
	var nearest := Coop.nearest_player(get_tree(), global_position)
	return nearest != null \
			and global_position.distance_squared_to(nearest.global_position) <= band_sq


## Llaves maestras de los raiders en pie del anillo: cuenta la mayor.
func _keys_in_ring() -> int:
	return best_item_count_in_range("master_key")


func _charge_speed() -> float:
	return 1.0 + key_speed_per_copy * float(_keys_in_ring())


## Sin botón: entrar empieza (o reanuda) la carga.
func _on_range_entered() -> void:
	if not available or channeling or _leaving:
		return
	channeling = true
	# Con contador: otro altar o el Cráneo zumbante pueden sostener la misma
	# voz a la vez.
	_hold_loop(CHANNEL_LOOP)
	_emit_started()


## Salir a mitad de carga solo la PAUSA: el progreso se guarda y volver a
## entrar la reanuda.
func _on_range_exited() -> void:
	if not channeling:
		return
	channeling = false
	_drop_loop()
	_emit_cancelled()
	set_prompt(RESUME_TEXT % roundi(clampf(progress / channel_time, 0.0, 1.0) * 100.0))


func _interact(_player: Node) -> void:
	pass  # la cercanía hace todo; el botón no hace nada


func _complete() -> void:
	channeling = false
	_drop_loop()
	progress = channel_time
	var keys := _keys_in_ring()
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
	var options := _reward_options(keys)
	if options.is_empty():
		return
	get_tree().call_group("upgrade_ui", "open_choice", choice_title, options,
			recipient, _on_choice_picked.bind(keys, recipient), choice_tag)


## Virtual: las opciones de este altar. El de carga saca ALTAR_CHOICE_COUNT
## dones DISTINTOS; el demoníaco ofrece pactos.
func _reward_options(keys: int) -> Array[Dictionary]:
	var pool := ALTAR_BOONS.duplicate()
	pool.shuffle()
	var options: Array[Dictionary] = []
	for i in mini(ALTAR_CHOICE_COUNT, pool.size()):
		var boon: Dictionary = pool[i]
		var amount := boon_amount(float(boon.amount), keys)
		var label := String(boon.label) % roundi(amount)
		options.append({
			"title": String(boon.name),
			"description": label + " para toda la party",
			"color": _accent_color(),
			"label": label,
			"stat": String(boon.stat),
			"amount": amount,
		})
	return options


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
	return String(option.label)


## Tamaño de un don: la cantidad base, la escala de este altar y las Llaves
## maestras de quien carga. Nunca menos de 1.
func boon_amount(base: float, keys: int) -> float:
	var amount := base * _effective_boon_scale() * (1.0 + key_boon_per_copy * float(keys))
	return maxf(roundf(amount), 1.0)


## Escala del don al entregarlo. Virtual para que el altar demoníaco sume la
## Sangre de demonio sin escribir en el export.
func _effective_boon_scale() -> float:
	return boon_scale


## Don plano para toda la party. Los caídos también cuentan (dejan el grupo
## "player" al caer, pero el don es para toda la partida).
func grant_boon(stat: String, amount: float) -> void:
	for group: String in ["player", "downed_players"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			var stats := PlayerStats.find_in(node)
			if stats != null:
				stats.add_altar_boon(stat, amount)


## Se hunde, se encoge y se libera (sink_away). Solo lo toma un altar gastado.
func _leave(reason: String) -> void:
	if _leaving:
		return
	_leaving = true
	available = false
	_refresh_prompt()
	sink_away()
	print("Altar left: %s %s" % [name, reason])
