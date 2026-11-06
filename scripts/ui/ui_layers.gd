class_name UiLayers
extends RefCounted
## Orden de dibujo de las capas de la UI (CanvasLayer.layer): un número más
## alto dibuja encima de uno más bajo. Es la única tabla del orden: para
## subir o bajar una capa, cambia su número aquí. Nunca va en una escena:
## edita aquí.

## Viñeta de daño de Juice (juice.gd): sobre el mundo 3D y bajo el HUD.
const JUICE_VIGNETTE := 4
## HUD de la partida (HUD.tscn).
const HUD := 5
## Mapa de Tab (hud.gd): sobre el HUD.
const MAP_OVERLAY := 8
## Cartas de mejora (UpgradeCardUI.tscn).
const UPGRADE_CARDS := 10
## Paneles modales de la partida: vendedor y ruleta (vendor_ui.gd, roulette_ui.gd).
const MODAL := 15
## Pantalla de fin de partida (run_end_screen.gd): sobre las cartas de mejora.
const RUN_END := 20
## Menú de pausa (PauseMenu.tscn): sobre todo lo de la partida.
const PAUSE := 30
## Fundido de ScreenFade (screen_fade.gd): encima de todo.
const SCREEN_FADE := 100
