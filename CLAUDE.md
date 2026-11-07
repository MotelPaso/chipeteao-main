# Bonkraiders — how to write code here

Godot 4.7, typed GDScript. A team of students edits this code by hand to make
quick changes: a colour, a number, a text. Every change you make must keep
that easy. Someone who has never opened the file should find the value in
under a minute and change it without breaking anything. `docs/CAMBIOS-RAPIDOS.md`
is their map; keep it true.

## Where values live

- **What is shown owns how it looks.** The node that draws something keeps
  its colours, sizes, durations and texts as `@export` vars in its own script.
  Callers pass meaning (a flag, an enum, an id, a data row), never
  presentation. Example: `Health` tells `DamagePopup` "crit" or "dodge", and
  `DamagePopup` decides the colour and the font size.
- **Design values are `@export` at the top of the owning script**, grouped
  with `@export_group("Nombre en español")`. Each one gets a one-line `##`
  tooltip in Spanish with its unit (it is what the Inspector shows on hover).
  Never bury a tunable inside a function body. Use `const` only for values
  nobody tunes (math, keys, protocol), or in scripts that no scene uses
  (catalogs, `.new()` helpers), where a commented "edita aquí" const block at
  the top is the right place.
- **One source of truth.**
  - A script used by a single scene gets no overrides for its exports in the
    `.tscn`. Change the script default instead, so editing the script always
    works.
  - Per-instance values belong in each scene: each enemy's `max_hp`, each
    weapon's `damage`/`cooldown`/`attack_range`, per-map scatter values.
  - When a base-class default is the value in effect for exactly one scene,
    write it explicitly into that scene.
  - Never let `_ready` overwrite a value the scene already shows in the
    Inspector.
- **Catalogs are data.** Rows in `scripts/systems/catalogs/` follow the header
  of their file, which lists the internal keys and the fields that are free to
  edit. Internal keys are `id`s, rarity names, `node_name`s, and anything
  used as a save key or quest stat. Never rename one. Ids are
  `snake_case` (the catalog lint enforces it). Renaming a character id needs
  an alias in `SaveData.ID_ALIASES`.

## How code reads

- **Comments and `##` tooltips are in Latin American Spanish.** Identifiers,
  ids, group names, `StringName`s, `res://` paths, SaveData keys and every
  `print()`/`push_warning()` stay in English: the soak harness greps the logs.
  Player-facing text follows `docs/GLOSARIO.md`.
- Comments say what the code does now and why, in one or two lines. No
  history in code: no iteration numbers, audit ids, "antes…", or stories about
  past bugs. That goes in the commit message and `CHANGELOG.md`.
- Keep files under ~400 lines and functions under ~50. When a file grows past
  that, split it by responsibility into a child node, a component scene or a
  helper script next to its owner (`scripts/<area>/<owner>/`).
- Script layout: `class_name`/`extends`, doc comment, signals, enums, consts,
  `@export` (grouped), public vars, private vars, built-in callbacks, public
  methods, private methods.

## Things reached by name (do not break them silently)

Many calls go through strings: `call_group("hud", "announce", …)`,
`has_method("add_points")`, `get("pet_id")`, group names, `%UniqueName`s,
export names stored in `.tscn` files, catalog rows that set properties by
name, and the log lines `tools/verificar.sh` greps. Before you rename or move
a symbol, `grep -rn` it across `scripts/`, `scenes/` and `tools/`. When a
public method moves into a component, keep a same-named forwarder on the
original node. The harness in `scenes/tests/` calls into the game this way
too.

## Docs to keep current

- `docs/CAMBIOS-RAPIDOS.md`: the team's "where do I change X" table. Update
  its row when you add or move a value someone may want to change.
- `docs/ARQUITECTURA.md`: the system map (how to add a weapon, an enemy, a
  map…).
- `docs/GLOSARIO.md`: player-facing terms; it is mandatory for new text.

## Before a PR

Run `tools/verificar.sh`: headless import, catalog lint, UI probe and soaks.
`godot --headless --import` alone does not catch parse errors in scripts that
only a scene loads; the soaks do. Team PRs go to `MotelPaso/chipeteao-main`,
base `main`, which needs one approving review.
