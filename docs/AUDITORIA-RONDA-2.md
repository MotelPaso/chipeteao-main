# Auditoría de la ronda 2 (iteraciones 46-56)

Cacería de bugs sobre las once iteraciones de «feedback ronda 2»
(`main` 0c7400d → `task/feedback-ronda-2` 9b06c54: 137 archivos,
+12 616 / −1 355). Cuatro instrumentos, en este orden: cobertura de harness
(iteración 57), seis carriles de auditoría de solo lectura sobre el diff,
soaks de estrés sobre el harness ampliado, y arreglos de raíz (58 y 59).

**Ids**: `L<carril>-<n>` para los hallazgos de carril, `S-<n>` para los que
salieron de los soaks de estrés. **Estados**: `fixed` (con commit y prueba),
`deferred` (con motivo de una línea) o `not-a-bug` (con la evidencia que lo
descartó).

## Márgenes de referencia (baseline en `pre-audit`, 9b06c54)

`tools/verificar.sh` en verde, exit 0, 14 min de reloj.

| Soak | nivel | explored | cofres | altares | portales | airborne | legs |
|---|---|---|---|---|---|---|---|
| HollowWoods 360 s | 12 | 0.18 | 9 | 4 | 0 | 0 | 11 ok / 3 timeout |
| AshDunes 360 s | 14 | 0.19 | 1 | 1 | 1 | 0 | 7 ok / 6 timeout |
| Gloomfen 360 s | 19 | 0.16 | 11 | 3 | 4 | 0 | 22 ok / 1 timeout |
| Etapa 720 s | 45 | 0.08 (exenta) | 25 | 2 | 2 | 0 | 35 ok / 6 timeout; 4 avances, 8 carries |

Suma de interactuables de las tres arenas: **34**. Barridos sucios: **0**.
Aperturas de máscara: **0** en las cinco pasadas.

### Comparación de márgenes tras la higiene de guardado (57.2)

Los soaks ya no comparten `user://soak_save.json`; cada uno arranca de un
archivo vacío. La corrida de la iteración 57, contra la de referencia:

| Soak | nivel base → 57 | explored base → 57 | airborne |
|---|---|---|---|
| HollowWoods | 12 → 12 | 0.18 → 0.14 | 0 → 0 |
| AshDunes | 14 → 14 | 0.19 → 0.17 | 0 → 0 |
| Gloomfen | 19 → 17 | 0.16 → 0.16 | 0 → 0 |
| Etapa | 45 → 55 | 0.08 → 0.13 | 0 → 0 |

Suma de interactuables: 34 → **40**.

**No es un hallazgo.** `explored` se mueve dentro de la banda de ±0.05 en
las cuatro. El nivel se sale de ±1 en dos de ellas, pero la causa no es el
guardado: **dos corridas de la MISMA cabeza y las mismas semillas**, ambas
con archivos nuevos, dieron `15 / 16 / 14 / 26` y `12 / 14 / 17 / 55`. La
dispersión del propio número entre corridas idénticas es mayor que su
diferencia contra la referencia, así que el archivo compartido no puede
leerse como la causa — y era de esperar: los soaks godmode nunca terminan
la partida, o sea que nunca doblaban meta, y lo único que el archivo
arrastraba (`kills_<script>`, `used_weapon_<id>`) no lo lee nada durante
una corrida. Lo que la higiene arregla es la contaminación entre la
corrida mortal y la del harness de UI, que sí escriben esquirlas,
misiones y desbloqueos.

El reloj de la verificación se comporta igual: 16 min una corrida y 75 min
la otra, con el mismo código y las mismas semillas. Lo manda el tamaño de
la horda, no el número de frames.

## Cobertura añadida antes de auditar (iteración 57)

Cinco superficies que ningún soak había tocado nunca, porque un bug que
nadie ejecuta no puede ensuciar ningún log:

| Superficie | Antes | Ahora |
|---|---|---|
| Co-op (2 raiders, derribo y reanimación) | ningún soak | quinto soak de `verificar.sh`, `BONK_PLAYERS=2 BONK_DOWN_NOW=45` |
| Siete de las nueve escenas de UI | nada las arrancaba | `UiProbe.tscn`, 13 pasos |
| Referencias cruzadas de catálogo | nada las comprobaba | `CatalogLint.tscn`, 9 comprobaciones |
| Las seis recompensas del bloque de la suerte | tabla ponderada, la rara 1 de cada ~10 | `BONK_LUCKY_REWARD` fuerza la cola |
| Fin de partida mortal | el árbol quedaba pausado hasta el `WEDGE` | `Probe: run ended` y salida limpia |
| Higiene de guardado | un archivo compartido por todos los soaks | uno por soak, con sus `.bak`/`.tmp` |

## Hallazgos

Prioridad de triaje: errores en cualquier ruta > estados atascados >
fugas entre etapas o partidas > reglas equivocadas > fallos silenciosos >
marcadores de cadena > deriva de documentación.

### Carril 1 — ciclo de partida, etapas, guardado, co-op, catálogos meta

| Id | Sev | Dónde | Qué | Estado |
|---|---|---|---|---|
| L1-1 | HIGH | `scripts/world/run_root.gd:194` | Un cambio de etapa con un menú de vendedor o de ruleta abierto deja el árbol pausado **para siempre**: esos `CanvasLayer` cuelgan de la arena (`vendor.gd:162`, `roulette_shrine.gd:82`), así que `_arena.free()` los destruye sin pasar por su `_close()` —el único `get_tree().paused = false` que existe— y `was_paused` ya era `true`, así que el paso 7 tampoco despausa. `_swap_stage` nunca llama al hook `dismiss()` del grupo `blocking_ui_closable`. Contradice el CHANGELOG 54 («VendorUi … pauses and always unpauses») y el propio comentario de `vendor.gd:160`. | **fixed** (58), aserción `Swap menu: paused=true` → `false` |
| L1-2 | MEDIUM | `scripts/world/run_root.gd:129` | `advance_stage()` no comprueba `RunState.run_active`: una pulsación de portal cuya cortina sobrevive a la party reconstruye una etapa entera para una partida ya doblada al guardado. | **fixed** (58) |
| L1-3 | MEDIUM | `docs/ARQUITECTURA.md:297` | (sembrado) «para explícitamente el spawner **y el director**»: `_swap_stage` solo para el spawner (`run_root.gd:157`); el director se para a sí mismo dentro de `on_stage_ended` (`world_director.gd:387`), en el paso 3. El comentario del propio `run_root.gd:152-156` repite el error. | **fixed** (59, doc) |
| L1-4 | MEDIUM | `docs/ARQUITECTURA.md:300` | El formato documentado de `Stage sweep:` tiene 6 campos; el código imprime 10 y `verificar.sh` greppea el literal de 10. | **fixed** (59, doc) |
| L1-5 | MEDIUM | `scripts/world/exit_portal.gd:120` | Marca `_taken`/`consume()` **antes** de que `advance_stage()` pueda declinar (ScreenFade ocupado), dejando un portal muerto. Contradice `run_root.gd:137-139`. | **fixed** (58) |
| L1-6 | MEDIUM | `scripts/ui/roulette_ui.gd:87` | El vigía de auto-cierre mira solo `_player`, nunca `_shrine`; su hermano `vendor_ui.gd:126` mira los dos. | **fixed** (58) |
| L1-7 | MEDIUM | `docs/ARQUITECTURA.md:56`, `:956` | `blocking_ui_closable` «hoy solo la ruleta» y `dismiss()` «sin llamador todavía»: `vendor_ui.gd:99/115` es un segundo miembro desde la iteración 54. | **fixed** (59, doc) |
| L1-8 | LOW | `docs/ARQUITECTURA.md:33` | El contrato del grupo `enemy_spawner` sigue anunciando `apply_tier_spec`, borrado con los grados en la iteración 50. | **fixed** (59, doc) |
| L1-9 | LOW | `scripts/systems/save_data.gd:113` | `Save path overridden:` no estaba en el inventario de logs. | **fixed** (57) |
| L1-10 | LOW | `scripts/systems/save_data.gd:20`, `:34` | Comentarios de cabecera obsoletos (`best_endless_minutes`, reglas de desbloqueo de mapa). | deferred: comentarios de cabecera, sin consumidor; cambian con el próximo toque de `save_data.gd` |
| L1-11 | LOW | `scripts/world/run_systems.gd:42` | `show_stage_tag` corre antes de que `RunRoot._ready` resuelva `stage_index`: una partida que empieza pasada la etapa 1 muestra «E1» hasta el primer cruce. | deferred: solo alcanzable con `BONK_ARENA` apuntando a un bioma que no es el primero; ninguna partida real empieza pasada la etapa 1 |
| L1-12 | LOW | `scenes/world/RunSystems.tscn:34` | El nodo `FogOfWar` está declarado después de la sección `[connection]`. | deferred: carga bien hoy; reordenarlo es un cambio de escena sin síntoma |
| L1-13 | LOW | `scripts/ui/run_end_screen.gd:198`, `:204` | Se descarta el retorno de `ScreenFade.leave_run()`; `pause_menu.gd:148` sí lo comprueba. | **fixed** (59) |
| L1-14 | LOW | `scripts/ui/screen_fade.gd:87` | `await action.call()` no tiene ruta de fallo: una acción que revienta deja `_busy` y el rectángulo negro puestos para siempre. | deferred: un `_busy` colgado necesita que la acción reviente, y no hay ninguna que lo haga hoy; el arreglo honesto (un vigía en el autoload) es más grande que el hallazgo |

### Carril 2 — director del mundo, clima, POIs, economía, props

| Id | Sev | Dónde | Qué | Estado |
|---|---|---|---|---|
| L2-1 | MEDIUM | `scripts/world/world_director.gd:1364` | `_weather_start_full_moon` reparte solo al grupo `player`: un raider derribado se queda sin la luna llena entera. Su hermana `_weather_start_golden_rain` sí recorre los dos grupos. Además los dos boons van **sin tag**. | **fixed** (59) |
| L2-2 | MEDIUM | `scripts/world/world_director.gd:1530` | La ola del tsunami se dimensiona con el reloj de **partida**; `docs/ARQUITECTURA.md:768` dice «minuto de **etapa**», que es a donde la iteración 50 movió jefes y hordas. | **fixed** (59) |
| L2-3 | MEDIUM | `scripts/world/world_director.gd:493` | `_physics_process` sale antes de `_tick_weather` en cuanto `run_active` cae, así que un clima vivo **nunca se para al terminar la partida**: el desplazamiento del HUD queda congelado, `price_discount` se queda en 0.5 y la fuente de puntos de la lluvia dorada sobrevive hasta el siguiente `RunState.reset()`. | **fixed** (58) |
| L2-4 | MEDIUM | `scripts/world/event_altar.gd:117` | El altar **fuerza** y reemplaza el clima activo; `CHANGELOG.md:57` y `docs/ARQUITECTURA.md:790` dicen que **rechaza**. El código lleva su razón escrita al lado: la deriva está en los documentos. | **fixed** (59, doc) |
| L2-5 | MEDIUM | `scripts/world/vendor.gd:153` | `_interact` abre un menú que pausa el árbol sin mirar `ui_blocking`, y `vendor_ui._close` despausa incondicionalmente: puede soltar una pausa que era del selector de cartas. | **fixed** (58) |
| L2-6 | LOW | `scripts/world/world_director.gd:352` | `_spawn_start_pet_boxes` tira `randf()` incondicionalmente, rompiendo la regla de cortocircuito que sus dos vecinas explican textualmente. | **fixed** (59) |
| L2-7 | LOW | `scripts/world/world_director.gd:418` | El último recurso de `_stage_parent()` (`return self`) cuelga un spawn de etapa del director persistente, invisible para el barrido. | deferred: la ventana (`_arena == null` con el director procesando) está cerrada por `set_physics_process(false)` en `on_stage_ended`; devolver `null` ahí necesita revisar cada llamador |
| L2-8 | LOW | `scripts/world/world_director.gd:1602` | Una lluvia de meteoros que termina por duración descarta los impactos pendientes. | deferred: resolver los impactos pendientes al parar cambia lo que hace un desastre, que es una decisión de diseño de la iteración 55 |
| L2-9 | LOW | `scripts/world/world_director.gd:1045` | `_despawn_chest` construye el tween de hundimiento en el **director**, no en el cofre. | **fixed** (59) |
| L2-10 | LOW | `scripts/world/run_root.gd:267` | El campo `beacons=` del barrido es estructuralmente siempre 0: `on_stage_ended` ya vació `_beacons` en el paso 3. | **fixed** (59) — y el campo pasó a ser real: `on_stage_ended` ahora LIBERA los nodos de baliza en vez de solo vaciar la lista |
| L2-11 | LOW | `scripts/world/vendor.gd:154` | Un puesto en `retry_cooldown` sigue `available` y con su prompt puesto mientras ignora cada pulsación. | **fixed** (58) |
| L2-12 | LOW | `scripts/world/curse_shrine.gd:214` | Comentario obsoleto («sin consumidor hasta la parte C»). | **fixed** (59, doc) |
| L2-13 | LOW | `scenes/tests/arena_probe.gd:27` | Lista `BONK_POI_NOW` de la cabecera incompleta. | **fixed** (57) |
| L2-14 | LOW | `scripts/world/world_director.gd:1144`, `:1305`, `docs/ARQUITECTURA.md:769` | Tres textos dicen que el tick del tsunami «termina solo»; lo termina su duración. | deferred: comentarios; el comportamiento documentado y el real coinciden en lo que importa (la duración termina la fila) |

### Carril 3 — enemigos, spawner, posesión, pools, FX

| Id | Sev | Dónde | Qué | Estado |
|---|---|---|---|---|
| L3-1 | HIGH | `scripts/systems/enemy_spawner.gd:652` | `_freeze_new_bodies` recorre solo `enemies` y `boss`, pero un Duneburrower **enterrado** ya salió de `enemies` (`duneburrower.gd:107`) y no entra en ningún otro grupo: Tiempo detenido no lo congela nunca. Sigue moviéndose y su `_erupt` golpea a la party dentro de la ventana cuya promesa entera es «nada te toca» — y, al no estar en `_frozen`, `frozen_bodies()` tampoco puede delatarlo. | **fixed** en el código (58); **prueba incompleta** — ver «Las tres aserciones de los HIGH» |
| L3-2 | MEDIUM | `scripts/systems/power_ups.gd:169` | `time_stop` se empuja una sola vez desde `_apply_row` y no está en `_sync()`: un cambio de etapa deja caer una congelación viva (el spawner nuevo nace con `_freeze_left = 0`) mientras la casilla del HUD sigue contando. | **fixed** (58) |
| L3-3 | MEDIUM | `scripts/enemies/enemy_base.gd:292` | `_tint_possessed()` escribe `mesh.material_overlay` directo en vez de tomar una ranura: `Juice.flash` restaura `current_overlay()` (nulo), así que el primer golpe borra el tinte morado del sirviente para siempre. | **fixed** (58) |
| L3-4 | MEDIUM | `scripts/enemies/enemy_base.gd:336` | `_tick_climb` limpia `_climbing` solo al tocar suelo: un cuerpo que pierde contacto conserva la bandera mientras cae, y con ella `_clamp_solver_launch` sale antes de tiempo **y** el detector de vuelo del harness lo exime. | deferred: tocar `_climbing` mueve a la vez la pinza del solver y una de las dos exenciones del detector de vuelo; sin un caso reproducible el riesgo supera al hallazgo |
| L3-5 | MEDIUM | `scripts/enemies/enemy_base.gd:781` | `_on_died` de un sirviente no lo saca de `POSSESSED_GROUP`: los cadáveres cuentan contra `max_possessed` durante 0.3 s y pueden provocar un `Possessed expired:` falso. | **fixed** (58) |
| L3-6 | LOW | `scripts/systems/enemy_spawner.gd:877` | `spawn_at_points` quedó insertada **dentro** del bloque de documentación de `spawn_pressure_burst`; el de `elite_chance()` quedó huérfano 170 líneas más arriba. | deferred: bloques de documentación mal colocados, sin efecto en ejecución |
| L3-7 | LOW | `scripts/systems/enemy_spawner.gd:865` | `spawn_minions()` no tiene ningún llamador: `Rotking._resolve_summon` sigue instanciando a mano y saltándose `_make_enemy_at`. **Anterior a la ronda** (viene de antes de `main`). | deferred: anterior a la ronda (ver Seguimiento) |
| L3-8 | LOW | `scripts/weapons/necro_staff.gd:184` | `possessed_count()` es código muerto y su docstring describe mal lo que imprime el harness; en co-op el `possessed=a/b` compara los sirvientes de toda la party contra el tope de un solo portador. | **fixed** (58, mitad del harness) |
| L3-9 | LOW | `scripts/weapons/necro_staff.gd:176` | `while mine.size() >= max_possessed` no termina si `max_possessed` llegara a 0 o menos, y las tablas de evolución escriben propiedades por nombre. | **fixed** (58) |
| L3-10 | LOW | `scripts/systems/powerup_pickup.gd:82` | `_ground_y` se captura en `_ready`, antes de que el spawn ponga la posición. | **fixed** (58) |

### Carril 4 — jugador, stats, objetos, power-ups, mascotas, armas

| Id | Sev | Dónde | Qué | Estado |
|---|---|---|---|---|
| L4-1 | HIGH | `scripts/systems/item_bag.gd:291` | `_start_aura` pone `SAIYAN_TAG` en sus tres boons pero **nunca llama a `clear_timed_boons(SAIYAN_TAG)`**, así que un re-disparo dentro de los 12 s **apila** un segundo aura en vez de reemplazarlo y la primera expiración se lleva solo la mitad. Es exactamente lo que su propio comentario (`item_bag.gd:288`), el docstring de `add_timed_boon` y el CHANGELOG 56 dicen que está prevenido. `PowerUps._apply_row` es el único sitio del proyecto que lo hace bien. | **fixed** (58), aserción `Saiyan boons: max=9 of 3` → `max=3 of 3` |
| L4-2 | MEDIUM | `scripts/world/world_director.gd:1364` | (mismo defecto que L2-1, visto desde el otro lado: los boons de luna llena no llevan tag y no cubren a los caídos). | **fixed** (59) con L2-1 |
| L4-3 | MEDIUM | `scripts/weapons/necro_staff.gd:108` | `_tick_bolts` re-comprueba el objetivo sin mirar su pertenencia a `enemies`: un proyectil en vuelo sigue persiguiendo a un cuerpo que ya es sirviente y lo daña, rompiendo la regla 56 de que un sirviente queda oculto a las armas del jugador. | **fixed** (58) |
| L4-4 | MEDIUM | `scripts/weapons/slime_trail.gd:128`, `scripts/weapons/blood_vial.gd:233` | Las **visuales** de los charcos pasaron a ser de etapa (`RunRoot.stage_parent`), pero los **registros** viven en el arma, que sobrevive al cruce: tras cambiar de mapa `_pulse` sigue dañando en las coordenadas de la arena anterior, sin nada en pantalla. | **fixed** (58) |
| L4-5 | LOW | `scripts/weapons/necro_staff.gd:75` | `create_timer(delay, false)` sin `process_in_physics`, al revés que las siete armas hermanas de la misma ronda. | **fixed** (58) |
| L4-6 | LOW | `scripts/player/player.gd:151` | `set_pet` busca la mascota saliente por nombre; `queue_free()` la deja como hija hasta el final del frame, así que un segundo `set_pet` en el mismo frame hace que `add_child` renombre a la nueva y nadie vuelva a encontrarla. | **fixed** (59) |
| L4-7 | LOW | `scripts/player/player.gd:868` | `_clear_weapon_fields()` es un no-op silencioso: **ninguna** arma implementa `clear_weapon_fields()`. | **fixed** (58, con L4-4) |
| L4-8 | LOW | `scenes/tests/arena_probe.gd:900` | `_watch_airborne` recorre solo `enemies`, y la iteración 56 sacó de ahí a los sirvientes: hasta `max_possessed` cuerpos por portador quedan fuera de un detector que «no se puede ajustar hasta callarlo». | **fixed** (58) |
| L4-9 | LOW | `scripts/systems/item_catalog.gd:105` | La descripción del cinturón promete «3 enemigos»; `zap_chain` hace `base_bounces + copies + 1` = 4 con una copia. | **fixed** (59) |
| L4-10 | LOW | `scripts/systems/item_bag.gd:306` | `_apply_aura_shell(true)` añade a `_aura_overlays` sin vaciarlo antes. | **fixed** (58) |
| L4-11 | LOW | `scenes/tests/arena_probe.gd:729` | `_tick_zenkai_test` escribe `health.invulnerable`, un estado que pertenece a `PowerUps._sync`. | **fixed** (58) |
| L4-12 | LOW | `scripts/player/player.gd:844` | `_set_downed(true)` apaga solo `weapons_mount`: la mascota de un raider derribado sigue disparando, contra lo que dice el comentario del propio bloque. | deferred: parar la mascota de un caído es una **decisión de diseño** (el comentario del bloque la implica, pero nada la escribió); queda para el usuario |

### Carril 5 — UI, HUD, mapa, feel

| Id | Sev | Dónde | Qué | Estado |
|---|---|---|---|---|
| L5-1 | MEDIUM | `scripts/ui/hud.gd:68` | El minimapa se ancla **encima** del grupo superior derecho del propio HUD: `MINIMAP_SOLO_TOP` 46 + margen 14 deja el mapa de 150 px en y 60..210, tapando la insignia de FPS y dos tercios de `%PointsLabel`; en co-op el `top` es 14 y también tapa `%KillsLabel`. Contradice `hud.gd:66-68` y `docs/ARQUITECTURA.md:501` («bajo la insignia de FPS»). | deferred: geométrico pero solo visible al renderizar, que esta auditoría no verifica |
| L5-2 | MEDIUM | `scripts/ui/upgrade_card_ui.gd:292` | `_roll()` muestra solo `_cards.size()` (3) opciones y descarta el resto **en silencio**: el pozo del bloque de la suerte ofrece 3 objetos + la carta «Nada», así que un raider con tres o más objetos pierde la opción de negarse. | **fixed** (58) |
| L5-3 | MEDIUM | `scripts/ui/vendor_ui.gd:465`, `scripts/ui/roulette_ui.gd:291` | `_close()` es la única liberación de la pausa y es incondicional, sin hook en `_exit_tree`/`NOTIFICATION_PREDELETE`; `upgrade_card_ui.gd:532` sí se guarda. | **fixed** (58) |
| L5-4 | LOW | `scripts/ui/vendor_ui.gd:410`, `:455` | `_on_buy` y `_first_affordable` leen `_player` sin comprobar validez. | **fixed** (58) |
| L5-5 | LOW | `scripts/systems/juice.gd:232` | `_rest_camera` sale por invalidez **antes** de `_shake_rest.erase()`; `_fov_kicks` tiene la misma forma: una cámara liberada a media sacudida deja una entrada permanente en el autoload. | **fixed** (58) |
| L5-6 | LOW | `scripts/ui/hud.gd:554` | `_refresh_mate_powerups()` queda detrás del `return` temprano de `_refresh_powerups()`. | **fixed** (58) |
| L5-7 | LOW | `scripts/ui/vendor_ui.gd:109`, `scripts/ui/roulette_ui.gd:72` | `is_blocking()` devuelve `true` durante el frame posterior a su `queue_free()`. | **fixed** (58) |
| L5-8 | LOW | `scripts/ui/map_draw.gd:95` y `docs/ARQUITECTURA.md:436`, `:457` | «0.5 da 240 px para una arena de 240 m» es el doble de lo real (120 px); y 121x121 contra los 120 de `fog_of_war.gd`. | **fixed** (59, doc) |
| L5-9 | LOW | `docs/ARQUITECTURA.md:492` | Sigue diciendo que `lucky_block` queda reservado para la parte C2; tanto él como `event_altar` ya enviaron. | **fixed** (59, doc) |

### Carril 6 — cadenas, documentación y datos

| Id | Sev | Dónde | Qué | Estado |
|---|---|---|---|---|
| L6-1 | HIGH | `docs/ARQUITECTURA.md:297` | Mismo hallazgo sembrado que L1-3, confirmado por los dos carriles. | **fixed** (59, doc) |
| L6-2 | HIGH | `docs/ARQUITECTURA.md:930` | El manantial se documenta como `heal_full` + `add_timed_boon` (30 s); `spring_shrine.gd:74-84` cura y llama a `PowerUps.apply(PowerUpCatalog.roll_id(true))`, y los power-ups duran 20 s. La iteración 53 borró ese canal de boons a propósito. | **fixed** (59, doc) |
| L6-3 | MEDIUM | `docs/ARQUITECTURA.md:951` | Nombra `show_tier_tag(tier)`; el hook real es `show_stage_tag(stage_index, lap)`, que el mismo documento cita bien en otras dos líneas. | **fixed** (59, doc) |
| L6-4 | MEDIUM | `docs/ARQUITECTURA.md:300` | Mismo hallazgo que L1-4. | **fixed** (59, doc) |
| L6-5 | MEDIUM | `README.md:3` | «13 raiders», «14 armas», «4 mascotas»; son 16, 15 y 9. | **fixed** (59, doc) |
| L6-6 | MEDIUM | `docs/GLOSARIO.md:592`, `:639` | La tabla «Interfaz» conserva `T%d → G%d` y `T2 → G2`, la insignia de grado que la regla 6 del mismo archivo declara muerta. | **fixed** (59, doc) |
| L6-7 | MEDIUM | `docs/GLOSARIO.md:29-44` | La tabla de personajes lista 13; el catálogo tiene 16. | **fixed** (59, doc) |
| L6-8 | MEDIUM | `docs/GLOSARIO.md:123-126`, `:139-142` | Cuatro filas de huevos de mascota que la iteración 54 borró del catálogo, y faltan los glifos de los tres objetos de la 56 (`CL`, `SS`, `ZK`), que la regla 19 exige. | **fixed** (59, doc) |
| L6-9 | MEDIUM | `scripts/ui/map_draw.gd:85-87` | La regla 21 pide plural para las familias sin tope: «Caja de mascotas», «Altar de eventos» y «Bloque de la suerte» van en singular y ninguna de las tres está capada. | **fixed** (59) |
| L6-10 | MEDIUM | `docs/GLOSARIO.md:21` | La regla 21 nombra tres paneles del mapa; `map_overlay.gd:134-138` construye cinco. | **fixed** (59, doc) |
| L6-11 | MEDIUM | `docs/ARQUITECTURA.md:1103` | El inventario de logs omitía siete prefijos de la ronda. | **fixed** (57) |
| L6-12 | MEDIUM | `docs/ARQUITECTURA.md:878` | «`EVOLUTION_LIBRARY`, 14 filas»; son 15 desde la iteración 56. | **fixed** (59, doc) |
| L6-13 | LOW | `scenes/tests/arena_probe.gd:28` | Mismo hallazgo que L2-13. | **fixed** (57) |
| L6-14 | LOW | `README.md:71` | «el manantial … da un power-up de 30 s»; duran 20 s (15 la estrella, que el manantial no puede sacar). | **fixed** (59, doc) |
| L6-15 | LOW | `tools/verificar.sh:100` | Un comentario decía que el RNG del juego se `randomize()`a, contra la cabecera del mismo archivo. | **fixed** (59, doc) |
| L6-16 | LOW | varios | Siete derivas menores más de README/GLOSARIO (puerta de cobertura a 240 s y no 360, una cadena documentada que no existe, el prompt de respaldo del vendedor, dos cadenas muertas del manantial, un marcador documentado que la cadena viva no tiene, huevos de mascota en cofres, «grados» entre las claves guardadas, «14 armas» en dos sitios más y «Varita de brasas» por «Vara de brasas» en el CHANGELOG). | **fixed** (59, doc) en README y GLOSARIO; las derivas de `CHANGELOG` histórico se dejan como están (un CHANGELOG es un registro, no un documento vivo) |

## Soaks de estrés (58.2)

Seis corridas sobre el harness ampliado, en serie y con un solo Godot vivo
a la vez. Logs en `$TMPDIR/bonkraiders-audit/stress_*.log`.

| Id | Qué | Resultado |
|---|---|---|
| (a) | cruce en modo NORMAL: 1200 s, sin `BONK_STAGE_FAST` | **S-1** (abajo): jefe abatido (`Stage boss slain: Rey Pútrido Ancestral at 672.4s`) y `Exit portal opened at 900.0s`, pero la party **no cruzó** y la niebla se quedó en 0.06. Tras arreglar S-1 la cobertura sube a **0.22** y aparece **S-4**, 57 `look_at() failed` que ningún soak anterior había alcanzado. Tras S-4 y S-5 **cruza**: `Stage advanced: 1 -> 2 (ash_dunes) at 912.7s`, 12.7 s después de abrirse el portal, con `explored=0.25` en la etapa 1. Conserva **un** warning de niebla, y la causa está medida: al cruzar, la niebla se reinicia, así que la lectura final (0.07) es la cobertura de la etapa 2 en los 259 s que le quedaron — la misma razón por la que el soak de `BONK_STAGE_FAST` está exento. **No se añadió una exención nueva**: la puerta tiene razón, lo raro es la configuración |
| (b) | tres corridas MORTALES (semillas 1, 2, 3), hasta 360 s | **limpias**: las tres terminan en `Run ended: defeat`, `Meta saved:` y `Probe: run ended victory=false`, sin `WEDGE` y sin un solo warning |
| (c) | todo a la vez: shiny, drops, tsunami, seis POIs, 900 puntos, tres objetos | 14 líneas de los sistemas nuevos (cinturón, aura, zenkai, desastre, vendedor, caja, altar de eventos, bloque). **Reprodujo L4-1**: once `Saiyan aura:`, dos de ellas a 290.8 s y 296.5 s — 5.7 s de diferencia dentro de una ventana de 12 s. Warning de niebla (0.07), misma causa que S-1 |
| (d) | barrido del bloque de la suerte: seis bloques, las seis recompensas forzadas | tras S-1/S-5: **las seis ramas** y **cero warnings** (niebla 0.11). Antes: cinco de las seis ramas (`enemy_explosion`, `gem_rain`, `points`, `free_chest`, `powerup`) entre los 105 s y los 182 s; el sexto bloque no se abrió dentro del reloj. Warning de niebla (0.07) |
| (e) | co-op + lluvia dorada + derribo forzado | **limpia**: `Player revived: p1 by p0`, `HUD offset: (0.0, 0.0)` y `Points sources: p0=1.00 p1=1.00` la trama en que la lluvia se apaga |
| (f) | co-op + traficante de animales + caja de mascotas | **limpia**: `Vendor sold: animals angry_bird 120` + `Vendor buyer: p0` + `Pet joined: angry_bird`, después `Pet box opened: magic_pumpkin`, y al final `Party pets: p0=magic_pumpkin p1=none` |

### Hallazgos de los soaks de estrés

| Id | Sev | Dónde | Qué | Estado |
|---|---|---|---|---|
| S-1 | HIGH | `scenes/tests/arena_probe.gd:_pick_waypoint` | El desvío a power-ups se evalúa **antes** que el rush de salida, así que una horda que suelta un power-up cada pocos segundos deja al recorrido dando vueltas dentro de una burbuja de 20 m para siempre. Medido en el soak (a): jefe abatido a los 672 s, `Exit portal opened at 900.0s`, y en los 300 s siguientes **54 power-ups soltados, 2 recogidos, ningún `Stage advanced:`** y `explored` clavado en 0.06 mientras el raider seguía abriendo cofres. El comentario del propio `_nearest_interactable` dice para qué existe el rush — «un recorrido que sigue de compras nunca cruza de etapa, y cruzar es lo que este harness tiene que probar» — y el desvío estaba delante de él sin que nadie lo dijera. Ningún soak lo había visto: es el primero sin `BONK_STAGE_FAST`. | **fixed** (58) |
| S-2 | MEDIUM | `scripts/ui/pause_menu.gd:_ready` | El menú de pausa **lee** el grupo `ui_blocking` desde que se escribió, pero nunca **entra** en él: la pausa que toma con Esc era invisible para todos los que preguntan al grupo, así que un puesto abierto sobre el menú devolvía el mundo al salir. Encontrado por el carril de arreglos de UI al escribir las guardas nuevas. | **fixed** (58) |
| S-3 | MEDIUM | `scripts/world/roulette_shrine.gd:_interact` | El mismo hueco que L2-5, en el hermano: abre la ruleta sobre cualquier capa que ya tenga la pausa, y a diferencia del puesto no tiene ni cooldown de reintento. | **fixed** (58) |
| S-4 | MEDIUM | `scripts/enemies/skirmisher.gd:78` | `_fire_bolt` normaliza `objetivo - proyectil` sin comprobar que no sea cero: un skirmisher empujado por la horda **encima** del raider dispara desde el punto exacto al que apunta, `normalized()` devuelve el vector cero y `look_at` recibe un origen igual a su destino. **57 `ERROR:` en un solo soak de 1200 s**, y el proyectil sale apuntando a donde lo dejó el pool. No lo vio ningún carril y no salía en ningún soak anterior: hizo falta que el recorrido arreglado (S-1) volviera a meterse en la horda para alcanzarlo. | **fixed** (58) |
| S-5 | MEDIUM | `scenes/tests/arena_probe.gd:_pick_waypoint` | Regresión del propio arreglo de S-1: la regla anti-burbuja que fuerza un paseo cada ocho tramos también lo forzaba **durante el rush de salida**, mandando al recorrido lejos del único objetivo que ese rush existe para alcanzar. Medido: un soak de etapa de 720 s que no cruzó ni una vez, con 16 de sus 22 tramos agotando el tiempo. | **fixed** (58) |


## Cómo se probó cada arreglo

Un `fixed` lleva su commit y **la línea de log o el comando que enseña el
bug ausente**. Para un HIGH confirmado solo por lectura de código, el
arreglo viaja con una **aserción** que se enseña **fallando en
`pre-audit`** y pasando en HEAD; el fallo citado es siempre el síntoma
propio del bug, nunca un símbolo que falta ni un error de parseo.

Las corridas de `pre-audit` se hacen en un worktree temporal
(`git worktree add "$TMPDIR/bonk-pre-audit" pre-audit`), con el harness
copiado de HEAD **más `scripts/world/lucky_block.gd`**, que es lo único que
el probe nombra y que no existe en `pre-audit` (`LuckyBlock.force_rewards`):
sin él el fallo citado sería un error de parseo y no probaría nada.

### Las tres aserciones de los HIGH

| Bug | Aserción | `pre-audit` | HEAD |
|---|---|---|---|
| **L1-1** cambio de etapa con un menú abierto | `BONK_SWAP_MENU=1 BONK_POI_NOW=vendor_items BONK_POINTS=4000` → `Swap menu: paused=%s` | `Swap menu: paused=true` (el árbol se queda pausado para siempre) | `Stage advanced: 1 -> 2 (ash_dunes) at 105.4s` + `Swap menu: paused=false` |
| **L4-1** aura sayayin apilada | `BONK_ITEM_NOW=saiyan_blood:5 BONK_POWERUP_BOOST=1` → `Saiyan boons: max=%d of 3` | `Saiyan boons: max=9 of 3` (tres auras a la vez) | `Saiyan boons: max=3 of 3`, con 15 disparos de aura |
| **L3-1** gusano enterrado dentro de un tiempo detenido | `BONK_POWERUP_NOW=time_stop BONK_POWERUP_AT=<s>` → `Time stop worms: sampled=%d moved=%d loose=%d` | **no se consiguió una corrida que falle** (ver abajo) | `loose=0` en todas las ventanas |

**L3-1, con honestidad.** El defecto es seguro por lectura de código:
`Duneburrower._burrow()` saca al cuerpo del grupo `enemies`
(`duneburrower.gd:107`) y `EnemySpawner._freeze_new_bodies` solo recorre
`enemies` y `boss`, así que un gusano enterrado nunca entra en el conjunto
congelado. La corrección está aplicada y la aserción está puesta y en cero
en HEAD — pero **no se logró producir la corrida de `pre-audit` que la haga
fallar**, y el motivo es del propio harness: `_tick_freeze` vuelve a
congelar cuerpos nuevos **cada frame**, así que con el `BONK_POWERUP_NOW`
re-concedido en cada expiración todos los gusanos quedan atrapados **en
superficie** y prácticamente nunca alcanzan el estado enterrado dentro de
una ventana. Se probó con la congelación arrancando a los 90, 120, 150, 180
y 210 s: `loose=0` en todas. Lo que sí se midió, con la congelación
retrasada a 150 s: `damage_events=1` en `pre-audit` contra `0` en HEAD
—exactamente el síntoma que describe el hallazgo, un enemigo golpeando
dentro de la ventana cuya promesa entera es que nada te toca— y
`Time stop worms: moved=139` contra `48`. Las dos corridas divergen frame a
frame, así que eso es **indicio, no una pareja controlada**. Se anota como
`fixed` en el código con la **prueba incompleta** dicha aquí, no como un
`fixed` probado.

## Seguimiento (fuera del alcance de esta auditoría)

- **L3-7** `spawn_minions()` sin llamador y `Rotking._resolve_summon`
  instanciando esbirros a mano, saltándose `_make_enemy_at` y con él el
  escalado por vuelta, por minuto tardío, por co-op y la tirada de shiny.
  Es **anterior a la ronda** (viene de antes de `main`), así que queda como
  seguimiento: la regla que rompe está escrita en su propio docstring, en
  el CHANGELOG 48 y en `docs/ARQUITECTURA.md:244`.
- El renderizado **no se verificó**: todo lo de aquí es headless. Un
  hallazgo cuyo síntoma solo se ve en pantalla (el minimapa sobre el
  grupo del HUD) se razona por sus constantes, no por una captura.

## Recuento

**80 hallazgos**: 68 `fixed`, 12 `deferred`, 0 `not-a-bug`. No hay filas
`not-a-bug` porque los seis carriles reportaron por separado lo que
**revisaron y encontraron sano** — no llegó a ser un hallazgo, así que no
llega a ser una fila. Lo despejado, en una línea cada bloque:

- **Carril 1**: `RunState.reset()` cubre las 28 variables del archivo, una
  por una (`price_discount`, `powerup_vendor_price`,
  `disaster_chance_bonus` y los seis campos de etapa incluidos); el clima
  no se filtra al cruzar (`on_stage_ended` corre el `stop()` de la fila
  viva antes de `_snap_sky_back()`); `Coop.configure` limpia las acciones
  de los cuatro slots antes de reconstruirlas; el literal de `Stage sweep:`
  coincide byte a byte con el que greppea `verificar.sh`; el fold de
  `SaveData` no escribe ceros y la API de grados no tiene ni un llamador;
  `RunManager.bind_player` es idempotente.
- **Carril 2**: `price_discount` lo leen los cuatro precios que deben
  leerlo y **no** los dos que no; la lluvia dorada cubre a los caídos y se
  limpia por tres caminos; los dieciséis `marker_kind` tienen fila de
  estilo; los sub-recursos de `Rock`/`DuneRock` no se mutan en runtime; una
  gema de la lluvia del bloque no hereda el `xp_value` de una fisura; la
  explosión y los meteoros aciertan a los jefes y no a los sirvientes.
- **Carril 3**: `EnemyBolt.launcher` y los temporizadores de `AcidPool`
  **sí** los limpia su `pool_reset`; el viaje de ida y vuelta del pool no
  deja nodos inertes; el orden de `release_all_live` frente a los padres
  liberados es correcto; las capas de shiny son por instancia; la lista de
  enemigos poseíbles es exactamente la que dice el CHANGELOG 56; la guarda
  de `_on_died` cubre todos los pagos.
- **Carril 4**: la re-entrada de `recompute` está cerrada; ninguna fila de
  catálogo se muta; las fuentes de puntos son un producto que se reemplaza
  por nombre; `PowerUps._sync` compone bien la estrella; los 16 raiders
  tienen arma y stat válidos; los glifos no se repiten.
- **Carril 5**: el desplazamiento del HUD siempre vuelve a cero; los
  minimapas no se filtran entre etapas; mapa y niebla miden lo mismo; la
  flecha de jefe aguanta un objetivo liberado; los precios del vendedor no
  se desincronizan de lo que cobra.
- **Carril 6**: **cero** desajustes reales de marcadores `%` en los 74
  `.gd` cambiados (el único candidato era un ternario con dos literales
  correctos); las reglas 1, 7, 9 y 17 del GLOSARIO se cumplen en cada
  cadena nueva; todos los grupos que nombra la tabla de ARQUITECTURA
  existen; las nueve filas de clima coinciden con el documento.

## Lo que NO se verificó

- **El renderizado.** Todo esto es headless. Un hallazgo cuyo síntoma solo
  se ve en pantalla se razona por sus constantes, no por una captura: L5-1
  (el minimapa anclado sobre la insignia de FPS y la etiqueta de puntos) se
  queda en `deferred` por eso, con los números escritos para que quien
  arranque el juego lo confirme en un segundo.
- **La prueba de `pre-audit` de L3-1**, dicha arriba con todo detalle.
- **Los mandos.** El co-op real reparte un control por slot; el harness
  pone a todos en el teclado, que es lo único que existe en headless.
- **El export en Windows y Linux**: las plantillas instaladas son las de
  macOS. El preset de macOS sí se ejerció y sale limpio.
