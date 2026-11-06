class_name HummingSkull
extends SecretTrigger
## Secreto de Dunas de Ceniza: una pila de huesos cuyo cráneo brilla turquesa
## y zumba. Con E dentro del anillo se ESCUCHA: un canal que solo avanza si el
## raider que apretó se queda quieto (moverse o salir lo reinicia a cero) y
## que al cumplir listen_time despierta al minijefe. El despertar vive en
## SecretTrigger.

## Ritmo del brillo (Hz): lento en reposo, rápido mientras se escucha, y su vaivén (fracción).
const GLOW_IDLE_HZ: float = 1.6
const GLOW_LISTEN_HZ: float = 9.0
const GLOW_SWING: float = 0.25

## Segundos de escucha quieto para despertarlo.
@export var listen_time: float = 4.0
## Velocidad horizontal (m/s) por encima de la cual el raider cuenta como en movimiento.
@export var still_speed_limit: float = 0.2
## Segundos iniciales en los que moverse no cancela (solo no suma), para apretar E mientras frenas.
@export var start_grace: float = 0.4
## Aviso tras cancelar la escucha por moverse.
@export var cancel_prompt: String = "[E] El zumbido se apartó — no te muevas"
## Loop de Sfx compartido con los altares de carga (va con contador por _hold_loop/_drop_loop).
@export var hum_loop: StringName = &"shrine_channel"

## true mientras corre la escucha (lo lee el harness).
var listening: bool = false
## Segundos quieto acumulados (vuelve a 0 al cancelar; lo lee el harness).
var progress: float = 0.0

## El raider que apretó: el canal mide SU quietud, no la del más cercano.
var _listener: Node3D = null
var _listen_age: float = 0.0
var _idle_prompt: String
var _glow_base_energy: float = 1.0
var _time: float = 0.0

@onready var _glow_light: OmniLight3D = $Visual/GlowLight


func _ready() -> void:
	super()
	_idle_prompt = prompt_text
	_glow_base_energy = _glow_light.light_energy


func _physics_process(delta: float) -> void:
	_time += delta
	# El brillo respira lento en reposo y aletea durante la escucha.
	var rate := GLOW_LISTEN_HZ if listening else GLOW_IDLE_HZ
	_glow_light.light_energy = _glow_base_energy * (1.0 + GLOW_SWING * sin(_time * rate))
	if not listening:
		return
	_listen_age += delta
	# La quietud de QUIEN ESCUCHA: en co-op, un compañero que pasa corriendo
	# no cancela.
	if not is_instance_valid(_listener):
		_cancel_listen()
		return
	var player := _listener as CharacterBody3D
	if player == null or not player.is_in_group("player") \
			or not _players_in_range.has(player):
		_cancel_listen()
		return
	if Vector2(player.velocity.x, player.velocity.z).length() > still_speed_limit:
		if _listen_age > start_grace:
			_cancel_listen()
		return
	progress += delta
	set_prompt("Escuchando... %d%%" % roundi(clampf(progress / listen_time, 0.0, 1.0) * 100.0))
	if progress >= listen_time:
		_complete_listen()


func _interact(player: Node) -> void:
	if listening:
		return
	listening = true
	_listener = player as Node3D
	progress = 0.0
	_listen_age = 0.0
	_hold_loop(hum_loop)
	_emit_started()


func _on_range_exited() -> void:
	if listening:
		_cancel_listen()


## Moverse (o salir del anillo) borra el canal entero: a diferencia del altar
## de carga no hay reanudar, la escucha empieza de cero.
func _cancel_listen() -> void:
	listening = false
	_listener = null
	progress = 0.0
	_drop_loop()
	set_prompt(cancel_prompt)
	_emit_cancelled()


func _complete_listen() -> void:
	listening = false
	_listener = null
	_drop_loop()
	set_prompt(_idle_prompt)
	set_physics_process(false)
	_awaken()
