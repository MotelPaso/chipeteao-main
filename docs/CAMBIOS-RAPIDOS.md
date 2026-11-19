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
| Caída de cara al morir | SealRig.tscn > SealRig (grupo «Muerte») | `death_lift`, `death_duration`, `death_tilt`, `death_squash` |

## Armas

Cada arma es una escena en `scenes/weapons/`. Daño, enfriamiento y alcance
siempre están en la escena de cada arma; lo que es propio del arma está en
grupos con su nombre.

| Qué quieres cambiar | Dónde | Qué propiedad |
| --- | --- | --- |
| Daño, enfriamiento y alcance de un arma | `scenes/weapons/<Arma>.tscn` > raíz (grupo «Estadísticas») | `damage`, `cooldown`, `attack_range`, `projectile_count` |
| Cómo se reparten los disparos extra del Tomo de Multitud | `<Arma>.tscn` > raíz (grupo «Multitud»); Pistola de dardos y Arco de caza: grupos «Dardos» / «Flechas» | `extra_stagger` (segundos entre extras), `extra_fan_deg`; `fan_spread_deg` |
| Color o forma del efecto de un arma | `<Arma>.tscn` > raíz, la malla del grupo (`flask_mesh`, `beam_mesh`, `orb_mesh`, `cloud_mesh`, `puddle_mesh`, `bolt_mesh`); el Aura: `Aura.tscn` > `Disc` > `mesh` > material | su material: `albedo_color` (color y opacidad); son sin sombreado (la emisión no se ve), salvo `flask_mesh`: sombreado, su color es `albedo_color` más `emission`. En `bolt_mesh` solo cuenta la opacidad: el color sale de `assets/enemies/enemy_look.tres` > `possessed_color` |
| Espada corta | `Shortsword.tscn` > Shortsword | `arc_angle_deg`, `swing_time`, `slash_color`, `spark_color` |
| Dagas gemelas | `TwinDaggers.tscn` > TwinDaggers | `slash_time`, `slash_radius`, `slash_color`, `slash_sweep_deg` |
| Orbes espirituales (tamaño visual, tamaño de golpe, velocidad) | `SpiritOrbs.tscn` > SpiritOrbs (grupo «Orbes») | `orb_radius`, `hit_radius`, `orbit_speed`, `orb_height` |
| Kamehameha (largo, ancho, sacudida, cámara lenta) | `Kamehameha.tscn` > Kamehameha (grupos «Rayo», «Sensación») | `beam_length`, `beam_width`, `shake_strength`, `hit_stop_time` |
| Báculo de nigromante (siervos y rayo) | `NecroStaff.tscn` > NecroStaff (grupos «Siervos», «Rayo de alma») | `possess_duration`, `max_possessed`, `bolt_speed`, `bolt_lifetime` |
| Vial de sangre (lanzamiento y charco) | `BloodVial.tscn` > BloodVial (grupos «Frasco», «Charco») | `lob_time`, `arc_height`, `pool_radius`, `pool_ticks`, `heal_fraction` |
| Latido del charco del Vial de sangre | `scenes/fx/BloodPool.tscn` > raíz (grupo «Animación») | `throb_time`, `throb_spread`, `throb_height` |
| Rastro de baba | `SlimeTrail.tscn` > SlimeTrail (grupos «Charco», «Visual») | `puddle_radius`, `puddle_life`, `tick_interval` |
| Hedor (veneno, ralentización, nube) | `Stench.tscn` > Stench | `poison_damage_fraction`, `slow_multiplier`, `cloud_*` |
| Aura y Hedor: cuánto crece el campo con Multitud | `Aura.tscn` / `Stench.tscn` > raíz (grupo «Multitud») | `radius_per_extra`, `pulse_per_extra` |
| Pararrayos (cadena) | `StormRod.tscn` > StormRod (grupo «Cadena») | `chain_count`, `chain_range` |
| Látigo de espinas | `ThornWhip.tscn` > ThornWhip | `strip_width`, `slow_percent`, `slow_duration` |
| Vara de brasas | `EmberWand.tscn` > EmberWand | `burst_radius` |
| Bumerán | `Boomerang.tscn` y `BoomerangProjectile.tscn` | `travel_scale`; `speed`, `spin_speed` |
| Velocidad, rastreo y perforación de los dardos | `Projectile.tscn` > raíz | `speed`, `homing_enabled`, `pierce_remaining` |
| Velocidad y rastreo de las flechas | `Arrow.tscn` > raíz | `speed`, `homing_enabled` |
| Perforación de las flechas | `HuntingBow.tscn` > raíz | `pierce_count` (reemplaza el `pierce_remaining` de cada flecha) |
| Destello del disparo, tajos y latigazo | `scenes/fx/MuzzleFlash.tscn`, `SlashArc.tscn`, `WhipCrack.tscn` > raíz | sus grupos de forma y tiempo |
| Daño, rebotes y alcance del rayo del Cinturón eléctrico | `scripts/weapons/belt_bolt.gd` (bloque «Edita aquí») | `BELT_DAMAGE`, `DAMAGE_PER_EXTRA_COPY`, `BASE_BOUNCES`, `FIRST_RANGE`, `BOUNCE_RANGE` (si cambias `BASE_BOUNCES`, cambia también el «4» de la descripción de la fila `electric_belt` en `item_catalog.gd`) |
| Rayo del Pararrayos y del Cinturón eléctrico | `scenes/fx/LightningBeam.tscn` > raíz (grupos «Pararrayos», «Cinturón eléctrico») | `storm_mesh` / `belt_mesh` (radio, y color en `albedo_color` de su material), `*_fade_time`, `*_fade_scale` |
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
| Colores del shiny, del veneno, de los poseídos y la animación de muerte | `assets/enemies/enemy_look.tres` (ábrelo en el Inspector) | grupos Shiny, Veneno, Poseído, Muerte; `possessed_color` tiñe también el rayo del Báculo de nigromante |
| Luna de sangre y eclipse (velocidad, daño, vida, color) | `scripts/enemies/enemy_base.gd`, tabla `VARIANTS` al comienzo | filas `berserker` y `shade` |
| Altura a la que apuntan las armas | `scripts/enemies/enemy_base.gd` (grupo «Puntería») o la escena del enemigo | `aim_height` |
| Colores de los avisos y del impacto de un jefe, temblor y destello | `scenes/enemies/<Jefe>.tscn` > raíz (grupo «Telegrafía») | `telegraph_color`, `impact_color`, `impact_shake_strength`, `impact_shake_duration`, `impact_flash_time` (los ataúdes del Sarcognato usan `coffin_telegraph_color` y `coffin_shake_*`; el parpadeo del Espectro de la Ciénaga, `blink_shake_*`; el escupitajo del Larvón, `glob_flash_time`; el mordisco del Cofre Mímico, `snap_flash_time`) |
| Avisos, impacto y arena del Excavadunas | `scenes/enemies/Duneburrower.tscn` > raíz (grupo «Telegrafía») | `telegraph_color`, `impact_color`, `impact_flash_time`, `impact_shake_*`, `sand_burst_*` |
| Llegada de un jefe (anillo y aparición) | `scripts/enemies/boss_base.gd` (grupo «Llegada compartida») o `<Jefe>.tscn` > raíz | `entrance_ring_time`, `entrance_pop_time`, `entrance_start_scale`; `entrance_ring_radius` (Sarcognato, Larvón, Cofre Mímico) |
| Lo que paga un jefe al morir | `<Jefe>.tscn` > raíz | `boss_gem_count`, `boss_gem_value`, `health_orb_count`, `base_chest_drops` |
| Dónde caen las gemas, los orbes y los cofres de un jefe, y la suerte de cofre por altar demoníaco | `scripts/enemies/boss_base.gd` (grupos «Pago» y «Cofres»; vale para todos los jefes) o `<Jefe>.tscn` > raíz para uno solo | `gem_ring_radius`, `orb_ring_radius`, `chest_ring_radius`, `chest_luck_per_demonic` |
| Púas de corteza (Rey Pútrido) y de arenisca (Sarcognato) | `scenes/enemies/BarkSpikes.tscn` / `SandSpikes.tscn` | la malla y el material de `Spike1`; tiempos en la raíz |
| Animación del Rey Pútrido (inclinación del Aplastón, inflado del rugido) | `scenes/enemies/Rotking.tscn` > raíz (grupos «Aplastón», «Invocación») | `smash_lean_angle`, `smash_straighten_time`, `summon_roar_scale`, `summon_swell_fraction` |
| Aplastado del Espectro de la Ciénaga al hundirse | `scenes/enemies/Fenwraith.tscn` > raíz (grupo «Hundirse y emerger») | `blink_sink_squash`, `blink_sink_fraction` |
| Salto del Larvón (agazapado, estirón y altura del arco) | `scenes/enemies/Grubthing.tscn` > raíz (grupo «Salto embestida») | `hop_windup_squash`, `hop_leap_stretch`, `hop_stretch_time`, `hop_leap_lift` |
| Tapa y entierro del Cofre Mímico | `scenes/enemies/CofferMimic.tscn` > raíz (grupos «Mordisco», «Enterrarse») | `lid_gape_angle`, `snap_lid_close_time`, `bury_lid_close_time`, `bury_rise_time`, `bury_lid_open_time` |
| Estirón del Excavadunas al salir del suelo | `scenes/enemies/Duneburrower.tscn` > raíz (grupo «Erupción») | `erupt_pop_scale`, `erupt_pop_time` |
| Espera del muñeco de práctica antes de reaparecer | `scenes/enemies/TargetDummy.tscn` > raíz (grupo «Reaparición») | `respawn_delay` |
| Cada cuánto pega el veneno a un enemigo | `scripts/enemies/enemy/enemy_status.gd` (bloque «Edita aquí») | `POISON_TICK` (segundos) |
| Láseres (color y grosor) | `Sunspitter.tscn` / `Sarcognath.tscn` | color: `color` en AimLine / WarnLine (aviso) y Beam (disparo); grosor del aviso: `aim_width_start` / `aim_width_end` (raíz del Sunspitter) o `warn_width_start` / `warn_width_end` (raíz del Sarcognath); grosor del disparo: Beam > `default_thickness` |
| Discos de aviso en el suelo | `scenes/fx/TelegraphDisc.tscn` > raíz | `start_scale`, `fade_time`; opacidad en `albedo_color` de su material (el color lo pasa quien avisa) |
| Velocidad de los proyectiles enemigos | `scenes/enemies/EnemyBolt.tscn` > raíz | `speed`, `max_distance` (el daño lo pone quien dispara) |
| Nombre de un jefe en pantalla | `<Jefe>.tscn` > raíz | `boss_title` (y la tabla `BESTIARY` de `scripts/ui/meta/collection/collection_entries.gd`) |

### Mythos, el jefe de etapa del Bosque Hueco

Mythos llega en el minuto 11 del Bosque Hueco. Su vida **no es un número
fijo**: se calcula para que la pelea dure lo mismo con una party débil o
fuerte. Lo que se edita son las perillas de ese cálculo (nodo `Scaling`).
Pelea **solo**: al empezar quema a la horda que quedaba y, mientras vive, no
aparece ningún enemigo normal. Tiene **dos fases** (dos vidas): al agotar la
primera renace más grande, de otro color y con ataques más rápidos. Alterna
el vuelo con ratos en tierra (tras una Picada). En vuelo no se queda quieto:
gira rápido alrededor del raider, también mientras lanza varios de sus
ataques, y si el raider se le aleja cruza la arena volando hasta alcanzarlo.
Cada ataque es un nodo de `Moves`, y algunos salen encadenados (combos).
Todo lo de esta tabla está en `scenes/enemies/Mythos.tscn` salvo que diga
otra cosa.

| Qué quieres cambiar | Dónde | Qué propiedad |
| --- | --- | --- |
| Qué jefe llega en el minuto 11 de un mapa | `scenes/world/<Arena>.tscn` > EnemySpawner (grupo «Jefes») | `stage_boss_scene` (vacío = la revancha Ancestral; el Bosque Hueco trae `Mythos.tscn`) |
| Que el jefe de etapa pelee solo, sin horda | `scripts/systems/enemy_spawner.gd` (grupo «Jefes») | `stage_boss_fights_alone` (apagado = la horda sigue llegando durante la pelea) |
| La ola de fuego que quema a la horda al empezar la pelea | Mythos.tscn > Purge («Barrido») | `start_delay`, `wave_speed`, `max_per_frame`, `burst_every`, `burst_color`, `burst_amount` |
| Qué cinemática y qué transformación del mapa trae, y la entrada simple que usa si no hay cinemática | Mythos.tscn > Arrival («Llegada») | `cinematic_scene`, `transformation_scene`, `plain_arrival_seconds`, `plain_arrival_height` |
| Cuánto dura la pelea | Mythos.tscn > Scaling (grupo «Duración objetivo») | `target_fight_seconds` (segundos que debería durar), `min_fight_seconds` (lo mínimo, por fuerte que sea la party), `min_life_seconds` |
| Cuántas fases (vidas) tiene y qué parte de la pelea es cada una | `scripts/enemies/boss/stage_boss_scaling.gd` («Duración objetivo») | `life_shares` (una entrada por fase: hoy dos; agregar una entrada agrega una fase) |
| Vida mínima (1 jugador, primera vuelta, party recién empezada) | Mythos.tscn > Health | `max_hp` (se reparte entre las vidas con `life_shares`) |
| Cuánta vida extra gana contra una party fuerte, y el tope | Mythos.tscn > Scaling («Vida») | `advantage_absorbed` (1 = toda pelea dura lo mismo; 0 = una party fuerte lo mata rápido), `max_hp_over_floor`, `recent_life_weight` |
| Cómo estima el daño de la party cuando llega | Mythos.tscn > Scaling («Estimación de la primera vida») | `dps_window_seconds`, `focus_on_boss`, `extra_player_focus` (cuánto aporta cada jugador extra en co-op), `expected_dps_base`, `expected_dps_growth`, `power_check_low`, `power_check_high` |
| Cuánto más agresivo se pone con más jugadores, más poder o menos vidas | Mythos.tscn > Scaling («Agresividad») | `aggression_per_extra_player`, `aggression_per_power`, `aggression_per_life`, `aggression_cap` |
| Daño extra por el poder de la party | Mythos.tscn > Scaling («Daño») | `damage_per_power`, `damage_power_cap` |
| Que la pelea no se atasque: cuándo Mythos empieza a consumirse solo y cuánto tarda | Mythos.tscn > Scaling («Desgaste») | `burnout_after` (veces el tiempo previsto de la vida; 0 = nunca), `burnout_seconds` |
| Desgaste: cada cuánto pierde vida y el aviso del HUD | Mythos.tscn > Burnout («Desgaste») | `tick_seconds`, `announce_text` (`%s` = nombre del jefe) |
| Cuánto pesa cada «poder» (armas, niveles, evoluciones, tomos, objetos, power-ups, mascota) | `scenes/world/RunSystems.tscn` > PartyPower (grupos «Peso de las armas» y «Peso del resto») | `weapon_weight`, `weapon_level_weight`, `weapon_evolved_weight`, `weapon_ascension_weight`, `tome_weight`, `tome_stack_weight`, `item_weight`, `powerup_weight`, `pet_weight` |
| Cada cuánto sale en el log el poder de la party | RunSystems.tscn > PartyPower («Registro») | `log_interval`, `log_window` |
| Velocidad de vuelo y giro | Mythos.tscn > raíz («Movimiento») | `move_speed`, `turn_speed` |
| En vuelo: a qué distancia y qué tan rápido gira, cuánto se acerca y se aleja, cuánto sube y baja, si retrocede cuando se le acercan y cada cuánto cambia de raider | Mythos.tscn > Flight («En vuelo», «Objetivo») | `air_distance`, `air_band`, `orbit_speed_factor`, `retreat_speed_factor`, `orbit_flip_seconds`, `breath_metres`, `breath_seconds`, `lift_metres`, `lift_seconds`, `focus_seconds` |
| Persecución: desde qué distancia cruza la arena volando hacia un raider que se alejó, hasta dónde, a qué velocidad y cuándo se rinde | Mythos.tscn > Flight («Persecución») | `chase_from`, `chase_until`, `chase_speed`, `chase_lift`, `chase_max_seconds`, `chase_rest_seconds` |
| Caza: el chillido con que deja de girar y se le viene encima al raider, y cada cuánto puede repetirlo | Mythos.tscn > Flight («Caza») | `hunt_sfx` (vacío = ninguno), `hunt_sfx_cooldown` |
| Cómo se ve cuando va hacia el raider, en vuelo de caza y acechando a pie: cuánto baja, cómo lleva el cuerpo, las alas y las patas, cuánto abre el pico y cuánto se lanza con cada golpe de alas | `scripts/enemies/mythos/mythos_poses.gd` (bloque «Edita aquí») | `HUNT_DROP`, `HUNT_PITCH`, `HUNT_WING`, `HUNT_SWEEP`, `HUNT_FLAP`, `HUNT_PERIOD`, `HUNT_LEGS`, `HUNT_SCALE`, `HUNT_JAW`, `HUNT_LUNGE`; `PROWL_CROUCH`, `PROWL_PITCH`, `PROWL_WING`, `PROWL_SWEEP`, `PROWL_FOLD`, `PROWL_JAW` |
| Lo que se siente cuando se acerca: el retumbo de cada pisada, la ráfaga de cada golpe de alas de caza, cuánto se cierra la viñeta de peligro y con qué distancia se apaga todo | Mythos.tscn > Presence («Pisadas», «Aletazos de caza», «Pavor», «Distancia») | `step_sfx`, `step_shake`, `step_shake_seconds`, `step_side`; `beat_sfx`, `beat_shake`, `beat_shake_seconds`, `beat_ember_height`; `hunt_dread`, `prowl_dread`, `dread_from`, `dread_full_within`; `full_within`, `none_beyond`, `far_volume_db` |
| Las brasas que levanta cada pisada y cada golpe de alas de caza | Mythos.tscn > Visual/StepEmbers y Visual/GustEmbers (partículas) | `amount`, `lifetime`, `emission_ring_radius`, `initial_velocity_min/max`, `radial_accel_min/max` |
| Fogonazo (segunda fase: cruza de un tirón al otro lado del raider): cada cuánto, cuánto gira y cuánto tarda | Mythos.tscn > Flight («Fogonazo») | `blink_every` (0 = nunca), `blink_every_at_full_aggression`, `blink_min_degrees`, `blink_max_degrees`, `blink_seconds`, `blink_flash_radius`, `blink_sfx` |
| En tierra: cuánto se acerca, a qué velocidad camina, cuánto se queda y a qué distancia se rinde y despega | Mythos.tscn > Flight («En tierra») | `ground_distance`, `ground_speed_factor`, `ground_seconds`, `ground_seconds_at_full_aggression`, `ground_leash`, `ground_leash_seconds`, `stride_seconds`, `stride_rest` (camina a embestidas: cada cuánto y cuánto afloja entre una y otra) |
| Pausa entre ataques | Mythos.tscn > raíz («Ritmo de ataques») | `attack_pause`, `attack_pause_at_full_aggression`, `ground_pause_factor` |
| Segunda fase: desde qué vida toma su forma renacida, su nombre, el color de su barra y el de sus avisos | Mythos.tscn > Rebirth («Forma renacida») | `ascend_from_life`, `ascended_title`, `bar_fill_color`, `ascended_bar_color`, `ascended_telegraph_color`, `ascended_impact_color` |
| La sorpresa: cuántos segundos parece muerto antes de renacer, y cuánto bajan las llamas del mapa mientras tanto | Mythos.tscn > Rebirth («Muerte fingida»); `hell_transformation.gd` («Frente de fuego») | `fakeout_seconds` (0 = renace enseguida); `falter_heat` |
| Tamaño del fénix en cada fase y cuánto tarda en transformarse | Mythos.tscn > Visual («Tamaño», «Vuelo») | `body_scale`, `ascended_scale`, `ascend_seconds`, `hover_height`, `ascended_hover_height` |
| Colores de la forma renacida | los materiales de plumas y cuerpo (Shader Parameters, grupo «Renacido») | `ascended_root_color`, `ascended_mid_color`, `ascended_tip_color`, `ascended_glow`; en el cuerpo: `ascended_dark_color`, `ascended_hot_color`, `ascended_rim_color`, `ascended_seam_color` (sus valores por defecto están en `assets/shaders/phoenix_plumage.gdshader` y `phoenix_body.gdshader`) |
| Piezas que solo tiene la forma renacida (aureola, corona, plumas largas) | Mythos.tscn > los nodos bajo `AscendedCrown`, `AscendedBack`, `AscendedTail`, `AscendedWingL/R` | sus transforms y materiales |
| Renacer SIN cinemática (si Mythos.tscn > Arrival no trae `cinematic_scene`): segundos en cenizas, estallido y pausa después | Mythos.tscn > Rebirth («Renacer») | `rebirth_seconds`, `rebirth_radius`, `rebirth_damage`, `rebirth_height_window`, `post_rebirth_pause` (esta última vale también con cinemática) |
| Renacer sin cinemática: la columna de fuego y las ondas que salen del estallido | Mythos.tscn > Rebirth («Columna de fuego», «Ondas de fuego») | `pillar_at`, `pillar_radius`; `waves`, `wave_interval`, `wave_speed`, `wave_radius`, `wave_damage` |
| Renacer sin cinemática: cartel, cámara lenta, temblor, destello y sonidos; y los orbes de vida que suelta al caer (siempre) | Mythos.tscn > Rebirth («Puesta en escena», «Orbes de vida») | `banner_text`, `slow_scale`, `slow_seconds`, `shake_strength`, `shake_seconds`, `flash_radius`, `flash_seconds`, `charge_sfx`, `rebirth_sfx`; `ash_orbs`, `ash_orbs_per_extra_player`, `ash_orb_radius` |
| Cinemática del renacer: cuándo sube la columna, cuándo toma su forma, cuándo estalla y cuándo grita | MythosCinematic.tscn > Rebirth («Brasa», «Columna de fuego», «Forma», «Renace», «Grito»). Los tiempos son fracciones del renacer (0-1) y van en ese orden | `glow_from`, `ember_glow`; `pillar_fraction`, `pillar_radius`, `pillar_form_seconds`; `form_fraction`; `burst_fraction`, `burst_flash_radius`, `burst_flash_alpha`, `burst_shake`, `waves`, `wave_speed`, `wave_radius`; `roar_fraction`; y el sonido `*_sfx` de cada momento |
| Cinemática del renacer: los cuatro planos (brasa, marea, columna y héroe) | `scripts/enemies/mythos/mythos_rebirth_camera.gd` (MythosCinematic.tscn > Rebirth/Camera) | `ember_shot_until`, `ember_distance_start`, `ember_distance_end`, `ember_orbit_degrees`; `tide_shot_until`, `tide_distance_end`, `tide_height_end`; `pillar_shot_until`, `pillar_distance`, `pillar_look_end`; `hero_distance_start`, `hero_distance_end`, `hero_side_degrees`, `hero_look_fraction`; `clear_angles`, `corridor_width` |
| Cinemática del renacer: las cenizas que se juntan y las esquirlas del estallido | MythosCinematic.tscn > Rebirth/`Gather`, `Shards` | `amount`, `lifetime`, `scale_amount_min`, `scale_amount_max`, `emission_ring_radius`; el color, en su material (`color`, `ascended_color`) |
| Orbes de vida que suelta al caer en cenizas | Mythos.tscn > Rebirth («Orbes de vida») | `ash_orbs`, `ash_orbs_per_extra_player`, `ash_orb_radius` |
| Plumas ardientes (cuántas, tandas, daño, abanico y cuánto se adelanta al raider) | Mythos.tscn > Moves/FeatherVolley («Plumas») | `bolt_count`, `extra_bolts_at_full_aggression`, `bolt_damage`, `spread_degrees`, `windup`, `waves`, `extra_waves_at_full_aggression`, `wave_delay`, `lead`, `max_lead` |
| Tormenta de plumas (segunda fase): brazos de la espiral, duración, cada cuánto sale una pluma, cuánto giran y a qué altura vuelan | Mythos.tscn > Moves/Storm («Tormenta») | `arms`, `extra_arms_at_full_aggression`, `seconds`, `step_seconds`, `turn_degrees`, `bolt_damage`, `bolt_height`, `windup`, `recover` |
| Molino de tornados (segunda fase): aspas, tornados por aspa, separación, giro, duración y daño | Mythos.tscn > Moves/Mill («Molino») | `blades`, `extra_blades_at_full_aggression`, `per_blade`, `spacing`, `radius`, `warn_seconds`, `spin_speed`, `spin_at_full_aggression`, `life_seconds`, `dps`, `max_live` |
| Velocidad y alcance de una pluma | `scenes/enemies/FireFeather.tscn` > raíz | `speed`, `max_distance` |
| Cómo se ve una pluma ardiente: la cabeza, la cola de llama, el resplandor y la estela de brasas | FireFeather.tscn > `Core`, `Plume`, `Glow` (el material de cada uno, Shader Parameters) y `Trail` (partículas) | `color`, `glow`; `strength`, `flow_speed`, `wobble_amount`, y el largo y ancho de la cola en el `transform` de `Plume`; `strength`, `softness`; `amount`, `lifetime` |
| Picada (aviso, cuánto antes del golpe el disco deja de perseguir al raider, radio, daño, cuánto se remonta, la columna y la onda de fuego del golpe, y cuánto queda quieto al caer: la ventana para pegarle) | Mythos.tscn > Moves/Dive y, en la segunda fase, Moves/DiveChain (la Picada en cadena: `chain` picadas seguidas con `chain_windup` de aviso) («Picada», «Remontada», «Columna de fuego», «Onda de fuego») | `windup`, `lock_seconds`, `radius`, `damage`, `lead_seconds`, `dash_time`, `recover`, `recover_at_full_aggression`, `lock_sfx`; `climb_height`, `climb_speed`, `stoop_distance`, `follow_speed`; `burst_height`, `burst_radius_factor`; `wave_radius`, `wave_speed`, `wave_damage`, `wave_height_window` |
| Aliento de fuego (el chorro que barre la arena: aviso, cuánto y qué tan rápido barre, largo, ancho, la zona pegada a Mythos donde no llega, daño, a qué altura se esquiva y cuántas pasadas) | Mythos.tscn > Moves/Breath y, en la segunda fase, Moves/Scorch (el mismo script con `passes = 2`: vuelve sobre lo barrido) («Aliento») | `windup`, `sweep_degrees`, `sweep_seconds`, `sweep_at_full_aggression`, `reach`, `inner_radius`, `width`, `damage`, `height_window`, `passes`, `turn_seconds`, `recover`, `stoop`, `breath_sfx` |
| Cómo se ve el chorro del Aliento y sus líneas de aviso | `scenes/fx/FireBeam.tscn` > raíz («Chorro», «Aviso»); los colores, en su material (Shader Parameters) | `segments`, `flame_height`, `core_height` (la hilera del medio, que le da cuerpo), `nozzle_distance`, `jet_width` (la llama que baja del pico), `fade_time`, `light_energy`, `light_color`, `reborn_light_color`; `warn_height`, `warn_end_height`, `warn_fade`. Brillo del chorro: `strength` del material de `Wall` (tres hileras sumadas: alto encandila). La llama del pico y las brasas: nodos `Jet` y `Embers` |
| Embestida (primera fase: una sola pasada rasante que cruza por donde va el raider) | Mythos.tscn > Moves/Charge (el mismo script de la Pasada de fuego, con sus valores) | lo de la Pasada de fuego; aquí `burn_seconds` es corto y `second_pass_aggression = 1` (no da segunda pasada) |
| Cerco de brasas (tamaño del anillo, hueco de salida, daño y estallido del centro) | Mythos.tscn > Moves/Ring («Cerco», «Estallido del centro») | `ring_radius`, `zone_radius`, `zone_spacing`, `gap_zones`, `warn_seconds`, `burn_seconds`, `zone_dps`; `blast_delay`, `blast_radius`, `blast_damage`, `burst_height`, `burst_radius_factor` |
| Bolas de fuego (cuántas, cada cuánto, cuánto tardan en caer, radio, daño y el fuego que dejan) | Mythos.tscn > Moves/Fireballs («Bolas de fuego», «Fuego que dejan») | `count`, `extra_at_full_aggression`, `interval`, `flight_seconds`, `blast_radius`, `damage`, `lead`, `scatter`; `zone_radius`, `zone_burn_seconds`, `zone_dps` |
| Diluvio de fuego (segunda fase: bolas que caen del cielo, y la que cae sola de fondo) | Mythos.tscn > Moves/Deluge (el mismo script, con sus valores; «Desde el cielo», «De fondo») | lo de Bolas de fuego más `from_sky`, `sky_height`, `sky_drift`, `area_radius`, `aimed_every`, `passive_from_life`, `passive_interval` |
| Jaula de tornados (cuántos por raider, hueco entre ellos, hasta dónde se cierra, aviso, velocidades, daño y el estallido final) | Mythos.tscn > Moves/Tornados («Jaula», «Estallido») | `count`, `extra_at_full_aggression`, `max_live`, `radius`, `gap`, `closed_radius`, `warn_seconds`, `closing_speed`, `spin_speed`, `speed_at_full_aggression`, `hold_seconds`, `dps`; `blast_radius`, `blast_speed`, `blast_damage`, `blast_height_window`, `blast_band`, `blast_sfx` |
| Ondas de fuego (cuántas, cada cuánto, velocidad, alcance, daño y a qué altura se esquivan) | Mythos.tscn > Moves/Waves y, en la segunda fase, Moves/Tide (la Marea de fuego: `return_waves` ondas que vuelven, tras `return_pause`) («Ondas») | `waves`, `extra_at_full_aggression`, `interval`, `speed`, `max_radius`, `damage`, `height_window`, `band` |
| Bola de fuego: tamaño, arco y estallido | `scenes/fx/Fireball.tscn` > raíz («Vuelo», «Estallido»); colores en el material de `Ball` | `ball_radius`, `arc_per_meter`, `min_arc`, `max_arc`, `glow_scale`, `tail_length`, `tail_width` (la cola de llama que deja atrás), `shake_strength`, `blast_sfx`; `crust_color`, `fire_color`, `core_color`. La cola, el humo y las brasas: nodos `Tail/Flame` (material), `Smoke` y `Trail` (partículas) |
| Estallido de fuego (el de las bolas y el de sus golpes grandes): la bola que se deshace, el anillo de choque, las chispas, la luz y la quemadura que queda | `scenes/fx/FireBlast.tscn` > raíz («Bola», «Anillo de choque», «Chispas», «Luz», «Quemadura»); colores y forma, en los materiales de `Ball`, `Ring` y `Scorch/Cracks` (Shader Parameters); cantidad máxima de chispas, en `Sparks` (`amount`) | `ball_seconds`, `ball_start`, `ball_end`; `ring_seconds`, `ring_reach`; `sparks_per_metre`, `spark_speed_per_metre`; `light_energy`, `light_reach`, `light_seconds`, `light_color`; `scorch_seconds`, `scorch_size`; `core_color`, `fire_color`, `edge_color`, `strength`, `lump_depth`, `front_color`, `wake_color`, `cracks` |
| Aviso en el suelo de los golpes de Mythos (el aro, la rueda de marcas que gira y el relleno de brasas) | `scenes/fx/FireSigil.tscn` > raíz («Animación») y su material (Shader Parameters: «Color», «Renacido», «Forma») | `appear_time`, `fade_time`, `lift`; `ring_color`, `ember_color`, `locked_color` (cuando la Picada se clava), `strength`, `marks`, `spin`, `pulse_slow`, `pulse_fast` |
| Resplandor (halo de luz) de todo el fuego mientras dura el infierno | `scripts/enemies/mythos/hell_sky.gd` (bloque «Edita aquí: resplandor del fuego») | `GLOW_INTENSITY` (0 = sin resplandor), `GLOW_STRENGTH`, `GLOW_BLOOM`, `GLOW_THRESHOLD` |
| Llamas de las ondas, las columnas y el chorro: detalle, brillo del pie, chispas que suben y cómo se funden los tramos | el material de `scenes/fx/FireWave.tscn`, `FireBurst.tscn` y `FireBeam.tscn` (Shader Parameters: «Color», «Llamas», «Chispas») | `strength`, `tongue_scale`, `rise_speed`, `base_heat`, `seam` (no tocar sin cambiar `segment_overlap`), `spark_density`, `spark_size`, `spark_speed` |
| Cuánto brillan las vetas de la lava de una zona de fuego y los tornados | el material de `scenes/fx/FireZone.tscn` y el de `FireTornado.tscn` (Shader Parameters) | `vein_glow`; `strength` (alto encandila de cerca) |
| Tornado: altura, cada cuánto quema, qué tan fácil se lo torea y sus colores | `scenes/fx/FireTornado.tscn` > raíz («Daño», «Persecución», «Aspecto»); colores en el material de `Funnel` | `tick_interval`, `height_window`, `steer_rate`, `retarget_seconds`, `funnel_height`, `funnel_width`, `ground_color`; `base_color`, `mid_color`, `top_color`, `smoke_color`, `bands`, `spin_speed`, `detail` (grano fino de las llamas), `soft_edge` (borde que se deshace), `base_heat` (brillo donde toca el suelo) |
| Onda de fuego: alto de las llamas, tramos y colores | `scenes/fx/FireWave.tscn` > raíz («Aspecto»); colores en el material del tramo de `Wall` | `wall_height`, `segments`, `segment_overlap`, `fade_time`, `wake_distance` y `wake_height` (la estela de llamas bajas que sigue al anillo; 0 = sin estela); `base_color`, `tip_color`, `strength` |
| Garras (zarpazos en tierra: cuántos, aviso, radio, avance, daño) | Mythos.tscn > Moves/Claws («Garras») | `swipes`, `extra_swipes_at_full_aggression`, `windup`, `radius`, `reach`, `lunge`, `damage`, `gap`, `recover` |
| Aletazo (el despegue: aviso, radio, daño, la columna de fuego y la onda que manda) | Mythos.tscn > Moves/Takeoff («Aletazo», «Columna de fuego», «Onda de fuego») | `windup`, `radius`, `damage`; `burst_height`, `burst_radius_factor`; `wave_radius`, `wave_speed`, `wave_damage`, `wave_height_window` |
| La columna de fuego de los golpes grandes (Picada, Aletazo, Cerco de brasas): cómo brota, cuánto dura y su luz | `scenes/fx/FireBurst.tscn` > raíz («Aspecto», «Luz»); los colores de las llamas, en su material (Shader Parameters) | `segments`, `start_radius`, `start_height`, `rise_seconds`, `fade_seconds`, `fade_spread`; `light_energy`, `light_reach`, `light_color`, `reborn_light_color` |
| Pasada de fuego (largo, aviso, velocidad, daño, pared de fuego y segunda pasada) | Mythos.tscn > Moves/Strafe («Pasada», «Pared de fuego», «Segunda pasada») | `length`, `windup`, `run_speed`, `damage`, `angle_jitter_degrees`; `zone_radius`, `spacing`, `burn_seconds`, `zone_dps`; `second_pass_aggression`, `second_pass_degrees` |
| Amanecer (carga, daño, aviso del HUD, círculos a salvo y plumas mientras carga) | Mythos.tscn > Moves/Dawn («Amanecer», «Círculos a salvo», «Plumas mientras carga») | `charge_seconds`, `damage`, `blast_radius`, `burst_radius` (el tamaño de la bola de fuego con que se ve el estallido), `announce_text`; `safe_circles`, `extra_circles_per_player`, `safe_radius`, `safe_min_distance`, `safe_max_distance`; `harass_interval`, `harass_bolts`, `harass_bolt_damage` |
| Círculo a salvo: color (dorado, para que se distinga del fuego azul de la segunda fase), columna de luz y latido | `scenes/fx/SafeCircle.tscn` > raíz («Aspecto») | `color`, `ring_alpha`, `beam_alpha`, `beam_height`, `fade_time`, `pulse_period`, `pulse_depth` |
| Cada cuánto usa un ataque, desde qué vida, a qué distancia, si es de vuelo o de tierra, qué grita al empezarlo y cuánto sigue volando mientras lo hace | Mythos.tscn > Moves/<ataque> («Ritmo») | `cooldown`, `cooldown_at_full_aggression`, `unlock_life`, `retire_life` (desde qué vida deja de usarlo porque otro lo reemplaza), `first_use_fraction`, `min_range`, `max_range`, `stance`, `call_sfx`, `flight_factor` (0 = se queda quieto en el aire; 1 = sigue girando igual de rápido) |
| Combos: qué ataque sale pegado a otro, sin pausa, desde qué vida y con qué probabilidad | Mythos.tscn > Moves/<ataque> («Combo») | `chain_to` (el nombre del nodo del ataque que sigue; vacío = ninguno), `chain_from_life`, `chain_chance` |
| Lo que se siente de sus golpes: temblor de cámara y pausa de impacto de cada tamaño de golpe, y cuánto se apaga con la distancia | Mythos.tscn > Feel («Golpe liviano», «Golpe fuerte», «Cataclismo», «Distancia») | `light_shake`, `light_shake_seconds`; `heavy_shake`, `heavy_shake_seconds`, `heavy_stop_scale`, `heavy_stop_seconds`; `cataclysm_shake`, `cataclysm_shake_seconds`, `cataclysm_stop_scale`, `cataclysm_stop_seconds`; `full_within`, `faint_beyond`, `faint_share` |
| Viñeta de peligro (los bordes de la pantalla se oscurecen mientras carga el Aliento, el Amanecer o cuando el disco de la Picada se clava): color en cada fase, opacidad y latido | Mythos.tscn > Feel («Viñeta de peligro»); la forma, en el material de Feel/Vignette (Shader Parameters) | `dread_color`, `reborn_dread_color`, `dread_opacity`, `dread_pulse`, `dread_pulse_seconds`, `dread_speed`; `inner`, `outer` |
| Cuánto puede crecer la puntería contra un raider que corre más rápido que su velocidad base (el tope `max_lead` de cada ataque es para la velocidad base) | `scripts/enemies/mythos/mythos_bolts.gd` (bloque «Edita aquí») | `LEAD_GROWTH_MAX` |
| Gritos de Mythos: al empezar la pelea, sueltos, al dolerle y al morir | Mythos.tscn > Voice («Gritos») | `arrival_sfx`, `call_sfx`, `call_min_seconds`, `call_max_seconds`, `hurt_sfx`, `hurt_fraction`, `hurt_cooldown`, `death_sfx` |
| Gestos del fénix: grito, chillido, escupir fuego, aletazo, golpe de alas, barrido de un ala, sacudidas, tambaleo, vuelta y ladeo al moverse | Mythos.tscn > Visual/Gestures | `roar_seconds`, `roar_neck_degrees`, `roar_jaw_degrees`, `screech_seconds`, `screech_jaw_degrees`, `spit_seconds`, `flap_wing_degrees`, `slam_seconds`, `slam_wing_degrees`, `slam_drop`, `swipe_seconds`, `swipe_wing_degrees`, `swipe_twist_degrees`, `flinch_pitch_degrees`, `stagger_seconds`, `stagger_roll_degrees`, `shake_seconds`, `spin_seconds`, `bank_per_speed`, `bank_max_degrees` |
| Lo que el fénix hace solo: seguir al raider con la cabeza, cola y patas atrasadas, inclinarse y aletear más rápido al volar, caminar en tierra (qué tan larga es la zancada, cuánto recoge la pata que pasa adelante, cuánto se carga hacia la pata apoyada) y manías | Mythos.tscn > Visual/Motion («Mirada», «Arrastre», «Empuje», «Pasos», «Manías») | `gaze_yaw_max`, `gaze_pitch_max`, `gaze_speed`; `tail_per_turn`, `tail_per_climb`, `legs_per_speed`, `spring_stiffness`, `spring_damping`; `lean_per_speed`, `lean_max`, `ground_lean_share`, `flap_rate_per_speed`; `stride_degrees`, `leg_length` (el largo real de la pata: si cambias el modelo, cámbialo aquí para que los pies no patinen), `step_air_share`, `step_air_height`, `step_tuck`, `step_sway_degrees`, `step_wing_degrees`, `step_min_speed`; `fidget_min_seconds`, `fidget_max_seconds`, `tilt_degrees`, `scan_degrees` |
| Tope de zonas de fuego, distancia a los raiders y aviso mínimo de una zona que nace bajo un raider | Mythos.tscn > Zones | `max_live_zones`, `raider_clearance`, `downed_clearance`, `min_warn_on_raiders` |
| Zona de fuego: cada cuánto quema, encendido, apagado y sonido | `scenes/fx/FireZone.tscn` > raíz | `tick_interval`, `ignite_time`, `fade_time`, `downed_clearance`, `ignite_sfx` |
| Marca de garra que deja cada zarpazo en el suelo: tamaño, inclinación, cuánto dura y sus colores | Mythos.tscn > Moves/Claws («Marca en el suelo»); `scenes/fx/ClawScar.tscn` > raíz («Animación») y su material (Shader Parameters) | `scar_scene` (vacío = sin marca), `scar_length`, `scar_degrees`; `burn_seconds`, `width_ratio`; `spacing`, `gash_width`, `curve`, `ragged`, `strength` |
| Qué sonido usa cada ataque de Mythos | el export `…_sfx` del ataque en Mythos.tscn > Moves/<ataque> (Garras `swipe_sfx`; Picada `lock_sfx`, `fall_sfx`, `impact_sfx`; Aletazo, Cerco y Jaula `blast_sfx`; Pasada y Embestida `pass_sfx`; Ondas `wave_sfx`; Aliento `inhale_sfx`, `breath_sfx`; Amanecer `charge_sfx`, `riser_sfx`, `blast_sfx`; Plumas y Bolas `launch_sfx`); el Fogonazo en Flight (`blink_sfx`) | el id de una fila de `Sfx.SOUND_LIBRARY` |
| Cómo SUENA cada ataque de Mythos (las capas de cada sonido: golpe grave, cuerpo, chasquido, brasas, cola) | `scripts/tools/generate_sfx/sfx_mythos.gd` (una función por sonido; `GLUE_DRIVE` arriba) y los bloques que usa en `sfx_dsp.gd`. Después de cambiar una receta corre `godot --headless --path . -s res://scripts/tools/generate_sfx.gd` | los números de cada capa: duración, frecuencias, cuánto pesa en la mezcla |
| Zona de fuego: colores del aviso y de la lava | FireZone.tscn > Disc > su material (Shader Parameters) | `warn_color`, `fire_color`, `core_color`, `flow_scale`, `flow_speed`, `warn_fill_alpha` |
| Altura de vuelo, poses y aleteo del fénix | Mythos.tscn > Visual (grupos «Vuelo», «Cuerpo», «En tierra», «Amanecer», «Alas», «Cenizas», «Vuelo dirigido») | `hover_height`, `perch_height` (la altura a la que sus patas tocan el suelo: va con el largo de las patas), `bob_amplitude`, `pose_speed`, `fly_pitch_degrees`, `rear_pitch_degrees`, `nova_rise`, `flap_period`, `flap_degrees`, `ashes_scale`, `directed_head_level` |
| Colores de las plumas del fénix | Mythos.tscn > el material de cada pluma bajo Visual/Hover (Shader Parameters): `flight` alas, `covert` cobertoras, `tail` cola, `crest` cresta | `root_color`, `mid_color`, `tip_color`, `mid_point` (cuánto de la pluma queda oscuro antes de la punta encendida), `glow`, `tip_glow`; en la cola, `eye_core_color`, `eye_ring_color`, `eye_size` y `eye_slit` (1 = ojo redondo; más alto = pupila rasgada) |
| Colores del cuerpo del fénix | Mythos.tscn > el material de cada pieza maciza (Shader Parameters): `body`, `neck`, `head`, `limb`, `heart` | `dark_color`, `hot_color`, `rim_color`, `rim_strength`, `glow`, `scale_rows`, `scale_contrast`; las grietas de fuego entre las escamas: `seam_glow` (0 = sin grietas), `seam_color`; el latido: `pulse_amount`, `pulse_speed` |
| Ojos del fénix (color y brillo en cada fase) | Mythos.tscn > el material `eye` de `EyeL` y `EyeR` (Shader Parameters) | `color`, `glow`, `ascended_color` |
| Cuernos, púas del lomo y de los hombros, garras de las alas y de las patas | Mythos.tscn > `HornL/R`, `HornLowL/R` (bajo Head), `Spine1`-`Spine5`, `ShoulderSpikeL/R`, `ShoulderSpikeLowL/R` (bajo Body), `WristClawL/R` (bajo HandL/HandR), `Claw*` (bajo Legs/LegL y Legs/LegR) | el `transform` de cada cono (posición, largo y grosor); su color, en el material `StandardMaterial3D_horn` (`albedo_color`, `emission`) |
| A qué distancia de la cámara el fénix se vuelve transparente | los mismos materiales (Shader Parameters, grupo «Camara») y el del resplandor (`halo`) | `fade_near`, `fade_far`; en `halo`: `distance_fade_min_distance`, `distance_fade_max_distance` |
| Cómo se mecen las plumas | los materiales de las plumas (Shader Parameters, grupo «Movimiento») | `sway_amount`, `sway_speed`, `flutter_amount`, `flutter_speed` |
| La bola de luz del Amanecer y de los fogonazos | Mythos.tscn > Visual/Hover/Nova («Tamaño») y su material (Shader Parameters) | `start_radius`, `full_radius`; `core_color`, `edge_color`, `strength`, `softness` |
| Chispas del fénix: estela, ráfaga y aura de la forma renacida | Mythos.tscn > Visual/Hover/Body/`Trail`, `Burst`, `Aura` | `amount`, `lifetime`, `scale_amount_min`, `scale_amount_max`, `color` |
| Lo que paga al morir y sus colores de aviso | Mythos.tscn > raíz («Pago», «Cofres», «Telegrafía») | `boss_gem_count`, `boss_gem_value`, `health_orb_count`, `base_chest_drops`, `telegraph_color`, `impact_color` |
| Cuánto dura cada cinemática: la llegada y el renacer | `scripts/enemies/mythos/mythos_cinematic.gd` (grupo «Calma») | `calm_seconds` (lo que dura la calma con que empieza la canción de la primera fase), `rebirth_seconds` (la de la canción de la segunda fase) |
| Canciones del jefe (una por fase), su volumen y cuánto tardan en apagarse | `scenes/enemies/mythos/MythosCinematic.tscn` > `Music` (primera fase) y `MusicReborn` (segunda fase) | `song` (arrastra ahí el archivo), `song_volume_db` (0 = el volumen del archivo; las dos de Mythos están en 0, porque sus archivos ya llegan al máximo y más arriba saturan), `fade_seconds`, `handover_seconds` (cuánto tarda en apagarse al cambiar de fase), `resync_threshold` |
| Que una canción empiece antes: cuántos segundos va adelantada a su cinemática (así su parte fuerte cae esos segundos antes de que la cinemática termine) | MythosCinematic.tscn > `MusicReborn` (o `Music`) | `lead_seconds` (0 = lo fuerte cae justo cuando vuelve la pelea). La de la segunda fase trae 1.94: arranca mientras Mythos parece muerto y lo fuerte cae en el estallido con que renace (`burst_fraction` del nodo Rebirth × `rebirth_seconds`). No puede adelantarse más que `fakeout_seconds` sin perder el principio de la canción |
| Saltar la cinemática: botón, segundos y texto | `mythos_cinematic.gd` (grupo «Saltar») | `skip_action_name`, `skip_hold_seconds`, `skip_hint_text` |
| Cámara de la llegada: los cuatro planos (cometa, anillo, cielo y héroe) | `scripts/enemies/mythos/mythos_cinematic_camera.gd` (MythosCinematic.tscn > Camera) | `comet_shot_until`, `comet_ahead`, `comet_outside`, `comet_eye_height`, `comet_fov_start`, `comet_fov_end`; `ring_shot_until`, `ring_back`, `ring_eye_height`, `ring_orbit_degrees`, `ring_follow`, `ring_fov`; `sky_after_impact`, `sky_back`, `sky_side`, `sky_eye_height`, `sky_wall_clearance`, `sky_fov`, `sky_fov_high`, `sky_zoom_height`; `hero_distance_start`, `hero_distance_end`, `hero_height`, `hero_orbit_degrees`, `hero_side_degrees`, `hero_look_fraction`, `camera_fov`, `hero_fov`; `track_speed` |
| Cinemática: lo que hace el fénix y cuándo (cae como un cometa, deja un anillo de fuego, sube, cae a plomo, golpea el suelo, sale de una columna de fuego y grita) | MythosCinematic.tscn > Entrance («Cometa», «Anillo de fuego», «Ascenso y picada», «Impacto», «Columna de fuego», «Grito»). Los tiempos son fracciones de la calma (0-1) y van en ese orden | `comet_until`, `comet_distance`, `comet_height`, `low_height`, `level_fraction`, `trail_back`; `ring_until`, `ring_radius`, `ring_party_margin`, `ring_laps`, `bank_max_degrees`; `apex_fraction`, `apex_height`, `climb_turns`, `plunge_fraction`; `impact_fraction`, `impact_flash_alpha`, `impact_shake`, `waves`, `wave_speed`, `wave_radius`; `pillar_radius`, `rear_fraction`, `rise_fraction`, `reveal_fraction`; `roar_fraction`; y el sonido `*_sfx` de cada momento |
| Cinemática: el anillo de fuego que queda en el suelo | MythosCinematic.tscn > Entrance/Ring («Aspecto»); los colores, en su material (Shader Parameters) | `segments`, `wall_height`, `segment_overlap`, `grow_seconds`, `fade_seconds`; `base_color`, `tip_color`, `strength` |
| Cinemática: la estela del cometa y los escombros del golpe | MythosCinematic.tscn > Entrance/`CometTrail`, `Debris` | `amount`, `lifetime`, `scale_amount_min`, `scale_amount_max`, `color_ramp` (estela), `color` (escombros) |
| Cinemática: de qué lados prueba la cámara para que un árbol no tape al jefe, y el pasillo sin árboles que buscan los planos a ras de suelo | `mythos_cinematic_camera.gd` («Vista despejada») | `clear_angles`, `clear_mask`, `open_spot_reach`, `open_spot_width` |
| Cartel de las cinemáticas: nombre, franjas negras, destellos y sus colores en cada fase | MythosCinematic.tscn > Overlay («Cartel», «Destello»); la letra, en Overlay/Root/…; los textos, en `mythos_cinematic.gd` («Cartel») | `title_fade_seconds`, `title_letter_spacing`, `reborn_title_color`, `reborn_title_outline_color`, `bar_height_ratio`, `bar_seconds`; `flash_color`, `reborn_flash_color`, `flash_seconds`, `end_flash_alpha`; `subtitle_text`, `reborn_subtitle_text`. El nombre aparece con el grito (`roar_fraction` de Entrance y de Rebirth) |
| Cielo, sol, niebla y horizonte del infierno, del infierno de la segunda fase y del bosque carbonizado | `scripts/enemies/mythos/hell_transformation.gd` (grupos «Cielo del infierno», «Cielo renacido», «Cielo carbonizado», «Horizonte») | `hell_*`, `reborn_*`, `charred_*` |
| El color de la segunda fase en todo lo que arde (ataques, chispas, suelo y árboles) | los parámetros `ascended_*` del material de cada efecto (Shader Parameters, grupo «Renacido»): `FireZone.tscn`, `FireWave.tscn`, `FireTornado.tscn`, `Fireball.tscn`, `FireBlast.tscn`, `FireSigil.tscn`, `FireBurst.tscn`, `FireBeam.tscn`, `FireFeather.tscn`, la bola de luz y las chispas de Mythos.tscn, las brasas de `HellTransformation.tscn`, y `forest_ground.gdshader` / `burnt_prop.gdshader` para el mapa. Dos casos aparte: la luz de los estallidos, las columnas y el chorro (`reborn_light_color` en `FireBlast.tscn`, `FireBurst.tscn` y `FireBeam.tscn`) y el resplandor del cuerpo del jefe (Mythos.tscn > Visual/Hover/Body/Halo) | `ascended_*` (por ejemplo `ascended_fire_color`, `ascended_lava_color`); `reborn_light_color`; `ascended_color`; cuánto tarda el cambio: `ascend_tint_seconds` en `hell_transformation.gd` |
| Avance del fuego sobre el mapa y cuánto tarda en enfriarse (el frente arranca cuando Mythos golpea el suelo: `impact_fraction` del nodo Entrance) | `hell_transformation.gd` (grupo «Frente de fuego») | `front_reach`, `front_edge`, `front_curve`, `cool_seconds` |
| Cómo arden árboles, rocas, tocones y mesetas | `scenes/enemies/mythos/HellTransformation.tscn` > raíz > `prop_material` (Shader Parameters); el pasto de las mesetas, en la raíz | `char_color`, `ember_color`, `fire_color`, `fire_core`, `fire_glow`; `grass_flame_amount` |
| Suelo quemado: tierra, grietas de lava y ceniza | `assets/shaders/forest_ground.gdshader` (uniforms «Quemado») | `scorch_dark`, `scorch_light`, `lava_color`, `lava_core`, `ash_color`, `crack_scale`, `crack_width`, `lava_glow` |
| Sonido de fuego, brasas y humo | HellTransformation.tscn > raíz («Sonido», «Partículas»), sus nodos FireBed y Embers, y `HellSmoke.tscn` | `fire_volume_db`, `smolder_volume_db`, `charred_ember_ratio`; `amount`, `lifetime` y el material de cada nube |
| Nombre de Mythos en la Colección | `scripts/ui/meta/collection/collection_entries.gd` > tabla `BESTIARY`, fila `mythos` | `display_name`, `flavor`, `tint` (color de su carta) |

### Langosta Azul, el minijefe del Bosque Hueco

La Langosta Azul llega en el minuto 5 del Bosque Hueco, **sin aviso**: la
pantalla corta de golpe a un primer plano de su cara (la entrada), y cuando su
canción entra de lleno empieza la pelea. **Pelea sola**: desde que llega no
aparece ningún enemigo más y al empezar la pelea se lleva a la horda que
quedaba; mientras vive, el mapa queda azul, como bajo el mar (la marea), y el
Rey Pútrido espera. Su vida **no es un número fijo**: se calcula para que la
pelea dure lo mismo con una party débil o fuerte (nodo `Scaling`), y se
recalcula dos veces durante la pelea con el daño que le hicieron de verdad, sin
que la barra se mueva. Tiene una sola fase y cinco ataques, todos avisados y
todos en cadena: sus avisos se adelantan a quien corre, así que se esquivan
reaccionando cuando el aviso se clava (salto, derrape o cambio de rumbo).
El cuerpo físico (lo que choca y a lo que le apuntan las armas) va en su
**cabeza**, no en la mitad del lomo.

| Qué quieres cambiar | Dónde | Qué propiedad |
| --- | --- | --- |
| En qué minuto llega, o sacarla de la arena | `scenes/world/HollowWoods.tscn` > EnemySpawner (grupo «Jefes») | `mini_boss_spawn_minute`, `mini_boss_scene` (vacío = sin minijefe); el Rey Pútrido llega en `boss_spawn_minute`; si a Mythos (`elder_spawn_minute`) le toca llegar con ella todavía en la arena, la espera |
| Que pelee sola o en medio de la horda | `scenes/world/HollowWoods.tscn` > EnemySpawner (grupo «Jefes») | `mini_boss_fights_alone` (apagado = la horda sigue llegando y nadie la barre); el respiro tras su muerte es `boss_relief_duration` |
| El barrido de la horda al empezar la pelea: salpicones, anillo y sonido | `scripts/enemies/blue_lobster/lobster_purge.gd` | `max_bursts`, `burst_color`, `burst_amount`, `ring_radius`, `ring_speed`, `wave_sfx` |
| Su nombre, colores de sus avisos y de su barra | `scenes/enemies/BlueLobster.tscn` > raíz («Jefe», «Telegrafía») y `scripts/enemies/blue_lobster.gd` («Aspecto») | `boss_title`, `telegraph_color`, `impact_color`; `bar_fill_color`, `burst_color` |
| Su nombre en la Colección | `scripts/ui/meta/collection/collection_entries.gd` > tabla `BESTIARY`, fila `blue_lobster` | `display_name` (igual a `boss_title`), `flavor`, `tint` (color de su carta) |
| Cuánto dura la pelea | `BlueLobster.tscn` > nodo `Scaling` | `target_fight_seconds` (su vida se recalcula para durar esto con el daño real de la party), `min_fight_seconds`, `focus_on_boss` (la estimación del principio), `advantage_absorbed` (parte de la ventaja de daño de la party que se vuelve vida: 1 = dura lo mismo con cualquier build; más bajo = una party fuerte la mata antes); `life_shares` queda en `[1.0]` |
| Cada cuánto y con qué cuidado recalcula su vida con el daño real | `scripts/enemies/blue_lobster/lobster_life.gd` («Recálculo») | `replan_seconds`, `trust_seconds`, `recent_seconds`, `recent_weight`, `max_drop_per_replan`, `stop_with_seconds_left`, `stop_with_bar_left`, `log_change` |
| Su vida mínima (el PISO del cálculo) | `BlueLobster.tscn` > nodo `Health` | `max_hp` |
| Cuándo empieza a desgastarse sola si la pelea se alarga, y su aviso | `BlueLobster.tscn` > nodos `Scaling` y `Burnout` | `burnout_after`, `burnout_seconds`; `announce_text` |
| Daño extra y agresividad por poder de la party y por jugador | `BlueLobster.tscn` > nodo `Scaling` («Agresividad», «Daño») | `aggression_per_extra_player`, `aggression_per_power`, `damage_per_power`, `damage_power_cap` |
| Cada cuánto ataca (el respiro entre un ataque y otro) | `scripts/enemies/blue_lobster.gd` (grupo «Ritmo de la pelea») | `first_attack_delay`, `attack_pause`, `attack_pause_at_full_aggression` |
| Espera de cada ataque, a qué distancia lo usa y su sonido de aviso | `BlueLobster.tscn` > `Moves` > cada ataque (grupo «Ritmo») | `cooldown`, `cooldown_at_full_aggression`, `first_use_fraction`, `min_range`, `max_range`, `call_sfx` |
| Tenazas: daño, avisos, alcance, cuántos pinzazos y el remate de las dos pinzas | `scripts/enemies/blue_lobster/lobster_pincers.gd` («Tenazas», «Remate») | `damage`, `windup`, `windup_jitter` (ritmo irregular), `lock_seconds`, `radius`, `reach`, `lunge`, `snaps`, `gap`, `height_window`, `recover`; `slam` (apagado = sin remate), `slam_damage`, `slam_windup`, `slam_lock_seconds`, `slam_radius`, `slam_spread` |
| Embestida: daño, aviso, carril, velocidad y cuántas pasadas | `scripts/enemies/blue_lobster/lobster_charge.gd` | `damage`, `passes`, `windup`, `repass_windup`, `lock_seconds`, `length`, `width`, `overshoot`, `backstep`, `run_speed`, `turn_degrees_per_second`, `skid_seconds`, `recover` |
| Salto aplastante: daño, tiempo en el aire, disco, sus ondas de choque y la réplica | `scripts/enemies/blue_lobster/lobster_leap.gd` («Salto», «Onda de choque») | `damage`, `crouch_seconds`, `air_seconds`, `lock_seconds`, `leap_height`, `radius`, `stand_off`, `recover`; `rings` (1 = sin réplica), `ring_gap_seconds`, `ring_damage`, `ring_radius`, `ring_speed`, `ring_height_window`, `aftershock_cue_seconds` |
| Coletazo: daño, aviso, radio, cuántos giros y la ola que sale de cada uno | `scripts/enemies/blue_lobster/lobster_tail_spin.gd` («Coletazo», «Ola del coletazo») | `damage`, `windup`, `respin_windup`, `radius`, `spin_seconds`, `height_window` (más bajo = más fácil de saltar), `spins`, `recover`; `wave_damage`, `wave_radius`, `wave_speed`, `wave_scene` (vacío = sin ola) |
| Emboscada: daño, velocidad bajo tierra, aviso, cuántas salidas y la última, más grande | `scripts/enemies/blue_lobster/lobster_burrow.gd` («Emboscada», «Última salida») | `damage`, `dig_seconds`, `redig_seconds`, `tunnel_speed`, `max_tunnel_seconds`, `lock_seconds`, `radius`, `stand_off`, `eruptions`, `recover`; `final_damage`, `final_radius`, `final_lock_seconds`, `final_pop_height` |
| Que sus ataques sean más fáciles o más difíciles de esquivar | el script de cada ataque | `lock_seconds` (la ventana para salir desde que el aviso se clava: más = más fácil; por debajo de unos 0.3 s ya no se puede reaccionar), `lead_seconds` y `max_lead` (cuánto se adelanta a quien corre; 0 = apunta a donde está), `radius` / `width`, `height_window` |
| Cuánto crecen sus ataques contra un raider más rápido | `scripts/enemies/blue_lobster/lobster_reach.gd` (nodo `Reach` de `BlueLobster.tscn`) | `speed_follow` (0 = no crecen; 1 = crecen como su velocidad), `max_growth`. Los radios, alcances y velocidades de cada ataque son los de un raider sin mejoras |
| A qué distancia ronda, cuándo corre a alcanzarte y cada cuánto cambia de raider en co-op | `scripts/enemies/blue_lobster/lobster_stalk.gd` («Ronda», «Persecución», «Objetivo») | `orbit_distance`, `orbit_band`, `orbit_speed_factor`; `chase_distance`, `chase_speed_factor`; `focus_seconds` |
| Su velocidad al caminar y al girar | `BlueLobster.tscn` > raíz («Movimiento») | `move_speed`, `turn_speed` |
| Qué hace cuando queda trabada contra una roca | `scripts/enemies/blue_lobster.gd` (grupo «Atasco») | `stuck_seconds`, `escape_moves` |
| Temblor, pausa de impacto y viñeta de peligro de sus golpes | `scripts/enemies/blue_lobster/lobster_feel.gd` y el material de `BlueLobster.tscn` > `Feel/Vignette` | `light_shake`, `heavy_shake`, `heavy_stop_seconds`, `crushing_shake`, `crushing_stop_seconds`, `crushing_flash` (el golpe más grande: caída del Salto, remate, última salida; el último es su fogonazo de pantalla, 0 = sin fogonazo), `dread_opacity`; `tint`, `ripples` |
| Los efectos de cada golpe: tamaño de los chorros de agua, salpicones, medialunas, la corona de los golpes grandes y las estelas | `scripts/enemies/blue_lobster/lobster_fx.gd` (un grupo por ataque: «Tenazas», «Salto», «Corona», «Embestida», «Coletazo», «Emboscada»; «Colores») | `snap_burst`, `slam_burst`, `landing_burst`, `aftershock_burst`, `crown_count`, `crown_burst`, `charge_wake_spacing`, `charge_wake_burst`, `sweep_arcs`, `eruption_burst`, `final_eruption_burst`… (los `*_burst` son radio y alto en metros); `ripple_color`, `arc_color`; con una escena vacía en «Escenas» ese efecto no sale |
| Aspecto del chorro de agua y de la onda del suelo | `scenes/fx/WaterBurst.tscn` (nodos `Column`, `Light`, `Drops`) y `ImpactRipple.tscn`, con `scripts/fx/water_burst.gd` e `impact_ripple.gd` | `rise_seconds`, `fade_seconds`, `fade_spread`, `light_energy`, `light_min_radius`; Shader Parameters del chorro: `foam_color`, `water_color`, `strength`, `rise_speed`, `fade_near`; de la onda: `rings`, `ring_width`, `spokes`, `strength`; `seconds` |
| Sus sonidos (rugido, tableteo, siseo, muerte) | `scripts/enemies/blue_lobster/lobster_voice.gd`; las recetas en `scripts/tools/generate_sfx.gd` (`_gen_lobster_*`) | `roar_sfx`, `call_sfx`, `hurt_sfx`, `death_sfx`, `call_min_seconds`, `hurt_fraction` |
| Su tamaño y cuánto va corrido el modelo detrás del cuerpo físico | `scripts/enemies/blue_lobster/lobster_rig.gd` (grupo «Tamaño») | `body_scale`, `body_setback` |
| Sus poses (ronda, cada ataque, muerte) | `scripts/enemies/blue_lobster/lobster_poses.gd`, tabla `TABLE` | una fila por pose: `height`, `pitch`, `arms`, `tail_curl`, `fan`… (la cabecera explica cada campo) |
| Gestos, cómo camina, respira y mueve ojos y antenas | `lobster_gestures.gd`, `lobster_gait.gd`, `lobster_motion.gd`, `lobster_head.gd` (en `scripts/enemies/blue_lobster/`) | los exports de cada uno, con su unidad en el tooltip |
| Colores y brillo del caparazón, y a qué distancia se deshace frente a la cámara | `BlueLobster.tscn` > material del caparazón (Shader Parameters) | `deep_color`, `bright_color`, `pale_color`, `glow`, `rim_strength`, `fade_near`, `fade_far` |
| El color con que se enciende mientras carga un ataque | el mismo material (grupo «Furia») | `anger_color` (cálido, para que se despegue del azul de la marea), `anger_glow` |
| Cómo muere | `scripts/enemies/blue_lobster.gd` (grupo «Muerte») | `death_seconds`, `death_fade_seconds` |
| Aspecto de la onda de choque, del carril de la Embestida y del salpicón de arena | `scenes/fx/ShockRing.tscn`, `TelegraphLane.tscn`, `SplashBurst.tscn` y sus scripts en `scripts/fx/` | `crest_height`, `segments`, `danger_color` (el color de la onda que daña; Shader Parameters del nodo `Crest`); `segment_length`, `empty_alpha`, `full_alpha`; los valores de las partículas |
| **La canción** | `scenes/enemies/blue_lobster/LobsterEntrance.tscn` > nodo `Music` | `song` (vacío = entrada y pelea sin música), `song_volume_db`, `fade_seconds` |
| Cuánto dura la entrada (lo que dura la introducción de la canción) | `scripts/enemies/blue_lobster/lobster_entrance.gd` (grupo «Entrada») | `intro_seconds`; `warmup_frames` (frames de espera antes de que arranquen canción y reloj: si los cortes caen después de los golpes de la canción, súbelo); `catch_up_after` (cuánto puede adelantarse la canción antes de que la entrada salte a alcanzarla tras un tirón; 0 = es la canción la que se reacomoda) |
| Los planos de la entrada: cuándo entra cada uno, desde dónde filma y qué hace la langosta | `LobsterEntrance.tscn` > `Camera` > `Shot1`…`Shot8` | `at_seconds` (un golpe de la canción), `focus`, `distance`, `around_degrees`, `height`, `fov`, `push_in`, `isolated`, `hit_shake`, `pose`, `gesture`, `sfx` |
| Con qué plano aparece el cartel | `lobster_entrance.gd` («Entrada») | `title_shot` (el cartel lleva solo el nombre: el `boss_title` de `BlueLobster.tscn`) |
| Aspecto del cartel y de los destellos | `scripts/enemies/blue_lobster/lobster_entrance_overlay.gd` y los nodos `Overlay/Root/Card` de la escena | `card_color`, `card_tilt_degrees`, `card_pop_seconds`, `cut_flash_alpha`, `end_flash_alpha`, `skip_hint_delay` |
| Saltar la entrada | `lobster_entrance.gd` (grupo «Saltar») | `skip_action_name`, `skip_hold_seconds`, `skip_hint_text` |
| El fondo oscuro y la luz de los primeros planos | `LobsterEntrance.tscn` > `Camera/Backdrop` (Shader Parameters) y `Camera/Light` | `core_color`, `edge_color`, `ray_strength`; `light_color`, `light_energy` |
| El sonido del susto cuando no hay canción | `lobster_entrance.gd` (grupo «Entrada») | `scare_sfx` |
| Quitar la entrada (llega como un jefe común) | `scripts/enemies/blue_lobster/lobster_arrival.gd` | `entrance_scene` (vacío = llegada simple: `plain_seconds`, `plain_ring_radius`, `plain_roar_sfx`) |
| Qué tan lejos de la línea de vista se oculta la decoración que la taparía en la entrada | `scripts/enemies/blue_lobster/lobster_entrance_camera.gd` (grupo «Vista libre») | `sight_clearance`, `hide_radius_limit` |
| **La marea**: quitarla, o cuánto tarda en subir y en bajar | `lobster_arrival.gd` («Marea») y `scripts/enemies/blue_lobster/lobster_tide.gd` («Ritmo») | `tide_scene` (vacío = el mapa no cambia); `rise_seconds`, `ebb_seconds` |
| El tono azul del mapa durante la pelea | `lobster_tide.gd` (grupo «Cielo de la marea») | `sky_top`, `sky_horizon`, `sun_color`, `sun_energy`, `ambient_color`, `ambient_energy`, `fog_color`, `fog_density`, `backdrop_ground`, `backdrop_hills` |
| Los corales que brotan: cuántos, dónde y de qué tamaño | `lobster_tide.gd` (grupo «Corales») | `coral_sites`, `coral_reach`, `coral_clearance`, `raider_clearance`, `branches_min`/`branches_max`, `branch_height_min`/`branch_height_max`, `bulb_radius_min`/`bulb_radius_max` |
| Color y brillo de los corales, a qué distancia de la cámara se deshacen, y los reflejos de agua del suelo | `scenes/enemies/blue_lobster/LobsterTide.tscn` > materiales de `Branches` y de `Caustics` (Shader Parameters) | corales: `deep_color`, `bright_color`, `tip_color`, `glow`, `pulse`, `rim_strength`, `sway`, `fade_near`, `fade_far`; reflejos: `tint`, `strength`, `scale`, `speed`, `sharpness`, `fade_far` |
| Las burbujas alrededor de cada raider | `LobsterTide.tscn` > nodo `Bubbles`; `lobster_tide.gd` («Burbujas») | `amount`, `lifetime`, el tamaño de la caja de emisión; `bubble_height` |

## Aparición de enemigos

El nodo `EnemySpawner` vive dentro de cada arena (`scenes/world/<Arena>.tscn`).
Lo que no cambia por mapa se edita en `scripts/systems/enemy_spawner.gd`.
La lógica vive en ayudantes de `scripts/systems/spawner/` (`SpawnScaling`, `SpawnPoints`, `HordeSchedule`, `BossSchedule`…), pero todos leen los exports del spawner: los valores se cambian en `enemy_spawner.gd` o en el nodo de la arena.

| Qué quieres cambiar | Dónde | Qué propiedad |
| --- | --- | --- |
| Cuántos enemigos salen (flujo y hordas a la vez) | `enemy_spawner.gd` (grupo «Ritmo y dificultad») | `spawn_count_multiplier` |
| Ritmo del flujo de enemigos | `enemy_spawner.gd` («Ritmo y dificultad») | `start_interval`, `min_interval`, `interval_shrink_per_minute`, `base_count_per_tick`, `extra_count_per_minute` |
| Máximo de enemigos vivos | `enemy_spawner.gd` (grupo «Cupo de enemigos») | `max_active`, `horde_overflow`, `pressure_overflow` (si subes el multiplicador, súbelos juntos) |
| Hordas en co-op | `enemy_spawner.gd` (grupo «Co-op») | `coop_horde_per_extra_player` |
| Minuto del jefe, jefe ancestral (o jefe de etapa) y su aviso | `scenes/world/<Arena>.tscn` > EnemySpawner (grupo «Jefes») | `boss_spawn_minute`, `elder_spawn_minute`, `boss_warning_text`, `elder_title`, `stage_boss_scene` |
| Minijefe de una arena (el que llega antes del jefe del bioma) y su minuto | `scenes/world/<Arena>.tscn` > EnemySpawner (grupo «Jefes») | `mini_boss_scene` (vacío = sin minijefe), `mini_boss_spawn_minute`; solo el Bosque Hueco lo usa (la Langosta Azul) |
| Qué enemigos salen en cada minuto | `enemy_spawner.gd`, tablas al comienzo | `FOREST_PHASES`, `DUNES_PHASES`, `MARSH_PHASES` (un bioma nuevo va al FINAL del enum `PhasePreset`) |
| Probabilidad de que caiga un power-up | `enemy_spawner.gd` (grupo «Power-ups») | `base_powerup_drop_chance`, `shiny_powerup_drop_scale` |
| Textos de «¡TIEMPO DETENIDO!» | `enemy_spawner.gd` (grupo «Tiempo detenido») | `time_stop_start_text`, `time_stop_end_text` |
| Altura a la que nace un enemigo sobre el suelo e intentos para hallar un punto libre | `scripts/systems/spawner/spawn_points.gd`, constantes al comienzo | `SPAWN_GROUND_OFFSET`, `RING_ATTEMPTS` |
| Cuánto se desordena el cerco de una oleada de horda | `scripts/systems/spawner/horde_schedule.gd`, constante al comienzo | `BURST_ANGLE_JITTER` (radianes) |

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
| Cómo sigue y se ve toda mascota (velocidad, distancia al raider, brillo, ojos, vaivén) | `scripts/systems/pet.gd` (bloque «Edita aquí») | `FOLLOW_SPEED`, `TURN_SPEED`, `FOLLOW_OFFSET`, `BODY_GLOW`, `EYE_COLOR`, `HOVER_BOB_HEIGHT`, `HOVER_BOB_SPEED` |
| Misiones (texto, meta, premio) | `scripts/systems/catalogs/quest_catalog.gd` > `QUEST_LIBRARY` | `display_name`, `description`, `target`, `reward` |
| Reliquias de la Armería | `scripts/systems/catalogs/relic_catalog.gd` > `RELIC_LIBRARY` | `display_name`, `amount`, `max_ranks`, `base_cost`, `cost_growth` |
| Orden y textos de los mapas | `scripts/systems/catalogs/map_catalog.gd` > `MAP_LIBRARY` | orden de las filas, `display_name`, `blurb` |

## Objetos, power-ups, sonido y sensaciones

| Qué quieres cambiar | Dónde | Qué propiedad |
| --- | --- | --- |
| Números de un objeto (imán, veneno, titán, arañas, aura sayayin, zenkai…) | `scripts/systems/catalogs/item_catalog.gd` > su fila en `ITEM_LIBRARY` | sus campos numéricos (la descripción se arma sola con ellos) |
| Aspecto del aura sayayin (color, opacidad, partículas) | `scripts/systems/catalogs/item_catalog.gd` > fila `saiyan_blood` | `aura_color`, `aura_alpha`, `aura_burst` |
| Duración, peso, color o texto de un power-up | `scripts/systems/catalogs/powerup_catalog.gd` > su fila en `POWERUP_LIBRARY` | `duration`, `weight`, `color`, `display_name` |
| Fiebre del oro, reflejo, vida por baja del vampiro | `powerup_catalog.gd` > fila gold / reflect / vampire | `points_multiplier`, `reflect_fraction`, `max_hp_per_kill` (si cambias el número, ajusta el texto) |
| Textos «¡Aura sayayin!» y «¡Zenkai!» | Player.tscn > ItemBag (grupo «Textos») | `saiyan_aura_text`, `zenkai_text` |
| Texto bajo el nombre en el aviso de un power-up («… (10 s)») | Player.tscn > PowerUps (grupo «Textos») | `toast_template` (%s = descripción, %d = segundos) |
| Power-up en el suelo (tamaño, brillo, luz, duración, desvanecimiento, arcoíris de la estrella) | `scenes/systems/PowerUpPickup.tscn` > sus nodos y la raíz | la malla de `Gem`, `light_energy`; `lifetime`, `fade_time`, `spin_speed`, `star_hue_hz` en la raíz |
| Ronda de la estrella (velocidad, saltos, a qué distancia mira un muro, cuánto desnivel la hace rebotar al pie de un acantilado) | `scripts/systems/pickups/powerup_pickup.gd` → grupo «Ronda de la estrella» | `roam_speed`, `hop_height`, `hop_hz`, `roam_probe`, `roam_max_rise` |
| Orbe de vida (imán, curación, duración) | `scenes/systems/HealthOrb.tscn` > HealthOrb | `magnet_radius`, `heal_fraction`, `lifetime` |
| Sacudida de cámara | `scenes/systems/Juice.tscn` > Juice (grupo «Sacudida de cámara») | `kill_shake_*`, `hurt_shake_*`, `boss_death_shake_*`, `crit_shake_*` |
| Cámara lenta al crítico o al matar un jefe | Juice.tscn > Juice («Hit-stop») | `crit_stop_scale`, `crit_stop_duration`, `boss_death_stop_*` |
| Destello blanco al golpear | Juice.tscn > Juice («Destello de golpe») | `flash_duration`, `flash_color` |
| Viñeta al recibir daño (color, fuerza, cuánto dura) | Juice.tscn > Juice («Viñeta de daño») | `vignette_color`, `vignette_strength`, `vignette_hold_time`, `vignette_fade_time` |
| Anillo al subir de nivel (color, duración, tamaño, altura) | Juice.tscn > Juice («Anillo de subida de nivel») | `level_pulse_color`, `level_pulse_duration`, `level_ring_alpha`, `level_ring_inner_radius`, `level_ring_outer_radius`, `level_ring_height`, `level_ring_start_scale`, `level_ring_end_scale` |
| Volumen, tope por segundo o variación de un sonido | `scripts/systems/catalogs/sound_library.gd` > su fila en `ROWS` (`Sfx.SOUND_LIBRARY`) | `volume_db`, `rate_limit`, `jitter`, `loop` |
| Voces simultáneas de sonido | `scenes/systems/Sfx.tscn` > Sfx | `pool_size`, `default_pitch_jitter` |
| Volumen de la música antes de que el jugador mueva el slider | `scripts/systems/autoloads/save_data.gd` (constantes al comienzo) | `DEFAULT_MUSIC_VOLUME` (0-100; el slider «Volumen de música» de Ajustes lo guarda) |
| Texto de la fila de música en Ajustes | `scenes/ui/SettingsPanel.tscn` > Center/Panel/VBox/MusicRow/MusicLabel | `text` |
| Precio de los cofres y cuánto suben | `scripts/systems/autoloads/run_state.gd` (bloque «Edita aquí») | `CHEST_BASE_PRICES`, `CHEST_PRICE_GROWTH` |
| Curva de experiencia por nivel | `scripts/systems/autoloads/run_state.gd` (bloque «Edita aquí») | `XP_BASE`, `XP_PER_LEVEL`, `XP_PER_LEVEL_SQUARED` |

## Eventos del mapa, clima y portales

| Qué quieres cambiar | Dónde | Qué propiedad |
| --- | --- | --- |
| Cuándo sale el primer evento y la pausa entre eventos | `scenes/world/RunSystems.tscn` > WorldDirector (grupo «Eventos») | `first_event_at`, `event_gap_min`, `event_gap_max`, `event_gap_floor` |
| Qué tan seguido sale cada evento, su aviso y su baliza | `scripts/world/run/world_director.gd` > su fila en `EVENT_LIBRARY` | `weight`, `announce`, `beacon_color` (quítalo y no hay baliza; el vendedor usa el `color` de su fila en `VENDOR_LIBRARY` de `vendor.gd`), `beacon_time` (sin él, hasta que se use) |
| Gemas de la grieta de esencia (cuántas, XP, qué tan repartidas) | RunSystems.tscn > WorldDirector (grupo «Eventos») | `rift_gem_count`, `rift_gem_value`, `rift_gem_min_spread`, `rift_gem_max_spread` |
| Máximo de vendedores o manantiales a la vez | `world_director.gd` > fila `vendor` / `spring` | `cap` |
| Tope y ritmo de los altares | RunSystems.tscn > WorldDirector (grupo «Altares») | `altar_cap_base`, `altar_cap_minutes` |
| Aspecto del pilar de baliza | `scenes/world/director/Beacon.tscn` > Pillar (su malla y su material) / Light / raíz | `height` y radios de la malla (el pilar se apoya solo en el suelo), la opacidad (alfa de `albedo_color` del material de Pillar), `light_energy`, `pulse_half_time`; el color sale de la fila del evento (`beacon_color`), no del material |
| Cofre de suministros (rareza mínima, suerte) | `scenes/world/director/SupplyChest.tscn` > SupplyChest | `min_rarity`, `luck_bonus` |
| Cuánto tarda en encogerse el cofre de suministros que nadie abrió | `scenes/world/director/SupplyChest.tscn` > SupplyChest (grupo «Cofre perdido») | `lost_sink_duration`, `lost_sink_depth` |
| Aviso, tinte del cielo, nombre en el HUD y partículas de un clima | `scripts/world/run/director/weather_catalog.gd` > su fila en `WEATHER_CATALOG` | `announce`, `sun_color`, `sun_energy`, `ambient_color`, `fx_color`, `display_name` |
| Peso, duración base y si el altar de evento puede invocar un clima | `scripts/world/run/director/weather_catalog.gd` > su fila en `WEATHER_CATALOG` | `weight`, `duration`, `altar_ok` |
| De dónde viene el tsunami (texto del aviso) | `scripts/world/run/director/weather_catalog.gd` | `COMPASS_WORDS` |
| Segundos del paso al tinte del cielo y de la vuelta | `scripts/world/run/director/sky_tint.gd` | `TINT_SECONDS`, `RESTORE_SECONDS` |
| Duración de un clima y probabilidades de desastre, lluvia y luna | RunSystems.tscn > WorldDirector > Weather | `weather_duration_overrides`, `disaster_chance`, `rain_chance`, `sky_event_chance` |
| Ácido, meteoritos y tsunami (daño, radio, frecuencia) | RunSystems.tscn > WorldDirector > Weather (grupos por clima) | `acid_pool_*`, `meteor_*`, `tsunami_*` |
| Partículas de la lluvia de enemigos, del terremoto y de los meteoritos | RunSystems.tscn > WorldDirector > Weather (grupos «Lluvia de enemigos», «Terremoto», «Meteoritos») | `enemy_rain_burst_height`, `enemy_rain_burst_count`, `earthquake_dust_count`, `meteor_impact_burst_count`; el color sale de `fx_color` / `impact_color` de su fila en `WEATHER_CATALOG` |
| Bonos de la luna llena y de la lluvia dorada | RunSystems.tscn > WorldDirector > Weather | `full_moon_xp_bonus`, `full_moon_luck_bonus`, `golden_points_multiplier` |
| Portales, ruletas, cofres y cajas al inicio de cada etapa | RunSystems.tscn > WorldDirector > StageFixtures | `portal_count`, `roulette_count`, `extra_start_chests_min/max`, `start_pet_box_chance` |
| Colores, recarga y avisos de los pares de portales | `scenes/world/director/PortalShrine.tscn` > PortalShrine | `pair_colors`, `cooldown`, `prompt_text`, `recharging_prompt` |
| Color y tamaño del portal de salida | `scenes/world/director/ExitPortal.tscn` > ExitPortal | `portal_color`, `ring_radius` |
| Aspecto de los portales (anillo, pilar, latido, luz y círculo de piedras: grupo «Marco de piedra», `frame_stones`, `frame_gap`, `frame_height_min/max`, `frame_width`, `frame_lintels`, colores) | `scenes/world/director/ExitPortal.tscn` > Visual; los pares de portales usan los valores de `scripts/world/run/director/portal_visual.gd` (`PortalShrine.tscn` > Visual no guarda ninguno) | `ring_*`, `pillar_*`, `idle_pulse_*`, `recharge_min_width` (solo pares), `light_*`; el color es `portal_color` / `pair_colors` |

## Altares, cofres y secretos del mapa

Todos los interactuables comparten la base `scripts/world/interactables/interactable.gd`:
lo que cambies ahí vale para todos los que no tengan su propio valor en la escena.

| Qué quieres cambiar | Dónde | Qué propiedad |
| --- | --- | --- |
| Tamaño y color del aviso «[E] …» | `interactable.gd` (grupo «Aviso flotante») | `prompt_font_size`, `prompt_outline_size`, `prompt_color` |
| Altura del aviso «[E] …» de un interactuable | la escena del interactuable > raíz (grupo «Aviso flotante») | `prompt_height` (cada escena guarda el suyo) |
| Cuánto tarda en hundirse algo gastado | la escena del interactuable > raíz (grupo «Gastado») | `sink_duration`, `sink_depth`, `spent_color` |
| Brillo de los cofres según la rareza | `scenes/world/chests/Chest.tscn` > Chest (grupo «Brillo por rareza») | `glow_energy_by_rarity`, `free_glow_energy`, `free_tint` |
| Salto de apertura y textos del cofre | `Chest.tscn` > Chest (grupos «Apertura», «Textos») | `open_duration`, `open_hop_height`, `paid_prompt`, `opened_announce` |
| Aspecto de los altares (zócalo, columna, cristal, obelisco, garras, monedas, rueda, fuente, círculo de piedras) | `scenes/world/shrines/<Altar>.tscn` > Visual > Look (grupos de cada uno: «Zócalo y columna», «Cristal», «Círculo de piedras», «Obelisco», «Medidas», «Colores») | medidas y colores de cada pieza; la colisión es el nodo `Body` de la escena (cambiarla si cambia el ancho de la base) |
| Color del anillo de un altar de carga o del altar demoníaco | `scenes/world/shrines/ChargeShrine.tscn` / `CurseShrine.tscn` > raíz (grupo «Anillo») | `accent_color`; el color de su baliza es aparte: `beacon_color` de la fila `charge_altar` / `demonic_altar` en `EVENT_LIBRARY` (`world_director.gd`) |
| Tiempo de carga y tamaño del don | `ChargeShrine.tscn` / `CurseShrine.tscn` > raíz (grupo «Carga») | `channel_time`, `boon_scale` |
| Costo de dificultad de los pactos | `CurseShrine.tscn` > CurseShrine (grupo «Pactos») | `difficulty_scale` (1 = lo que dice `PACT_LIBRARY` en `curse_shrine.gd`) |
| Premios y aspecto del bloque de la suerte | `scenes/world/chests/LuckyBlock.tscn` > LuckyBlock | `points_reward`, `gem_count`, `gem_min_spread`/`gem_spread`, `explosion_radius`, `explosion_burst_count`, `explosion_shake`, `block_color` |
| Caja de mascota | `scenes/world/PetBox.tscn` > PetBox | `paw_color`, grupo «Textos» |
| Precio y textos del manantial | `scenes/world/shrines/SpringShrine.tscn` > SpringShrine | `price`, `price_prompt` |
| Peaje y premio del altar de la codicia | `scenes/world/shrines/GreedShrine.tscn` > GreedShrine | `hp_cost_fraction`, `gem_chance`, `card_chance`, `gem_count`, `gem_ring_min_radius`/`gem_ring_max_radius` |
| Altar de eventos | `scenes/world/shrines/EventAltar.tscn` > EventAltar | `glass_color`, `busy_prompt` |
| Minijefe secreto y sus frases | `scenes/world/secrets/HummingSkull.tscn` / `OddStump.tscn` > raíz | `miniboss_scene`, `spawn_offset` (el minijefe aparece en el suelo libre más cercano a ese punto donde cabe su cuerpo), `awaken_text`, `held_text` (aviso si lo despiertan mientras el jefe de etapa pelea solo) |

## Terreno y reparto del mapa

Cada arena es una escena: `scenes/world/HollowWoods.tscn` (Bosque Hueco),
`AshDunes.tscn` (Dunas de Ceniza) y `Gloomfen.tscn` (Ciénaga Lóbrega). El nodo
de reparto se llama `ForestScatter`, `DuneScatter` o `MarshScatter`.

| Qué quieres cambiar | Dónde | Qué propiedad |
| --- | --- | --- |
| Tamaño de la arena | la arena > *Scatter (grupo «Arena») | `arena_half_extent` (y mover a mano los muros de `Perimeter` a ±(ese valor + 0.5)); el Bosque Hueco mide 320 m (`arena_half_extent = 160`), las otras dos, 240 |
| Cuántos árboles, rocas o tocones hay y su tamaño | la arena > *Scatter (grupo «Reparto interior») | `tree_count`, `rock_count`, `stump_count`, `*_scale_min/max` |
| Ancho de los pasillos y zona libre del inicio | la arena > *Scatter («Reparto interior») | `min_prop_spacing`, `spawn_clear_radius`, `keepout_radius` |
| Línea de props del borde | la arena > *Scatter (grupo «Borde») | `perimeter_step`, `perimeter_rock_every`, `perimeter_jitter` |
| Mesetas | la arena > *Scatter (grupo «Mesetas») | `mesa_count`, `mesa_scale_min/max`, `mesa_ramp_offset`, `mesa_ramp_attached` (encendido pega la rampa a la plataforma a cualquier escala; solo el Bosque Hueco lo enciende), `mesa_footprint_gap` (metros libres alrededor de la plataforma y la rampa de cada meseta, a su escala: ahí no se coloca ningún POI ni prop y, en el Bosque Hueco, tampoco spawns, botín ni pasto) |
| Cofres sobre las mesetas | la arena > *Scatter (grupo «Mesetas») | `mesa_chest_scene`, `mesa_chest_count`, `mesa_deck_height` (en el Bosque Hueco, 4 de sus 5 mesetas llevan cofre) |
| Meseta del Bosque Hueco (el estrado de piedra y su escalera): medidas, adornos y colores | `scenes/world/props/RuinDais.tscn` > RuinDais («Medidas», «Adornos», «Colores») y `RuinStairs.tscn` > RuinStairs | `post_height`, `ivy_per_side`, `runes_per_side`, `rubble`, `banners`, `banner_width/length`, `light_energy`, colores; en la escalera `steps`, `cheek_width`, `post_height`, colores (las medidas de la caja y la cuña tienen que seguir iguales a su colisión) |
| Formaciones de roca (cuántas y qué tan grandes) | la arena > *Scatter (grupo «Máscara de la arena») | `mask_blobs_min/max`, `mask_blob_cells_min/max`, `mask_min_open_fraction` |
| Color y forma de la roca de un bioma | `assets/world/rock_style_<mapa>.tres` | `rock_color`, `cap_color`, `cliff_height`, `peak_height`, `max_height` (bajar `margin_min` o `cliff_height` puede abrir huecos en el sello del mapa) |
| Tamaño de las ondulaciones, grietas y cumbres de la roca (todas las arenas) | `scripts/world/rock_formation.gd` (bloque «edita aquí») | `LIFT_WAVELENGTH`, `CRAG_WAVELENGTH`, `EDGE_WAVELENGTH`, `SPIRE_WAVELENGTH` (metros; más grande = rasgos más anchos), `SPIRE_FADE_FROM`/`SPIRE_FADE_TO` (desde qué profundidad asoman las cumbres) |
| Jugar siempre el mismo mapa (para probar) | la arena > *Scatter (grupo «Semilla (solo pruebas)») | `randomize_per_run` apagado y `scatter_seed` |
| Altura de las lomas del suelo | la arena > Terrain (grupo «Relieve») | `amplitude`, `feature_size` (en el Bosque Hueco, que tiene relieve por zonas, es la ondulación DENTRO de cada zona) |
| Quitarle o ponerle a una arena el relieve por zonas (montaña, cañón, cerros, rampas, puentes y sus estructuras) | la arena > Terrain (grupo «Relieve») | `relief` (un `.tres` de `assets/world/`; vacío = suelo suave) |
| Macizo del Bosque Hueco (el nivel donde aparece el equipo): tamaño, forma y alto | `assets/world/relief_hollow_woods.tres` (grupo «Macizo») | `massif_radius_min/max`, `massif_stretch_min/max`, `massif_lobes`, `massif_height_min/max`, `massif_offset_min/max` (a cuánto del centro queda el spawn), `massif_swell_min/max`, `massif_ways_min/max` (rampas al llano) |
| Segundo nivel y cumbre de la montaña | `relief_hollow_woods.tres` (grupo «Niveles altos») | `tier_radius_min/max`, `tier_height_min/max`, `tier_distance_min/max`, `tier_ways_min/max`; `summit_radius_min/max`, `summit_height_min/max`, `summit_shift`, `summit_ways_min/max`; `tier_margin` (la cornisa entre dos cortes), `tier_ramp_slope_degrees` (ningún corte sobre 8 m: la horda trepa 10) |
| Cerros sueltos del llano: cuántos, qué tan grandes y qué tan altos | `relief_hollow_woods.tres` (grupo «Cerros») | `butte_count_min/max`, `butte_radius_min/max`, `butte_stretch_max`, `butte_lobes`, `butte_height_min/max`, `butte_swell_min/max`, `butte_ways_min/max` |
| Rampas: cada cuánto, ancho y pendiente | `relief_hollow_woods.tres` (grupo «Rampas») | `way_every`, `ramp_width`, `ramp_slope_degrees` (bajo 30: sobre 45 nadie camina), `swell_reach` |
| Cañón: largo, ancho, profundidad, curva y distancia a la montaña | `relief_hollow_woods.tres` (grupo «Cañón») | `ravine_length_min/max`, `ravine_width_min/max`, `ravine_depth_min/max`, `ravine_valley`, `ravine_gap`, `ravine_bend_min/max`, `ravine_ramp_slope_degrees`, `ravine_floor_detail` (el fondo no puede bajar de -7 m) |
| Puentes del cañón: cuántos, escena, ancho de la obra, largo de las escaleras y claro de las cabeceras | `relief_hollow_woods.tres` (grupo «Puentes») | `bridge_count_min/max` (entre dos puentes va siempre un collado), `bridge_scene` (vacío = sin puentes), `bridge_width`, `bridge_stair_reach` (de aquí sale la pendiente de las escaleras: bajo 45 grados), `bridgehead_radius` |
| Gran Puente: tablero, estribos y arcos | `scenes/world/props/Bridge.tscn` > Bridge («Medidas», «Arcos») | `deck_thickness`, `wing`, `nose`, `footing`; `pier_count` (los arcos son uno más), `pier_thickness`, `cutwater`, `cutwater_rise`, `crown_cover`, `pier_stand` |
| Gran Puente: barandas, torres, braseros y estandartes | `scenes/world/props/Bridge.tscn` > Bridge («Barandas», «Torres») | `parapet_height` (bajo 1.5: un raider la salta), `parapet_thickness`, `post_every`; `tower_height` (bajo 10), `tower_radius`, `tower_inset`, `lintel_height` (0 = sin dintel), `banner_width`, `banner_length`, `banner_color`, `banner_trim_color`, `flame_color`, `flame_light_energy` (0 = sin luz), `flame_light_range`, `flame_flicker` |
| Gran Puente: escaleras al río | `scenes/world/props/Bridge.tscn` > Bridge («Escaleras») | `stair_landing`, `stair_out`, `stair_embed`, `step_rise` (su largo viene de `bridge_stair_reach`, en `relief_hollow_woods.tres`) |
| Gran Puente: colores de la piedra | `scenes/world/props/Bridge.tscn` > Bridge («Colores») | `stone_color`, `stone_low_color`, `paving_color`, `trim_color`, `moss_color` |
| Sillares del puente: tamaño de las piedras y tramos de cada arco | `scripts/world/props/bridge/bridge_masonry.gd` (bloque «edita aquí») | `COURSE`, `BLOCK`, `ARCH_STEPS`, `RING_WIDTH`, `PAVERS_ACROSS`, `TOWER_SIDES`, `LINTEL_DROP`, `BOWL_COLOR`, `FLAME_CORE` |
| Cómo rodea la horda un puente (por dónde entra y por dónde sube) | `scripts/world/run/terrain/relief_lanes.gd` (bloque «edita aquí») | `BELOW`, `NEAR_ALONG`, `NEAR_ASIDE`, `MOUTH`, `CLIMB_BACK`, `CLIMB_ASIDE` |
| Qué estructuras lleva el relieve (apagar una = dejar su escena vacía) | `relief_hollow_woods.tres` (grupo «Estructuras») | `landmark_scene` (el Árbol Hueco), `stones_scene` (portales, menhires, círculo, ruinas, monolitos), `ruin_count`, `monolith_count`, `monolith_height_min/max` (bajo 10 m), `water_material` (el agua del cañón) |
| Árbol Hueco de la cumbre: alto, grosor, raíces, copa y colores | `scenes/world/props/HollowTree.tscn` > HollowTree («Tronco», «Raíces», «Copa») | `trunk_height`, `trunk_base_radius`, `hollow_height`, `root_count`, `crown_blobs`, `crown_blob_radius`, `crown_spread`, `bark_color`, `leaf_dark_color`, `leaf_bright_color` |
| Piedras antiguas (portales, menhires, círculo, ruinas): tamaños y colores | `scenes/world/props/StandingStones.tscn` > StandingStones («Piedras», «Color») | `stone_height_min/max`, `stone_radius`, `gate_height`, `gate_thickness`, `circle_stones`, `ruin_pillars`, `tilt_degrees`, `stone_color`, `moss_color` |
| Vegetación del suelo (arbustos, pasto, flores, hongos, piedras, helechos): cuánta y de qué color | la arena > *Scatter > GroundCover («Cantidades (por trozo)», «Tamaños», «Colores») | `bushes`, `tufts`, `flower_patches`, `mushroom_groups`, `pebble_groups`, `ferns`; `bush_radius_min/max`, `tuft_height_min/max`, `fern_reach_min/max`; `flower_colors`, `mushroom_caps`, `bush_dark`, `bush_bright`, `fern_color` |
| Árboles antiguos (los gigantes): cuántos y qué tan grandes | la arena > *Scatter (grupos «Escenas de props» y «Reparto interior»); la escena es `scenes/world/props/AncientTree.tscn` | `ancient_tree_scene`, `ancient_tree_count`, `ancient_tree_scale_min/max` |
| Cordillera del horizonte: cuántos picos, qué tan altos y de qué color | la arena > Backdrop (grupo «Cordillera») | `peak_count` (0 = sin cordillera), `peak_height_min/max`, `peak_width_min/max`, `peak_ring_min_factor`/`peak_ring_max_factor`, `peak_sides`, `peak_base_color`, `peak_top_color` |
| Agua del cañón: color y brillo | `assets/materials/water.tres` | `albedo_color`, `roughness`, `metallic` |
| Cascada: encenderla o apagarla | `relief_hollow_woods.tres` (grupo «Estructuras») | `cascade` |
| Cascada y río: anchos, a cuánto del puente va, color del agua que cae, nenúfares y juncos | `scripts/world/run/scatter/relief_waters.gd` (bloque «edita aquí») | `CASCADE_APART`, `SPRING_INSET`, `SPRING_RADIUS`, `POOL_RADIUS`, `STREAM_WIDTH`, `FALL_WIDTH`, `FALL_LIP`, `FALL_REACH`, `RAPIDS`, `FOAM`, `FLAKES`; `PAD_EVERY`, `PAD_RADIUS`, `REEDS_EVERY`, `REED_HEIGHT`, `LIFE_FROM_BRIDGE`, `PAD`, `PAD_FLOWER`, `REED` |
| Velocidad y tamaño de la espuma de la cascada | `scripts/world/props/cascade_flow.gd` (bloque «edita aquí») | `SPEED`, `FLAKE_MIN`, `FLAKE_MAX` |
| Camino antiguo: ancho, losas que faltan, hasta dónde sigue y faroles | `scripts/world/run/scatter/relief_road.gd` (bloque «edita aquí») | `WIDTH`, `ROW_STEP`, `GAPS`, `GAPS_AT_END`, `START`, `BEYOND`, `FROM_CLIFF`, `FROM_CANYON`; `LAMP_EVERY`, `LAMP_ASIDE`, `LAMP_HEIGHT`, `LAMP_FROM_HEAD`; `SLAB`, `MOSS`, `LAMP_STONE`, `LAMP_GLOW` |
| Árboles colosales del horizonte: cuántos, qué tan altos y de qué color | la arena > Backdrop (grupo «Árboles colosales») | `giant_count` (0 = ninguno), `giant_height_min/max`, `giant_ring_min_factor`/`giant_ring_max_factor`, `giant_trunk_radius`, `giant_crown_radius`, `giant_bark_color`, `giant_leaf_dark_color`, `giant_leaf_bright_color` |
| Hongos gigantes: cuántos y qué tan grandes | la arena > *Scatter (grupos «Escenas de props» y «Reparto interior») | `mushroom_scene`, `mushroom_count`, `mushroom_scale_min/max` |
| Hongos gigantes: forma y colores | `scenes/world/props/GiantMushroom.tscn` > GiantMushroom («Forma», «Colores») | `stem_height_min/max`, `stem_radius` (es lo que frena), `cap_radius_min/max`, `sprouts`, `spots`, `cap_colors`, `stem_color`, `spot_color` |
| Hojas que caen: cuántas, tamaño, velocidad, viento y colores | la arena > FallingLeaves (grupo «Hojas») | `leaf_count`, `leaf_lifetime`, `area_half_extent`, `spawn_height`, `leaf_size_min/max`, `fall_speed`, `wind`, `leaf_colors` |
| Dónde cae el relieve: lejos del spawn, del borde y entre sí | `relief_hollow_woods.tres` (grupo «Reparto en el mapa») | `spawn_clearance` (metros sin cortes alrededor del spawn), `edge_margin`, `feature_gap` |
| Que el borde no plante árboles en las esquinas del mapa | la arena > *Scatter (grupo «Borde») | `perimeter_corner_gap` (metros desde cada esquina; 0 = planta hasta la esquina) |
| Aire alrededor de troncos y rocas donde no se coloca nada (portal de salida, eventos, cofres, spawns) | `scripts/world/run/scatter/prop_footprints.gd` (bloque «edita aquí») | `SKIRT` (metros más allá de la colisión del prop), `CELL` (lado de la grilla) |
| Forma de la roca de los acantilados (cornisa, labio, inclinación de la cara) | `scripts/world/cliff_wall.gd` (bloque «edita aquí») | `LEDGE_BURIED`, `LEDGE_INNER`, `LIP_MIN/MAX`, `FACE_RUN` (más alto = cara más acostada; no pasar de 0.28, que en las esquinas la cara ya se acuesta un 40% más y bajo 60 grados la horda no la trepa), `JITTER_ALONG`; los colores salen del `rock_style_<mapa>.tres` |
| Distancia de árboles, rocas y mesetas a un corte | la arena > *Scatter (grupo «Relieve por zonas») | `relief_prop_clearance`, `relief_mesa_clearance`, `relief_mesa_keepout` |
| Distancia de POIs, spawns y cofres soltados a un corte | `stage_layout.gd`, `spawn_points.gd`, `enemy_loot.gd` (constantes al comienzo) | `RELIEF_MARGIN` (POIs 5 m, contados desde el borde de lo que ocupa cada POI y, en todo mapa, también de la roca y de cada meseta; spawns 4 m), `DROP_RELIEF_MARGIN`; `PROP_TOP` (un spawn no cae sobre la punta de un árbol) |
| Distancia de un jefe a un corte al elegir dónde ponerse | `scripts/enemies/boss_base.gd` → grupo «Jefe» | `relief_margin` |
| Suelo lejano de una arena con relieve por zonas | la arena > Backdrop (grupo «Suelo lejano») | `rim_drop`, `rim_overlap` (el marco que rodea la arena al nivel de su borde) |
| Verdes del pasto del Bosque Hueco | `assets/shaders/forest_ground.gdshader` (uniforms «Pasto»), o HollowWoods.tscn > Terrain > `surface_material` (Shader Parameters) | `grass_dark`, `grass_light`, `grass_scale` |
| Color del minimapa y colinas del horizonte | la arena > Backdrop | `ground_color`, `hill_color`, `far_hill_color` (cambiar `hill_count` mueve los altares aunque la semilla sea la misma) |
| Tamaño y variante de los pinos | `scenes/world/props/Tree.tscn` > Tree | `wide_chance`, `base_scale`, `width_scale_min/max`, `height_scale_min/max` |
| Color de las rocas sueltas de las Dunas de Ceniza | `assets/materials/boulder_red.tres` (lo usa `scenes/world/props/DuneRock.tscn`) | `shader_parameter/albedo` |
| Color de las rocas sueltas del Bosque Hueco y la Ciénaga Lóbrega | `scenes/world/props/Rock.tscn` (modelo `assets/models/survival/rock-a.glb`) | sin valor propio: el color sale de la textura `assets/models/survival/Textures/colormap.png`, que también pinta árboles y tocones |

## HUD

| Qué quieres cambiar | Dónde | Qué propiedad |
| --- | --- | --- |
| Posición o tamaño de cualquier elemento del HUD | `scenes/ui/HUD.tscn` > el nodo (RunInfo, KillsLabel, LoadoutDock, FpsBadge, PowerUpRow, MatePanel…) | Layout (anclas y márgenes) |
| Fila de arriba a la izquierda (reloj, etapa y dificultad) | HUD.tscn > RunInfo | Layout; Theme Overrides > Constants > `separation` (espacio entre fichas) |
| Ficha de dificultad (texto, colores, golpe al subir) | `scenes/ui/hud/DifficultyChip.tscn` > raíz (icono y tamaño de letra: sus hijos Icon y Label) | `text_format`, `tip_format`, `body_color`, `border_color`, `text_color`, `pop_scale`, `pop_time` |
| Dónde va el equipo (armas, tomos, mascota y objetos) | HUD.tscn > LoadoutDock (abajo a la izquierda; crece hacia arriba) | Layout |
| Cuántos objetos caben antes de la ficha «+N» | HUD.tscn > LoadoutDock/BagStrip | `columns` (fichas por fila) y `max_tiles` (columnas x filas) |
| Línea entre armas, tomos y mascota | HUD.tscn > LoadoutDock/BuildStrip | `divider_size`, `divider_color` |
| Golpe de una ficha al ganarla o subirla | HUD.tscn > LoadoutDock/BuildStrip y BagStrip | `gain_pop_scale`, `gain_pop_time` |
| Tamaño de las fichas chicas de objetos | `scenes/ui/hud/LoadoutTile.tscn` > raíz (grupo «Casilla chica») | `compact_size`, `compact_glyph_font_size`, `compact_corner_font_size` |
| Icono de un tomo o un objeto en su ficha | el mismo de la Colección: `scripts/ui/stat_icons.gd` (`ICON_FILES`) y `scripts/ui/item_icons.gd` (`KIND_FILES`); para un dibujo propio, un PNG en `assets/icons/<tomes o items>/<id>.png` | la fila del stat o del `kind` |
| Tamaño y margen del minimapa | HUD.tscn > ViewWidgets/MinimapSlot (solo cuentan su tamaño y sus márgenes, medidos desde la esquina superior derecha de cada celda; no muevas sus anclas); en co-op y en las celdas de abajo, ViewWidgets | Layout > márgenes; `coop_size_scale`, `lower_cell_top_margin` |
| Color o tamaño de Nivel, Reloj, Etapa, Bajas y Puntos | HUD.tscn > LevelLabel, RunInfo/TimerLabel, RunInfo/StageLabel, KillsLabel, PointsLabel | Theme Overrides > Colors / Font Sizes |
| Colores de la barra de vida y el latido de vida baja | HUD.tscn > HUD | `hp_full_color`, `hp_low_color`, grupo «Latido de vida baja» |
| Color y forma de la barra de XP | HUD.tscn > HUD | `xp_color`, `xp_trough_color`, `xp_line_color`, `xp_corner_radius`, `xp_line_width` |
| Textos de bajas, puntos, etapa y reloj | HUD.tscn > HUD (grupo «Textos») | `kills_format`, `points_format`, `stage_format`, `stage_lap_format`, `timer_format` |
| Palabras, colores y umbrales de las rachas («¡TRITURANDO!») | HUD.tscn > StreakLabel | `tier_kills`, `tier_words`, `tier_colors`, `window_seconds` |
| Duración y color de los avisos en pantalla | HUD.tscn > AnnounceLabel | `fade_in_time`, `hold_time`, `fade_out_time`, `normal_color`, `major_*` |
| Barra de vida del jefe: colores (y color de la flecha que apunta al jefe) | `scripts/ui/game/hud/boss_bar.gd` («Colores») | `fill_color`, `trough_color`, `ghost_color`, `low_color`, `tick_color` |
| Barra de vida del jefe: marco, sombra y brillo | `boss_bar.gd` («Forma») | `corner_radius`, `border_width`, `shadow_offset`, `shine_height`, `shine_lighten` |
| Barra de vida del jefe: rastro del daño, llenado, sacudida y latido con poca vida | `boss_bar.gd` («Animación») | `tween_time`, `ghost_delay`, `ghost_speed`, `fill_in_time`, `shake_pixels`, `shake_time`, `low_fraction`, `low_pulse_speed` |
| Tamaño y lugar de la barra del jefe y de su nombre | `scenes/ui/HUD.tscn` > BossBar y BossBar/BossNameLabel | sus `offset_*`; en el nombre, `font_size` y `outline_size`; `name_letter_spacing` en `boss_bar.gd` |
| Rombos de fase bajo la barra de un jefe que cuenta sus fases (la señal `lives_changed` y los métodos `lives_left()` y `lives_total()`; hoy ninguno: Mythos las esconde a propósito) | `boss_bar.gd` («Fases») | `pip_size`, `pip_gap`, `pip_drop`, `pip_spent_color` |
| Colores de las fichas de armas, evoluciones y tomos | HUD.tscn > LoadoutDock/BuildStrip | `weapon_color`, `evolved_weapon_color`, `tome_color` |
| Contorno, sombra y glifo de cada ficha (su color es el de su tipo o rareza) | `scenes/ui/hud/LoadoutTile.tscn` > raíz | `border_width`, `corner_radius`, `shadow_offset`, `show_placeholder_art`, `glyph_font_size` |
| Tarjeta de botín | `scenes/ui/hud/LootToast.tscn` > raíz | `hold_time`, `fade_time`, `background_color` |
| Filas de compañeros en co-op | `scenes/ui/hud/MateRow.tscn` > raíz | `knocked_out_format`, `knocked_out_tint`, `points_format` |
| Panel de relleno del cuarto vacío con 3 jugadores (fondo, texto, color, tamaño) | `scripts/systems/split_screen.gd` (bloque «Edita aquí») | `FILLER_BG`, `FILLER_TEXT`, `FILLER_TEXT_COLOR`, `FILLER_FONT_SIZE` |
| Color del chip de clima bajo el reloj | HUD.tscn > RunInfo/TimerLabel/WeatherBadge | `group_colors`, `text_format` (el nombre sale de `display_name` en `weather_catalog.gd`) |
| Insignia de FPS | HUD.tscn > FpsBadge | `text_format`, `background_color`, `refresh_seconds` |
| Minimapa: que gire con la cámara o deje el norte arriba; colores y grosor del aro, sombra | `scenes/ui/maps/Minimap.tscn` > raíz | `rotate_with_view`, `ring_color`, `band_color`, `outline_width`, `inner_outline_width`, `shadow_color`, `shadow_offset`, `north_inset` (la chapa «N» es el nodo North) |
| Minimapa: cuánto terreno muestra, tamaño de los marcadores y grosor total del aro | `Minimap.tscn` > View | `view_radius` (metros), `marker_scale`, `own_arrow_scale`, `own_halo_alpha`, `pinned_scale`, `pin_margin`; el aro es el margen del nodo (Layout) |
| Colores del suelo del mapa: lo sin explorar, fuera de la arena y la línea del borde | `Minimap.tscn` > View y `MapOverlay.tscn` > MapView (grupo «Suelo») | `unexplored_color`, `unexplored_strength`, `outside_color`, `border_color`, `border_meters`, `rim_shade` |
| Cada cuánto se refrescan la niebla y los marcadores del mapa | HUD.tscn > ViewWidgets | `refresh_seconds` |
| Colores, formas y leyenda de los marcadores del mapa; cuáles se anclan a la orilla del minimapa | `scripts/ui/maps/map_draw.gd` | `MARKER_STYLES` (`color`, `shape`, `size`, `pin`, `order`), `MARKER_LABELS` |
| Color de la flecha de cada jugador (J1-J4), contorno de los marcadores y anillo de caído | `scripts/ui/maps/map_draw.gd` (bloque «Edita aquí») | `PLAYER_COLORS`, `OUTLINE_COLOR`, `OUTLINE_WIDTH`, `DOWNED_RING_*` |
| Formaciones de roca en el mapa, nitidez de la imagen y fondo liso cuando la arena no tiene Terrain | `scripts/ui/maps/map_ground.gd` (bloque «Edita aquí») | `ROCK_BLEND`, `ROCK_OUTLINE_DARKEN`, `ROCK_EDGE`, `ROCK_FALLBACK_COLOR`, `PIXELS_PER_METER`, `PLAIN_BACKGROUND` (el color de la roca sale del `formation_style` de cada arena) |
| Mapa de Tab: cuánto tapa el velo al mundo y su viñeta | `scenes/ui/maps/MapOverlay.tscn` > Dim > Material | `dim`, `vignette`, `tint_color`, `edge_color` |
| Mapa de Tab: color, giro y título de cada tarjeta | `MapOverlay.tscn` > StatsPanel, PlayersPanel, PowerUpsPanel, PetPanel, ItemsPanel | `tile_color`, `tilt_degrees`, `title` |
| Mapa de Tab: contorno, esquinas, sombra, márgenes y letra del título de las tarjetas | `scenes/ui/maps/MapSection.tscn` > raíz (grupos «Marco», «Contenido», «Panel») | `border_width`, `corner_radius`, `shadow_offset`, `padding`, `title_font_size` y sus pares `compact_*` para las celdas de co-op |
| Mapa de Tab: marco del mapa, márgenes y orden de los paneles | `MapOverlay.tscn` (MapFrame, Layout y los paneles bajo Side/Panels) | Layout, Theme Overrides > Styles |
| Mapa de Tab: cuánto ancho toma el mapa, ancho mínimo de la columna de paneles, separación de las tarjetas, aparición y textos | `MapOverlay.tscn` > raíz | `map_share`, `min_map_side`, `min_side_width`, `wide_cell_aspect`, `panel_gap`, `compact_panel_gap`, `tight_panel_gap`, `fade_seconds`, `pop_stagger`, `header_font_size`, grupo «Textos» (`close_hint` incluido) |
| Estadísticas del mapa de Tab: colores de subida y baja, chapa del valor, letra y ancho de cada celda | `MapOverlay.tscn` > Stats | `raised_color`, `lowered_color`, `idle_color`, `chip_color`, `chip_radius`, `font_size`, `cell_min_width`, `max_columns` |
| Filas de estadísticas del mapa de Tab (nombre, nombre corto para co-op, orden) | `scripts/ui/maps/map_overlay.gd` | `STAT_ROWS` (al comienzo) |
| Filas de jugadores del mapa de Tab (co-op) | `MapOverlay.tscn` > Players | `bar_size`, `knocked_out_color`, `knocked_out_format`, `points_format`, `font_size` |
| Fichas de equipo y de power-ups del mapa de Tab | `scenes/ui/maps/MapChip.tscn` (la casilla es Tile; el nombre, Name; la etiqueta, Tag) | Theme Overrides; en Tile, `glyph_font_size` y tamaño mínimo |
| Separación entre las fichas del mapa de Tab | `MapOverlay.tscn` > `Items` y `PowerUps` | con espacio: Theme Overrides > Constants > H Separation; en celdas chicas: `compact_h_separation` (grupo «Fichas») |
| Mapa de Tab: cómo se desliza la columna de paneles cuando ni el escalón más apretado cabe | `MapOverlay.tscn` > `Side` (grupo «Deslizamiento») | `scroll_pause` (segundos quieta arriba y abajo), `scroll_speed` (px/s) |
| Leyenda del mapa de Tab | `MapOverlay.tscn` > Legend y SideLegend | `swatch_side`, `swatch_scale`, `font_size`, `text_color`, `outline_size` |

## Menús

| Qué quieres cambiar | Dónde | Qué propiedad |
| --- | --- | --- |
| Menú principal: título, subtítulo, textos de Ajustes y Salir | `scenes/ui/MainMenu.tscn` > Layout/VBox/TopBar/Titles/*, Footer/ButtonRow/* | `text`, Theme Overrides |
| Menú principal: nombre, frase, color y giro de cada tarjeta (Cacería, Misiones, Colección, Armería); ancho de Cacería | `MainMenu.tscn` > Layout/VBox/Tiles/HuntButton, QuestsButton, CollectionButton, ArmoryButton | grupos «Textos» (`title_text`, `detail_text`) y «Marco» (`tile_color`, `tilt_degrees`); Layout > Stretch Ratio |
| Tarjetas del menú principal: contorno, sombra, letra y movimiento (las cuatro a la vez) | `scenes/ui/menu/MenuTile.tscn` > raíz, Frame/Content/VBox/Title, Detail, Stat (el texto es hijo del marco: gira y crece con él) | grupos «Marco» (`border_width`, `corner_radius`, `shadow_offset`, `shadow_offset_lifted`) y «Movimiento» (`focus_scale`, `press_scale`, `pose_time`, `entrance_time`, `entrance_rise`); Theme Overrides |
| Menú principal: dibujo de cada tarjeta (cuál, contorno, cuánto se inclina con foco) | `MainMenu.tscn` > Layout/VBox/Tiles/* (los SVG están en `assets/ui/icons/menu_*.svg`; Cacería no lleva: muestra la foto del raider elegido) | grupo «Dibujo» (`art_texture`, `art_outline`, `art_lit_tilt`) |
| Dibujos del menú: sombra, aire, cuánto suben y crecen con foco, duración (las cuatro a la vez) | `scripts/ui/menu/menu_tile.gd` | grupo «Dibujo» (`art_shadow_offset`, `art_padding`, `art_lift`, `art_lit_scale`, `art_time`, `art_fade_time`) |
| Menú principal: dato de la tarjeta Misiones, indicación del control y entrada escalonada | `MainMenu.tscn` > raíz | grupos «Textos» (`quests_claimable_format`, `choose_hint`, `version_format`) y «Movimiento» (`tile_stagger`, `shards_pop_*`) |
| Cambio entre pantallas de menú (duración y distancia de la salida y la entrada) | `scripts/ui/menu/menu_nav.gd` (constantes al comienzo) | `EXIT_TIME`, `EXIT_SHIFT`, `ENTER_TIME`, `ENTER_SHIFT` |
| Título y subtítulo del selector de personajes | `scenes/ui/CharacterSelect.tscn` > TopBar/Titles/TitleLabel, SubtitleLabel | Theme Overrides |
| Botones Volver y Ajustes y chapa de esquirlas del selector (tamaño, letra) | `CharacterSelect.tscn` > TopBar/Left/BackButton, SettingsButton, TopBar/Right/ShardsLabel | `custom_minimum_size`, Theme Overrides |
| Textos de los botones del selector (Iniciar, Cacería diaria, Volver) | `CharacterSelect.tscn` > raíz (grupo «Textos»), Main/DetailColumn/StartButton y Footer/ButtonRow | `start_solo_format`, `start_party_format`, `daily_best_format` (Cacería diaria cuando ya hay marca hoy), `choose_hint`, `back_hint` (indicaciones del control); `text` de cada botón |
| Columnas de la cuadrícula de personajes y separación entre cartas | `CharacterSelect.tscn` > raíz (grupo «Cuadrícula») y CardsGrid | `grid_min_columns`, `card_max_width`; `h_separation`, `v_separation` |
| Brillo del título, entrada escalonada de las cartas y rebotes del selector | `CharacterSelect.tscn` > raíz (grupo «Movimiento») | `title_glow_color`, `title_glow_time`, `card_stagger`, `card_stagger_shrink`, `card_stagger_cap`, `entrance_fade_time`, `start_hover_grow`, `start_press_squash`, `shards_pop_*` |
| Carta de personaje (letra y color del nombre y de la inicial) | `scenes/ui/meta/character_select/CharacterCard.tscn` > Unlocked/Name, Unlocked/Portrait/Monogram | Theme Overrides |
| Carta bloqueada (precio, candado, pregunta de desbloqueo) | `CharacterCard.tscn` > Locked/*, Confirm/* y raíz | Theme Overrides; `confirm_format` |
| Bordes y tamaño mínimo de la carta (el anillo de foco amarillo es el de `ui_theme.gd`) | `CharacterCard.tscn` > raíz | grupo «Bordes» (`idle_border_color`, `selected_border_width`…), `custom_minimum_size` |
| Retrato de la carta (fondo del tinte del raider, giro de sticker, fundido de la cara) y movimiento con el foco o el cursor | `CharacterCard.tscn` > raíz (grupos «Retrato», «Movimiento») | `portrait_body_darken`, `portrait_tilt`, `face_fade_time`, `monogram_outline_darken`; `focus_scale`, `press_scale`, `pose_time`, `unselected_modulate`, `entrance_start_scale`, `entrance_time` |
| Foto de la cara de cada raider en su carta (encuadre, ángulo, recorte, tamaño, luces) | `scenes/ui/meta/character_select/PortraitStudio.tscn` > raíz (grupos «Encuadre», «Foto») y Viewport/Stage/KeyLight, RimLight, Camera | `pose_angle`, `window_per_width`, `window_min`, `headroom`, `framing_margin`, `camera_lift`, `crop_margin`, `face_max_width`; `light_energy`, `fov` |
| Panel de detalle del raider (letra y color de nombre, arma, pasiva, descripción, precio; ancho del panel) | `scenes/ui/meta/character_select/CharacterDetail.tscn` > Body/Content/Info/* y raíz | Theme Overrides; `text` de los rótulos «Arma» y «Pasiva»; `custom_minimum_size` |
| Cambio de raider en el panel de detalle (deslizamiento, fundido) y su borde | `CharacterDetail.tscn` > raíz (grupos «Movimiento», «Panel», «Textos») | `slide_distance`, `fade_from`, `swap_time`; `border_darken`, `panel_margin`; `hint_format` |
| Retrato 3D del raider (velocidad de giro, ángulo, encuadre, foca para los raiders sin modelo) | `scenes/ui/meta/character_select/CharacterPortrait.tscn` > raíz (grupo «Modelo») | `spin_speed`, `start_angle`, `framing_margin`, `camera_lift`, `look_height`, `skin_padding`, `model_fade_time`, `seal_for_rows_without_model` |
| Fondo, luces y cámara del retrato 3D | `CharacterPortrait.tscn` > raíz (grupo «Fondo») y Viewport/Stage/KeyLight, RimLight, Camera, WorldEnvironment | `backdrop_darken`, `backdrop_rim_darken`, `spot_alpha`; `light_energy`, `light_color`, `fov`, `ambient_light_energy` |
| Lobby co-op (textos y botones 1-4) | `scenes/ui/meta/character_select/CoopLobby.tscn` | grupo «Textos»; PlayersRow/Count1..Count4 |
| Colores, bordes y tamaños de los botones del lobby co-op | `CoopLobby.tscn` > raíz (grupos «Botones de cantidad», «Botones de slot») | `count_*`, `slot_*` (por ejemplo `count_selected_color`, `slot_button_size`) |
| Oscurecido sobre el mapa de fondo de los menús (cuánto tapa, viñeta, color de respaldo sin mapa) | `assets/ui/menu_backdrop.gdshader` (o el Inspector de `assets/ui/menu_backdrop.tres`) | `dim`, `vignette`, `tint_color`, `edge_color` |
| Mapa de fondo de los menús (cámara: altura, giro, campo de visión; aparición; sombras) | `scripts/ui/menu/menu_backdrop.gd` (bloque de constantes al comienzo) | `CAMERA_HEIGHT`, `CAMERA_TURN_SPEED`, `CAMERA_FOV`, `CAMERA_PITCH`, `CAMERA_BOB_*`, `REVEAL_TIME`, `SHADOW_DISTANCE` |
| Títulos de Misiones, Armería y Colección | `scenes/ui/QuestLog.tscn`, `RelicShop.tscn`, `Collection.tscn` > TitleLabel | Theme Overrides |
| Filas de Armería y Colección (letra, color, textos) | `RelicShop.tscn`, `Collection.tscn` > raíz | grupos «Filas» y «Textos» |
| Colección: títulos de sección (RAIDERS, ARSENAL, BESTIARIO) y el «???» de lo no descubierto | `scenes/ui/Collection.tscn` > raíz | grupo «Textos» (`raiders_title`, `arsenal_title`, `bestiary_title`, `unknown_text`) |
| Misiones: tarjeta (fondo, contorno, sombra, atenuado de las reclamadas), fichas de tipo y recompensa, colores de la barra, sello «¡Lista!» y todos sus textos (Reclamar, RECLAMADA, «Faltan %d») | `scenes/ui/meta/QuestCard.tscn` > raíz | grupos «Tarjeta», «Ficha de tipo», «Barra de progreso», «Recompensa», «Sello», «Animación» y «Textos» |
| Misiones: tamaño y color de letra de nombre, descripción, avance y recompensa; alto de la barra; tamaño del botón Reclamar | `scenes/ui/meta/QuestCard.tscn` > Name, Description, Bar, Count, Remaining, Reward, ClaimButton | Theme Overrides; Layout > Custom Minimum Size |
| Misiones: títulos de grupo («Para reclamar», «Reclamadas»), su letra y color, y el ritmo de la entrada de las tarjetas | `scenes/ui/QuestLog.tscn` > raíz | grupos «Grupos» y «Entrada» (`card_stagger`, `card_stagger_shrink`, `card_stagger_cap`) |
| Misiones: tipos (título de grupo, icono, orden) y qué contador cae en cada tipo | `scripts/ui/meta/quest_log/quest_types.gd` | `TYPES`, `STATS`, `PREFIXES`; iconos en `assets/ui/icons/quests/` |
| Icono de esquirla de la ficha de recompensa | `assets/ui/icons/shard.svg` | el dibujo |
| Armería: tamaño del botón de compra, sello MÁX y separaciones de cada fila | `scenes/ui/RelicShop.tscn` > raíz | grupo «Filas» (`buy_button_size`, `maxed_spacing`, `columns_separation`, `info_separation`) |
| Vendedor de la Armería: sus frases (abrir, comprar, no alcanza, rango máximo, todo al máximo) | `scenes/ui/meta/Shopkeeper.tscn` > raíz | grupo «Frases» (`open_lines`, `bought_line`, `cant_afford_line`, `maxed_line`, `sold_out_line`) |
| Vendedor de la Armería: globo de diálogo (colores, contorno, sombra), su aparición y la respiración del herrero | `scenes/ui/meta/Shopkeeper.tscn` > raíz (letra del globo: su hijo Text; punta: Tail y TailOutline) | grupos «Globo» y «Animación» (`bubble_start_scale`, `bubble_time`, `breath_scale`, `breath_half_period`) |
| Vendedor de la Armería: el dibujo del herrero y su tamaño | `assets/ui/shopkeeper/blacksmith.svg`; tamaño: `Shopkeeper.tscn` > Figure y la raíz | el dibujo; Layout > Custom Minimum Size |
| Colección: separación entre el título y el detalle de cada fila y tono de las filas del bestiario | `scenes/ui/Collection.tscn` > raíz | grupo «Filas» (`row_separation`, `bestiary_row_lighten`) |
| Colección, submenú: nombre, frase, color, giro y dibujo de cada tarjeta | `scenes/ui/Collection.tscn` > Layout/VBox/Tiles/* (los SVG están en `assets/ui/icons/collection/`) | grupos «Textos», «Marco» y «Dibujo» de cada tarjeta |
| Colección, submenú: qué categoría abre cada tarjeta, textos del avance y entrada escalonada | `scripts/ui/meta/collection.gd` | `TILE_CATEGORIES` (al comienzo); grupos «Textos» (`badge_format`, `tile_progress_format`) y «Movimiento» (`tile_stagger`, `tile_stagger_shrink`) |
| Colección: bestiario (nombre, frase y color de cada enemigo) y todos los textos de las entradas («???», pistas, «HP base», «Abatidos»…) | `scripts/ui/meta/collection/collection_entries.gd` (bloques «Edita aquí») | `BESTIARY`, `CATEGORY_TITLES`, `UNKNOWN_NAME`, `HIDDEN_*`, `*_FORMAT`, `*_CAPTION`, `*_TINT` |
| Colección, cuadrícula: columnas, ancho de carta y entrada escalonada | `scenes/ui/CollectionBrowser.tscn` > raíz | grupos «Cuadrícula» (`grid_min_columns`, `card_max_width`) y «Movimiento» (`card_stagger`, `card_stagger_shrink`, `card_stagger_cap`) |
| Colección: carta (bordes, giro del dibujo, escala con foco, entrada) | `scenes/ui/meta/collection/CollectionCard.tscn` > raíz | grupos «Bordes», «Texto» y «Movimiento» |
| Colección: panel de detalle (margen, tamaño de las líneas, deslizamiento al cambiar) | `scenes/ui/meta/collection/CollectionDetail.tscn` > raíz; letras en Body/Content/Info/* | grupos «Panel», «Líneas» y «Movimiento»; Theme Overrides |
| Colección: marco del dibujo (fondo, contorno, tamaño del icono y de la sigla, silueta) | `scenes/ui/meta/collection/CollectionArt.tscn` > raíz | grupos «Marco» y «Contenido» |
| Colección: postal de un mapa (horizonte, sol, cerros) | `CollectionArt.tscn` > Postcard (los colores salen de `palette` en `map_catalog.gd`) | grupo «Postal» |
| Colección: foto y retrato giratorio de los enemigos (ángulo, encuadre, velocidad de giro, luces) | `scenes/ui/meta/collection/EnemyStudio.tscn`, `EnemyPortrait.tscn`, `EnemyStage.tscn` > raíz | grupos «Foto», «Modelo» y «Encuadre»; luces en EnemyStage > Stage |
| Icono propio de un objeto especial (imán, veneno, arañas…) | `scripts/ui/item_icons.gd` (bloque «Edita aquí»); los SVG están en `assets/ui/icons/items/` | `KIND_FILES` (kind -> archivo) |
| Nombre de cada estadística en las líneas de Objetos y Tomos | `scripts/ui/stat_icons.gd` | `LABELS` |
| Icono de cada estadística (daño, salud, armadura…) en la Armería y la Colección | `scripts/ui/stat_icons.gd` (bloque «Edita aquí»); los SVG están en `assets/ui/icons/stats/` | `ICON_FILES` (stat -> archivo), `FALLBACK_FILE` |
| Ficha del icono de estadística: tamaño, color, contorno y sombra | `scenes/ui/meta/StatIconChip.tscn` > raíz (grupo «Ficha») | `chip_size`, `chip_color`, `border_color`, `border_width`, `corner_radius`, `icon_padding`, `shadow_offset` |
| Tarjeta de las filas de la Armería (margen, borde y brillo) | `scripts/ui/meta/meta_screen.gd` | `CARD_MARGIN_H`, `CARD_MARGIN_V`, `CARD_BORDER_WIDTH`, `CARD_GLOW_SIZE`, `CARD_GLOW_ALPHA` (al comienzo) |
| Entrada de filas de la Armería, y conteo del saldo y destello de pago de Misiones y Armería | esas mismas escenas > raíz (sección MetaScreen); las tres a la vez: valores por defecto en `scripts/ui/meta/meta_screen.gd` | grupos «Animación» y «Textos» |
| Ajustes: formato de los valores, indicaciones y entrada del panel | `SettingsPanel.tscn` > raíz | grupos «Textos» (`sensitivity_format`, `volume_format`) y «Entrada» |
| Ajustes: sliders (canal, relleno y agarrador) y margen del panel | `scenes/ui/SettingsPanel.tscn` > raíz | grupos «Panel» (`panel_margin`) y «Sliders» (`slider_track_color`, `slider_track_border_color`, `slider_track_border_width`, `slider_track_margin`, `slider_corner_radius`, `slider_fill_darken`, `slider_fill_edge_width`, `slider_fill_edge_lighten`, `slider_grabber_hover_lighten`) |
| Ajustes: color de los valores y encabezados | `scenes/ui/SettingsPanel.tscn` > los nodos *Value; encabezados en SoundHeader/Label, ControlsHeader/Label y ScreenHeader/Label (texto y letra) y */Rule (línea) | Theme Overrides, `text`; `color` de cada Rule |
| Rango de la sensibilidad del mouse | `scripts/systems/autoloads/save_data.gd` | `MIN_MOUSE_SENSITIVITY`, `MAX_MOUSE_SENSITIVITY` |
| Pantalla de fin de partida | `scenes/ui/RunEndScreen.tscn` > TitleLabel; colores en `scripts/ui/game/run_end_screen.gd` | Theme Overrides; `DEFEAT_TITLE_COLOR`, `VICTORY_TITLE_COLOR` |
| Títulos y subtítulos de cada final («MORISTE», «¡Sobreviviste!»…) | `scripts/ui/game/run_end_screen.gd` > `ENDINGS` (al comienzo) | `title`, `subtitle` |
| Margen del panel de estadísticas de la pantalla de fin | `scenes/ui/RunEndScreen.tscn` > raíz | grupo «Panel» (`panel_margin`) |
| Textos de ganancias y animación de la pantalla de fin | `RunEndScreen.tscn` > raíz | grupos «Textos» (`stages_format`, `quests_format`…) y «Animación» (`title_start_scale`, `shimmer_color`…) |
| Paleta del juego (tinta, papel, amarillo, rojo naranja, menta, petróleo) y frases comunes («%d esquirlas», «J%d») | `scripts/ui/ui_theme.gd` (después corre `godot --headless --path . -s res://scripts/tools/build_ui_theme.gd`) | constantes de la sección «paleta», al comienzo |
| Fuentes (títulos y botones: Lilita One; texto: Nunito), grosor y tamaño del texto | `scripts/ui/ui_theme.gd` (y vuelve a correr `build_ui_theme.gd`); los archivos están en `assets/ui/fonts/` | `DISPLAY_FONT_PATH`, `TEXT_FONT_PATH`, `TEXT_WEIGHT`, `TEXT_SIZE`, `BUTTON_TEXT_SIZE` |
| Que un nodo nuevo use el estilo del juego | no hagas nada: `assets/ui/theme/game_theme.tres` es el tema de todo el proyecto. Para un título, un botón principal o una tarjeta, elige en el Inspector > Theme > Type Variation | `TitleLabel`, `HeadingLabel`, `DimLabel`, `BadgeLabel`, `PrimaryButton`, `DangerButton`, `CardPanel` |
| Anillo de foco del control (color, grosor, cuánto sobresale) | `scripts/ui/ui_theme.gd` | `FOCUS_COLOR`, `FOCUS_RING_WIDTH`, `FOCUS_RING_EXPAND` |
| Sombra dura de paneles, cartas y botones, texto de los botones, borde de las chapas, interruptor apagado y canal de las barras | `scripts/ui/ui_theme.gd` | `SHADOW_COLOR`, `PANEL_SHADOW_OFFSET`, `CARD_SHADOW_OFFSET`, `BUTTON_SHADOW_OFFSET`, `BUTTON_TEXT`, `BADGE_BORDER`, `TOGGLE_TRACK_OFF`, `BAR_TROUGH`, `BAR_TROUGH_BORDER` (al comienzo) |
| Medidas de paneles, botones, píldoras, interruptores, agarradores y barras (bordes, radios, brillos y márgenes) | `scripts/ui/ui_theme.gd` (sección «medidas de los estilos») | `PANEL_*`, `BUTTON_*`, `BADGE_*`, `TOGGLE_*`, `GRABBER_*`, `BAR_*`, `CARD_HIGHLIGHT_LIGHTEN`, `POP_RISE_SHARE` |
| Orden de dibujo de las capas de UI | las capas de escena en la raíz de su .tscn (HUD 5, UpgradeCardUI 10, modal/ModalPanel 15, RunEndScreen 20, PauseMenu 30); las que se crean en código en `scripts/ui/ui_layers.gd` | Layer; una constante por capa |

## Cartas de mejora, pausa, tienda y ruleta

| Qué quieres cambiar | Dónde | Qué propiedad |
| --- | --- | --- |
| Animación del reparto y de la carta elegida | `scenes/ui/UpgradeCardUI.tscn` > Motion | `reveal_delay`, `deal_time`, `deal_stagger`, `pick_scale` |
| Texto del título «Nivel N — elige» | `UpgradeCardUI.tscn` > raíz; aspecto en Center/VBox/LevelLabel | `level_title_template`; Theme Overrides |
| Letra, tamaño y color de los textos de una carta | `scenes/ui/upgrade_card_ui/UpgradeCard.tscn` > CardBox/RarityLabel, TitleLabel, DescLabel, WeapLabel | Theme Overrides |
| Brillo de las legendarias, cinta de rareza, crecer al pasar el cursor | `UpgradeCard.tscn` > raíz | `shine_color`, `ribbon_text_color`, `hover_grow` |
| Menú de pausa (título, animación, textos de ayuda) | `scenes/ui/PauseMenu.tscn` > TitleLabel y raíz | Theme Overrides; `panel_fade_time`, `accept_hint_text` |
| Marco común de la tienda y la ruleta («Tienes N pts», «Salir») | `scripts/ui/game/modal/modal_panel.gd` (vale para los dos paneles; para uno solo, la raíz de `RoulettePanel.tscn` o `VendorPanel.tscn`); aspecto de cada nodo en `scenes/ui/modal/ModalPanel.tscn` | grupos «Textos» (`points_template`, `close_text`) y «Panel» (`panel_margin`, `title_letter_spacing`); propiedades de cada nodo |
| Textos y barrido de la ruleta | `scenes/ui/modal/RoulettePanel.tscn` > raíz | `title_text`, `spin_template`, `sweep_time`, `sweep_steps` |
| Premios de la ruleta (cuánto da cada resultado y su peso) | `scripts/world/interactables/roulette_shrine.gd` > `OUTCOMES` | `amount`, `seconds`, `weight` (el número de la etiqueta sale del campo) |
| Precio del altar de la ruleta | `scenes/world/shrines/RouletteShrine.tscn` > raíz | `price` |
| Cartas y textos de la tienda | `scenes/ui/modal/VendorPanel.tscn` > raíz | `card_size`, `card_title_font_size`, `sold_template` |
| Margen y separación del contenido de las cartas de la tienda | `scripts/ui/card_factory.gd` (bloque «Edita aquí») | `CARD_BOX_MARGIN`, `CARD_BOX_SEPARATION` |
| Precios y oferta del vendedor | `scenes/world/Vendor.tscn` > Vendor | `pet_price`, `powerup_price_growth`, `pet_offers`, `item_offers` (precio inicial del power-up: `POWERUP_VENDOR_BASE_PRICE` en `run_state.gd`) |
| Aspecto del puesto del vendedor (mostrador, postes, toldo, repisa, sacos, farol, alfombra, sombrero) | `Vendor.tscn` > Look («Medidas», «Colores»); la figura, el toldo (nodo Sign) y la luz son nodos de Vendor.tscn | `counter_size`, `canopy_width`, `canopy_back_height`, `canopy_front_height`, `scallops`, colores; el color de la figura, el toldo y la luz sale del campo `color` de su fila en `VENDOR_LIBRARY` (`scripts/world/interactables/vendor.gd`) |
