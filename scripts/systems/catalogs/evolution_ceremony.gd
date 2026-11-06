class_name EvolutionCeremony
extends RefCounted
## Ceremonia de un hito de arma (evolución o ascenso): fanfarria, destello
## sobre quien lleva el arma, sacudida de cámara y cartel grande.
## EvolutionCatalog.try_advance_by_level decide QUÉ hito ocurre; este script
## decide cómo se ve y se oye. No tiene escena, así que sus valores son
## constantes: edita aquí.

# --- Edita aquí --------------------------------------------------------------

## Cartel de una evolución: el primer %s es el nombre del arma, el segundo el
## nombre evolucionado.
const EVOLVED_BANNER: String = "¡%s evolucionó a %s!"
## Cartel de un ascenso: %s es el nombre del arma.
const ASCENDED_BANNER: String = "¡%s asciende!"
## Sonido de la fanfarria (id de Sfx).
const FANFARE_SFX: StringName = &"secret_fanfare"
## Altura del destello sobre el jugador, en metros.
const SPARKLE_HEIGHT: float = 1.2
## Fuerza de la sacudida de cámara (primer argumento de Juice.shake).
const SHAKE_STRENGTH: float = 0.25
## Duración de la sacudida de cámara, en segundos.
const SHAKE_DURATION: float = 0.5


## Celebra una evolución: fanfarria, destello, sacudida y el cartel
## EVOLVED_BANNER con `weapon_name` y `evolved_name`.
static func play_evolution(player: Node, weapon_name: String, evolved_name: String) -> void:
	_celebrate(player)
	_announce(EVOLVED_BANNER % [weapon_name, evolved_name])


## Celebra un ascenso: fanfarria, destello, sacudida y el cartel
## ASCENDED_BANNER con `weapon_name`.
static func play_ascension(player: Node, weapon_name: String) -> void:
	_celebrate(player)
	_announce(ASCENDED_BANNER % weapon_name)


## Fanfarria, destello sobre `player` y sacudida. Los autoloads se buscan con
## AutoloadLookup: un harness `-s` no los tiene y debe seguir sin ellos en vez
## de abortar.
static func _celebrate(player: Node) -> void:
	var sfx := AutoloadLookup.find(&"Sfx")
	if sfx != null:
		sfx.play(FANFARE_SFX)
	var juice := AutoloadLookup.find(&"Juice")
	if juice != null:
		if player is Node3D:
			juice.sparkle((player as Node3D).global_position + Vector3.UP * SPARKLE_HEIGHT)
		juice.shake(SHAKE_STRENGTH, SHAKE_DURATION)


## El cartel grande, por el grupo "boss_ui" (announce_major del HUD).
static func _announce(message: String) -> void:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return
	loop.call_group("boss_ui", "announce_major", message)
