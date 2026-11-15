class_name ScenePaths
extends RefCounted
## Rutas de las escenas entre las que navega la UI. Si mueves o renombras una
## de estas escenas, cambia su ruta aquí (la escena principal también está en
## project.godot, run/main_scene). Nunca va en una escena: edita aquí.

## Menú principal, la escena de entrada del juego.
const MAIN_MENU := "res://scenes/ui/MainMenu.tscn"
## Selector de personaje: se abre con Cacería desde el menú principal.
const CHARACTER_SELECT := "res://scenes/ui/CharacterSelect.tscn"
## Pantallas entre partidas que se abren desde el menú principal.
const QUEST_LOG := "res://scenes/ui/QuestLog.tscn"
const COLLECTION := "res://scenes/ui/Collection.tscn"
const RELIC_SHOP := "res://scenes/ui/RelicShop.tscn"
## La única escena en la que arranca una partida.
const RUN := "res://scenes/world/Run.tscn"
