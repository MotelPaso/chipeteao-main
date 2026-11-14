class_name BossBurnout
extends Node
## Desgaste de un jefe de etapa (nodo Burnout de la escena del jefe). Si una
## vida dura bastante más de lo previsto, el jefe empieza a CONSUMIRSE solo:
## pierde vida a ritmo fijo hasta que esa vida se acaba. Así la pelea siempre
## termina, aunque la party casi no le pueda pegar: un jefe que pelea solo no
## deja horda de la que sacar XP para mejorar a mitad de pelea.
## Cuándo empieza y a qué ritmo lo decide StageBossScaling en el plan de cada
## vida (burnout_after, burnout_seconds); aquí están el pulso y el aviso. No
## sabe qué jefe lo lleva.

@export_group("Desgaste")
## Segundos entre un pulso de desgaste y el siguiente.
@export var tick_seconds: float = 0.5
## Aviso del HUD cuando empieza a consumirse; %s es el nombre del jefe (vacío = sin aviso).
@export var announce_text: String = "%s se consume en su propio fuego"

## True mientras un pulso de desgaste está quitando vida: quien lleva la
## cuenta del daño de la party lo mira para no sumar este.
var draining: bool = false

var _health: Health = null
var _title: String = ""
var _after: float = 0.0
var _drain: float = 0.0
var _started: bool = false
var _tick_left: float = 0.0


## Prepara una vida nueva del jefe `title`: pasados `after_seconds` de esa
## vida pierde `drain_per_second` de vida por segundo. Con 0 no se consume.
func arm(health: Health, title: String, after_seconds: float, drain_per_second: float) -> void:
	_health = health
	_title = title
	_after = after_seconds
	_drain = drain_per_second
	_started = false
	_tick_left = 0.0


## Un frame de pelea. `life_seconds` son los segundos vulnerables que lleva
## la vida actual.
func tick(delta: float, life_seconds: float) -> void:
	if _after <= 0.0 or _drain <= 0.0 or _health == null or life_seconds < _after:
		return
	if not _started:
		_started = true
		# Línea de log para los soaks: desde aquí la vida se acaba sola.
		print("%s burnout: after=%.1fs drain=%.1f/s" % [_title, life_seconds, _drain])
		if not announce_text.is_empty():
			get_tree().call_group("boss_ui", "announce", announce_text.replace("%s", _title))
	_tick_left -= delta
	if _tick_left > 0.0:
		return
	_tick_left = tick_seconds
	draining = true
	_health.take_damage(_drain * tick_seconds)
	draining = false
