# Bonkraiders — Game Design Document

Mechanically inspired by Megabonk (Vedinad, 2025) — same structural "DNA" (3D bullet-heaven survival roguelite),
built from scratch with original names, art direction, and content so the team can freely modify/rebrand it.
No Megabonk assets, code, text, or branding are copied — only the game-design *patterns* researched from
public reviews, the Steam page, and community wikis.

## 1. Core Pillars

- **Genre**: 3D "bullet-heaven" survival roguelite (Vampire Survivors formula, taken to 3D — like Megabonk/Risk of Rain 2).
- **Camera**: Third-person, slightly elevated, following the player over the shoulder/top-back.
- **Session length**: ~15–20 minute timed runs. Survive the clock or die.
- **Loop**: Kill enemies → collect XP gems → level up → pick 1 of 3 randomized upgrade cards → build a synergy → fight escalating waves and bosses → run ends → spend meta-currency on permanent *unlocks* (not power).
- **Art direction**: Low-poly, colorful, exaggerated/meme-y proportions (original models, not Megabonk's).
- **Engine**: Godot 4.7, GDScript, `.glb`/procedural low-poly meshes.

## 2. Movement & Controls

- WASD move, mouse-look camera (or fixed follow-cam), Space = jump.
- **Slide**: hold Shift while moving at speed → crouch-slide with brief i-frames and speed burst.
- **Bunny-hop chaining**: jumping right as you land preserves slide momentum (skill-expressive movement).
- Some characters unlock extra traversal (double jump, wall-climb, glide) via their passive.
- No manual aiming for most weapons — attacks fire automatically at nearby/targeted enemies. Positioning and movement are the "aim."

## 3. Combat

- All weapons **auto-fire** on cooldown at valid targets (nearest, random, or lowest-HP depending on weapon).
- Weapon slots: player can carry multiple weapons simultaneously (stacking DPS sources), same as the genre standard.
- Damage numbers, crit chance/crit damage, attack speed, area size, projectile count/pierce are all upgradeable stats.
- "Tomes" = passive stat-modifier items (flat/percent buffs) separate from weapons — combine for build synergy.

## 4. Progression (per run)

- Enemies drop **XP shards**; collecting enough levels you up.
- On level-up: choose 1 of 3 random cards — new weapon, weapon upgrade (tiered I→V), or a Tome. Rarity tiers: Common/Rare/Epic/Legendary weight the offer pool.
- **Shrines** scattered across the map (interact to trigger):
  - *Charge Shrine* — channel while standing in a zone under enemy pressure for a big reward.
  - *Greed Shrine* — risk/reward gamble (pay HP or gold for a chance at rare loot).
  - *Curse Shrine* — makes the next boss spawn tougher clones, in exchange for guaranteed higher-rarity drops.
- Chests award guaranteed items; some require a small platforming/combat challenge to reach (verticality payoff).

## 5. Characters (original roster, 8 at launch, mirrors the "starting weapon + scaling passive" pattern)

| Name | Starting Weapon | Passive |
|---|---|---|
| Rook | Shortsword | +Damage per level |
| Vex | Dart Pistol | +Crit Chance per level |
| Ash | Ember Wand | +Burn radius per level |
| Juno | Hunting Bow | +Move Speed → +Damage conversion |
| Bramble | Thorn Whip | +Thorns/reflect per level |
| Otto | Boomerang | Wall-climb unlocked, +HP per level |
| Nyx | Twin Daggers | +Evasion per level, dodges can execute low-HP enemies |
| Doc | Blood Vial | +Lifesteal per level |

Two characters (Rook, Vex) are unlocked from the start; the rest unlock via in-run challenges (defeat a hidden miniboss, reach map tier 2, etc.) — mirrors the genre's "skill unlocks, not purchases" philosophy.

## 6. Enemies & Bosses

- Waves scale over the run timer: grunt swarms → ranged skirmishers → armored tanks → elite variants (glowing, bigger, faster).
- Each biome has a boss line that gets harder per map tier (reskins/palette + moveset additions), plus 1–2 hidden bosses unlocked via secret interactions (mirrors Megabonk's "Suspicious Bush" hidden-boss pattern, with original triggers).

## 7. Maps

- **Biome 1 — Hollow Woods**: default forest biome, moderate verticality, goblin/bug-type enemies.
- **Biome 2 — Ash Dunes**: unlocked by clearing Hollow Woods Tier 2; desert/wasteland biome, laser/area-denial enemies.
- Procedurally arranged from hand-built chunks (not full procedural generation at first — modular chunk assembly is far more feasible for iterative solo dev).

## 8. Meta-progression (between runs)

- Currency: **Shards** (renamed from Megabonk's "Silver") earned from quests/challenges, not from grinding stats.
- Spend Shards on: unlocking new characters, unlocking new starting weapons/Tomes into the run pool, cosmetics.
- **Deliberately no direct "+X% damage" permanent purchases** — matches the source game's stated design philosophy that mastery, not gold-grinding, is the power curve.
- Quest log tracks ~30–50 launch challenges (kill counts, no-damage boss clears, etc.) that unlock content.

## 9. Technical scope for iteration 1 (MVP loop)

1. Player controller: move, jump, slide, camera follow.
2. Auto-attack weapon system (1 weapon working end-to-end: fire, damage, cooldown).
3. Enemy spawner + basic grunt AI (seek player, melee damage).
4. XP gems, leveling, 3-card upgrade UI.
5. HUD: HP, XP bar, timer, level.
6. Death + run-end screen with run stats.
7. One playable arena chunk (Hollow Woods) with a couple of props for verticality.

Everything past this (multiple characters, shrines, bosses, meta-progression, second biome) layers on top once the MVP loop is fun and stable.
