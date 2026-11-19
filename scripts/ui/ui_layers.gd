class_name UiLayers
extends RefCounted
## Orden de dibujo de las capas de la UI que se crean en código
## (CanvasLayer.layer): un número más alto dibuja encima. Nunca va en una
## escena: edita aquí.
## Las capas de escena guardan su número en su .tscn (Layer del nodo
## CanvasLayer): HUD.tscn 5, el nodo Overlay de las dos cinemáticas de jefe
## 9 (enemies/mythos/MythosCinematic.tscn y
## enemies/blue_lobster/LobsterEntrance.tscn), UpgradeCardUI.tscn 10,
## modal/ModalPanel.tscn 15, RunEndScreen.tscn 20 y PauseMenu.tscn 30; el
## nodo Feel de Mythos.tscn y de BlueLobster.tscn (su viñeta de peligro) va
## en 4, como la de Juice. El orden completo que importa es: viñetas de Juice
## y de los jefes 4 < HUD 5 < mapa de Tab 8 < cinemática de jefe 9 < cartas
## 10 < modales 15 < fin de partida 20 < pausa 30 < fundido 100.

## Viñeta de daño de Juice (juice.gd): sobre el mundo 3D y bajo el HUD.
const JUICE_VIGNETTE := 4
## Mapa de Tab (view_widgets.gd): sobre el HUD y bajo las cartas de mejora.
const MAP_OVERLAY := 8
## Fundido de ScreenFade (screen_fade.gd): encima de todo.
const SCREEN_FADE := 100
