# Arquitectura — dónde tocar cada cosa

Mapa de referencia por sistema: qué hace, archivos clave y cómo extenderlo. Regla general del proyecto: **el contenido son filas de catálogo** (Dictionaries const en `scripts/systems/catalogs/`) + una escena; casi nunca hace falta código nuevo por pieza de contenido. Los sistemas se comunican por **señales y grupos**, nunca por rutas de nodos entre escenas.

> **¿Solo quieres cambiar un valor** (un color, un daño, un texto, un tiempo)? Empieza por `docs/CAMBIOS-RAPIDOS.md`: dice en qué archivo o escena > nodo vive cada valor y qué propiedad tocar. Este documento explica **cómo funciona** cada sistema. Las reglas para trabajar con Claude en este repo están en `CLAUDE.md`.

Dos documentos que este mapa da por leídos:

- **`docs/GLOSARIO.md` es la ley de la terminología.** El juego está íntegramente en español latinoamericano (es-419). Toda cadena visible por el jugador sale de esa tabla; si añades contenido, extiende el glosario en vez de improvisar un término. Lo que **nunca** se traduce: `id` de catálogo, `node_name`, nombres de grupo, `StringName` (`&"..."`), rutas `res://`, claves de `SaveData` y todo `print()`/`push_warning()` — los soaks y este documento dependen de ellos en inglés. Los comentarios del código y los tooltips `##` del Inspector sí van en español (ver «Convenciones»).
- **`tools/verificar.sh` es la puerta de salida.** Import limpio + lint de catálogos + harness de UI + soaks de las tres arenas, de etapa y de co-op. Ver «Verificación» al final.

## Vista general de una partida

`scenes/ui/CharacterSelect.tscn` (escena principal) escribe la elección en el autoload `GameConfig` (`selected_character_id`, más el modo diario) y carga **una sola escena**: `scenes/world/Run.tscn`. Ya no hay selector de mapa ni de grado — toda partida empieza en el Bosque Hueco y recorre la lista de mapas.

`Run.tscn` (raíz `run_root.gd`, `class_name RunRoot`, grupo `run_root`) tiene dos hijos: la instancia **única** de `scenes/world/RunSystems.tscn` — el bloque común: `Player`, `RunManager` (fin de partida y puerta de etapa), `WorldDirector` (layout y eventos; hijos `Weather` = `WeatherDirector` y `StageFixtures`), `UpgradeCardUI`, `HUD`, `RunEndScreen`, `PauseMenu`, `FogOfWar` — y `ArenaHost`, bajo el cual se instancia la arena de la etapa actual. Cada arena (`HollowWoods.tscn`, `AshDunes.tscn`, `Gloomfen.tscn`) es solo el mundo: entorno, luz, suelo, perímetro, verticalidad, interactuables de escena, scatter, `EnemySpawner` y `AmbientBed`. **Una arena ya no se puede arrancar sola** (F6 o `--quit-after` directo sobre el `.tscn`): sin raíz de partida no hay jugador, ni HUD, ni director.

`RunSystems._enter_tree()` llama `RunState.reset()`: el bloque de partida es el dueño del reinicio y entra al árbol **antes** de que `RunRoot._ready` construya la primera arena, así que el scatter y el director de cada etapa siempre ven un `RunState` limpio.

Ver «Partida por etapas» más abajo para el ciclo de vida completo y el contrato del cambio de mapa.

Autoloads (`project.godot`, en orden de carga): `RunState` (XP/nivel/kills/reloj/dificultad), `GameConfig`, `Coop` (entrada por slot), `SaveData` (meta persistente), `Juice` (game feel), `Sfx` (audio), `Settings` (aplica ajustes), `Pools` (object pooling), `ScreenFade` (fundidos y el ritual de salir de partida), `ControllerIcons` (addon de glifos de control). `Juice` y `Sfx` cargan **escenas** (`scenes/systems/Juice.tscn`, `scenes/systems/Sfx.tscn`), no scripts sueltos: su ajuste fino se edita en el Inspector de esas escenas.

### Grupos y hooks por grupo

El acoplamiento cruzado va siempre por aquí. Lista actual:

| Grupo                         | Quién está dentro                                                                                    | Qué se le llama                                                                                                                                   |
| ----------------------------- | ---------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `player`                      | raiders **en pie**                                                                                   | seek de enemigos, imanes, repartos                                                                                                                |
| `downed_players`              | raiders derribados (salen de `player` al caer)                                                       | repartos «a toda la party»                                                                                                                        |
| `enemies`, `boss`             | cuerpos vivos                                                                                        | targeting de armas, cupo del spawner                                                                                                              |
| `enemy_bolts`, `player_shots` | proyectiles en vuelo (`EnemyBolt.tscn` declara `enemy_bolts` en la escena)                           | limpieza, filtros de colisión; el diagnóstico `PerfProbe` del HUD cuenta `enemy_bolts`                                                                                           |
| `gems` / `health_orbs`        | pickups vivos (`XpGem.LIVE_GROUP`, `HealthOrb.LIVE_GROUP`)                                           | `vacuum()`, tope blando de orbes                                                                                                                  |
| `enemy_spawner`               | el spawner de la arena                                                                               | `spawn_pressure_burst`, `spawn_minions`, `set_sky_event`, `apply_temp_enemy_buff`, `freeze_enemies`                                               |
| `world_director`              | el director de `RunSystems`                                                                          | `start_sky_event(kind)`, `on_stage_started(arena)`, `on_stage_ended()`, `beacon_count()`                                                          |
| `run_manager`                 | el `RunManager`                                                                                      | `extract_run()`                                                                                                                                   |
| `run_systems`                 | la raíz del bloque                                                                                   | `vacuum_pickups()`, `place_party(origin)`                                                                                                         |
| `run_root`                    | la raíz de la partida (`Run.tscn`)                                                                   | `arena_root()`, `current_arena()`, `advance_stage()`                                                                                              |
| `arena_root`                  | la arena de la etapa viva                                                                            | la busca `RunRoot`; el scatter la usa para filtrar sus keepouts                                                                                   |
| `arena_bounds`                | el nodo de scatter de la arena                                                                       | `is_walkable`, `random_walkable_point`, extensión de arena                                                                                        |
| `hud`                         | el HUD                                                                                               | `announce(msg)`, `announce_major(msg)`, `show_loot(...)`, `show_stage_tag(stage, lap)`, `track_objective(node)`, `set_quake_offset(shift)`, `on_stage_started(arena)` (reenvía a minimapa y mapa). Son reenvíos al principio de `hud.gd` hacia sus componentes |
| `fog`                         | la niebla de guerra de la partida                                                                    | `reset_for_stage(arena)`, `reveal_at(xz)`, `is_explored(xz)`, `explored_fraction()`                                                               |
| `map_markers`                 | todo lo que sale en el mapa (raiders, jefes, interactuables con `marker_kind`)                       | `map_marker_kind()`, opcional `map_marker_color()`                                                                                                |
| `map_overlay`                 | los mapas de Tab vivos                                                                               | `marker_count()` (lo lee el harness)                                                                                                              |
| `powerup_pickups`             | power-ups en el suelo                                                                                | limpieza de etapa y `Stage sweep: pickups=`                                                                                                       |
| `enemy_projectiles`           | bolts enemigos en vuelo                                                                              | el flag `frozen` de Tiempo detenido                                                                                                               |
| `springs`                     | el manantial vivo (como máximo uno)                                                                  | el peso 0 de su fila de evento                                                                                                                    |
| `acid_pools`                  | charcos ácidos vivos (iteración 55)                                                                  | el tope y la separación de la lluvia radiactiva                                                                                                   |
| `possessed`                   | siervos del nigromante (iteración 56)                                                                | `Stage sweep: possessed=`, el cupo por portador y la limpieza de etapa                                                                            |
| `lucky_blocks`                | bloques de la suerte vivos                                                                           | limpieza de etapa                                                                                                                                 |
| `vendors`                     | los puestos vivos (máximo 2)                                                                         | el peso 0 de su fila y `Stage sweep: vendors=`                                                                                                    |
| `pet_boxes`                   | las cajas de mascotas vivas                                                                          | limpieza de etapa y `Stage sweep: boxes=`                                                                                                         |
| `boss_ui`                     | HUD + flecha de jefe                                                                                 | `track_boss(boss, title)`, `track_objective(node)`, `announce`                                                                                    |
| `upgrade_ui`                  | `UpgradeCardUI`                                                                                      | `open_bonus_pick(...)`, `open_choice(...)`                                                                                                        |
| `altars`                      | todo `ChargeShrine` vivo (de escena o del director)                                                  | el cupo de altares sin gastar del `WorldDirector`                                                                                                 |
| `ui_blocking`                 | toda UI que se adueña de la pausa (`BlockingUi.GROUP`)                                               | `is_blocking() -> bool`; `BlockingUi.any_open(tree)` / `other_open(...)` hacen la consulta                                                       |
| `blocking_ui_closable`        | UI bloqueante que acepta cierre por código (`BlockingUi.CLOSABLE_GROUP`): todo `ModalPanel` (ruleta y vendedor) | `dismiss()` — **llamado por `RunRoot._freeze_world`** (primer paso de `_swap_stage`) antes de tomar la pausa; las dos además se resuelven solas en headless |
| `feel_camera`                 | cámaras que Juice sacude (`Juice.FEEL_CAMERA_GROUP`)                                                 | shake / FOV kick en pantalla dividida                                                                                                             |
| `scatter_keepout`             | props y POIs colocados a mano                                                                        | el scatter no siembra encima                                                                                                                      |

## Clases base y helpers compartidos

Estas piezas existen para que un mismo cálculo no viva copiado en varios archivos (cada copia acaba con su propio bug). Antes de escribir un helper nuevo, mira si ya vive en uno de estos:

| Archivo                                         | `class_name`     | Qué unifica                                                                                                                                                                                                                                                                                                                                  |
| ----------------------------------------------- | ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `scripts/systems/catalogs/catalog_index.gd`     | `CatalogIndex`   | Índice `id -> fila` de los catálogos. `build(rows, campo)` y `values_where(...)`. Cada catálogo guarda su `static var` de índice y conserva su `by_id()` público.                                                                                                                                                                            |
| `scripts/systems/catalogs/rarity.gd`            | `Rarity`         | Las cuatro rarezas (`TIERS`: nombre-llave, color, peso, potencia), su traducción para pantalla (`display_name(id)`) y la tirada con suerte (`roll`, `resolve`, `_weights`). `UpgradePool.RARITIES` / `rarity_display` reenvían aquí.                                                                                                        |
| `scripts/systems/catalogs/weapon_catalog.gd`    | `WeaponCatalog`  | `WEAPON_LIBRARY` y sus accesores `by_id`, `by_node`, `id_for_node`, `display_name_for_node` (los `UpgradePool.weapon_*` reenvían aquí).                                                                                                                                                                                                       |
| `scripts/systems/catalogs/autoload_lookup.gd`   | `AutoloadLookup` | `find(nombre)`: el helper que comparten los catálogos `static` para llegar a un autoload, en vez de repetir `Engine.get_main_loop()`.                                                                                                                                                                                                                                                                      |
| `scripts/systems/row_text.gd`                   | `RowText`        | Rellena los `%d` de una descripción con los números de su propia fila (`text_values`), así el texto y el efecto no se separan.                                                                                                                                                                                                              |
| `scripts/systems/pickups/magnet_pickup.gd`      | `MagnetPickup`   | Chasis de los pickups tirados (`XpGem`, `HealthOrb`): idle con giro/bob, homing acelerado al raider en pie más cercano (radio × `RunState.pickup_radius_multiplier`), captura por proximidad y caducidad. La subclase aporta `LIVE_GROUP`, qué hace recolectar y el adorno propio.                                                          |
| `scripts/ui/meta/meta_screen.gd`                | `MetaScreen`     | Chasis de las tres pantallas entre partidas (Registro de misiones, Armería, Colección): fondo, insignia, botón Volver, entrada escalonada y el conteo de esquirlas. Contrato de escena: `%BadgeLabel`, `%List`, `%BackButton` (el título vive entero en la escena). Hooks: `_tracks_shards()`, `_build_rows(list)`; momentos compartidos: `payoff()`, `reject()`, `rebuild()`. |
| `scripts/ui/card_factory.gd`                    | `CardFactory`    | Dos constructores sin estado, `label(...)` y `card_box(card)`, para las cartas que se arman en código (las ofertas del vendedor). Los colores siguen viniendo de `UiTheme`.                                                                                                                                                                |
| `scripts/ui/ui_layers.gd`                       | `UiLayers`       | El orden de dibujo de las `CanvasLayer` que se crean en código (viñeta de Juice 4, mapa de Tab 8, fundido 100). Las capas de escena (HUD 5, cartas 10, modales 15, fin 20, pausa 30) guardan su número en la raíz de su `.tscn`.                                                                                                              |
| `scripts/ui/scene_paths.gd`                     | `ScenePaths`     | Las rutas de las escenas entre las que navega la UI (selector, Registro, Colección, Armería, `Run.tscn`).                                                                                                                                                                                                                                   |
| `scripts/ui/game/modal/blocking_ui.gd`          | `BlockingUi`     | El contrato de pausa: los grupos `ui_blocking` / `blocking_ui_closable` y las consultas `any_open(tree)` / `other_open(tree, yo)`.                                                                                                                                                                                                          |
| `scripts/ui/game/modal/modal_panel.gd`          | `ModalPanel`     | Chasis de los paneles que pausan la partida desde el mundo (vendedor, ruleta): toma y devuelve la pausa, se cierra si el comprador o el puesto desaparecen, `dismiss()` y el juego solo en headless. Escena base `scenes/ui/modal/ModalPanel.tscn`.                                                                                       |
| `scripts/fx/fx_mesh.gd`                         | `FxMesh`         | `strip(vertices, colors)`: la tira de triángulos que comparten el arco de tajo y el latigazo.                                                                                                                                                                                                                                              |

Helpers de las clases base (ver cada sección):

- `WeaponBase`: barridos de área (`enemies_in_disc/sphere/lane/arc`), `damage_all`, `spawn_fx_mesh`, helpers de aim y las andanadas del Tomo de Multitud (`fire_volley`, `fire_volley_retarget`, `volley_step`). `FieldWeapon` (`scripts/weapons/field_weapon.gd`) es la base de los campos centrados en el portador (Aura, Hedor).
- `EnemyBase`: `damage_players_in_disc/discs` (AoE consciente de la party), `spawn_chest`, `current_overlay`. Sus partes viven en `scripts/enemies/enemy/` (ver «Añadir un enemigo»).
- `BossBase`: `_clamp_to_arena`, `_safe_arena_point`, `_play_boss_entrance` / `_tick_entrance` / `_play_entrance`, `_consume_thresholds`, `_resolve_ground_hit`, `_spawn_spike_cluster`, un único slot de tween de telégrafo (`_play_cue`/`_begin_cue`/`_kill_cue`).
- `Interactable`: `live_players_in_range()`, `nearest_live_player()`, `best_kind_count_in_range(kind)`, `sink_away(keep_alive)` (hundirse y liberarse), `_hold_loop`/`_drop_loop`.
- `Juice`: `damp()` (suavizado independiente del framerate) y el registro `feel_camera`.

## Añadir un arma nueva

- Qué es: nodos hijos del mount `Weapons` del Player que disparan solos por cooldown al enemigo más cercano del grupo `enemies`.
- Archivos: `scripts/weapons/weapon_base.gd` (clase `WeaponBase`), `scripts/systems/catalogs/weapon_catalog.gd` (`WeaponCatalog.WEAPON_LIBRARY`, 15 armas), `scenes/weapons/`. Las cartas genéricas por arma (daño, velocidad de ataque, alcance, Temple, Ritmo de batalla) salen de `UpgradePool.WEAPON_STAT_CARDS`.
- Contrato `WeaponBase`: exporta `damage/cooldown/attack_range/projectile_count/cooldown_scale`; la subclase sobreescribe `fire(target)` y canaliza **todo** golpe por `deal_damage(target_health)` (aplica multiplicador global, crit, lifesteal y los hooks de objetos del portador). Helpers de stats: `effective_damage()`, `effective_cooldown()`, `area_scale()` (radios/arcos, no `attack_range`), `effective_projectile_count()`, `duration_scale()`, `targeting_range()`.
- **Barridos de área compartidos**: `enemies_in_disc(centro, radio, ventana_y)`, `enemies_in_sphere(centro, radio)`, `enemies_in_lane(origen, dir, largo, ancho)`, `enemies_in_arc(centro, dir, alcance, ángulo)` y `damage_all(bodies)`. Si tu arma golpea una forma, **úsala desde aquí** en vez de escribir un `get_nodes_in_group("enemies")` nuevo. Los helpers de aim (`aim_dir_or`, `flat_dir_or`, `safe_up`) son estáticos y cubren los casos degenerados (vector nulo, dirección colineal con Y).
- Visual efímero: `spawn_fx_mesh(mesh)` construye el `MeshInstance3D` en la raíz de escena con la configuración correcta. La malla y el material de cada efecto viven **en la escena del arma** (exports como `beam_mesh` o `puddle_mesh`), no se construyen en código: para cambiar cómo se ve un ataque se edita su escena en `scenes/weapons/`. Los FX pooled (`scenes/fx/`) son dueños de su propio look, y el rayo del Pararrayos y del Cinturón eléctrico es una sola escena, `scenes/fx/LightningBeam.tscn` (`LightningBeam.play(desde, hasta, estilo)`, un estilo por arma).
- Números de daño: el arma (vía `Health`) solo dice **qué pasó** — `DamagePopup.show_hit(kind, posición, cantidad)` con `kind` ∈ `DAMAGE`, `CRIT`, `DODGE` —; colores, tamaños de letra, texto de esquiva y movimiento son exports de `scripts/fx/damage_popup.gd` y se editan en `scenes/fx/DamagePopup.tscn`.
- Pasos: (1) script `extends WeaponBase` + escena en `scenes/weapons/` (mira `shortsword.gd` melee, `dart_pistol.gd` proyectil, `ember_wand.gd` área); (2) una fila en `WeaponCatalog.WEAPON_LIBRARY` con `id`, `display_name` (**en español**, glosario «Armas»), `node_name` (== nombre de nodo al instanciarse **y** nombre del archivo de `scene`, **en inglés**), `glyph`, `scene`, `flavor` y opcionalmente `extra_entries`. `id` y `node_name` son llaves (la cabecera del catálogo dice quién las lee): no se renombran. Con eso ya aparece como carta de arma nueva y genera sus cartas de daño/velocidad de ataque/alcance automáticamente.
- `WEAPON_LIBRARY` está indexada por `id` y por `node_name` (`CatalogIndex`) para el HUD y el banner de evolución: no hagas un bucle lineal nuevo, usa `WeaponCatalog.by_id` / `by_node`.
- Si dispara proyectiles: el proyectil es su propia escena con `pool_reset()`, se lanza con `Pools.acquire_scene(...)` y se registra con **una fila** en `Pools.POOLS` (ver Pools abajo). Ejemplo completo: `dart_pistol.gd` + `projectile.gd`.
- Armas sin objetivo: un arma que actúa sola (Rastro de baba) sobreescribe `_physics_process` y devuelve `null` en `acquire_target()`; las de área alrededor del portador (Aura, Hedor) extienden `FieldWeapon`, cuyo `reach()` (`attack_range * area_scale()` más el bono de Multitud) es a la vez el radio de daño, el del visual y el que decide cuándo pulsar.
- Al caer un raider (co-op), el Player avisa a sus armas **antes** de congelar el mount: un arma que deja objetos en el mundo (charcos) tiene que limpiarlos ahí, o quedan huérfanos.

### Multitud por arma

`Tomo de Multitud` (stat `projectiles`) llega a **todas** las armas: cada script lee `effective_projectile_count()` en su ruta de ataque (`fire()`, o `_physics_process` en las que atacan desde ahí). Qué hace el conteo extra depende de la forma del arma — un arma de ataque único no puede sacar dos golpes en el mismo sitio y el mismo frame, y un campo persistente no puede duplicar su anillo sin duplicar el daño en silencio:

| Arma               | Forma                    | Qué hace el conteo extra                                                     |
| ------------------ | ------------------------ | ---------------------------------------------------------------------------- |
| Pistola de dardos  | proyectil                | más dardos por andanada (abanico), como siempre                              |
| Arco de caza       | proyectil                | más flechas por andanada (abanico), como siempre                             |
| Orbes espirituales | órbita                   | más orbes en el anillo, como siempre                                         |
| Espada corta       | ataque único (arco)      | un arco completo más por extra, escalonado y abanicado                       |
| Dagas gemelas      | ataque único (estocada)  | estocadas extra escalonadas; cada una re-adquiere objetivo                   |
| Látigo de espinas  | ataque único (carril)    | latigazos extra escalonados y abanicados, cada uno su carril                 |
| Kamehameha         | ataque único (rayo)      | rayos extra escalonados y abanicados; un rugido por andanada                 |
| Pararrayos         | ataque único (cadena)    | descargas extra escalonadas, cada una con su propia bifurcación              |
| Bumerán            | proyectil (ataque único) | hojas extra lanzadas una tras otra y abanicadas                              |
| Vial de sangre     | ataque único (frasco)    | frascos extra escalonados, impacto rotado **alrededor del lanzador**         |
| Vara de brasas     | ataque único (estallido) | detonaciones extra escalonadas, cada una re-adquiere su centro               |
| Aura               | campo persistente        | **no** añade anillos: +12% de radio y −8% de intervalo por extra (suelo 60%) |
| Hedor              | campo persistente        | igual que Aura: +12% de radio y −8% de intervalo por extra (suelo 60%)       |
| Rastro de baba     | charco                   | un charco más por gota, en anillo a 1.2 radios del punto de caída            |
| Báculo de nigromante | proyectil (ataque único) | rayos extra escalonados; cada uno re-adquiere objetivo                     |

Reglas que comparten las de ataque único, todas en `WeaponBase`: `fire_volley(count, dir, disparo, escalón, abanico)` (abanico) y `fire_volley_retarget(...)` (cada extra elige su blanco) lanzan la andanada; el escalón de cada arma es un export suyo y `volley_step()` lo recorta para que **toda la cadena quepa en `VOLLEY_WINDOW` (60%) del `effective_cooldown()`**; los disparos diferidos usan `get_tree().create_timer(delay, false, true)` (pausable y en paso de física) y se descartan si el arma ya no está en el árbol, porque un arma se libera con su raider. Todo golpe sigue pasando por `deal_damage()`. Aura y Hedor reciben Multitud por los exports `radius_per_extra`, `pulse_per_extra` y `min_pulse_scale` de `FieldWeapon`.

## Mascotas

**Una sola mascota por jugador.** El slot vive en el nodo `PetSlot` del
Player (`scripts/player/components/pet_slot.gd`); `Player.pet_id` lo lee y
`Player.set_pet(id)` reenvía a `PetSlot.set_pet`, el único que lo mueve: libera la mascota
anterior, instancia la nueva, anuncia las dos mitades del cambio por el
toast de botín, imprime `Pet joined:` y pide un `recompute()`.

**No hay copias.** Dar dos veces la misma mascota no hace nada, y por eso
**cada fila declara arma y estadística**: una mascota es un paquete
entero, y una fila a medias convertiría un cambio en una pérdida que el
jugador no puede deshacer.

- **De dónde salen**: solo de la **caja de mascotas** y del **traficante de
  animales**. Los cofres y la ruleta no dan mascotas (no existe un kind
  `pet` en `ITEM_LIBRARY`): una compañera que llega sin que la pidas es una
  compañera que tira la que elegiste.
- **El arma** se instancia bajo la mascota (`Pet._build_weapon`), queda
  **fuera del tope de armas** (`Player.max_weapons`) y del pool de mejoras, lee las
  estadísticas del raider (Multitud, daño, velocidad de ataque) porque el
  `carrier_player()` del arma sube hasta él, y **nunca** toca
  `used_weapon_<id>`: los dos únicos sitios que suben ese contador
  (`Player._apply_character` y la concesión de `upgrade_pool.gd`) son
  inalcanzables desde aquí, así que la Colección no desbloquea un arma que
  nadie llevó.
- **La estadística** la aplica `PlayerStats._apply_pet_stat()` leyendo
  `Player.pet_id`: `amount_per_level × RunState.level`.
- Las nueve filas tienen **arma distinta y estadística distinta**, y su
  `stat_label` lo imprimen todas las cartas de la caja y del traficante:
  un cambio irreversible nunca debe ser una adivinanza.

| id              | Nombre          | Arma               | Estadística         |
| --------------- | --------------- | ------------------ | ------------------- |
| `alien`         | Alienígena      | Varita de brasas   | suerte              |
| `dinosaur`      | Dinosaurio      | Espada corta       | HP máx.             |
| `angry_bird`    | Pájaro furioso  | Pistola de dardos  | prob. de crítico    |
| `capybara`      | Capibara        | Pararrayos         | velocidad de ataque |
| `doki`          | Doki            | Bumerán            | ganancia de XP      |
| `pony`          | Pony            | Arco de caza       | velocidad           |
| `cj7`           | Cj7             | Aura               | robo de vida        |
| `magic_pumpkin` | Calabaza mágica | Látigo de espinas  | espinas             |
| `pokemon`       | Pokemon         | Orbes espirituales | daño                |

### Caja de mascotas

`scripts/world/interactables/pet_box.gd` (`PetBox extends Interactable`, escena
`scenes/world/PetBox.tscn`, grupo `pet_boxes`, `marker_kind` `&"pet_box"`).
**Gratis**: el traficante vende una _elección_ de tres por puntos; la caja
es la versión que te encuentras, y su precio es haber caminado hasta ella.

Tira una mascota distinta de la que llevas. Sin mascota, la da directo;
con mascota **pregunta** por `UpgradeCardUI.open_choice`, con
**«Cambiar por %s» como opción 0** — el harness siempre pulsa la primera,
así que la rama interesante tiene que ser la que ejercita. Log
`Pet box opened:`, **antes** del `Pet joined:` que imprime `set_pet`.

La siembra el `WorldDirector`: fila `pet_box` (peso 0.35) de `EVENT_LIBRARY`, y
0-1 al empezar la etapa (`StageFixtures.start_pet_box_chance`, nodo
`RunSystems.tscn > WorldDirector > StageFixtures`). La caja, la tapa y la
huella son nodos de `PetBox.tscn`; `paw_color` las tiñe y sus textos son
exports del grupo «Textos».

## Vendedores

`scripts/world/interactables/vendor.gd` (`Vendor extends Interactable`, grupo `vendors`,
`marker_kind` `&"vendor"`), tres kinds en una tabla `VENDOR_LIBRARY`.

**El puesto es dueño de la ECONOMÍA y del estante** (qué ofrece, qué cobra,
qué entrega, el log y la regla de una sola venta); **`scripts/ui/game/vendor_ui.gd`
(`VendorUi`, escena `scenes/ui/modal/VendorPanel.tscn`) solo dibuja** las
ofertas que recibe y le pasa el clic a `Vendor.buy`. Un kind nuevo es una fila
en `VENDOR_LIBRARY`, una rama en `Vendor.roll_offers()` con su función
`_<kind>_offers()` y una rama en `Vendor.buy`. El puesto (mostrador, figura,
cartel y luz) son nodos de `scenes/world/Vendor.tscn`.

| kind       | Qué vende                                                            | Precio                                                                                    |
| ---------- | -------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| `animals`  | 3 mascotas ≠ la que llevas, con arma y estadística en la carta       | `pet_price` fijo (120)                                                                    |
| `powerups` | 1 power-up al azar, **nunca la estrella**                            | `RunState.powerup_vendor_price`, empieza en 100 y **×1.5 por compra**, a nivel de partida |
| `items`    | 4 objetos, cada uno con su rareza tirada con la suerte del comprador | `RunState.chest_price(rareza)`, y la venta cuenta como cofre abierto para la inflación    |

- **El kind se tira a escondidas.** El anuncio es «¡Llega un vendedor!» y
  la baliza no lo dice: caminar hasta allá para averiguar cuál es **es** el
  evento. El marcador del mapa sí lleva el color del puesto, pero está
  bajo niebla como todo POI, así que tampoco lo adelanta.
- **Se va después de UNA venta**; si el menú se cierra sin comprar, el
  puesto **se queda** pero ignora `interact` durante `retry_cooldown` 20 s
  — el harness re-dispara interactuar cada 0.75 s mientras espera, y sin
  eso el menú se reabriría en el frame siguiente para siempre.
- **Máximo 2 vivos**: la fila `vendor` de `EVENT_LIBRARY` lleva `cap_group`
  `vendors` y `cap` 2, el mismo canal de peso 0 que usa el manantial.
- `VendorUi` y `RouletteUi` extienden `ModalPanel` (`scripts/ui/game/modal/modal_panel.gd`,
  escena base `scenes/ui/modal/ModalPanel.tscn`): `CanvasLayer` en
  la capa 15 (raíz de `ModalPanel.tscn`), `PROCESS_MODE_ALWAYS`, grupos `ui_blocking` +
  `blocking_ui_closable`, pausa el árbol y **siempre** la devuelve, se cierra
  sola si el comprador o el puesto desaparecen, y en headless **se juega
  sola**: compra la primera oferta que puede pagar o se va a los 3 s.
- Las ofertas se tiran **una vez**, en `Vendor.roll_offers()` al abrir el
  menú: el panel se redibuja tras cada clic, y un mostrador reconstruido en
  el redibujo cambiaría la mercancía bajo el cursor.
- Logs `Vendor arrived: <kind>` y `Vendor sold: <kind> <id> <precio>`, este
  **antes** de entregar, para que el soak lea causa y después efecto.

## Añadir un personaje

- Qué es: arma inicial + pasiva escalable + cuerpo (modelo cosmético), todo datos; el select y el spawn del Player leen la fila, no hay código por personaje.
- Archivos: `scripts/systems/catalogs/character_catalog.gd` (se editan las 12 filas de `CHARACTER_ROWS`; el juego lee `CHARACTER_LIBRARY`, que es esa lista con `weapon_scene` y `weapon_display_name` copiados de `WeaponCatalog` al cargar), consumidores: `scripts/player/player.gd` (`_apply_character`), `scripts/ui/meta/character_select.gd`, `scripts/systems/player_stats.gd`.
- Fila: `id`, `display_name` (los nombres propios **no se traducen**, glosario regla 5), `blurb`, `weapon_node_name` (**debe** coincidir con el `node_name` de `WeaponCatalog.WEAPON_LIBRARY` para que el pool la vea como poseída; la escena y el nombre del arma **no** se escriben en la fila), `passive_description`, `passive_stat` + `passive_amount`, `tint`.
- **El `id` es la llave del guardado** (desbloqueos, `runs_as_<id>`, `wins_as_<id>`, misiones): `snake_case` (lo exige el lint `id_format`) y no se renombra a la ligera. Si hay que renombrar uno, se añade la fila vieja → nueva a `SaveData.ID_ALIASES`: al cargar, un guardado viejo se traduce, imprime `Save migrated: <n> character id(s)`, se reescribe una vez y el archivo anterior queda como `.bak`.
- Cuerpo (opcional): sin campos de modelo el rig es la foca. `model_scene` = escena envoltorio (`assets/models/foca_character.tscn` — que carga la transformación propia, incluido el giro de 180° y la escala 0.6 de la foca) o un `.glb` crudo, que entonces necesita `model_scale` (multiplicador uniforme sobre la transformación de la escena). `tint_material_prefix` = prefijo del `resource_name` de los materiales que reciben el tinte (cada export nombra los suyos; la foca usa «Azul personaje»), porque `SealRig.apply_tint` nunca debe usarse para otra cosa (es el color de identidad, véase Sangre sayayin). La muerte levanta el cuerpo `death_lift` (0.55 por defecto, export del rig) — los cuerpos que no apoyen en 0.55 lo sobreescriben. Ejemplo de prefijo propio: Backyardigan usa `assets/models/tyrone_character.tscn` con «Placeholder personaje»; un `.glb` nuevo cuyo _root_ no mire a -Z necesita su giro en una escena envoltorio (el pipeline de `procedural motion` asume nariz a -Z).
- Los campos **obligatorios** se leen duro a propósito (una fila malformada revienta de inmediato); solo los opcionales usan `.get()` con default. No conviertas los primeros a `.get()`: convierte un error de datos en un personaje silenciosamente roto.
- `passive_kind` (opcional): `"per_level"` (defecto), `"speed_to_damage"` (Yandere-chan) o `"evasion_execute"` (ninguna fila lo usa hoy; sigue soportado por `PlayerStats`). `passive_base` = cantidad ya activa a nivel 1 (Doc). Ids de stat = los de `PlayerStats._apply_effect`.
- Desbloqueo: `unlock_cost` en esquirlas (0 = inicial). **Trampa**: toda fila con 0 es inicial y `load_from_disk` añade los iniciales a cada guardado que carga, así que poner 0 y después volver a ponerle precio **no** la vuelve a bloquear para quien ya jugó; opcional `unlock_boss` (id de minijefe secreto cuya muerte lo regala, resuelto por `SecretBossBase` vía `CharacterCatalog.by_unlock_boss`) + `unlock_hint`.
- El grid del selector deriva sus columnas del tamaño del catálogo y tiene scroll: añadir filas ya no descuadra la pantalla. Los textos de tarjeta se recortan con elipsis por número de líneas, no por medición — una pasiva mucho más larga que las actuales conviene mirarla en pantalla.

## Añadir un tomo

- Qué es: pasivas apilables sin techo de stacks (el tope es de tomos **distintos**, `Player.max_tomes`) que alimentan la capa de stats del jugador.
- Archivos: `scripts/systems/catalogs/tome.gd` (`TOME_LIBRARY`, 15 filas), aplicado por `scripts/systems/player_stats.gd`; las cartas las genera `upgrade_pool.gd` (`_tome_entries`).
- Fila: `id`, `display_name` («Tomo de X» / «Tomo del X», glosario), `description` (el `%d` se rellena con la cantidad del **primer** efecto), `effects: [{stat, amount}]`. Una fila nueva basta: el pool ofrece el siguiente stack automáticamente.
- Ojo con el nombre: la tira de equipamiento del HUD (`scripts/ui/game/hud/loadout_strip.gd`) recorta el prefijo para la sigla usando `LoadoutStrip.TOME_NAME_PREFIXES`, **ordenado del más largo al más corto** (`"Tomo del "` antes que `"Tomo de "`). Al revés, «Tomo del Azar» quedaría como «l Azar». Un prefijo nuevo se añade ahí respetando ese orden.
- Escalado: `amount` es el valor a potencia Común; la rareza de la carta lo multiplica (`potency` de `Rarity.TIERS`, en `scripts/systems/catalogs/rarity.gd`: Common 1.0 / Rare 1.5 / Epic 2.0 / Legendary 3.0). La `luck` del jugador inclina los pesos al tirar (`Rarity._weights`).
- Ids de stat de `_apply_effect`: `damage, cooldown, area, move_speed, crit_chance, crit_damage, lifesteal, evasion, armor, luck, thorns, max_hp, projectiles, duration, xp_gain, difficulty, gambling`. Ojo: el id `cooldown` sigue siendo enfriamiento por dentro, pero **se muestra como «velocidad de ataque» en positivo** (GLOSARIO regla 7) — no cambies la matemática al tocar una etiqueta. `difficulty` es **run-wide**: cada jugador publica su total con `RunState.set_difficulty_source("tomes_p<slot>")`.

## Añadir un enemigo

- Qué es: chasis compartido de horda (gravedad, seek + separación, giro, trepada, muerte con gema de XP) con hooks virtuales.
- Archivos: `scripts/enemies/enemy_base.gd` (`EnemyBase`), spawner: `scripts/systems/enemy_spawner.gd`, ejemplos: `grunt.gd` (melee), `skirmisher.gd` (a distancia), `tank.gd`, `sunspitter.gd` (láser), `duneburrower.gd` (emboscada).
- Partes del chasis en `scripts/enemies/enemy/` (todas `RefCounted`, sin nodo propio): `enemy_separation.gd` (`EnemySeparation`, la grilla de separación), `enemy_overlays.gd` (`EnemyOverlays`, el material superpuesto: shiny, variante, veneno, poseído), `enemy_status.gd` (`EnemyStatus`, lentitud y veneno), `enemy_possession.gd` (`EnemyPossession`, los siervos del nigromante), `enemy_loot.gd` (`EnemyLoot`: puntos, cofre de recompensa, charco ácido, drop de power-up) y `enemy_look_palette.gd` (`EnemyLookPalette`). **El look compartido de toda la horda** (colores y brillo shiny, tinte de veneno, brillo de poseído, animación de muerte) es un solo recurso: `assets/enemies/enemy_look.tres`, editable en el Inspector.
- Escena: raíz `CharacterBody3D` en grupo `enemies`, hijos `Health` (`scripts/systems/health.gd`), `Visual`, `CollisionShape3D`; exporta `xp_gem_scene`.
- Hooks a sobreescribir: `_behavior_tick(delta)` (cooldowns), `_movement_intent(seek, distance)` (a dónde ir), `_combat_tick(player, distance)` (atacar), `_facing_direction(...)` y **`_apply_elite_damage(mult)`** (multiplica los números de daño propios — lo llaman los shiny y `apply_tier_scaling(hp, dmg, xp)`).
- **AoE consciente de la party (iteración 45)**: un ataque de área telegrafiado se resuelve con `damage_players_in_disc(centro, radio, ventana_y, daño)` o `damage_players_in_discs(spots, radio, ventana_y, daño)`, **nunca** con «buscar al jugador más cercano». Ambos devuelven los cuerpos golpeados (el Entomb del Sarcognath enraiza exactamente a quien alcanzó) y respetan la regla de «un impacto máximo aunque los discos se solapen» **por jugador**. Nueve resolutores mono-objetivo se arreglaron con este helper; no reintroduzcas el bucle.
- Overlay de material: hay **un solo** punto de verdad con precedencia shiny > variante > estado (`current_overlay()`, que lee `EnemyOverlays`). Un efecto que pinte al enemigo pasa por ahí; escribir `material_overlay` a mano borra el tinte de otro sistema.
- `_tick_climb` está extraído de `_physics_process`: la trepada (`can_climb`/`climb_speed`, con `is_on_wall()` y steering activo) tiene estado propio y techo, y la posición se clampa a `arena_bounds`. El resto de `_physics_process` **no** está partido a propósito: es el bucle más caliente del juego y tiene optimizaciones deliberadas (snapshot por tick, stagger de separación).
- `spawn_chest(at, luck_bonus, min_rarity)` es el único camino a un cofre soltado, compartido por el cofre shiny (`elite_chest_chance × (1 + difficulty_bonus)`) y el anillo del jefe.
- Otros hooks del chasis: `apply_poison(dps, duración)` (tick de 0.5 s, gana el dps más fuerte y el timer más largo), `apply_slow`, `apply_variant("berserker"|"shade")`, `make_elite()`, `death_burst_color()`.
- **Shiny**: los identificadores siguen en inglés (`is_elite`, `make_elite`, `elite_chest_chance`, `Elite chest dropped:`); el texto visible es **shiny** (glosario). `EnemyOverlays.apply_elite_glow()` deja un overlay **por cuerpo** cuyo tono recorre la rueda de color y cuyo brillo late (`EnemyOverlays.tick_shiny`, valores `shiny_*` en `assets/enemies/enemy_look.tres`), con una fase inicial distinta por `get_instance_id()` para que una horda no parpadee al unísono. **Solo material**: nada de partículas ni de FX pooled — el soak de refuerzo de shiny vuelve shiny a todos los cuerpos y un emisor por cuerpo vaciaría los pools.
- Para que spawnee: en `enemy_spawner.gd` añadir un `@export var <kind>_scene` en el grupo «Escenas y fases», una rama en `_scene_for(kind)` y pesos en las tablas de fases `FOREST_PHASES` / `DUNES_PHASES` / `MARSH_PHASES` (`phase_preset` elige tabla por arena). Asignar la escena en el nodo `EnemySpawner` de cada arena. Un `kind` desconocido o sin escena hace que `_scene_for` devuelva `null`, y `_validate_phase_scenes()` (en `_ready`) lo reporta con `push_error`.
- **Nada aparece encima de un raider**: `min_player_clearance` (5 m por defecto) es la distancia mínima a **cualquier** raider en pie. `SpawnPoints.band_position` (`scripts/systems/spawner/spawn_points.gd`) la trata como parte de «este punto sirve» (rota por la banda igual que con una celda bloqueada) y **`EnemySpawner.make_enemy_at` es la puerta única**: todo camino de spawn —anillo, hordas, ráfagas, invocaciones de jefe, jauría del director— pasa por ahí, así que un llamador nuevo no puede olvidarse de la regla. El jefe se coloca **antes** de instanciarse, para que un anillo sin punto libre reintente en el siguiente tick en vez de anunciar un jefe que no llegó. Los descartes se cuentan e imprimen una vez por minuto de partida: `Spawn skipped: no clearance xN` — sin eso, un cupo mal elegido se come la presión en silencio. El valor está **por debajo** de la banda de ráfaga (7-10 m) a propósito: una horda centrada en un raider tiene que seguir siendo incómoda.
- Spawner: hordas (`horde_minutes`, luego cada `horde_repeat_minutes`; log `Horde:`; la lógica vive en `scripts/systems/spawner/horde_schedule.gd`, `HordeSchedule`, junto con `spawn_pressure_burst` y `spawn_at_points`), jefes recurrentes tras el Elder (`boss_repeat_minutes`, `boss_repeat_growth`; la lógica del horario vive en `scripts/systems/spawner/boss_schedule.gd`, `BossSchedule`, pero los exports siguen en el `EnemySpawner`, grupo «Jefes», porque las arenas los overridean), `late_xp_factor()`, `set_sky_event(kind, s)`, `apply_temp_enemy_buff(mult, s)` (los factores de escalado, el evento de cielo y el buff temporal viven en `scripts/systems/spawner/spawn_scaling.gd`, `SpawnScaling`; el `EnemySpawner` conserva fachadas con el mismo nombre) y `spawn_minions(scene, positions, force_elites)`. El cupo `max_active` se mide sobre el **grupo** `enemies` (cuerpos vivos), no sobre `get_child_count()`, y el temporizador acumula su sobrepaso: la cadencia real coincide con la tabulada.
- Eventos de cielo: `start_sky_event("blood_moon"|"eclipse"|"full_moon")` (grupo `world_director`, que reenvía al `WeatherDirector`), probabilidad `sky_event_chance + sky_event_chance_per_demonic × demonic_uses`, tinta `DirectionalLight3D` y `ambient_light_color` con **un solo** tween y los restaura; toda luna oscura encadena una luna llena que da `xp_gain`/`luck` temporales a la party. Log `Sky event:`.

## Añadir un jefe

- Qué es: chasis sobre `EnemyBase` con barra de vida en HUD, clamp de arena, escalado Elder/tier/party y pago en anillo de gemas + orbes de vida.
- Archivos: `scripts/enemies/boss_base.gd` (`BossBase`), ejemplos con máquina de estados propia: `rotking.gd`, `sarcognath.gd`, `fenwraith.gd`; telégrafos: `scenes/fx/TelegraphDisc.tscn`; púas de suelo: `scripts/enemies/spike_cluster.gd` con sus escenas `scenes/enemies/BarkSpikes.tscn` y `scenes/enemies/SandSpikes.tscn`.
- **El look de los ataques es de cada escena de jefe**: los colores de telégrafo e impacto y el temblor de cámara son el grupo de exports «Telegrafía» de `BossBase`, que cada jefe fija en su `.tscn`; la escena de púas es el export `spike_cluster_scene`. Los puntos que paga un jefe son su `points_value` (25), guardado en cada escena de jefe.
- Escena: raíz en grupos `boss` + `enemies`. En `_ready` el chasis ya hace `call_group("boss_ui", "track_boss", self, boss_title)` — la barra del HUD y la flecha de pantalla (`scripts/ui/game/boss_arrow.gd`) se enganchan solas.
- Sobreescribir **`_scale_attack_damage(mult)`** con los números del moveset. `_apply_elite_damage` delega en él, así que un jefe que pase por `apply_tier_scaling` escala su moveset en vez de quedarse en daño base; `make_elite()` es un no-op en jefes a propósito.
- **`apply_tier(hp_mult, damage_mult = -1.0, payout_mult = -1.0)`**: tres canales separados, `-1.0` = «igual que HP». El spawner los llena así, y la razón está en su comentario: HP lleva rematch × tier × dificultad × tamaño de party; **daño** lleva lo mismo **sin** el factor de party (cuatro cuerpos ya absorben más golpes: escalar también el golpe cobra doble); pago lleva rematch × tier solamente (`RunState.difficulty_xp_multiplier()` ya paga la parte de dificultad al recolectar). Compone: llamarlo dos veces multiplica dos veces.
- Piezas compartidas del chasis: `_clamp_to_arena` y `_safe_arena_point` (respetan `arena_bounds`), la llegada (`_play_boss_entrance`, `_tick_entrance` / `_play_entrance`), `_consume_thresholds` (umbrales de vida que disparan fases), `_resolve_ground_hit(spots, radio, ventana_y, ...)` (resuelve un golpe de suelo telegrafiado con su destello y su temblor), `_spawn_spike_cluster(centro, radio)` (instancia `spike_cluster_scene`) y **un único slot de tween de señal** (`_play_cue`/`_begin_cue`/`_kill_cue`): dos telégrafos solapados no se pisan el visual.
- Invocaciones: `call_group("enemy_spawner", "spawn_minions", escena, posiciones)`. Los esbirros pasan por **el mismo** escalado que un spawn de anillo (tier, rampa tardía, dificultad, buff temporal, HP de co-op, variante de cielo, tirada de shiny). Instanciarlos a mano se saltaba todo eso.
- Horario: exportado en el spawner y **overrideado por arena** en la escena del mapa — `boss_scene`, `boss_spawn_minute` (5), `elder_spawn_minute` (11), `elder_stat_multiplier`, `elder_title`, `boss_warning_text`. El spawner imprime `Boss spawned:` para los soaks.
- **No hay maldición por jefe.** El altar demoníaco sube `RunState.difficulty_bonus` para toda la partida y el `CurseLabel` del HUD muestra `Dificultad +N%`.
- Jefes ocultos: `extends SecretBossBase` (ver Secretos).

## Añadir un mapa

- Qué es: una fila de catálogo + una escena de arena. **El orden de `MAP_LIBRARY` es el orden de la partida**: una fila nueva insertada en medio cambia la progresión de todos inmediatamente. No hay desbloqueos de mapa ni grados; a un bioma se llega jugando.
- Archivos: `scripts/systems/catalogs/map_catalog.gd` (`MAP_LIBRARY`), `scripts/world/run/run_root.gd`, `scripts/world/run/arena.gd`, `scripts/world/run/scatter.gd`, arenas existentes como plantilla.
- Fila: `id`, `display_name` (topónimo, mayúscula en las dos partes), `blurb`, `scene_path`, `palette`. Nada más.
- Escena de arena (copiar `AshDunes.tscn`): raíz `Node3D` **con `scripts/world/run/arena.gd` y su `map_id`**, `WorldEnvironment` + luz (`Sun`), `Perimeter` (muros, capa 1), `Backdrop` (`scripts/world/run/backdrop.gd`, sus anillos de colinas se derivan de `arena_half_extent`), spots de verticalidad y props a mano (en grupo `scatter_keepout`), nodo de scatter con `scatter.gd` (seed determinista; su `arena_half_extent` es la **fuente única del tamaño de arena** — 120.0 = 240x240 — publicada por el grupo `arena_bounds`: la leen `BossBase` y `EnemySpawner` restando su margen, el `Terrain` (su lado es `2 × arena_half_extent`, leído al construirse) y el propio scatter, que deriva de ahí las zonas de mesetas, interior y perímetro con los márgenes `mesa_edge_margin`, `interior_edge_margin` y `perimeter_edge_margin_min/max`; el scatter además necesita su `formation_style`, un `RockFormationStyle` en `assets/world/rock_style_<mapa>.tres`), `Interactables`, `EnemySpawner` (con `phase_preset` y sus escenas/horario), `AmbientBed`, un nodo **`Terrain`** con `scripts/world/run/terrain.gd`, su `amplitude` del bioma, el `ShaderMaterial` del suelo en `surface_material` y un `backdrop_path` válido (por defecto `../Backdrop`, de donde saca el tinte del minimapa) (colocado **después** del scatter en orden de árbol), y un `Marker3D` llamado `SpawnPoint` (dónde aterriza el equipo). Los muros del `Perimeter` se escriben **estáticos** en la escena: formas `(1, 17, 242)` / `(242, 17, 1)` centradas en ±120.5 y y = 3.5. Unos **13 POI barajables** bajo `Interactables`. **NO** instancia `RunSystems.tscn`: eso vive una sola vez en `Run.tscn`.
- Los `@export` del `EnemySpawner` los overridean las tres arenas en su `.tscn`: mover esos exports a un colaborador rompe los tres mapas. Por eso `SpawnScaling`, `SpawnPoints`, `HordeSchedule`, `BossSchedule`, `PowerUpDrops` y `EnemyFreeze` (`scripts/systems/spawner/`) tienen la lógica pero leen los exports del spawner. Son `RefCounted` sin proceso propio: el `_physics_process` del spawner los avanza, así que parar el spawner los para a todos.

## Partida por etapas

Una partida es una **secuencia de etapas**, una por mapa, en el orden de `MAP_LIBRARY`, volviendo al primero con **vuelta + 1**. Lo que cruza de etapa es todo lo del equipo — nivel, armas, tomos, objetos, mascotas, puntos, boons de altar, boons temporales, la dificultad de partida y la inflación de precios de cofre y ruleta —; **no se copia nada, porque no se recrea nada**: los raiders son los mismos nodos. Lo que se reinicia es el mapa y lo que cuelga de él (cofres, altares, portales, balizas, enemigos, props), el reloj de etapa y el horario de jefes.

### Piezas

| Archivo                                                                                 | Qué hace                                                                                                                                                                                                                                                                                                                                                                                |
| --------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `scenes/world/Run.tscn` + `scripts/world/run/run_root.gd` (`RunRoot`, grupo `run_root`) | La raíz persistente. Hijos: `RunSystems` y `ArenaHost`. API: `arena_root()` / `current_arena()`, `advance_stage()`, y el estático `RunRoot.stage_parent(tree)`.                                                                                                                                                                                                                         |
| `scripts/world/run/arena.gd` (`Arena`, grupo `arena_root`)                              | Raíz de cada bioma. `map_id`, `SpawnPoint`, y el **orden** del ciclo de vida.                                                                                                                                                                                                                                                                                                           |
| `scripts/world/run/exit_portal.gd` (`ExitPortal`) | El portal de salida de la etapa, escena `scenes/world/director/ExitPortal.tscn`. |
| `scripts/world/run/world_director.gd` (`WorldDirector`, grupo `world_director`) | Dura toda la partida: los hooks de etapa, el tick de eventos (`EVENT_LIBRARY`), el portal de salida y las balizas. Sus dos hijos en `RunSystems.tscn` hacen el resto. |
| `scripts/world/run/director/weather_director.gd` (`WeatherDirector`, nodo `WorldDirector/Weather`) | El clima: lunas, lluvias y desastres, el canal de uno a la vez, sus exports y los charcos ácidos. |
| `scripts/world/run/director/weather_catalog.gd` (`WeatherCatalog`, `RefCounted`) | La tabla de climas `WEATHER_CATALOG`, `STRETCHABLE_GROUPS`, `COMPASS_WORDS` y las tiradas por peso (`roll_group`, `roll_altar`). `WeatherDirector.WEATHER_CATALOG` y `weather_row()` reenvían aquí. |
| `scripts/world/run/director/sky_tint.gd` (`SkyTint`, `RefCounted`) | El tinte del cielo: cachea el Sol y el `Environment` de la arena, los tiñe y los devuelve con **un solo** tween, creado sobre el nodo `Weather`. |
| `scripts/world/run/director/stage_fixtures.gd` (`StageFixtures`, nodo `WorldDirector/StageFixtures`) | Lo que se pone al empezar cada etapa: inicio irregular, cofres gratis, portales emparejados, ruletas, cajas de mascotas, altares de eventos y bloques de la suerte. |
| `scripts/world/run/director/stage_layout.gd` (`StageLayout`, `RefCounted`) | Las preguntas de geometría de una etapa: `event_point`, `claim_clear_point`, `ring_point`, `exit_portal_point`, `ground_height`, `shuffle_ground_interactables`. Un `StageLayout` nuevo por etapa. |
| `scenes/world/director/` | Las escenas que pone el director: `ExitPortal.tscn`, `PortalShrine.tscn`, `PortalVisual.tscn` (`portal_visual.gd`, el aspecto que comparten los dos portales), `Beacon.tscn` (`beacon.gd`, la baliza) y `SupplyChest.tscn`. |
| `RunState`                                                                              | `stage_index`, `lap`, `stage_time`, `stage_boss_dead`, `stage_cleared`, `pseudo_infinite_time`, `stages_cleared_total`, `endless_seconds_total`, `laps_completed`, `visited_map_ids`, `cleared_map_ids`, señal `stage_changed(stage_index, map_id)`, y `begin_stage()` / `mark_stage_cleared(map_id)`. Los índices son **0-based**; todo lo que ve el jugador (o un log) imprime `+ 1`. |

### El orden del ciclo de vida de una etapa (es load-bearing)

1. `RunRoot._load_stage()` instancia la arena y la cachea **antes** del `add_child` (el scatter y el `_ready` de la arena ya preguntan por `arena_root()`).
2. Al entrar al árbol, `scatter._enter_tree` siembra su RNG y **construye la máscara** de la etapa.
3. Corren los `_ready` de los hijos (spawner, ambiente, interactuables de escena).
4. `Arena._ready()` llama `world_director.on_stage_started(arena)` por grupo: arma el `StageLayout` de la etapa, el `WeatherDirector` **re-cachea el Sol y el `Environment`** (ver abajo), reinicia la niebla, baraja los POI de suelo (`StageLayout.shuffle_ground_interactables`) y `StageFixtures.place()` aplica el inicio irregular y coloca portales, ruletas y demás objetos de inicio, en ese orden (el orden interno es parte del sorteo).
5. `Arena._ready()` llama `scatter.place_props()`, así que la lista de keepouts ve las posiciones **ya barajadas** — exactamente el orden que producía el viejo reparto `_enter_tree`/`_ready` cuando cada arena tenía su propio director.
6. `RunRoot` coloca al equipo (`run_systems.place_party(origin)`, que reusa la geometría del anillo de co-op y **re-ancla el rescate del vacío** de cada cuerpo) y emite `stage_changed`.

**Por qué el re-cacheo de luces es obligatorio**: `SkyTint.cache()` sale temprano si ya tiene un Sol, y el `_exit_tree` del `WeatherDirector` no se dispara entre etapas, porque el director sobrevive a la arena. Sin `SkyTint.forget()` en `WeatherDirector.begin_stage` (llamado desde `on_stage_started`), la segunda etapa tintaría el Sol liberado de la primera y **ningún evento de cielo se vería** a partir de ahí. El soak lo comprueba: el harness dispara una luna de sangre 5 s después de cada cambio de etapa.

### El cambio de etapa (`advance_stage`)

Corre dentro de `ScreenFade.transition_async(action)` — el hermano que **espera** a la acción entre el fundido de entrada y el de salida, cosa que `transition()` no puede hacer (su acción va en un `tween_callback`, y una corrutina vuelve al tween en su primer `await`). `RunRoot._swap_stage()` es la lista de pasos, cada uno un helper con nombre (`_freeze_world`, `_print_carry`, `_tear_down_stage`, `_print_sweep`, `_free_arena`, `_advance_counters`, `_load_stage`, `_announce_stage`). Pasos:

1. Cierra todo menú bloqueante que acepte cierre por código (`call_group("blocking_ui_closable", "dismiss")`: esas capas cuelgan de la ARENA y el paso 5 las liberaría sin pasar por su `_close()`, que es lo único que devuelve la pausa), pausa el árbol **y para explícitamente el spawner**; el director se detiene **a sí mismo** en `on_stage_ended` (paso 3), no aquí. La pausa sola no basta: los `process_mode` se **heredan**, y el harness de soaks enraiza toda la partida bajo un nodo `ALWAYS`, así que un árbol «pausado» ahí sigue generando enemigos. Un spawner trabajando mientras se desmonta su arena mete enemigos en el `Stage sweep:`.
2. `Stage carry:` con lo que lleva el equipo, leído de los nodos vivos.
3. Desmontaje: liberar todo enemigo con `free()` (no `queue_free()`: el barrido cuenta en el mismo frame), `Pools.release_all_live()` (cada `NodePool` mantiene un conjunto de vivos y los reclama de inmediato), `world_director.on_stage_ended()` y liberar los restos de etapa (cofres, altares, portales, ruletas, manantiales, balizas, gemas, orbes). Los grupos que se liberan enteros están en `RunRoot.STAGE_PROP_GROUPS`: **un tipo nuevo de cosa que vive en la etapa añade ahí su grupo.**
4. `await get_tree().process_frame` y `Stage sweep: enemies=%d gems=%d orbs=%d chests=%d altars=%d beacons=%d pickups=%d boxes=%d vendors=%d possessed=%d` (diez campos; `tools/verificar.sh` greppea el literal completo) — **todos en cero**, o hay una fuga que seguiría al equipo al mapa siguiente.
5. Liberar la arena.
6. Avanzar los contadores (`lap += 1` al envolver) y construir la etapa siguiente por el ciclo de arriba.
7. Banner «Etapa %d — %s», `show_stage_tag`, log `Stage advanced:` y `Stage carry:` otra vez. **Las dos líneas de acarreo tienen que coincidir**: es la prueba de que cruzar no cuesta nada.

### Dónde se parentan las cosas

`RunRoot.stage_parent(tree)` es **el** padre de todo lo que se spawnea al mundo: pooled FX, proyectiles, cofres soltados, púas de jefe, la UI de la ruleta, los minijefes secretos. Antes todos usaban `get_tree().current_scene`, que **era** la arena; ahora `current_scene` es la raíz persistente, así que spawnear ahí arrastraría los dardos y los charcos de la etapa 1 a la etapa 2. `Pools._spawn_parent()` hace lo mismo. Los únicos `current_scene` que quedan son los de esos dos helpers (su fallback fuera de partida) y los del harness.

### La puerta de etapa y el modo pseudo-infinito

- **Puerta** (`RunManager`): la etapa se supera cuando `RunState.stage_time >= stage_goal` (900 s) **y** el jefe de etapa (el Elder) está muerto. Una arena sin `boss_scene` cuenta como «jefe muerto». Log `Stage gate: time=%.1f boss=%s`, y `Stage boss slain:` cuando cae el Elder (`BossSchedule._watch_stage_boss`, en `scripts/systems/spawner/boss_schedule.gd`, conectado a **esa** instancia: los jefes recurrentes posteriores no reabren nada).
- Superarla abre el **portal de salida** (`WorldDirector._tick_exit_portal`, a `exit_portal_min_distance` 40 m o más de todo raider, con baliza hasta usarse; el aviso del HUD es el export `exit_portal_announce`) y la flecha de jefe lo apunta mientras no viva ningún jefe (`track_objective`). Logs `Exit portal opened at %.1fs` y `Portal used: exit`.
- **Pseudo-infinito**: mientras la etapa está superada, cada minuto de `RunState.pseudo_infinite_time` suma HP +15%, daño +10% y velocidad +4% (con tope `endless_speed_cap` 1.8), comprime el intervalo de spawn ×0.85 y agranda las hordas ×1.5. Exports en el spawner (`endless_*`), aplicados en spawns frescos por `SpawnScaling.scale_fresh_spawn`; la velocidad es su canal propio porque `apply_tier_scaling` cubre HP/daño/pago solamente. Log `Pseudo-infinite: minute %d hp x%.2f dmg x%.2f speed x%.2f`, uno por minuto.
- **Vueltas**: los grados de mapa desaparecieron; su lugar lo ocupa `lap_hp_mult` 1.5 / `lap_damage_mult` 1.3 / `lap_xp_mult` 1.3 por vuelta completa, aplicados por el mismo canal `apply_tier_scaling` / `apply_tier`.
- El horario de jefes y las hordas leen **`RunState.stage_time`**, no `run_time`: cada mapa tiene su jefe en el minuto 5 y su Elder en el 11. Las rampas globales (intervalo, conteo, rampa tardía) siguen leyendo `run_time`.

### Interruptores del harness

`BONK_STAGE_FAST=1` supera la etapa a los 60 s y sin jefe; el harness se queda entonces `PSEUDO_INFINITE_DWELL` (70 s) antes de ir al portal, para que la rampa registre al menos un minuto, y después abandona su ruta y va directo. `BONK_ARENA` ya no nombra la escena a instanciar sino el **bioma inicial** (`GameConfig.start_map_id`); el harness siempre arranca `Run.tscn`. `BONK_SAVE_PATH` re-apunta el guardado antes de la primera lectura, para cualquier arranque headless que no sea el probe.

## Terreno

Desde la iteración 51 el suelo de una arena **no es una placa plana**: es
`scripts/world/run/terrain.gd` (`class_name Terrain extends StaticBody3D`, grupo
`terrain`, `static func find(tree)`), un heightmap suave de amplitud baja
(bosque 2.5, dunas 3.0, ciénaga 1.5) con mesetas encima.

**El relieve es deliberadamente bajo.** Esto es un bullet-heaven: la horda no
tiene navmesh, persigue en línea recta y trepa lo que la bloquea, así que un
terreno capaz de esconder a un raider o cortar una persecución rompería la
persecución en vez de enriquecerla. Lo que compra el relieve es legibilidad
(saber dónde estás en 240×240) y silueta.

- **Semilla**: la del scatter (`scatter.run_seed()`, válida desde su
  `_enter_tree`, leída por el grupo `arena_bounds`), así que `BONK_SEED`,
  `BONK_GAME_SEED` y la Cacería diaria reproducen el mismo relieve **y** los
  mismos props encima.
  - **De dónde sale esa semilla**: de `randi()`, es decir del **stream de
    la partida**, el que `RunState.reset()` acaba de sembrar. Nunca de
    `_rng.randomize()`, que resiembra desde la entropía del sistema y es
    sorda a `BONK_GAME_SEED`: dos soaks con la misma semilla saldrían con
    máscara, props y relieve distintos. En una partida normal `reset()` hace
    `randomize()` sobre ese mismo stream.
- **Orden de construcción**: se arma en `_ready`, que corre **antes** de
  `Arena._ready` (los hijos primero) y **después** del `_enter_tree` del
  scatter, así que la máscara y los sitios de meseta ya existen. Quien pueda
  correr antes (el `Backdrop` es el hijo #2 y lee `min_height` en su propio
  `_ready`) llama `ensure_built()`, que es idempotente.
- **API**: `height_at(x, z)` (bilineal sobre la misma rejilla que tiene el
  cuerpo físico), `height_at_xz`, `snap(pos)`, `min_height`, `max_height`,
  `map_image(px_per_meter)` (para el minimapa y el mapa de Tab: el
  `ground_color` del nodo en `backdrop_path`, por defecto `../Backdrop`,
  aclarado en las cimas con `map_peak_lighten` y oscurecido en las
  hondonadas con `map_hollow_darken`).
- **Tamaño**: `Terrain.size` no es un export: es `2 × arena_half_extent`
  del scatter, leído al construir (la fuente única del tamaño de arena).
- **Técnica**: el ruido se muestrea en una retícula de `noise_step` 2 m y se
  interpola a la rejilla de 1 m del `HeightMapShape3D` (que es **fija** en una
  unidad por muestra: 241×241 y el nodo sin escalar). La malla se arma con
  `add_surface_from_arrays` sobre arrays empaquetados, no con `SurfaceTool`:
  un vértice por llamada sobre 241×241 son cientos de miles de llamadas de
  GDScript y tarda segundos. Presupuesto: **400 ms**; medido 92-115 ms.
- **El sentido de los triángulos (iteración 60).** Godot considera **frontal
  la cara horaria vista desde delante**, así que un suelo que se pisa se
  emite **horario visto desde +Y** — lo mismo que decir que
  `cross(v1 − v0, v2 − v0)` apunta **hacia abajo**. De la iteración 51 a la
  59 salió al revés y **el suelo era transparente**: el terreno se
  culeaba por back-face desde cualquier cámara por encima, se caminaba sobre
  un collider invisible y la arena se veía como un puñado de props flotando
  sobre el disco del backdrop. Es lo que el jugador reportó y lo que ninguna
  puerta pudo ver, porque todas corren `--headless` y el renderizador de
  pega no rasteriza nada. `_assert_winding()` comprueba ahora el primer
  triángulo en **cada** construcción y hace `push_error` si mira hacia
  arriba, que es un fallo de `tools/verificar.sh` **sin** necesidad de
  pantalla. Ver «Verificación → La cámara del harness».
- **Pads planos**: bajo el spawn (`spawn_flat_radius`), bajo cada grupo
  autorizado de `Verticality` y bajo cada sitio de meseta, con una banda de
  mezcla de `pad_blend` (6 m). **Nunca bajo los POI barajables**, cuyo XZ cambia después: a
  esos se los apoya en el relieve. Una banda de `rim_flat_band` 10 m aplana el
  borde para que los muros estáticos y el disco del backdrop encuentren suelo
  llano.
- **Regla de nulos**: quien corre desde `on_stage_started` en adelante trata un
  `find()` nulo como un `push_error` una vez; quien corre en construcción
  (Backdrop, HUD, overlay) lo tolera en silencio y se reconstruye al empezar la
  etapa.

### La regla de apoyado

**Nada se coloca a y = 0.** Todo pasa por `Terrain.height_at`:

| Dónde                                                              | Cómo                                                                                                                       |
| ------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------- |
| Props del scatter                                                  | `_spawn_prop` **ignora** el `pos.y` que le pasan y usa `ground_height()`                                                   |
| Línea de perímetro, mesetas                                        | por el mismo `_spawn_prop`                                                                                                 |
| Formaciones rocosas de la máscara                                  | `RockFormation.build` levanta cada vértice sobre `height_at` de su propio XZ                                               |
| Puntos del director                                                | `StageLayout.claim_clear_point()` → `terrain_height()`                                                                     |
| Eventos, portales, ruletas, altares, manantiales, cofres de evento | `StageLayout.event_point()` / `claim_clear_point()`                                                                        |
| Portal de salida                                                   | `StageLayout.exit_portal_point()`, apoyado por `ground_height`                                                             |
| POI barajados                                                      | `StageLayout.shuffle_ground_interactables` apoya los autorizados por debajo de `POI_PLATFORM_Y` 0.5; los de plataforma conservan su y |
| Spawn del equipo                                                   | `Arena.spawn_origin()` y `RunSystems.place_party` (cada offset del anillo lee su propia altura)                            |
| Anillo de cofres del jefe                                          | uno por uno en `BossBase._drop_chests`                                                                                     |
| Spawns de enemigos                                                 | `EnemySpawner.ring_position` → `SpawnPoints.ground_height`                                                                 |

**Las dos sondas de suelo** (`StageLayout.ground_height`,
`SpawnPoints.ground_height`, en `scripts/systems/spawner/spawn_points.gd`) barren **todo** el relieve —desde sobre la
meseta más alta (`max_height` + margen) hasta bajo la hondonada más honda
(`min_height` − margen)— y su fallback **no es 0** sino `height_at`: cero es
una altura real en un heightmap, así que un fallback a 0 enterraría o
levitaría lo que colocara.

**Las dos puertas del harness se reescribieron con el terreno, no se
aflojaron**: el barrido de máscara centra su cápsula en
`height_at(muestra) + SWEEP_CAPSULE_CENTER_Y` y **excluye el RID del terreno**
de la consulta (una cápsula que toca el suelo no es una apertura; rocas, props
y muros siguen contando); el vigilante de celda bloqueada compara
`y − height_at(xz)` contra `FLOOR_STAND_MAX_Y`.

## Arena irregular

- Qué es: cada partida el cuadrado de **240x240** recibe una **máscara de celdas**. Vive en `scripts/world/run/scatter/arena_mask.gd` (`ArenaMask`, `RefCounted`, sin Inspector): el scatter (`scatter.gd`, grupo `arena_bounds`) la crea en su `_enter_tree`, con **su** RNG, y le copia sus exports `mask_*` del grupo «Máscara de la arena» antes de `build()`; ahí viven la acreción, `_fill_notches`, el flood fill y los pasillos. `mask_cell_size` (**5 m**, o sea 48x48 celdas), y entre `mask_blobs_min` y `mask_blobs_max` (**5-8**) formaciones crecen por **acreción** desde una semilla hasta `mask_blob_cells_min..max` (20-50) celdas: cada paso añade una celda de la frontera, con peso hacia el eje propio de la formación (crestas, `mask_ridge_bias`) y hacia celdas ya rodeadas por dos o más lados (masas compactas). Las semillas guardan `mask_blob_spacing` (10 celdas) entre sí, dos formaciones distintas dejan siempre `mask_formation_gap` (2) celdas abiertas entre ellas, el anillo exterior de `mask_border_cells` (2) celdas nunca lleva roca y nada crece a menos de `mask_protect_radius` (15 m, medido al cuadrado de la celda) del spawn ni de los spots de verticalidad. Una celda abierta rodeada por tres lados se rellena (`_fill_notches`) y un flood fill 4-vecinos desde el spawn **sella** cualquier bolsa no alcanzable. Si queda menos de `mask_min_open_fraction` (0.84) abierto se reintenta con menos formaciones. Los enemigos trepadores cruzan la roca; el jugador solo si sube encima (la cresta se camina).
  - **Cuánto tapa.** Medido en 34 arranques (3 biomas × semillas 1-8 más las arenas de un `verificar.sh`): **7.3-15.5%** de las celdas, 5-8 formaciones por etapa; el techo es 16% por `mask_min_open_fraction`.
  - **Una formación por región** (`scripts/world/rock_formation.gd`, `class_name RockFormation`). `_raise_formations()` parte las celdas bloqueadas en regiones 4-conexas y levanta **un** `StaticBody3D` por región: una malla facetada (sombreado plano, un color por faceta) con un acantilado que empieza `margin_min..margin_max` (1-2 m, campos del `RockFormationStyle`) **fuera** de las celdas y una cresta cuya altura sigue la distancia al contorno —una cresta larga se lee como cresta, una masa compacta tiene cumbre—, picos de ruido _ridged_ y un techo suave en `max_height` 8 m (también del estilo), por debajo de los 10 m que un trepador escala de una vez (`EnemyBase.max_climb_height`). Log `Rock formations: %d regions, %d faces, %d shapes, tallest=%.1f in %d ms`.
  - **La colisión ES la malla.** Cada cuadrilátero visible es también un prisma convexo (sus 4 esquinas más las mismas hundidas bajo el terreno), partido por la diagonal **más alta**, que es justo la envolvente superior de las 4 esquinas: el techo del prisma son los dos triángulos que se ven. Nada invisible contra lo que chocar, nada visible que se atraviese. Convexo y no trimesh a propósito: un trimesh no tiene interior, y el barrido de máscara del harness para una cápsula **dentro** de la roca en cada frontera.
  - **El sello es estructural.** El paso de la malla divide exacto el tamaño de celda, así que cada frontera de celda es una fila de aristas de la malla (los vértices sobre una frontera solo se desplazan A LO LARGO de ella), y la huella empieza siempre al menos `margin_min` fuera de la frontera, donde el perfil ya está alto (peor caso del perfil por defecto ≈ 0.95 m). `build()` mide cada vértice de frontera y `push_warning` si queda bajo `SEAL_MIN_HEIGHT` (0.75 m): hace fallar `verificar.sh`.
  - **No hay muros invisibles**: lo que bloquea es lo que se ve, y una formación es roca maciza de borde a borde, sin interior hueco al que un raider pueda saltar ni techo plano por el que un trepador camine.
  - **Paleta por bioma** en el `formation_style` de cada scatter (un `RockFormationStyle`, `scripts/world/run/scatter/rock_formation_style.gd`): `assets/world/rock_style_hollow_woods.tres` (granito con musgo), `assets/world/rock_style_ash_dunes.tres` (arenisca roja con estratos y escalones: `strata_strength`, `terrace_strength`, `terrace_step`) y `assets/world/rock_style_gloomfen.tres` (pizarra oscura musgosa). Para cambiar cómo se ve la roca de un mapa se edita su `.tres` en el Inspector. El color va **horneado en vértices** sobre `assets/materials/rock_formation.tres` (blanco × color de vértice, sRGB), incluido el sombreado por pendiente: con el ambiente y la niebla de las arenas el sol solo no separaba un acantilado de una cresta y la primera versión se leía como una maqueta de papel.
  - Los árboles (`scenes/world/props/Tree.tscn`, script `scripts/world/props/tree_prop.gd`) cambian su `TreeModel` de vista previa por uno de dos modelos al azar con una escala al azar al entrar al juego: los modelos, la probabilidad y los rangos de escala son exports de la escena (tres tiradas del RNG de la partida, siempre en el mismo orden).
  - Los props interiores (`_is_clear`) guardan `formation_clearance` (2.5 m) a cualquier celda bloqueada y las mesetas `mesa_clearance` (12 m), para que ni un árbol ni una rampa salgan de un acantilado.
  - Las rocas sueltas (`Rock.tscn`, `DuneRock.tscn`) siguen llevando **un `ConvexPolygonShape3D` por blob visible**, con los puntos horneados en la transformación del blob para que `_spawn_prop` pueda escalar **uniformemente** (Godot no soporta escalar una forma de colisión de forma no uniforme). Se pintan con `assets/shaders/faceted_rock.gdshader` (`boulder.tres`, `boulder_red.tres`): normal de cara por derivadas, para que no parezcan cantos rodados junto a las formaciones. `rock.tres` y `red_rock.tres` siguen en plataformas y santuarios, sin cambios.
- API: `is_walkable(Vector2)`, `random_walkable_point()`, `blocked_cell_count()`, `open_cell_count()`, `blocked_cells()`, `cell_center(Vector2i)`, `cell_of(Vector2)` (las tres últimas las usa el barrido de máscara del harness). Son métodos de `scatter.gd` que reenvían a su `ArenaMask`. Consumidores: `SpawnPoints.ring_position` / `band_position` (`scripts/systems/spawner/spawn_points.gd`, detrás de `EnemySpawner.ring_position` y `spawn_pressure_burst`) (reintentan hasta hallar celda abierta, no clampean), el `StageLayout` del director (un **único** camino respeta la máscara para portales, ruleta, altares y cofres de evento), `scatter._is_clear`, y el harness de pruebas. La máscara se construye en `_enter_tree` (antes del barajado del director) con el mismo RNG. Log `Arena mask:`, que **imprime la fracción abierta** (la puerta que persigue el bucle de reconstrucción).
- Inicio irregular: `StageFixtures._randomize_starting_pois` (`scripts/world/run/director/stage_fixtures.gd`) elimina cofres/altares colocados con `poi_skip_chance` (conserva al menos el primer cofre) y añade `extra_start_chests_min..max` cofres en puntos libres. Log `Start layout:`.

## Minimapa y mapa (Tab)

Cada vista de jugador tiene **su propio** minimapa en la esquina y **su
propio** mapa a pantalla completa con Tab. En 240×240 con relieve, «¿dónde
estoy y dónde está lo que no he abierto?» no se responde mirando alrededor.

### Las tres piezas

| Pieza                    | Qué es                                                                  | Dónde vive                                                                                   |
| ------------------------ | ----------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `FogOfWar`               | lo que el equipo **ha visto** de la etapa                               | `scripts/systems/fog_of_war.gd`, nodo de `RunSystems.tscn`, grupo `fog`, `static find(tree)` |
| `MapDraw`                | **el** dibujante: fondo, composición con niebla, marcadores, proyección | `scripts/ui/maps/map_draw.gd` (`RefCounted`, `MapDraw.new(get_tree())`)                      |
| `Minimap` / `MapOverlay` | los dos consumidores                                                    | `scripts/ui/maps/minimap.gd`, `scripts/ui/maps/map_overlay.gd` (escena `scenes/ui/maps/MapOverlay.tscn`), ambos creados por `ViewWidgets` del HUD |

**`MapDraw` es uno solo a propósito.** Un widget de 150 px y un overlay de
media pantalla comparten el 100% de la lógica (la imagen del terreno, el
oscurecido de celdas bloqueadas, la composición con la niebla, el filtrado de
marcadores y la proyección mundo→pantalla). Escrita dos veces, la única
pregunta interesante —«¿por qué el marcador cae en un sitio distinto en el
minimapa?»— habría tenido respuesta.

Reparto de trabajo, y **cuándo** corre cada cosa:

- `build_background(arena)` — **una vez por etapa**, desde el hook de etapa del
  consumidor. Pide `Terrain.map_image(PIXELS_PER_METER)` (tinte del bioma
  sombreado por altura; 0.5 px/m = 240 px para una arena de 240 m) y oscurece
  las celdas que la máscara bloquea, para que el mapa tenga la **forma
  irregular** de la etapa y no un cuadrado limpio.
- `composite()` — en el tick de refresco (10 Hz), **pero solo si cambió algo
  que lee**: el minimapa y el overlay comparan
  `Minimap.composite_key()` —identidad de la `Image` de fondo, identidad del
  nodo de niebla y `FogOfWar.revision`— y se la saltan si es la misma de la
  última vez; `on_stage_started` borra la clave. Recomponer cuesta 1,5-2,8 ms,
  demasiado para hacerlo cada 6 frames sin motivo. **Contrato**: si
  `composite()` empieza a leer otra cosa, esa cosa entra en la clave; y quien
  escriba `FogOfWar.image` fuera de `fog_of_war.gd` sube `revision`. Fondo × niebla en una única
  `ImageTexture` que el consumidor solo blitea. Lo inexplorado se atenúa a
  `FOG_ALPHA` 0.85, **no** se pinta opaco: la silueta del mapa es una pista, lo
  que hay **encima** es la recompensa.
- `collect_markers()` — 10 Hz. Quién está dónde, filtrado por la niebla.
- `draw_into(canvas, rect, marker_scale)` — desde el `_draw` de cada consumidor.

Las tres primeras son **métodos planos sin Control**: un soak headless las
ejercita aunque `_draw()` no se despache jamás bajo el renderer dummy. Esa es
la razón de que el minimapa y el overlay refresquen llamándolas en vez de
dejarlo todo dentro de `_draw`.

### Niebla de guerra

- Estado autoritativo: **una `Image` L8** (255 explorado, 0 desconocido),
  `meters_per_pixel` 2.0 → 121×121 para 240 m. Nada fuera de `FogOfWar`
  escribe en ella.
- Se pinta un disco de `reveal_radius` 18 m por raider **vivo y caído** cada
  `paint_interval` 0.2 s. Los caídos revelan porque su cuerpo sigue ahí.
- **Compartida por todo el equipo**: en co-op, cuatro raiders explorando cuatro
  esquinas están explorando **un** mapa.
- Ámbito de partida: se reconstruye por etapa desde
  `WorldDirector.on_stage_started` (no desde la señal `stage_changed`: por ese
  hook pasa también la etapa 0, así que no hay caso especial de primera etapa)
  y no persiste nada entre incursiones.
- `explored_fraction()` no barre la imagen: `reveal_at` lleva la cuenta de
  píxeles nuevos. El harness la lee.
- API pública: `reveal_at(xz)` (existe para un futuro power-up de «leer el
  mapa»), `is_explored(xz)`, `explored_fraction()`, `pixels()`,
  `half_extent()`.

### Marcadores de mapa

Un nodo aparece en el mapa **poniendo `marker_kind`** y nada más: `Interactable`
se une solo al grupo `map_markers` cuando ese export no está vacío, y expone
`map_marker_kind()`. `Player` y `BossBase` hacen lo mismo por su cuenta.

- La tabla es `MapDraw.MARKER_STYLES`: color, forma (`dot` / `square` /
  `triangle` / `diamond`), tamaño y `always_visible`. **Un kind que no está en
  la tabla no se dibuja.**
- Solo los raiders y la **salida** son `always_visible`; todo lo demás hay que
  **encontrarlo** (la niebla filtra en `collect_markers`).
- **Los enemigos normales no se dibujan nunca.** Un minimapa con cuarenta
  grunts es ruido, y la horda es justo lo que el jugador ya está mirando. Solo
  los jefes.
- Un altar gastado o un cofre abierto **desaparecen** por el `available` que
  esos nodos ya tenían: no se añadió estado nuevo.
- `secret_trigger.gd` deja `marker_kind` **vacío a propósito** y lo dice en un
  comentario: los secretos siguen siendo secretos.
- Un kind nuevo necesita su fila en `MARKER_STYLES` y otra en `MARKER_LABELS`
  para la leyenda (el lint `marker_labels` lo exige), salvo que sea una
  variante nombrada en `MapDraw.LEGEND_VARIANTS`. El nodo solo pone su
  `marker_kind` (en el script o en su escena).
- Un nodo puede además implementar `map_marker_color()` para pintarse con su
  propio color (rareza de cofre, por ejemplo) sin tocar la tabla.

### Los dos consumidores

- **`Minimap`** (150 px): norte arriba, marcadores a 0.75 de escala, refresco
  0.1 s. En solitario va arriba a la derecha, **bajo las bajas y la insignia
  de FPS**; en co-op, uno por celda de pantalla dividida.
  - **Dónde va, exactamente.** El rectángulo del minimapa en las celdas que
    tocan el borde superior de la ventana es el nodo
    `HUD.tscn > ViewWidgets > MinimapSlot`: se mueve y se redimensiona en el
    editor. Las celdas de abajo (co-op) usan el mismo ancho y alto con el
    margen superior `lower_cell_top_margin` de
    `scripts/ui/game/hud/view_widgets.gd`.
- **`MapOverlay`** (`scenes/ui/maps/MapOverlay.tscn`): en su propia
  `CanvasLayer` de capa **8** (`UiLayers.MAP_OVERLAY` en `scripts/ui/ui_layers.gd`; bajo
  `UpgradeCardUI` 10 — una carta abierta tiene que verse por encima),
  `PROCESS_MODE_ALWAYS`, grupo `map_overlay`. Cabecera «Etapa N · Vuelta M —
  MM:SS», leyenda abajo a la izquierda y cinco paneles a la derecha, cada uno
  una instancia de `scenes/ui/maps/MapSection.tscn` que solo pone su `title`:
  **Power-ups**, **Mascota**, **Estadísticas** (la capa derivada, con
  `cooldown_multiplier` mostrado como **velocidad de ataque en positivo**,
  regla 7 del glosario; qué filas salen y en qué orden es `STAT_ROWS`, al
  principio de `map_overlay.gd`), **Jugadores** (HP, nivel y puntos de los
  cuatro slots, caídos incluidos) y **Objetos** (objetos con copias, armas
  con nivel, tomos con su numeral).
- **No pausa la partida.** Es un mapa, no un menú: el mundo sigue vivo detrás,
  y por eso el overlay tampoco entra en `ui_blocking`. Se oculta solo si la
  partida no está activa, si el árbol está pausado o si el slot no tiene raider.
- **Todo Control de ambos widgets es `FOCUS_NONE` y `MOUSE_FILTER_IGNORE`**:
  **Tab es `ui_focus_next` de Godot**, así que un solo Control enfocable
  dentro del overlay se come la tecla y el mapa deja de cerrarse. Las filas
  que se arman en código pasan por `_own()`; los nodos de `MapOverlay.tscn`
  tienen foco None por defecto y `mouse_filter = 2` en la escena. **Un nodo
  nuevo en esa escena tiene que quedar con foco None.**
- Los construye `ViewWidgets` (`scripts/ui/game/hud/view_widgets.gd`, nodo
  `HUD.tscn > ViewWidgets`): `build(player_count)` crea un par por jugador y
  `_anchor_to_cell` ancla el overlay usando **`SplitScreenView.cell_rect(i, n)`**
  (con un caso `1:` explícito que devuelve el rect entero).

### Entrada

`map_overlay` es una acción nueva de `project.godot` (Tab por keycode físico,
botón **BACK** en control) y está en `Coop.BASE_ACTIONS`, así que cada slot
tiene su `p0_map_overlay`, `p1_map_overlay`… ligado solo a su dispositivo: en
co-op cada jugador abre **su** mapa.

## Power-ups

Hay **power-ups temporales**: efectos ruidosos y
breves (20 s; la estrella 15) que caen de las bajas, salen del manantial y
los vende un vendedor. No son tomos ni objetos: no se acumulan, no se
eligen en una carta y **se sienten sin leer un número**.

### Las cuatro piezas

| Pieza            | Qué es                                                | Dónde                                                                                                      |
| ---------------- | ----------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `PowerUpCatalog` | las 10 filas                                          | `scripts/systems/catalogs/powerup_catalog.gd`                                                              |
| `PowerUps`       | componente por raider: qué está activo y cuánto queda | `scripts/systems/power_ups.gd`, hijo de `Player.tscn`, `PowerUps.find_in(body)`                            |
| `PowerUpPickup`  | la gema en el suelo                                   | `scripts/systems/pickups/powerup_pickup.gd` + `scenes/systems/PowerUpPickup.tscn`, grupo `powerup_pickups`. La gema, el glifo, la luz y la forma son nodos de la escena; el script solo los tiñe con el color de la fila |
| `EnemySpawner`   | la tirada del drop, el congelado y la puerta de spawn | `roll_powerup_drop` / `spawn_powerup_pickup` (fachadas sobre `scripts/systems/spawner/powerup_drops.gd`, `PowerUpDrops`) y `freeze_enemies(duration, announce := false)` (fachada sobre `scripts/systems/spawner/enemy_freeze.gd`, `EnemyFreeze`) |

### Añadir un power-up

**Una fila.** Si el efecto es estadístico (`effects: [{stat, amount}]`) no
hay que escribir **nada** de código: el canal de boons temporales ya
existe. Si es un comportamiento (`kind`) se añade **una** rama en
`PowerUps`. Dos filas llevan las dos cosas y dicen por qué: el vampiro
(robo de vida normal + HP permanente por baja) y la estrella (`kind` sin
`effects`, porque **es** todas las demás a la vez).

La regla de acumulación es una sola: **distintos se apilan, el mismo se
refresca** (y un refresco nunca acorta). Por eso los consumidores de
`kind` se re-sincronizan desde `has(kind)` después de cada cambio en vez de
apagarse al expirar: con apilado, «se acabó la inmortalidad» y «ya no soy
inmortal» son preguntas distintas — puede seguir corriendo una estrella.

Los boons estadísticos van **etiquetados** (`add_timed_boon(..., tag)` +
`clear_timed_boons(tag)`): sin etiqueta, volver a agarrar
Furia apilaría un segundo +100% y la primera expiración se llevaría la
mitad.

### Las filas de comportamiento

| kind        | Qué hace                                       | Dónde vive el efecto                                                          |
| ----------- | ---------------------------------------------- | ----------------------------------------------------------------------------- |
| `immortal`  | ningún golpe entra                             | `Health.invulnerable` (+ `Health.blocked_hits`, que el soak lee)              |
| `reflect`   | el daño recibido vuelve al atacante            | `Health.reflect_fraction` (la fracción es el campo `reflect_fraction` de la fila), evaluado **antes** del rechazo por inmortalidad |
| `vampire`   | robo de vida + **HP máx. permanente por baja** | boon de `lifesteal` + `PowerUps.permanent_max_hp` (cuánto por baja: campo `max_hp_per_kill`) |
| `gold`      | cada baja paga doble                           | `Player.set_points_source(id, mult)` (reenvía al nodo `Wallet`) — un **producto de factores con nombre**; el factor es el campo `points_multiplier` |
| `flight`    | mantener salto para volar                      | `PlayerFlight.tick` (nodo `Flight` del Player, `scripts/player/components/player_flight.gd`), techo sobre `Terrain.height_at` |
| `time_stop` | la horda se congela                            | `EnemySpawner.freeze_enemies(duration, true)`: `PowerUps` pide el anuncio, cuyo texto es `EnemySpawner.time_stop_start_text` |
| `star`      | todas las demás, con **su** reloj de 15 s      | `PowerUps.apply` recursivo sobre `star_components()`                          |

**`permanent_max_hp` es un total guardado**, re-aplicado por
`PlayerStats._apply_powerups()` en cada `recompute()`. Sumarlo a
`bonus_max_hp` lo borraría el siguiente `_reset_derived()`. El componente
pide el recompute con un `call_deferred` coalescido: un arma de área
puede cobrar doce bajas en un frame.

### Tiempo detenido

El spawner es el dueño porque es el único nodo que ya conoce a **todos**:
cuerpos, jefes y los bolts en vuelo.

- Un cuerpo congelado queda en `PROCESS_MODE_DISABLED` con su `velocity`
  **guardada y puesta a cero**. Lo de poner a cero importa dos veces: un
  `CharacterBody3D` deshabilitado conserva la velocidad que tenía (el
  detector de voladores del harness seguiría leyéndolo subiendo) y
  restaurarla al descongelar es lo que evita que un enemigo lanzado
  teletransporte la distancia que «debía».
- **Lo que se genera durante el congelado se congela también**: una horda
  que sigue entrando a través del tiempo detenido no es tiempo detenido.
- **`EnemyBase._on_died` restaura el `process_mode` antes de crear su tween
  de muerte.** Un nodo deshabilitado **sí** recibe llamadas y señales: se
  lo puede matar congelado, y su tween quedaría atado a un nodo que no
  procesa — nunca termina y el cadáver no se libera nunca.
- Los bolts enemigos (grupo `enemy_projectiles`, al que `EnemyBolt` se une
  en `_ready` **y** en `pool_reset`) llevan un **flag** `frozen`, no un
  `set_physics_process(false)`: `NodePool` fotografía el estado de proceso
  al soltar y lo restaura al adquirir, así que un nodo pooled congelado
  así vuelve inerte para siempre. Un bolt congelado además **no golpea**:
  su `Area3D` sigue vigilando (para eso es un flag y no un apagado), y sin
  esa guarda una bala ya en el aire rompería lo único que el tiempo
  detenido promete.
- Los cuerpos congelados quedan **no sólidos** (`collision_layer` 0,
  restaurada al descongelar). «La horda se congela; tú no» tiene que
  significar libre para **moverse**, y un cuerpo deshabilitado no se puede
  empujar: ochenta de ellos cerrados alrededor del raider serían ochenta
  estatuas soldándolo en el sitio. Las armas buscan por **grupo y
  distancia**, nunca por capa de colisión (`WeaponBase.enemies_in_disc`),
  así que un congelado no sólido sigue siendo perfectamente dañable.

### Vuelo

Mientras corre y **se mantiene** la acción de salto, el raider sube a
`flight_rise_speed` (exports del nodo `Flight`) hasta `flight_ceiling` metros **sobre el terreno**
(un Y absoluto lo enterraría en una colina de un mapa y lo dejaría en el
cielo en otro); soltar el salto planea. El XZ se limita al
`arena_half_extent` del nodo `arena_bounds` — el borde de arena es un muro
para quien camina y no sería nada para quien vuela.

**Al expirar** (`Player.end_flight()`, que reenvía a `PlayerFlight.end_flight`; un borde y no un estado): si el
raider está sobre una celda **no caminable**, se lo baja al punto caminable
más cercano de entre `PlayerFlight.LANDING_SAMPLES` muestras. Sin eso caería
en una celda bloqueada de la máscara, que es exactamente lo que el vigilante
de celda bloqueada del harness existe para atrapar. Log `Flight landing:`.

### El drop, la estrella y el manantial

- **Drop por baja**: `EnemyLoot.drop_powerup(cuerpo)` →
  `EnemySpawner.roll_powerup_drop(raider, shiny)`. Base
  `base_powerup_drop_chance` 0.004 × (1 + `powerup_drop_chance`/100 del
  raider más cercano) × 5 si el cuerpo era shiny × `BONK_POWERUP_BOOST`.
  **Aquí se consume la estadística `powerup_chance`** («Fortuna menor» en
  los altares).
- **La estrella nunca cae de una baja.** Su única fuente es la fila
  `star_sighting` del `WorldDirector` (peso 0.15): sale en un punto de
  evento y **ronda** el mapa a 6 m/s rebotando contra lo no caminable y
  contra el borde, con tinte arcoíris y 60 s de vida. Log `Star roam:`.
- **Manantial**: cura completa + **un power-up al azar** (nunca la
  estrella). Ya no tira su propio paquete de boons: con un roster de
  power-ups, un manantial que diera +30% de daño mientras una Furia da
  +100% serían dos sistemas para una idea. **Nunca caduca y solo hay uno
  vivo**: su fila de evento pesa 0 mientras el grupo `springs` no esté
  vacío, igual que el cupo de altares (una fila que dispara y no hace nada
  quema toda la ventana de evento).

### Ciclo de vida y UI

El pickup se parenta con `RunRoot.stage_parent`, está en `powerup_pickups`
(que `_free_stage_props()` limpia y `Stage sweep:` cuenta como
`pickups=`), se une solo a `map_markers` con `map_marker_kind()` →
`&"powerup"` y su propio `map_marker_color()`. Vive 45 s (la estrella 60):
el mapa ya carga decenas de marcadores tarde en una etapa y un pickup
eterno solo engordaría esa pila.

En el HUD, una fila de fichas **sobre la barra de HP** con los segundos
que quedan (jugador 1; en co-op los compañeros llevan un contador `◈N` en
su fila compacta), y el mapa de Tab lista «Power-ups» con sus segundos.

## Clima y eventos

Las lunas, las lluvias y los desastres son **un solo canal**: el
`WeatherDirector` (`scripts/world/run/director/weather_director.gd`, nodo
`RunSystems.tscn > WorldDirector > Weather`, donde se ajustan sus exports).
El `WorldDirector` le pasa el `StageLayout` de la etapa y reenvía a él los
hooks de grupo (`start_sky_event`, `spawn_acid_pool`). En código se llama
**weather**, nunca «event»:
`EVENT_LIBRARY` es la tabla de POIs del tick de eventos y los dos sentidos
chocarían en cada lectura. La palabra que ve el jugador sigue siendo
«evento» (el altar invoca uno).

**`active_weather` guarda como mucho una fila** (`{id, group, time_left}`),
así que «solo una luna, lluvia o desastre a la vez» es una propiedad de la
estructura de datos y no un acuerdo entre tres temporizadores.

### El catálogo

| id                 | grupo    | duración | sigue a         | notas                                        |
| ------------------ | -------- | -------- | --------------- | -------------------------------------------- |
| `blood_moon`       | moon     | 45 s     | → `full_moon`   | tinte rojo, variante `berserker` del spawner |
| `eclipse`          | moon     | 45 s     | → `full_moon`   | tinte violeta, variante `shade`              |
| `full_moon`        | moon     | 40 s     | _solo secuela_  | XP y suerte temporales                       |
| `enemy_rain`       | rain     | 35 s     | → `golden_rain` | 3-6 enemigos cada 1.5 s                      |
| `radioactive_rain` | rain     | 40 s     | → `golden_rain` | charcos ácidos                               |
| `golden_rain`      | rain     | 40 s     | _solo secuela_  | ×2 puntos y mitad de precio                  |
| `enemy_tsunami`    | disaster | 3 s      | —               | una ola, puede repetirse                     |
| `earthquake`       | disaster | 25 s     | —               | sacudida + HUD desplazado                    |
| `meteor_shower`    | disaster | 30 s     | —               | zonas marcadas, luego impacto                |

La tabla es `WEATHER_CATALOG`, en `weather_catalog.gd` (`WeatherCatalog`; su encabezado dice qué campos se editan libremente). Campos
de fila: `id`, `group`, `weight` (dentro de su grupo), `duration`,
`start`/`tick`/`stop` (nombres de método de `WeatherDirector`, `tick` y `stop`
opcionales; el lint `director_methods` comprueba que existan), `follow_up` y
`follow_up_only`.

- **Duración**: `weather_duration_overrides` (export del `WeatherDirector`,
  por id; hay un solo director por partida, así que vale para todas las
  arenas, igual que `event_weight_overrides` del `WorldDirector`) y, **solo
  para lunas y lluvias**, `RunState.sky_duration_multiplier`. Los desastres
  son fijos: un pacto que vende «lunas más largas» no debe vender también una
  lluvia de meteoritos más larga.
- **La tirada del tick de eventos** va del grupo más raro al más común:
  desastre (`disaster_chance` 0.08 + `RunState.disaster_chance_bonus`),
  luego lluvia (`rain_chance` 0.12 + `event_chance_bonus`), luego luna (la
  fórmula de siempre + `event_chance_bonus` + por uso demoníaco). Así un
  desastre no queda aplastado por lluvias y lunas más frecuentes.
- **`sky_event_min_gap` vale para los tres grupos**: la exclusividad es
  «una a la vez», el gap es «no una detrás de otra».
- **Las secuelas** arrancan sin gap y **sin restaurar el cielo primero**:
  restaurar lanzaba un tween de 2 s compitiendo con el de 1.5 s de la
  secuela sobre las mismas propiedades, y ganaba el largo.

### La entrada forzada

**`start_sky_event(kind)` sigue siendo el hook público del grupo** y ahora
FUERZA una fila: para lo que esté corriendo (con su `stop`, nunca a la
brava) y arranca aunque el gap no haya pasado. Es la misma puerta para
tres llamadores: el probe tras cada cambio de etapa (que es lo que mide la
puerta `CIELO_TRAS_AVANCE` de `verificar.sh`), `BONK_WEATHER_NOW` y el
altar de eventos. Un invocador que no hiciera nada por el gap se leería
como roto.

**Las lunas conservan su log literal `Sky event: %s for %.0fs`**, que es lo
que esa puerta cuenta. Las lluvias y los desastres no lo imprimen: no
tiñen nada de lo que esa puerta habla.

### Desmontaje

El `stop` de la fila viva corre desde `WeatherDirector.end_stage()` —que
llaman `WorldDirector.on_stage_ended()` y el `_exit_tree()` del propio
`WeatherDirector`— **antes** de `SkyTint.snap_back()`: una lluvia dorada que
terminara con la etapa dejaría un multiplicador de puntos ×2 en cada raider
y un descuento de 0.5 en `RunState`, y los dos sobreviven a la arena.
`begin_stage()` (desde `on_stage_started(arena)`) arranca con el canal vacío, y `RunState.reset()`
devuelve `price_discount` a 1.0.

### Las lluvias

- **`enemy_rain`**: cada 1.5 s elige 3-6 puntos caminables a 12-25 m de un
  raider al azar, los telegrafía (`Telegraph.spawn_disc`, 1 s) y genera un
  enemigo **a ras de suelo** por `EnemySpawner.spawn_at_points()`. **No
  caen desde altura**: un cuerpo cayendo es un cuerpo con velocidad
  vertical fuera del suelo, que es justo lo que el detector de voladores
  del harness existe para atrapar — y ese detector es deliberadamente
  estrecho y no se ensancha por decorado. La «caída» es el disco más una
  ráfaga descendente.
- **`radioactive_rain`**: cada muerte deja un charco ácido en el cadáver
  (`EnemyLoot.drop_acid_pool` → `WorldDirector.spawn_acid_pool`, que reenvía
  a `WeatherDirector.spawn_acid_pool`), más uno
  extra cada 2 s cerca de un raider. `AcidPool` (`scripts/fx/acid_pool.gd`,
  fila `acid_pool` en `Pools`, grupo `acid_pools`) **tiene su propio tick de
  daño**, a diferencia de `BloodPoolFx`, que es solo cosmético porque
  `blood_vial.gd` lleva sus ticks: aquí no hay arma detrás, y un charco que
  necesitara un ticker externo obligaría al director a llevar una lista —
  y esa lista sería lo que se filtra en un cambio de etapa. **Solo daña
  raiders**: ácido que también derritiera a la horda haría del peor clima
  del juego el mejor sitio donde estar. Tope duro `MAX_LIVE_ACID_POOLS` 24
  y separación de 3 m; lo que pasa de ahí **se salta en silencio** (un
  `WARNING:` haría fallar el soak por funcionar como está diseñado, y subir
  el tope no es un arreglo).
- **`golden_rain`** (solo como secuela): `set_points_source("golden_rain", 2.0)`
  en los grupos `player` **y** `downed_players`, y `RunState.price_discount`
  0.5 leído por `chest_price()`, `roulette_price()` y el precio del
  manantial — y por tanto por el vendedor de objetos, que cotiza su
  mostrador con `chest_price`. **Fuera**: el vendedor de power-ups y el
  precio de mascotas, que son la economía larga de la partida.

### Los desastres

- **`enemy_tsunami`**: una ola. Anuncia el lado («desde el norte»…) y vierte
  `tsunami_base` 40 + 4 × minuto de etapa enemigos en trozos de 6 por frame
  a lo largo de un arco de ~60° a 40-60 m, y termina sola. Puede volver a
  salir más tarde.
- **`earthquake`**: `Juice.shake` cada 0.5 s, polvo en cada raider cada 3 s
  y **el `offset` del CanvasLayer del HUD** oscilando ±14 px a 20 Hz — una
  sola escritura mueve barras, reloj, tiras de equipamiento y los minimapas
  de cada vista, que es lo que significa «los sprites se mueven». El mapa
  de Tab vive en otra capa y se queda quieto a propósito: un mapa temblando
  sería ilegible. `stop` lo devuelve a cero.
- **`meteor_shower`**: cada 0.8 s marca una zona (disco naranja, 1.2 s) y
  luego impacta: los raiders dentro reciben 40 × (1 + minuto × 0.05) y los
  enemigos **el triple**. Un desastre que solo dañara al equipo sería un
  impuesto, y uno que solo dañara a la horda un regalo; siendo los dos, lo
  que se castiga es quedarse quieto. Tope `MAX_LIVE_TELEGRAPHS` 16.

### El altar de eventos

`scripts/world/interactables/event_altar.gd` (`EventAltar extends Interactable`, escena
`scenes/world/shrines/EventAltar.tscn`, `marker_kind = &"event_altar"` guardado
en la escena, gratis, un solo uso, se hunde). El pedestal, el cristal y la luz
son nodos de la escena; `glass_color` los tiñe. Invoca una fila al azar
**excepto `golden_rain` y `full_moon`**: esas dos son lo que paga haber
sobrevivido a una mala, y un altar que las regalara dejaría sin sentido a
las lluvias y lunas que las ganan. Si ya hay clima corriendo, **rechaza** en
vez de encolar. Log `Event altar used: <id>`.

### La insignia del HUD

Debajo del reloj (`HUD.tscn > TimerLabel > WeatherBadge`,
`scripts/ui/game/hud/weather_badge.gd`): nombre y segundos restantes,
teñida por **grupo** (tres colores leen como tres tipos de problema; nueve
leerían como decoración). Los nombres visibles (`weather_names`) y los
colores por grupo (`group_colors`) son exports de ese nodo. La lee del
director en vez de que el director la empuje: es una vista, y un push
necesitaría una señal disparada desde tres grupos distintos.

## Poseídos (Báculo de nigromante)

Lo que mata el báculo **se levanta de tu lado**.

- **El cadáver muere entero primero.** `Health.died` es síncrona, así que
  cuando `deal_damage` regresa `EnemyBase._on_died` ya corrió: gema de XP,
  puntos, orbes, tirada de cofre de élite y bestiario, todo pagado. El
  siervo es una **copia nueva** de la misma escena en el sitio del muerto,
  así que la baja es baja **y** siervo, nunca una en lugar de la otra.
- **Un siervo no paga nada al expirar.** Ya pagó una vez como cadáver, y
  un arma capaz de cobrar dos veces por el mismo cuerpo dejaría a las demás
  en ruido estadístico. `_on_died` corta todos los pagos cuando el cuerpo es
  un siervo (tiene `EnemyPossession`, creado por `make_possessed`) y conserva
  solo la muerte visual.
- **Solo pueden ser poseídos los cuerpo a cuerpo.** El contrato es
  `EnemyBase.possessable` y el interruptor real es
  **`_pick_target() -> Node3D`**, que `_physics_process` usa en vez de
  llamar a `Coop.nearest_player` directo: todo lo de abajo (el seek, el
  encaramiento y `_combat_tick`, que daña la `Health` que le den) ya es
  agnóstico del objetivo, así que ese único override cambia el bando.

| Script                                               | ¿Poseíble? | Por qué                                                                        |
| ---------------------------------------------------- | ---------- | ------------------------------------------------------------------------------ |
| `grunt`, `tank`                                      | **sí**     | su `_combat_tick` daña `Health.find_in(target)`, sea quien sea                 |
| `skirmisher`                                         | no         | dispara `EnemyBolt`s que solo dañan al grupo `player`                          |
| `sunspitter`                                         | no         | su rayo se filtra por el mismo grupo                                           |
| `duneburrower`                                       | no         | guarda y restaura sus propias capas y grupo en cada ciclo de excavación        |
| `boss_base` (y `rotking`, `sarcognath`, `fenwraith`) | no         | los jefes llegan al equipo por `damage_players_in_disc` / `Coop.alive_players` |
| `secret_boss_base` (y `grubthing`, `coffer_mimic`)   | no         | un minijefe secreto es un jefe, y su muerte desbloquea un raider               |

- **Capas**: el siervo sale del grupo `enemies` (que declara la escena), lo
  que de una sola vez lo esconde de las armas del jugador, del conteo vivo
  del spawner y del tiempo detenido — los tres leen ese grupo. Pasa a
  `collision_layer` 8 con máscara 1 (terreno) **más una excepción explícita
  por raider**: los jugadores comparten la capa 1 con el mundo, así que una
  máscara que lo dejara atravesar raiders lo dejaría atravesar el suelo.
- **Cupo** `max_possessed` 12 por portador (export del Báculo, `necro_staff.gd`); el más viejo expira para hacer
  sitio (un cupo que rechazara al nuevo se sentiría roto justo cuando el
  arma funciona). Expira también si el portador muere y en cada cambio de
  etapa. Logs `Possessed spawned:` / `Possessed expired:`.

## Bloques de la suerte

`scripts/world/interactables/lucky_block.gd` (`LuckyBlock extends Interactable`, escena
`scenes/world/chests/LuckyBlock.tscn`, grupo `lucky_blocks`, `marker_kind`
`&"lucky_block"` guardado en la escena). El bloque, el «?» y la luz son nodos
de la escena; `block_color` tiñe el bloque y la luz, y los premios y textos
son exports (grupos «Premios» y «Textos del pozo»). Parece un cofre y no lo es: **gratis, raro y
siempre paga algo**. No hay precio ni rareza — el objeto entero es la
sorpresa, y por eso todos los premios son buenos y se diferencian en
**tipo**, no en tamaño.

`LUCKY_REWARDS` es una tabla con pesos y una rama cada uno: `enemy_explosion`
(todo lo no-jefe a 12 m muere; los jefes pierden 15% de HP máx.), `gem_rain`
(25 gemas), `points` (+80), `free_chest`, `powerup` (nunca la estrella) y
`well`.

**El pozo** es el único premio que hace una pregunta: ofrece hasta 3 de tus
objetos más «Nada» por `open_choice`, y entregar uno devuelve un objeto de
la rareza siguiente (Legendario se queda en Legendario) o, un 30% de las
veces, un power-up. **Sin objetos paga un power-up y no abre menú**:
`open_choice` retorna sin hacer nada con una lista vacía, y un bloque que se
quedara callado se leería como roto. Log `Lucky block: <premio>`, uno por
apertura, nombrando lo que de verdad se pagó.

## Misiones y meta-progresión

- Qué es: misiones que pagan esquirlas; las esquirlas compran personajes y rangos de reliquia de la Armería. Todo persiste en `user://save.json`.
- Archivos: `scripts/systems/catalogs/quest_catalog.gd` (`QUEST_LIBRARY`, 39 filas), `scripts/systems/autoloads/save_data.gd` (autoload `SaveData`), UI: `scripts/ui/meta/quest_log.gd`, fin de partida: `scripts/systems/run_manager.gd`.
- Fila de misión: `id`, `display_name`, `description` (imperativo, tuteo), `stat` (id de contador — **lista canónica en la cabecera de `save_data.gd`**), `target`, `reward`. Un contador nuevo no necesita registro: `bump` crea la clave.
- **Contrato transaccional**: los sistemas en partida acreditan con `SaveData.bump(id)` / `raise_to(id, valor)`, que caen en un **buffer de partida** (`_run_counters` / `_run_highs`). Solo el fin de partida lo funde en el ledger persistido (`fold_run_results`); `RunState.reset()` lo descarta. Consecuencia observable y deliberada: **abandonar una partida con «Salir al menú» no deja rastro de nada** — ni `bosses_killed`, ni `chests_opened`, ni `used_weapon_<id>` para la Colección —, así que esos contadores no se pueden farmear sin terminar partidas.
  - `stat(id)` lee ledger + buffer (para mostrar progreso); la **evaluación de misiones lee solo el ledger**, así que una misión nunca se marca completa con contadores que un abandono va a revertir.
  - Firma: `fold_run_results(victory, character_ids, visited_map_ids, cleared_map_ids, stages_cleared, laps, level, kills, run_seconds)`. Una partida recorre **varios** mapas, así que `runs_on_<map>` se acredita por cada mapa **visitado** y `victories_<map>` por cada mapa **superado** — así `dunes_run_1`, `fen_win_1` y compañía siguen funcionando sin tocarlas. `victory` significa «superó al menos una etapa». Los `Array[String]` tienen que ir **tipados**: un literal sin tipo lanza `Invalid type in function`.
  - Las misiones de grado conservan sus ids (`tier2_win`, `tier3_win`) pero ahora son de **vueltas** (`laps_completed`), y las de `best_endless_minutes` cuentan el tiempo en **pseudo-infinito**. Las claves que este build ya no conoce (`tier_choice`, `victories_<map>_t<n>`, ids de misiones borradas) simplemente no se leen: un guardado viejo carga limpio y en silencio.
  - **Ids de personaje renombrados**: `SaveData.ID_ALIASES` traduce al cargar los ids viejos (desbloqueos y contadores `runs_as_<id>` / `wins_as_<id>`), imprime `Save migrated: <n> character id(s)` y reescribe el archivo una vez, dejando el anterior como `.bak`.
- Escritura en disco: `save()` escribe en `<save>.tmp` y solo renombra al terminar, dejando el anterior como `.bak`. Una escritura interrumpida no puede truncar el archivo real; `load_from_disk()` cae al respaldo e imprime `Save recovered from backup:`.
- El cobro de misiones es manual en el Registro (`claim_quest`). Los harness pueden re-apuntar `SaveData.save_path` a un archivo temporal **antes** de `load_from_disk()`.

## Evoluciones de armas

- Qué es: cada carta invertida en un arma es un nivel de arma (`WeaponBase.upgrade_level`); cada múltiplo de `EvolutionCatalog.EVOLVE_AT_LEVEL` (**10**) es un **hito**. El primero evoluciona el arma si tiene receta; los siguientes —y también el primero para un arma sin receta— son **ascensos**: un escalón plano sin fila de catálogo (`WeaponBase.ASCEND_MULTS`: daño ×1.15, `cooldown_scale` ×0.9, alcance ×1.1, y +1 proyectil en los tiers pares). Así ningún arma deja de mejorar nunca. No intervienen cofres ni tomos.
- `WeaponBase.ascension_tier` cuenta los hitos pasados (la evolución del nivel 10 es el tier 1). El HUD pinta `N%d` (nivel) por debajo del primer hito y `★%d` (tier) desde ahí.
- Archivos: `scripts/systems/catalogs/evolution_catalog.gd` (`EVOLUTION_LIBRARY`, 15 filas, indexada por `weapon_id`; `try_advance_by_level`), `scripts/weapons/weapon_base.gd` (`upgrade_level`, `ascension_tier`, `evolve()`, `ascend()`, y el aplicador genérico `_apply_stat_tables` que comparten), `scripts/systems/catalogs/upgrade_pool.gd` (`apply` llama a `try_advance_by_level` tras cada carta de arma), `scripts/systems/catalogs/evolution_ceremony.gd` (`EvolutionCeremony.play_evolution` / `play_ascension`: fanfarria, sparkle, shake y banner; sus textos y números son consts al principio del archivo) y el banner del HUD (`announce_major`, que `hud.gd` reenvía a `scripts/ui/game/hud/announce_banner.gd`).
- Ceremonia compartida por ambos hitos (fanfarria, sparkle, shake) + banner propio: «¡%s evolucionó a %s!» y «¡%s asciende!». Logs `Weapon evolved:` y `Weapon ascended: <arma> tier <n>`.
- Evolución nueva: una fila con `weapon_id`/`weapon_node`, `evolved_name`, `mults`/`adds` (aplicados genéricamente sobre cualquier propiedad del arma vía get/set) y `flavor` para la Colección. El banner busca el `display_name` traducido en `WEAPON_LIBRARY`, no capitaliza el id. La ceremonia bumpea `evo_<weapon_id>` + `evolutions_total` e imprime `Weapon evolved:`. El nombre del banner sale de `WeaponCatalog`. **Bug conocido, sin arreglar**: el banner de evolución lee el nombre del arma **después** de `evolve()`, así que dice «¡Mandoble del Caudillo evolucionó a Mandoble del Caudillo!» en vez del nombre base primero (el arreglo, que cambia un texto visible, es leer el nombre antes de `weapon.evolve(row)` en `EvolutionCatalog.try_advance_by_level`).
- Los catálogos tienen funciones `static`; para alcanzar autoloads desde ahí usan **un** helper compartido, `AutoloadLookup.find(nombre)` (`scripts/systems/catalogs/autoload_lookup.gd`), no `Engine.get_main_loop()` repetido.

## Cartas de mejora: multi-stat y topes

- Una entrada del pool puede llevar `effects: [{property, op, amount}, ...]` en vez del trío `property/op/amount`: todos los efectos caen sobre el mismo `target` en una sola carta y la descripción lleva un `%d` por efecto. Las cartas por arma son las filas de `UpgradePool.WEAPON_STAT_CARDS` (daño, velocidad de ataque, alcance, y «Temple» y «Ritmo de batalla» como filas con `effects`): `_entries_for_weapon` copia cada fila con el id y el `target` del arma y añade los `extra_entries` de su fila de `WeaponCatalog`.
- Las descripciones genéricas **no nombran el arma** («Aumenta el daño en un %d%%»): la carta muestra el arma en su propia etiqueta.
- Topes por jugador: `Player.max_weapons` (3) y `Player.max_tomes` (3 tomos **distintos**; al llegar, el pool solo ofrece stacks de los ya poseídos — `PlayerStats.distinct_tome_count()`). **No hay tope de stacks ni de nivel de arma**: un tomo se apila indefinidamente y `Tome.stack_label(n)` construye el numeral romano para cualquier `n`, tanto en el título de la carta como en la esquina del HUD.
- **Un lado por subida de nivel**: cada carta de nivel ofrece _o_ armas (cartas de arma poseída + `new_weapon`) _o_ tomos/stats (entradas de tomo + `GENERIC_POOL`), nunca mezclado. `UpgradePool.roll_side(player)` elige el lado al azar ponderado por cuántas entradas tiene cada uno y jamás devuelve un lado vacío; `build_pool(player, side)` lo materializa y el título de la UI lo nombra («Nivel 7 — elige: Armas»). Los picks de bonificación (`open_bonus_pick`: cofres, santuarios) pasan `side = ""` y siguen mezclando.
- **Curva de XP** (`RunState._xp_required`): lineal más un término cuadrático (`XP_PER_LEVEL_SQUARED`); el nivel 10 cuesta 50 y el 20 cuesta 125.
- Rareza: `Rarity.TIERS[].name` (`scripts/systems/catalogs/rarity.gd`) es un **identificador** (`Common`/`Rare`/`Epic`/`Legendary`) que llavea precios de cofre, el campo `rarity` de `ITEM_LIBRARY` y los pisos `min_rarity`. Para pintarla, `Rarity.display_name(id)` (`UpgradePool.rarity_display` reenvía ahí) — ver Convenciones.
- Curva de suerte: `Rarity._weights(luck)` mueve hacia las rarezas superiores una fracción del peso de Común que crece con la suerte (`LUCK_TILT_PER_POINT`) y se acerca a `MAX_LUCK_TILT` (0.5) sin cortarse en seco, así la suerte sigue sirviendo por encima de 50 (consts al principio de `rarity.gd`).

## Colección, Armería y modos meta

- **Colección** (`scripts/ui/meta/collection.gd` + `scenes/ui/Collection.tscn`, `extends MetaScreen`): lee contadores de `SaveData` — `used_weapon_<id>` (bump en `Player._apply_character` y `UpgradePool._grant_weapon`), `evo_<id>`, `kills_<script>` (bump en `EnemyBase._on_died`, keyed por nombre de archivo del script — un enemigo nuevo entra al bestiario añadiendo su fila a `BESTIARY` en `collection.gd`). Recuerda el contrato transaccional: una partida abandonada no registra nada aquí.
- **Armería / reliquias** (`scripts/systems/catalogs/relic_catalog.gd`, `scripts/ui/meta/relic_shop.gd`, `extends MetaScreen`): 6 reliquias de stats permanentes por rangos; `SaveData.relic_ranks` + `purchase_relic()`; `PlayerStats._apply_relics()` las aplica en cada `recompute()` por el mismo canal `_apply_effect` que los tomos. Reliquia nueva = una fila (id de stat de `_apply_effect`).
- **Registro de misiones** (`scripts/ui/meta/quest_log.gd`, `extends MetaScreen`): filas con `enum RowState`.
- **Cacería diaria**: `GameConfig.daily_mode/daily_seed/daily_date`; `RunState.reset()` siembra el RNG global con la semilla y `scatter.gd` la adopta, así cartas/spawns/layout/máscara son deterministas por fecha. Score en `GameConfig.daily_score` (estática); `RunManager` lo registra (`daily_best_<fecha>` vía `raise_to`, `daily_runs`). Log `Daily run scored:`.
- **Partida sin reloj**: `RunManager` no termina la partida por tiempo: sigue hasta que cae toda la party o alguien se extrae. `extract_run()` (grupo `run_manager`, lo llama el botón **Extraerse** del `PauseMenu`) cierra la partida con el fold normal. Todo final con **al menos una etapa superada** cuenta como victoria (`stage_goal` 900 s + jefe de etapa, ver «La puerta de etapa»). `RunEndScreen` titula EXTRACCIÓN LOGRADA / INCURSIÓN ABANDONADA cuando alguien sigue en pie. `survival_text` es el aviso del momento en que se supera una etapa y no lleva marcadores de formato.

## Objetos y puntos de partida

- Qué es: economía por jugador dentro de la partida. Cada muerte paga `EnemyBase.points_value` (shiny x5; jefes: `points_value` = 25 guardado en cada escena de jefe, escalado por `apply_tier`) al raider **más cercano** (`Player.add_points`, señal `points_changed`; el saldo vive en el nodo `Wallet` del Player, `scripts/player/components/player_wallet.gd`, y se reinicia cada partida).
- Archivos: `scripts/systems/catalogs/item_catalog.gd` (`ITEM_LIBRARY`, 16 filas), `scripts/systems/item_bag.gd` (`ItemBag`, nodo del Player junto a `Stats`), `scripts/world/interactables/chest.gd`, `scripts/systems/autoloads/run_state.gd` (`chest_price`, `register_chest_opened`, `CHEST_BASE_PRICES`, `CHEST_PRICE_GROWTH`).
- Objeto nuevo: una fila con `id`, `display_name`, `rarity` **fija en inglés** (un `name` de `Rarity.TIERS`), `glyph` (sigla de dos letras del nombre **español**; `icon` opcional con ruta a textura), `description`, y opcionalmente `effects` y/o `kind` (`magnet`, `poison_on_hit`, `titan`, `spiders`, `shock_dash`, `saiyan`, `zenkai`, y los de santuario `demonic_boost`, `charge_boost`, `portal_recharge`). **Los números de cada objeto viven en su fila** y llenan la descripción por `text_values` (`RowText`): cambiar el número cambia también el texto. Los ids por `kind` se resuelven con el helper del catálogo, no con literales repetidos. No hay kind `pet`: las mascotas son un slot del Player.
- `ItemBag.remove_item(item_id) -> bool` devuelve UNA copia (lo usa el pozo del bloque de la suerte) y repite los tres seguimientos de `add_item` en el mismo orden: reescala el titán, pide `recompute` y emite `items_changed`.
- **Tres objetos de comportamiento**, cada uno un `kind` con una rama:
  - **Cinturón eléctrico** (`shock_dash`): el Player emite `slide_started(direction)` y la bolsa engancha ahí — el derrape no tenía señal porque nada fuera del Player necesitaba saberlo. El rayo salta desde `carrier_player().global_position`, **nunca** desde la bolsa (`ItemBag extends Node`, no tiene transformada: un `Node3D` hijo suyo se queda en el origen del mundo). Pega con `scripts/weapons/belt_bolt.gd` (`BeltBolt extends WeaponBase`, hijo **de la bolsa** y no del montaje `Weapons`, así que ni la tira del HUD ni el tope de armas ni el pool de mejoras lo ven; su rayo es `scenes/fx/LightningBeam.tscn` con el estilo del cinturón), de modo que `deal_damage` le da crítico, robo de vida y los hooks de muerte gratis. Log `Belt bolt: hits=%d`.
  - **Sangre sayayin** (`saiyan`): cuenta bajas y cada 40 (×0.85 por copia, piso 15) enciende 12 s de aura con boons **etiquetados** (`tag = "saiyan"`, así un re-disparo se reemplaza en vez de apilarse) y una carcasa dorada por `material_overlay` a la manera de `Juice.flash` — **nunca** `SealRig.apply_tint`, que es el color de identidad del personaje. Log `Saiyan aura:`.
  - **Zenkai** (`zenkai`): **se arma** con `Health.damaged` por debajo del 10% (es la única señal que significa «algo me hizo daño»: `take_damage` no emite `hp_changed`) y **dispara** con `hp_changed` por encima del 50%. Ignora las señales levantadas durante un `recompute` — `_push_bonus_max_hp_to_health` escribe `max_hp` y cura desde dentro de ese cuerpo, y sin la guarda `PlayerStats.is_recomputing()` el objeto se dispararía con su propia reconstrucción, para siempre. Los stacks son un canal permanente de todas las estadísticas (+8% cada uno). Log `Zenkai triggered:`.
- Hooks de arma: `WeaponBase.deal_damage` avisa a la bolsa del portador con `on_weapon_hit(body)` y `on_weapon_kill(pos, weapon)`. `Projectile.extra_on_hit` + `tint()` sirven para proyectiles especiales (arañas).
- Cofres — **dos modos**:
  - **De pago**: `rarity` fija en la instancia o tirada en `_ready` (pesos de rareza + `luck_bonus` de la party, piso `min_rarity`); el tinte y el precio se fijan ahí para que se lean a distancia. Precio = base por rareza × multiplicador global que crece x1.25 con **cada** cofre de pago abierto.
  - **Gratis** (`free_open`): precio 0, prompt «[E] Abrir cofre — gratis», **no** llama `register_chest_opened()` (un cofre gratis no encarece los de pago), y su rareza se tira **al abrirlo** con la suerte de quien abre — sin piso, así que cualquier rareza es posible. Sin rareza sellada no tiene color de rareza: lleva su propio tinte blanco-dorado (export `free_tint`). Son gratis todos los cofres soltados por un cuerpo (`EnemyBase.spawn_chest`: shiny y anillo de jefe — los del jefe ya **sin** piso `Rare`, conservando el bono de suerte por uso demoníaco), el cofre del pacto demoníaco y el del bloque de la suerte (los dos por `Chest.spawn_free(tree, en, suerte_extra)`), y una parte de los cofres de inicio (`StageFixtures.free_start_chest_chance` ≈ 15%; los de escena se convierten con `Chest.make_free()`, que reimprime el tinte). Los cofres de suministro del director siguen siendo de pago.
  - **Todo cofre se hunde y se libera** tras entregar el premio (`Interactable.sink_away()`, con `sink_depth` en `Chest.tscn`), de pago o gratis. El brillo por rareza (`glow_energy_by_rarity`, `lit_rarities`, nodo `Visual/GlowLight`), los tiempos de apertura y los textos del prompt son exports de `chest.gd`. `WorldDirector._despawn_chest` y las balizas están protegidas contra una instancia ya liberada. Log `Chest opened:`, con ` (free)` al final cuando fue gratis.
- HUD: insignia de puntos (`%PointsLabel`, abajo a la derecha, sobre la tira de objetos) y dos tiras de equipamiento, nodos `BuildStrip` (armas y tomos, abajo a la izquierda) y `BagStrip` (objetos, abajo a la derecha) de `HUD.tscn`, ambos con `scripts/ui/game/hud/loadout_strip.gd` (sondeo cada `refresh_seconds` 0.5 s): armas con nivel (★ si evolucionada), tomos con numeral de stack, objetos con copias. Cada casilla es una instancia de `scenes/ui/hud/LoadoutTile.tscn`.

## Santuarios, cofres y secretos

- Qué es: interactuables de mundo con prompt flotante y acción `interact`.
- Archivos: base `scripts/world/interactables/interactable.gd` (`Interactable extends Area3D`); `chest.gd`, `charge_shrine.gd`, `curse_shrine.gd` (extiende `ChargeShrine`), `greed_shrine.gd`, `spring_shrine.gd`, `roulette_shrine.gd` + `scripts/ui/game/roulette_ui.gd`, `portal_shrine.gd`; secretos: `secret_trigger.gd`, `odd_stump.gd`, `humming_skull.gd`, `scripts/enemies/secret_boss_base.gd`.
- Contrato `Interactable`: sobreescribir `_interact(player)` (y opcionalmente `_on_range_entered()` / `_on_range_exited()`); llamar `consume()` al gastarse (bumpea `meta_stat_id` y apaga el prompt); `dim_visuals()` para el gris de «usado» (`spent_color`); `sink_away(keep_alive)` para hundirse y liberarse (exports `sink_duration`, `sink_depth`, `sink_end_scale`, que cada escena ajusta); `_emit_completed()` da destello + sonido (`complete_sound`).
- **Quién está en el anillo**: `_players_in_range` es la lista real; `player_in_range` es solo «alguno». Un raider **derribado sigue en la lista** (su cuerpo nunca sale del árbol, así que `body_exited` no dispara): para saber quién puede sostener un ritual, usar **`live_players_in_range()`** y `nearest_live_player()`. `best_kind_count_in_range(kind)` da el mejor conteo de copias de un `kind` de objeto entre los presentes.
- **Prompts**: el texto por defecto de cada interactuable es su `prompt_text`, guardado en su escena; el tamaño, el contorno, el color y la altura del aviso flotante son los exports del grupo «Aviso flotante» de `Interactable`. El botón se escribe como el literal `[E]` (`Interactable.INTERACT_TOKEN`), que la etiqueta sustituye por el glifo del control (`[Y]`) según el slot que esté en el anillo. Un prompt nuevo **tiene que** escribir `[E]` literal para que el token funcione.
- **Audio en loop**: `_hold_loop(id)` / `_drop_loop()` sobre `Sfx.acquire_loop`/`release_loop`, con refcount y una liberación extra desde `_exit_tree`, así un abandono a mitad de canalización no deja la voz sonando.
- **Altares**: _Carga_ se carga solo mientras un jugador está en el anillo. **No hay sobresaltos de spawn, ni caducidad, ni renuncia**: salir del anillo solo **pausa** la carga y volver a entrar la reanuda; un altar que nadie toca espera para siempre. **Todos** los altares se hunden tras pagar (`spent_lifetime`), de escena o del director. El anillo es grande (zona 9.3 en `ChargeShrine.tscn`, 7.8 en `CurseShrine.tscn`) y se **marca al acercarse**: dentro de `approach_band_scale` (2×) radios —medidos sobre la forma de la zona, `_measure_zone_radius()`— el anillo y el disco brillan y laten, con materiales **por instancia** (`_own_material` duplica el material de la escena y lo tiñe con `accent_color`, porque un `[sub_resource]` es un objeto compartido). El disco de progreso es el nodo `Visual/ProgressDisc` de cada escena. El color de cada altar es su export `accent_color` (azul el de carga, rojo el demoníaco, guardado en `CurseShrine.tscn`). Todo `ChargeShrine` se une al grupo `altars`.
  - Al completar, el altar **no reparte un boon al azar**: abre un menú de 3 opciones distintas de `ALTAR_BOONS` en el propio `UpgradeCardUI` (`open_choice`, ver UI) con el raider que sostuvo el anillo como destinatario explícito. Lo elegido llega a **toda la party** — `player` **y** `downed_players` — vía `ChargeShrine.grant_boon` → `PlayerStats.add_altar_boon`, escalado por `_effective_boon_scale()` y las Llaves maestras. Log `Altar charged:` (lo cuenta `verificar.sh`).
  - _Demoníaco_ hereda el ritual y sustituye las opciones por **pactos** (`CurseShrine.PACT_LIBRARY`): cada carta es un **beneficio** (boon grande ~2× el de altar, puntos de partida, o un cofre gratis ahí mismo) más un **costo** que escribe knobs de `RunState` (`add_difficulty`, `elite_chance_bonus`, `sky_duration_multiplier`, `event_chance_bonus`, `disaster_chance_bonus`). Beneficio y costo son filas `{kind, ...}` con **una rama por kind**, nunca un caso especial por id. Mantiene `demonic_uses += 1`, el escalado por Sangre de demonio (`_blood_scale()`, vía el hook virtual `_effective_boon_scale()`, no mutando el `@export` del padre) y los logs `Demonic altar used:` y `Demonic pact:`.
  - `WorldDirector` ya no da vida a los altares: los siembra por el tick de eventos con **cadencia creciente** (el hueco entre eventos se comprime con el minuto hacia `event_gap_floor` ≈ 20 s, y el peso de las filas marcadas `altar` sube con `altar_weight_per_minute`) y un **cupo de altares sin gastar** que crece con el minuto (`altar_cap_base + minuto / altar_cap_minutes`); al tope, el peso del altar cae a 0 y la tirada elige otro evento. La baliza de un altar vive hasta que el altar se gasta (`TimedBeacon` con `INF` + `poi_worth_showing()`). Log `Altar placed: <kind>`. _Codicia_: apuesta de HP (log `Greed shrine:`). _Manantial_: precio fijo en puntos, `heal_full` + **un power-up al azar** vía `PowerUps.apply(PowerUpCatalog.roll_id(true))` — nunca la estrella, y duran 20 s. _Ruleta_: `RouletteShrine.price` es la **base**; cada giro **duplica** el precio para el resto de la partida y para toda la party (`RunState.roulette_price_multiplier` / `roulette_price()` / `register_roulette_spin()`, reiniciado en `reset()` junto a los precios de cofre). El prompt y el botón releen `current_price()`. `RouletteShrine.OUTCOMES` (clasificador puro `outcome_for(roll)`), `apply_outcome(id, player)`; la UI (`RouletteUi`, `scripts/ui/game/roulette_ui.gd`, escena `scenes/ui/modal/RoulettePanel.tscn`, que hereda de `ModalPanel.tscn`; grupos `ui_blocking` + `blocking_ui_closable`) se instancia **bajo la raíz de la arena** (`RunRoot.stage_parent`), nunca bajo root ni bajo `current_scene`, pausa el árbol y se resuelve sola en headless. _Portal_: `StageFixtures._spawn_portals` crea `portal_count` portales emparejados (el color de cada par sale de `PortalShrine.pair_colors`; el aspecto es `PortalVisual.tscn`); E teletransporta al gemelo y ambos recargan `cooldown / (1 + 0.25 × cosmic_worm)`.
- WorldDirector: los eventos temporizados salen de un **catálogo de filas** (`EVENT_LIBRARY`: cofre de suministros / jauría shiny / grieta / altar de carga / altar demoníaco / manantial / vendedor / caja de mascotas / …), y cada fila lleva su `scene` y/o `method`, su `announce`, su baliza (`beacon_color`, `beacon_time`) y su cupo (`cap_group` + `cap`). `event_weight_overrides` cambia pesos por id para toda la partida (hay un solo director). Las balizas son `scenes/world/director/Beacon.tscn` y viven en una lista tipada con clase interna. Logs: `Altar charged:`, `Altar left:`, `Altar placed:`, `Demonic altar used:`, `Demonic pact:`, `Roulette spun:`, `Portal used:`, `Portals placed:`, `Spring used:`, `Boss chests dropped:`.
- Presión vía `call_group("enemy_spawner", "spawn_pressure_burst", centro, n)`; buff temporal de enemigos vía `apply_temp_enemy_buff(mult, s)`.
- Secreto nuevo: `extends SecretTrigger`, define la condición (Tocón raro: 3 interacciones; Cráneo zumbante: canal quieto de 4 s) y llama `_awaken()` — gasta, anuncia por `boss_ui` y spawnea `miniboss_scene` (raíz `extends SecretBossBase` con `secret_boss_id` exportado: su muerte bumpea `slain_<id>` y desbloquea el personaje cuya fila tenga ese `unlock_boss`). Logs `Secret miniboss awakened:` / `Secret boss slain:`.

## UI

- Capas (CanvasLayer): SplitScreen (capa por defecto) → viñeta de Juice 4 → HUD 5 → MapOverlay 8 → UpgradeCardUI 10 → paneles modales (vendedor, ruleta) 15 → RunEndScreen 20 → PauseMenu 30 → ScreenFade 100. Las capas de escena guardan su número en la raíz de su `.tscn`; `UiLayers` (`scripts/ui/ui_layers.gd`) solo tiene las que se crean en código (4, 8 y 100). Las rutas de las escenas entre las que navega la UI están en `ScenePaths` (`scripts/ui/scene_paths.gd`). Archivos en `scripts/ui/` + `scenes/ui/`; los componentes de una pantalla viven junto a su dueña (`scripts/ui/game/hud/`, `scripts/ui/game/modal/`, `scripts/ui/game/upgrade_card_ui/`, `scripts/ui/meta/character_select/`, con sus escenas en `scenes/ui/hud/`, `scenes/ui/modal/`, `scenes/ui/upgrade_card_ui/`, `scenes/ui/meta/character_select/`).
- **`UiTheme`** (`scripts/ui/ui_theme.gd`, todo `static`) es el sistema de diseño: la paleta compartida (`ACCENT`, `ACCENT_AMBER`, `TEXT_BRIGHT`…), radios, `style_card()` (un único constructor de tarjeta de 4 estados), `style_button`, `style_badge`, `style_bar`, `style_toggle`, `attach_motion`, `pop`, `reject()` (la sacudida de «no alcanza»), `spaced_font(spacing)` (con caché por spacing) y los textos compartidos: `LEVEL_ABBREV` («Nv %d»), `WEAPON_LEVEL_ABBREV` («N%d»), `SHARDS_BALANCE`, `POINTS_AMOUNT`, `POINTS_BALANCE`… **No inventes styleboxes nuevas en una pantalla**: si falta un estilo, se añade aquí. Los títulos de los menús se estilan **en sus escenas** (fuente, color, contorno), y los cuatro fondos de menú comparten `assets/ui/menu_backdrop.tres`.
- **`CardFactory`** arma las cartas de oferta del vendedor; **`MetaScreen`** es el chasis de Registro / Colección / Armería. Los encabezados de sección de Ajustes son nodos de `SettingsPanel.tscn`.
- **Selector de personaje** (`scenes/ui/CharacterSelect.tscn`), en cuatro piezas: `scripts/ui/meta/character_select.gd` (el cableado, la selección y el flujo de desbloqueo, el foco), `CharacterCard.tscn` (`scripts/ui/meta/character_select/character_card.gd`, las caras de cada carta; señal `unlock_confirmed`), `CoopLobby.tscn` (`coop_lobby.gd`: tamaño de la party y slots J1-J4; señales `party_changed` y `slots_rebuilt`) y `DailyHunt` (`daily_hunt.gd`, `RefCounted`: semilla del día y arranque de la Cacería diaria). Los botones Colección, Armería y Cacería diaria son nodos de `CharacterSelect.tscn`, no se construyen en código.
- **`ScreenFade`** (autoload): `transition(callable)` funde a negro, ejecuta el callable (el `change_scene`/`reload` y su limpieza) y funde de vuelta; mientras está ocupado **descarta** peticiones repetidas y devuelve `false`, así que la limpieza irreversible va **dentro** del callable, nunca antes. `leave_run(ruta)` es el **único dueño del ritual de fin de partida**: guarda ajustes, para los loops de audio, deja el árbol **pausado durante el swap** (dos frames), llama `RunState.reset()` y cambia de escena. Cualquier botón que saque de una partida debe usarlo.

### Iconos

Cada casilla de la tira de equipamiento (`scenes/ui/hud/LoadoutTile.tscn`, `scripts/ui/game/hud/loadout_tile.gd`) resuelve su arte en este orden:

1. `icon` explícito en la fila de catálogo (`WEAPON_LIBRARY`, `TOME_LIBRARY`, `ITEM_LIBRARY`), si el recurso existe.
2. **Convención por id**: `res://assets/icons/<biblioteca>/<id>.png`, con `biblioteca` ∈ `weapons`, `tomes`, `items` (más adelante `pets`, `powerups`) e `id` = el `id` de la fila de catálogo. **Para poner arte real solo hay que soltar los PNG con ese nombre**: no hay que tocar código ni catálogos.
3. `res://assets/icons/placeholder.png` con la sigla de dos letras encima.

La existencia se comprueba con `ResourceLoader.exists(path, "Texture2D")`, **no** con `FileAccess.file_exists`: en una build exportada el PNG viaja empaquetado como `.ctex` y el chequeo de archivo daría falso. El único PNG del repo es el placeholder, generado por `scripts/tools/generate_placeholder_icon.gd` (`godot --headless -s ...`, sin autoloads, hermano de `generate_sfx.gd`) y commiteado junto a su `.import`.

- HUD (`scenes/ui/HUD.tscn`, raíz `scripts/ui/game/hud.gd`): grupos `hud` y `boss_ui`. `hud.gd` se queda con las barras de HP y XP, el nivel, el cronómetro (se repinta solo cuando cambia el segundo), las bajas, los puntos y `Dificultad +N%`, todos con sus colores, formatos y tiempos como exports agrupados («Vida», «Experiencia», «Textos», «Animación»…). Al principio del archivo está la API por grupo (`announce`, `announce_major`, `show_loot`, `track_boss`, `track_objective`, `show_stage_tag`, `on_stage_started`, `set_quake_offset`), que reenvía a los componentes. Cada componente es un nodo de `HUD.tscn` con su script en `scripts/ui/game/hud/`, dueño de su propio look:
  - `StreakLabel` → `streak_popup.gd` (`StreakPopup`): las rachas de bajas, sus palabras, colores y umbrales.
  - `AnnounceLabel` → `announce_banner.gd` (`AnnounceBanner`): los avisos y los banners mayores (`announce_major`: evoluciones, etapa superada).
  - `BossBar` → `boss_bar.gd` (`BossBar`), con sus marcas `Tick1..3` y `BossNameLabel`.
  - `BuildStrip` y `BagStrip` → `loadout_strip.gd` (`LoadoutStrip`, export `contents`): armas y tomos abajo a la izquierda, objetos abajo a la derecha; cada casilla es `scenes/ui/hud/LoadoutTile.tscn`.
  - `PowerUpRow` → `powerup_row.gd` (`PowerUpRow`): las fichas de power-ups sobre la barra de HP.
  - `MatePanel` → `mate_panel.gd` (`MatePanel`): las filas compactas J2-J4 en co-op, cada una `scenes/ui/hud/MateRow.tscn` (`mate_row.gd`). El daño a un compañero **no** dispara viñeta/shake globales, solo el pop de su fila.
  - `LootToast` (instancia de `scenes/ui/hud/LootToast.tscn`, `loot_toast.gd`): el **toast de botín** (`show_loot`).
  - `FpsBadge` → `fps_badge.gd`: el **badge de FPS** opcional (`SaveData.show_fps`, Ajustes → «Mostrar FPS»; se sondea, no se escucha, porque la opción se cambia con el HUD vivo o antes de que exista).
  - `TimerLabel/WeatherBadge` → `weather_badge.gd`: la chapa de clima.
  - `PerfProbe` → `perf_probe.gd`: el overlay de rendimiento, oculto salvo con su export `enabled` o `BONK_PERF=1`.
  - `ViewWidgets` → `view_widgets.gd`: **construye y ancla** el minimapa y el mapa de Tab de cada jugador y les reenvía `on_stage_started(arena)` — ver «Minimapa y mapa (Tab)».
  - **Las posiciones son de la escena**: para mover algo del HUD se mueve su nodo en `HUD.tscn` (anclas y offsets), no se toca código. Lo que tiene que respetarse al moverlos:
  - **Arriba al centro**: el cronómetro, y **debajo de su caja** —no encima— la chapa de clima, que es hija de `TimerLabel` y cuelga de su borde inferior: si el reloj cambia de alto, la chapa lo sigue sola.
  - **Arriba a la derecha**: las bajas, la insignia de FPS y el minimapa (`ViewWidgets/MinimapSlot`) debajo de las dos.
  - **Abajo al centro**: barra de HP con su etiqueta, y la fila de power-ups **por encima**.
  - **Abajo a los lados**: las dos tiras de equipamiento (a 36 px del borde inferior), con la insignia de puntos sobre la tira de objetos.
- Flecha de jefe (`boss_arrow.gd`): `bind_view(camera, carrier)` inyecta la cámara y el raider de esa vista. Sin inyección cae al viewport raíz (solo) — ver la convención de cámaras.
- Cartas (`scenes/ui/UpgradeCardUI.tscn`, `upgrade_card_ui.gd`): en `RunState.leveled_up` pausa el árbol y ofrece 3 tiradas de `UpgradePool.roll_offer()` **de un solo lado del pool** (ver «Cartas de mejora»); los picks extra se encolan. Cada carta es una instancia de `scenes/ui/upgrade_card_ui/UpgradeCard.tscn` (`scripts/ui/game/upgrade_card_ui/upgrade_card.gd`, `UpgradeCard`: cómo se ve una carta), los tiempos de animación son exports del nodo `Motion` de `UpgradeCardUI.tscn` (`pick_motion.gd`) y la rotación de a quién le toca en co-op es `PickRecipients` (`pick_recipients.gd`).
- **`open_choice(title, options, recipient, on_pick, tag)`** es la **única** ampliación del contrato: dibuja opciones que el llamador construyó (`{title, description, color, ...payload}`) y le devuelve la elegida por `on_pick`. No tira rareza, no aplica nada, no es un framework de menús. Existe así a propósito: la pausa, la cola, el título con destinatario de co-op, el look de `UiTheme.style_card` y —sobre todo— el harness de soaks (que responde llamando `_on_card_pressed(0)` sobre cualquier nodo visible del grupo `upgrade_ui`) siguen funcionando **porque una elección ES un pick**. Una UI bloqueante nueva sería una forma nueva de encallar una partida.
- **Toast de botín** (`hud.show_loot(title, description, color, player_index)`, grupo `hud`, que reenvía a `LootToast`): tarjeta abajo al centro `hold_time` 3 s, encolada si llegan varias, con etiqueta `J%d` en co-op; su look se edita en `scenes/ui/hud/LootToast.tscn`. La llama **`ItemBag.add_item`**, que es la única puerta por la que entra un objeto (cofres, ruleta, lo que venga): una llamada por fuente habría que escribirla otra vez en cada fuente nueva. El Tomo del Azar también se anuncia ahí: `PlayerStats.add_tome` **devuelve** los boons que acaba de tirar, `UpgradePool.apply` los propaga y `UpgradeCardUI` los pinta con `Tome.boon_text()`. **`open_bonus_pick(title, luck_bonus, min_rarity, recipient)`** lleva destinatario explícito: en co-op, un cofre o altar tiene que decir a **quién** le toca la carta, no confiar en «el jugador de turno».
- Contrato de pausa (`BlockingUi`, `scripts/ui/game/modal/blocking_ui.gd`): quien posee la pausa se une a `ui_blocking` y expone `is_blocking() -> bool`; antes de abrir encima de la partida se pregunta `BlockingUi.any_open(tree)`. `pause_menu.gd` mantiene además su propio flag `_pause_owned`, así que nunca devuelve una pausa que no tomó ni roba la de las cartas o el fin de partida. Un panel nuevo que se abre desde el mundo extiende `ModalPanel` y hereda todo eso; si acepta cierre por código entra a `blocking_ui_closable`, que llaman el cambio de etapa (`RunRoot._freeze_world`) y el harness.
- Fin de partida: `run_manager.gd` (señal `run_ended`, cableada dentro de `RunSystems.tscn`) → `run_end_screen.gd`, cuya coreografía sale de una tabla `ENDINGS` (título, subtítulo, color por final) en vez de ramas.
- **Longitud del español**: las superficies del HUD y las tarjetas son tolerantes a etiquetas más largas, pero la regla del glosario sigue vigente — una etiqueta española no debe crecer más de ~10% sobre la inglesa en HUD, insignias y botones.

## Escala de la interfaz

**La interfaz se diseña sobre 1280x720 y se ESTIRA.** `project.godot`
declara desde la iteración 62:

```
window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
```

Antes no declaraba nada de `[display]`, y los valores por defecto de Godot
son 1152x648 con `stretch/mode = "disabled"`. **«disabled» quiere decir que
un `Control` mide lo mismo en PÍXELES pase lo que pase con la ventana**: al
darle al botón verde del Mac el viewport pasaba de 1280x720 a la pantalla
entera (3024x1898 medidos) y el HUD, los menús y los botones se quedaban a
menos de la mitad de su tamaño relativo. Lo reportó el jugador; ninguna
puerta podía verlo, por lo mismo que el suelo invisible de la iteración 60.

Las tres decisiones, y por qué:

| Ajuste         | Por qué ese y no otro                                                                                                                                                                                                                                         |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `canvas_items` | escala el sistema de coordenadas **2D** y deja el 3D renderizando a resolución NATIVA: interfaz del mismo tamaño relativo en cualquier ventana y mundo nítido. `viewport` habría escalado también el 3D y lo habría dejado borroso                            |
| `expand`       | la pantalla de un MacBook no es 16:9 (3024x1898 es 1.59:1) y `keep` habría metido barras negras. Con `expand` el factor es el menor de los dos ejes y el sobrante se ve como **más mundo**; el HUD está anclado a las esquinas, así que sigue en sus esquinas |
| base 1280x720  | es la resolución sobre la que está calibrada cada posición de `HUD.tscn` y con la que se verificó la ronda visual entera. Medido: el mismo fotograma a 1280x720 antes y después del cambio difiere en **0 píxeles de 921 600**                                    |

**Consecuencia deliberada en el ratón.** `PlayerCamera._apply_look` (`scripts/player/components/player_camera.gd`, nodo `CameraRig` del Player) lee
`InputEventMouseMotion.relative`, y con stretch ese vector llega en unidades
de CANVAS, no en píxeles de ventana. La sensibilidad deja de depender de la
resolución — antes, maximizar la ventana la subía sola. A 1280x720 el factor
es 1 y el número guardado en Ajustes significa exactamente lo que siempre.

**Al añadir interfaz**: se piensa en el lienzo de 1280x720 y se ancla a un
borde o a una esquina. Nada de posiciones absolutas pensadas para una
pantalla concreta, y nada de leer `DisplayServer.window_get_size()` para
colocar un `Control`: eso es lo que el stretch ya resuelve.

## Sistemas transversales

- **Pools** (`scripts/systems/autoloads/pools.gd` + `node_pool.gd`): pooling de los **15** hotspots (gemas, orbes, dardos, flechas, bumerán, bolts enemigos, bursts de muerte, popups, discos de telégrafo, arco de tajo, fogonazo, latigazo, brasas, charcos de sangre y charcos ácidos). Contrato de uso: spawn = `Pools.acquire_scene(escena)`, despawn = `Pools.release(nodo)`; el script pooled implementa `pool_reset()` restaurando estado recién-spawneado. **Escena nueva de alta rotación = UNA fila en `Pools.POOLS`** (`name`, `scene`, `warm`, `cap`); los tamaños se ajustan en esa misma fila. Sin registrar, `acquire_scene` cae a instanciar normal.
  - Contrato del `NodePool`: `release()` **registra** en el nodo lo que apaga (`process`, `physics_process`, `monitoring`, `monitorable`) y `acquire()` restaura exactamente eso. El pool no inventa estado (no fuerza processing sobre escenas que no definen callbacks) ni deja un `Area3D` aparcado escuchando. Métricas: `total_created` (churn) y `peak_parked`.
- **Juice** (`scripts/systems/autoloads/juice.gd`, autoload cargado desde `scenes/systems/Juice.tscn`): hooks semánticos de una línea — `enemy_died(pos, color)`, `boss_died(...)`, `crit_punch()`, `player_hurt()`, `sparkle(pos)`, `burst(...)`, `flash(visual)`, `shake(...)`, `hit_stop(...)`, `fov_kick_begin(camera)` / `fov_kick_end(camera)`. Una mecánica nueva con impacto debería llamar a uno existente antes que inventar efectos propios; los tunables son exports agrupados que se editan en el Inspector de `Juice.tscn`. `Juice.damp(tasa, delta)` es el peso de suavizado compartido: se usa como `lerp(a, b, Juice.damp(r, d))` y es independiente del framerate (el `tasa * delta` de siempre es su aproximación de Euler y deriva con el frame time). El rig de la foca, las mascotas y la cámara se asientan a la misma velocidad real gracias a él.
- **Sfx** (`scripts/systems/autoloads/sfx.gd`, autoload cargado desde `scenes/systems/Sfx.tscn`, donde se ajustan voces y variación de tono): `Sfx.play(&"id")` sobre un pool de voces con jitter de pitch y rate-limit; loops con `acquire_loop/release_loop`, siempre **con refcount** (un solo camino, sin caso especial para el primer dueño) y `stop_all_loops()` para los cortes de escena. **Cada sonido es una fila de `SOUND_LIBRARY`** (al principio de `sfx.gd`): `stream`, `volume_db` y, si aplica, `loop`, `jitter` y `rate_limit`. Sonido nuevo = receta en `scripts/tools/generate_sfx.gd` (síntesis determinista) + una fila en `SOUND_LIBRARY`. Regenerar los 20 wav: `godot --headless --path . -s res://scripts/tools/generate_sfx.gd`.
- **Player** (`scenes/player/Player.tscn`, `scripts/player/player.gd`): el raider es un `CharacterBody3D` con un hijo por responsabilidad — `CollisionShape3D`, `SealRig` (el cuerpo), `CameraRig` (`SpringArm3D` + `Camera3D`, script `player_camera.gd`: modos de cámara y mirada), `Weapons` (el montaje de armas), `Health`, `Stats`, `ItemBag`, `PowerUps`, `Revive` (+ `RevivePrompt`; derribo y reanimación, `player_revive.gd`), `Flight` (`player_flight.gd`), `PetSlot` (`pet_slot.gd`) y `Wallet` (puntos de partida, `player_wallet.gd`). Los componentes nuevos están en `scripts/player/components/`; `player.gd` conserva los métodos públicos de siempre (`set_pet`, `end_flight`, `add_points`, `set_points_source`, `view_camera`…) como reenvíos, así que el resto del juego no cambia de llamada.
- **Capa de stats** (`scripts/systems/player_stats.gd`, nodo `Stats` del Player): guarda stacks de tomos + pasiva + reliquias + objetos + boons y **recalcula todo desde cero** en `recompute()` en cada cambio (nunca acumular sobre valores derivados). `recompute()` está partido en cuatro fases nombradas; `_apply_boons()` recorre gamble/altar/temporales en un solo bucle y `_apply_items()` hace una sola pasada por la bolsa. Stat nuevo: campo derivado + rama en `_apply_effect(stat, amount)` + que el consumidor lo lea (armas vía helpers de `WeaponBase`; `Health` recibe `armor`/`evasion` empujados). Los suelos de multiplicador son const documentadas.
- **Saltos y suerte de power-ups**: `extra_jumps` (id `jumps`) da saltos en el aire extra — `Player._try_jump` gasta un presupuesto `_jumps_left` que se recarga **al pisar suelo** (no dentro del salto, para que quien se cae de un borde conserve los suyos), con tope `PlayerStats.MAX_EXTRA_JUMPS`; y `powerup_drop_chance` (id `powerup_chance`, en porcentaje). Ambos entran al pool de boons de altar y `extra_jumps` además al catálogo de objetos («Botas de resorte», Rara).
- **Knobs de partida que venden los altares y pactos**: `PlayerStats.powerup_drop_chance` lo lee la tirada de drop de power-ups (`PowerUpDrops`) y `RunState.disaster_chance_bonus` la tirada de clima del `WeatherDirector`. Los dos **se reinician** (`recompute()` / `reset()`).
- **Health** (`scripts/systems/health.gd`): componente hijo reutilizable (los números flotantes no son suyos: le dice a `DamagePopup` qué pasó); señales `damaged`, `damaged_by(attacker)` (thorns), `dodged(attacker)` (ejecuciones), `hp_changed(current, max)` y `died`. El **setter de `max_hp` es dueño de la invariante**: un cuerpo a vida llena sigue lleno tras subirle el máximo, uno herido queda clampado, y `hp_changed` reporta ambos valores — ningún sitio que escale HP tiene que acordarse. Un golpe siempre quita al menos `MIN_CHIP_DAMAGE` (o su valor bruto si ya era menor), así que la armadura nunca vuelve a un cuerpo inmortal. `Health.find_in(body)` / `PlayerStats.find_in(body)` son la forma estándar de encontrar componentes.
- **Co-op** (`scripts/systems/autoloads/coop.gd`, autoload `Coop`): `player_count`, `devices`, `character_ids`, `action(slot, base)` (acciones clonadas por slot), `look_vector(slot)`, `nearest_player(tree, from)`, `random_player(tree)`, `alive_players(tree)`, `alive_player_count(tree)`. El snapshot de jugadores está tipado y su invalidación es explícita (`invalidate_players()`): si spawneas o liberas un raider fuera de `RunSystems`, invalídalo.
- **Pantalla dividida** (`scripts/systems/split_screen.gd`): un `SubViewportContainer` por jugador con una cámara que **espeja** la del jugador (transform, `fov`, `h_offset`, `v_offset`, `cull_mask` — la lista completa está en `CameraPair.sync()`; una vista que se saltaba los offsets no temblaba). Las cámaras fuente se apuntan a `Juice.FEEL_CAMERA_GROUP`.

## Rendimiento (iteración 64)

**Cómo se mide.** Cada soak imprime una línea `Perf t=...` cada 600 frames
(media, p50, p95, p99 y máximo del frame, junto a enemigos, nodos, huérfanos,
draw calls y primitivas) y un `Perf summary` al salir (`PerfMeter`,
`scenes/tests/perf_meter.gd`). Bajo `--fixed-fps 60` el reloj de pared de
un frame headless **es** el costo de CPU de ese frame con el renderer
anulado. Con ventana suma la GPU, pero en un Mac solo en **pantalla
completa**: en ventana el compositor la topa a la frecuencia del panel
aunque se pase `--disable-vsync`. Dos corridas con la misma semilla
divergen después de ~38 s, así que una comparación de frame time se hace
con **varias semillas por lado** y medianas, nunca con una corrida.

**Física: Jolt.** `project.godot` fija `3d/physics_engine="Jolt Physics"`.
`DEFAULT` es GodotPhysics3D en 4.7, y con él el `move_and_slide` de cada
enemigo costaba 130-400 µs (95 % de su tick), más cuando la horda se
apretaba: 80 enemigos pasaban los 16,6 ms del frame **solo en CPU**, y un
cuerpo trabado en la masa llegó a 33 ms por tick él solo. Medido con 18
pares de soaks de 360 s (6 semillas × 3 arenas): frame medio 7,8 → 1,9 ms,
p99 27 → 4,9 ms, tirones de más de 33 ms 37 → 0, con la misma progresión
(nivel mediano 14 y 14, bajas 342 y 351, cofres abiertos 7 y 8,5). Sin
enemigos, el raider camina igual con los dos motores (misma velocidad y
mismos atascos por semilla). Lo que cambia y hay que saber:

- Los monitores `PHYSICS_3D_ACTIVE_OBJECTS` y `PHYSICS_3D_COLLISION_PAIRS`
  leen **0** con Jolt: las columnas `bodies`/`pairs` de `Perf` dejaron de
  servir.
- Desde 4.5 un `Area3D` **sí** detecta cuerpos estáticos con Jolt (el ajuste
  que lo apagaba se eliminó), así que proyectiles y bolts siguen chocando
  con el terreno y las rocas.
- El proyecto no usa joints ni `RigidBody3D`, que es donde Jolt más difiere.
- Todo lo medido antes de esta iteración (umbrales de soak, recetas de
  puertas, comportamientos de contacto) se midió con GodotPhysics. Una rama
  abierta antes de la iteración 64 re-corre su puerta con Jolt al
  rebasarse sobre ella.

**`monitorable = false` en los `Area3D`.** Nadie en el proyecto detecta un
área como área (ni `area_entered`, ni `get_overlapping_areas`, ni consultas
con `collide_with_areas`), así que las áreas de pickups, cofres, santuarios,
proyectiles y bolts lo tienen apagado. Si una mecánica nueva necesita
detectar un área, se enciende **en esa escena** y se dice en su cabecera.
`NodePool` registra y restaura el valor, así que el pool no lo pisa.

**Mallas primitivas con teselado explícito.** Un `SphereMesh` sin
`radial_segments`/`rings` son 4 224 triángulos: los dos ojos de 6 cm de un
Grunt eran la mitad de sus 17 536. Toda `SphereMesh`, `CapsuleMesh`,
`CylinderMesh` y `TorusMesh` —en escena o creada con `.new()`— declara sus
segmentos, con la silueta a menos de ~1 cm del círculo real a escala de
autor: cabezas y cuerpos 24×12, orbes y bolts 12×6, ojos y llamitas 8×4,
gemas 4×2, conos y cilindros sin anillos intermedios. El disco de telégrafo
de los jefes declara 64 lados a propósito (el valor por defecto, escrito
para que se vea que es una decisión): su borde **es** la zona de golpe que
el jugador lee. `cast_shadow = 0` en partes de menos de ~0,1 m (ojos,
dientes, gemas, llamitas) y en FX pequeños que brillan (orbes, el orbe de
vida, el anillo de nivel, el disco de telégrafo).

**Separación de la horda en grilla.** `EnemySeparation.push`
(`scripts/enemies/enemy/enemy_separation.gd`) no recorre la horda entera por
cuerpo: una grilla espacial de celdas de `EnemySeparation.CELL_SIZE` (1,25 m,
mayor que el `separation_radius` más grande)
se arma una vez por tick y cada cuerpo mira su celda y las 8 vecinas. Mismos
vecinos y misma contribución que antes; solo cambia el orden de suma en coma
flotante. **Invariante**: un enemigo solo se mueve dentro de su propio
`_physics_process` (que reubica su celda) o entre ticks. Algo que lo
teletransporte o lo empuje a mitad de tick desde otro nodo tiene que
reubicarlo también.

**Tope de cofres de recompensa.** `EnemyBase.BOUNTY_CHEST_CAP` (30, alias de `EnemyLoot.BOUNTY_CHEST_CAP`): con
30 cofres de élite **sin abrir** en el mapa, un élite muerto no suelta otro
hasta que se abra alguno o cambie la etapa (`Elite chest capped: ...` en el
log). Antes no expiraban ni tenían tope: un soak de 15 minutos terminaba con
~390 en el suelo. Los cofres de jefe no cuentan. El harness imprime
`Probe bounty chests: max=%d cap=%d` y `verificar.sh` falla si se pasa.

**Calidad gráfica** (Ajustes → «Calidad gráfica», `SaveData.graphics_quality`,
aplicada por `Settings`): Alta es lo de siempre; Media renderiza el 3D al
75 % con FSR 1 y deja las sombras del sol a 60 m en dos cortes; Baja, al
50 % y sin sombras del sol. El 2D no se escala nunca (`canvas_items`), así
que el HUD queda nítido en cualquier preset. Las `SubViewport` de la
pantalla dividida no heredan la escala de la raíz: entran al grupo
`world_views` y `Settings` se la aplica. El sol de cada etapa recibe el
preset en `RunState.stage_changed` y guarda lo que su arena tenía de fábrica
(meta `authored_sun_shadow`) para que volver a Alta lo restaure exacto. Log:
`Graphics: quality=%d scale=%.2f suns=%d views=%d`; el soak de co-op corre en
Media (`BONK_GRAPHICS=1`) y lo exige.

## Verificación

### `tools/verificar.sh`

La comprobación estándar del proyecto. Desde la raíz:

```sh
tools/verificar.sh            # 360 s de partida por arena (el modo estándar)
tools/verificar.sh 720        # corrida larga, para cambios de ritmo tardío
```

**Nunca la corras con menos de 360 s.** Por debajo de ese umbral la puerta
de cobertura de interactuables se salta en silencio y el script imprime OK
sin haber exigido nada: un soak corto «pasa» aunque ningún cofre, altar
ni portal se haya resuelto en las tres arenas. 360 s es lo que tarda el
recorrido en cruzar una arena de 240x240.

Hace `godot --headless --import`, el **lint de catálogos** y el **harness de UI** (iteración 57, los dos abajo), un soak de **las tres arenas** (`HollowWoods`, `AshDunes`, `Gloomfen`) con `BONK_GODMODE=1 BONK_SEED=4242 BONK_GAME_SEED=4242`, un **cuarto soak de etapa** (iteración 49): Bosque Hueco con `BONK_STAGE_FAST=1` y **el doble de reloj** (60 s hasta la puerta + 70 s de espera deliberada + cruzar el mapa hasta un portal que sale a 40 m o más no cabe en 240 s, y el RNG del juego se `randomize()`a por corrida, así que la semilla solo fija el paseo del harness). Ese cuarto soak queda **fuera** de la cuenta de interactuables, y `Portal used: exit` no cuenta como portal usado. Falla (exit 1) si:

- el import o algún soak imprime errores/warnings de Godot (patrón amplio: `SCRIPT ERROR`, `ERROR:`, `WARNING:`, `null instance`, `previously freed`, `Resource file not found`…),
- una arena no llega al final del soak (se colgó o murió antes) — lo mide contando las líneas `frame N ...` que el harness imprime cada 120 frames,
- **cobertura**: el raider no pasó del nivel 3 (señal de que el arma no hace daño), o —solo en corridas de ≥240 s— ningún interactuable se resolvió. Un soak que no sube de nivel ni toca nada puede pasar «limpio» sin haber ejercitado nada.
- **etapa**: el soak de etapa no abrió su portal, no cruzó de `hollow_woods` a `ash_dunes`, dejó algo vivo en un `Stage sweep:`, perdió progreso entre el par de `Stage carry:` de un cruce, o no produjo ningún `Sky event:` después del cruce (lo que probaría que el director no volvió a cachear las luces del mapa nuevo).
- **co-op** (iteración 57): el quinto soak no arrancó con dos raiders (`ArenaProbe: players=2`), no cruzó de etapa, ensució un `Stage sweep:` o no produjo ningún `Player revived:`. Desde la iteración 64 corre en calidad Media y además falla sin la línea `Graphics: quality=1 scale=0.75 suns=1 views=2` (el preset llegó al sol y a las dos `SubViewport`).
- **tope de cofres** (iteración 64): a cualquiera de los cinco soaks le falta `Probe bounty chests: max=N cap=M`, o `N` pasa de `M`. El conteo cuenta los cofres que hay, no pasa por el tope, así que quitar el tope se ve en cuanto un soak deja caer más de 30 — cosa que no pasa siempre: de las dos corridas que cerraron la iteración 64, el soak de etapa llegó a 30 en una y a 6 en la otra.
- **lint / UI**: falta cualquiera de las doce líneas `Catalog lint: check <nombre> ok rows=N` (con `rows` > 0) o de los trece `UiProbe: step <nombre> ok`. Las listas de nombres viven en `tools/verificar.sh` y se greppean **una por una**: una comprobación que deja de ejecutarse desaparece del log sin ruido, y un conteo la daría por buena mientras otra se repite.
- **partida godmode terminada**: cualquier soak inmortal que imprima `Probe fog: skipped` (ver la regla de fin de partida abajo). Un raider con 10M de HP no tiene por qué morirse.

La corrida completa (import + lint + harness de UI + 3×360 s + 1×720 s + 1×360 s de co-op) tarda **entre ~16 y ~75 minutos**, más que el timeout de una llamada de shell: lánzala en segundo plano. El reloj de una corrida lo manda el TAMAÑO DE LA HORDA, no el número de frames: medido en dos corridas de la misma cabeza y las mismas semillas, **16 min** y **75 min**. El soak de co-op es el que más se mueve (la horda escala +50% de HP y +30% de ritmo de spawn por raider extra, y un cuerpo vivo cuesta física cada frame): 78 s en una corrida y 32 min en la otra. Por eso `verificar.sh` imprime los segundos de cada fase y el total — una estimación fija envejece mal. **Desde Jolt (iteración 64)** la corrida completa tardó 3-5 min en las tres medidas de esa iteración: el costo por cuerpo que estiraba el reloj es lo que Jolt se llevó.

Logs en `$TMPDIR/bonkraiders-verify/`. Cada arena imprime su resumen `nivel=… cofres=… altares=… portales=…`.

### Guardado por corrida (iteración 57)

`tools/verificar.sh` le da a **cada** soak y a cada harness su propio
`BONK_SAVE_PATH` (`$LOGDIR/save_<soak>.json`), borrado junto a sus hermanos
`.bak` y `.tmp` antes de arrancar. Alcance, dicho con honestidad: los soaks
godmode nunca terminan la partida, así que **nunca doblaban meta**; lo que sí
arrastraban era lo que `SaveData.bump` acredita **durante** la corrida
(bestiario `kills_<script>`, `used_weapon_<id>`), y cualquier corrida mortal o
del harness de UI escribía encima esquirlas, misiones y desbloqueos en el mismo
archivo. Borrar solo el `.json` no era un reset: `load_from_disk` cae al `.bak`
(«Save recovered from backup»), así que el borrado tiene que llevarse los tres.

### `scenes/tests/CatalogLint.tscn` + `catalog_lint.gd`

Las referencias cruzadas que **ningún soak puede comprobar**, porque una rota
no revienta: simplemente no hace nada. Un `passive_stat` mal escrito le cuesta
a su raider la pasiva entera y deja un warning enterrado en un log de 20 000
líneas; una ruta `scene` con un typo solo falla el día que alguien tira esa
fila; un glifo repetido entre dos catálogos pinta la sigla equivocada.

Quince comprobaciones (la lista fija es `LINT_CHECKS` en `tools/verificar.sh`), una línea `Catalog lint: check <nombre> ok rows=%d` por
cada una que pasa y un `push_error` por cada fallo:

| Comprobación                | Qué mira                                                                                                                                                                                   |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `ids_unique`                | id repetido dentro de cada librería (13 librerías)                                                                                                                                         |
| `glyphs_unique`             | glifo repetido **entre** armas, evoluciones, tomos, objetos, power-ups y mascotas                                                                                                         |
| `paths_exist`               | toda ruta `scene` / `weapon_scene` / `scene_path` / `icon`, con `ResourceLoader.exists`                                                                                                    |
| `stat_ids`                  | todo `passive_stat`, `stat` de objeto/power-up/mascota/reliquia y stat de boon de altar o pacto contra las ramas del `match` de `PlayerStats._apply_effect`                                |
| `character_weapons`         | el `weapon_node_name` de cada raider existe como `node_name` en `WeaponCatalog.WEAPON_LIBRARY`                                                                                            |
| `director_methods`          | todo `method` de `EVENT_LIBRARY` está declarado en `world_director.gd` (y toda fila sin `method` trae una `scene`); todo `start`/`tick`/`stop` de `WEATHER_CATALOG` (`weather_catalog.gd`) está declarado en `weather_director.gd` |
| `weapon_properties`         | toda `extra_entries.property` y toda clave `mults`/`adds` de evolución existe en el arma destino (se instancia la escena y se lee su lista de propiedades)                                 |
| `vendor_lucky_roulette_ids` | ids únicos en `VENDOR_LIBRARY`, `LUCKY_REWARDS` y `OUTCOMES`                                                                                                                               |
| `marker_labels`             | todo `marker_kind` que algún `.gd` o `.tscn` asigna y toda clave de `MARKER_STYLES` (salvo `player`/`boss`/`exit`) tiene fila en `MARKER_LABELS`, **a menos que** esté en `MapDraw.LEGEND_VARIANTS` |
| `id_format`                 | todo id de catálogo es minúsculas, dígitos y guiones bajos: un id con espacios o mayúsculas termina dentro de claves del guardado (`runs_as_<id>`) y de los contadores de las misiones |
| `quest_stats`               | toda misión cuyo `stat` lleva un id de otro catálogo tras un prefijo de `SaveData` nombra un id que existe: si no, el contador nunca sube y la misión queda imposible sin ningún error |
| `text_numbers`              | los números que un texto repite de su propia fila (la pasiva de cada personaje, la etiqueta de cada mascota, el texto de rango de cada reliquia) coinciden con los que de verdad se aplican |
| `text_values`               | las filas de objetos y power-ups que arman su texto con `RowText`: cada campo de `text_values` existe en la fila y la descripción tiene un `%d` por campo; un campo que falta se dibujaría como 0 sin avisar |
| `item_kinds_unique`         | cada `kind` de comportamiento aparece en una sola fila de `ITEM_LIBRARY`: `ItemCatalog.kind_row()` lee los números de la primera, así que una segunda fila mostraría sus números en el texto y jugaría con los de la otra |
| `sfx_ids`                   | todo id escrito a mano en `Sfx.play(&"…")`, `acquire_loop(&"…")` y demás llamadas a `Sfx` con un literal existe como clave de `Sfx.SOUND_LIBRARY`: un id mal escrito solo avisa en tiempo de ejecución y el sonido no suena |

`rows` es lo que se inspeccionó **de verdad**, y **cero filas es un fallo**: una
comprobación que recorre una lista vacía pasa por el motivo equivocado, que es
exactamente cómo una constante renombrada pasaría desapercibida.

`MapDraw.LEGEND_VARIANTS` nombra las tres variantes que a propósito **no**
llevan fila de leyenda (`chest_free`, `altar_demonic`, `altar_greed`): cada una
es una variante de una familia que ya tiene la suya, y una línea por variante
convertiría una leyenda de un vistazo en una taxonomía. Nombrarlas en una
constante en vez de dejarlas implícitas es lo que le permite al lint distinguir
una omisión deliberada de una olvidada.

### `scenes/tests/UiProbe.tscn` + `ui_probe.gd`

**Siete de las nueve escenas de UI no las arrancaba nada**: CharacterSelect,
Collection, QuestLog, RelicShop y SettingsPanel no se instanciaban nunca, y
PauseMenu y RunEndScreen las instanciaba `RunSystems.tscn` sin que nadie las
abriera. Un handler que revienta en su primera pulsación, un menú que no
devuelve la pausa, un nombre `%` renombrado en un `.tscn`: nada de eso podía
ensuciar un soak, porque ningún soak pasaba por ahí.

```sh
godot --headless --fixed-fps 60 --quit-after 7200 res://scenes/tests/UiProbe.tscn
```

Arquitectura, porque el botón de inicio y los de la pantalla final
**reemplazan `current_scene`**: el script raíz de la escena hace una sola cosa
en su `_ready` — crear el **driver** y añadirlo a `get_tree().root` con
`call_deferred` (añadir un hijo a la raíz desde dentro de un `_ready` da
«Parent node is busy setting up children»). El driver vive como hermano de
`current_scene`, con `process_mode = ALWAYS`, así que sobrevive a todos los
cambios de escena; tras cada corte re-adquiere `current_scene` y **espera a que
la cortina de `ScreenFade` termine** antes de pulsar nada, porque una pulsación
que cae dentro de esa ventana se descarta en silencio.

Pulsa los **controles reales**: por nombre único resuelto contra su propio
dueño (`%SettingsButton` existe en `CharacterSelect.tscn` **y** en
`PauseMenu.tscn`) —incluidos `%CollectionButton`, `%ArmoryButton` y el
`%UnlockYes` («Sí») de cada carta—, y `pause_game` como
`InputEventAction` parseado con la soltada en un frame **posterior**. Antes de
cada `pressed.emit()` comprueba `not disabled and is_visible_in_tree()`:
`pressed.emit()` se salta las dos cosas, así que un harness que solo emite
prueba que el handler corre, no que un jugador pudiera llegar a él. Nunca llama
a un handler con guion bajo.

Trece pasos, cada uno con su `UiProbe: step <nombre> ok`: `collection`,
`quests`, `relics`, `coop_count_reject`, `unlock_confirm`, `cards_all`,
`start_run`, `pause_open`, `settings_toggle`, `pause_close`, `extract`,
`retry`, `done`; cierra con `UiProbe: done steps=%d`.

Cada paso tiene un **plazo en frames** que hace `push_error` con su nombre y
sale. El plazo por defecto son 600 frames y es un detector de **cuelgue**, no
un cronómetro: `start_run` (1200) y `retry` (900) esperan al reloj de partida
(`RunState.run_time` ≥ 10 y ≥ 5, o sea 600 y 300 frames por sí solos), así que
el plazo por defecto se dispararía en una corrida **sana**. Los dos plazos
largos están tabulados en `STEP_DEADLINES` con ese motivo escrito al lado.

### El harness: `scenes/tests/ArenaProbe.tscn` + `arena_probe.gd`

Arranca una arena como **hijo de un nodo siempre activo**, imprime estado cada 2 s (`frame N paused=… run_time=… enemies=… level=… airborne=… explored=…`) y elige sola la primera carta en cada subida de nivel (si no, el soak se queda pausado en la primera carta).

Desde la iteración 45 **el raider camina e interactúa por defecto**. Un raider aparcado se salta en silencio todo sistema condicionado al movimiento — el Rastro de baba solo suelta charcos moviéndose, los altares de carga solo cargan con alguien en el anillo, cofres y portales necesitan que alguien llegue **y** pulse interactuar — así que un soak quieto reporta «sin errores» sobre código que nunca ejecutó. Cómo funciona, y por qué importa si tocas el Player:

- Conduce **manteniendo las acciones de input reales** (`Coop.action(0, &"move_*")`), no escribiendo `velocity`: `Player` reconstruye la velocidad desde `Input.get_vector()` cada frame de física, así que una velocidad escrita se pierde. De paso, el soak ejercita el camino de input real (derrape, gating de sprint, base de la cámara libre).
- El recorrido visita primero los `Interactable` disponibles (`LINGER_TIME` quieto al llegar, pulsando `interact` cada `INTERACT_INTERVAL`, para que los altares de carga completen su canal), con `REVISIT_COOLDOWN` para no hacer ping-pong entre los dos más cercanos, y cae a `random_walkable_point()` del grupo `arena_bounds` cuando no quedan.
- «Llegó» es la condición del propio juego (`player_in_range` del objetivo), no un radio fijo: un cofre sobre un saliente nunca satisfaría una prueba de distancia siendo perfectamente interactuable.
- Se despega solo: si el avance horizontal se estanca (`STALL_WINDOW`/`STALL_DISTANCE`), salta. Sin eso, ni rampas ni muros de máscara son franqueables.
- La pulsación de `interact` se sintetiza con `InputEventAction` y **suelta en un frame posterior**: ambas en el mismo flush y la acción nunca lee como «recién pulsada», que es justo lo que comprueba `Interactable._unhandled_input`.
- Detector de atasco: si el árbol lleva `PAUSE_WEDGE_WARN` segundos pausado sin UI de cartas abierta, imprime un `push_warning` con los bloqueantes **visibles**. Un soak encallado en una UI bloqueante se ve idéntico a uno sano en el contador de frames.
- **Barrido de máscara** (iteración 48, una sola vez en el frame de física 10, cuando los transforms de los props ya llegaron al servidor de física): por cada celda bloqueada recorre en pasos de 0.2 m cada arista que comparte con una celda caminable y prueba ahí una cápsula del tamaño del jugador (radio 0.4, altura 1.8, centrada a 0.9 m) a caballo de la arista contra la capa 1, excluyendo a los raiders. Una muestra que no golpea nada es una **apertura**. Imprime `Mask sweep: blocked=%d samples=%d openings=%d` y hace `push_warning` por cada apertura. Es la prueba de que la roca sella de verdad (desde la iteración 63, las formaciones de `RockFormation`); **jamás se afloja la tolerancia ni la densidad de muestreo** para hacerlo pasar — se cambia la roca.
- **Raider dentro de celda bloqueada** (iteración 48): si el raider líder está **a nivel de suelo** (y ≤ 0.6, no sobre una roca ni una meseta) dentro de una celda no caminable más de 2 s seguidos, `push_warning`. Se reporta una vez por entrada a la celda, no por frame.
- **Detector de enemigos voladores** (iteración 48): un cuerpo cuenta como _airborne_ cuando lleva `velocity.y > 0.5` **en subida y sin piso** durante 0.5 s seguidos. Exactamente dos excepciones, y son las dos que suben a propósito: un enemigo en estado de trepada (`_climbing`) y un Duneburrower en erupción. Cada ocurrencia nueva imprime **un** `push_warning` (una vez por cuerpo) y la línea de estado del harness termina en `airborne=%d` acumulado. Las reglas son fijas: ensancharlas para callar un warning es exactamente lo que este detector existe para impedir.
- **Cobertura de niebla** (iteración 52): la línea de estado termina en
  `explored=` (`FogOfWar.explored_fraction()`) y al terminar el soak imprime
  `Probe fog: explored=%.2f`, avisando si quedó por debajo de
  `FOG_MIN_EXPLORED` **0.09**. La puerta **no** se aplica bajo
  `BONK_STAGE_FAST` (la niebla se reinicia en cada etapa) ni bajo
  `BONK_POWERUP_NOW` (ese interruptor mantiene **un** power-up encendido
  toda la corrida, un estado que ninguna partida real alcanza: con
  `time_stop` la horda nunca entra en alcance, no muere nada y el
  recorrido se arrastra — medido: nivel 2 y 107 cuerpos vivos a los
  360 s). En ambos casos la cobertura mide el interruptor, no el paseo.
  La puerta conserva toda su fuerza donde se calibró: los cuatro soaks de
  `tools/verificar.sh`, que no ponen ninguno de los dos. Ese número se calibró **una sola vez**, con las
  tres arenas a 360 s y las semillas de `verificar.sh`: Bosque Hueco 0.15,
  Dunas de Ceniza 0.32, Ciénaga Lóbrega 0.16 → el **60% de la peor**. Ese 40%
  de margen no es holgura para un recorrido flojo, es **varianza medida**: el
  mundo sí es reproducible (misma máscara, mismo relieve, líneas de frame
  idénticas los primeros ~38 s) pero la partida **no** —el orden de contactos
  de la física diverge y la misma semilla cae entre 0.13 y 0.24 en el mismo
  mapa—, así que una puerta clavada en el mínimo observado sería intermitente.
  Aun así atrapa lo que existe para atrapar: la corrida en la que el raider se
  quedó atascado midió **0.08**. Es un piso: se sube si el recorrido mejora, no
  se baja porque una corrida se quedó corta. La fracción se **cachea mientras la partida vive**: en
  `_exit_tree` el nodo de niebla ya no está y leerla ahí reportaba 0.00. El
  soak de etapa (`BONK_STAGE_FAST`) no pasa por esta puerta: dura 60 s por
  etapa a propósito y no le da tiempo a explorar nada.
  A los dos interruptores se suma, desde la iteración 57, una **regla
  semántica** (no un interruptor nuevo): **una partida terminada no puede
  explorar**. Un soak mortal acaba en la muerte del raider, así que la
  fracción que alcanzó dice cuánto vivió, no cómo camina el recorrido.
  Cuando la regla se aplica el harness imprime
  `Probe fog: skipped (run ended at %.1fs)`, de modo que el salto **nunca es
  silencioso** — y `tools/verificar.sh` **falla** cualquier soak GODMODE que
  imprima esa línea, porque un raider con 10M de HP no tiene por qué morirse.
- **Fin de partida** (iteración 57): sin `BONK_GODMODE`, el harness se conecta
  a `RunManager.run_ended` (por el grupo `run_manager`), imprime
  `Probe: run ended victory=%s` dos frames después de `Meta saved:` y sale.
  Antes de esto una corrida mortal dejaba el árbol pausado bajo la pantalla
  final —que **no** se juega sola en headless, a diferencia de la ruleta y del
  vendedor— hasta que saltaba el `PAUSE_WEDGE_WARN` a los 20 s. La ruta de
  «Reintentar» de esa pantalla es cosa del harness de UI, no de este.
- **Co-op** (iteración 57): con `BONK_PLAYERS=N` el harness llama a
  `Coop.configure` **antes** de instanciar `Run.tscn` (que es lo que
  `RunSystems._spawn_party` lee dentro de su propio `_ready`), con todos los
  slots en el teclado — un soak no tiene controles, y `_rebuild_slot_actions`
  duplica los eventos de teclado por slot, así que `p0_*` y `p1_*` acaban
  siendo dos juegos de acciones distintos sobre las mismas teclas, que es
  justo lo que necesita un harness que sintetiza acciones por nombre.
  `_apply_godmode` cubre **solo al slot 0**: el slot 1 se queda mortal, que es
  lo que permite que `BONK_DOWN_NOW` aterrice. Todo helper que dice «el
  raider» resuelve al líder por `player_index == 0`, nunca por «el primero del
  grupo» (con dos cuerpos el orden del grupo es orden de spawn). Los slots 1+
  **siguen** al líder y no interactúan nunca: dos recorridos duplicarían las
  cuentas de interactuables con las que se calibró cada puerta. Y una **regla
  de rescate** manda por encima de todo lo demás, el rush al portal incluido:
  con un cuerpo de `downed_players` a menos de 6 m, el líder camina hasta él y
  **mantiene** interactuar (`_hold_action`, no la pulsación de un frame:
  `PlayerRevive.tick` quiere 3 s continuos de la acción **del rescatador**)
  hasta que se levanta. Al final imprime `Party: downs=%d revives=%d` y
  `Party pets: p0=%s p1=%s`.
- **Mapa de Tab** (iteración 52): cada `MAP_OVERLAY_INTERVAL` 60 s pulsa
  `map_overlay`, lo mantiene `MAP_OVERLAY_HOLD` 2 s y suelta. Imprime
  `Map overlay: open markers=%d` y `Map overlay: closed`. El conteo se lee
  `MAP_OVERLAY_REPORT_DELAY` 0.5 s **después** de la pulsación, no en el mismo
  frame: el overlay refresca en su propio `_process`, que cae en un frame de
  idle **posterior** al de física que sintetizó la tecla, y leerlo antes
  reportaba el mapa de antes de abrirse (`markers=0`).
- `_send_action(base, pressed)` es el sintetizador de teclas genérico (antes
  era solo `_send_interact`): misma regla de soltar en un frame posterior.
- **Power-ups** (iteración 53): el recorrido se desvía a la gema más cercana dentro de `PICKUP_DETOUR` 20 m (caminar encima **es** la interacción: ni pulsación ni linger). Bajo `BONK_POWERUP_NOW=time_stop` muestrea hasta tres cuerpos congelados por frame y al descongelar imprime `Time stop: sampled=%d moved=%d damage_events=%d` — `moved` y `damage_events` son las dos formas en que un congelado puede ser mentira, y las dos tienen que salir en cero. Al terminar imprime `Immortal blocked:` con `Health.blocked_hits` (cacheado en vida, como la niebla). Bajo `BONK_POWERUP_NOW=flight` **mantiene el salto** 5 s cada 15 s, porque Vuelo solo hace algo mientras se mantiene; el resto de los soaks conservan el paseo de siempre.
- Nunca toca el guardado real: usa `BONK_SAVE_PATH` si está puesta y `user://soak_save.json` si no, antes de instanciar la partida.

Variables de entorno:

| Variable                                      | Efecto                                                                                                                                                                                                                                                                                                                                                                                                       |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `BONK_ARENA=res://scenes/world/AshDunes.tscn` | **bioma inicial** de la etapa 1 (defecto: Hollow Woods). El probe siempre arranca `Run.tscn`                                                                                                                                                                                                                                                                                                                 |
| `BONK_CHARACTER=<id>`                         | raider de `CharacterCatalog`. Un id desconocido es un **`push_error`** desde la iteración 54 (antes se ignoraba en silencio, y un soak que creía probar un raider corría el de siempre); el probe imprime `ArenaProbe: character=<id>`                                                                                                                                                                       |
| `BONK_PLAYERS=<1-4>`                          | tamaño de la party (iteración 57); `Coop.configure` antes de instanciar `Run.tscn`. El probe imprime `ArenaProbe: players=%d slot1=%s` contado sobre los **grupos**, no sobre el interruptor                                                                                                                                                                                                                 |
| `BONK_CHARACTER2=<id>`                        | raider del slot 1 (defecto: la fila siguiente del catálogo)                                                                                                                                                                                                                                                                                                                                                  |
| `BONK_DOWN_NOW=<seg>`                         | golpe letal al slot 1 a ese segundo y cada 60 s después: fuerza el ciclo derribo/reanimación en vez de esperar a que la horda lo elija                                                                                                                                                                                                                                                                       |
| `BONK_GODMODE=1`                              | raider con 10M de HP, para que los sistemas tardíos se ejerciten. **Solo el slot 0** desde la iteración 57                                                                                                                                                                                                                                                                                                   |
| `BONK_WALK=0`                                 | deja el raider quieto (defecto: camina)                                                                                                                                                                                                                                                                                                                                                                      |
| `BONK_SEED=<int>`                             | recorrido determinista, para reproducir un soak                                                                                                                                                                                                                                                                                                                                                              |
| `BONK_PROBE_DEBUG=1`                          | narra el recorrido (waypoints, llegadas, pulsaciones)                                                                                                                                                                                                                                                                                                                                                        |
| `BONK_ELITE_BOOST=1`                          | todo spawn sale shiny (`force_elite_spawns` por grupo)                                                                                                                                                                                                                                                                                                                                                       |
| `BONK_STAGE_FAST=1`                           | la etapa se supera a los 60 s sin jefe; el harness espera 70 s y cruza                                                                                                                                                                                                                                                                                                                                       |
| `BONK_SAVE_PATH=<ruta>`                       | re-apunta el guardado. Lo honran `SaveData._ready` (cualquier arranque headless) **y** el propio probe, antes de instanciar la partida; `tools/verificar.sh` le da a cada soak el suyo                                                                                                                                                                                                                       |
| `BONK_GAME_SEED=<int>`                        | siembra el RNG **del juego** (cartas, spawns, scatter y relieve): lo que hace reproducible un soak entero                                                                                                                                                                                                                                                                                                    |
| `BONK_POWERUP_NOW=<id>`                       | concede ese power-up al slot 0 a los 20 s y **lo re-concede en cada expiración**                                                                                                                                                                                                                                                                                                                             |
| `BONK_STAR_NOW=1`                             | suelta una estrella **quieta** a los pies del raider a los 30 s                                                                                                                                                                                                                                                                                                                                              |
| `BONK_POWERUP_BOOST=1`                        | multiplica ×50 la probabilidad de drop por baja (lo lee `EnemySpawner`)                                                                                                                                                                                                                                                                                                                                      |
| `BONK_POI_NOW=a,b,c`                          | siembra esos POIs a 8 m del raider a los 20 s: `vendor_items`, `vendor_powerups`, `vendor_animals`, `pet_box`, `event_altar`, `lucky_block`. Las repeticiones se conservan (seis `lucky_block` siembran seis bloques)                                                                                                                                                                                        |
| `BONK_LUCKY_REWARD=a,b`                       | cola de recompensas que pagan los bloques siguientes en vez de tirar la tabla (la última se repite); un id desconocido es `push_error`. Cola **estática** en `lucky_block.gd`, porque la tirada es estática y tiene que sobrevivir entre bloques                                                                                                                                                             |
| `BONK_SWAP_MENU=1`                            | aserción de auditoría (iteración 58): en la trama en que un menú cerrable tiene la pausa, dispara un cambio de etapa por el grupo `run_root` e informa `Swap menu: paused=%s` cinco segundos después. `true` es el atasco. Necesita que se abra un menú (`BONK_POI_NOW=vendor_items BONK_POINTS=4000`)                                                                                                       |
| `BONK_POWERUP_AT=<s>`                         | mueve la primera concesión de `BONK_POWERUP_NOW` fuera de sus 20 s por defecto: una congelación que arranca a los 20 s y se re-concede para siempre atrapa a todos los enemigos **en superficie**, así que los estados que solo existen más tarde en un ciclo (un Duneburrower enterrado) son inalcanzables con el valor por defecto                                                                         |
| `BONK_WEATHER_NOW=<id>`                       | fuerza ese clima a los 30 s por la misma entrada forzada que usa el altar                                                                                                                                                                                                                                                                                                                                    |
| `BONK_WEAPON=<id>`                            | el raider arranca con esa arma en vez de la de su personaje, por la misma vía de concesión                                                                                                                                                                                                                                                                                                                   |
| `BONK_ITEM_NOW=a,b:2`                         | concede esos objetos al slot 0 a los 10 s (`id:n` para n copias) y hace que el recorrido **derrape** cada ~3 s, único disparador del cinturón                                                                                                                                                                                                                                                                |
| `BONK_ZENKAI_TEST=1`                          | a los 60 s: golpe del 95%, 3 s invulnerable y curación completa — el bajón-y-supervivencia con el que Zenkai se arma                                                                                                                                                                                                                                                                                         |
| `BONK_POINTS=<n>`                             | le da esos puntos al slot 0 al arrancar, para que un soak de vendedor pueda pagar                                                                                                                                                                                                                                                                                                                            |
| `BONK_PERF=1`                                 | enciende el overlay de rendimiento del HUD                                                                                                                                                                                                                                                                                                                                                                   |
| `BONK_GRAPHICS=<0-2>`                         | preset gráfico del soak (iteración 64): 0 Alta, 1 Media, 2 Baja. Se aplica antes de arrancar la partida, así que el sol de la primera etapa ya lo recibe. **No se guarda** en el save del soak, y un valor que no sea 0-2 es un `push_error`, como un `BONK_CHARACTER` desconocido. Sin el interruptor, el harness aplica el preset del save del soak (no el del jugador, que `Settings` aplicó al arrancar) |

Uso directo:

```sh
BONK_ARENA=res://scenes/world/Gloomfen.tscn BONK_GODMODE=1 \
  godot --headless --fixed-fps 60 --quit-after 36000 res://scenes/tests/ArenaProbe.tscn
```

Arrancar una arena directamente (`res://scenes/world/Gloomfen.tscn` como
escena principal, o F6 en el editor) **ya no funciona** desde la iteración
49: una arena es solo el mundo. Arranca `res://scenes/world/Run.tscn` y
elige el bioma con `BONK_ARENA` / `GameConfig.start_map_id`.

Para lógica aislada sigue sirviendo un harness desechable `extends SceneTree` (patrón de `generate_sfx.gd`) con `godot --headless --path . -s res://...`. Ojo: en un script `-s` **no hay autoloads**, así que no sirve para nada que toque `RunState`, `SaveData`, `Coop`, `Juice` o `Sfx`. Recuerda además que `Juice` y `Sfx` son autoloads **de escena** (`scenes/systems/Juice.tscn`, `scenes/systems/Sfx.tscn`): un cambio en sus valores se hace en esas escenas, y el import tiene que cargarlas limpias como cualquier otra.

### La cámara del harness: `BONK_SHOT_DIR` (iteración 60)

**El agujero que tapa.** Todo lo que este proyecto verifica corre
`--headless`, y el `DisplayServer` de pega **no compila un shader ni
rasteriza un triángulo**. Eso deja una clase entera de fallo sin puerta
posible: una malla culeada al revés, un material que nunca llega, un panel
dibujado encima del reloj, una etiqueta cortada. Todos dan un log
perfectamente verde. Las iteraciones 51 a 59 pasaron `verificar.sh` con **el
suelo de las tres arenas invisible**, y quien lo vio fue el jugador.

`scenes/tests/shot_camera.gd` (`class_name ShotCamera`, `RefCounted`) es lo
que lo cierra, y lo llevan **los dos** harnesses:

|                      |                                                                                                                                                                                                                                                                       |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Cómo captura         | `Viewport.get_texture().get_image().save_png()` **tras `await RenderingServer.frame_post_draw`**. Antes de ese await `get_image()` devuelve el fotograma anterior, que para una foto de evento es el de justo antes del evento                                        |
| Por qué desde dentro | macOS le niega `screencapture` a una terminal sin permiso de Grabación de Pantalla, y un soak no tiene a quién pedírselo. Desde el motor no hace falta permiso ninguno                                                                                                |
| Headless             | **se ignora**, con un `Shots skipped: headless` una sola vez. Un PNG vacío sería peor que ninguno                                                                                                                                                                     |
| Cuándo dispara       | cada `BONK_SHOT_EVERY` s (10 por defecto, 2 en `UiProbe`), en cada cambio de etapa, clima, llegada de vendedor, caja de mascotas abierta, bloque de la suerte resuelto, power-up recogido, apertura del mapa Tab y en la primera carta de nivel; `final.png` al salir |
| Retardo              | etapa y clima esperan `SHOT_SETTLE` 1.5 s y el mapa 0.6 s (`ShotCamera.request_in`): el overlay abre al fotograma siguiente al Tab, el tinte de un clima entra en rampa y un cambio de etapa va detrás del fundido de `ScreenFade`                                    |
| Qué NO hace          | nada que una puerta lea. Con la variable sin poner, todas sus líneas son no-ops, y el temporizador se alimenta del delta de física —no de `RunState.run_time`— precisamente para que un menú que congela el reloj **sí** salga fotografiado                           |

**Los eventos se leen del árbol, no de los logs.** Un `print` no es algo a lo
que otro nodo se pueda suscribir: un vendedor es un miembro nuevo del grupo
`vendors`, la caja y el bloque avisan por el `interaction_completed` que ya
emitían, y un power-up es un id que el líder no llevaba en la muestra
anterior.

**Lo que la cámara no puede juzgar** y sigue necesitando ojos humanos:
sensación, ritmo, legibilidad de un texto sobre un fondo movido y si el arte
gusta. Lo que sí decide sola: si algo se dibuja, dónde, y encima de qué.

### `scenes/tests/TerrainShots.tscn` + `terrain_shots.gd` (iteración 63)

La cámara del soak ve lo que el raider tenga delante mientras camina. Para
juzgar un cambio en **cómo se ve el suelo** hacen falta las mismas
formaciones fotografiadas desde los mismos sitios antes y después. Este
harness arranca una partida, la congela a los 20 fotogramas, oculta todos
los `CanvasLayer` y saca:

| Foto                | Qué es                                                                                  |
| ------------------- | --------------------------------------------------------------------------------------- |
| `map.png`           | ortográfica cenital, sin niebla: el trazado de la máscara                               |
| `aerial.png`        | 3/4 de la arena entera, sin niebla                                                      |
| `spawn.png`         | a la altura de los ojos desde el spawn, con niebla                                      |
| `formation_<n>.png` | a la altura de los ojos, a 26 m de una de las regiones bloqueadas más cercanas al spawn |
| `drone_<n>.png`     | la misma región desde 18 m de altura                                                    |

```sh
BONK_ARENA=res://scenes/world/AshDunes.tscn BONK_GAME_SEED=7 \
BONK_SHOT_DIR="$TMPDIR/terrain/dunas" BONK_SAVE_PATH="$TMPDIR/terrain_save.json" \
godot --path . --resolution 1280x720 res://scenes/tests/TerrainShots.tscn
```

Imprime `Terrain shots: <mapa> formations=<n> props=<n> meshes=<n> blocked=<n>`
y sale. Necesita ventana (headless no guarda nada y lo dice, como
`ShotCamera`). `BONK_GAME_SEED` es lo que hace comparables dos fotos —misma
semilla, mismo mundo— siempre que el cambio no altere cuántas veces se tira
del RNG antes del scatter; uno que cambie la máscara misma da otro trazado y
se compara por estilo, no píxel a píxel.

## Convenciones

- **GDScript con tipado estático** en el 100% del código (parámetros, retornos, variables con tipo, `:=` solo con tipo inferible), incluidos los `Array`/`Dictionary` tipados (`Array[Dictionary]`, `Dictionary[String, int]`). Mantenerlo: el codebase compila limpio y los soaks dependen de ello. Un `Array` sin tipar cruzando una firma tipada lanza `Invalid type in function` en runtime, no en parseo.
- **Señales y grupos, no referencias duras** entre escenas: `call_group(...)` / `get_first_node_in_group(...)` para todo acoplamiento cruzado; rutas de nodo solo dentro de la propia escena.
- **`resource_local_to_scene = true` en todo sub-recurso que se mute en runtime.** Un `[sub_resource]` de una `.tscn` es **UN objeto compartido por todas las instancias** de esa escena: mutarlo desde el script cambia el de todos los demás y se filtra a la partida siguiente. Casos ya marcados: la `CapsuleShape3D` del Player (el derrape le cambia la altura — sin la marca, derrapar encogía a toda la party), y los `ParticleProcessMaterial` de `DeathBurst`, `BloodPool`, `WhipCrack` y `TelegraphDisc` (se tintan por spawn). Si tu script escribe en `mesh`, `shape`, `material`, `process_material` o cualquier `SubResource("...")`, márcalo en la escena y **dilo en la cabecera del script**. Trampa aparte: un `StandardMaterial3D` **sin sombreado** (unshaded) pierde todo `emission_*` al guardarse y al duplicarse, así que su emisión se pone en código desde un export (`TelegraphDisc.start_energy`, `BeamVisual.emission_energy`), no en la escena.
- **Los repartos «a toda la party» cubren también a los caídos.** Un raider derribado **sale del grupo `player`** y entra en `downed_players` (`PlayerRevive.set_downed`, nodo `Revive` del Player). Un efecto permanente para la partida (boon de altar, evento de cielo, desbloqueo) que solo recorra `player` le deja al caído un déficit que nada repone. Recorre los dos grupos (`for group in ["player", "downed_players"]`, como `ChargeShrine.grant_boon`) salvo que la mecánica exija estar en pie a propósito. Dentro de un `Interactable`, la pregunta correcta es `live_players_in_range()`.
- **Cualquier cosa que actúe sobre una cámara la recibe explícitamente.** En co-op el viewport raíz **no tiene cámara activa**: las cámaras que renderizan viven en los `SubViewport` de `SplitScreen`. `get_viewport().get_camera_3d()` devuelve `null` (o la equivocada) en cuanto hay dos jugadores. Por eso `Juice.fov_kick_begin/end` reciben la cámara del deslizador, la flecha de jefe (`scripts/ui/game/boss_arrow.gd`) recibe la suya por `bind_view(camera, carrier)`, y las cámaras fuente se registran en `Juice.FEEL_CAMERA_GROUP` para que el shake llegue. `Player.view_camera()` es el accesor de la cámara propia de un raider. Nunca busques «la» cámara.
- **Los nombres de rareza son identificadores.** `Rarity.TIERS[].name` (`Common`/`Rare`/`Epic`/`Legendary`, en `scripts/systems/catalogs/rarity.gd`) llavea precios de cofre, el campo `rarity` de `ITEM_LIBRARY` y los pisos `min_rarity`: **no se traduce nunca**. Para mostrarla en pantalla, `Rarity.display_name(id)` (la tabla es `Rarity.DISPLAY_NAMES`; `UpgradePool.rarity_display` reenvía ahí) — es el único punto de traducción, y nada compara contra su resultado.
- **Español latinoamericano para todo lo visible, inglés para todo lo estructural.** La tabla es `docs/GLOSARIO.md`. En inglés y sin tocar: identificadores, ids, `node_name`, grupos, `StringName`, rutas `res://`, claves de `SaveData` y los `print()`/`push_warning()`/`push_error()`. Los marcadores de formato (`%d %s %.1f %02d %%`) conservan número y orden exactos.
- **Los comentarios y los tooltips `##` van en español (es-419)**, en presente y cortos: qué hace el código y por qué cuando no es obvio. Sin historia (números de iteración, «antes era», bugs pasados, valores viejos): eso vive en git y en `CHANGELOG.md`. Se conservan, cortos, los avisos que sostienen algo: orden de operaciones, orden de tiradas del RNG, contratos que se alcanzan por nombre, unidades y «esto tiene que coincidir con X».
- **Lo que se muestra es dueño de cómo se ve.** Un nodo que dibuja algo guarda sus colores, tamaños, tiempos y textos como `@export` en su propio script, y su escena guarda los valores que cambian por instancia. Quien lo llama pasa **significado** (un flag, un enum, un id, una fila de catálogo), nunca presentación: `Health` dice `DamagePopup.Kind.CRIT` y `DamagePopup` decide el color del crítico.
- **Valores de diseño como `@export` agrupados**, al principio del script que los usa, con `@export_group("Nombre en español")` y un tooltip `##` de una línea en español que dice qué es y su unidad (segundos, metros, píxeles, 0-1, por minuto…). `const` solo para lo que nadie ajusta (matemática, llaves, protocolo). Un script que nunca va en una escena (creado con `.new()`, o un catálogo estático) no tiene Inspector: ahí los valores son `const` con nombre en un bloque arriba, con un comentario «edita aquí».
- **Una sola fuente de verdad por valor.** Un script usado por una sola escena no lleva overrides en esa escena: el valor vive en el default del script, así editar el script siempre funciona. Los valores por instancia (la vida de cada enemigo, el scatter de cada mapa, el horario de jefes por arena, las escenas del spawner) viven en cada escena. **Nunca dejes que `_ready` pise un valor del Inspector**: si el código lo sobreescribe, editarlo en la escena no hace nada. Antes de mover un `@export` de sitio, comprueba qué `.tscn` lo overridea: las tres arenas overridean el `EnemySpawner`.
- **Cada catálogo dice en su cabecera qué campos son llaves** («NUNCA las cambies») y cuáles se pueden cambiar libremente. Los ids de personaje son `snake_case` (el lint `id_format` lo exige en todo catálogo); renombrar uno exige una fila en `SaveData.ID_ALIASES` para que los guardados viejos no lo pierdan.
- **Nada de números sueltos.** Un `0.5` repetido en dos archivos es la forma en que dos copias del mismo cálculo se separan: si es diseño, es un `@export` (regla de arriba); si no, una `const` con nombre.
- **Logs de una línea** en eventos clave — son la interfaz de verificación de los soaks headless, van **en inglés** y se conservan. Inventario actual: `Run ended:`, `Meta saved:`, `Save recovered from backup:`, `Boss spawned:`, `Boss chests dropped:`, `Elite chest dropped:`, `Horde:`, `Sky event:`, `Chest opened:`, `Altar charged:`, `Altar left:`, `Altar placed:`, `Demonic altar used:`, `Demonic pact:`, `Spawn skipped:`, `Stage advanced:`, `Stage sweep:`, `Stage carry:`, `Stage gate:`, `Stage boss slain:`, `Exit portal opened`, `Portal used: exit`, `Pseudo-infinite:`, `Run stages:`, `Terrain built:`, `Probe legs:`, `Greed shrine:`, `Roulette spun:`, `Spring used:`, `Portal used:`, `Portals placed:`, `Weapon evolved:`, `Weapon ascended:`, `Pet joined:`, `Secret miniboss awakened:`, `Secret boss slain:`, `Arena mask:`, `Rock formations:`, `Start layout:`, `Daily run scored:`, `Void rescue:`, `Power-up picked:`, `Power-up dropped:`, `Star roam:`, `Flight landing:`, `Pet box opened:`, `Vendor arrived:`, `Vendor sold:`, `Time stop:`, `Immortal blocked:`, `Weather started:`, `Weather ended:`, `Disaster:`, `Event altar used:`, `Possessed spawned:`, `Possessed expired:`, `Belt bolt:`, `Saiyan aura:`, `Zenkai triggered:`, `Lucky block:`, `Save path overridden:`, `Save migrated:`, `Player revived:`, `Vendor buyer:`, `Elite chest capped:`, `Graphics:`, `Skirmisher degenerate aim:`. Al crear un evento mayor, añade el tuyo con el mismo formato. Las líneas de los harness van aparte y también se conservan, porque `tools/verificar.sh` las greppea: `Probe legs:`, `Probe fog:` (incluida su forma `Probe fog: skipped`), `Probe: run ended`, `Mask sweep:`, `Map overlay:`, `Time stop:`, `Immortal blocked:`, `HUD offset:`, `Party:`, `Party pets:`, `Points sources:`, `Catalog lint:`, `UiProbe:`, `Swap menu:`, `Saiyan boons:`, `Time stop worms:`, `Probe bounty chests:`, `Perf` (y `Perf summary:`, del `PerfMeter`).
- **Verificar antes de dar por hecho un cambio**: `tools/verificar.sh`. Un cambio que no pasa el import o ensucia el log de un soak no está terminado.
