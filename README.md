# Bonkraiders

Roguelite de supervivencia "bullet-heaven" en 3D hecho en Godot 4.7 (GDScript): partidas cronometradas de 15 minutos donde las armas disparan solas, los enemigos llegan en hordas crecientes y cada subida de nivel ofrece 3 cartas de mejora. Incluye dos biomas (Hollow Woods y Ash Dunes) con jefes propios y minijefes secretos, 8 personajes con arma inicial y pasiva propia, 8 armas, 9 tomos, 3 tiers de dificultad por mapa y meta-progresión entre partidas (Shards, 30 misiones, desbloqueo de personajes). El diseño completo está en `GDD.md` y la historia de desarrollo en `CHANGELOG.md`.

## Requisitos y ejecución

- **Godot 4.7.2** (el proyecto declara features `4.7` + Forward Plus). Sin plugins ni dependencias externas; todo el arte y audio es procedural/incluido.
- Ejecutar desde la raíz del proyecto:

```sh
godot --path .          # lanza el juego (escena principal: selector de personaje)
godot -e --path .       # abre el editor
```

- Escena principal: `scenes/ui/CharacterSelect.tscn` (selector de personaje, mapa y tier; botón Quests abre el registro de misiones). También se puede ejecutar una arena directamente (F6 sobre `scenes/world/HollowWoods.tscn`): usa el personaje/mapa por defecto.

### Controles

| Entrada | Acción |
|---|---|
| WASD | Movimiento (relativo a la cámara) |
| Ratón | Cámara en tercera persona (clic recaptura el cursor si se libera) |
| Espacio | Salto |
| Shift (moviéndose) | Derrape (burst de velocidad, colisión baja) |
| E | Interactuar (santuarios, cofres, secretos) |
| Esc | Menú de pausa (Resume / Settings / Quit to Menu) |

Las armas disparan automáticamente al enemigo más cercano: no hay botón de ataque. Los mapeos viven en `project.godot` (`[input]`: `move_*`, `jump`, `sprint`, `interact`).

## Compilar (export)

Hay tres presets en `export_presets.cfg`: **macOS** (`builds/Bonkraiders.app`), **Windows Desktop** (`builds/Bonkraiders.exe`) y **Linux/X11** (`builds/Bonkraiders.x86_64`). Desde la raíz:

```sh
mkdir -p builds
godot --headless --export-release "macOS" builds/Bonkraiders.app
```

Para Windows/Linux se usan los mismos comandos con `"Windows Desktop"` / `"Linux/X11"`, pero hay que **descargar antes las export templates 4.7.2** de la plataforma destino (Editor > Manage Export Templates, o `Godot_v4.7.2-stable_export_templates.tpz`). La carpeta `builds/` está en `.gitignore`. Versión actual: `0.1.0` (`config/version` en `project.godot`, mostrada en el selector).

## Estructura del proyecto

```
project.godot            # autoloads, input map, escena principal
export_presets.cfg       # presets macOS / Windows / Linux
GDD.md                   # documento de diseño
CHANGELOG.md             # una línea por iteración (28 hasta ahora)
docs/ARQUITECTURA.md     # mapa de sistemas: dónde tocar para extender cada cosa
assets/
  audio/sfx/             # 20 wav sintetizados (regenerables, ver ARQUITECTURA)
  audio/ambient/         # camas de viento por bioma (forest_wind, desert_wind)
  materials/             # StandardMaterial3D .tres de los props low-poly
scenes/
  ui/                    # CharacterSelect (main), HUD, UpgradeCardUI, PauseMenu,
                         #   RunEndScreen, QuestLog, SettingsPanel
  player/Player.tscn     # CharacterBody3D + SpringArm3D + Weapons + Health + Stats
  weapons/               # 8 armas + proyectiles (Projectile, Arrow, BoomerangProjectile)
  enemies/               # Grunt/Skirmisher/Tank/Sunspitter/Duneburrower, jefes
                         #   (Rotking, Sarcognath), minijefes (Grubthing, CofferMimic)
  world/                 # HollowWoods.tscn y AshDunes.tscn (arenas),
                         #   RunSystems.tscn (bloque común de partida),
                         #   props/, shrines/, chests/, secrets/
  systems/               # XpGem, HealthOrb
  fx/                    # DamagePopup, DeathBurst, TelegraphDisc
scripts/                 # espejo de scenes/: systems/ (autoloads y catálogos),
                         #   player/, weapons/, enemies/, world/, ui/, fx/,
                         #   tools/generate_sfx.gd (generador de audio)
```

Los archivos clave para tocar contenido son los **catálogos** en `scripts/systems/`: `upgrade_pool.gd` (armas y cartas), `character_catalog.gd`, `tome.gd`, `map_catalog.gd`, `quest_catalog.gd`. Ver `docs/ARQUITECTURA.md`.

## Verificación (usada en todo el desarrollo)

Tras cualquier cambio, desde la raíz:

```sh
# 1. Reimporta assets y compila todos los scripts; debe salir con exit 0
godot --headless --import

# 2. Boot de humo: la arena arranca sin errores (5 s simulados)
godot --headless --fixed-fps 60 --quit-after 300 res://scenes/world/HollowWoods.tscn

# 3. Soak largo: simula minutos de partida más rápido que tiempo real
#    (36000 frames = 10 min de juego). Revisar el log: los sistemas imprimen
#    una línea por evento ("Boss spawned: ...", "Run ended: ...", "Meta saved: ...")
godot --headless --fixed-fps 60 --quit-after 36000 res://scenes/world/HollowWoods.tscn
```

También arrancan así `AshDunes.tscn` y las escenas de UI. Para lógica aislada, el patrón usado fue un harness desechable `extends SceneTree` ejecutado con `godot --headless --path . -s <script>` (igual que `scripts/tools/generate_sfx.gd`). El overlay de rendimiento (FPS, conteos, pools) se activa con la variable de entorno `BONK_PERF=1`.

## Guardado

Un único JSON en `user://save.json` (Shards, personajes desbloqueados, contadores de misiones, tiers, ajustes). En macOS:

```
~/Library/Application Support/Godot/app_userdata/Bonkraiders/save.json
```

(Windows: `%APPDATA%\Godot\app_userdata\Bonkraiders\`; Linux: `~/.local/share/godot/app_userdata/Bonkraiders/`.)

**Resetear el progreso** = borrar ese archivo con el juego cerrado; se regenera limpio al arrancar (Rook y Vex desbloqueados, 0 Shards). Un archivo corrupto no crashea: `SaveData.load_from_disk()` cae a valores por defecto. Los harness de prueba pueden apuntar `SaveData.save_path` a un archivo temporal antes de `load_from_disk()`.
