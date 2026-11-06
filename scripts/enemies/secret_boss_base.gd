class_name SecretBossBase
extends BossBase
## Chasis de los minijefes ocultos (GDD 6): solo aparecen por su disparador,
## sin horario del spawner ni revancha Elder, y heredan de BossBase todo lo
## de jefe (grupo boss, barra de vida, recorte de arena, pago en anillo, sin
## brillo shiny). Esta capa suma lo secreto al morir: la fanfarria, el
## contador de misión "slain_<id>" y el desbloqueo gratis del personaje cuya
## fila de catálogo nombra a este jefe en unlock_boss. Todo sale de datos: un
## jefe oculto nuevo es una escena más filas de catálogo, nunca una rama aquí.

## Clave de contador y de catálogo de este minijefe ("grubthing"): las
## misiones leen "slain_<secret_boss_id>" y las filas de CharacterCatalog lo
## nombran en unlock_boss.
@export var secret_boss_id: String = ""


func _init() -> void:
	# No poseíble: es un jefe y su muerte desbloquea un raider.
	possessable = false
	# Definir _init aquí oculta el de BossBase; se llama a mano.
	super()


func _ready() -> void:
	super()
	_health.died.connect(_on_secret_boss_died)


func _on_secret_boss_died() -> void:
	Sfx.play(&"secret_fanfare")
	if secret_boss_id.is_empty():
		return
	# Suma en memoria; el cierre de la partida la evalúa y la guarda, así la
	# misión se completa aunque el raider muera justo después de la baja.
	SaveData.bump("slain_" + secret_boss_id)
	var row := CharacterCatalog.by_unlock_boss(secret_boss_id)
	if row.is_empty():
		return
	# Lectura defensiva, como CharacterCatalog lee sus filas: acceder a una
	# clave que falta en un Dictionary falla, y esto corre dentro de un
	# manejador de muerte.
	var character_id := String(row.get("id", ""))
	if character_id.is_empty():
		push_warning("SecretBossBase: unlock row for '%s' has no id." % secret_boss_id)
		return
	# Idempotente: si el personaje ya estaba desbloqueado no hace nada y la
	# pelea queda como pago de gemas y misión.
	if SaveData.unlock_character(character_id, "boss"):
		# announce_major y no announce: un raider gratis es el anuncio más
		# grande de la partida, y un announce común lo pisa la siguiente
		# racha de bajas en 0.3 s.
		get_tree().call_group("boss_ui", "announce_major",
				"¡RAIDER DESBLOQUEADO: %s!" % String(row.get("display_name", character_id)))
	# Log de una línea para que las corridas headless lo confirmen.
	print("Secret boss slain: %s" % secret_boss_id)
