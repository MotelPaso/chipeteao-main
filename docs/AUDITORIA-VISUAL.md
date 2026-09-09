# Auditoría VISUAL — ronda 2 (iteraciones 60-61)

Rama `task/visual-ronda-2`, salida de `task/audit-ronda-2` (`43844f4`), tag
`pre-visual` en la cabeza anterior.

## Por qué existe este documento

Las auditorías anteriores de este proyecto se hicieron **enteras a ciegas**.
`tools/verificar.sh`, los cinco soaks, el harness de UI y el lint corren
`--headless`, y el `DisplayServer` de pega **no compila un shader ni rasteriza
un triángulo**. Eso deja una clase entera de fallo sin puerta posible: una
malla con los triángulos al revés, un material que nunca llega, un panel
dibujado encima del reloj, una etiqueta cortada. Todos dan un log
perfectamente verde.

Las iteraciones 51 a 59 pasaron todas las puertas con **el suelo de las tres
arenas invisible**, y quien lo vio fue el jugador arrancando la build
exportada. Esta ronda cierra ese hueco: primero le puso una **cámara** al
harness (iteración 60, `BONK_SHOT_DIR`), después miró.

## Cómo se reprodujo

Todas las capturas salen de corridas **con ventana** de los harnesses que ya
existían, con la variable nueva puesta. Ninguna se sacó con un capturador de
pantalla: macOS le niega `screencapture` a una terminal sin permiso de
Grabación de Pantalla, así que la foto se toma **desde dentro del motor**
(`Viewport.get_texture().get_image()` tras `await RenderingServer.frame_post_draw`).

```sh
BONK_SHOT_DIR="$TMPDIR/bonk-shots/hollow" BONK_SHOT_EVERY=10 \
BONK_SAVE_PATH="$TMPDIR/save_hollow.json" \
BONK_GODMODE=1 BONK_SEED=7 BONK_GAME_SEED=7 \
godot --path . --resolution 1280x720 --position 60,60 \
  --fixed-fps 60 --quit-after 3600 res://scenes/tests/ArenaProbe.tscn
```

**Las rutas de este documento son relativas a `$TMPDIR/bonk-shots/`** (fuera
del repo a propósito: ningún PNG de una corrida entra en el árbol). El
directorio es de sesión; el comando de arriba las regenera.

| Directorio | Qué es |
|---|---|
| `00-baseline-hollow/` | la PRIMERA corrida con ventana, antes de tocar nada |
| `before-floor/<Arena>/`, `after-floor/<Arena>/` | el mismo comando con y sin el arreglo del suelo, por bioma |
| `09-hudcheck-before/`, `10-hudcheck/` | el mismo comando con y sin los arreglos del HUD, con FPS y puntos encendidos |
| `<caso>/` y `after/<caso>/` | el barrido completo, antes y después de los arreglos del HUD |

## Hallazgos arreglados

| Id | Sev | Pantalla / sistema | Qué se veía | Causa | Arreglo | Antes | Después |
|---|---|---|---|---|---|---|---|
| V1 | **ALTA** | Terreno, los tres biomas | **El suelo no estaba.** Se caminaba sobre un collider invisible y la arena se leía como props flotando sobre el disco del backdrop: sin relieve, sin ruido de bioma, con las sombras cayendo sobre un plano liso | `terrain.gd::_build_mesh` emitía sus índices `(top_left, bottom_left, top_right)`, que es **antihorario visto desde +Y**. La cara frontal de Godot es la **horaria**, así que la superficie entera se culeaba por back-face desde cualquier cámara por encima. No hay línea de log: el `ArrayMesh` se construye bien (`Terrain built: … min=-1.9 max=1.8`), el `ShaderMaterial` del bioma sí queda enlazado (comprobado en runtime) y el shader **sí compila** — el stdout de la corrida de referencia no tiene una sola línea de shader | iteración 60: se invierte el orden a `(top_left, top_right, bottom_left)` y se añade `_assert_winding()`, que mira el primer triángulo en **cada** construcción y hace `push_error` si su normal de mano derecha apunta hacia arriba. La guarda se probó fallando con el orden viejo y callada con el nuevo | `before-floor/HollowWoods/final.png`, `before-floor/AshDunes/final.png`, `before-floor/Gloomfen/final.png`, `00-baseline-hollow/shot_10.0s.png`, `00-baseline-hollow/shot_39.6s.png` | `after-floor/HollowWoods/final.png`, `after-floor/AshDunes/final.png`, `after-floor/Gloomfen/final.png`, `after/hollow/shot_10.0s.png` |
| V2 | MEDIA | HUD, arriba al centro | La chapa de clima se dibujaba **encima del reloj** y le tapaba la mitad inferior: durante todo cada clima (45 s de cada tanda) el tiempo de partida era ilegible | `_build_weather_badge` ponía la chapa en `position.y = 26` **desde el TOP** de `%TimerLabel`, cuya fuente es de 34 px más el relleno de `UiTheme.style_badge`: 26 px cae dentro de la etiqueta | iteración 61: `maxf(_timer_label.size.y, WEATHER_BADGE_MIN_DROP) + WEATHER_BADGE_GAP`, medido en vez de adivinado | `09-hudcheck-before/shot_31.7s.png`, `00-baseline-hollow/shot_10.0s.png` | `10-hudcheck/shot_31.7s.png`, `after/w_eclipse/shot_30.0s_weather_eclipse.png` |
| V3 | MEDIA | HUD, arriba a la derecha (= **L5-1** de `AUDITORIA-RONDA-2.md`, allí diferido) | El minimapa tapaba **entera** la etiqueta de puntos y **entera** la insignia de FPS, que quedaba dibujada dentro del cuadro negro del mapa. En co-op tapaba además el contador de bajas de la celda superior | `MINIMAP_SOLO_TOP` 46 + margen 14 dejaba el mapa en y 60..210, sobre `%PointsLabel` (56) y la insignia (76). Y el inset extra **solo se aplicaba en solitario** (`if count == 1`), cuando la pila superior derecha está anclada a la **ventana** y la comparte toda celda pegada al borde de arriba | iteración 61: `MINIMAP_TOP_UNDER_HUD` = offset de la insignia + su alto + 8, aplicado a **toda** celda con `cell.position.y == 0` | `09-hudcheck-before/shot_31.7s.png`, `coop/shot_20.0s.png` | `10-hudcheck/shot_31.7s.png`, `after/coop/shot_20.0s.png` |
| V4 | MEDIA | HUD, abajo al centro | La fila de power-ups activos no era una fila: era una **columna de 104 px de alto** con la ficha estirada, dibujada **encima de la barra de vida** y partiendo por la mitad el texto de HP | `_rebuild_powerup_row` escribía `offset_left` y `offset_top` y **no** `offset_right` ni `offset_bottom`. `set_anchors_preset` pone los cuatro a cero, así que el contenedor quedaba anclado al borde inferior de la ventana con 104 px de alto en vez de colapsado en el punto de anclaje | iteración 61: se escriben los cuatro offsets, el contenedor toma su tamaño mínimo y crece hacia arriba y hacia los lados | `09-hudcheck-before/shot_31.7s.png`, `w_eclipse/shot_44.2s.png`, `pu_flight/shot_29.6s.png` | `10-hudcheck/shot_31.7s.png`, `after/pu_timestop/shot_44.6s.png` |
| V5 | BAJA | HUD, abajo a la derecha | En cuanto el raider recogía **un solo objeto**, su ficha se dibujaba encima de `%PauseHintLabel` y «Esc — Pausa» se quedaba en «Esc —» | Las dos tiras terminaban a 20 px del borde inferior (`offset_bottom = -20`, alto 48) y la pista está a 12 px del borde con 20 px de alto: se solapan 12 px | iteración 61: `BOTTOM_STRIP_MARGIN` 36 para **las dos** tiras, que se leen como una sola fila | `09-hudcheck-before/shot_31.7s.png`, `w_eclipse/shot_44.2s.png` | `10-hudcheck/shot_31.7s.png`, `after/poi2/shot_91.1s_lucky.png` |
| V6 | BAJA | HUD, arriba a la derecha | La insignia de FPS empezaba dentro de la etiqueta de puntos (se solapan ~4 px). Invisible mientras el minimapa las tapaba a las dos (V3), visible en cuanto V3 se arregló | `FPS_BADGE_OFFSET.y` = 76 contra un `%PointsLabel` que arranca en 56 con fuente 18 | iteración 61: 76 → 88, y la pila queda escrita como pila en `ARQUITECTURA.md` | `09-hudcheck-before/shot_31.7s.png` (la insignia dentro del mapa) | `10-hudcheck/shot_31.7s.png` |
| V7 | **ALTA** | Toda la interfaz, en cuanto la ventana deja de medir 1280x720 | **Al maximizar (el botón verde del Mac) el HUD, los menús y los botones se quedaban a menos de la mitad de su tamaño relativo.** Reportado por el jugador sobre la build exportada | `project.godot` **no declaraba `[display]`**, así que corría con los valores por defecto de Godot: base 1152x648 y `stretch/mode = "disabled"`. «disabled» significa que un `Control` mide lo mismo en PÍXELES pase lo que pase con la ventana, así que al pasar de 1280x720 a 3024x1898 todo se encogió a ojo. Ninguna puerta podía verlo: es el mismo agujero que dejó pasar el suelo invisible | iteración 62: base **1280x720** con `stretch/mode = "canvas_items"` y `aspect = "expand"`. `canvas_items` escala solo el 2D y deja el 3D nativo; `expand` evita barras negras en el 1.59:1 del MacBook. La base es 1280x720 porque es sobre lo que está calibrado `hud.gd`: **el mismo fotograma a 1280x720 antes y después difiere en 0 píxeles de 921 600** | `scale-before/2560x1440/shot_10.0s.png` | `scale-after/2560x1440/shot_10.0s.png`, `scale-after/fullscreen/shot_10.0s.png` (3024x1898 reales), `scale-after/ui2560/ui_05_cards_all_p8.png`, `scale-after/coop2560/shot_16.0s.png` |
| H1 | — | El harness, no el juego | Las fotos de evento salían **un fotograma antes del evento**: el mapa de Tab se fotografiaba cerrado, un clima forzado se fotografiaba con el tinte del anterior y un cambio de etapa en negro a mitad del fundido | El evento y su aspecto no ocurren en el mismo fotograma: el overlay abre al siguiente del Tab, el tinte entra en rampa y la etapa va detrás del corte de `ScreenFade` | iteración 60: `ShotCamera.request_in(delay, stem)`; etapa y clima esperan 1.5 s, el mapa 0.6 s | `poi/shot_59.2s_map.png` (mapa cerrado), `w_golden_rain/shot_30.0s_weather_golden_rain.png` (tinte anterior), `stage/shot_133.7s_stage2.png` (fundido) | `after/poi/shot_59.2s_map.png`, `after/w_golden_rain/shot_30.0s_weather_golden_rain.png`, `after/stage/shot_136.1s_stage2.png` |

## Lo que se miró y estaba bien

Una captura por fila, todas de la pasada posterior a los arreglos.

| Qué | Captura | Qué se comprobó |
|---|---|---|
| Bosque Hueco | `after/hollow/shot_10.0s.png` | suelo opaco con relieve, props apoyados, sombras sobre el terreno |
| Dunas de Ceniza | `after-floor/AshDunes/final.png` | dunas con relieve, cactus y rocas apoyados, tinte de bioma correcto |
| Ciénaga | `after-floor/Gloomfen/final.png` | suelo opaco, niebla del bioma, props apoyados |
| Pantalla dividida (2 jugadores) | `after/coop/shot_20.0s.png` | dos celdas, un minimapa por celda en su propia esquina, fila de compañero arriba a la izquierda, barra de vida y tiras compartidas |
| Luna de sangre | `after/w_blood_moon/shot_20.0s_weather_blood_moon.png` | tinte rojo, chapa con cuenta atrás |
| Eclipse | `after/w_eclipse/shot_30.0s_weather_eclipse.png` | oscurecido y desaturado, banner legible a opacidad plena |
| Luna llena | `after/w_full_moon/shot_30.0s_weather_full_moon.png` | tinte azul pálido |
| Lluvia de enemigos | `after/w_enemy_rain/shot_30.0s_weather_enemy_rain.png` | tinte cian **y** un enemigo cayendo del cielo en la propia foto |
| Lluvia radiactiva | `after/w_radioactive_rain/shot_30.0s_weather_radioactive_rain.png` | tinte verde ácido |
| Lluvia dorada | `after/w_golden_rain/shot_30.0s_weather_golden_rain.png` | tinte dorado |
| Tsunami | `after/w_enemy_tsunami/shot_30.0s_weather_enemy_tsunami.png` | chapa de 3 s, anuncio con la dirección |
| Terremoto | `after/w_earthquake/shot_30.0s_weather_earthquake.png` | **el HUD entero desplazado** por la sacudida, sin que nada se salga ni se solape |
| Lluvia de meteoritos | `after/w_meteor_shower/shot_30.0s_weather_meteor_shower.png` | tinte cálido y marcas de impacto en el suelo |
| Los climas se **quitan** | `after/w_eclipse/shot_44.2s.png` frente a `after/w_eclipse/shot_15.0s.png` | el tinte entra y sale; `HUD offset: (0.0, 0.0)` tras el terremoto en `after/logs/w_earthquake.log` |
| Vendedor: llegada | `after/poi/shot_20.0s_vendor_items.png` | el puesto aparece junto al raider |
| Vendedor: tienda | `after/poi2/shot_102.2s.png` | título, puntos, cuatro fichas con rareza y precio, «Salir»; el HUD de debajo atenuado (medido: media de brillo 70.6 contra 195.1 sin atenuar) |
| Bloque de la suerte | `after/poi2/shot_91.1s_lucky.png` | cubo amarillo con su «?», `Lucky block: points` en el log |
| Mapa de Tab | `after/poi/shot_59.2s_map.png` | imagen del terreno con niebla, **13 filas de leyenda** incluida «Bloques de la suerte», paneles de power-ups, mascota, estadísticas, jugadores y objetos |
| Minimapa | `after/hollow/shot_10.0s.png` | marco, niebla, marcadores del equipo |
| Tiempo detenido | `after/pu_timestop/shot_44.6s.png` | ficha «TD» con cuenta atrás sobre la barra de vida |
| Vuelo | `after/pu_flight/shot_29.6s.png` | ficha «VU» con cuenta atrás sobre la barra de vida; en ESE fotograma el raider está en suelo (el harness suelta el salto cada 15 s), así que la foto prueba la ficha, no el vuelo |
| Objetos (cinturón + sangre sayayin) | `after/items/shot_35.6s.png` | dos fichas en la tira derecha con su multiplicador «x3» |
| Báculo de nigromante | `after/necro/shot_35.6s.png` | dos siervos morados siguiendo al raider, ficha «BN» |
| Cruce de etapa | `after/stage/shot_136.1s_stage2.png` | arena nueva, insignia «E2», anuncio «Etapa 2 — Dunas de Ceniza», minimapa reiniciado |
| Carta de nivel | `10-hudcheck/shot_18.9s_card.png` | «Nivel 2 — elige: Armas», tres cartas sin solapes, fondo atenuado |
| Selección de personaje (16 fichas) | `after/ui/ui_05_cards_all_p8.png` | rejilla con desbloqueadas, bloqueadas con candado y precio, selector de jugadores, barra inferior de botones |
| Colección | `after/ui/ui_00_collection_p2.png` | cabecera, porcentaje, lista con entradas «???» |
| Misiones | `after/ui/ui_01_quests_p2.png` | cabecera, esquirlas, filas con barra de progreso `0/N` y recompensa, «Volver» |
| Armería | `after/ui/ui_02_relics_p2.png` | seis reliquias con descripción, escalera de rangos en rombos y precio, «Volver» |
| Ajustes | `after/ui/ui_08_settings_toggle_p1.png` | cinco filas (efectos, ambiente, sensibilidad, pantalla completa, mostrar FPS) y «Volver» |
| Fin de partida | `after/ui/ui_10_extract_p1.png` | «INCURSIÓN ABANDONADA» sobre la partida |
| La interfaz a cuatro resoluciones | `scale-after/{1280x720,1920x1080,2560x1440,fullscreen}/shot_10.0s.png` | mismo tamaño relativo en las cuatro; el 3D se sigue renderizando a resolución nativa (los PNG salen a 1280x720, 1920x1080, 2560x1440 y 3024x1898) |
| Los menús a 2560x1440 | `scale-after/ui2560/ui_05_cards_all_p8.png` | las 13 pruebas del harness de UI en verde y las fichas, títulos y botones escalados |
| Pantalla dividida a 2560x1440 | `scale-after/coop2560/shot_16.0s.png` | las dos celdas y sus minimapas escalan con la ventana |
| Shader de suelo del bioma | prueba temporal con `ALBEDO = vec3(n, 0, 1-n)` | el ruido de valor **sí** corre; se ve suave porque su celda es de ~2.9 m y la cámara está a unos metros del suelo. Revertido |

## Lo que sigue necesitando ojos humanos

Nada de esto es geometría, así que la cámara no puede decidirlo:

1. **Legibilidad de «Esc — Pausa».** Gris al 50% de alfa y sin contorno; sobre
   el césped claro casi desaparece (`after/poi2/shot_91.1s_lucky.png`). Ya no
   la tapa nada; que se lea o no es una decisión de estilo.
2. **El mapa de Tab deja el HUD debajo.** El reloj y la chapa de clima caen en
   el hueco entre el panel del mapa y la columna de paneles
   (`after/poi/shot_59.2s_map.png`). Es coherente con lo que documenta
   ARQUITECTURA (overlay en capa 8, HUD en 5), así que no se tocó.
3. **Los banners de anuncio a media transparencia** sobre un fondo movido: el
   tween entra en 0.3 s y sale en 0.6 s, y una foto a mitad los pilla lavados.
   A opacidad plena se leen bien (`after/w_eclipse/shot_30.0s_weather_eclipse.png`).
4. **El ruido de los suelos de bioma se lee muy plano** a la distancia de
   cámara real. El shader corre; es una decisión de arte, fuera del alcance.
5. **Sensación y ritmo**: nada de esto se juzga en una captura.

## La comprobación del switch

Sobre la cabeza final, el mismo comando con y sin `--headless`:

| Corrida | Resultado |
|---|---|
| Con ventana, Bosque Hueco, 60 s (`--quit-after 3600`) | **11 PNG y 11 líneas `Shot saved:`**, sin un solo `WARNING:` ni `ERROR:` |
| La misma con `--headless` | **`Shots skipped: headless`**, cero PNG (ni siquiera crea el directorio) |

Y `tools/verificar.sh` termina en **`VERIFICACIÓN OK`** con las puertas sin
tocar: 18 min 24 s en la cabeza de la iteración 61 y 14 min 17 s en la de la
62 (la del cambio de escala).

## Límites de esta ronda

- **Resoluciones cubiertas** (tras la iteración 62): 1280x720, 1920x1080,
  2560x1440 y pantalla completa real (3024x1898). **No** cubiertas: ventanas
  más pequeñas que la base, monitores ultrapanorámicos, ni 4 jugadores (el
  reparto de celdas para 4 se arregló por la misma regla que el de 2, pero no
  se fotografió).
- **El arte es placeholder a propósito** (iconos de dos letras): fuera del
  alcance por encargo.
- **La tienda del vendedor encalla el harness.** La sonda no sabe comprar, así
  que la UI se queda abierta y salta su propio aviso `WEDGE` a los 20 s
  (`after/logs/poi2.log`). Es una limitación del harness, no un fallo del
  juego: la pantalla se dibuja bien y un jugador la cerraría. Queda anotado
  para quien quiera enseñarle a comprar.
- **La cámara no juzga**: dice si algo se dibuja, dónde y encima de qué.
- **Una corrida con ventana tiene el teclado de verdad.** El juego recibe las
  teclas del sistema como cualquier ventana enfocada, así que un `Escape`
  perdido —el que manda otra app al cambiar el foco, por ejemplo— abre el
  menú de pausa y congela el soak. Pasó una vez en esta ronda y la sonda lo
  dijo con todas las letras: `ArenaProbe: WEDGE — tree paused 20s with no
  card UI; blocking=["PauseMenu"]`. No es un fallo del juego. Si una corrida
  con ventana se queda quieta, **eso es lo primero que hay que mirar en el
  log**; repetirla suele bastar.
- **El soak de etapa de `verificar.sh` es variable, y en esta ronda se vio.**
  Una corrida de la cabeza final no cruzó de mapa en 720 s
  (`Probe legs: reached=6 timed_out=16`, horda de 81 cuerpos al final) y
  falló las cuatro comprobaciones que cuelgan del cruce; **la misma cabeza
  con las mismas semillas** (`BONK_SEED=4242 BONK_GAME_SEED=4242`) cruzó
  **cuatro veces** al repetirla (`reached=33 timed_out=8`). Es la varianza
  que el propio `tools/verificar.sh` documenta en su comentario del soak de
  etapa: la semilla fija el MUNDO, no el orden de contactos de la física, y
  con la horda crecida el recorrido se queda pinchado. Nada que ver con esta
  ronda —ninguno de los cambios toca colisión, recorrido ni IA— pero queda
  anotado porque cuesta media hora descubrirlo dos veces.
