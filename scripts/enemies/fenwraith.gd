class_name Fenwraith
extends BossBase
## Espectro de la Ciénaga, jefe de la Ciénaga Lóbrega: un espíritu ahogado
## del pantano que pelea a distancia y no se deja acorralar. Máquina de
## estados sobre los hooks de EnemyBase, al estilo del Rotking. Moveset:
##   - Nova de miasma: estallido venenoso marcado alrededor suyo cuando lo
##     rodean (salta o sal del anillo durante la carga).
##   - Andanada del pantano: un abanico de saetas lentas a media distancia
##     (EnemyBolt del pool, la saeta del hostigador, más densa).
##   - Hundirse y emerger: marca un punto cerca del raider, se hunde en el
##     pantano y sale ahí; acorta distancia y mantiene la pelea en movimiento.
## Título, grados, pago y recorte de arena viven en BossBase; el spawner
## sube la revancha Elder con apply_tier(). Colores de aviso e impacto:
## grupo Telegrafía de Fenwraith.tscn.

enum State { ENTRANCE, PURSUE, NOVA, VOLLEY, BLINK }

## Segundos del estado de llegada antes de empezar a pelear.
@export var entrance_duration: float = 0.9

@export_group("Miasma Nova")
@export var nova_trigger_range: float = 5.0
@export var nova_radius: float = 5.5
@export var nova_damage: float = 22.0
@export var nova_windup: float = 0.9
@export var nova_recover: float = 0.7
@export var nova_cooldown: float = 5.0
## Un raider más alto que esto sobre los pies del jefe no la recibe.
@export var nova_height_window: float = 1.5

@export_group("Bog Volley")
@export var volley_interval: float = 5.5
@export var volley_windup: float = 0.5
@export var volley_min_range: float = 6.0
@export var volley_max_range: float = 22.0
@export var volley_bolt_count: int = 5
@export var volley_spread_degrees: float = 40.0
@export var bolt_damage: float = 9.0
@export var bolt_scene: PackedScene
@export var muzzle_height: float = 1.6
@export var target_height: float = 0.9

@export_group("Sink & Rise")
@export var blink_interval: float = 9.0
@export var blink_trigger_range: float = 12.0
@export var blink_windup: float = 0.7
## El punto de salida queda a esta distancia del raider perseguido.
@export var blink_arrival_distance: float = 5.0
## Fracción de blink_interval que espera el primer hundimiento al aparecer (0-1).
@export var first_blink_fraction: float = 0.6
## Radio en metros del disco que marca la salida (y el destello al llegar).
@export var blink_disc_radius: float = 2.2
## Segundos que tarda el sudario en desplegarse al salir.
@export var blink_rise_time: float = 0.3
## Fuerza del temblor de cámara al salir (0-1).
@export var blink_shake_strength: float = 0.15
## Segundos del temblor de cámara al salir.
@export var blink_shake_duration: float = 0.3

var _state: State = State.ENTRANCE
var _state_timer: float = 0.0
var _nova_cooldown_timer: float = 0.0
var _nova_resolved: bool = false
var _volley_timer: float = 0.0
var _blink_timer: float = 0.0
var _blink_target: Vector3 = Vector3.ZERO


func _ready() -> void:
	super()
	_state_timer = entrance_duration
	_volley_timer = volley_interval
	_blink_timer = blink_interval * first_blink_fraction


func _scale_attack_damage(multiplier: float) -> void:
	nova_damage *= multiplier
	bolt_damage *= multiplier


func _behavior_tick(delta: float) -> void:
	_nova_cooldown_timer = maxf(_nova_cooldown_timer - delta, 0.0)
	if _state == State.PURSUE:
		_volley_timer = maxf(_volley_timer - delta, 0.0)
		_blink_timer = maxf(_blink_timer - delta, 0.0)
		return
	_tick_entrance(_state == State.ENTRANCE)
	_state_timer -= delta
	if _state_timer > 0.0:
		return
	match _state:
		State.ENTRANCE:
			_state = State.PURSUE
		State.NOVA:
			if _nova_resolved:
				_state = State.PURSUE
			else:
				_resolve_nova()
		State.VOLLEY:
			_resolve_volley()
		State.BLINK:
			_resolve_blink()


func _movement_intent(seek: Vector3, _distance: float) -> Vector3:
	return seek if _state == State.PURSUE else Vector3.ZERO


func _facing_direction(steer: Vector3, seek: Vector3) -> Vector3:
	if _state == State.ENTRANCE:
		return Vector3.ZERO
	return seek if seek.length_squared() > 0.0001 else steer


func _combat_tick(player: Node3D, distance: float) -> void:
	if _state != State.PURSUE:
		return
	if _nova_cooldown_timer <= 0.0 and distance <= nova_trigger_range:
		_start_nova()
		return
	if _blink_timer <= 0.0 and distance >= blink_trigger_range:
		_start_blink(player)
		return
	if _volley_timer <= 0.0 \
			and distance >= volley_min_range and distance <= volley_max_range:
		_start_volley()


func _play_entrance() -> void:
	Sfx.play(&"boss_roar_2")
	_play_boss_entrance(nova_radius * 0.6, impact_color)


## --- Nova de miasma -----------------------------------------------------------

func _start_nova() -> void:
	_state = State.NOVA
	_state_timer = nova_windup
	_nova_resolved = false
	Telegraph.spawn_disc(self, global_position, nova_radius, nova_windup, telegraph_color)


func _resolve_nova() -> void:
	_nova_resolved = true
	_state_timer = nova_recover
	_nova_cooldown_timer = nova_cooldown
	# Todo raider dentro del anillo la recibe.
	_resolve_ground_hit([global_position], nova_radius, nova_height_window,
			nova_damage)


## --- Andanada del pantano -----------------------------------------------------

func _start_volley() -> void:
	_state = State.VOLLEY
	_state_timer = volley_windup
	_volley_timer = volley_interval


func _resolve_volley() -> void:
	_state = State.PURSUE
	if bolt_scene == null:
		return
	var player := Coop.nearest_player(get_tree(), global_position)
	if player == null:
		return
	var origin := global_position + Vector3.UP * muzzle_height
	var aim_point := player.global_position + Vector3.UP * target_height
	var base_aim := aim_point - origin
	base_aim.y = 0.0
	if base_aim.length_squared() < 0.01:
		return
	var base_angle := atan2(base_aim.z, base_aim.x)
	var spread := deg_to_rad(volley_spread_degrees)
	var count := maxi(volley_bolt_count, 1)
	for i in count:
		var bolt := Pools.acquire_scene(bolt_scene) as EnemyBolt
		if bolt == null:
			return
		bolt.damage = bolt_damage
		bolt.global_position = origin
		bolt.launcher = self
		var t := 0.5 if count == 1 else float(i) / float(count - 1)
		var bolt_angle := base_angle + lerpf(-spread * 0.5, spread * 0.5, t)
		var flat_target := origin + Vector3(cos(bolt_angle), 0.0, sin(bolt_angle)) * 10.0
		flat_target.y = aim_point.y
		var aim := (flat_target - origin).normalized()
		bolt.look_at(bolt.global_position + aim, WeaponBase.safe_up(aim))


## --- Hundirse y emerger -------------------------------------------------------

func _start_blink(player: Node3D) -> void:
	_state = State.BLINK
	_state_timer = blink_windup
	_blink_timer = blink_interval
	var angle := randf() * TAU
	var wanted := player.global_position \
			+ Vector3(cos(angle), 0.0, sin(angle)) * blink_arrival_distance
	wanted.y = global_position.y
	# Teletransporte duro, así que el recorte cuadrado no alcanza: la máscara
	# de la arena llena celdas enteras con muros de 7 m, y salir dentro de una
	# deja al jefe encaramado en roca donde nadie lo alcanza cuerpo a cuerpo.
	_blink_target = _safe_arena_point(wanted)
	Telegraph.spawn_disc(self, _blink_target, blink_disc_radius, blink_windup, telegraph_color)
	# Señal de hundirse: el sudario se aplasta en el pantano durante la carga.
	_play_cue(_visual, "scale", Vector3(1.2, 0.1, 1.2), blink_windup * 0.8,
			Tween.TRANS_QUAD, Tween.EASE_IN)


func _resolve_blink() -> void:
	_state = State.PURSUE
	global_position = _blink_target
	Sfx.play(&"burrow_pop")
	Telegraph.spawn_disc(self, global_position, blink_disc_radius, impact_flash_time,
			impact_color)
	Juice.shake(blink_shake_strength, blink_shake_duration)
	_play_cue(_visual, "scale", Vector3.ONE, blink_rise_time,
			Tween.TRANS_BACK, Tween.EASE_OUT)
