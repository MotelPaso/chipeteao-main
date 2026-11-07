class_name UiLayers
extends RefCounted
## Orden de dibujo de las capas de la UI que se crean en código
## (CanvasLayer.layer): un número más alto dibuja encima. Nunca va en una
## escena: edita aquí.
## Las capas de escena guardan su número en su .tscn (nodo raíz > Layer):
## HUD.tscn 5, UpgradeCardUI.tscn 10, modal/ModalPanel.tscn 15,
## RunEndScreen.tscn 20 y PauseMenu.tscn 30. El orden completo que importa es: viñeta de Juice 4 <
## HUD 5 < mapa de Tab 8 < cartas 10 < modales 15 < fin de partida 20 <
## pausa 30 < fundido 100.

## Viñeta de daño de Juice (juice.gd): sobre el mundo 3D y bajo el HUD.
const JUICE_VIGNETTE := 4
## Mapa de Tab (view_widgets.gd): sobre el HUD y bajo las cartas de mejora.
const MAP_OVERLAY := 8
## Fundido de ScreenFade (screen_fade.gd): encima de todo.
const SCREEN_FADE := 100
