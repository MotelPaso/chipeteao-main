class_name SecretBossBase
extends BossBase
## Chassis for the hidden minibosses (GDD 6): trigger-spawned only — no
## spawner timetable and no Elder rematch — with all the boss plumbing
## (boss group, HP-bar binding, arena clamp, ring payout, no elite glow)
## inherited from BossBase. This layer adds the secrets meta on death:
## the celebratory fanfare, the "slain_<id>" quest counter, and the free
## character unlock for whichever catalog row names this boss in its
## unlock_boss field — fully data-driven, so a new hidden boss is a scene
## plus catalog rows, never a new branch here.

## Counter/catalog key for this miniboss ("grubthing"): quests watch the
## "slain_<secret_boss_id>" counter and CharacterCatalog rows reference the
## id through unlock_boss.
@export var secret_boss_id: String = ""


func _ready() -> void:
	super()
	_health.died.connect(_on_secret_boss_died)


func _on_secret_boss_died() -> void:
	Sfx.play(&"secret_fanfare")
	if secret_boss_id.is_empty():
		return
	# In-memory bump; the run-end fold evaluates and persists it, so the
	# quest completes even if the player dies right after the kill.
	SaveData.bump("slain_" + secret_boss_id)
	var row := CharacterCatalog.by_unlock_boss(secret_boss_id)
	if row.is_empty():
		return
	# Idempotent: with the character already unlocked (purchase or an
	# earlier kill) this no-ops and the fight stays a gem/quest payday.
	if SaveData.unlock_character(String(row.id), "boss"):
		get_tree().call_group("boss_ui", "announce",
				"CHARACTER UNLOCKED: %s!" % String(row.display_name))
	# One-line log (RunManager convention) so headless runs can confirm it.
	print("Secret boss slain: %s" % secret_boss_id)
