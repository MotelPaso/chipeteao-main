class_name CatalogIndex
extends RefCounted
## Shared id -> row lookup for the static catalogs (tomes, items, relics,
## characters, pets, quests, maps, evolutions, weapons).
##
## Why this exists: every catalog used to copy the same linear
## "for row in LIBRARY: if String(row.id) == wanted: return row" loop — nine
## identical bodies that a new catalog copied a tenth time. Worse, those
## lookups sit on a hot path: PlayerStats.recompute() resolves one row per
## tome stack, per item stack and per relic, and it runs on every level-up,
## every altar boon and every timed-boon expiry.
##
## The libraries are `const`, so an index built once can never go stale.
## Each catalog keeps its own `static var` index plus its public by_id():
## the contract callers see does not change, only the cost of a lookup.

## id -> row map for `rows`, keyed by `field`. Rows without the field (or
## with an empty value) are skipped, so optional keys like `unlock_boss`
## index cleanly. First row wins on duplicate ids, matching the old loops.
static func build(rows: Array[Dictionary], field: String = "id") -> Dictionary[String, Dictionary]:
	var index: Dictionary[String, Dictionary] = {}
	for row: Dictionary in rows:
		var key := String(row.get(field, ""))
		if key.is_empty() or index.has(key):
			continue
		index[key] = row
	return index


## Every value of `field` across `rows` whose row matches `value` on
## `match_field` — the "all ids of this rarity/kind" shape.
static func values_where(rows: Array[Dictionary], match_field: String, value: String,
		field: String = "id") -> Array[String]:
	var out: Array[String] = []
	for row: Dictionary in rows:
		if String(row.get(match_field, "")) == value:
			out.append(String(row.get(field, "")))
	return out
