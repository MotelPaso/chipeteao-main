# Glosario — español latinoamericano
Terminología canónica del juego. **Toda cadena visible por el jugador usa estas equivalencias**; si añades contenido nuevo, extiende esta tabla en vez de improvisar un término.
Lo que NO se traduce nunca: los `id` de catálogo, los `node_name`, los nombres de grupo, los `StringName` (`&"..."`), las rutas `res://`, las claves de `SaveData` y los `print()`/`push_warning()` de depuración (los soaks y `docs/ARQUITECTURA.md` dependen de ellos).

## Reglas de estilo
1. Español latino neutro. Prohibido: vosotros, coger, ordenador, chaval, guay, molar, tío, flipante, ratón, mando, recogida, PV, vale. Se dice: control, mouse, HP, recolección, esquirla, incursión, agarrar/tomar.
2. Tuteo siempre. Imperativos: Elige, Presiona, Sobrevive, Derrota, Abate, Gana, Termina. Nunca tercera persona en logros («Viste el amanecer», no «Vio el amanecer»).
3. Caja baja tipo oración en TODO nombre de arma, tomo (salvo la palabra del tomo), objeto, carta, misión, evolución, reliquia y enemigo: «Espada corta», «Ritmo de batalla», «Cien caídos». Nada de Title Case inglés.
4. Llevan mayúscula inicial en las dos partes solo: topónimos (Bosque Hueco, Dunas de Ceniza, Ciénaga Lóbrega), nombres de tomo («Tomo de Furia»), nombres propios de jefe (Rey Pútrido, Cofre Mímico, Espectro de la Ciénaga) y de evolución con genitivo (Mandoble del Caudillo, Resplandor Final).
5. Nombres de personaje intactos por regla 4 del brief: Juno, Nyx, Doc, Otto, Vex, Rook, Ash, Miro, Bogg, Kael, Torren, Wisp, **Bramble**, **Boxeador**, **PNG gucci morty** y **Backyardigan**. Bramble NO se traduce. Los tres nombres de la iteración 54 son palabras textuales del compañero de equipo y se copian tal cual: «Boxeador» ya está en español y NO se vuelve «Boxer», y «PNG gucci morty» conserva sus minúsculas y su sigla en mayúsculas — la regla 3 (caja baja tipo oración) nunca aplica a nombres de personaje. Si un nombre no cabe en su carta se **envuelve**, nunca se recorta: un nombre propio con puntos suspensivos es un nombre distinto.
6. Cuatro escalas distintas, cuatro palabras: level = Nivel / «Nv %d» (el raider); **etapa = Etapa / insignia «E%d»** (el mapa dentro de la partida); **vuelta = Vuelta / «V%d»** (loops completos al circuito de mapas); rank de reliquia = Rango. **«Grado» / «G%d» quedó retirado en la iteración 50**: los grados de mapa desaparecieron junto con el selector, y la dificultad ahora sale de cuán lejos llegó la partida, no de un menú. Si ves «Grado» en notas viejas, está muerto.
7. cooldown = «velocidad de ataque», y **siempre como bonificación positiva** (iteración 46): un enfriamiento que baja se escribe como una velocidad que sube («Enfriamiento de X -15%» → «Velocidad de ataque de X +15%»), incluido el texto de reliquias («-1.5%» → «+1.5%») y de pasivas. La matemática interna sigue siendo un multiplicador de enfriamiento (`cooldown_multiplier`, `cooldown_scale`): solo cambia lo que lee el jugador, porque «enfriamiento» obligaba a leer un número que baja como algo bueno. La palabra «enfriamiento» ya no aparece en ninguna cadena visible. «Recarga» sigue reservada a los portales («Recharging... %d s» → «Recargando... %d s», «Portals recharge» → «los portales se recargan»); usarla para cooldown crearía una sola palabra para dos sistemas.
8. Marcadores %d %s %.1f %.2f %02d %% \n: mismo número y mismo orden que el original, sin excepción. Ninguna cadena pierde o gana marcadores.
9. Mayúsculas con tilde (MORISTE, EN PAUSA, ARMERÍA, COLECCIÓN, MÁX, COMÚN, ÉPICO, RECLAMADA) y apertura obligatoria de ¿ y ¡.
10. RAREZAS: nunca traducir RARITIES[].name ni el campo "rarity" de item_catalog. Es id en 9 archivos. Traducir solo en pantalla con rarity_display() (ver bloque «rarezas»).
11. IDs, node_name, grupos, StringName &"...", rutas res://, claves de SaveData y todo print()/push_warning() quedan en inglés y sin tocar.
12. hud.gd:231 hace trim_prefix("Tome of "). Con tomos en español debe ser, EN ESTE ORDEN: .trim_prefix("Tomo del ").trim_prefix("Tomo de ") — al revés «Tomo del Azar» quedaría como «l Azar».
13. Cartas por arma (`upgrade_pool.gd`, `_entries_for_weapon`): en español el sustantivo va delante. Mantener concatenación, no % : "Daño de " + display + " +%d%%", "Velocidad de ataque de " + display + " +%d%%", "Alcance de " + display + " +%d%%", y las dos de dos stats. Así el conteo de marcadores no cambia.
14. run_end_screen.gd:82 pasa 3 argumentos. Traducir a "+%d esquirlas · %d %s — reclámalas en el registro" y cambiar el tercer argumento por la frase completa: "misión completada" si quest_count == 1, si no "misiones completadas". Prohibido «misión%s» (da «misiónes») y prohibido dejar «(s)» suelto.
15. `evolution_catalog.gd` busca el `display_name` traducido en `UpgradePool.WEAPON_LIBRARY`, nunca capitaliza el id: «¡%s evolucionó a %s!» y, desde la iteración 46, «¡%s asciende!» para los hitos posteriores (ascender = subir un escalón de arma cada 10 niveles; no es «evolucionar», que sigue siendo el cambio de nombre y de forma).
16. Co-op: character_select.gd:190/234/237/238 ya está en español peninsular. Corregir a control / mouse / J1 según la tabla ui_chrome. player.gd:508/511 ya está correcto: no tocar.
17. La ruleta es RULETA (RULETA DE LA FORTUNA + «[E] Girar la ruleta» + «Altar de la ruleta»); nunca «rueda», que en México es la vuelta al mundo.
18. Compuestos: verbo + sustantivo en plural (Perforacorazones, Matarreyes, Cazacoronas, Levantatapas); mata- no elide nunca. Escupesol va en singular (quitasol, girasol).
19. Los glifos de dos letras de item_catalog.gd se re-siglan al nombre español (tabla en «terminos»); un glifo «WS» sobre «Piedra de afilar» se lee como bug.
20. Brevedad: la etiqueta española no debe crecer más de ~10% sobre la inglesa en HUD, insignias y botones. Si crece, se recorta el adjetivo, nunca el sentido.
21. El mapa de Tab **no** es un menú y su título no lleva verbo: la cabecera es «Etapa N · Vuelta M — MM:SS» y los tres paneles son sustantivos sueltos («Estadísticas», «Jugadores», «Objetos»). La leyenda nombra **familias** en plural («Cofres», «Altares», «Portales») y en singular solo lo que es único en la etapa («Jefe», «Salida», «Manantial», «Ruleta»).

## Personajes (no se traducen)

| Inglés | Español |
|---|---|
| Rook | Rook |
| Vex | Vex |
| Ash | Ash |
| Juno | Juno |
| Bramble | Bramble |
| Otto | Otto |
| Nyx | Nyx |
| Wisp | Wisp |
| Torren | Torren |
| Doc | Doc |
| Miro | Miro |
| Bogg | Bogg |
| Kael | Kael |

## Armas

| Inglés | Español |
|---|---|
| Shortsword | Espada corta |
| Dart Pistol | Pistola de dardos |
| Ember Wand | Vara de brasas |
| Hunting Bow | Arco de caza |
| Thorn Whip | Látigo de espinas |
| Boomerang | Bumerán |
| Twin Daggers | Dagas gemelas |
| Spirit Orbs | Orbes espirituales |
| Storm Rod | Pararrayos |
| Blood Vial | Vial de sangre |
| Slime Trail | Rastro de baba |
| Aura | Aura |
| Stench | Hedor |
| Kamehameha | Kamehameha |

## Evoluciones de arma

| Inglés | Español |
|---|---|
| Warlord's Greatblade | Mandoble del Caudillo |
| Needlestorm | Tormenta de agujas |
| Solar Lance | Lanza solar |
| Heartpiercer | Perforacorazones |
| Gravewreath | Guirnalda sepulcral |
| Orbit Saw | Sierra orbital |
| Phantom Fangs | Colmillos fantasma |
| Plague Chalice | Cáliz de peste |
| Comet Ring | Anillo de cometas |
| Tempest Crown | Corona de tempestad |
| Acid Tide | Marea ácida |
| Halo of Ruin | Halo de ruina |
| Miasma | Miasma |
| Final Flash | Resplandor Final |

## Tomos

| Inglés | Español |
|---|---|
| Tome of Fury | Tomo de Furia |
| Tome of Haste | Tomo de Celeridad |
| Tome of Reach | Tomo de Alcance |
| Tome of Swiftness | Tomo de Ligereza |
| Tome of Precision | Tomo de Precisión |
| Tome of Ruin | Tomo de Ruina |
| Tome of Thirst | Tomo de Sed |
| Tome of Stone | Tomo de Piedra |
| Tome of Mist | Tomo de Bruma |
| Tome of Fortune | Tomo de Fortuna |
| Tome of Multitude | Tomo de Multitud |
| Tome of Lingering | Tomo de Persistencia |
| Tome of Wisdom | Tomo de Sabiduría |
| Tome of Chance | Tomo del Azar |
| Tome of Peril | Tomo del Peligro |
| Tome of Fury II | Tomo de Furia II |
| Tome of  | Tomo de  / Tomo del  (prefijo; ver principio 12: hud.gd:231) |

## Objetos

| Inglés | Español |
|---|---|
| Whetstone | Piedra de afilar |
| Iron Rations | Raciones de hierro |
| Lucky Coin | Moneda de la suerte |
| Swift Boots | Botas veloces |
| Spring Boots | Botas de resorte |
| Magnet | Imán |
| Fart Bag | Bolsa de pedos |
| Keen Eye | Ojo agudo |
| Titan Blood | Sangre de titán |
| Demon Blood | Sangre de demonio |
| Master Key | Llave maestra |
| Superhero Mask | Máscara de superhéroe |
| Cosmic Worm | Gusano cósmico |
| Alien Egg | Huevo alienígena |
| Dino Egg | Huevo de dino |
| Angry Egg | Huevo furioso |
| Capybara Friend | Amigo capibara |
| glyph "WS" | glifo "PA" |
| glyph "IR" | glifo "RH" |
| glyph "LC" | glifo "MO" |
| glyph "SB" | glifo "BV" |
| glyph "MG" | glifo "IM" |
| glyph "FB" | glifo "BP" |
| glyph "KE" | glifo "OA" |
| glyph "TB" | glifo "ST" |
| glyph "DB" | glifo "SD" |
| glyph "MK" | glifo "LM" |
| glyph "SM" | glifo "MS" |
| glyph "CW" | glifo "GC" |
| glyph "AL" | glifo "HA" |
| glyph "DN" | glifo "HD" |
| glyph "AB" | glifo "HF" |
| glyph "CP" | glifo "AC" |
| glyph "SP" (Spring Boots) | glifo "RS" (por «reSorte»: «BR» ya es Tomo de Bruma) |

## Mascotas

| Inglés | Español |
|---|---|
| Alien | Alienígena |
| Dinosaur | Dinosaurio |
| Angry Bird | Pájaro furioso |
| Capybara | Capibara |

## Reliquias (Armería)

| Inglés | Español |
|---|---|
| Ember Sigil | Sello de brasas |
| Heartwood Charm | Amuleto de roble |
| Whistling Fang | Colmillo silbante |
| Gilded Whisker | Bigote dorado |
| Tidal Anklet | Tobillera de marea |
| Barnacle Plate | Coraza de percebes |

## Enemigos

| Inglés | Español |
|---|---|
| Grunt | Esbirro |
| Skirmisher | Hostigador |
| Tank | Mole |
| Sunspitter | Escupesol |
| Duneburrower | Excavadunas |

## Jefes

| Inglés | Español |
|---|---|
| Rotking | Rey Pútrido |
| Sarcognath | Sarcognato |
| Fenwraith | Espectro de la Ciénaga |
| Grubthing | Larvón |
| Coffer Mimic | Cofre Mímico |
| Boss | Jefe |
| Rotking Elder | Rey Pútrido Ancestral |
| Sarcognath Elder | Sarcognato Ancestral |
| Fenwraith Elder | Espectro de la Ciénaga Ancestral |
| X Elder (patrón) | X Ancestral (patrón para todo elder_title) |
| Ascendant (título de rejefe) | Ascendente |

## Mapas

| Inglés | Español |
|---|---|
| Hollow Woods | Bosque Hueco |
| Ash Dunes | Dunas de Ceniza |
| Gloomfen | Ciénaga Lóbrega |

## Altares e interactuables

| Inglés | Español |
|---|---|
| Charge Shrine | Altar de carga |
| Curse Shrine | Altar demoníaco |
| demonic obelisk | obelisco demoníaco |
| Greed Shrine | Altar de codicia |
| Spring Shrine | Manantial |
| Portal Shrine | Portal |
| Roulette Shrine | Altar de la ruleta |
| Humming Skull | Cráneo zumbante |
| Odd Stump | Tocón raro |
| Chest | Cofre |
| supply chest | cofre de suministros |
| shrine | altar |
| free chest | cofre gratis |
| free (precio) | gratis (nunca «libre») |
| blessing | bendición (etiqueta de la carta de altar de carga) |
| pact | pacto (etiqueta de la carta de altar demoníaco) |

### Menú del altar de carga (iteración 47)

| Inglés | Español |
|---|---|
| `The altar offers you a gift` | El altar te ofrece un don |
| `Blessing` | Bendición |
| `Fury` / `Rhythm` / `Breadth` | Furia / Ritmo / Amplitud |
| `Swiftness` / `Vigor` / `Carapace` | Ligereza / Vigor / Coraza |
| `Fortune` / `Precision` / `Wisdom` / `Multitude` | Fortuna / Precisión / Sabiduría / Multitud |
| `%s for the whole party` | %s para toda la party |

### Menú de pactos del altar demoníaco (iteración 47)

| Inglés | Español |
|---|---|
| `The obelisk offers a deal` | El obelisco ofrece un trato |
| `Pact` | Pacto |
| `You gain: %s\nYou pay: %s` | Ganas: %s\nPagas: %s |
| `Pact of fury` | Pacto de furia |
| `Pact of the pulse` | Pacto del pulso |
| `Pact of the carapace` | Pacto de la coraza |
| `Pact of flesh` | Pacto de carne |
| `Pact of the swarm` | Pacto del enjambre |
| `Pact of greed` | Pacto de codicia |
| `Pact of the hoard` | Pacto del arcón |
| `Pact of the omen` | Pacto del augurio |
| `+%d pts` | +%d pts |
| `a free chest right here` | un cofre gratis aquí mismo |
| `difficulty +%d%%` | dificultad +%d%% |
| `shiny chance +%d%%` | prob. de shiny +%d%% |
| `moons last %d%% longer` | las lunas duran %d%% más |
| `moon chance +%d%%` | prob. de luna +%d%% |
| `disaster chance +%d%%` | prob. de desastre +%d%% |

## Misiones

| Inglés | Español |
|---|---|
| Hundred Down | Cien caídos |
| Cull the Tide | Diezma la marea |
| Horde Accountant | Contador de hordas |
| Extinction Event | Evento de extinción |
| Kingslayer | Matarreyes |
| Crown Collector | Cazacoronas |
| Dynasty's End | Fin de la dinastía |
| Five Alive | Cinco y vivo |
| Double Digits | Dos cifras |
| Went the Distance | Hasta el final |
| Growth Spurt | Estirón |
| Seasoned Raider | Raider veterano |
| Apex Form | Forma suprema |
| Saw the Dawn | Viste el amanecer |
| Habitual Winner | Ganar es costumbre |
| Getting a Feel | Agarrando el ritmo |
| Regular Raider | Raider asiduo |
| Lifer | Cadena perpetua |
| Devout | Devoto |
| Shrine Circuit | Ruta de altares |
| Lid Lifter | Levantatapas |
| Treasure Route | Ruta del tesoro |
| Rook's Proof | La prueba de Rook |
| Vex's Routine | La rutina de Vex |
| Dune Strider | Andadunas |
| Sandblasted | Curtido por la arena |
| Into the Murk | Hacia el fango |
| Bogwalker | Andaciénagas |
| Wraithbane | Azote de espectros |
| Ascendant | Ascendente |
| Apex Raider | Raider supremo |
| Transcendence | Trascendencia |
| Arsenal Ascendant | Arsenal ascendente |
| First Relic | Primera reliquia |
| Creature of Habit | Animal de costumbres |
| Ritualist | Ritualista |
| Past the Dawn | Más allá del amanecer |
| The Long Night | La noche larga |
| What Lurks Below | Lo que acecha abajo |
| Tomb Raider | Saqueador de tumbas |

## Cartas de mejora

| Inglés | Español |
|---|---|
| Honed Edge | Filo aguzado |
| Quick Grip | Mano rápida |
| Long Reach | Largo alcance |
| Tempered | Temple |
| Battle Rhythm | Ritmo de batalla |
| Stout Heart | Corazón recio |
| Greed Aura | Aura de codicia |
| Split Darts | Dardos divididos |
| Barbed Heads | Puntas con púas |
| Clinging Thorns | Espinas aferradas |
| Far Flight | Vuelo lejano |
| Flurry | Ráfaga |
| Another Spirit | Otro espíritu |
| Forked Sky | Cielo bifurcado |
| Coagulate | Coagular |
| Thicker Slime | Baba más espesa |
| Ranker Stench | Hedor más rancio |
| Longer Beam | Rayo más largo |

## Otros

| Inglés | Español |
|---|---|
| Raider | raider |
| raiders | raiders |
| Run | incursión |
| Shards | esquirlas |
| Rank (relic) | Rango |
| Level | Nivel (abreviado Nv) |
| Armory | Armería |
| Collection | Colección |
| Quest log | Registro de misiones |
| Daily Hunt | Cacería diaria |
| Endless | Infinito |
| Points / pts | puntos / pts |
| XP gem | gema de XP |
| Health orb | orbe de vida |
| Blood Moon | Luna de sangre |
| Eclipse | Eclipse |
| Full Moon | Luna llena |
| Essence rift | grieta de esencia |
| elite (enemigo) | shiny (minúscula dentro de la frase, regla 3; nunca «élite») |
| Elite pack | jauría shiny |
| Extract / Extraction | extraerse / extracción |
| stage | etapa (un mapa dentro de la partida; insignia «E%d») |
| lap | vuelta (un circuito completo de mapas; insignia «V%d») |
| exit portal | portal de salida |
| cleared (stage) | superada (etapa superada) |
| pseudo-infinite | pseudo-infinito |
| gamepad | control (NUNCA «mando») |
| mouse | mouse (NUNCA «ratón») |
| Player 1 / P1 | Jugador 1 / J1 (NUNCA «P1») |
| Show FPS | Mostrar FPS (FPS no se traduce ni se declina) |
| jump | salto (mid-air jump = salto en el aire) |
| power-up | power-up (con guion, invariable en plural: «power-up»/«power-ups») |

## Estadísticas

| Inglés | Español |
|---|---|
| damage | daño |
| cooldown | velocidad de ataque (siempre en positivo; ver regla 7) |
| cooldowns | velocidad de ataque |
| attack speed | velocidad de ataque |
| ascend / ascension | ascender / ascenso (hito de arma cada 10 niveles) |
| area | área |
| attack area | área de ataque |
| move speed | velocidad de movimiento (corto: velocidad) |
| crit chance | prob. de crítico |
| crit damage | daño crítico |
| crit | crítico |
| lifesteal | robo de vida |
| armor | armadura |
| evasion | evasión |
| luck | suerte |
| thorns | espinas |
| max HP | HP máx. |
| HP | HP (nunca «PV») |
| projectiles | proyectiles |
| projectile | proyectil |
| duration | duración |
| effect duration | duración de efectos |
| XP gain | ganancia de XP |
| XP gained | XP ganada |
| XP | XP |
| difficulty | dificultad |
| gambling | apuesta |
| range | alcance |
| pierce | perforación |
| slow | ralentización |
| poison | veneno |
| pickup radius | radio de recolección |
| travel distance | distancia de vuelo |
| beam length | largo del rayo |
| chain | encadenamiento |
| recharge (portales) | recarga — reservado para portales, NO para cooldown |

## Mapa, minimapa y niebla (iteración 52)

| Inglés | Español |
|---|---|
| minimap | minimapa (el widget de esquina, uno por vista) |
| map | mapa (el de Tab, a pantalla completa) |
| map overlay | mapa (nunca «superposición»; en código, `map_overlay`) |
| fog of war | niebla de guerra (corto: niebla) |
| explored | explorado |
| unexplored | sin explorar |
| reveal | destapar (la niebla), revelar (un secreto) |
| legend | leyenda |
| marker | marcador |
| Stats | Estadísticas |
| Players | Jugadores |
| Items | Objetos |
| Stage %d | Etapa %d |
| Stage %d · Lap %d | Etapa %d · Vuelta %d |
| `%s — %02d:%02d` | `%s — %02d:%02d` |
| Boss | Jefe |
| Chests | Cofres |
| Altars | Altares |
| Spring | Manantial |
| Roulette | Ruleta |
| Portals | Portales |
| Exit | Salida |
| `J%d  %s  %s  %s  %d pts` | `J%d  %s  %s  %s  %d pts` |

Las filas del panel **Estadísticas** reusan tal cual los términos de la tabla
«Estadísticas» de más abajo, incluida la **regla 7**: `cooldown_multiplier` se
imprime como «Velocidad de ataque» y **en positivo**. Los nombres de arma,
tomo y objeto del panel **Objetos** salen de los catálogos ya traducidos: el
overlay no tiene tabla propia de nombres.

## Power-ups (iteración 53)

| Inglés | Español |
|---|---|
| power-up | power-up (invariable en plural: «power-ups»; nunca «potenciador») |
| Haste | Celeridad total |
| Might | Furia |
| Wisdom | Sabiduría brígida |
| Gold Rush | Fiebre del oro |
| Reflect | Reflejo |
| Vampire Mode | Modo vampiro |
| Flight | Vuelo |
| Immortality | Inmortalidad |
| Time Stop | Tiempo detenido |
| Star | Estrella |
| `¡TIEMPO DETENIDO!` | ¡TIEMPO DETENIDO! |
| `El tiempo vuelve a correr.` | El tiempo vuelve a correr. |
| `[E] Drink — %d pts (heal + random power-up)` | `[E] Beber — %d pts (cura + power-up al azar)` |
| `The spring restores and empowers you` | El manantial te restaura y te potencia |
| `Something bright crosses the field...` | Algo brillante cruza el campo... |
| `%s (%d s)` | `%s (%d s)` |

«Power-up» se queda en inglés a propósito: es la palabra que el equipo usó
en su propio pedido y la que cualquier jugador de este género reconoce;
«potenciador» sería más largo (regla 20) y menos claro. La **estrella** no
lleva apellido: en el juego es solo «Estrella», y el guiño a Mario vive en
el arcoíris, no en el nombre.

## Vendedores, caja de mascotas y mascotas nuevas (iteración 54)

| Inglés | Español |
|---|---|
| vendor | vendedor |
| Animal trafficker | Traficante de animales |
| Power-up vendor | Vendedor de power-ups |
| Item vendor | Vendedor de objetos |
| pet box | caja de mascotas |
| companion / pet | mascota (nunca «compañero», que es el otro jugador en co-op) |
| `A vendor arrives!` | ¡Llega un vendedor! |
| `The vendor packs up.` | El vendedor recoge el puesto. |
| `[E] See the animals` | `[E] Ver los animales` |
| `[E] See the power-up` | `[E] Ver el power-up` |
| `[E] See the goods` | `[E] Ver la mercancía` |
| `[E] Open the box` | `[E] Abrir la caja` |
| `A box with a paw appears...` | Una caja con una huella aparece en el campo... |
| `The box is empty.` | La caja está vacía. |
| `The box opens by itself` | La caja se abre sola |
| `Swap for %s` | Cambiar por %s |
| `Keep %s` | Quedarme con %s |
| `Choose what you take.` | Elige lo que te llevas. |
| `Deal! %s` | ¡Trato hecho! %s |
| `The vendor has nothing for you.` | El vendedor no tiene nada para ti. |
| `No pet` | Sin mascota |
| `%s joins` | %s se une |
| `%s says goodbye` | %s se despide |
| Doki | Doki |
| Pony | Pony |
| Cj7 | Cj7 |
| Magic Pumpkin | Calabaza mágica |
| Pokemon | Pokemon |

Los cinco nombres de mascota son palabras del compañero de equipo y viajan
sin traducir, como el roster de personajes: «Calabaza mágica» llegó ya en
español y ya en caja baja tipo oración, así que traducir o reestilar
cualquiera de los cinco inventaría un nombre que nadie del equipo usa.

## Rarezas

> **Cuidado:** `UpgradePool.RARITIES[].name` y el campo `rarity` de `ItemCatalog` son **claves de lógica**, no texto. Se leen como id en los precios de cofre (`RunState.CHEST_BASE_PRICES`), en la tirada de objetos y en varios santuarios. Se traducen **solo al pintarlos**, con `UpgradePool.rarity_display()`.

| Inglés | Español |
|---|---|
| Common | Común |
| Rare | Raro |
| Epic | Épico |
| Legendary | Legendario |
| COMMON | COMÚN |
| RARE | RARO |
| EPIC | ÉPICO |
| LEGENDARY | LEGENDARIO |
| SOLUCIÓN: función de presentación | Añadir a upgrade_pool.gd: const RARITY_ES := {"Common":"Común","Rare":"Raro","Epic":"Épico","Legendary":"Legendario"} y static func rarity_display(n:String)->String: return RARITY_ES.get(n,n). Usarla SOLO al pintar: upgrade_card_ui.gd:190 (con .to_upper()), chest.gd:68/70/115 y roulette_shrine.gd:101. |

## Interfaz

| Inglés | Español |
|---|---|
| `Shards: 0` | Esquirlas: 0 |
| `BONKRAIDERS` | BONKRAIDERS |
| `Choose your hunting ground and raider` | Elige tu coto de caza y tu raider |
| `Start Run` | Iniciar incursión |
| `Quests` | Misiones |
| `Settings` | Ajustes |
| `v0.0.0` | v0.0.0 |
| `v%s` | v%s |
| `T%d` | G%d |
| `Jugadores` | Jugadores |
| `Conecta %d mando(s) para %d jugadores` | Conecta %d control(es) para %d jugadores |
| `P1 teclado+ratón · P2-P%d mando · %d mando(s)` | J1 teclado+mouse · J2-J%d control · %d control(es) |
| `%d mando(s) conectado(s)` | %d control(es) conectado(s) |
| `Conecta mandos para co-op local` | Conecta controles para co-op local |
| `J%d: %s` | J%d: %s |
| `Start Run — %d jugadores` | Iniciar incursión — %d jugadores |
| `Start Run — %s` | Iniciar incursión — %s |
| `Shards: %d` | Esquirlas: %d |
| `Collection` | Colección |
| `Armory` | Armería |
| `Daily Hunt` | Cacería diaria |
| `Daily Hunt — best %d` | Cacería diaria — mejor %d |
| `%d Shards` | %d esquirlas |
| `— or %s` | — o %s |
| `Unlock for %d Shards?` | ¿Desbloquear por %d esquirlas? |
| `Yes` | Sí |
| `click card to cancel` | clic en la carta para cancelar |
| `find something odd in the Hollow Woods` | busca algo raro en el Bosque Hueco |
| `follow a strange hum in the Ash Dunes` | sigue un zumbido extraño en las Dunas de Ceniza |
| `Win a run in Hollow Woods` | Gana una incursión en el Bosque Hueco |
| `Win a run in Ash Dunes` | Gana una incursión en las Dunas de Ceniza |
| `COLLECTION` | COLECCIÓN |
| `Collection: 0 / 0 — 0%` | Colección: 0 / 0 — 0% |
| `Collection: %d / %d — %d%%` | Colección: %d / %d — %d%% |
| `Back` | Volver |
| `RAIDERS` | RAIDERS |
| `ARSENAL` | ARSENAL |
| `BESTIARY` | BESTIARIO |
| `A raider still out there...` | Un raider que sigue allá afuera... |
| `An unclaimed weapon...` | Un arma sin reclamar... |
| `Something not yet faced...` | Algo que aún no enfrentas... |
| `an evolved form awaits` | una forma evolucionada te espera |
| `reach weapon level %d to evolve it` | sube el arma al nivel %d para evolucionarla |
| `%s Lv %d: %s` | %s Nv %d: %s |
| `%s — %d slain` | %s — %d abatidos |
| `???` | ??? |
| `⤷ ???` | ⤷ ??? |
| `PAUSED` | EN PAUSA |
| `Resume` | Continuar |
| `Extract (end run)` | Extraerse (terminar incursión) |
| `Quit to Menu` | Salir al menú |
| `Lv 1` | Nv 1 |
| `Lv %d` | Nv %d |
| `00:00` | 00:00 |
| `%02d:%02d` | %02d:%02d |
| `T2` | G2 |
| `Cursed x1` | Maldito x1 |
| `Difficulty +%d%%` | Dificultad +%d%% |
| `Kills: 0` | Bajas: 0 |
| `Kills: %d` | Bajas: %d |
| `0 pts` | 0 pts |
| `%d pts` | %d pts |
| `100 / 100` | 100 / 100 |
| `%d / %d` | %d / %d |
| `Esc — Pause` | Esc — Pausa |
| `J%d` | J%d |
| `J%d K.O.` | J%d K.O. |
| `SHREDDING!` | ¡TRITURANDO! |
| `RAMPAGING!` | ¡ARRASANDO! |
| `UNSTOPPABLE!` | ¡IMPARABLE! |
| `A monstrous presence approaches...` | Una presencia monstruosa se acerca... |
| `QUEST LOG` | REGISTRO DE MISIONES |
| `Claim` | Reclamar |
| `CLAIMED` | RECLAMADA |
| `+%d Shards` | +%d esquirlas |
| `%d/%d` | %d/%d |
| `ARMORY` | ARMERÍA |
| `MAX` | MÁX |
| `SETTINGS` | AJUSTES |
| `SFX Volume` | Volumen de efectos |
| `Ambient Volume` | Volumen ambiente |
| `Mouse Sensitivity` | Sensibilidad del mouse |
| `1.00x` | 1.00x |
| `%.2fx` | %.2fx |
| `Fullscreen` | Pantalla completa |
| `Show FPS` | Mostrar FPS |
| `%d FPS` | %d FPS |
| `YOU DIED` | MORISTE |
| `RUN COMPLETE` | INCURSIÓN COMPLETA |
| `EXTRACTED` | EXTRACCIÓN LOGRADA |
| `RUN ABANDONED` | INCURSIÓN ABANDONADA |
| `The horde got you.` | La horda te alcanzó. |
| `You survived!` | ¡Sobreviviste! |
| `You made it out.` | Saliste con vida. |
| `Out before the goal.` | Saliste antes de la meta. |
| `Time survived` | Tiempo con vida |
| `Level reached` | Nivel alcanzado |
| `Total kills` | Bajas totales |
| `+0 shards` | +0 esquirlas |
| `Retry` | Reintentar |
| `Change Character` | Cambiar raider |
| `Quit` | Salir |
| `+%d shards · %d quest%s completed — claim in the quest log` | +%d esquirlas · %d %s — reclámalas en el registro |
| `"" if quest_count == 1 else "s"  (arg 3 de run_end_screen.gd:82)` | "misión completada" if quest_count == 1 else "misiones completadas" |
| `Daily score: %d — today's best: %d` | Puntaje diario: %d — mejor de hoy: %d |
| `Level up!` | ¡Subiste de nivel! |
| `Stage %d — %s` | Etapa %d — %s |
| `Stage cleared! The portal is open — stay as long as you like` | ¡Etapa superada! Se abrió el portal — quédate cuanto quieras |
| `The exit portal opened — cross it whenever you like` | Se abrió el portal de salida — crúzalo cuando quieras |
| `[E] Cross to the next map` | [E] Cruzar al siguiente mapa |
| `Stages cleared: %d` | Etapas superadas: %d |
| `Laps: %d` | Vueltas: %d |
| `You left before clearing a stage.` | Saliste antes de superar una etapa. |
| `E%d` / `E%d · V%d` | E%d / E%d · V%d (insignia de etapa del HUD) |
| `Level %d — choose: %s` | Nivel %d — elige: %s (el %s es el lado del pool: «Armas» o «Tomos», iteración 46) |
| `Weapons` (lado del pool) | Armas |
| `Tomes` (lado del pool) | Tomos |
| `Title` | Título |
| `Description` | Descripción |
| `Jugador %d` | Jugador %d |
| `New weapon: ` | Arma nueva:  |
| `WHEEL OF FORTUNE` | RULETA DE LA FORTUNA |
| `SPIN — %d pts` | GIRAR — %d pts |
| `Leave` | Salir |
| `You have %d pts` | Tienes %d pts |
| `Not enough points.` | No te alcanzan los puntos. |
| `▶ %s` | ▶ %s |
| `[E] Spin the wheel` | [E] Girar la ruleta |
| `[E] Spin the wheel — %d pts` | [E] Girar la ruleta — %d pts |
| `Spin costs %d pts (you have %d)` | Girar cuesta %d pts (tienes %d) |
| `%s: %s` | %s: %s |
| `Legendary item` | Objeto legendario |
| `Epic item` | Objeto épico |
| `Rare item` | Objeto raro |
| `Common item` | Objeto común |
| `All stats +10%` | Todas las stats +10% |
| `All weapons +1 level` | Todas las armas +1 nivel |
| `Jackpot: +120 pts` | Premio mayor: +120 pts |
| `Full heal` | Curación total |
| `Curse: slowed & weakened 20 s` | Maldición: lento y débil 20 s |
| `Difficulty +15%` | Dificultad +15% |
| `Enemies stronger 30 s` | Enemigos más fuertes 30 s |
| `[E] Interact` | [E] Interactuar |
| `[E] Open the chest` | [E] Abrir el cofre |
| `[E] Open chest — free` | [E] Abrir cofre — gratis |
| `[E] Open %s chest — %d pts` | [E] Abrir cofre %s — %d pts |
| `%s chest — %d pts (you have %d)` | Cofre %s — %d pts (tienes %d) |
| `%s chest: %s — %s` | Cofre %s: %s — %s |
| `[E] Step through` | [E] Atravesar |
| `Recharging... %d s` | Recargando... %d s |
| `[E] Drink — %d pts (heal + power-up)` | [E] Beber — %d pts (cura + power-up) |
| `The spring restores you — empowered for %d s` | El manantial te restaura — potenciado por %d s |
| `Stay inside to charge` | Quédate dentro para cargar |
| `Charging... %d%%` | Cargando... %d%% |
| `The altar hums: %s for everyone` | El altar zumba: %s para todos |
| `fades away, unclaimed` | se apaga sin que nadie lo reclame |
| `sinks away — you let go` | se hunde: lo soltaste |
| `[E] Channel the shrine` | [E] Canalizar el altar |
| `[E] Accept the curse` | [E] Aceptar la maldición |
| `The obelisk drinks deep: %s — the horde grows hungrier` | El obelisco bebe hondo: %s — la horda se pone más hambrienta |
| `[E] Offer blood` | [E] Ofrendar sangre |
| `The altar yields a prize` | El altar entrega un premio |
| `The altar is pleased.` | El altar queda complacido. |
| `[E] Listen to the humming skull` | [E] Escuchar el cráneo zumbante |
| `Listening... %d%%` | Escuchando... %d%% |
| `[E] The hum shied away — hold still` | [E] El zumbido se apartó — no te muevas |
| `The hum was a lure — the sand disgorges a coffer!` | El zumbido era un cebo: ¡la arena vomita un cofre! |
| `[E] Prod the odd stump` | [E] Hurgar el tocón raro |
| `Something fat and furious heaves out of the roots!` | ¡Algo gordo y furioso se abre paso entre las raíces! |
| `A muffled grumble rolls up through the roots...` | Un gruñido sordo sube por las raíces... |
| `The grumble swells. The mushroom quivers angrily.` | El gruñido crece. El hongo tiembla de rabia. |
| `The roots burst apart!` | ¡Las raíces revientan! |
| `Something hidden stirs...` | Algo oculto se remueve... |
| `CHARACTER UNLOCKED: %s!` | ¡RAIDER DESBLOQUEADO: %s! |
| `A charge altar rises — stand in its ring` | Se alza un altar de carga — párate en su anillo |
| `A demonic obelisk claws out of the ground...` | Un obelisco demoníaco sale del suelo a zarpazos... |
| `A spring bubbles up somewhere in the field...` | Un manantial brota en algún lugar del campo... |
| `A supply chest hums somewhere in the field...` | Un cofre de suministros zumba en algún lugar del campo... |
| `An elite pack picks up your scent!` | ¡Una jauría shiny te huele el rastro! |
| `An essence rift tears open...` | Se abre una grieta de esencia... |
| `BLOOD MOON — the horde goes berserk!` | LUNA DE SANGRE — ¡la horda enloquece! |
| `ECLIPSE — shadows pour in from everywhere` | ECLIPSE — las sombras entran por todos lados |
| `FULL MOON — fortune and wisdom shine on you` | LUNA LLENA — la fortuna y la sabiduría te sonríen |
| `A horde is closing in!` | ¡Se acerca una horda! |
| `The horde surges with unnatural strength!` | ¡La horda crece con una fuerza antinatural! |
| `%s Ascendant %d` | %s Ascendente %d |
| `Rotking Elder` | Rey Pútrido Ancestral |
| `Sarcognath Elder` | Sarcognato Ancestral |
| `Fenwraith Elder` | Espectro de la Ciénaga Ancestral |
| `Rotking` | Rey Pútrido |
| `The sand shivers over something entombed...` | La arena tiembla sobre algo sepultado... |
| `The marsh holds its breath...` | La ciénaga contiene el aliento... |
| `15 minutes survived — extract any time from the pause menu` | 15 minutos sobrevividos — extráete cuando quieras desde el menú de pausa |
| `%s evolved into %s!` | ¡%s evolucionó a %s! |
| `%s ascends!` | ¡%s asciende! (hito de arma cada 10 niveles, iteración 46) |
| `Reviviendo... %d%%` | Reviviendo... %d%% |
| `CAÍDO — mantén [Interactuar] cerca` | CAÍDO — mantén [Interactuar] cerca |
| `A patient wall of a raider whose swings only get meaner.` | Un muro con patas: sus golpes solo se ponen más feos. |
| `A twitchy sharpshooter who always finds the soft spots.` | Un tirador nervioso que siempre encuentra el punto blando. |
| `A soot-caked hermit whose fire blooms wider every level.` | Un ermitaño cubierto de hollín cuyo fuego se abre más en cada nivel. |
| `A fleet-footed stalker who turns raw speed into killing force.` | Una acechadora de pies ligeros que convierte la velocidad en fuerza mortal. |
| `A bristling warden whose hide punishes every careless bite.` | Un guardián erizado cuyo cuero castiga cada mordida descuidada. |
| `A stout wanderer who only gets harder to put down.` | Un errante recio al que cada vez cuesta más tumbar. |
| `A dusk-veiled blur who answers every whiffed swing with steel.` | Un borrón crepuscular que responde con acero a cada golpe fallado. |
| `A half-here spirit ringed by lights that answer only to it.` | Un espíritu a medias, rodeado de luces que solo le obedecen a él. |
| `A storm-chaser whose luck reads like a weather report.` | Un cazatormentas cuya suerte se lee como un parte del clima. |
| `A cheery field surgeon who bills every patient in blood.` | Un cirujano de campaña muy alegre que le cobra a cada paciente en sangre. |
| `A drooling slug of a raider who is never where the mess is.` | Una babosa babeante de raider que nunca está donde quedó el desastre. |
| `Nobody sits next to Bogg. Nobody survives near Bogg either.` | Nadie se sienta al lado de Bogg. Tampoco nadie sobrevive cerca de Bogg. |
| `Charges for six seconds, then rewrites the map.` | Carga seis segundos y después reescribe el mapa. |
| `+0.8% damage per level` | +0.8% de daño por nivel |
| `+0.5% crit chance per level` | +0.5% de prob. de crítico por nivel |
| `+0.7% area per level` | +0.7% de área por nivel |
| `+0.6% damage per 1% bonus move speed` | +0.6% de daño por cada 1% de velocidad extra |
| `+1 thorns per level` | +1 de espinas por nivel |
| `+2 max HP per level` | +2 de HP máx. por nivel |
| `+0.5% evasion per level; dodges execute weakened non-boss enemies` | +0.5% de evasión por nivel; al esquivar rematas a enemigos debilitados que no sean jefes |
| `-0.5% weapon cooldowns per level` | +0.5% de velocidad de ataque por nivel |
| `+1 luck per level (rarer upgrade cards)` | +1 de suerte por nivel (cartas más raras) |
| `+1% lifesteal per level (base +5%)` | +1% de robo de vida por nivel (base +5%) |
| `+2% effect duration per level` | +2% de duración de efectos por nivel |
| `+1% attack area per level` | +1% de área de ataque por nivel |
| `+1% damage per level` | +1% de daño por nivel |
| `sweeps a melee arc through nearby foes` | barre un arco cuerpo a cuerpo entre los enemigos cercanos |
| `snipes the nearest foe with fast homing darts` | castiga al enemigo más cercano con dardos rápidos que persiguen |
| `detonates fire bursts on distant packs` | detona estallidos de fuego sobre grupos lejanos |
| `looses straight arrows that skewer whole ranks` | suelta flechas rectas que ensartan filas enteras |
| `rakes a bramble line that snags and slows` | traza una línea de zarzas que engancha y ralentiza |
| `hurls a returning blade that cuts coming and going` | lanza una hoja que corta al ir y al volver |
| `shreds the nearest foe with rapid left-right stabs` | destroza al enemigo más cercano con estocadas rapidísimas |
| `orbiting familiars that burn whatever they touch` | espíritus en órbita que queman todo lo que rozan |
| `lightning that forks between packed foes` | rayos que se bifurcan entre enemigos apretados |
| `lobs flasks that pool blood under the thickest packs` | arroja frascos que encharcan sangre bajo los grupos más densos |
| `leaves caustic slime wherever you walk` | deja baba cáustica por donde camines |
| `a ring of light that burns everything near you` | un anillo de luz que quema todo a tu alrededor |
| `flatulent pulses that poison and slow the pack` | pulsos flatulentos que envenenan y ralentizan a la jauría |
| `a devastating beam that erases a whole lane` | un rayo devastador que borra un carril entero |
| `a colossal arc that cleaves the whole front line` | un arco colosal que parte toda la primera línea |
| `a hail of darts that never stops falling` | una granizada de dardos que no deja de caer |
| `detonations the size of a clearing` | detonaciones del tamaño de un claro |
| `arrows that thread entire columns of foes` | flechas que enhebran columnas enteras de enemigos |
| `a strangling bramble that all but stops the horde` | un zarzal que estrangula y casi detiene a la horda |
| `a screaming blade that carves out and back through everything` | una hoja aullante que talla al ir y al volver |
| `stabs faster than the eye can follow` | estocadas más rápidas de lo que el ojo alcanza |
| `pools that fester long after the flask shatters` | charcos que siguen pudriéndose mucho después de que el frasco revienta |
| `a blazing halo no body survives crossing` | un halo ardiente que nadie cruza y vive |
| `lightning that forks until nothing is left standing` | rayos que se bifurcan hasta que no queda nada en pie |
| `a corrosive wake that never quite dries` | una estela corrosiva que nunca termina de secarse |
| `a sun no body can stand inside` | un sol adentro del cual nadie aguanta |
| `a rot cloud that lingers on everything it touches` | una nube de podredumbre que se queda en todo lo que toca |
| `a beam wide enough to end a horde in one breath` | un rayo tan ancho que acaba una horda de un solo aliento |
| `All weapon damage +%d%%` | Daño de todas las armas +%d%% |
| `All weapon cooldowns -%d%%` | Velocidad de ataque de todas las armas +%d%% |
| `Attack area +%d%%` | Área de ataque +%d%% |
| `Move speed +%d%%` | Velocidad de movimiento +%d%% |
| `Crit chance +%d%%` | Prob. de crítico +%d%% |
| `Crit damage +%d%%` | Daño crítico +%d%% |
| `Lifesteal: heal %d%% of damage dealt` | Robo de vida: te curas el %d%% del daño hecho |
| `Armor +%d (flat damage reduction)` | Armadura +%d (reducción fija de daño) |
| `Evasion: %d%% chance to dodge hits` | Evasión: %d%% de probabilidad de esquivar golpes |
| `Luck +%d (better card and item rarities)` | Suerte +%d (mejores rarezas de cartas y objetos) |
| `+%d projectile(s) on every volley weapon` | +%d proyectil(es) en cada arma de andanada |
| `Effect durations +%d%% (slows, pools, poison)` | Duración de efectos +%d%% (ralentizaciones, charcos, veneno) |
| `XP gained +%d%%` | XP ganada +%d%% |
| `Gamble: %d random stat boon(s), bigger at higher rarity` | Apuesta: %d bonificación(es) de stat al azar, mayores a más rareza |
| `Difficulty +%d%%: tougher foes, richer XP` | Dificultad +%d%%: enemigos más duros, más XP |
| `All damage +8% per copy` | Todo el daño +8% por copia |
| `Max HP +15 per copy` | HP máx. +15 por copia |
| `Luck +8 per copy` | Suerte +8 por copia |
| `Move speed +6% per copy` | Velocidad de movimiento +6% por copia |
| `Periodically pulls every XP gem on the map; each copy pulls sooner and adds +10% XP` | Cada tanto atrae todas las gemas de XP del mapa; cada copia lo hace antes y suma +10% de XP |
| `Weapon hits poison enemies; more copies = stronger poison, duration stat lengthens it` | Los golpes de arma envenenan; más copias = veneno más fuerte, y la duración de efectos lo alarga |
| `Crit chance +5% per copy` | Prob. de crítico +5% por copia |
| `You grow 8% bigger and attacks cover +8% area per copy` | Creces un 8% y tus ataques cubren +8% de área por copia |
| `Demonic altars grant +25% more per copy` | Los altares demoníacos dan +25% más por copia |
| `Charge altars fill 20% faster and grant +20% more per copy` | Los altares de carga se llenan 20% más rápido y dan +20% más por copia |
| `Your kills release venomous spiders that hunt other enemies` | Tus bajas liberan arañas venenosas que cazan a otros enemigos |
| `Portals recharge 25% faster per copy` | Los portales se recargan 25% más rápido por copia |
| `An alien companion that zaps foes and adds +1 luck per level` | Un compañero alienígena que fulmina enemigos y suma +1 de suerte por nivel |
| `A dinosaur companion that bites and adds +2 max HP per level` | Un compañero dinosaurio que muerde y suma +2 de HP máx. por nivel |
| `An angry bird companion that snipes and adds crit per level` | Un compañero pájaro furioso que dispara de lejos y suma crítico por nivel |
| `A serene capybara that adds XP gain per level` | Un capibara sereno que suma ganancia de XP por nivel |
| `All damage %s per rank.` | Todo el daño %s por rango. |
| `Max HP %s per rank.` | HP máx. %s por rango. |
| `Weapon cooldowns %s per rank.` | Velocidad de ataque %s por rango. (texto del rango: «+1.5%») |
| `Luck %s per rank (rarer upgrade cards).` | Suerte %s por rango (cartas de mejora más raras). |
| `Move speed %s per rank.` | Velocidad de movimiento %s por rango. |
| `Armor %s per rank (flat damage reduction).` | Armadura %s por rango (reducción fija de daño). |
| `luck +1 per level` | suerte +1 por nivel |
| `max HP +2 per level` | HP máx. +2 por nivel |
| `crit +0.3% per level` | crítico +0.3% por nivel |
| `XP gain +0.6% per level` | ganancia de XP +0.6% por nivel |
| `damage +%d%%` | daño +%d%% |
| `cooldowns -%d%%` | velocidad de ataque +%d%% |
| `area +%d%%` | área +%d%% |
| `move speed +%d%%` | velocidad +%d%% |
| `max HP +%d` | HP máx. +%d |
| `armor +%d` | armadura +%d |
| `luck +%d` | suerte +%d |
| `crit chance +%d%%` | prob. de crítico +%d%% |
| `XP gain +%d%%` | ganancia de XP +%d%% |
| `+%d projectile` | +%d proyectil(es) |
| `+%d jump(s)` | +%d salto(s) |
| `power-up chance +%d%%` | prob. de power-up +%d%% |
| `Impulse` (boon de altar) | Impulso |
| `Lesser fortune` (boon de altar) | Fortuna menor |
| `Max HP +%d (heals the gained HP)` | HP máx. +%d (te cura lo que ganas) |
| `Pickup radius +%d%%` | Radio de recolección +%d%% |
| `display + " damage +%d%%"` | "Daño de " + display + " +%d%%" |
| `display + " cooldown -%d%%"` | "Velocidad de ataque de " + display + " +%d%%" |
| `display + " range +%d%%"` | "Alcance de " + display + " +%d%%" |
| `display + " damage +%d%%, range +%d%%"` | "Daño de " + display + " +%d%%, alcance +%d%%" |
| `display + " cooldown -%d%%, damage +%d%%"` | "Velocidad de ataque de " + display + " +%d%%, daño +%d%%" |
| `Dart Pistol fires %d extra dart(s)` | La Pistola de dardos dispara %d dardo(s) más |
| `Hunting Bow arrows pierce %d more enemies` | Las flechas del Arco de caza perforan %d enemigos más |
| `Thorn Whip slow %d%% stronger` | La ralentización del Látigo de espinas es %d%% más fuerte |
| `Boomerang travel distance +%d%%` | Distancia de vuelo del Bumerán +%d%% |
| `Twin Daggers cooldown -%d%%` | Velocidad de ataque de las Dagas gemelas +%d%% |
| `Spirit Orbs gains %d more orb(s)` | Los Orbes espirituales suman %d orbe(s) más |
| `Storm Rod chains to %d more enemies` | El Pararrayos encadena a %d enemigos más |
| `Blood Vial pools pulse %d more time(s)` | Los charcos del Vial de sangre pulsan %d vez(ces) más |
| `Slime Trail puddles last %d%% longer` | Los charcos del Rastro de baba duran %d%% más |
| `Stench poison lasts %d%% longer` | El veneno del Hedor dura %d%% más |
| `Kamehameha beam reaches %d%% farther` | El rayo del Kamehameha llega %d%% más lejos |
| `Mossy glades under a patient green canopy.` | Claros musgosos bajo un dosel verde y paciente. |
| `Scorched sand, leaning monuments, a horizon that hums.` | Arena calcinada, monumentos inclinados, un horizonte que zumba. |
| `Drowned moss islands under a sky that never quite lightens.` | Islas de musgo anegado bajo un cielo que nunca termina de aclarar. |
| `the tide itself` | la marea misma |
| `keeps its distance, lobs bolts` | guarda distancia y lanza saetas |
| `armored, slow, relentless` | acorazado, lento, implacable |
| `line-of-sight laser artillery` | artillería láser a línea de visión |
| `ambushes from below` | embosca desde abajo |
| `boss of the Hollow Woods` | jefe del Bosque Hueco |
| `boss of the Ash Dunes` | jefe de las Dunas de Ceniza |
| `boss of the Gloomfen` | jefe de la Ciénaga Lóbrega |
| `what sleeps beneath the woods` | lo que duerme bajo el bosque |
| `the tomb-thing of the dunes` | la cosa sepulcral de las dunas |
| `Defeat 100 enemies.` | Derrota a 100 enemigos. |
| `Defeat 500 enemies.` | Derrota a 500 enemigos. |
| `Defeat 2,000 enemies.` | Derrota a 2000 enemigos. |
| `Defeat 5,000 enemies.` | Derrota a 5000 enemigos. |
| `Bring down your first boss.` | Abate a tu primer jefe. |
| `Bring down 5 bosses.` | Abate a 5 jefes. |
| `Bring down 15 bosses.` | Abate a 15 jefes. |
| `Survive 5 minutes in one run.` | Sobrevive 5 minutos en una incursión. |
| `Survive 10 minutes in one run.` | Sobrevive 10 minutos en una incursión. |
| `Survive 15 minutes in one run.` | Sobrevive 15 minutos en una incursión. |
| `Reach level 10 in one run.` | Llega al nivel 10 en una incursión. |
| `Reach level 20 in one run.` | Llega al nivel 20 en una incursión. |
| `Reach level 30 in one run.` | Llega al nivel 30 en una incursión. |
| `Win a run.` | Gana una incursión. |
| `Win 3 runs.` | Gana 3 incursiones. |
| `Finish 3 runs.` | Termina 3 incursiones. |
| `Finish 10 runs.` | Termina 10 incursiones. |
| `Finish 25 runs.` | Termina 25 incursiones. |
| `Use 3 shrines.` | Usa 3 altares. |
| `Use 10 shrines.` | Usa 10 altares. |
| `Open 3 chests.` | Abre 3 cofres. |
| `Open 10 chests.` | Abre 10 cofres. |
| `Win a run as Rook.` | Gana una incursión con Rook. |
| `Finish 5 runs as Vex.` | Termina 5 incursiones con Vex. |
| `Finish a run in Ash Dunes.` | Termina una incursión en las Dunas de Ceniza. |
| `Finish 3 runs in Ash Dunes.` | Termina 3 incursiones en las Dunas de Ceniza. |
| `Finish a run in the Gloomfen.` | Termina una incursión en la Ciénaga Lóbrega. |
| `Win a run in the Gloomfen.` | Gana una incursión en la Ciénaga Lóbrega. |
| `Bring down the Fenwraith 5 times.` | Abate al Espectro de la Ciénaga 5 veces. |
| `Complete a full lap of the map circuit.` | Completa una vuelta entera al circuito de mapas. |
| `Complete two full laps of the map circuit.` | Completa dos vueltas enteras al circuito de mapas. |
| `Evolve a weapon by leveling it up enough.` | Evoluciona un arma subiéndola lo suficiente de nivel. |
| `Evolve 4 weapons across your runs.` | Evoluciona 4 armas a lo largo de tus incursiones. |
| `Buy a relic rank in the Armory.` | Compra un rango de reliquia en la Armería. |
| `Finish a Daily Hunt.` | Termina una Cacería diaria. |
| `Finish 7 Daily Hunts.` | Termina 7 Cacerías diarias. |
| `Survive 20 minutes in one run.` | Sobrevive 20 minutos en una incursión. |
| `Survive 25 minutes in one run.` | Sobrevive 25 minutos en una incursión. |
| `Defeat what sleeps beneath the Hollow Woods.` | Derrota a lo que duerme bajo el Bosque Hueco. |
| `Unearth and defeat the tomb-thing of the Ash Dunes.` | Desentierra y derrota a la cosa sepulcral de las Dunas de Ceniza. |
