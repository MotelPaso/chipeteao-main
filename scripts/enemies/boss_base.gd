class_name BossBase
extends EnemyBase
## Chasis común de los jefes sobre EnemyBase: lo que repite cada jefe de
## bioma. Engancha la barra de vida del HUD por el grupo "boss_ui", recorta
## la posición a la arena, escala por grado con apply_tier() (el daño del
## moveset pasa por el hook _scale_attack_damage), paga gemas en anillo y
## hace el momento de muerte de jefe. Cada jefe concreto (Rotking,
## Sarcognath...) tiene su propia máquina de estados y moveset. Un jefe
## nunca se vuelve shiny (make_elite no hace nada).

@export var boss_title: String = "Jefe"
## Distancia en metros que el jefe guarda del muro, para que sus ataques de
## suelo caigan en el piso.
@export var arena_clamp_margin: float = 4.0

@export_group("Llegada compartida")
## Segundos que dura el anillo de destello de la llegada.
@export var entrance_ring_time: float = 0.45
## Segundos que tarda la silueta en crecer hasta su tamaño.
@export var entrance_pop_time: float = 0.55
## Escala con la que aparece la silueta antes de crecer (0-1).
@export var entrance_start_scale: float = 0.15

@export_group("Telegrafía")
## Color de los discos de aviso de los ataques de suelo; cada jefe fija el suyo en su escena.
@export var telegraph_color: Color = Color(1.0, 0.55, 0.12)
## Color del destello de impacto y del anillo de llegada; cada jefe fija el suyo en su escena.
@export var impact_color: Color = Color(1.0, 0.8, 0.35)
## Segundos que dura el destello de impacto en el suelo.
@export var impact_flash_time: float = 0.2
## Fuerza del temblor de cámara de _resolve_ground_hit (0-1).
@export var impact_shake_strength: float = 0.2
## Segundos del temblor de cámara de _resolve_ground_hit.
@export var impact_shake_duration: float = 0.4

@export_group("Púas de suelo")
## Escena del grupo de púas que revienta el suelo (SpikeCluster); vacío = sin púas.
@export var spike_cluster_scene: PackedScene

@export_group("Reward")
## Pago al morir: un anillo de boss_gem_count gemas de boss_gem_value XP.
@export var boss_gem_count: int = 8
## XP de cada gema del anillo de pago.
@export var boss_gem_value: int = 5
## Orbes de vida garantizados al morir (sujetos al tope global de HealthOrb).
@export var health_orb_count: int = 2

@export_group("Tier")
## Escala extra del cuerpo por cada llamada a apply_tier() (Elder y más).
@export var tier_body_scale: float = 1.15

@export_group("Chests")
## Cofres al morir: siempre esta cantidad, más uno por altar demoníaco
## usado en la partida (RunState.demonic_uses).
@export var base_chest_drops: int = 1
## Rareza mínima del anillo de cofres ("" = sin piso). Los cofres de jefe
## son gratis y tiran su rareza al abrirse, inclinada por la suerte
## demoníaca; un piso encima les quitaría la tirada.
@export var chest_min_rarity: String = ""

## Anillo donde caen los cofres de la muerte, y la suerte extra que suma
## cada altar demoníaco usado en la partida a su tirada de rareza.
const CHEST_RING_RADIUS: float = 3.5
const CHEST_LUCK_PER_DEMONIC: float = 20.0
## Anillos de pago: las gemas caen cerca y los orbes de vida más abiertos,
## para que se distingan en el suelo.
const GEM_RING_RADIUS: float = 1.2
const ORB_RING_RADIUS: float = 2.2

## Media arena menos arena_clamp_margin: la posición se recorta para que el
## jefe (y sus ataques de suelo) nunca salgan del campo. _ready la recalcula
## desde el nodo "arena_bounds" del mapa; 76 queda si el mapa no tiene uno.
var arena_half_extent: float = 76.0
## Un único slot de tween para toda señal de ataque o de llegada: una señal
## nueva siempre mata a la que reemplaza, así nunca se pelean entre ellas (ni
## con la caída al morir) por _visual.
var _cue_tween: Tween
## Nodo que publica la máscara de la arena ("arena_bounds"), si el mapa
## tiene uno: el mismo que consulta el spawner antes de ubicar un cuerpo.
var _bounds: Node3D = null
## Veces que apply_tier corrió en esta instancia. Solo diagnóstico: debe
## pasar una sola vez y se acumula si no.
var _tier_stacks: int = 0
var _entrance_played: bool = false


func _ready() -> void:
	# Marcador de mapa: el jefe es el único enemigo que muestra el mapa.
	add_to_group(&"map_markers")
	super()
	_bounds = get_tree().get_first_node_in_group("arena_bounds") as Node3D
	if _bounds != null:
		var extent: Variant = _bounds.get("arena_half_extent")
		if extent is float or extent is int:
			arena_half_extent = float(extent) - arena_clamp_margin
	_health.died.connect(_on_boss_base_died)
	get_tree().call_group("boss_ui", "track_boss", self, boss_title)


func _physics_process(delta: float) -> void:
	super(delta)
	# Límite duro de la arena (también frena cualquier empujón futuro).
	global_position.x = clampf(global_position.x, -arena_half_extent, arena_half_extent)
	global_position.z = clampf(global_position.z, -arena_half_extent, arena_half_extent)


## La tirada de shiny del spawner nunca toca a un jefe; los grados pasan
## por apply_tier().
func make_elite() -> void:
	pass


## Virtual: multiplica cada número de daño de ataque del jefe concreto; se
## llama una vez por apply_tier().
func _scale_attack_damage(_multiplier: float) -> void:
	pass


## El canal de daño de EnemyBase entra al del jefe, así un jefe que pase por
## apply_tier_scaling escala su moveset en vez de quedarse con el daño base.
func _apply_elite_damage(multiplier: float) -> void:
	_scale_attack_damage(multiplier)


## Instancia de jefe más fuerte (revancha Elder, grados de mapa): multiplica
## vida, daño y pago, y abulta un poco el cuerpo. Los tres canales van
## separados a propósito: el factor de grupo en co-op es solo un muro de
## vida (ver "damage is deliberately NOT scaled" en EnemySpawner), y
## juntarlos duplicaría cada ataque en una partida de cuatro. `-1.0` quiere
## decir "el mismo factor que la vida".
## Llamar una vez, con el jefe ya en el árbol: se acumula.
func apply_tier(hp_mult: float, damage_mult: float = -1.0, payout_mult: float = -1.0) -> void:
	var damage_factor := hp_mult if damage_mult < 0.0 else damage_mult
	var payout_factor := hp_mult if payout_mult < 0.0 else payout_mult
	_tier_stacks += 1
	_health.max_hp *= hp_mult
	_health.heal_full()
	_scale_attack_damage(damage_factor)
	boss_gem_value = ceili(float(boss_gem_value) * payout_factor)
	# Los puntos escalan con el pago, como make_elite los escala en los
	# enemigos comunes.
	points_value = maxi(roundi(float(points_value) * payout_factor), 1)
	# La misma regla que make_elite: crece el rig y una forma propia de la
	# instancia, nunca el CharacterBody3D.
	_grow_body(tier_body_scale)


func _on_boss_base_died() -> void:
	# El flujo base de muerte (crédito, gemas, caída) ya corre con esta señal;
	# el jefe solo tiene que dejar de leerse como jefe activo. Matar aquí el
	# tween de señal deja que la caída al morir sea dueña de _visual: el
	# manejador base corrió primero y su tween ya es el vivo.
	_kill_cue()
	remove_from_group("boss")
	_drop_chests()


# --- señales compartidas -------------------------------------------------------

## Reproduce una señal de una sola propiedad en el slot _cue_tween, matando
## la que estuviera corriendo. Toda animación de jefe pasa por aquí (o por
## _begin_cue si tiene varios pasos) para que nada anime _visual a espaldas
## de otro tween.
func _play_cue(node: Node, property: String, target: Variant, duration: float,
		trans: Tween.TransitionType = Tween.TRANS_QUAD,
		ease_type: Tween.EaseType = Tween.EASE_OUT) -> void:
	_begin_cue().tween_property(node, property, target, duration) \
			.set_trans(trans).set_ease(ease_type)


## Tween de señal nuevo en el slot compartido, para señales de varios pasos.
func _begin_cue() -> Tween:
	_kill_cue()
	_cue_tween = create_tween()
	return _cue_tween


func _kill_cue() -> void:
	if _cue_tween != null and _cue_tween.is_valid():
		_cue_tween.kill()


## Llama a _play_entrance() una sola vez, en el primer tick del estado de
## llegada. Va fuera de _ready para que el spawner ya haya puesto la posición
## real antes de que aparezca el anillo.
func _tick_entrance(in_entrance: bool) -> void:
	if in_entrance and not _entrance_played:
		_entrance_played = true
		_play_entrance()


## Virtual: rugido y anillo de llegada del jefe concreto.
func _play_entrance() -> void:
	pass


## Llegada de jefe compartida: un anillo de destello en el suelo mientras la
## silueta aparece de la nada. Cada jefe elige el tamaño, el color y su rugido.
func _play_boss_entrance(ring_radius: float, ring_color: Color) -> void:
	Telegraph.spawn_disc(self, global_position, ring_radius,
			entrance_ring_time, ring_color)
	_visual.scale = Vector3.ONE * entrance_start_scale
	_play_cue(_visual, "scale", Vector3.ONE, entrance_pop_time,
			Tween.TRANS_BACK, Tween.EASE_OUT)


## Quita de `remaining` (fracciones de vida de mayor a menor) las que
## `ratio` ya cruzó y devuelve cuántas fueron: un golpe grande puede cruzar
## varias a la vez.
func _consume_thresholds(remaining: Array[float], ratio: float) -> int:
	var crossed := 0
	while not remaining.is_empty() and ratio <= remaining[0]:
		remaining.remove_at(0)
		crossed += 1
	return crossed


# --- golpes de suelo -----------------------------------------------------------

## Golpe de suelo estándar: destello de impact_color en cada punto (si
## `flash`), temblor de cámara impact_shake_* y daño a todo raider dentro de
## algún disco, con el jefe como atacante para que las espinas respondan.
## Devuelve los raiders golpeados.
func _resolve_ground_hit(spots: Array[Vector3], radius: float, height_window: float,
		damage: float, flash: bool = true) -> Array[Node3D]:
	if flash:
		for spot: Vector3 in spots:
			Telegraph.spawn_disc(self, spot, radius, impact_flash_time, impact_color)
	Juice.shake(impact_shake_strength, impact_shake_duration)
	return damage_players_in_discs(spots, radius, height_window, damage, self)


# --- posiciones seguras en la arena -------------------------------------------

## Solo recorte cuadrado: alcanza para un disco de aviso, que puede pisar
## escenografía.
func _clamp_to_arena(point: Vector3) -> Vector3:
	var clamped := point
	clamped.x = clampf(clamped.x, -arena_half_extent, arena_half_extent)
	clamped.z = clampf(clamped.z, -arena_half_extent, arena_half_extent)
	return clamped


## Recorte MÁS la máscara caminable irregular de la arena, para puntos donde
## se pone un CUERPO. Teletransportarse a una celda bloqueada lo deja dentro
## de una formación de roca de la máscara, donde nadie lo alcanza; el
## spawner ya hace la misma pregunta antes de cada aparición en anillo.
## Prueba rumbos alternados alrededor del punto original y, si fallan, se
## queda en la posición actual del jefe, que es caminable por construcción.
func _safe_arena_point(point: Vector3, tries: int = 6) -> Vector3:
	var clamped := _clamp_to_arena(point)
	if _is_walkable(clamped):
		return clamped
	var to_point := clamped - global_position
	to_point.y = 0.0
	var radius := to_point.length()
	if radius > 0.01:
		var base_angle := atan2(to_point.z, to_point.x)
		for i in tries:
			# Se abre hacia afuera alternando lados, para que el reintento quede
			# lo más cerca posible del punto buscado (y del disco avisado).
			var offset := TAU * float((i / 2) + 1) / float(tries + 1)
			var angle := base_angle + (offset if i % 2 == 0 else -offset)
			var candidate := _clamp_to_arena(global_position
					+ Vector3(cos(angle), 0.0, sin(angle)) * radius)
			candidate.y = point.y
			if _is_walkable(candidate):
				return candidate
	return global_position


# --- púas de suelo compartidas ------------------------------------------------

## Instancia spike_cluster_scene en la raíz de la escena y la hace reventar en
## `center`, con las púas repartidas a `spread_radius`. El grupo se libera
## solo, así sobrevive si el jefe muere a mitad.
func _spawn_spike_cluster(center: Vector3, spread_radius: float) -> void:
	var scene_root := RunRoot.stage_parent(get_tree())
	if scene_root == null or spike_cluster_scene == null:
		return
	var cluster := spike_cluster_scene.instantiate() as SpikeCluster
	scene_root.add_child(cluster)
	cluster.erupt(center, spread_radius)


func _is_walkable(point: Vector3) -> bool:
	if _bounds == null or not _bounds.has_method("is_walkable"):
		return true
	return bool(_bounds.call("is_walkable", Vector2(point.x, point.z)))


## Cofres de recompensa del jefe: repartidos en un anillo; cada altar
## demoníaco usado en la partida suma uno. Cuelgan de la raíz de la escena
## para sobrevivir al cadáver.
func _drop_chests() -> void:
	var count := base_chest_drops + RunState.demonic_uses
	var parent := RunRoot.stage_parent(get_tree())
	if parent == null:
		parent = get_parent()
	# Las mismas guardas de EnemyBase: un jefe que muere durante el cierre no
	# tiene escena donde colgarlos, y un cast fallido no debe romper el flujo
	# de muerte (las gemas y el crédito ya salieron).
	if parent == null or count <= 0:
		return
	var dropped := 0
	for i in count:
		var angle := TAU * float(i) / float(count)
		var at := global_position \
				+ Vector3(cos(angle), 0.0, sin(angle)) * CHEST_RING_RADIUS
		# Cada cofre del anillo cae sobre el relieve bajo SU propio punto, así
		# un jefe que muere en una pendiente no entierra la mitad del pago.
		var terrain := Terrain.find(get_tree())
		if terrain != null:
			at.y = terrain.height_at(at.x, at.z)
		if spawn_chest(at, CHEST_LUCK_PER_DEMONIC * float(RunState.demonic_uses),
				chest_min_rarity) != null:
			dropped += 1
	print("Boss chests dropped: %d" % dropped)


## Momento de muerte de jefe: gran sacudida, cámara lenta breve y un
## estallido de esquirlas grande.
func _death_feedback() -> void:
	Juice.boss_died(global_position + Vector3.UP * 1.5, death_burst_color())


## Pago del jefe: un anillo de gemas de mucho valor en vez de la gema única.
func _drop_xp_gem() -> void:
	if xp_gem_scene == null:
		return
	# Los mismos factores que la gema única base, así un jefe que pase por los
	# canales normales de escalado paga lo que prometen. Ambos valen 1 en un
	# jefe común y dejan intacto el valor exportado.
	var value := maxi(roundi(float(boss_gem_value * _xp_multiplier) * _tier_xp_multiplier), 1)
	for i in boss_gem_count:
		var gem := Pools.acquire_scene(xp_gem_scene) as XpGem
		if gem == null:
			return
		gem.xp_value = value
		var gem_angle := TAU * float(i) / float(boss_gem_count)
		gem.global_position = global_position + Vector3.UP * 0.6 \
				+ Vector3(cos(gem_angle), 0.0, sin(gem_angle)) * GEM_RING_RADIUS


## Los jefes siempre pagan curación: health_orb_count orbes en un anillo más
## abierto que el de las gemas.
func _drop_health_orbs() -> void:
	for i in health_orb_count:
		var orb_angle := TAU * (float(i) + 0.5) / float(maxi(health_orb_count, 1))
		EnemyLoot.spawn_health_orb(get_tree(), global_position + Vector3.UP * 0.6
				+ Vector3(cos(orb_angle), 0.0, sin(orb_angle)) * ORB_RING_RADIUS)


## Contrato de marcador de mapa (grupo "map_markers"). Los enemigos comunes
## no están a propósito: un minimapa con cuarenta esbirros es ruido.
func map_marker_kind() -> StringName:
	return &"boss"
