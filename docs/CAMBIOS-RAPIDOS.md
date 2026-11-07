# Cambios rápidos: dónde está cada cosa

Esta guía es para cambios chicos sin leer código. Busca en la tabla lo que
quieres cambiar, abre el archivo o la escena que indica y cambia el valor.

## Antes de tocar nada

1. **Si es parte de una escena** (un arma, un enemigo, el jugador, un altar,
   el HUD), ábrela en Godot, selecciona el nodo que dice la tabla y cambia el
   valor en el Inspector. Los valores están agrupados (Movimiento, Colores,
   Textos…). Si pasas el mouse sobre el nombre de una propiedad, la ayuda te
   dice qué es y en qué unidad está (segundos, metros, píxeles…).
2. **Si junto a un valor aparece la flechita circular ↺**, esa escena le pone
   su propio valor. Ese es el que vale en el juego, no el que trae el script.
   Si cambiaste un script y no pasó nada, busca esa flechita.
3. **Los catálogos** (`scripts/systems/catalogs/`) son listas de filas:
   personajes, armas, cartas, objetos, misiones, mascotas, reliquias, mapas.
   Al comienzo de cada archivo dice qué campos puedes cambiar sin miedo y
   cuáles son llaves internas. **Nunca cambies un `id`**: es la llave del
   guardado y de las misiones. Para el nombre que ve el jugador está
   `display_name`.
4. Donde dice **«bloque Edita aquí»**, el valor es una constante al comienzo
   del script (son scripts que no tienen escena, así que no hay Inspector).
5. Cuando termines, corre `tools/verificar.sh` (o por lo menos juega una
   partida) antes de subir el cambio.

## Números de daño

El número flotante decide su propio aspecto: `health.gd` solo le avisa si el
golpe fue normal, crítico o una esquiva.

| Qué quieres cambiar | Dónde | Qué propiedad |
| --- | --- | --- |
| Color del número normal, del crítico o de la esquiva | `scenes/fx/DamagePopup.tscn` > DamagePopup (grupo «Colores») | `damage_color`, `crit_color`, `dodge_color`, `outline_color` |
| Tamaño de letra de cada tipo | `DamagePopup.tscn` > DamagePopup (grupo «Tamaños de letra») | `damage_font_size`, `crit_font_size`, `dodge_font_size` |
| Texto que sale al esquivar | `DamagePopup.tscn` > DamagePopup (grupo «Textos») | `dodge_text` |
| Altura, subida y desvanecido del número | `DamagePopup.tscn` > DamagePopup (grupo «Movimiento») | `spawn_lift`, `spawn_jitter`, `rise_height`, `rise_time`, `fade_delay`, `fade_time` |
| Que un cuerpo no muestre números | la escena del cuerpo > nodo `Health` | `show_damage_popups` |

## Jugador

| Qué quieres cambiar | Dónde | Qué propiedad |
| --- | --- | --- |
| Velocidad al caminar | `scenes/player/Player.tscn` > Player (grupo «Movimiento») | `move_speed` (m/s) |
| Aceleración en el suelo y en el aire | Player.tscn > Player («Movimiento») | `acceleration`, `air_acceleration` |
| Altura del salto | Player.tscn > Player («Movimiento») | `jump_velocity` |
| Velocidad, duración y espera del derrape | Player.tscn > Player (grupo «Derrape») | `slide_speed_multiplier`, `slide_duration`, `slide_cooldown` |
| Cuántas armas o tomos distintos puede llevar | Player.tscn > Player (grupo «Inventario») | `max_weapons`, `max_tomes` |
| Vida del raider | Player.tscn > nodo `Health` | `max_hp` |
| Daño crítico base | Player.tscn > nodo `Stats` | `base_crit_damage` |
| Sensibilidad del mouse y ángulos de cámara | Player.tscn > CameraRig | `mouse_sensitivity`, `initial_pitch_deg`, `min_pitch_deg`, `max_pitch_deg`, `spring_length` |
| Campo de visión (FOV) | Player.tscn > CameraRig > Camera3D | `fov` |
| Cámara en primera persona y órbita libre | Player.tscn > CameraRig (grupos «Primera persona», «Órbita libre») | `first_person_*`, `free_orbit_*` |
| Radio y tiempo para revivir a un compañero (co-op) | Player.tscn > Revive | `revive_radius`, `revive_time`, `revive_heal_fraction` |
| Texto, color y tamaño del cartel «CAÍDO» | Player.tscn > Revive > RevivePrompt | `down_text`, `reviving_text`, `down_color`, `reviving_color`, `font_size` |
| Power-up Vuelo (subida, techo, planeo) | Player.tscn > Flight | `flight_rise_speed`, `flight_ceiling`, `flight_fall_speed` |
| Aviso cuando llega o se va una mascota | Player.tscn > PetSlot | `joins_text`, `leaves_text` |
| Respiración, inclinación y rebote de la foca | `scenes/player/SealRig.tscn` > SealRig | `breathe_*`, `lean_max`, `bob_amount`, `bob_speed`, `reference_speed` |
| Estiramiento al saltar y aplastado al derrapar | SealRig.tscn > SealRig | `stretch_max`, `slide_squash`, `slide_spread` |

## Armas

Cada arma es una escena en `scenes/weapons/`. Daño, enfriamiento y alcance
siempre están en la escena de cada arma; lo que es propio del arma está en
grupos con su nombre.

| Qué quieres cambiar | Dónde | Qué propiedad |
| --- | --- | --- |
| Daño, enfriamiento y alcance de un arma | `scenes/weapons/<Arma>.tscn` > raíz (grupo «Estadísticas») | `damage`, `cooldown`, `attack_range`, `projectile_count` |
| Cómo se reparten los disparos extra del Tomo de Multitud | `<Arma>.tscn` > raíz (grupo «Multitud») | `extra_stagger` (segundos entre extras), `extra_fan_deg` |
| Color o forma del efecto de un arma | `<Arma>.tscn` > raíz, la malla del grupo (`flask_mesh`, `beam_mesh`, `orb_mesh`, `cloud_mesh`, `puddle_mesh`, `bolt_mesh`) | su material (`albedo_color`, emisión) |
| Espada corta | `Shortsword.tscn` > Shortsword | `arc_angle_deg`, `swing_time`, `slash_color`, `spark_color` |
| Dagas gemelas | `TwinDaggers.tscn` > TwinDaggers | `slash_time`, `slash_radius`, `slash_color`, `slash_sweep_deg` |
| Orbes espirituales (tamaño visual, tamaño de golpe, velocidad) | `SpiritOrbs.tscn` > SpiritOrbs (grupo «Orbes») | `orb_radius`, `hit_radius`, `orbit_speed`, `orb_height` |
| Kamehameha (largo, ancho, sacudida, cámara lenta) | `Kamehameha.tscn` > Kamehameha (grupos «Rayo», «Sensación») | `beam_length`, `beam_width`, `shake_strength`, `hit_stop_time` |
| Báculo de nigromante (siervos y rayo) | `NecroStaff.tscn` > NecroStaff (grupos «Siervos», «Rayo de alma») | `possess_duration`, `max_possessed`, `bolt_speed`, `bolt_lifetime` |
| Vial de sangre (lanzamiento y charco) | `BloodVial.tscn` > BloodVial (grupos «Frasco», «Charco») | `lob_time`, `arc_height`, `pool_radius`, `pool_ticks`, `heal_fraction` |
| Rastro de baba | `SlimeTrail.tscn` > SlimeTrail (grupos «Charco», «Visual») | `puddle_radius`, `puddle_life`, `tick_interval` |
| Hedor (veneno, ralentización, nube) | `Stench.tscn` > Stench | `poison_damage_fraction`, `slow_multiplier`, `cloud_*` |
| Aura y Hedor: cuánto crece el campo con Multitud | `Aura.tscn` / `Stench.tscn` > raíz (grupo «Multitud») | `radius_per_extra`, `pulse_per_extra` |
| Pararrayos (cadena) | `StormRod.tscn` > StormRod (grupo «Cadena») | `chain_count`, `chain_range` |
| Látigo de espinas | `ThornWhip.tscn` > ThornWhip | `strip_width`, `slow_percent`, `slow_duration` |
| Vara de brasas | `EmberWand.tscn` > EmberWand | `burst_radius` |
| Bumerán | `Boomerang.tscn` y `BoomerangProjectile.tscn` | `travel_scale`; `speed`, `spin_speed` |
| Velocidad, rastreo y perforación de dardos y flechas | `Projectile.tscn` (dardo) / `Arrow.tscn` (flecha) > raíz | `speed`, `homing_enabled`, `pierce_remaining` |
| Destello del disparo, tajos y latigazo | `scenes/fx/MuzzleFlash.tscn`, `SlashArc.tscn`, `WhipCrack.tscn` > raíz | sus grupos de forma y tiempo |
| Rayo del Pararrayos y del Cinturón eléctrico | `scenes/fx/LightningBeam.tscn` > raíz | grosor, brillo y tiempo del rayo |
| Nombre, sigla, carta propia, evolución | ver «Personajes, armas, cartas y progreso» | |

## Enemigos y jefes

| Qué quieres cambiar | Dónde | Qué propiedad |
| --- | --- | --- |
| Vida de un enemigo | `scenes/enemies/<Enemigo>.tscn` > nodo `Health` | `max_hp` |
| Velocidad, giro y empuje entre enemigos | `<Enemigo>.tscn` > raíz (grupo «Movimiento») | `move_speed`, `turn_speed`, `separation_strength` |
| Puntos que paga | `<Enemigo>.tscn` > raíz (grupo «Recompensa») | `points_value` |
| Daño de contacto | `<Enemigo>.tscn` > raíz | `contact_damage` |
| Si un enemigo se puede poseer o trepar | `<Enemigo>.tscn` > raíz (grupos «Posesión», «Trepar») | `possessable`, `can_climb`, `max_climb_height` |
| Fuerza de los shiny (vida, velocidad, daño, XP) | `scripts/enemies/enemy_base.gd` (grupo «Shiny») o la escena del enemigo | `elite_*` |
| Colores del shiny, del veneno, de los poseídos y la animación de muerte | `assets/enemies/enemy_look.tres` (ábrelo en el Inspector) | grupos Shiny, Veneno, Poseído, Muerte |
| Luna de sangre y eclipse (velocidad, daño, vida, color) | `scripts/enemies/enemy_base.gd`, tabla `VARIANTS` al comienzo | filas `berserker` y `shade` |
| Altura a la que apuntan las armas | `scripts/enemies/enemy_base.gd` (grupo «Puntería») o la escena del enemigo | `aim_height` |
| Colores de los avisos y del impacto de un jefe, temblor y destello | `scenes/enemies/<Jefe>.tscn` > raíz (grupo «Telegrafía») | `telegraph_color`, `impact_color`, `impact_shake_strength`, `impact_shake_duration`, `impact_flash_time` |
| Lo que paga un jefe al morir | `<Jefe>.tscn` > raíz | `boss_gem_count`, `boss_gem_value`, `health_orb_count`, `base_chest_drops` |
| Púas de corteza (Rey Pútrido) y de arenisca (Sarcognato) | `scenes/enemies/BarkSpikes.tscn` / `SandSpikes.tscn` | la malla y el material de `Spike1`; tiempos en la raíz |
| Láseres (color y grosor) | `Sunspitter.tscn` > AimLine / Beam; `Sarcognath.tscn` > WarnLine / Beam | `color`, `default_thickness`, `emission_energy` |
| Discos de aviso en el suelo | `scenes/fx/TelegraphDisc.tscn` > raíz | `start_scale`, `peak_energy`, `fade_time`; opacidad en su material |
| Velocidad de los proyectiles enemigos | `scenes/enemies/EnemyBolt.tscn` > raíz | `speed`, `max_distance` (el daño lo pone quien dispara) |
| Nombre de un jefe en pantalla | `<Jefe>.tscn` > raíz | `boss_title` (y la tabla `BESTIARY` de `scripts/ui/meta/collection.gd`) |

## Aparición de enemigos

El nodo `EnemySpawner` vive dentro de cada arena (`scenes/world/<Arena>.tscn`).
Lo que no cambia por mapa se edita en `scripts/systems/enemy_spawner.gd`.

| Qué quieres cambiar | Dónde | Qué propiedad |
| --- | --- | --- |
| Cuántos enemigos salen (flujo y hordas a la vez) | `enemy_spawner.gd` (grupo «Ritmo y dificultad») | `spawn_count_multiplier` |
| Ritmo del flujo de enemigos | `enemy_spawner.gd` («Ritmo y dificultad») | `start_interval`, `min_interval`, `interval_shrink_per_minute`, `base_count_per_tick`, `extra_count_per_minute` |
| Máximo de enemigos vivos | `enemy_spawner.gd` (grupo «Cupo de enemigos») | `max_active`, `horde_overflow`, `pressure_overflow` (si subes el multiplicador, súbelos juntos) |
| Hordas en co-op | `enemy_spawner.gd` (grupo «Co-op») | `coop_horde_per_extra_player` |
| Minuto del jefe, jefe ancestral y su aviso | `scenes/world/<Arena>.tscn` > EnemySpawner (grupo «Jefes») | `boss_spawn_minute`, `elder_spawn_minute`, `boss_warning_text`, `elder_title` |
| Qué enemigos salen en cada minuto | `enemy_spawner.gd`, tablas al comienzo | `FOREST_PHASES`, `DUNES_PHASES`, `MARSH_PHASES` (un bioma nuevo va al FINAL del enum `PhasePreset`) |
| Probabilidad de que caiga un power-up | `enemy_spawner.gd` (grupo «Power-ups») | `base_powerup_drop_chance`, `shiny_powerup_drop_scale` |
| Textos de «¡TIEMPO DETENIDO!» | `enemy_spawner.gd` (grupo «Tiempo detenido») | `time_stop_start_text`, `time_stop_end_text` |

## Personajes, armas, cartas y progreso (catálogos)

| Qué quieres cambiar | Dónde | Qué propiedad |
| --- | --- | --- |
| Nombre, frase o pasiva de un personaje | `scripts/systems/catalogs/character_catalog.gd` > su fila en `CHARACTER_ROWS` | `display_name`, `blurb`, `passive_description`, `passive_stat`, `passive_amount` |
| Arma inicial de un personaje | `character_catalog.gd` > `CHARACTER_ROWS` | `weapon_node_name` (el `node_name` de una fila de `weapon_catalog.gd`) |
| Precio de un personaje | `character_catalog.gd` > `CHARACTER_ROWS` | `unlock_cost` (ojo: con 0 queda gratis para siempre en los guardados que ya existen) |
| Color o modelo de un personaje | `character_catalog.gd` > `CHARACTER_ROWS` | `tint`, `model_scene`, `model_scale` |
| Renombrar el `id` de un personaje (mejor no) | `character_catalog.gd` > `id` **y** `scripts/systems/autoloads/save_data.gd` > `ID_ALIASES` | el `id` nuevo, más una fila `"id_viejo": "id_nuevo"` para no romper guardados |
| Nombre, sigla o texto de un arma | `scripts/systems/catalogs/weapon_catalog.gd` > `WEAPON_LIBRARY` | `display_name`, `glyph`, `flavor` |
| Carta propia de un arma | `weapon_catalog.gd` > `WEAPON_LIBRARY` > `extra_entries` | `title`, `description`, `amount` |
| Cartas de mejora de todas las armas (Afilado, Mano rápida, Largo alcance, Temple, Ritmo de batalla) | `scripts/systems/catalogs/upgrade_pool.gd` > `WEAPON_STAT_CARDS` | `title`, `description`, `amount` |
| Cartas genéricas (Corazón recio, Aura de codicia) | `upgrade_pool.gd` > `GENERIC_POOL` | `title`, `description`, `amount` |
| Qué tan seguido salen cartas de arma nueva, de dos stats o de tomo | `upgrade_pool.gd` (bloque «Edita aquí») | `NEW_WEAPON_OFFER_WEIGHT`, `MULTI_STAT_OFFER_WEIGHT`, `TOME_OFFER_WEIGHT` |
| Probabilidad, potencia o color de una rareza | `scripts/systems/catalogs/rarity.gd` > `TIERS` | `weight`, `potency`, `color` |
| Nombre en pantalla de una rareza | `rarity.gd` > `DISPLAY_NAMES` | el texto («Común», «Raro»…) |
| Cuánto mejora la suerte las rarezas | `rarity.gd` | `LUCK_TILT_PER_POINT`, `MAX_LUCK_TILT` |
| Evolución de un arma | `scripts/systems/catalogs/evolution_catalog.gd` > `EVOLUTION_LIBRARY` | `evolved_name`, `glyph`, `mults`, `adds`, `flavor` |
| Cada cuántos niveles evoluciona o asciende un arma | `evolution_catalog.gd` | `EVOLVE_AT_LEVEL` |
| Cartel, fanfarria y sacudida de la evolución | `scripts/systems/catalogs/evolution_ceremony.gd` | `EVOLVED_BANNER`, `ASCENDED_BANNER`, `FANFARE_SFX`, `SHAKE_STRENGTH` |
| Mascotas | `scripts/systems/catalogs/pet_catalog.gd` > `PET_LIBRARY` | `display_name`, `weapon_scene`, `weapon_damage_scale`, `stat`, `amount_per_level`, `color` |
| Misiones (texto, meta, premio) | `scripts/systems/catalogs/quest_catalog.gd` > `QUEST_LIBRARY` | `display_name`, `description`, `target`, `reward` |
| Reliquias de la Armería | `scripts/systems/catalogs/relic_catalog.gd` > `RELIC_LIBRARY` | `display_name`, `amount`, `max_ranks`, `base_cost`, `cost_growth` |
| Orden y textos de los mapas | `scripts/systems/catalogs/map_catalog.gd` > `MAP_LIBRARY` | orden de las filas, `display_name`, `blurb` |

## Objetos, power-ups, sonido y sensaciones

| Qué quieres cambiar | Dónde | Qué propiedad |
| --- | --- | --- |
| Números de un objeto (imán, veneno, titán, arañas, aura sayayin, zenkai…) | `scripts/systems/catalogs/item_catalog.gd` > su fila en `ITEM_LIBRARY` | sus campos numéricos (la descripción se arma sola con ellos) |
| Duración, peso, color o texto de un power-up | `scripts/systems/catalogs/powerup_catalog.gd` > su fila en `POWERUP_LIBRARY` | `duration`, `weight`, `color`, `display_name` |
| Fiebre del oro, reflejo, vida por baja del vampiro | `powerup_catalog.gd` > fila gold / reflect / vampire | `points_multiplier`, `reflect_fraction`, `max_hp_per_kill` (si cambias el número, ajusta el texto) |
| Textos «¡Aura sayayin!» y «¡Zenkai!» | Player.tscn > ItemBag (grupo «Textos») | `saiyan_aura_text`, `zenkai_text` |
| Power-up en el suelo (tamaño, brillo, luz, duración) | `scenes/systems/PowerUpPickup.tscn` > sus nodos y la raíz | la malla de `Gem`, `light_energy`; `lifetime`, `spin_speed` en la raíz |
| Orbe de vida (imán, curación, duración) | `scenes/systems/HealthOrb.tscn` > HealthOrb | `magnet_radius`, `heal_fraction`, `lifetime` |
| Sacudida de cámara | `scenes/systems/Juice.tscn` > Juice (grupo «Sacudida de cámara») | `kill_shake_*`, `hurt_shake_*`, `boss_death_shake_*`, `crit_shake_*` |
| Cámara lenta al crítico o al matar un jefe | Juice.tscn > Juice («Hit-stop») | `crit_stop_scale`, `crit_stop_duration`, `boss_death_stop_*` |
| Destello blanco al golpear | Juice.tscn > Juice («Destello de golpe») | `flash_duration`, `flash_color` |
| Viñeta roja al recibir daño | Juice.tscn > Juice («Viñeta de daño») | `vignette_strength`, `vignette_fade_time` |
| Anillo al subir de nivel | Juice.tscn > Juice («Anillo de subida de nivel») | `level_pulse_color`, `level_pulse_duration` |
| Volumen, tope por segundo o variación de un sonido | `scripts/systems/autoloads/sfx.gd` > su fila en `SOUND_LIBRARY` | `volume_db`, `rate_limit`, `jitter`, `loop` |
| Voces simultáneas de sonido | `scenes/systems/Sfx.tscn` > Sfx | `pool_size`, `default_pitch_jitter` |
| Precio de los cofres y cuánto suben | `scripts/systems/autoloads/run_state.gd` | el bloque de precios de cofres |
| Curva de experiencia por nivel | `scripts/systems/autoloads/run_state.gd` | el bloque de la curva de XP |

## Eventos del mapa, clima y portales

| Qué quieres cambiar | Dónde | Qué propiedad |
| --- | --- | --- |
| Cuándo sale el primer evento y la pausa entre eventos | `scenes/world/RunSystems.tscn` > WorldDirector (grupo «Eventos») | `first_event_at`, `event_gap_min`, `event_gap_max`, `event_gap_floor` |
| Qué tan seguido sale cada evento, su aviso y su baliza | `scripts/world/run/world_director.gd` > su fila en `EVENT_LIBRARY` | `weight`, `announce`, `beacon_color`, `beacon_time` |
| Máximo de vendedores o manantiales a la vez | `world_director.gd` > fila `vendor` / `spring` | `cap` |
| Tope y ritmo de los altares | RunSystems.tscn > WorldDirector (grupo «Altares») | `altar_cap_base`, `altar_cap_minutes` |
| Aspecto del pilar de baliza | `scenes/world/director/Beacon.tscn` > Pillar / Light / raíz | `height`, `light_energy`, `pulse_half_time` |
| Cofre de suministros (rareza mínima, suerte) | `scenes/world/director/SupplyChest.tscn` > SupplyChest | `min_rarity`, `luck_bonus` |
| Aviso, tinte del cielo, nombre en el HUD y partículas de un clima | `scripts/world/run/director/weather_director.gd` > su fila en `WEATHER_CATALOG` | `announce`, `sun_color`, `sun_energy`, `ambient_color`, `fx_color`, `display_name` |
| Duración de un clima y probabilidades de desastre, lluvia y luna | RunSystems.tscn > WorldDirector > Weather | `weather_duration_overrides`, `disaster_chance`, `rain_chance`, `sky_event_chance` |
| Ácido, meteoritos y tsunami (daño, radio, frecuencia) | RunSystems.tscn > WorldDirector > Weather (grupos por clima) | `acid_pool_*`, `meteor_*`, `tsunami_*` |
| Bonos de la luna llena y de la lluvia dorada | RunSystems.tscn > WorldDirector > Weather | `full_moon_xp_bonus`, `full_moon_luck_bonus`, `golden_points_multiplier` |
| Portales, ruletas, cofres y cajas al inicio de cada etapa | RunSystems.tscn > WorldDirector > StageFixtures | `portal_count`, `roulette_count`, `extra_start_chests_min/max`, `start_pet_box_chance` |
| Colores y recarga de los pares de portales | `scenes/world/director/PortalShrine.tscn` > PortalShrine | `pair_colors`, `cooldown` |
| Color y tamaño del portal de salida | `scenes/world/director/ExitPortal.tscn` > ExitPortal | `portal_color`, `ring_radius` |

## Altares, cofres y secretos del mapa

Todos los interactuables comparten la base `scripts/world/interactables/interactable.gd`:
lo que cambies ahí vale para todos los que no tengan su propio valor en la escena.

| Qué quieres cambiar | Dónde | Qué propiedad |
| --- | --- | --- |
| Tamaño, color y altura del aviso «[E] …» | `interactable.gd` (grupo «Aviso flotante») | `prompt_font_size`, `prompt_outline_size`, `prompt_color`, `prompt_height` |
| Cuánto tarda en hundirse algo gastado | la escena del interactuable > raíz (grupo «Gastado») | `sink_duration`, `sink_depth`, `spent_color` |
| Brillo de los cofres según la rareza | `scenes/world/chests/Chest.tscn` > Chest (grupo «Brillo por rareza») | `glow_energy_by_rarity`, `free_glow_energy`, `free_tint` |
| Salto de apertura y textos del cofre | `Chest.tscn` > Chest (grupos «Apertura», «Textos») | `open_duration`, `open_hop_height`, `paid_prompt`, `opened_announce` |
| Color del anillo de un altar de carga o del altar demoníaco | `scenes/world/shrines/ChargeShrine.tscn` / `CurseShrine.tscn` > raíz (grupo «Anillo») | `accent_color` |
| Tiempo de carga y tamaño del don | `ChargeShrine.tscn` / `CurseShrine.tscn` > raíz (grupo «Carga») | `channel_time`, `boon_scale` |
| Costo de dificultad de los pactos | `CurseShrine.tscn` > CurseShrine (grupo «Pactos») | `difficulty_scale` (1 = lo que dice `PACT_LIBRARY` en `curse_shrine.gd`) |
| Premios y aspecto del bloque de la suerte | `scenes/world/chests/LuckyBlock.tscn` > LuckyBlock | `points_reward`, `gem_count`, `explosion_radius`, `block_color` |
| Caja de mascota | `scenes/world/PetBox.tscn` > PetBox | `paw_color`, grupo «Textos» |
| Precio y textos del manantial | `scenes/world/shrines/SpringShrine.tscn` > SpringShrine | `price`, `price_prompt` |
| Peaje y premio del altar de la codicia | `scenes/world/shrines/GreedShrine.tscn` > GreedShrine | `hp_cost_fraction`, `gem_chance`, `card_chance` |
| Altar de eventos | `scenes/world/shrines/EventAltar.tscn` > EventAltar | `glass_color`, `busy_prompt` |
| Minijefe secreto y su frase | `scenes/world/secrets/HummingSkull.tscn` / `OddStump.tscn` > raíz | `miniboss_scene`, `spawn_offset`, `awaken_text` |

## Terreno y reparto del mapa

Cada arena es una escena: `scenes/world/HollowWoods.tscn` (Bosque Hueco),
`AshDunes.tscn` (Dunas de Ceniza) y `Gloomfen.tscn` (Ciénaga Lóbrega). El nodo
de reparto se llama `ForestScatter`, `DuneScatter` o `MarshScatter`.

| Qué quieres cambiar | Dónde | Qué propiedad |
| --- | --- | --- |
| Tamaño de la arena | la arena > *Scatter (grupo «Arena») | `arena_half_extent` (y mover a mano los muros de `Perimeter` a ±(ese valor + 0.5)) |
| Cuántos árboles, rocas o tocones hay y su tamaño | la arena > *Scatter (grupo «Reparto interior») | `tree_count`, `rock_count`, `stump_count`, `*_scale_min/max` |
| Ancho de los pasillos y zona libre del inicio | la arena > *Scatter («Reparto interior») | `min_prop_spacing`, `spawn_clear_radius`, `keepout_radius` |
| Línea de props del borde | la arena > *Scatter (grupo «Borde») | `perimeter_step`, `perimeter_rock_every`, `perimeter_jitter` |
| Mesetas | la arena > *Scatter (grupo «Mesetas») | `mesa_count`, `mesa_scale_min/max`, `mesa_ramp_offset` |
| Formaciones de roca (cuántas y qué tan grandes) | la arena > *Scatter (grupo «Máscara de la arena») | `mask_blobs_min/max`, `mask_blob_cells_min/max`, `mask_min_open_fraction` |
| Color y forma de la roca de un bioma | `assets/world/rock_style_<mapa>.tres` | `rock_color`, `cap_color`, `cliff_height`, `peak_height`, `max_height` (bajar `margin_min` o `cliff_height` puede abrir huecos en el sello del mapa) |
| Jugar siempre el mismo mapa (para probar) | la arena > *Scatter (grupo «Semilla») | `randomize_per_run` apagado y `scatter_seed` |
| Altura de las lomas del suelo | la arena > Terrain (grupo «Relieve») | `amplitude`, `feature_size` |
| Color del minimapa y colinas del horizonte | la arena > Backdrop | `ground_color`, `hill_color`, `far_hill_color` (cambiar `hill_count` mueve los altares aunque la semilla sea la misma) |
| Tamaño y variante de los pinos | `scenes/world/props/Tree.tscn` > Tree | `wide_chance`, `base_scale`, `width_scale_min/max`, `height_scale_min/max` |
| Color de las rocas sueltas | `assets/materials/boulder.tres`, `boulder_red.tres` | `shader_parameter/albedo` |

## HUD

| Qué quieres cambiar | Dónde | Qué propiedad |
| --- | --- | --- |
| Posición o tamaño de cualquier elemento del HUD | `scenes/ui/HUD.tscn` > el nodo (TimerLabel, KillsLabel, BuildStrip, BagStrip, FpsBadge, PowerUpRow, MatePanel…) | Layout (anclas y márgenes) |
| Tamaño y margen del minimapa | HUD.tscn > ViewWidgets/MinimapSlot (solo cuentan su tamaño y sus márgenes, medidos desde la esquina superior derecha de cada celda; no muevas sus anclas); en las celdas de abajo, ViewWidgets | Layout > márgenes; `lower_cell_top_margin` |
| Color o tamaño de Nivel, Reloj, Bajas y Puntos | HUD.tscn > LevelLabel, TimerLabel, KillsLabel, PointsLabel | Theme Overrides > Colors / Font Sizes |
| Colores de la barra de vida y el latido de vida baja | HUD.tscn > HUD | `hp_full_color`, `hp_low_color`, grupo «Latido de vida baja» |
| Color de la barra de XP | HUD.tscn > HUD | `xp_color`, `xp_trough_color` |
| Textos de bajas, puntos, dificultad, etapa y reloj | HUD.tscn > HUD (grupo «Textos») | `kills_format`, `points_format`, `difficulty_format`, `stage_format`, `timer_format` |
| Palabras, colores y umbrales de las rachas («¡TRITURANDO!») | HUD.tscn > StreakLabel | `tier_kills`, `tier_words`, `tier_colors`, `window_seconds` |
| Duración y color de los avisos en pantalla | HUD.tscn > AnnounceLabel | `fade_in_time`, `hold_time`, `fade_out_time`, `normal_color`, `major_*` |
| Barra del jefe (y color de su flecha) | HUD.tscn > BossBar | `fill_color`, `glow_size`, `glow_alpha` |
| Colores de las fichas de armas, evoluciones y tomos | HUD.tscn > BuildStrip | `weapon_color`, `evolved_weapon_color`, `tome_color` |
| Fondo, borde y brillo de cada ficha | `scenes/ui/hud/LoadoutTile.tscn` > raíz | `background_color`, `border_width`, `glow_size` |
| Tarjeta de botín | `scenes/ui/hud/LootToast.tscn` > raíz | `hold_time`, `fade_time`, `background_color` |
| Filas de compañeros en co-op | `scenes/ui/hud/MateRow.tscn` > raíz | `knocked_out_format`, `knocked_out_tint`, `points_format` |
| Color del chip de clima bajo el reloj | HUD.tscn > TimerLabel/WeatherBadge | `group_colors`, `text_format` (el nombre sale de `display_name` en `weather_director.gd`) |
| Insignia de FPS | HUD.tscn > FpsBadge | `text_format`, `background_color`, `refresh_seconds` |
| Marco y refresco del minimapa | `scripts/ui/maps/minimap.gd` (bloque «Edita aquí») | `FRAME_PAD`, `MARKER_SCALE`, `BACKGROUND_COLOR`, `REFRESH` |
| Colores, formas y leyenda de los marcadores del mapa | `scripts/ui/maps/map_draw.gd` | `MARKER_STYLES`, `MARKER_LABELS` |
| Mapa de Tab: fondo, paneles y textos | `scenes/ui/maps/MapOverlay.tscn` (paneles: `scenes/ui/maps/MapSection.tscn`) | Layout, `title`, grupo «Textos» |
| Filas de estadísticas del mapa de Tab | `scripts/ui/maps/map_overlay.gd` | `STAT_ROWS` (al comienzo) |

## Menús

| Qué quieres cambiar | Dónde | Qué propiedad |
| --- | --- | --- |
| Título del selector de personajes | `scenes/ui/CharacterSelect.tscn` > TitleLabel | Theme Overrides |
| Textos de los botones del selector (Iniciar, Misiones, Colección, Armería, Cacería diaria) | `CharacterSelect.tscn` > raíz (grupo «Textos») y ButtonRow | `start_solo_format`, `start_party_format`; `text` de cada botón |
| Carta de personaje (letra y color del nombre, arma, pasiva, descripción) | `scenes/ui/meta/character_select/CharacterCard.tscn` > Unlocked/Name, Weapon, Passive, Blurb | Theme Overrides |
| Carta bloqueada (precio, candado, pregunta de desbloqueo) | `CharacterCard.tscn` > Locked/* y raíz | Theme Overrides; `confirm_format` |
| Bordes, escala y tamaño de la carta | `CharacterCard.tscn` > raíz | grupo «Bordes», `selected_scale`, `custom_minimum_size` |
| Lobby co-op (textos y botones 1-4) | `scenes/ui/meta/character_select/CoopLobby.tscn` | grupo «Textos»; PlayersRow/Count1..Count4 |
| Fondo de niebla de los menús | `assets/ui/menu_backdrop.tres` | `top_color`, `bottom_color`, `fog_color`, `fog_strength` |
| Títulos de Misiones, Armería y Colección | `scenes/ui/QuestLog.tscn`, `RelicShop.tscn`, `Collection.tscn` > TitleLabel | Theme Overrides |
| Filas de Misiones, Armería y Colección (letra, color, textos) | esas mismas escenas > raíz | grupos «Filas» y «Textos» |
| Entrada de filas, conteo del saldo y destello de pago de Misiones, Armería y Colección | esas mismas escenas > raíz (sección MetaScreen) | grupos «Animación» y «Textos» |
| Ajustes: formato de los valores, indicaciones y entrada del panel | `SettingsPanel.tscn` > raíz | grupos «Textos» (`sensitivity_format`, `volume_format`) y «Entrada» |
| Ajustes: color de los valores y encabezados | `scenes/ui/SettingsPanel.tscn` > los nodos *Value; encabezados en SoundHeader/Label, ControlsHeader/Label y ScreenHeader/Label (texto y letra) y */Rule (línea) | Theme Overrides, `text`; `color` de cada Rule |
| Rango de la sensibilidad del mouse | `scripts/systems/autoloads/save_data.gd` | `MIN_MOUSE_SENSITIVITY`, `MAX_MOUSE_SENSITIVITY` |
| Pantalla de fin de partida | `scenes/ui/RunEndScreen.tscn` > TitleLabel; colores en `scripts/ui/game/run_end_screen.gd` | Theme Overrides; `DEFEAT_TITLE_COLOR`, `VICTORY_TITLE_COLOR` |
| Textos de ganancias y animación de la pantalla de fin | `RunEndScreen.tscn` > raíz | grupos «Textos» (`stages_format`, `quests_format`…) y «Animación» (`title_start_scale`, `shimmer_color`…) |
| Colores compartidos y frases comunes («%d esquirlas», «J%d») | `scripts/ui/ui_theme.gd` | constantes al comienzo |
| Orden de dibujo de las capas de UI | las capas de escena en la raíz de su .tscn (HUD 5, UpgradeCardUI 10, modal/ModalPanel 15, RunEndScreen 20, PauseMenu 30); las que se crean en código en `scripts/ui/ui_layers.gd` | Layer; una constante por capa |

## Cartas de mejora, pausa, tienda y ruleta

| Qué quieres cambiar | Dónde | Qué propiedad |
| --- | --- | --- |
| Animación del reparto y de la carta elegida | `scenes/ui/UpgradeCardUI.tscn` > Motion | `reveal_delay`, `deal_time`, `deal_stagger`, `pick_scale` |
| Texto del título «Nivel N — elige» | `UpgradeCardUI.tscn` > raíz; aspecto en Center/VBox/LevelLabel | `level_title_template`; Theme Overrides |
| Letra, tamaño y color de los textos de una carta | `scenes/ui/upgrade_card_ui/UpgradeCard.tscn` > CardBox/RarityLabel, TitleLabel, DescLabel, WeapLabel | Theme Overrides |
| Brillo de las legendarias, cinta de rareza, crecer al pasar el cursor | `UpgradeCard.tscn` > raíz | `shine_color`, `ribbon_text_color`, `hover_grow` |
| Menú de pausa (título, animación, textos de ayuda) | `scenes/ui/PauseMenu.tscn` > TitleLabel y raíz | Theme Overrides; `panel_fade_time`, `accept_hint_text` |
| Marco común de la tienda y la ruleta («Tienes N pts», «Salir») | `scenes/ui/modal/ModalPanel.tscn` > raíz y sus nodos | `points_template`, `close_text`; propiedades de cada nodo |
| Textos y barrido de la ruleta | `scenes/ui/modal/RoulettePanel.tscn` > raíz | `title_text`, `spin_template`, `sweep_time`, `sweep_steps` |
| Premios de la ruleta (cuánto da cada resultado y su peso) | `scripts/world/interactables/roulette_shrine.gd` > `OUTCOMES` | `amount`, `seconds`, `weight` (el número de la etiqueta sale del campo) |
| Precio del altar de la ruleta | `scenes/world/shrines/RouletteShrine.tscn` > raíz | `price` |
| Cartas y textos de la tienda | `scenes/ui/modal/VendorPanel.tscn` > raíz | `card_size`, `card_title_font_size`, `sold_template` |
| Precios y oferta del vendedor | `scenes/world/Vendor.tscn` > Vendor | `pet_price`, `powerup_price_growth`, `pet_offers`, `item_offers` (precio inicial del power-up: `POWERUP_VENDOR_BASE_PRICE` en `run_state.gd`) |
| Aspecto del puesto del vendedor | `Vendor.tscn` > Stall, Figure, Sign, Light | malla, material, color de la luz |
