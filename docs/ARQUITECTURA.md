# Arquitectura — dónde tocar cada cosa

Mapa de referencia por sistema: qué hace, archivos clave y cómo extenderlo. Regla general del proyecto: **el contenido son filas de catálogo** (Dictionaries const en `scripts/systems/`) + una escena; casi nunca hace falta código nuevo por pieza de contenido. Los sistemas se comunican por **señales y grupos**, nunca por rutas de nodos entre escenas.

## Vista general de una partida

`scenes/ui/CharacterSelect.tscn` (escena principal) escribe la elección en el autoload `GameConfig` (`selected_character_id`, `selected_map_id`, `selected_tier`) y carga la arena (`scenes/world/HollowWoods.tscn` o `AshDunes.tscn`). Cada arena instancia `scenes/world/RunSystems.tscn` — el bloque común: `Player`, `RunManager` (fin de partida), `UpgradeCardUI`, `HUD`, `RunEndScreen`, `PauseMenu` — y mantiene como propios su `EnemySpawner` y `AmbientBed`. Autoloads (`project.godot`): `RunState` (XP/nivel/kills/reloj de la partida), `GameConfig`, `SaveData` (meta persistente), `Juice` (game feel), `Sfx` (audio), `Settings` (aplica ajustes), `Pools` (object pooling).

Grupos usados: `player`, `enemies`, `boss`, `enemy_spawner`, `hud`, `boss_ui`, `upgrade_ui`, `ui_blocking`, `gems`, `health_orbs`, `scatter_keepout`.

## Añadir un arma nueva

- Qué es: nodos hijos del mount `Weapons` del Player que disparan solos por cooldown al enemigo más cercano del grupo `enemies`.
- Archivos: `scripts/weapons/weapon_base.gd` (clase `WeaponBase`), `scripts/systems/upgrade_pool.gd` (`WEAPON_LIBRARY`), `scenes/weapons/`.
- Contrato `WeaponBase`: exporta `damage/cooldown/attack_range/projectile_count/cooldown_scale`; la subclase sobreescribe `fire(target)` y canaliza **todo** golpe por `deal_damage(target_health)` (aplica multiplicador global, crit, lifesteal). Helpers: `effective_damage()`, `effective_cooldown()`, `area_scale()` (para radios/arcos, no para `attack_range`).
- Pasos: (1) script `extends WeaponBase` + escena en `scenes/weapons/` (mira `shortsword.gd` melee, `dart_pistol.gd` proyectil, `ember_wand.gd` área); (2) una fila en `UpgradePool.WEAPON_LIBRARY` con `id`, `display_name`, `node_name` (== nombre de nodo al instanciarse), `scene`, `flavor` y opcionalmente `extra_entries` (cartas de mejora propias, ej. `hunting_bow_pierce`). Con eso ya aparece como carta "new weapon" y genera sus cartas de daño/cooldown/rango automáticamente.
- Si dispara proyectiles: el proyectil es su propia escena con `pool_reset()` (ver Pools abajo), se lanza con `Pools.acquire_scene(...)` y se registra en `scripts/systems/pools.gd` (const preload + `_register()` en `_ready()` + entrada en `pool_sizes`). Ejemplo completo: `dart_pistol.gd` + `projectile.gd`.

## Añadir un personaje

- Qué es: arma inicial + pasiva escalable, todo datos; el select y el spawn del Player leen la fila, no hay código por personaje.
- Archivos: `scripts/systems/character_catalog.gd` (`CHARACTER_LIBRARY`), consumidores: `scripts/player/player.gd` (`_apply_character`), `scripts/ui/character_select.gd`, `scripts/systems/player_stats.gd`.
- Fila: `id`, `display_name`, `blurb`, `weapon_scene` + `weapon_node_name` (**debe** coincidir con el `node_name` de `WEAPON_LIBRARY` para que el pool lo vea como poseída), `weapon_display_name`, `passive_description`, `passive_stat` + `passive_amount`, `tint`.
- `passive_kind` (opcional): `"per_level"` (defecto — `passive_stat` gana `passive_amount` por nivel; ids de stat = los de `PlayerStats._apply_effect`: `damage, cooldown, area, move_speed, crit_chance, crit_damage, lifesteal, evasion, armor, luck, thorns, max_hp`), `"speed_to_damage"` (Juno: velocidad extra → daño) o `"evasion_execute"` (Nyx: per_level + cada esquiva ejecuta atacantes no-jefe débiles). `passive_base` = cantidad ya activa a nivel 1 (Doc).
- Desbloqueo: `unlock_cost` en Shards (0 = inicial); opcional `unlock_boss` (id de minijefe secreto cuya muerte lo regala, resuelto por `SecretBossBase` vía `CharacterCatalog.by_unlock_boss`) + `unlock_hint` (pista en la carta bloqueada).

## Añadir un tomo

- Qué es: pasivas apilables (máx. 5 stacks) que alimentan la capa de stats del jugador.
- Archivos: `scripts/systems/tome.gd` (`TOME_LIBRARY`), aplicado por `scripts/systems/player_stats.gd`; las cartas las genera `upgrade_pool.gd` (`_tome_entries`).
- Fila: `id`, `display_name`, `description` (el `%d` se rellena con la cantidad del **primer** efecto), `effects: [{stat, amount}]` — mismos ids de stat que las pasivas. Una fila nueva basta: el pool ofrece el siguiente stack automáticamente ("Tome of X II"...).
- Escalado: `amount` es el valor a potencia Common; la rareza de la carta lo multiplica (`UpgradePool.RARITIES`: Common 1.0 / Rare 1.5 / Epic 2.0 / Legendary 3.0). La `luck` del jugador inclina los pesos de rareza al tirar.

## Añadir un enemigo

- Qué es: chasis compartido de horda (gravedad, seek + separación, giro, muerte con gema de XP) con hooks virtuales.
- Archivos: `scripts/enemies/enemy_base.gd` (`EnemyBase`), spawner: `scripts/systems/enemy_spawner.gd`, ejemplos: `grunt.gd` (melee), `skirmisher.gd` (a distancia, mantiene rango), `tank.gd`, `sunspitter.gd` (láser), `duneburrower.gd` (emboscada).
- Escena: raíz `CharacterBody3D` en grupo `enemies`, hijos `Health` (`scripts/systems/health.gd`), `Visual`, `CollisionShape3D`; exporta `xp_gem_scene`.
- Hooks a sobreescribir: `_behavior_tick(delta)` (cooldowns), `_movement_intent(seek, distance)` (a dónde ir), `_combat_tick(player, distance)` (atacar), `_facing_direction(...)` y **`_apply_elite_damage(mult)`** (multiplica los números de daño propios — lo llaman élites y el escalado por tier vía `apply_tier_scaling(hp, dmg, xp)`).
- Para que spawnee: en `enemy_spawner.gd` añadir un `@export var ..._scene`, una rama en `_scene_for(kind)` y pesos en las tablas de fases `FOREST_PHASES` / `DUNES_PHASES` (`{"from_minute": N, "weights": {kind: peso}}`; `phase_preset` elige tabla por arena). Asignar la escena en el nodo `EnemySpawner` de cada arena. Élites (`make_elite()`) y tiers llegan gratis desde el chasis.

## Añadir un jefe

- Qué es: chasis sobre `EnemyBase` con barra de vida en HUD, clamp de arena, escalado Elder/tier/maldición y pago en anillo de gemas + orbes de vida.
- Archivos: `scripts/enemies/boss_base.gd` (`BossBase`), ejemplos con máquina de estados propia: `rotking.gd`, `sarcognath.gd`; telégrafos: `scenes/fx/TelegraphDisc.tscn`.
- Escena: raíz en grupos `boss` + `enemies`. En `_ready` el chasis ya hace `call_group("boss_ui", "track_boss", self, boss_title)` — la barra del HUD y la flecha de pantalla (`scripts/ui/boss_arrow.gd`, grupo `boss`) se enganchan solas.
- Sobreescribir `_scale_attack_damage(mult)` con los números del moveset: por ahí pasan `apply_tier()` (rematch Elder × tier de mapa, un solo apply combinado) y `apply_curse(stacks)` (Curse Shrine: +40% HP/daño por stack, gemas ×2 por stack; exports `curse_*` en `BossBase`).
- Horario: exportado en el spawner y **overrideado por arena** en la escena del mapa — `boss_scene`, `boss_spawn_minute` (5), `elder_spawn_minute` (11), `elder_stat_multiplier`, `elder_title` (AshDunes pone "Sarcognath Elder"), `boss_warning_text`. El spawner consume las maldiciones (`RunState.consume_curses()`) al spawnearlo e imprime `Boss spawned: ...` para los soaks.
- Jefes ocultos: `extends SecretBossBase` (ver Secretos).

## Añadir un mapa

- Qué es: una fila de catálogo + una escena de arena; el select construye la carta y `SaveData.is_map_unlocked()` evalúa la regla.
- Archivos: `scripts/systems/map_catalog.gd` (`MAP_LIBRARY`, `DEFAULT_TIERS`), `scripts/world/run_systems.gd`, `scripts/world/scatter.gd`, arenas existentes como plantilla.
- Fila: `id`, `display_name`, `blurb`, `scene_path`, `unlock_stat` + `unlock_target` (contador de `SaveData`; `""` = siempre abierto; Ash Dunes usa `victories >= 1`), `locked_hint`, `palette`, `tiers` (normalmente `DEFAULT_TIERS`: T1 baseline exacto, T2/T3 con `enemy_hp_mult`, `enemy_damage_mult`, `spawn_rate_mult`, `boss_mult`, `xp_value_mult`, `shard_bonus`; T(N+1) se desbloquea ganando T(N) en ese mapa).
- Escena de arena (copiar `AshDunes.tscn`): `WorldEnvironment` + luz, `Floor` y `Perimeter` (muros, capa 1), spots de verticalidad y props a mano (en grupo `scatter_keepout`), nodo de scatter con `scatter.gd` (seed determinista, mantiene carriles libres), `Interactables` (santuarios/cofres/secreto), `EnemySpawner` (con `phase_preset` y sus escenas/horario), `AmbientBed` y **una instancia de `RunSystems.tscn` con `map_id` overrideado**. `RunSystems._ready` republica el mapa en `GameConfig`, valida el tier y lo reparte por grupos (`apply_tier_spec` al spawner, `show_tier_tag` al HUD).

## Misiones y meta-progresión

- Qué es: misiones que pagan Shards; los Shards solo compran personajes (nunca stats permanentes). Todo persiste en `user://save.json`.
- Archivos: `scripts/systems/quest_catalog.gd` (`QUEST_LIBRARY`), `scripts/systems/save_data.gd` (autoload `SaveData`), UI: `scripts/ui/quest_log.gd`, fin de partida: `scripts/systems/run_manager.gd`.
- Fila de misión: `id`, `display_name`, `description`, `stat` (id de contador — lista canónica en la cabecera de `save_data.gd`: `total_kills`, `bosses_killed`, `runs_finished`, `victories`, `shrines_used`, `chests_opened`, `max_level`, `best_run_minutes`, `runs_as_<char>`, `wins_as_<char>`, `runs_on_<map>`, `victories_<map>_t<tier>`, `any_t2_win`, `slain_<miniboss>`, ...), `target`, `reward`.
- Flujo: sistemas en partida acreditan **en memoria** con `SaveData.bump(stat_id)` / `raise_to(stat_id, valor)`; al terminar la partida `RunManager` llama `SaveData.fold_run_results(...)`, que acumula contadores, marca misiones completadas y guarda (una partida abandonada no persiste nada). El cobro es manual en el Quest Log (`claim_quest`). Un contador nuevo no necesita registro: `bump` crea la clave.

## Santuarios, cofres y secretos

- Qué es: interactuables de mundo con prompt flotante `[E]`, un solo uso.
- Archivos: base `scripts/world/interactable.gd` (`Interactable extends Area3D`); `chest.gd`, `charge_shrine.gd`, `greed_shrine.gd`, `curse_shrine.gd`; secretos: `secret_trigger.gd` (`SecretTrigger`), `odd_stump.gd`, `humming_skull.gd`, `scripts/enemies/secret_boss_base.gd`.
- Contrato `Interactable`: sobreescribir `_interact(player)` (y opcionalmente `_on_range_entered/_exited`); llamar `consume()` al gastarse (bumpea `meta_stat_id` — `"shrines_used"` / `"chests_opened"` — y apaga el prompt); `dim_visuals()` para el gris de "usado"; `_emit_completed()` da sparkle + sonido (`complete_sound`).
- Recompensas por grupos: cartas gratis vía `call_group("upgrade_ui", "open_bonus_pick", titulo, luck_bonus, min_rarity)` (Charge: luck +60; Greed: rareza mínima "Rare"); presión vía `call_group("enemy_spawner", "spawn_pressure_burst", centro, n)`; maldición vía `RunState.add_curse()`.
- Secreto nuevo: `extends SecretTrigger`, define la condición (OddStump: 3 interacciones; HummingSkull: canal quieto de 4 s) y llama `_awaken()` — gasta, anuncia por `boss_ui` y spawnea `miniboss_scene` (raíz `extends SecretBossBase` con `secret_boss_id` exportado: su muerte bumpea `slain_<id>`, toca `secret_fanfare` y desbloquea el personaje cuya fila tenga ese `unlock_boss`).

## UI

- Capas (CanvasLayer): HUD 5 → UpgradeCardUI 10 → RunEndScreen 20 → PauseMenu 30. Archivos en `scripts/ui/` + `scenes/ui/`.
- HUD (`hud.gd`): grupos `hud` y `boss_ui`; API por grupo: `announce(msg)` (banner), `track_boss(boss, title)` (barra de jefe), `show_tier_tag(tier)`. Barras HP/XP, timer, kills, rachas, flecha de jefe (`boss_arrow.gd`). Overlay de perf oculto: export `show_perf_probe` o `BONK_PERF=1`.
- Cartas (`upgrade_card_ui.gd`): en `RunState.leveled_up` pausa el árbol y ofrece 3 tiradas de `UpgradePool.roll_offer()`; los picks extra (level-ups encadenados, cofres/santuarios vía `open_bonus_pick`) se encolan. `UpgradePool.apply(offer, player)` aplica la carta elegida.
- Contrato de pausa: quien posee la pausa se une a `ui_blocking` y expone `is_blocking() -> bool`; `pause_menu.gd` ignora Esc mientras algún miembro bloquee — así el menú nunca roba la pausa de las cartas o del fin de partida. Al añadir una UI que pause, seguir este patrón.
- Fin de partida: `run_manager.gd` (señal `run_ended`, cableada dentro de `RunSystems.tscn`) → `run_end_screen.gd` (lee `SaveData.last_*` para el resumen de Shards/misiones).

## Sistemas transversales

- **Pools** (`scripts/systems/pools.gd` + `node_pool.gd`): pooling de los 9 hotspots (gemas, orbes, dardos, flechas, boomerang, bolts enemigos, bursts, popups, discos de telégrafo). Contrato: spawn = `Pools.acquire_scene(escena)`, despawn = `Pools.release(nodo)`; el script pooled implementa `pool_reset()` restaurando estado recién-spawneado (ver `projectile.gd`, `xp_gem.gd`). Escena nueva de alta rotación: const preload + `_register()` + `pool_sizes` en `pools.gd`; sin registrar, `acquire_scene` cae a instanciar normal.
- **Juice** (`scripts/systems/juice.gd`, autoload): hooks semánticos de una línea — `enemy_died(pos, color)`, `boss_died(...)`, `crit_punch()`, `player_hurt()`, `sparkle(pos)`, `flash(visual)`, `shake(...)`, `hit_stop(...)`, `fov_kick_begin/end()`. Una mecánica nueva con impacto debería llamar a uno existente antes que inventar efectos propios; tunables como exports del autoload.
- **Sfx** (`scripts/systems/sfx.gd`, autoload): `Sfx.play(&"id")` sobre un pool de voces con jitter de pitch y rate-limit; loops con `acquire_loop/release_loop`. Sonido nuevo = receta en `scripts/tools/generate_sfx.gd` (síntesis determinista) + entrada en `STREAMS` (y `id_volume_db`). Regenerar los wav: `godot --headless --path . -s res://scripts/tools/generate_sfx.gd`.
- **Capa de stats** (`scripts/systems/player_stats.gd`, nodo `Stats` del Player): guarda stacks de tomos + pasiva y **recalcula todo desde cero** en `recompute()` en cada cambio (nunca acumular sobre valores derivados — así el stacking no deriva). Stat nuevo: campo derivado + rama en `_apply_effect(stat, amount)` + que el consumidor lo lea (armas vía helpers de `WeaponBase`, `Health` recibe `armor`/`evasion` empujados).
- **Health** (`scripts/systems/health.gd`): componente hijo reutilizable; señales `damaged`, `damaged_by(attacker)` (thorns), `dodged(attacker)` (ejecuciones), `died`. `Health.find_in(body)` / `PlayerStats.find_in(body)` son la forma estándar de encontrar componentes.

## Convenciones

- **GDScript con tipado estático** en el 100% del código (parámetros, retornos, variables con tipo, `:=` solo con tipo inferible). Mantenerlo: el codebase compila limpio y los soaks dependen de ello.
- **Señales y grupos, no referencias duras** entre escenas: `call_group(...)` / `get_first_node_in_group(...)` para todo acoplamiento cruzado; rutas de nodo solo dentro de la propia escena.
- **Tunables como `@export`** con defaults en el script; los overrides por instancia viven en la escena (ej. el horario de jefes por arena).
- **Logs de una línea** en eventos clave (`Run ended:`, `Boss spawned:`, `Meta saved:`, `Secret miniboss awakened:`) — son la interfaz de verificación de los soaks headless; conservarlos y añadir el propio al crear un evento mayor.
- **Testing por harness desechable**: para probar lógica aislada, script `extends SceneTree` (patrón de `generate_sfx.gd`) ejecutado con `godot --headless --path . -s res://...`, más los soaks de `--fixed-fps 60 --quit-after N` del README. `SaveData.save_path` es re-apuntable para no tocar el save real.
