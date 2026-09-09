# Arquitectura — dónde tocar cada cosa

Mapa de referencia por sistema: qué hace, archivos clave y cómo extenderlo. Regla general del proyecto: **el contenido son filas de catálogo** (Dictionaries const en `scripts/systems/`) + una escena; casi nunca hace falta código nuevo por pieza de contenido. Los sistemas se comunican por **señales y grupos**, nunca por rutas de nodos entre escenas.

Dos documentos que este mapa da por leídos:

- **`docs/GLOSARIO.md` es la ley de la terminología.** El juego está íntegramente en español latinoamericano (es-419) desde la iteración 45. Toda cadena visible por el jugador sale de esa tabla; si añades contenido, extiende el glosario en vez de improvisar un término. Lo que **nunca** se traduce: `id` de catálogo, `node_name`, nombres de grupo, `StringName` (`&"..."`), rutas `res://`, claves de `SaveData` y todo `print()`/`push_warning()` — los soaks y este documento dependen de ellos en inglés.
- **`tools/verificar.sh` es la puerta de salida.** Import limpio + soak de las tres arenas + cobertura mínima. Ver «Verificación» al final.

## Vista general de una partida

`scenes/ui/CharacterSelect.tscn` (escena principal) escribe la elección en el autoload `GameConfig` (`selected_character_id`, más el modo diario) y carga **una sola escena**: `scenes/world/Run.tscn`. Ya no hay selector de mapa ni de grado — toda partida empieza en el Bosque Hueco y recorre la lista de mapas.

`Run.tscn` (raíz `run_root.gd`, `class_name RunRoot`, grupo `run_root`) tiene dos hijos: la instancia **única** de `scenes/world/RunSystems.tscn` — el bloque común: `Player`, `RunManager` (fin de partida y puerta de etapa), `WorldDirector` (layout y eventos), `UpgradeCardUI`, `HUD`, `RunEndScreen`, `PauseMenu` — y `ArenaHost`, bajo el cual se instancia la arena de la etapa actual. Cada arena (`HollowWoods.tscn`, `AshDunes.tscn`, `Gloomfen.tscn`) es solo el mundo: entorno, luz, suelo, perímetro, verticalidad, interactuables de escena, scatter, `EnemySpawner` y `AmbientBed`. **Una arena ya no se puede arrancar sola** (F6 o `--quit-after` directo sobre el `.tscn`): sin raíz de partida no hay jugador, ni HUD, ni director.

`RunSystems._enter_tree()` llama `RunState.reset()`: el bloque de partida es el dueño del reinicio y entra al árbol **antes** de que `RunRoot._ready` construya la primera arena, así que el scatter y el director de cada etapa siempre ven un `RunState` limpio.

Ver «Partida por etapas» más abajo para el ciclo de vida completo y el contrato del cambio de mapa.

Autoloads (`project.godot`, en orden de carga): `RunState` (XP/nivel/kills/reloj/dificultad), `GameConfig`, `Coop` (entrada por slot), `SaveData` (meta persistente), `Juice` (game feel), `Sfx` (audio), `Settings` (aplica ajustes), `Pools` (object pooling), `ScreenFade` (fundidos y el ritual de salir de partida).

### Grupos y hooks por grupo

El acoplamiento cruzado va siempre por aquí. Lista actual:

| Grupo | Quién está dentro | Qué se le llama |
|---|---|---|
| `player` | raiders **en pie** | seek de enemigos, imanes, repartos |
| `downed_players` | raiders derribados (salen de `player` al caer) | repartos «a toda la party» |
| `enemies`, `boss` | cuerpos vivos | targeting de armas, cupo del spawner |
| `enemy_bolts`, `player_shots` | proyectiles en vuelo | limpieza y filtros de colisión |
| `gems` / `health_orbs` | pickups vivos (`XpGem.LIVE_GROUP`, `HealthOrb.LIVE_GROUP`) | `vacuum()`, tope blando de orbes |
| `enemy_spawner` | el spawner de la arena | `spawn_pressure_burst`, `spawn_minions`, `set_sky_event`, `apply_temp_enemy_buff`, `freeze_enemies` |
| `world_director` | el director de `RunSystems` | `start_sky_event(kind)`, `on_stage_started(arena)`, `on_stage_ended()`, `beacon_count()` |
| `run_manager` | el `RunManager` | `extract_run()` |
| `run_systems` | la raíz del bloque | `vacuum_pickups()`, `place_party(origin)` |
| `run_root` | la raíz de la partida (`Run.tscn`) | `arena_root()`, `current_arena()`, `advance_stage()` |
| `arena_root` | la arena de la etapa viva | la busca `RunRoot`; el scatter la usa para filtrar sus keepouts |
| `arena_bounds` | el nodo de scatter de la arena | `is_walkable`, `random_walkable_point`, extensión de arena |
| `hud` | el HUD | `announce(msg)`, `announce_major(msg)`, `show_loot(...)`, `show_stage_tag(stage, lap)`, `on_stage_started(arena)` (reenvía a minimapa y mapa) |
| `fog` | la niebla de guerra de la partida | `reset_for_stage(arena)`, `reveal_at(xz)`, `is_explored(xz)`, `explored_fraction()` |
| `map_markers` | todo lo que sale en el mapa (raiders, jefes, interactuables con `marker_kind`) | `map_marker_kind()`, opcional `map_marker_color()` |
| `map_overlay` | los mapas de Tab vivos | `marker_count()` (lo lee el harness) |
| `powerup_pickups` | power-ups en el suelo (iteración 53) | limpieza de etapa y `Stage sweep: pickups=` |
| `enemy_projectiles` | bolts enemigos en vuelo | el flag `frozen` de Tiempo detenido |
| `springs` | el manantial vivo (como máximo uno) | el peso 0 de su fila de evento |
| `acid_pools` | charcos ácidos vivos (iteración 55) | el tope y la separación de la lluvia radiactiva |
| `possessed` | siervos del nigromante (iteración 56) | `Stage sweep: possessed=`, el cupo por portador y la limpieza de etapa |
| `lucky_blocks` | bloques de la suerte vivos | limpieza de etapa |
| `vendors` | los puestos vivos (máximo 2) | el peso 0 de su fila y `Stage sweep: vendors=` |
| `pet_boxes` | las cajas de mascotas vivas | limpieza de etapa y `Stage sweep: boxes=` |
| `boss_ui` | HUD + flecha de jefe | `track_boss(boss, title)`, `track_objective(node)`, `announce` |
| `upgrade_ui` | `UpgradeCardUI` | `open_bonus_pick(...)`, `open_choice(...)` |
| `altars` | todo `ChargeShrine` vivo (de escena o del director) | el cupo de altares sin gastar del `WorldDirector` |
| `ui_blocking` | toda UI que se adueña de la pausa | `is_blocking() -> bool` |
| `blocking_ui_closable` | UI bloqueante que acepta cierre por código: la ruleta y, desde la iteración 54, el panel de vendedor | `dismiss()` — **llamado por `RunRoot._swap_stage`** desde la iteración 58, antes de tomar la pausa; las dos además se resuelven solas en headless |
| `feel_camera` | cámaras que Juice sacude (`Juice.FEEL_CAMERA_GROUP`) | shake / FOV kick en pantalla dividida |
| `scatter_keepout` | props y POIs colocados a mano | el scatter no siembra encima |

## Clases base y helpers compartidos (iteración 45)

El refactor de la iteración 45 extrajo la duplicación que estaba causando bugs «gemelos» (el mismo defecto reportado dos y hasta cuatro veces, una por copia). Antes de escribir un helper nuevo, mira si ya vive en uno de estos:

| Archivo | `class_name` | Qué unifica |
|---|---|---|
| `scripts/systems/catalog_index.gd` | `CatalogIndex` | Índice `id -> fila` para los ocho catálogos. `build(rows, campo)` y `values_where(...)`. Cada catálogo guarda su `static var` de índice y conserva su `by_id()` público: cambia el coste de la búsqueda, no el contrato. `PlayerStats.recompute()` resolvía una fila por stack en un bucle lineal. |
| `scripts/systems/magnet_pickup.gd` | `MagnetPickup` | Chasis de los pickups tirados (`XpGem`, `HealthOrb`): idle con giro/bob, homing acelerado al raider en pie más cercano (radio × `RunState.pickup_radius_multiplier`), captura por proximidad y caducidad. La subclase aporta `LIVE_GROUP`, qué hace recolectar y el adorno propio. |
| `scripts/ui/meta_screen.gd` | `MetaScreen` | Chasis de las tres pantallas entre partidas (Registro de misiones, Armería, Colección): fondo, título, insignia, botón Volver, entrada escalonada y el conteo de esquirlas. Contrato de escena: `%TitleLabel`, `%BadgeLabel`, `%List`, `%BackButton`. Hooks: `_badge_color()`, `_tracks_shards()`, `_build_rows(list)`; momentos compartidos: `payoff()`, `reject()`, `rebuild()`. |
| `scripts/ui/card_factory.gd` | `CardFactory` | Constructores sin estado de la carpintería de tarjetas del selector (etiquetas, cajas, muestras de color, styleboxes por estado). Los colores siguen viniendo de `UiTheme`; esto es «cómo se arma una tarjeta», no un segundo sistema de diseño. |
| `scripts/fx/fx_mesh.gd` | `FxMesh` | `strip(vertices, colors)`: la tira de triángulos que comparten el arco de tajo y el latigazo. |

Helpers compartidos que ya existían pero **crecieron** en esta iteración (ver cada sección):

- `WeaponBase`: barridos de área (`enemies_in_disc/sphere/lane/arc`), `damage_all`, `spawn_fx_mesh`, helpers de aim.
- `EnemyBase`: `damage_players_in_disc/discs` (AoE consciente de la party), `spawn_chest`, `current_overlay`.
- `BossBase`: `_clamp_to_arena`, `_safe_arena_point`, `_play_boss_entrance`, `_spawn_spike_cluster`, un único slot de tween de telégrafo (`_play_cue`/`_begin_cue`/`_kill_cue`).
- `Interactable`: `live_players_in_range()`, `nearest_live_player()`, `best_item_count_in_range()`, `_hold_loop`/`_drop_loop`.
- `Juice`: `damp()` (suavizado independiente del framerate) y el registro `feel_camera`.

## Añadir un arma nueva

- Qué es: nodos hijos del mount `Weapons` del Player que disparan solos por cooldown al enemigo más cercano del grupo `enemies`.
- Archivos: `scripts/weapons/weapon_base.gd` (clase `WeaponBase`), `scripts/systems/upgrade_pool.gd` (`WEAPON_LIBRARY`, 14 armas), `scenes/weapons/`.
- Contrato `WeaponBase`: exporta `damage/cooldown/attack_range/projectile_count/cooldown_scale`; la subclase sobreescribe `fire(target)` y canaliza **todo** golpe por `deal_damage(target_health)` (aplica multiplicador global, crit, lifesteal y los hooks de objetos del portador). Helpers de stats: `effective_damage()`, `effective_cooldown()`, `area_scale()` (radios/arcos, no `attack_range`), `effective_projectile_count()`, `duration_scale()`, `targeting_range()`.
- **Barridos de área compartidos (iteración 45)**: `enemies_in_disc(centro, radio, ventana_y)`, `enemies_in_sphere(centro, radio)`, `enemies_in_lane(origen, dir, largo, ancho)`, `enemies_in_arc(centro, dir, alcance, ángulo)` y `damage_all(bodies)`. Cuatro armas repetían el mismo bucle con los mismos dos números mágicos; si tu arma golpea una forma, **úsala desde aquí** en vez de escribir un `get_nodes_in_group("enemies")` nuevo. Los helpers de aim (`aim_dir_or`, `flat_dir_or`, `safe_up`) son estáticos y cubren los casos degenerados (vector nulo, dirección colineal con Y).
- Visual efímero: `spawn_fx_mesh(mesh)` construye el `MeshInstance3D` en la raíz de escena con la configuración correcta (lo que antes copiaban cuatro armas).
- Pasos: (1) script `extends WeaponBase` + escena en `scenes/weapons/` (mira `shortsword.gd` melee, `dart_pistol.gd` proyectil, `ember_wand.gd` área); (2) una fila en `UpgradePool.WEAPON_LIBRARY` con `id`, `display_name` (**en español**, glosario «Armas»), `node_name` (== nombre de nodo al instanciarse, **en inglés**), `scene`, `flavor` y opcionalmente `extra_entries`. Con eso ya aparece como carta de arma nueva y genera sus cartas de daño/velocidad de ataque/alcance automáticamente.
- `WEAPON_LIBRARY` está indexada por `node_name` (`CatalogIndex`) para el HUD y el banner de evolución: no hagas un bucle lineal nuevo, usa el accesor del catálogo.
- Si dispara proyectiles: el proyectil es su propia escena con `pool_reset()`, se lanza con `Pools.acquire_scene(...)` y se registra con **una fila** en `Pools.POOLS` (ver Pools abajo). Ejemplo completo: `dart_pistol.gd` + `projectile.gd`.
- Armas sin objetivo: un arma que actúa sola (Rastro de baba) sobreescribe `_physics_process` y devuelve `null` en `acquire_target()`; las de área alrededor del portador (Aura, Hedor) usan `attack_range * area_scale()` como radio y `fire()` ignora el objetivo.
- Al caer un raider (co-op), el Player avisa a sus armas **antes** de congelar el mount: un arma que deja objetos en el mundo (charcos) tiene que limpiarlos ahí, o quedan huérfanos.

### Multitud por arma (iteración 46)

`Tomo de Multitud` (stat `projectiles`) llega a **todas** las armas: cada script lee `effective_projectile_count()` en su ruta de ataque (`fire()`, o `_physics_process` en las que atacan desde ahí). Qué hace el conteo extra depende de la forma del arma — un arma de ataque único no puede sacar dos golpes en el mismo sitio y el mismo frame, y un campo persistente no puede duplicar su anillo sin duplicar el daño en silencio:

| Arma | Forma | Qué hace el conteo extra |
|---|---|---|
| Pistola de dardos | proyectil | más dardos por andanada (abanico), como siempre |
| Arco de caza | proyectil | más flechas por andanada (abanico), como siempre |
| Orbes espirituales | órbita | más orbes en el anillo, como siempre |
| Espada corta | ataque único (arco) | un arco completo más por extra, escalonado y abanicado |
| Dagas gemelas | ataque único (estocada) | estocadas extra escalonadas; cada una re-adquiere objetivo |
| Látigo de espinas | ataque único (carril) | latigazos extra escalonados y abanicados, cada uno su carril |
| Kamehameha | ataque único (rayo) | rayos extra escalonados y abanicados; un rugido por andanada |
| Pararrayos | ataque único (cadena) | descargas extra escalonadas, cada una con su propia bifurcación |
| Bumerán | proyectil (ataque único) | hojas extra lanzadas una tras otra y abanicadas |
| Vial de sangre | ataque único (frasco) | frascos extra escalonados, impacto rotado **alrededor del lanzador** |
| Vara de brasas | ataque único (estallido) | detonaciones extra escalonadas, cada una re-adquiere su centro |
| Aura | campo persistente | **no** añade anillos: +12% de radio y −8% de intervalo por extra (suelo 60%) |
| Hedor | campo persistente | igual que Aura: +12% de radio y −8% de intervalo por extra (suelo 60%) |
| Rastro de baba | charco | un charco más por gota, en anillo a 1.2 radios del punto de caída |

Reglas que comparten las de ataque único: el escalonado es un `const` por archivo y se recorta para que **toda la cadena quepa en el 60% del `effective_cooldown()`**; los callbacks diferidos usan `get_tree().create_timer(delay, false, true)` (pausable y en paso de física) y abren con `if not is_inside_tree(): return`, porque un arma se libera con su raider. Todo golpe sigue pasando por `deal_damage()`.

## Mascotas

**Una sola mascota por jugador** (iteración 54). El slot vive en
`Player.pet_id` y solo lo mueve `Player.set_pet(id)`: libera la mascota
anterior, instancia la nueva, anuncia las dos mitades del cambio por el
toast de botín, imprime `Pet joined:` y pide un `recompute()`.

**No hay copias.** Dar dos veces la misma mascota no hace nada, y por eso
**cada fila declara arma y estadística**: una mascota es un paquete
entero, y una fila a medias convertiría un cambio en una pérdida que el
jugador no puede deshacer.

- **De dónde salen**: solo de la **caja de mascotas** y del **traficante de
  animales**. Los cofres y la ruleta ya no pueden dar una — se borraron las
  filas `kind: "pet"` de `ITEM_LIBRARY` y el propio kind. Una compañera que
  llega sin que la pidas es una compañera que tira la que elegiste.
- **El arma** se instancia bajo la mascota (`Pet._build_weapon`), queda
  **fuera del tope de 5 armas** y del pool de mejoras, lee las
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

| id | Nombre | Arma | Estadística |
|---|---|---|---|
| `alien` | Alienígena | Varita de brasas | suerte |
| `dinosaur` | Dinosaurio | Espada corta | HP máx. |
| `angry_bird` | Pájaro furioso | Pistola de dardos | prob. de crítico |
| `capybara` | Capibara | Pararrayos | velocidad de ataque |
| `doki` | Doki | Bumerán | ganancia de XP |
| `pony` | Pony | Arco de caza | velocidad |
| `cj7` | Cj7 | Aura | robo de vida |
| `magic_pumpkin` | Calabaza mágica | Látigo de espinas | espinas |
| `pokemon` | Pokemon | Orbes espirituales | daño |

### Caja de mascotas

`scripts/world/pet_box.gd` (`PetBox extends Interactable`, escena
`scenes/world/PetBox.tscn`, grupo `pet_boxes`, `marker_kind` `&"pet_box"`).
**Gratis**: el traficante vende una *elección* de tres por puntos; la caja
es la versión que te encuentras, y su precio es haber caminado hasta ella.

Tira una mascota distinta de la que llevas. Sin mascota, la da directo;
con mascota **pregunta** por `UpgradeCardUI.open_choice`, con
**«Cambiar por %s» como opción 0** — el harness siempre pulsa la primera,
así que la rama interesante tiene que ser la que ejercita. Log
`Pet box opened:`, **antes** del `Pet joined:` que imprime `set_pet`.

La siembra el `WorldDirector`: fila `pet_box` (peso 0.35) y 0-1 al empezar
la etapa (`start_pet_box_chance`).

## Vendedores

`scripts/world/vendor.gd` (`Vendor extends Interactable`, grupo `vendors`,
`marker_kind` `&"vendor"`), tres kinds en una tabla `VENDOR_LIBRARY`.

**El puesto es dueño de la ECONOMÍA** (qué cobra, qué entrega, el log y la
regla de una sola venta); **`scripts/ui/vendor_ui.gd` es dueño del
momento** (qué hay en el mostrador, qué dice una carta, qué pasa entre el
clic y la despedida). Un kind nuevo es una fila aquí, una rama en
`VendorUi._build_offers` y una en `Vendor.buy`.

| kind | Qué vende | Precio |
|---|---|---|
| `animals` | 3 mascotas ≠ la que llevas, con arma y estadística en la carta | `pet_price` fijo (120) |
| `powerups` | 1 power-up al azar, **nunca la estrella** | `RunState.powerup_vendor_price`, empieza en 100 y **×1.5 por compra**, a nivel de partida |
| `items` | 4 objetos, cada uno con su rareza tirada con la suerte del comprador | `RunState.chest_price(rareza)`, y la venta cuenta como cofre abierto para la inflación |

- **El kind se tira a escondidas.** El anuncio es «¡Llega un vendedor!» y
  la baliza no lo dice: caminar hasta allá para averiguar cuál es **es** el
  evento. El marcador del mapa sí lleva el color del puesto, pero está
  bajo niebla como todo POI, así que tampoco lo adelanta.
- **Se va después de UNA venta**; si el menú se cierra sin comprar, el
  puesto **se queda** pero ignora `interact` durante `retry_cooldown` 20 s
  — el harness re-dispara interactuar cada 0.75 s mientras espera, y sin
  eso el menú se reabriría en el frame siguiente para siempre.
- **Máximo 2 vivos** (`max_vendors`), por el mismo canal de peso 0 que usan
  los altares y el manantial.
- `VendorUi` sigue el patrón de `roulette_ui.gd`: `CanvasLayer` capa 15,
  `PROCESS_MODE_ALWAYS`, grupos `ui_blocking` + `blocking_ui_closable`,
  pausa el árbol y **siempre** la devuelve, se cierra sola si el comprador
  o el puesto desaparecen, y en headless **se juega sola**: compra la
  primera oferta que puede pagar o se va a los 3 s.
- Las ofertas se tiran **una vez** en `_ready`: el panel se redibuja tras
  cada clic, y un mostrador reconstruido en el redibujo cambiaría la
  mercancía bajo el cursor.
- Logs `Vendor arrived: <kind>` y `Vendor sold: <kind> <id> <precio>`, este
  **antes** de entregar, para que el soak lea causa y después efecto.

## Añadir un personaje

- Qué es: arma inicial + pasiva escalable, todo datos; el select y el spawn del Player leen la fila, no hay código por personaje.
- Archivos: `scripts/systems/character_catalog.gd` (`CHARACTER_LIBRARY`, 13 filas), consumidores: `scripts/player/player.gd` (`_apply_character`), `scripts/ui/character_select.gd`, `scripts/systems/player_stats.gd`.
- Fila: `id`, `display_name` (los nombres propios **no se traducen**, glosario regla 5), `blurb`, `weapon_scene` + `weapon_node_name` (**debe** coincidir con el `node_name` de `WEAPON_LIBRARY` para que el pool lo vea como poseída), `weapon_display_name`, `passive_description`, `passive_stat` + `passive_amount`, `tint`.
- Los campos **obligatorios** se leen duro a propósito (una fila malformada revienta de inmediato); solo los opcionales usan `.get()` con default. No conviertas los primeros a `.get()`: convierte un error de datos en un personaje silenciosamente roto.
- `passive_kind` (opcional): `"per_level"` (defecto), `"speed_to_damage"` (Juno) o `"evasion_execute"` (Nyx). `passive_base` = cantidad ya activa a nivel 1 (Doc). Ids de stat = los de `PlayerStats._apply_effect`.
- Desbloqueo: `unlock_cost` en esquirlas (0 = inicial); opcional `unlock_boss` (id de minijefe secreto cuya muerte lo regala, resuelto por `SecretBossBase` vía `CharacterCatalog.by_unlock_boss`) + `unlock_hint`.
- El grid del selector deriva sus columnas del tamaño del catálogo y tiene scroll: añadir filas ya no descuadra la pantalla. Los textos de tarjeta se recortan con elipsis por número de líneas, no por medición — una pasiva mucho más larga que la de Nyx conviene mirarla en pantalla.

## Añadir un tomo

- Qué es: pasivas apilables (máx. 5 stacks) que alimentan la capa de stats del jugador.
- Archivos: `scripts/systems/tome.gd` (`TOME_LIBRARY`, 15 filas), aplicado por `scripts/systems/player_stats.gd`; las cartas las genera `upgrade_pool.gd` (`_tome_entries`).
- Fila: `id`, `display_name` («Tomo de X» / «Tomo del X», glosario), `description` (el `%d` se rellena con la cantidad del **primer** efecto), `effects: [{stat, amount}]`. Una fila nueva basta: el pool ofrece el siguiente stack automáticamente.
- Ojo con el nombre: `hud.gd` recorta el prefijo para la sigla de la tira de equipamiento usando `TOME_NAME_PREFIXES`, **ordenado del más largo al más corto** (`"Tomo del "` antes que `"Tomo de "`). Al revés, «Tomo del Azar» quedaría como «l Azar». Un prefijo nuevo se añade ahí respetando ese orden.
- Escalado: `amount` es el valor a potencia Común; la rareza de la carta lo multiplica (`UpgradePool.RARITIES`: Common 1.0 / Rare 1.5 / Epic 2.0 / Legendary 3.0). La `luck` del jugador inclina los pesos al tirar.
- Ids de stat de `_apply_effect`: `damage, cooldown, area, move_speed, crit_chance, crit_damage, lifesteal, evasion, armor, luck, thorns, max_hp, projectiles, duration, xp_gain, difficulty, gambling`. Ojo: el id `cooldown` sigue siendo enfriamiento por dentro, pero **se muestra como «velocidad de ataque» en positivo** (GLOSARIO regla 7, iteración 46) — no cambies la matemática al tocar una etiqueta. `difficulty` es **run-wide**: cada jugador publica su total con `RunState.set_difficulty_source("tomes_p<slot>")`.

## Añadir un enemigo

- Qué es: chasis compartido de horda (gravedad, seek + separación, giro, trepada, muerte con gema de XP) con hooks virtuales.
- Archivos: `scripts/enemies/enemy_base.gd` (`EnemyBase`), spawner: `scripts/systems/enemy_spawner.gd`, ejemplos: `grunt.gd` (melee), `skirmisher.gd` (a distancia), `tank.gd`, `sunspitter.gd` (láser), `duneburrower.gd` (emboscada).
- Escena: raíz `CharacterBody3D` en grupo `enemies`, hijos `Health` (`scripts/systems/health.gd`), `Visual`, `CollisionShape3D`; exporta `xp_gem_scene`.
- Hooks a sobreescribir: `_behavior_tick(delta)` (cooldowns), `_movement_intent(seek, distance)` (a dónde ir), `_combat_tick(player, distance)` (atacar), `_facing_direction(...)` y **`_apply_elite_damage(mult)`** (multiplica los números de daño propios — lo llaman los shiny y `apply_tier_scaling(hp, dmg, xp)`).
- **AoE consciente de la party (iteración 45)**: un ataque de área telegrafiado se resuelve con `damage_players_in_disc(centro, radio, ventana_y, daño)` o `damage_players_in_discs(spots, radio, ventana_y, daño)`, **nunca** con «buscar al jugador más cercano». Ambos devuelven los cuerpos golpeados (el Entomb del Sarcognath enraiza exactamente a quien alcanzó) y respetan la regla de «un impacto máximo aunque los discos se solapen» **por jugador**. Nueve resolutores mono-objetivo se arreglaron con este helper; no reintroduzcas el bucle.
- Overlay de material: hay **un solo** punto de verdad con precedencia shiny > variante > estado (`current_overlay()`). Un efecto que pinte al enemigo pasa por ahí; escribir `material_overlay` a mano borra el tinte de otro sistema (era el bug del veneno que borraba la variante).
- `_tick_climb` está extraído de `_physics_process`: la trepada (`can_climb`/`climb_speed`, con `is_on_wall()` y steering activo) tiene estado propio y techo, y la posición se clampa a `arena_bounds`. El resto de `_physics_process` **no** está partido a propósito: es el bucle más caliente del juego y tiene optimizaciones deliberadas (snapshot por tick, stagger de separación).
- `spawn_chest(at, luck_bonus, min_rarity)` es el único camino a un cofre soltado, compartido por el cofre shiny (`elite_chest_chance × (1 + difficulty_bonus)`) y el anillo del jefe.
- Otros hooks del chasis: `apply_poison(dps, duración)` (tick de 0.5 s, gana el dps más fuerte y el timer más largo), `apply_slow`, `apply_variant("berserker"|"shade")`, `make_elite()`, `death_burst_color()`.
- **Shiny** (iteración 47, antes «élite»): los identificadores en inglés no cambian (`is_elite`, `make_elite`, `elite_*`, `Elite chest dropped:`); lo que cambió es el texto visible (glosario: **shiny**) y el look. En vez del tinte ámbar plano, `_apply_elite_glow()` deja un overlay **por cuerpo** cuyo tono recorre la rueda de color y cuyo brillo late (`_tick_shiny`, constantes `SHINY_*`), con una fase inicial distinta por `get_instance_id()` para que una horda no parpadee al unísono. **Solo material**: nada de partículas ni de FX pooled — el soak de refuerzo de shiny vuelve shiny a todos los cuerpos y un emisor por cuerpo vaciaría los pools.
- Para que spawnee: en `enemy_spawner.gd` añadir un `@export var ..._scene`, una rama en `_scene_for(kind)` y pesos en las tablas de fases `FOREST_PHASES` / `DUNES_PHASES` / `MARSH_PHASES` (`phase_preset` elige tabla por arena). Asignar la escena en el nodo `EnemySpawner` de cada arena — `_ready` **valida** que toda `kind` activa tenga su `PackedScene` y avisa si falta.
- **Nada aparece encima de un raider** (iteración 48): `min_player_clearance` (5 m por defecto) es la distancia mínima a **cualquier** raider en pie. `_band_position` la trata como parte de «este punto sirve» (rota por la banda igual que con una celda bloqueada) y **`_make_enemy_at` es la puerta única**: todo camino de spawn —anillo, hordas, ráfagas, invocaciones de jefe, jauría del director— pasa por ahí, así que un llamador nuevo no puede olvidarse de la regla. El jefe se coloca **antes** de instanciarse, para que un anillo sin punto libre reintente en el siguiente tick en vez de anunciar un jefe que no llegó. Los descartes se cuentan e imprimen una vez por minuto de partida: `Spawn skipped: no clearance xN` — sin eso, un cupo mal elegido se come la presión en silencio. El valor está **por debajo** de la banda de ráfaga (7-10 m) a propósito: una horda centrada en un raider tiene que seguir siendo incómoda.
- Spawner: hordas (`horde_minutes`, luego cada `horde_repeat_minutes`; log `Horde:`), jefes recurrentes tras el Elder (`boss_repeat_minutes`, `boss_repeat_growth`), `late_xp_factor()`, `set_sky_event(kind, s)`, `apply_temp_enemy_buff(mult, s)` y `spawn_minions(scene, positions, force_elites)`. El cupo `max_active` se mide sobre el **grupo** `enemies` (cuerpos vivos), no sobre `get_child_count()`, y el temporizador acumula su sobrepaso: la cadencia real coincide con la tabulada.
- WorldDirector — eventos de cielo: `start_sky_event("blood_moon"|"eclipse"|"full_moon")` (grupo `world_director`), probabilidad `sky_event_chance + sky_event_chance_per_demonic × demonic_uses`, tinta `DirectionalLight3D` y `ambient_light_color` con **un solo** tween y los restaura; toda luna oscura encadena una luna llena que da `xp_gain`/`luck` temporales a la party. Log `Sky event:`.

## Añadir un jefe

- Qué es: chasis sobre `EnemyBase` con barra de vida en HUD, clamp de arena, escalado Elder/tier/party y pago en anillo de gemas + orbes de vida.
- Archivos: `scripts/enemies/boss_base.gd` (`BossBase`), ejemplos con máquina de estados propia: `rotking.gd`, `sarcognath.gd`, `fenwraith.gd`; telégrafos: `scenes/fx/TelegraphDisc.tscn`.
- Escena: raíz en grupos `boss` + `enemies`. En `_ready` el chasis ya hace `call_group("boss_ui", "track_boss", self, boss_title)` — la barra del HUD y la flecha de pantalla (`scripts/ui/boss_arrow.gd`) se enganchan solas.
- Sobreescribir **`_scale_attack_damage(mult)`** con los números del moveset. `_apply_elite_damage` delega en él, así que un jefe que pase por `apply_tier_scaling` escala su moveset en vez de quedarse en daño base; `make_elite()` es un no-op en jefes a propósito.
- **`apply_tier(hp_mult, damage_mult = -1.0, payout_mult = -1.0)`** (contrato cambiado en la iteración 45): tres canales separados, `-1.0` = «igual que HP». El spawner los llena así, y la razón está en su comentario: HP lleva rematch × tier × dificultad × tamaño de party; **daño** lleva lo mismo **sin** el factor de party (cuatro cuerpos ya absorben más golpes: escalar también el golpe cobra doble); pago lleva rematch × tier solamente (`RunState.difficulty_xp_multiplier()` ya paga la parte de dificultad al recolectar). Compone: llamarlo dos veces multiplica dos veces.
- Piezas compartidas del chasis: `_clamp_to_arena` y `_safe_arena_point` (respetan `arena_bounds`), `_play_boss_entrance`, `_spawn_spike_cluster`, y **un único slot de tween de señal** (`_play_cue`/`_begin_cue`/`_kill_cue`) — dos telégrafos solapados ya no se pisan el visual.
- Invocaciones: `call_group("enemy_spawner", "spawn_minions", escena, posiciones)`. Los esbirros pasan por **el mismo** escalado que un spawn de anillo (tier, rampa tardía, dificultad, buff temporal, HP de co-op, variante de cielo, tirada de shiny). Instanciarlos a mano se saltaba todo eso.
- Horario: exportado en el spawner y **overrideado por arena** en la escena del mapa — `boss_scene`, `boss_spawn_minute` (5), `elder_spawn_minute` (11), `elder_stat_multiplier`, `elder_title`, `boss_warning_text`. El spawner imprime `Boss spawned:` para los soaks.
- **Ya no existe la maldición de jefes.** `RunState.add_curse` / `consume_curses` y `BossBase.apply_curse` desaparecieron con la iteración 41: el altar demoníaco sube `RunState.difficulty_bonus` para toda la partida y el `CurseLabel` del HUD muestra `Dificultad +N%`. Si ves esos nombres en código o notas viejas, están muertos.
- Jefes ocultos: `extends SecretBossBase` (ver Secretos).

## Añadir un mapa

- Qué es: una fila de catálogo + una escena de arena. **El orden de `MAP_LIBRARY` es el orden de la partida** (iteración 50): una fila nueva insertada en medio cambia la progresión de todos inmediatamente. No hay desbloqueos de mapa ni grados; a un bioma se llega jugando.
- Archivos: `scripts/systems/map_catalog.gd` (`MAP_LIBRARY`), `scripts/world/run_root.gd`, `scripts/world/arena.gd`, `scripts/world/scatter.gd`, arenas existentes como plantilla.
- Fila: `id`, `display_name` (topónimo, mayúscula en las dos partes), `blurb`, `scene_path`, `palette`. Nada más: `unlock_stat`, `locked_hint` y `tiers` desaparecieron con los grados.
- Escena de arena (copiar `AshDunes.tscn`): raíz `Node3D` **con `scripts/world/arena.gd` y su `map_id`**, `WorldEnvironment` + luz, `Floor` y `Perimeter` (muros, capa 1), `Backdrop` (`scripts/world/backdrop.gd`, sus anillos de colinas se derivan de `arena_half_extent`), spots de verticalidad y props a mano (en grupo `scatter_keepout`), nodo de scatter con `scatter.gd` (seed determinista; su `arena_half_extent` es la **fuente única del tamaño de arena** — 120.0 = 240x240 — publicada por el grupo `arena_bounds`, la leen `BossBase` y `EnemySpawner` restando su margen), `Interactables`, `EnemySpawner` (con `phase_preset` y sus escenas/horario), `AmbientBed`, un nodo **`Terrain`** con `scripts/world/terrain.gd`, su `amplitude` del bioma y el `ShaderMaterial` del suelo en `surface_material` (colocado **después** del scatter en orden de árbol), y un `Marker3D` llamado `SpawnPoint` (dónde aterriza el equipo). Los muros del `Perimeter` se escriben **estáticos** en la escena: formas `(1, 17, 242)` / `(242, 17, 1)` centradas en ±120.5 y y = 3.5. Unos **13 POI barajables** bajo `Interactables`. **NO** instancia `RunSystems.tscn`: eso vive una sola vez en `Run.tscn`.
- Los `@export` del `EnemySpawner` los overridean las tres arenas en su `.tscn`: mover esos exports a un colaborador rompe los tres mapas. Si hace falta partir el spawner, hay que migrar las escenas a la vez.

## Partida por etapas

Una partida es una **secuencia de etapas**, una por mapa, en el orden de `MAP_LIBRARY`, volviendo al primero con **vuelta + 1**. Lo que cruza de etapa es todo lo del equipo — nivel, armas, tomos, objetos, mascotas, puntos, boons de altar, boons temporales, la dificultad de partida y la inflación de precios de cofre y ruleta —; **no se copia nada, porque no se recrea nada**: los raiders son los mismos nodos. Lo que se reinicia es el mapa y lo que cuelga de él (cofres, altares, portales, balizas, enemigos, props), el reloj de etapa y el horario de jefes.

### Piezas

| Archivo | Qué hace |
|---|---|
| `scenes/world/Run.tscn` + `scripts/world/run_root.gd` (`RunRoot`, grupo `run_root`) | La raíz persistente. Hijos: `RunSystems` y `ArenaHost`. API: `arena_root()` / `current_arena()`, `advance_stage()`, y el estático `RunRoot.stage_parent(tree)`. |
| `scripts/world/arena.gd` (`Arena`, grupo `arena_root`) | Raíz de cada bioma. `map_id`, `SpawnPoint`, y el **orden** del ciclo de vida. |
| `scripts/world/exit_portal.gd` (`ExitPortal`) | El portal de salida de la etapa. |
| `RunState` | `stage_index`, `lap`, `stage_time`, `stage_boss_dead`, `stage_cleared`, `pseudo_infinite_time`, `stages_cleared_total`, `endless_seconds_total`, `laps_completed`, `visited_map_ids`, `cleared_map_ids`, señal `stage_changed(stage_index, map_id)`, y `begin_stage()` / `mark_stage_cleared(map_id)`. Los índices son **0-based**; todo lo que ve el jugador (o un log) imprime `+ 1`. |

### El orden del ciclo de vida de una etapa (es load-bearing)

1. `RunRoot._load_stage()` instancia la arena y la cachea **antes** del `add_child` (el scatter y el `_ready` de la arena ya preguntan por `arena_root()`).
2. Al entrar al árbol, `scatter._enter_tree` siembra su RNG y **construye la máscara** de la etapa.
3. Corren los `_ready` de los hijos (spawner, ambiente, interactuables de escena).
4. `Arena._ready()` llama `world_director.on_stage_started(arena)` por grupo: cachea los bounds, **re-cachea el Sol y el `Environment`** (ver abajo), baraja los POI de suelo, aplica el inicio irregular y coloca portales y ruletas.
5. `Arena._ready()` llama `scatter.place_props()`, así que la lista de keepouts ve las posiciones **ya barajadas** — exactamente el orden que producía el viejo reparto `_enter_tree`/`_ready` cuando cada arena tenía su propio director.
6. `RunRoot` coloca al equipo (`run_systems.place_party(origin)`, que reusa la geometría del anillo de co-op y **re-ancla el rescate del vacío** de cada cuerpo) y emite `stage_changed`.

**Por qué el re-cacheo de luces es obligatorio**: `_cache_lights()` sale temprano si `_sun` ya está puesto, y `_exit_tree` (que restauraba la luz) ya no se dispara nunca, porque el director sobrevive a la arena. Sin ponerlas a `null` en `on_stage_started`, la segunda etapa tintaría el Sol liberado de la primera y **ningún evento de cielo se vería** a partir de ahí. El soak lo comprueba: el harness dispara una luna de sangre 5 s después de cada cambio de etapa.

### El cambio de etapa (`advance_stage`)

Corre dentro de `ScreenFade.transition_async(action)` — el hermano que **espera** a la acción entre el fundido de entrada y el de salida, cosa que `transition()` no puede hacer (su acción va en un `tween_callback`, y una corrutina vuelve al tween en su primer `await`). Pasos:

1. Cierra todo menú bloqueante que acepte cierre por código (`call_group("blocking_ui_closable", "dismiss")`, iteración 58: esas capas cuelgan de la ARENA y el paso 5 las liberaba sin pasar por su `_close()`, que es lo único que devuelve la pausa), pausa el árbol **y para explícitamente el spawner**; el director se detiene **a sí mismo** en `on_stage_ended` (paso 3), no aquí. La pausa sola no basta: los `process_mode` se **heredan**, y el harness de soaks enraiza toda la partida bajo un nodo `ALWAYS`, así que un árbol «pausado» ahí sigue generando enemigos. Un spawner trabajando mientras se desmonta su arena metió seis enemigos en el primer `Stage sweep:`.
2. `Stage carry:` con lo que lleva el equipo, leído de los nodos vivos.
3. Desmontaje: liberar todo enemigo con `free()` (no `queue_free()`: el barrido cuenta en el mismo frame), `Pools.release_all_live()` (cada `NodePool` mantiene un conjunto de vivos y los reclama de inmediato), `world_director.on_stage_ended()` y liberar los restos de etapa (cofres, altares, portales, ruletas, manantiales, balizas, gemas, orbes). **Un prompt posterior añade sus propias clases a esas listas.**
4. `await get_tree().process_frame` y `Stage sweep: enemies=%d gems=%d orbs=%d chests=%d altars=%d beacons=%d pickups=%d boxes=%d vendors=%d possessed=%d` (diez campos; `tools/verificar.sh` greppea el literal completo) — **todos en cero**, o hay una fuga que seguiría al equipo al mapa siguiente.
5. Liberar la arena.
6. Avanzar los contadores (`lap += 1` al envolver) y construir la etapa siguiente por el ciclo de arriba.
7. Banner «Etapa %d — %s», `show_stage_tag`, log `Stage advanced:` y `Stage carry:` otra vez. **Las dos líneas de acarreo tienen que coincidir**: es la prueba de que cruzar no cuesta nada.

### Dónde se parentan las cosas

`RunRoot.stage_parent(tree)` es **el** padre de todo lo que se spawnea al mundo: pooled FX, proyectiles, cofres soltados, púas de jefe, la UI de la ruleta, los minijefes secretos. Antes todos usaban `get_tree().current_scene`, que **era** la arena; ahora `current_scene` es la raíz persistente, así que spawnear ahí arrastraría los dardos y los charcos de la etapa 1 a la etapa 2. `Pools._spawn_parent()` hace lo mismo. Los únicos `current_scene` que quedan son los de esos dos helpers (su fallback fuera de partida) y los del harness.

### La puerta de etapa y el modo pseudo-infinito

- **Puerta** (`RunManager`): la etapa se supera cuando `RunState.stage_time >= stage_goal` (900 s) **y** el jefe de etapa (el Elder) está muerto. Una arena sin `boss_scene` cuenta como «jefe muerto». Log `Stage gate: time=%.1f boss=%s`, y `Stage boss slain:` cuando cae el Elder (`EnemySpawner._watch_stage_boss`, conectado a **esa** instancia: los jefes recurrentes posteriores no reabren nada).
- Superarla abre el **portal de salida** (`WorldDirector._tick_exit_portal`, a `exit_portal_min_distance` 40 m o más de todo raider, con baliza hasta usarse) y la flecha de jefe lo apunta mientras no viva ningún jefe (`track_objective`). Logs `Exit portal opened at %.1fs` y `Portal used: exit`.
- **Pseudo-infinito**: mientras la etapa está superada, cada minuto de `RunState.pseudo_infinite_time` suma HP +15%, daño +10% y velocidad +4% (con tope `endless_speed_cap` 1.8), comprime el intervalo de spawn ×0.85 y agranda las hordas ×1.5. Exports en el spawner (`endless_*`), aplicados en spawns frescos; la velocidad es su canal propio porque `apply_tier_scaling` cubre HP/daño/pago solamente. Log `Pseudo-infinite: minute %d hp x%.2f dmg x%.2f speed x%.2f`, uno por minuto.
- **Vueltas**: los grados de mapa desaparecieron; su lugar lo ocupa `lap_hp_mult` 1.5 / `lap_damage_mult` 1.3 / `lap_xp_mult` 1.3 por vuelta completa, aplicados por el mismo canal `apply_tier_scaling` / `apply_tier`.
- El horario de jefes y las hordas leen **`RunState.stage_time`**, no `run_time`: cada mapa tiene su jefe en el minuto 5 y su Elder en el 11. Las rampas globales (intervalo, conteo, rampa tardía) siguen leyendo `run_time`.

### Interruptores del harness

`BONK_STAGE_FAST=1` supera la etapa a los 60 s y sin jefe; el harness se queda entonces `PSEUDO_INFINITE_DWELL` (70 s) antes de ir al portal, para que la rampa registre al menos un minuto, y después abandona su ruta y va directo. `BONK_ARENA` ya no nombra la escena a instanciar sino el **bioma inicial** (`GameConfig.start_map_id`); el harness siempre arranca `Run.tscn`. `BONK_SAVE_PATH` re-apunta el guardado antes de la primera lectura, para cualquier arranque headless que no sea el probe.

## Terreno

Desde la iteración 51 el suelo de una arena **no es una placa plana**: es
`scripts/world/terrain.gd` (`class_name Terrain extends StaticBody3D`, grupo
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
  - **De dónde sale esa semilla** (corregido en la iteración 52): de
    `randi()`, es decir del **stream de la partida**, el que
    `RunState.reset()` acaba de sembrar. Antes era `_rng.randomize()`, que
    resiembra desde la entropía del sistema y **es sorda** a ese `seed()`:
    `BONK_GAME_SEED` no reproducía nada: dos soaks con la misma semilla
    salían con máscara, props y relieve distintos (medido: `168/576` vs
    `167/576` celdas bloqueadas, `min=-1.8 max=1.8` vs `min=-2.1 max=2.0`).
    Lo encontró la puerta de niebla de esta misma iteración, comparando dos
    corridas que debían ser idénticas. Una partida normal no cambia: ahí
    `reset()` hace `randomize()` sobre el mismo stream.
- **Orden de construcción**: se arma en `_ready`, que corre **antes** de
  `Arena._ready` (los hijos primero) y **después** del `_enter_tree` del
  scatter, así que la máscara y los sitios de meseta ya existen. Quien pueda
  correr antes (el `Backdrop` es el hijo #2 y lee `min_height` en su propio
  `_ready`) llama `ensure_built()`, que es idempotente.
- **API**: `height_at(x, z)` (bilineal sobre la misma rejilla que tiene el
  cuerpo físico), `height_at_xz`, `snap(pos)`, `min_height`, `max_height`,
  `map_image(px_per_meter)` (tinte del bioma sombreado por altura, para el
  minimapa y el mapa de Tab), `add_pad(centro, radio)`.
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
  mezcla de 6 m. **Nunca bajo los POI barajables**, cuyo XZ cambia después: a
  esos se los apoya en el relieve. Una banda de `rim_flat_band` 10 m aplana el
  borde para que los muros estáticos y el disco del backdrop encuentren suelo
  llano.
- **Regla de nulos**: quien corre desde `on_stage_started` en adelante trata un
  `find()` nulo como un `push_error` una vez; quien corre en construcción
  (Backdrop, HUD, overlay) lo tolera en silencio y se reconstruye al empezar la
  etapa.

### La regla de apoyado

**Nada se coloca a y = 0.** Todo pasa por `Terrain.height_at`:

| Dónde | Cómo |
|---|---|
| Props del scatter | `_spawn_prop` **ignora** el `pos.y` que le pasan y usa `ground_height()` |
| Rocas de máscara, línea de perímetro, mesetas | por el mismo `_spawn_prop` |
| Puntos del director | `_claim_clear_point()` → `_terrain_height()` |
| Eventos, portales, ruletas, altares, manantiales, cofres de evento | `_event_point()` / `_claim_clear_point()` |
| Portal de salida | candidatos a y = 0, apoyados por `_ground_height` |
| POI barajados | `_shuffle_ground_interactables` apoya los autorizados por debajo de `POI_PLATFORM_Y` 0.5; los de plataforma conservan su y |
| Spawn del equipo | `Arena.spawn_origin()` y `RunSystems.place_party` (cada offset del anillo lee su propia altura) |
| Anillo de cofres del jefe | uno por uno en `BossBase._drop_chests` |
| Spawns de enemigos | `_ring_position` → `_ground_height` |

**Las dos sondas de suelo** (`WorldDirector._ground_height`,
`EnemySpawner._ground_height`) ahora barren **todo** el relieve —de
`max_height + 30` a `min_height − 2`— y su fallback ya **no es 0** sino
`height_at`: cero es una altura real en un heightmap, así que el viejo
fallback enterraba o levitaba lo que colocara. Una meseta sobre una colina
quedaba por encima del inicio del rayo y una hondonada por debajo del final.

**Las dos puertas del harness se reescribieron con el terreno, no se
aflojaron**: el barrido de máscara centra su cápsula en
`height_at(muestra) + SWEEP_CAPSULE_CENTER_Y` y **excluye el RID del terreno**
de la consulta (una cápsula que toca el suelo no es una apertura; rocas, props
y muros siguen contando); el vigilante de celda bloqueada compara
`y − height_at(xz)` contra `FLOOR_STAND_MAX_Y`.

## Arena irregular

- Qué es: cada partida el cuadrado de **240x240** recibe una **máscara de celdas** (`scatter.gd`, grupo `arena_bounds`): `mask_cell_size` (10 m, o sea 24x24 celdas), entre `mask_blobs_min` y `mask_blobs_max` (13-22) manchas por paseo aleatorio se bloquean (nunca las celdas del spawn ni las de los spots de verticalidad), y un flood fill 4-vecinos desde el spawn **sella** cualquier bolsa no alcanzable. Si queda menos de `mask_min_open_fraction` abierto se reintenta con menos manchas. Las celdas bloqueadas se llenan con **rocas de verdad** (iteración 48): una retícula de `mask_rocks_per_side`² props con jitter (`mask_rock_jitter`) y escala en `[mask_rock_scale_min, mask_rock_scale_max]`, **cubriendo la celda entera, frontera incluida**. Los enemigos trepadores pueden cruzarlas, el jugador no.
  - **Se acabaron los muros invisibles.** Antes cada celda bloqueada llevaba un `StaticBody3D` de 10×7×10 m (`MaskWalls`) con rocas encima de adorno: chocabas contra nada, y —peor— los trepadores subían los 7 m y **caminaban por arriba**, que es exactamente el reporte de «enemigos volando» (medido: y ≈ 7.0-7.5 con `velocity.y` = 5.5 = `climb_speed`). Sin esos cajones, la altura máxima que alcanza la horda es la cima de la roca más grande (≈ 4.0-4.3 m), que además se ve.
  - La cobertura no es opinión: `_fill_budget_gap()` recalcula en runtime el alcance de una roca (inradio en planta del casco × escala mínima + radio de la cápsula del jugador) contra el paso de la retícula en diagonal, y **avisa** si alguien afloja los exports por debajo del margen. La primera versión selló solo la frontera y el harness la rechazó: el raider saltaba, aterrizaba sobre las rocas del borde y bajaba al interior hueco.
  - `Rock.tscn` y `DuneRock.tscn` llevan **un `ConvexPolygonShape3D` por blob visible** (2 y 3), con los puntos ya horneados en la transformación del blob para que el `CollisionShape3D` quede en identidad y `_spawn_prop` pueda seguir escalando **uniformemente** (Godot no soporta escalar una forma de colisión de forma no uniforme). Antes el blob lateral no tenía collider.
- API: `is_walkable(Vector2)`, `random_walkable_point()`, `blocked_cell_count()`, `open_cell_count()`, `blocked_cells()`, `cell_center(Vector2i)`, `cell_of(Vector2)` (las tres últimas las usa el barrido de máscara del harness). Consumidores: `EnemySpawner._ring_position` / `_band_position` / `spawn_pressure_burst` (reintentan hasta hallar celda abierta, no clampean), `WorldDirector` (un **único** helper respeta la máscara para portales, ruleta, altares y cofres de evento), `scatter._is_clear`, y el harness de pruebas. La máscara se construye en `_enter_tree` (antes del barajado del director) con el mismo RNG. Log `Arena mask:`, que **imprime la fracción abierta** (la puerta que persigue el bucle de reconstrucción).
- Inicio irregular: `WorldDirector._randomize_starting_pois` elimina cofres/altares colocados con `poi_skip_chance` (conserva al menos el primer cofre) y añade `extra_start_chests_min..max` cofres en puntos libres. Log `Start layout:`.

## Minimapa y mapa (Tab)

Desde la iteración 52 cada vista de jugador tiene **su propio** minimapa en la
esquina y **su propio** mapa a pantalla completa con Tab. En 240×240 con
relieve, «¿dónde estoy y dónde está lo que no he abierto?» dejó de ser
respondible mirando alrededor.

### Las tres piezas

| Pieza | Qué es | Dónde vive |
|---|---|---|
| `FogOfWar` | lo que el equipo **ha visto** de la etapa | `scripts/systems/fog_of_war.gd`, nodo de `RunSystems.tscn`, grupo `fog`, `static find(tree)` |
| `MapDraw` | **el** dibujante: fondo, composición con niebla, marcadores, proyección | `scripts/ui/map_draw.gd` (`RefCounted`, `MapDraw.new(get_tree())`) |
| `Minimap` / `MapOverlay` | los dos consumidores | `scripts/ui/minimap.gd`, `scripts/ui/map_overlay.gd`, ambos creados por el HUD |

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
- `composite()` — en el tick de refresco (10 Hz). Fondo × niebla en una única
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
- `powerup` (53), `vendor` y `pet_box` (54) ya están en uso, con su fila en
  `MARKER_LABELS` para la leyenda. Queda **`lucky_block` reservado para la
  parte C2**. Esa parte solo
  tiene que poner el `marker_kind` en su nodo; aquí no se toca nada.
- Un nodo puede además implementar `map_marker_color()` para pintarse con su
  propio color (rareza de cofre, por ejemplo) sin tocar la tabla.

### Los dos consumidores

- **`Minimap`** (150 px): norte arriba, marcadores a 0.75 de escala, refresco
  0.1 s. En solitario va arriba a la derecha, **bajo la insignia de FPS**; en
  co-op, uno por celda de pantalla dividida.
  - **Dónde empieza, exactamente (iteración 61).** La columna de arriba a la
    derecha es una **pila**: `%KillsLabel` (arriba 22), `%PointsLabel` (56) y
    la insignia de FPS (88), y el mapa cuelga **debajo de las tres**
    (`MINIMAP_TOP_UNDER_HUD` = offset de la insignia + su alto + 8). Esa
    regla la aplica **toda celda que toque el borde superior de la ventana**,
    no solo la de una partida en solitario: la pila está anclada a la
    ventana, no a la celda. Hasta la 60 el inset extra era `46` y solo se
    aplicaba en solitario, así que el mapa arrancaba en y 60 y tapaba la
    etiqueta de puntos y la insignia de FPS —y en co-op, sin inset ninguno,
    también las bajas— (L5-1 de la auditoría de la ronda 2, diferido allí
    por ser solo visible al renderizar y confirmado en pantalla aquí).
- **`MapOverlay`**: capa **8** (bajo `UpgradeCardUI` 10 — una carta abierta
  tiene que verse por encima), `PROCESS_MODE_ALWAYS`, grupo `map_overlay`.
  Cabecera «Etapa N · Vuelta M — MM:SS», leyenda abajo a la izquierda y tres
  paneles a la derecha: **Estadísticas** (toda la capa derivada, con
  `cooldown_multiplier` mostrado como **velocidad de ataque en positivo**,
  regla 7 del glosario), **Jugadores** (HP, nivel y puntos de los cuatro slots,
  caídos incluidos) y **Objetos** (objetos con copias, armas con nivel, tomos
  con su numeral).
- **No pausa la partida.** Es un mapa, no un menú: el mundo sigue vivo detrás,
  y por eso el overlay tampoco entra en `ui_blocking`. Se oculta solo si la
  partida no está activa, si el árbol está pausado o si el slot no tiene raider.
- **Todo Control de ambos widgets es `FOCUS_NONE` y `MOUSE_FILTER_IGNORE`**
  (`_own()`): **Tab es `ui_focus_next` de Godot**, así que un solo Control
  enfocable dentro del overlay se come la tecla y el mapa deja de cerrarse.
  Es la trampa de esta iteración; si añades un Control aquí, pásalo por `_own`.
- El HUD los construye: `_build_map_widgets(count)` crea un par por jugador y
  `_anchor_to_cell` los ancla usando **`SplitScreenView.cell_rect(i, n)`**, que
  era `_cell_rect` privado y se hizo público exactamente para esto (con un caso
  `1:` explícito que devuelve el rect entero).

### Entrada

`map_overlay` es una acción nueva de `project.godot` (Tab por keycode físico,
botón **BACK** en control) y está en `Coop.BASE_ACTIONS`, así que cada slot
tiene su `p1_map_overlay`, `p2_map_overlay`… ligado solo a su dispositivo: en
co-op cada jugador abre **su** mapa.

## Power-ups

Desde la iteración 53 hay **power-ups temporales**: efectos ruidosos y
breves (20 s; la estrella 15) que caen de las bajas, salen del manantial y
los vende un vendedor. No son tomos ni objetos: no se acumulan, no se
eligen en una carta y **se sienten sin leer un número**.

### Las cuatro piezas

| Pieza | Qué es | Dónde |
|---|---|---|
| `PowerUpCatalog` | las 10 filas | `scripts/systems/powerup_catalog.gd` |
| `PowerUps` | componente por raider: qué está activo y cuánto queda | `scripts/systems/power_ups.gd`, hijo de `Player.tscn`, `PowerUps.find_in(body)` |
| `PowerUpPickup` | la gema en el suelo | `scripts/systems/powerup_pickup.gd` + `scenes/systems/PowerUpPickup.tscn`, grupo `powerup_pickups` |
| `EnemySpawner` | la tirada del drop, el congelado y la puerta de spawn | `roll_powerup_drop`, `spawn_powerup_pickup`, `freeze_enemies` |

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
`clear_timed_boons(tag)`, iteración 53): sin etiqueta, volver a agarrar
Furia apilaría un segundo +100% y la primera expiración se llevaría la
mitad.

### Las filas de comportamiento

| kind | Qué hace | Dónde vive el efecto |
|---|---|---|
| `immortal` | ningún golpe entra | `Health.invulnerable` (+ `Health.blocked_hits`, que el soak lee) |
| `reflect` | el daño recibido vuelve al atacante | `Health.reflect_fraction`, evaluado **antes** del rechazo por inmortalidad |
| `vampire` | robo de vida + **HP máx. permanente por baja** | boon de `lifesteal` + `PowerUps.permanent_max_hp` |
| `gold` | cada baja paga doble | `Player.set_points_source(id, mult)` — un **producto de factores con nombre** |
| `flight` | mantener salto para volar | `Player._tick_flight`, techo sobre `Terrain.height_at` |
| `time_stop` | la horda se congela | `EnemySpawner.freeze_enemies(duration)` |
| `star` | todas las demás, con **su** reloj de 15 s | `PowerUps.apply` recursivo sobre `star_components()` |

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
`flight_rise_speed` hasta `flight_ceiling` metros **sobre el terreno**
(un Y absoluto lo enterraría en una colina de un mapa y lo dejaría en el
cielo en otro); soltar el salto planea. El XZ se limita al
`arena_half_extent` del nodo `arena_bounds` — el borde de arena es un muro
para quien camina y no sería nada para quien vuela.

**Al expirar** (`Player.end_flight()`, un borde y no un estado): si el
raider está sobre una celda **no caminable**, se lo baja al punto caminable
más cercano de entre `FLIGHT_LANDING_SAMPLES` muestras. Sin eso caería
dentro de las rocas de la máscara, que es exactamente lo que el vigilante
de celda bloqueada del harness existe para atrapar. Log `Flight landing:`.

### El drop, la estrella y el manantial

- **Drop por baja**: `EnemyBase._drop_powerup()` →
  `EnemySpawner.roll_powerup_drop(raider, shiny)`. Base
  `base_powerup_drop_chance` 0.004 × (1 + `powerup_drop_chance`/100 del
  raider más cercano) × 5 si el cuerpo era shiny × `BONK_POWERUP_BOOST`.
  **Aquí es donde por fin se consume la estadística `powerup_chance`** que
  la iteración 48 dejó sin consumidor («Fortuna menor» en los altares).
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

Desde la iteración 55 las lunas, las lluvias y los desastres son **un solo
canal** en `WorldDirector`. En código se llama **weather**, nunca «event»:
`EVENT_LIBRARY` es la tabla de POIs del tick de eventos y los dos sentidos
chocarían en cada lectura. La palabra que ve el jugador sigue siendo
«evento» (el altar invoca uno).

**`active_weather` guarda como mucho una fila** (`{id, group, time_left}`),
así que «solo una luna, lluvia o desastre a la vez» es una propiedad de la
estructura de datos y no un acuerdo entre tres temporizadores.

### El catálogo

| id | grupo | duración | sigue a | notas |
|---|---|---|---|---|
| `blood_moon` | moon | 45 s | → `full_moon` | tinte rojo, variante `berserker` del spawner |
| `eclipse` | moon | 45 s | → `full_moon` | tinte violeta, variante `shade` |
| `full_moon` | moon | 40 s | *solo secuela* | XP y suerte temporales |
| `enemy_rain` | rain | 35 s | → `golden_rain` | 3-6 enemigos cada 1.5 s |
| `radioactive_rain` | rain | 40 s | → `golden_rain` | charcos ácidos |
| `golden_rain` | rain | 40 s | *solo secuela* | ×2 puntos y mitad de precio |
| `enemy_tsunami` | disaster | 3 s | — | una ola, puede repetirse |
| `earthquake` | disaster | 25 s | — | sacudida + HUD desplazado |
| `meteor_shower` | disaster | 30 s | — | zonas marcadas, luego impacto |

Campos de fila: `id`, `group`, `weight` (dentro de su grupo), `duration`,
`start`/`tick`/`stop` (nombres de método, `tick` y `stop` opcionales),
`follow_up` y `follow_up_only`.

- **Duración**: `weather_duration_overrides` por arena (mismo patrón que
  `event_weight_overrides`) y, **solo para lunas y lluvias**,
  `RunState.sky_duration_multiplier`. Los desastres son fijos: un pacto que
  vende «lunas más largas» no debe vender también una lluvia de meteoritos
  más larga. *(Esto reemplazó los exports `sky_event_duration` y
  `full_moon_duration`, que no podían vivir dentro de un catálogo `const`.)*
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

El `stop` de la fila viva corre desde `on_stage_ended()` y `_exit_tree()`,
**antes** del `_snap_sky_back()` que ya había: una lluvia dorada que
terminara con la etapa dejaría un multiplicador de puntos ×2 en cada raider
y un descuento de 0.5 en `RunState`, y los dos sobreviven a la arena.
`on_stage_started(arena)` arranca con el canal vacío, y `RunState.reset()`
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
  (`EnemyBase._drop_acid_pool` → `WorldDirector.spawn_acid_pool`), más uno
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

`scripts/world/event_altar.gd` (`EventAltar extends Interactable`, escena
`scenes/world/shrines/EventAltar.tscn`, `marker_kind = &"event_altar"` puesto
en `_init()`, gratis, un solo uso, se hunde). Invoca una fila al azar
**excepto `golden_rain` y `full_moon`**: esas dos son lo que paga haber
sobrevivido a una mala, y un altar que las regalara dejaría sin sentido a
las lluvias y lunas que las ganan. Si ya hay clima corriendo, **rechaza** en
vez de encolar. Log `Event altar used: <id>`.

### La insignia del HUD

Junto al reloj: nombre y segundos restantes, teñida por **grupo** (tres
colores leen como tres tipos de problema; nueve leerían como decoración).
La lee del director en vez de que el director la empuje: es una vista, y un
push necesitaría una señal disparada desde tres grupos distintos.

## Poseídos (Báculo de nigromante)

Lo que mata el báculo **se levanta de tu lado** (iteración 56).

- **El cadáver muere entero primero.** `Health.died` es síncrona, así que
  cuando `deal_damage` regresa `EnemyBase._on_died` ya corrió: gema de XP,
  puntos, orbes, tirada de cofre de élite y bestiario, todo pagado. El
  siervo es una **copia nueva** de la misma escena en el sitio del muerto,
  así que la baja es baja **y** siervo, nunca una en lugar de la otra.
- **Un siervo no paga nada al expirar.** Ya pagó una vez como cadáver, y
  un arma capaz de cobrar dos veces por el mismo cuerpo dejaría a las demás
  en ruido estadístico. `_on_died` corta todos los pagos con la bandera
  `_possessed` y conserva solo la muerte visual.
- **Solo pueden ser poseídos los cuerpo a cuerpo.** El contrato es
  `EnemyBase.possessable` y el interruptor real es
  **`_pick_target() -> Node3D`**, que `_physics_process` usa en vez de
  llamar a `Coop.nearest_player` directo: todo lo de abajo (el seek, el
  encaramiento y `_combat_tick`, que daña la `Health` que le den) ya es
  agnóstico del objetivo, así que ese único override cambia el bando.

| Script | ¿Poseíble? | Por qué |
|---|---|---|
| `grunt`, `tank` | **sí** | su `_combat_tick` daña `Health.find_in(target)`, sea quien sea |
| `skirmisher` | no | dispara `EnemyBolt`s que solo dañan al grupo `player` |
| `sunspitter` | no | su rayo se filtra por el mismo grupo |
| `duneburrower` | no | guarda y restaura sus propias capas y grupo en cada ciclo de excavación |
| `boss_base` (y `rotking`, `sarcognath`, `fenwraith`) | no | los jefes llegan al equipo por `damage_players_in_disc` / `Coop.alive_players` |
| `secret_boss_base` (y `grubthing`, `coffer_mimic`) | no | un minijefe secreto es un jefe, y su muerte desbloquea un raider |

- **Capas**: el siervo sale del grupo `enemies` (que declara la escena), lo
  que de una sola vez lo esconde de las armas del jugador, del conteo vivo
  del spawner y del tiempo detenido — los tres leen ese grupo. Pasa a
  `collision_layer` 8 con máscara 1 (terreno) **más una excepción explícita
  por raider**: los jugadores comparten la capa 1 con el mundo, así que una
  máscara que lo dejara atravesar raiders lo dejaría atravesar el suelo.
- **Cupo** `max_possessed` 12 por portador; el más viejo expira para hacer
  sitio (un cupo que rechazara al nuevo se sentiría roto justo cuando el
  arma funciona). Expira también si el portador muere y en cada cambio de
  etapa. Logs `Possessed spawned:` / `Possessed expired:`.

## Bloques de la suerte

`scripts/world/lucky_block.gd` (`LuckyBlock extends Interactable`, escena
`scenes/world/chests/LuckyBlock.tscn`, grupo `lucky_blocks`, `marker_kind`
`&"lucky_block"` en `_init()`). Parece un cofre y no lo es: **gratis, raro y
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
- Archivos: `scripts/systems/quest_catalog.gd` (`QUEST_LIBRARY`, 40 filas), `scripts/systems/save_data.gd` (autoload `SaveData`), UI: `scripts/ui/quest_log.gd`, fin de partida: `scripts/systems/run_manager.gd`.
- Fila de misión: `id`, `display_name`, `description` (imperativo, tuteo), `stat` (id de contador — **lista canónica en la cabecera de `save_data.gd`**), `target`, `reward`. Un contador nuevo no necesita registro: `bump` crea la clave.
- **Contrato transaccional (iteración 45)**: los sistemas en partida acreditan con `SaveData.bump(id)` / `raise_to(id, valor)`, que caen en un **buffer de partida** (`_run_counters` / `_run_highs`). Solo el fin de partida lo funde en el ledger persistido (`fold_run_results`); `RunState.reset()` lo descarta. Consecuencia observable y deliberada: **abandonar una partida con «Salir al menú» ya no deja rastro de nada** — ni `bosses_killed`, ni `chests_opened`, ni `used_weapon_<id>` para la Colección. Antes esos contadores se filtraban al siguiente guardado y se podían farmear sin terminar partidas.
  - `stat(id)` lee ledger + buffer (para mostrar progreso); la **evaluación de misiones lee solo el ledger**, así que una misión nunca se marca completa con contadores que un abandono va a revertir.
  - Firma actual (iteración 50): `fold_run_results(victory, character_ids, visited_map_ids, cleared_map_ids, stages_cleared, laps, level, kills, run_seconds)`. Una partida recorre **varios** mapas, así que `runs_on_<map>` se acredita por cada mapa **visitado** y `victories_<map>` por cada mapa **superado** — así `dunes_run_1`, `fen_win_1` y compañía siguen funcionando sin tocarlas. `victory` significa «superó al menos una etapa». Los `Array[String]` tienen que ir **tipados**: un literal sin tipo lanza `Invalid type in function`.
  - Las misiones de grado conservan sus ids (`tier2_win`, `tier3_win`) pero ahora son de **vueltas** (`laps_completed`), y las de `best_endless_minutes` cuentan el tiempo en **pseudo-infinito**. Las claves que este build ya no conoce (`tier_choice`, `victories_<map>_t<n>`) simplemente no se leen: un guardado viejo carga limpio y en silencio.
- Escritura en disco: `save()` escribe en `<save>.tmp` y solo renombra al terminar, dejando el anterior como `.bak`. Una escritura interrumpida no puede truncar el archivo real; `load_from_disk()` cae al respaldo e imprime `Save recovered from backup:`.
- El cobro de misiones es manual en el Registro (`claim_quest`). Los harness pueden re-apuntar `SaveData.save_path` a un archivo temporal **antes** de `load_from_disk()`.

## Evoluciones de armas

- Qué es: cada carta invertida en un arma es un nivel de arma (`WeaponBase.upgrade_level`); cada múltiplo de `EvolutionCatalog.EVOLVE_AT_LEVEL` (**10**) es un **hito**. El primero evoluciona el arma si tiene receta; los siguientes —y también el primero para un arma sin receta— son **ascensos**: un escalón plano sin fila de catálogo (`WeaponBase.ASCEND_MULTS`: daño ×1.15, `cooldown_scale` ×0.9, alcance ×1.1, y +1 proyectil en los tiers pares). Así ningún arma deja de mejorar nunca. No intervienen cofres ni tomos.
- `WeaponBase.ascension_tier` cuenta los hitos pasados (la evolución del nivel 10 es el tier 1). El HUD pinta `N%d` (nivel) por debajo del primer hito y `★%d` (tier) desde ahí.
- Archivos: `scripts/systems/evolution_catalog.gd` (`EVOLUTION_LIBRARY`, 15 filas, indexada por `weapon_id`; `try_advance_by_level`), `scripts/weapons/weapon_base.gd` (`upgrade_level`, `ascension_tier`, `evolve()`, `ascend()`, y el aplicador genérico `_apply_stat_tables` que comparten), `scripts/systems/upgrade_pool.gd` (`apply` llama a `try_advance_by_level` tras cada carta de arma), `scripts/ui/hud.gd` (`announce_major`).
- Ceremonia compartida por ambos hitos (fanfarria, sparkle, shake) + banner propio: «¡%s evolucionó a %s!» y «¡%s asciende!». Logs `Weapon evolved:` y `Weapon ascended: <arma> tier <n>`.
- Evolución nueva: una fila con `weapon_id`/`weapon_node`, `evolved_name`, `mults`/`adds` (aplicados genéricamente sobre cualquier propiedad del arma vía get/set) y `flavor` para la Colección. El banner busca el `display_name` traducido en `WEAPON_LIBRARY`, no capitaliza el id. La ceremonia bumpea `evo_<weapon_id>` + `evolutions_total` e imprime `Weapon evolved:`.
- `evolution_catalog.gd` tiene funciones `static`; para alcanzar autoloads desde ahí hay **un** helper estático en el archivo, no `Engine.get_main_loop()` repetido.

## Cartas de mejora: multi-stat y topes

- Una entrada del pool puede llevar `effects: [{property, op, amount}, ...]` en vez del trío `property/op/amount`: todos los efectos caen sobre el mismo `target` en una sola carta y la descripción lleva un `%d` por efecto. `_entries_for_weapon` genera dos por arma («Temple», «Ritmo de batalla»), con sus escalones en `TEMPERED_STEPS` / `RHYTHM_STEPS`.
- Las descripciones de cartas por arma **concatenan** el sustantivo delante (`"Daño de " + display + " +%d%%"`) en vez de usar `%s`: así el número de marcadores no cambia con el idioma.
- Topes por jugador: `Player.max_weapons` (5) y `Player.max_tomes` (5 tomos **distintos**; al llegar, el pool solo ofrece stacks de los ya poseídos — `PlayerStats.distinct_tome_count()`). **No hay tope de stacks ni de nivel de arma** (iteración 46): un tomo se apila indefinidamente y `Tome.stack_label(n)` construye el numeral romano para cualquier `n`, tanto en el título de la carta como en la esquina del HUD.
- **Un lado por subida de nivel** (iteración 46): cada carta de nivel ofrece *o* armas (cartas de arma poseída + `new_weapon`) *o* tomos/stats (entradas de tomo + `GENERIC_POOL`), nunca mezclado. `UpgradePool.roll_side(player)` elige el lado al azar ponderado por cuántas entradas tiene cada uno y jamás devuelve un lado vacío; `build_pool(player, side)` lo materializa y el título de la UI lo nombra («Nivel 7 — elige: Armas»). Los picks de bonificación (`open_bonus_pick`: cofres, santuarios) pasan `side = ""` y siguen mezclando.
- **Curva de XP** (`RunState._xp_required`): lineal más un término cuadrático (`XP_PER_LEVEL_SQUARED`). Los primeros niveles no cambian; el 10 cuesta 50 (antes 35) y el 20 cuesta 125 (antes 65).
- Los nombres de los escalones de carta de arma están en constantes con nombre, no en literales repartidos.
- Rareza: `UpgradePool.RARITIES[].name` es un **identificador** (`Common`/`Rare`/`Epic`/`Legendary`) que llavea precios de cofre, el campo `rarity` de `ITEM_LIBRARY` y los pisos `min_rarity`. Para pintarla, `UpgradePool.rarity_display(id)` — ver Convenciones.
- Balance a vigilar: la curva de suerte de `_rarity_weights` se arregló en la iteración 45 (todo punto por encima de 50 era un no-op); los pesos se mueven de verdad en la banda 10-50.

## Colección, Armería y modos meta

- **Colección** (`scripts/ui/collection.gd` + `scenes/ui/Collection.tscn`, `extends MetaScreen`): lee contadores de `SaveData` — `used_weapon_<id>` (bump en `Player._apply_character` y `UpgradePool._grant_weapon`), `evo_<id>`, `kills_<script>` (bump en `EnemyBase._on_died`, keyed por nombre de archivo del script — un enemigo nuevo entra al bestiario añadiendo su fila a `BESTIARY` en `collection.gd`). Recuerda el contrato transaccional: una partida abandonada no registra nada aquí.
- **Armería / reliquias** (`scripts/systems/relic_catalog.gd`, `scripts/ui/relic_shop.gd`, `extends MetaScreen`): 6 reliquias de stats permanentes por rangos; `SaveData.relic_ranks` + `purchase_relic()`; `PlayerStats._apply_relics()` las aplica en cada `recompute()` por el mismo canal `_apply_effect` que los tomos. Reliquia nueva = una fila (id de stat de `_apply_effect`).
- **Registro de misiones** (`scripts/ui/quest_log.gd`, `extends MetaScreen`): filas con `enum RowState`.
- **Cacería diaria**: `GameConfig.daily_mode/daily_seed/daily_date`; `RunState.reset()` siembra el RNG global con la semilla y `scatter.gd` la adopta, así cartas/spawns/layout/máscara son deterministas por fecha. Score en `GameConfig.daily_score` (estática); `RunManager` lo registra (`daily_best_<fecha>` vía `raise_to`, `daily_runs`). Log `Daily run scored:`.
- **Partida sin reloj**: `RunManager` no termina la partida por tiempo. `survival_goal` (900 s) es el hito que califica el final como victoria; `extract_run()` (grupo `run_manager`, lo llama el botón **Extraerse** del `PauseMenu`) cierra la partida con el fold normal. `RunEndScreen` titula EXTRACCIÓN LOGRADA / INCURSIÓN ABANDONADA cuando alguien sigue en pie. `survival_text` tiene **exactamente un** `%d`, relleno con `survival_goal` en minutos: retunear el objetivo no puede dejar el banner anunciando otro número.

## Objetos y puntos de partida

- Qué es: economía por jugador dentro de la partida. Cada muerte paga `EnemyBase.points_value` (shiny x5, jefes `BossBase.boss_points_value` = 25, escalado por `apply_tier`) al raider **más cercano** (`Player.add_points`, señal `points_changed`; se reinicia cada partida).
- Archivos: `scripts/systems/item_catalog.gd` (`ITEM_LIBRARY`, 19 filas), `scripts/systems/item_bag.gd` (`ItemBag`, nodo del Player junto a `Stats`), `scripts/world/chest.gd`, `scripts/systems/run_state.gd` (`chest_price`, `register_chest_opened`, `CHEST_BASE_PRICES`, `CHEST_PRICE_GROWTH`).
- Objeto nuevo: una fila con `id`, `display_name`, `rarity` **fija en inglés** (id de `UpgradePool.RARITIES`), `glyph` (sigla de dos letras del nombre **español**; `icon` opcional con ruta a textura), `description`, y opcionalmente `effects` y/o `kind` (`magnet`, `poison_on_hit`, `titan`, `spiders`, `hook`, y desde la iteración 56 `shock_dash`, `saiyan`, `zenkai`). Los ids por `kind` se resuelven con el helper del catálogo, no con literales repetidos. **El kind `pet` ya no existe**: las mascotas son un slot del Player desde la iteración 54.
- `ItemBag.remove_item(item_id) -> bool` devuelve UNA copia (lo usa el pozo del bloque de la suerte) y repite los tres seguimientos de `add_item` en el mismo orden: reescala el titán, pide `recompute` y emite `items_changed`.
- **Los tres de la iteración 56**, cada uno un `kind` con una rama:
  - **Cinturón eléctrico** (`shock_dash`): el Player emite `slide_started(direction)` y la bolsa engancha ahí — el derrape no tenía señal porque nada fuera del Player necesitaba saberlo. El rayo salta desde `carrier_player().global_position`, **nunca** desde la bolsa (`ItemBag extends Node`, no tiene transformada: un `Node3D` hijo suyo se queda en el origen del mundo). Pega con `scripts/weapons/belt_bolt.gd` (`BeltBolt extends WeaponBase`, hijo **de la bolsa** y no del montaje `Weapons`, así que ni la tira del HUD ni el tope de 5 armas ni el pool de mejoras lo ven), de modo que `deal_damage` le da crítico, robo de vida y los hooks de muerte gratis. Log `Belt bolt: hits=%d`.
  - **Sangre sayayin** (`saiyan`): cuenta bajas y cada 40 (×0.85 por copia, piso 15) enciende 12 s de aura con boons **etiquetados** (`tag = "saiyan"`, así un re-disparo se reemplaza en vez de apilarse) y una carcasa dorada por `material_overlay` a la manera de `Juice.flash` — **nunca** `SealRig.apply_tint`, que es el color de identidad del personaje. Log `Saiyan aura:`.
  - **Zenkai** (`zenkai`): **se arma** con `Health.damaged` por debajo del 10% (es la única señal que significa «algo me hizo daño»: `take_damage` no emite `hp_changed`) y **dispara** con `hp_changed` por encima del 50%. Ignora las señales levantadas durante un `recompute` — `_push_bonus_max_hp_to_health` escribe `max_hp` y cura desde dentro de ese cuerpo, y sin la guarda `PlayerStats.is_recomputing()` el objeto se dispararía con su propia reconstrucción, para siempre. Los stacks son un canal permanente de todas las estadísticas (+8% cada uno). Log `Zenkai triggered:`.
- Hooks de arma: `WeaponBase.deal_damage` avisa a la bolsa del portador con `on_weapon_hit(body)` y `on_weapon_kill(pos, weapon)`. `Projectile.extra_on_hit` + `tint()` sirven para proyectiles especiales (arañas).
- Cofres — **dos modos** (iteración 47):
  - **De pago**: `rarity` fija en la instancia o tirada en `_ready` (pesos de rareza + `luck_bonus` de la party, piso `min_rarity`); el tinte y el precio se fijan ahí para que se lean a distancia. Precio = base por rareza × multiplicador global que crece x1.25 con **cada** cofre de pago abierto.
  - **Gratis** (`free_open`): precio 0, prompt «[E] Abrir cofre — gratis», **no** llama `register_chest_opened()` (un cofre gratis no encarece los de pago), y su rareza se tira **al abrirlo** con la suerte de quien abre — sin piso, así que cualquier rareza es posible. Sin rareza sellada no tiene color de rareza: lleva su propio tinte blanco-dorado (`FREE_TINT`). Son gratis todos los cofres soltados por un cuerpo (`EnemyBase.spawn_chest`: shiny y anillo de jefe — los del jefe ya **sin** piso `Rare`, conservando el bono de suerte por uso demoníaco), el cofre del pacto demoníaco y una parte de los cofres de inicio (`WorldDirector.free_start_chest_chance` ≈ 15%; los de escena se convierten con `Chest.make_free()`, que reimprime el tinte). Los cofres de suministro del director siguen siendo de pago.
  - **Todo cofre se hunde y se libera** tras entregar el premio (`_sink()`), de pago o gratis. `WorldDirector._despawn_chest` y las balizas están protegidas contra una instancia ya liberada. Log `Chest opened:`, con ` (free)` al final cuando fue gratis.
- HUD: insignia de puntos (arriba a la derecha) y tira de equipamiento abajo a la izquierda (`hud.gd` `_refresh_loadout`, sondeo cada 0.5 s): armas con nivel (★ si evolucionada), tomos con numeral de stack, objetos con copias.

## Santuarios, cofres y secretos

- Qué es: interactuables de mundo con prompt flotante y acción `interact`.
- Archivos: base `scripts/world/interactable.gd` (`Interactable extends Area3D`); `chest.gd`, `charge_shrine.gd`, `curse_shrine.gd` (extiende `ChargeShrine`), `greed_shrine.gd`, `spring_shrine.gd`, `roulette_shrine.gd` + `scripts/ui/roulette_ui.gd`, `portal_shrine.gd`; secretos: `secret_trigger.gd`, `odd_stump.gd`, `humming_skull.gd`, `scripts/enemies/secret_boss_base.gd`.
- Contrato `Interactable`: sobreescribir `_interact(player)` (y opcionalmente `_on_range_entered/_exited`); llamar `consume()` al gastarse (bumpea `meta_stat_id` y apaga el prompt); `dim_visuals()` para el gris de «usado»; `_emit_completed()` da destello + sonido.
- **Quién está en el anillo (iteración 45)**: `_players_in_range` es la lista real; `player_in_range` es solo «alguno». Un raider **derribado sigue en la lista** (su cuerpo nunca sale del árbol, así que `body_exited` no dispara): para saber quién puede sostener un ritual, usar **`live_players_in_range()`** y `nearest_live_player()`. `best_item_count_in_range(item_id)` da el mejor conteo de un objeto entre los presentes.
- **Prompts**: el texto por defecto de cada interactuable vive en un solo sitio, y el botón se escribe como el literal `[E]` (`Interactable.INTERACT_TOKEN`), que la etiqueta sustituye por el glifo del control (`[Y]`) según el slot que esté en el anillo. Un prompt nuevo **tiene que** escribir `[E]` literal para que el token funcione.
- **Audio en loop**: `_hold_loop(id)` / `_drop_loop()` sobre `Sfx.acquire_loop`/`release_loop`, con refcount y una liberación extra desde `_exit_tree`, así un abandono a mitad de canalización no deja la voz sonando.
- **Altares (reglas de la iteración 47)**: *Carga* se carga solo mientras un jugador está en el anillo. **Ya no hay sobresaltos de spawn, ni caducidad, ni renuncia**: salir del anillo solo **pausa** la carga y volver a entrar la reanuda; un altar que nadie toca espera para siempre. Desapareció `idle_lifetime` — era el único discriminador entre un altar de escena y uno del director, y gobernaba tres comportamientos distintos —; **todos** los altares se hunden tras pagar (`spent_lifetime`). El anillo es **tres veces más grande** (zona 9.3 en `ChargeShrine.tscn`, 7.8 en `CurseShrine.tscn`) y se **marca al acercarse**: dentro de `APPROACH_BAND_SCALE` (2×) radios el anillo y el disco brillan y laten, con materiales **por instancia** (`_own_material`, porque un `[sub_resource]` es un objeto compartido). El radio del disco de progreso **se deriva de la forma de la zona** (`_measure_zone_radius()` × `PROGRESS_DISC_SHARE`), nunca de una constante propia. Todo `ChargeShrine` se une al grupo `altars`.
  - Al completar, el altar **no reparte un boon al azar**: abre un menú de 3 opciones distintas de `ALTAR_BOONS` en el propio `UpgradeCardUI` (`open_choice`, ver UI) con el raider que sostuvo el anillo como destinatario explícito. Lo elegido llega a **toda la party** — `player` **y** `downed_players` — vía `PlayerStats.add_altar_boon`, escalado por `_effective_boon_scale()` y las Llaves maestras. Log `Altar charged:` (lo cuenta `verificar.sh`).
  - *Demoníaco* hereda el ritual y sustituye las opciones por **pactos** (`CurseShrine.PACT_LIBRARY`): cada carta es un **beneficio** (boon grande ~2× el de altar, puntos de partida, o un cofre gratis ahí mismo) más un **costo** que escribe knobs de `RunState` (`add_difficulty`, `elite_chance_bonus`, `sky_duration_multiplier`, `event_chance_bonus`, `disaster_chance_bonus`). Beneficio y costo son filas `{kind, ...}` con **una rama por kind**, nunca un caso especial por id. Mantiene `demonic_uses += 1`, el escalado por Sangre de demonio (`_blood_scale()`, vía el hook virtual `_effective_boon_scale()`, no mutando el `@export` del padre) y los logs `Demonic altar used:` y `Demonic pact:`.
  - `WorldDirector` ya no da vida a los altares: los siembra por el tick de eventos con **cadencia creciente** (el hueco entre eventos se comprime con el minuto hacia `event_gap_floor` ≈ 20 s, y el peso de las filas marcadas `altar` sube con `altar_weight_per_minute`) y un **cupo de altares sin gastar** que crece con el minuto (`altar_cap_base + minuto / altar_cap_minutes`); al tope, el peso del altar cae a 0 y la tirada elige otro evento. La baliza de un altar vive hasta que el altar se gasta (`TimedBeacon` con `INF` + `poi_worth_showing()`). Log `Altar placed: <kind>`. *Codicia*: apuesta de HP (log `Greed shrine:`). *Manantial*: precio fijo en puntos, `heal_full` + **un power-up al azar** vía `PowerUps.apply(PowerUpCatalog.roll_id(true))` — nunca la estrella, y duran 20 s; la iteración 53 borró el canal de boons que había aquí. *Ruleta*: `RouletteShrine.price` es la **base**; cada giro **duplica** el precio para el resto de la partida y para toda la party (`RunState.roulette_price_multiplier` / `roulette_price()` / `register_roulette_spin()`, reiniciado en `reset()` junto a los precios de cofre). El prompt y el botón releen `current_price()`. `RouletteShrine.OUTCOMES` (clasificador puro `outcome_for(roll)`), `apply_outcome(id, player)`; la UI (`roulette_ui.gd`, `CanvasLayer` construido en código, grupos `ui_blocking` + `blocking_ui_closable`) se instancia **bajo la raíz de la arena** (`RunRoot.stage_parent`, iteración 49), nunca bajo root ni bajo `current_scene`, pausa el árbol y se resuelve sola en headless. *Portal*: `WorldDirector._spawn_portals` crea `portal_count` portales emparejados; E teletransporta al gemelo y ambos recargan `cooldown / (1 + 0.25 × cosmic_worm)`.
- WorldDirector: los eventos temporizados salen de un **catálogo de filas** (`EVENT_LIBRARY`: cofre / shiny / grieta / altar de carga / altar demoníaco / manantial), con `event_weight_overrides` por instancia. Las balizas viven en una lista tipada con clase interna. Logs: `Altar charged:`, `Altar left:`, `Altar placed:`, `Demonic altar used:`, `Demonic pact:`, `Roulette spun:`, `Portal used:`, `Portals placed:`, `Spring used:`, `Boss chests dropped:`.
- Presión vía `call_group("enemy_spawner", "spawn_pressure_burst", centro, n)`; buff temporal de enemigos vía `apply_temp_enemy_buff(mult, s)`.
- Secreto nuevo: `extends SecretTrigger`, define la condición (Tocón raro: 3 interacciones; Cráneo zumbante: canal quieto de 4 s) y llama `_awaken()` — gasta, anuncia por `boss_ui` y spawnea `miniboss_scene` (raíz `extends SecretBossBase` con `secret_boss_id` exportado: su muerte bumpea `slain_<id>` y desbloquea el personaje cuya fila tenga ese `unlock_boss`). Logs `Secret miniboss awakened:` / `Secret boss slain:`.

## UI

- Capas (CanvasLayer): SplitScreen (capa por defecto) → HUD 5 → MapOverlay 8 → UpgradeCardUI 10 → RunEndScreen 20 → PauseMenu 30 → ScreenFade 100. Archivos en `scripts/ui/` + `scenes/ui/`.
- **`UiTheme`** (`scripts/ui/ui_theme.gd`, todo `static`) es el sistema de diseño: paleta, radios, `style_card()` (un único constructor de tarjeta de 4 estados), `style_button`, `style_title`, `style_badge`, `style_bar`, `attach_motion`, `pop`, `spaced_font(spacing)` (con caché por spacing) y las abreviaturas compartidas `LEVEL_ABBREV` («Nv %d») / `WEAPON_LEVEL_ABBREV` («N%d»). **No inventes styleboxes nuevas en una pantalla**: si falta un estilo, se añade aquí.
- **`CardFactory`** arma las tarjetas del selector; **`MetaScreen`** es el chasis de Registro / Colección / Armería.
- **`ScreenFade`** (autoload): `transition(callable)` funde a negro, ejecuta el callable (el `change_scene`/`reload` y su limpieza) y funde de vuelta; mientras está ocupado **descarta** peticiones repetidas y devuelve `false`, así que la limpieza irreversible va **dentro** del callable, nunca antes. `leave_run(ruta)` es el **único dueño del ritual de fin de partida**: guarda ajustes, para los loops de audio, deja el árbol **pausado durante el swap** (dos frames), llama `RunState.reset()` y cambia de escena. Cualquier botón que saque de una partida debe usarlo.
### Iconos

Cada casilla de la tira de equipamiento resuelve su arte en este orden:

1. `icon` explícito en la fila de catálogo (`WEAPON_LIBRARY`, `TOME_LIBRARY`, `ITEM_LIBRARY`), si el recurso existe.
2. **Convención por id**: `res://assets/icons/<biblioteca>/<id>.png`, con `biblioteca` ∈ `weapons`, `tomes`, `items` (más adelante `pets`, `powerups`) e `id` = el `id` de la fila de catálogo. **Para poner arte real solo hay que soltar los PNG con ese nombre**: no hay que tocar código ni catálogos.
3. `res://assets/icons/placeholder.png` con la sigla de dos letras encima.

La existencia se comprueba con `ResourceLoader.exists(path, "Texture2D")`, **no** con `FileAccess.file_exists`: en una build exportada el PNG viaja empaquetado como `.ctex` y el chequeo de archivo daría falso. El único PNG del repo es el placeholder, generado por `scripts/tools/generate_placeholder_icon.gd` (`godot --headless -s ...`, sin autoloads, hermano de `generate_sfx.gd`) y commiteado junto a su `.import`.

- HUD (`hud.gd`): grupos `hud` y `boss_ui`; API por grupo: `announce(msg)`, `announce_major(msg)` (ceremonias), `track_boss(boss, title)`, `show_stage_tag(stage_index, lap)`. Barras HP/XP, cronómetro (se repinta solo cuando cambia el segundo), bajas, rachas, insignia de puntos, `Dificultad +N%`, filas compactas J2-J4 en co-op, **toast de botín** (`show_loot`) y **badge de FPS** opcional arriba a la derecha (`SaveData.show_fps`, Ajustes → «Mostrar FPS»; se sondea, no se escucha, porque la opción se cambia con el HUD vivo o antes de que exista). Desde la iteración 48 la tira de equipamiento son **dos**: armas y tomos abajo a la izquierda, objetos abajo a la derecha. Overlay de perf oculto: export `show_perf_probe` o `BONK_PERF=1`. El daño a un compañero **no** dispara viñeta/shake globales, solo el pop de su fila. Desde la iteración 52 el HUD también **construye y ancla** el minimapa y el mapa de Tab de cada jugador (`_build_map_widgets`, `_anchor_to_cell`) y les reenvía `on_stage_started(arena)` — ver «Minimapa y mapa (Tab)».
  - **Las cuatro zonas del HUD y quién no puede pisar a quién** (iteración 61, todo confirmado en captura; ver `docs/AUDITORIA-VISUAL.md`):
    - **Arriba al centro**: cronómetro, y **debajo de su caja** —no encima— la chapa de clima. Se mide con `_timer_label.size.y + WEATHER_BADGE_GAP` en vez de un offset fijo, porque el alto del reloj es su fuente (34) más el relleno que le pone `UiTheme.style_badge`, y ninguno de esos dos números debe estar copiado en la línea que coloca la chapa.
    - **Arriba a la derecha**: bajas (22), puntos (56), insignia de FPS (88) y el minimapa debajo de las tres.
    - **Abajo al centro**: barra de HP con su etiqueta, y la fila de power-ups **por encima** (`POWERUP_ROW_OFFSET`). Los **cuatro** offsets del contenedor se escriben: `set_anchors_preset` los pone a cero, así que dejar `right`/`bottom` sin tocar deja la fila anclada al borde inferior y de **104 px de alto**, es decir una columna de fichas estiradas encima de la barra de vida.
    - **Abajo a los lados**: las dos tiras de equipamiento, a `BOTTOM_STRIP_MARGIN` 36 del borde para dejar libre `%PauseHintLabel` («Esc — Pausa»), que la escena fija a 12 del borde con 20 px de alto.
- Flecha de jefe (`boss_arrow.gd`): `bind_view(camera, carrier)` inyecta la cámara y el raider de esa vista. Sin inyección cae al viewport raíz (solo) — ver la convención de cámaras.
- Cartas (`upgrade_card_ui.gd`): en `RunState.leveled_up` pausa el árbol y ofrece 3 tiradas de `UpgradePool.roll_offer()` **de un solo lado del pool** (ver «Cartas de mejora»); los picks extra se encolan.
- **`open_choice(title, options, recipient, on_pick, tag)`** (iteración 47) es la **única** ampliación del contrato: dibuja opciones que el llamador construyó (`{title, description, color, ...payload}`) y le devuelve la elegida por `on_pick`. No tira rareza, no aplica nada, no es un framework de menús. Existe así a propósito: la pausa, la cola, el título con destinatario de co-op, el look de `UiTheme.style_card` y —sobre todo— el harness de soaks (que responde llamando `_on_card_pressed(0)` sobre cualquier nodo visible del grupo `upgrade_ui`) siguen funcionando **porque una elección ES un pick**. Una UI bloqueante nueva sería una forma nueva de encallar una partida.
- **Toast de botín** (`hud.show_loot(title, description, color, player_index)`, grupo `hud`): tarjeta abajo al centro ~3 s, encolada si llegan varias, con etiqueta `J%d` en co-op. La llama **`ItemBag.add_item`**, que es la única puerta por la que entra un objeto (cofres, ruleta, lo que venga): una llamada por fuente habría que escribirla otra vez en cada fuente nueva, y la de la ruleta nunca se escribió. El Tomo del Azar también se anuncia ahí: `PlayerStats.add_tome` **devuelve** los boons que acaba de tirar, `UpgradePool.apply` los propaga y `UpgradeCardUI` los pinta con `Tome.boon_text()`. **`open_bonus_pick(title, luck_bonus, min_rarity, recipient)`** lleva destinatario explícito: en co-op, un cofre o altar tiene que decir a **quién** le toca la carta, no confiar en «el jugador de turno».
- Contrato de pausa: quien posee la pausa se une a `ui_blocking` y expone `is_blocking() -> bool`; `pause_menu.gd` mantiene además su propio flag `_pause_owned`, así que nunca devuelve una pausa que no tomó ni roba la de las cartas o el fin de partida. Al añadir una UI que pause, seguir este patrón (y unirse a `blocking_ui_closable` si acepta cierre por código; hoy ese grupo no tiene llamador, es la puerta que dejó la ruleta abierta para el harness).
- Fin de partida: `run_manager.gd` (señal `run_ended`, cableada dentro de `RunSystems.tscn`) → `run_end_screen.gd`, cuya coreografía sale de una tabla `ENDINGS` (título, subtítulo, color por final) en vez de ramas.
- **Longitud del español**: las superficies del HUD y las tarjetas son tolerantes a etiquetas más largas, pero la regla del glosario sigue vigente — una etiqueta española no debe crecer más de ~10% sobre la inglesa en HUD, insignias y botones.

## Sistemas transversales

- **Pools** (`scripts/systems/pools.gd` + `node_pool.gd`): pooling de los **14** hotspots (gemas, orbes, dardos, flechas, bumerán, bolts enemigos, bursts de muerte, popups, discos de telégrafo, arco de tajo, fogonazo, latigazo, brasas, charcos). Contrato de uso: spawn = `Pools.acquire_scene(escena)`, despawn = `Pools.release(nodo)`; el script pooled implementa `pool_reset()` restaurando estado recién-spawneado. **Escena nueva de alta rotación = UNA fila en `Pools.POOLS`** (`name`, `scene`, `warm`, `cap`); antes eran tres listas paralelas que se desincronizaban en silencio. `pool_size_overrides` permite tunear sin tocar la tabla. Sin registrar, `acquire_scene` cae a instanciar normal.
  - Contrato del `NodePool`: `release()` **registra** en el nodo lo que apaga (`process`, `physics_process`, `monitoring`, `monitorable`) y `acquire()` restaura exactamente eso. El pool no inventa estado (no fuerza processing sobre escenas que no definen callbacks) ni deja un `Area3D` aparcado escuchando. Métricas: `total_created` (churn) y `peak_parked`.
- **Juice** (`scripts/systems/juice.gd`, autoload): hooks semánticos de una línea — `enemy_died(pos, color)`, `boss_died(...)`, `crit_punch()`, `player_hurt()`, `sparkle(pos)`, `burst(...)`, `flash(visual)`, `shake(...)`, `hit_stop(...)`, `fov_kick_begin(camera)` / `fov_kick_end(camera)`. Una mecánica nueva con impacto debería llamar a uno existente antes que inventar efectos propios; tunables como exports del autoload. `Juice.damp(tasa, delta)` es el peso de suavizado compartido: se usa como `lerp(a, b, Juice.damp(r, d))` y es independiente del framerate (el `tasa * delta` de siempre es su aproximación de Euler y deriva con el frame time). El rig de la foca, las mascotas y la cámara se asientan a la misma velocidad real gracias a él.
- **Sfx** (`scripts/systems/sfx.gd`, autoload): `Sfx.play(&"id")` sobre un pool de voces con jitter de pitch y rate-limit; loops con `acquire_loop/release_loop`, siempre **con refcount** (un solo camino, sin caso especial para el primer dueño) y `stop_all_loops()` para los cortes de escena. Sonido nuevo = receta en `scripts/tools/generate_sfx.gd` (síntesis determinista) + entrada en `STREAMS` (y `id_volume_db`). Regenerar los 20 wav: `godot --headless --path . -s res://scripts/tools/generate_sfx.gd`.
- **Capa de stats** (`scripts/systems/player_stats.gd`, nodo `Stats` del Player): guarda stacks de tomos + pasiva + reliquias + objetos + boons y **recalcula todo desde cero** en `recompute()` en cada cambio (nunca acumular sobre valores derivados). `recompute()` está partido en cuatro fases nombradas; `_apply_boons()` recorre gamble/altar/temporales en un solo bucle y `_apply_items()` hace una sola pasada por la bolsa. Stat nuevo: campo derivado + rama en `_apply_effect(stat, amount)` + que el consumidor lo lea (armas vía helpers de `WeaponBase`; `Health` recibe `armor`/`evasion` empujados). Los suelos de multiplicador son const documentadas.
- **Stats de la iteración 48**: `extra_jumps` (id `jumps`) da saltos en el aire extra — `Player._try_jump` gasta un presupuesto `_jumps_left` que se recarga **al pisar suelo** (no dentro del salto, para que quien se cae de un borde conserve los suyos), con tope `PlayerStats.MAX_EXTRA_JUMPS`; y `powerup_drop_chance` (id `powerup_chance`, en porcentaje). Ambos entran al pool de boons de altar y `extra_jumps` además al catálogo de objetos («Botas de resorte», Rara).
- **Knobs de partida sin consumidor (ganchos hacia adelante)**: `PlayerStats.powerup_drop_chance` y `RunState.disaster_chance_bonus` lo escriben los pactos demoníacos y **nadie lo lee todavía** — son los ganchos de los power-ups y los desastres de la parte C, igual que `demonic_uses` fue el gancho de la iteración 42. Un altar ya vende el primero y un pacto el segundo, así que **existen y se reinician** (`recompute()` / `reset()`) aunque nadie los lea todavía. No los borres por «dato muerto»: sin ellos, la carta que los vende miente.
- **Health** (`scripts/systems/health.gd`): componente hijo reutilizable; señales `damaged`, `damaged_by(attacker)` (thorns), `dodged(attacker)` (ejecuciones), `hp_changed(current, max)` y `died`. El **setter de `max_hp` es dueño de la invariante**: un cuerpo a vida llena sigue lleno tras subirle el máximo, uno herido queda clampado, y `hp_changed` reporta ambos valores — ningún sitio que escale HP tiene que acordarse. Un golpe siempre quita al menos `MIN_CHIP_DAMAGE` (o su valor bruto si ya era menor), así que la armadura nunca vuelve a un cuerpo inmortal. `Health.find_in(body)` / `PlayerStats.find_in(body)` son la forma estándar de encontrar componentes.
- **Co-op** (`scripts/systems/coop.gd`, autoload `Coop`): `player_count`, `devices`, `character_ids`, `action(slot, base)` (acciones clonadas por slot), `look_vector(slot)`, `nearest_player(tree, from)`, `random_player(tree)`, `alive_players(tree)`, `alive_player_count(tree)`. El snapshot de jugadores está tipado y su invalidación es explícita (`invalidate_players()`): si spawneas o liberas un raider fuera de `RunSystems`, invalídalo.
- **Pantalla dividida** (`scripts/systems/split_screen.gd`): un `SubViewportContainer` por jugador con una cámara que **espeja** la del jugador (transform, `fov`, `h_offset`, `v_offset`, `cull_mask` — la lista completa está en `CameraPair.sync()`; una vista que se saltaba los offsets no temblaba). Las cámaras fuente se apuntan a `Juice.FEEL_CAMERA_GROUP`.

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
- **co-op** (iteración 57): el quinto soak no arrancó con dos raiders (`ArenaProbe: players=2`), no cruzó de etapa, ensució un `Stage sweep:` o no produjo ningún `Player revived:`.
- **lint / UI** (iteración 57): falta cualquiera de las nueve líneas `Catalog lint: check <nombre> ok rows=N` (con `rows` > 0) o de los trece `UiProbe: step <nombre> ok`. Las listas de nombres viven en `tools/verificar.sh` y se greppean **una por una**: una comprobación que deja de ejecutarse desaparece del log sin ruido, y un conteo la daría por buena mientras otra se repite.
- **partida godmode terminada**: cualquier soak inmortal que imprima `Probe fog: skipped` (ver la regla de fin de partida abajo). Un raider con 10M de HP no tiene por qué morirse.

La corrida completa (import + lint + harness de UI + 3×360 s + 1×720 s + 1×360 s de co-op) tarda **entre ~16 y ~75 minutos**, más que el timeout de una llamada de shell: lánzala en segundo plano. El reloj de una corrida lo manda el TAMAÑO DE LA HORDA, no el número de frames: medido en dos corridas de la misma cabeza y las mismas semillas, **16 min** y **75 min**. El soak de co-op es el que más se mueve (la horda escala +50% de HP y +30% de ritmo de spawn por raider extra, y un cuerpo vivo cuesta física cada frame): 78 s en una corrida y 32 min en la otra. Por eso `verificar.sh` imprime los segundos de cada fase y el total — una estimación fija envejece mal.

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

### `scenes/tests/CatalogLint.tscn` + `catalog_lint.gd` (iteración 57)

Las referencias cruzadas que **ningún soak puede comprobar**, porque una rota
no revienta: simplemente no hace nada. Un `passive_stat` mal escrito le cuesta
a su raider la pasiva entera y deja un warning enterrado en un log de 20 000
líneas; una ruta `scene` con un typo solo falla el día que alguien tira esa
fila; un glifo repetido entre dos catálogos pinta la sigla equivocada.

Nueve comprobaciones, una línea `Catalog lint: check <nombre> ok rows=%d` por
cada una que pasa y un `push_error` por cada fallo:

| Comprobación | Qué mira |
|---|---|
| `ids_unique` | id repetido dentro de cada librería (13 librerías) |
| `glyphs_unique` | glifo repetido **entre** armas, evoluciones, tomos, objetos y power-ups |
| `paths_exist` | toda ruta `scene` / `weapon_scene` / `scene_path` / `icon`, con `ResourceLoader.exists` |
| `stat_ids` | todo `passive_stat`, `stat` de objeto/power-up/mascota/reliquia y stat de boon de altar o pacto contra las ramas del `match` de `PlayerStats._apply_effect` |
| `character_weapons` | el `weapon_node_name` de cada raider existe como `node_name` en `WEAPON_LIBRARY` |
| `director_methods` | todo `method` de `EVENT_LIBRARY` y todo `start`/`tick`/`stop` de `WEATHER_CATALOG` está declarado en `world_director.gd` |
| `weapon_properties` | toda `extra_entries.property` y toda clave `mults`/`adds` de evolución existe en el arma destino (se instancia la escena y se lee su lista de propiedades) |
| `vendor_lucky_roulette_ids` | ids únicos en `VENDOR_LIBRARY`, `LUCKY_REWARDS` y `OUTCOMES` |
| `marker_labels` | todo `marker_kind` que algún script asigna y toda clave de `MARKER_STYLES` (salvo `player`/`boss`/`exit`) tiene fila en `MARKER_LABELS`, **a menos que** esté en `MapDraw.LEGEND_VARIANTS` |

`rows` es lo que se inspeccionó **de verdad**, y **cero filas es un fallo**: una
comprobación que recorre una lista vacía pasa por el motivo equivocado, que es
exactamente cómo una constante renombrada pasaría desapercibida.

`MapDraw.LEGEND_VARIANTS` nombra las tres variantes que a propósito **no**
llevan fila de leyenda (`chest_free`, `altar_demonic`, `altar_greed`): cada una
es una variante de una familia que ya tiene la suya, y una línea por variante
convertiría una leyenda de un vistazo en una taxonomía. Nombrarlas en una
constante en vez de dejarlas implícitas es lo que le permite al lint distinguir
una omisión deliberada de una olvidada.

### `scenes/tests/UiProbe.tscn` + `ui_probe.gd` (iteración 57)

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
`PauseMenu.tscn`), por texto solo los construidos en código (Colección,
Armería, el «Sí» de la carta de confirmación), y `ui_cancel` como
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
- **Barrido de máscara** (iteración 48, una sola vez en el frame de física 10, cuando los transforms de los props ya llegaron al servidor de física): por cada celda bloqueada recorre en pasos de 0.2 m cada arista que comparte con una celda caminable y prueba ahí una cápsula del tamaño del jugador (radio 0.4, altura 1.8, centrada a 0.9 m) a caballo de la arista contra la capa 1, excluyendo a los raiders. Una muestra que no golpea nada es una **apertura**. Imprime `Mask sweep: blocked=%d samples=%d openings=%d` y hace `push_warning` por cada apertura. Es la prueba de que las rocas sellan de verdad; **jamás se afloja la tolerancia ni la densidad de muestreo** para hacerlo pasar — se mueven las rocas.
- **Raider dentro de celda bloqueada** (iteración 48): si el raider líder está **a nivel de suelo** (y ≤ 0.6, no sobre una roca ni una meseta) dentro de una celda no caminable más de 2 s seguidos, `push_warning`. Se reporta una vez por entrada a la celda, no por frame.
- **Detector de enemigos voladores** (iteración 48): un cuerpo cuenta como *airborne* cuando lleva `velocity.y > 0.5` **en subida y sin piso** durante 0.5 s seguidos. Exactamente dos excepciones, y son las dos que suben a propósito: un enemigo en estado de trepada (`_climbing`) y un Duneburrower en erupción. Cada ocurrencia nueva imprime **un** `push_warning` (una vez por cuerpo) y la línea de estado del harness termina en `airborne=%d` acumulado. Las reglas son fijas: ensancharlas para callar un warning es exactamente lo que este detector existe para impedir.
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
  `Player._tick_downed` quiere 3 s continuos de la acción **del rescatador**)
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

| Variable | Efecto |
|---|---|
| `BONK_ARENA=res://scenes/world/AshDunes.tscn` | **bioma inicial** de la etapa 1 (defecto: Hollow Woods). El probe siempre arranca `Run.tscn` |
| `BONK_CHARACTER=<id>` | raider de `CharacterCatalog`. Un id desconocido es un **`push_error`** desde la iteración 54 (antes se ignoraba en silencio, y un soak que creía probar un raider corría el de siempre); el probe imprime `ArenaProbe: character=<id>` |
| `BONK_PLAYERS=<1-4>` | tamaño de la party (iteración 57); `Coop.configure` antes de instanciar `Run.tscn`. El probe imprime `ArenaProbe: players=%d slot1=%s` contado sobre los **grupos**, no sobre el interruptor |
| `BONK_CHARACTER2=<id>` | raider del slot 1 (defecto: la fila siguiente del catálogo) |
| `BONK_DOWN_NOW=<seg>` | golpe letal al slot 1 a ese segundo y cada 60 s después: fuerza el ciclo derribo/reanimación en vez de esperar a que la horda lo elija |
| `BONK_GODMODE=1` | raider con 10M de HP, para que los sistemas tardíos se ejerciten. **Solo el slot 0** desde la iteración 57 |
| `BONK_WALK=0` | deja el raider quieto (defecto: camina) |
| `BONK_SEED=<int>` | recorrido determinista, para reproducir un soak |
| `BONK_PROBE_DEBUG=1` | narra el recorrido (waypoints, llegadas, pulsaciones) |
| `BONK_ELITE_BOOST=1` | todo spawn sale shiny (`force_elite_spawns` por grupo) |
| `BONK_STAGE_FAST=1` | la etapa se supera a los 60 s sin jefe; el harness espera 70 s y cruza |
| `BONK_SAVE_PATH=<ruta>` | re-apunta el guardado. Lo honran `SaveData._ready` (cualquier arranque headless) **y** el propio probe, antes de instanciar la partida; `tools/verificar.sh` le da a cada soak el suyo |
| `BONK_GAME_SEED=<int>` | siembra el RNG **del juego** (cartas, spawns, scatter y relieve): lo que hace reproducible un soak entero |
| `BONK_POWERUP_NOW=<id>` | concede ese power-up al slot 0 a los 20 s y **lo re-concede en cada expiración** |
| `BONK_STAR_NOW=1` | suelta una estrella **quieta** a los pies del raider a los 30 s |
| `BONK_POWERUP_BOOST=1` | multiplica ×50 la probabilidad de drop por baja (lo lee `EnemySpawner`) |
| `BONK_POI_NOW=a,b,c` | siembra esos POIs a 8 m del raider a los 20 s: `vendor_items`, `vendor_powerups`, `vendor_animals`, `pet_box`, `event_altar`, `lucky_block`. Las repeticiones se conservan (seis `lucky_block` siembran seis bloques) |
| `BONK_LUCKY_REWARD=a,b` | cola de recompensas que pagan los bloques siguientes en vez de tirar la tabla (la última se repite); un id desconocido es `push_error`. Cola **estática** en `lucky_block.gd`, porque la tirada es estática y tiene que sobrevivir entre bloques |
| `BONK_SWAP_MENU=1` | aserción de auditoría (iteración 58): en la trama en que un menú cerrable tiene la pausa, dispara un cambio de etapa por el grupo `run_root` e informa `Swap menu: paused=%s` cinco segundos después. `true` es el atasco. Necesita que se abra un menú (`BONK_POI_NOW=vendor_items BONK_POINTS=4000`) |
| `BONK_POWERUP_AT=<s>` | mueve la primera concesión de `BONK_POWERUP_NOW` fuera de sus 20 s por defecto: una congelación que arranca a los 20 s y se re-concede para siempre atrapa a todos los enemigos **en superficie**, así que los estados que solo existen más tarde en un ciclo (un Duneburrower enterrado) son inalcanzables con el valor por defecto |
| `BONK_WEATHER_NOW=<id>` | fuerza ese clima a los 30 s por la misma entrada forzada que usa el altar |
| `BONK_WEAPON=<id>` | el raider arranca con esa arma en vez de la de su personaje, por la misma vía de concesión |
| `BONK_ITEM_NOW=a,b:2` | concede esos objetos al slot 0 a los 10 s (`id:n` para n copias) y hace que el recorrido **derrape** cada ~3 s, único disparador del cinturón |
| `BONK_ZENKAI_TEST=1` | a los 60 s: golpe del 95%, 3 s invulnerable y curación completa — el bajón-y-supervivencia con el que Zenkai se arma |
| `BONK_POINTS=<n>` | le da esos puntos al slot 0 al arrancar, para que un soak de vendedor pueda pagar |
| `BONK_PERF=1` | enciende el overlay de rendimiento del HUD |

Uso directo:

```sh
BONK_ARENA=res://scenes/world/Gloomfen.tscn BONK_GODMODE=1 \
  godot --headless --fixed-fps 60 --quit-after 36000 res://scenes/tests/ArenaProbe.tscn
```

Arrancar una arena directamente (`res://scenes/world/Gloomfen.tscn` como
escena principal, o F6 en el editor) **ya no funciona** desde la iteración
49: una arena es solo el mundo. Arranca `res://scenes/world/Run.tscn` y
elige el bioma con `BONK_ARENA` / `GameConfig.start_map_id`.

Para lógica aislada sigue sirviendo un harness desechable `extends SceneTree` (patrón de `generate_sfx.gd`) con `godot --headless --path . -s res://...`. Ojo: en un script `-s` **no hay autoloads**, así que no sirve para nada que toque `RunState`, `SaveData` o `Coop`.

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

| | |
|---|---|
| Cómo captura | `Viewport.get_texture().get_image().save_png()` **tras `await RenderingServer.frame_post_draw`**. Antes de ese await `get_image()` devuelve el fotograma anterior, que para una foto de evento es el de justo antes del evento |
| Por qué desde dentro | macOS le niega `screencapture` a una terminal sin permiso de Grabación de Pantalla, y un soak no tiene a quién pedírselo. Desde el motor no hace falta permiso ninguno |
| Headless | **se ignora**, con un `Shots skipped: headless` una sola vez. Un PNG vacío sería peor que ninguno |
| Cuándo dispara | cada `BONK_SHOT_EVERY` s (10 por defecto, 2 en `UiProbe`), en cada cambio de etapa, clima, llegada de vendedor, caja de mascotas abierta, bloque de la suerte resuelto, power-up recogido, apertura del mapa Tab y en la primera carta de nivel; `final.png` al salir |
| Retardo | etapa y clima esperan `SHOT_SETTLE` 1.5 s y el mapa 0.6 s (`ShotCamera.request_in`): el overlay abre al fotograma siguiente al Tab, el tinte de un clima entra en rampa y un cambio de etapa va detrás del fundido de `ScreenFade` |
| Qué NO hace | nada que una puerta lea. Con la variable sin poner, todas sus líneas son no-ops, y el temporizador se alimenta del delta de física —no de `RunState.run_time`— precisamente para que un menú que congela el reloj **sí** salga fotografiado |

**Los eventos se leen del árbol, no de los logs.** Un `print` no es algo a lo
que otro nodo se pueda suscribir: un vendedor es un miembro nuevo del grupo
`vendors`, la caja y el bloque avisan por el `interaction_completed` que ya
emitían, y un power-up es un id que el líder no llevaba en la muestra
anterior.

**Lo que la cámara no puede juzgar** y sigue necesitando ojos humanos:
sensación, ritmo, legibilidad de un texto sobre un fondo movido y si el arte
gusta. Lo que sí decide sola: si algo se dibuja, dónde, y encima de qué.

## Convenciones

- **GDScript con tipado estático** en el 100% del código (parámetros, retornos, variables con tipo, `:=` solo con tipo inferible), incluidos los `Array`/`Dictionary` tipados (`Array[Dictionary]`, `Dictionary[String, int]`). Mantenerlo: el codebase compila limpio y los soaks dependen de ello. Un `Array` sin tipar cruzando una firma tipada lanza `Invalid type in function` en runtime, no en parseo.
- **Señales y grupos, no referencias duras** entre escenas: `call_group(...)` / `get_first_node_in_group(...)` para todo acoplamiento cruzado; rutas de nodo solo dentro de la propia escena.
- **`resource_local_to_scene = true` en todo sub-recurso que se mute en runtime.** Un `[sub_resource]` de una `.tscn` es **UN objeto compartido por todas las instancias** de esa escena: mutarlo desde el script cambia el de todos los demás y se filtra a la partida siguiente. Casos ya marcados: la `CapsuleShape3D` del Player (el derrape le cambia la altura — sin la marca, derrapar encogía a toda la party), y los `ParticleProcessMaterial` de `DeathBurst`, `BloodPool`, `WhipCrack` y `TelegraphDisc` (se tintan por spawn). Si tu script escribe en `mesh`, `shape`, `material`, `process_material` o cualquier `SubResource("...")`, márcalo en la escena y **dilo en la cabecera del script**.
- **Los repartos «a toda la party» cubren también a los caídos.** Un raider derribado **sale del grupo `player`** y entra en `downed_players` (`Player._set_downed`). Un efecto permanente para la partida (boon de altar, evento de cielo, desbloqueo) que solo recorra `player` le deja al caído un déficit que nada repone. Recorre los dos grupos (`for group in ["player", "downed_players"]`, como `charge_shrine._grant_reward`) salvo que la mecánica exija estar en pie a propósito. Dentro de un `Interactable`, la pregunta correcta es `live_players_in_range()`.
- **Cualquier cosa que actúe sobre una cámara la recibe explícitamente.** En co-op el viewport raíz **no tiene cámara activa**: las cámaras que renderizan viven en los `SubViewport` de `SplitScreen`. `get_viewport().get_camera_3d()` devuelve `null` (o la equivocada) en cuanto hay dos jugadores. Por eso `Juice.fov_kick_begin/end` reciben la cámara del deslizador, la flecha de jefe (`scripts/ui/boss_arrow.gd`) recibe la suya por `bind_view(camera, carrier)`, y las cámaras fuente se registran en `Juice.FEEL_CAMERA_GROUP` para que el shake llegue. `Player.view_camera()` es el accesor de la cámara propia de un raider. Nunca busques «la» cámara.
- **Los nombres de rareza son identificadores.** `UpgradePool.RARITIES[].name` (`Common`/`Rare`/`Epic`/`Legendary`) llavea precios de cofre, el campo `rarity` de `ITEM_LIBRARY` y los pisos `min_rarity` en nueve archivos: **no se traduce nunca**. Para mostrarla en pantalla, `UpgradePool.rarity_display(id)` — es el único punto de traducción, y nada compara contra su resultado.
- **Español latinoamericano para todo lo visible, inglés para todo lo estructural.** La tabla es `docs/GLOSARIO.md`. En inglés y sin tocar: ids, `node_name`, grupos, `StringName`, rutas `res://`, claves de `SaveData` y los `print()`/`push_warning()`. Los marcadores de formato (`%d %s %.1f %02d %%`) conservan número y orden exactos.
- **Tunables como `@export`** con defaults en el script; los overrides por instancia viven en la escena (el horario de jefes por arena, las escenas del spawner). Antes de mover un `@export` de sitio, comprueba qué `.tscn` lo overridea: las tres arenas overridean el `EnemySpawner`.
- **Números mágicos a `const` con nombre y comentario del porqué.** Un `0.5` suelto en dos archivos es la forma en que dos copias del mismo cálculo se separan.
- **Logs de una línea** en eventos clave — son la interfaz de verificación de los soaks headless, van **en inglés** y se conservan. Inventario actual: `Run ended:`, `Meta saved:`, `Save recovered from backup:`, `Boss spawned:`, `Boss chests dropped:`, `Elite chest dropped:`, `Horde:`, `Sky event:`, `Chest opened:`, `Altar charged:`, `Altar left:`, `Altar placed:`, `Demonic altar used:`, `Demonic pact:`, `Spawn skipped:`, `Stage advanced:`, `Stage sweep:`, `Stage carry:`, `Stage gate:`, `Stage boss slain:`, `Exit portal opened`, `Portal used: exit`, `Pseudo-infinite:`, `Run stages:`, `Terrain built:`, `Probe legs:`, `Greed shrine:`, `Roulette spun:`, `Spring used:`, `Portal used:`, `Portals placed:`, `Weapon evolved:`, `Weapon ascended:`, `Pet joined:`, `Secret miniboss awakened:`, `Secret boss slain:`, `Arena mask:`, `Start layout:`, `Daily run scored:`, `Void rescue:`, `Power-up picked:`, `Power-up dropped:`, `Star roam:`, `Flight landing:`, `Pet box opened:`, `Vendor arrived:`, `Vendor sold:`, `Time stop:`, `Immortal blocked:`, `Weather started:`, `Weather ended:`, `Disaster:`, `Event altar used:`, `Possessed spawned:`, `Possessed expired:`, `Belt bolt:`, `Saiyan aura:`, `Zenkai triggered:`, `Lucky block:`, `Save path overridden:`, `Player revived:`, `Vendor buyer:`. Al crear un evento mayor, añade el tuyo con el mismo formato. Las líneas de los harness van aparte y también se conservan, porque `tools/verificar.sh` las greppea: `Probe legs:`, `Probe fog:` (incluida su forma `Probe fog: skipped`), `Probe: run ended`, `Mask sweep:`, `Map overlay:`, `Time stop:`, `Immortal blocked:`, `HUD offset:`, `Party:`, `Party pets:`, `Points sources:`, `Catalog lint:`, `UiProbe:`, `Swap menu:`, `Saiyan boons:`, `Time stop worms:`.
- **Verificar antes de dar por hecho un cambio**: `tools/verificar.sh`. Un cambio que no pasa el import o ensucia el log de un soak no está terminado.
