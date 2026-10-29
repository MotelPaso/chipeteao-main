class_name HealthOrb
extends MagnetPickup
## Health pickup dropped by elites (chance) and bosses (guaranteed count):
## the shared MagnetPickup chassis plus a flat heal — deliberately NOT
## scaled by map-tier XP factors — and an idle scale pulse. A global soft
## cap keeps generous boss fights from carpeting the arena with heals;
## because the chassis leaves the live group before every pooled release,
## the cap only ever counts orbs actually lying on the ground.

## Every live (dropped, uncollected) orb is in this group: drop sites
## count it for the soft cap and the level-up vacuum reaches orbs by it.
const LIVE_GROUP: StringName = &"health_orbs"
## Global cap on live orbs; drop sites skip the drop at the cap so
## generous boss fights cannot carpet the arena with heals.
const SOFT_CAP: int = 6

## Fraction of the player's max HP restored on pickup (flat: tiers and
## elites never scale it).
@export var heal_fraction: float = 0.15
## Idle scale-pulse swing (0.08 = ±8%) — the "alive" heartbeat read.
@export var pulse_amount: float = 0.08
@export var pulse_speed: float = 5.0


## Orb tuning of the shared magnet chassis: a shorter reach and a shorter
## life than an XP gem, and a lazier spin. Set here rather than as export
## defaults because the chassis is shared; HealthOrb.tscn stores no
## overrides, and any it gained would still win (scene properties are
## applied after _init).
func _init() -> void:
	magnet_radius = 3.5
	lifetime = 45.0
	spin_speed = 1.8
	bob_amplitude = 0.1


## True when the arena already holds SOFT_CAP live orbs. Drop sites check
## this before acquiring another (parked/releasing orbs left the group, so
## they are never counted against the cap).
static func at_soft_cap(tree: SceneTree) -> bool:
	return tree.get_node_count_in_group(LIVE_GROUP) >= SOFT_CAP


func live_group() -> StringName:
	return LIVE_GROUP


func _idle_visuals(_delta: float) -> void:
	_visual.scale = Vector3.ONE * (1.0 + pulse_amount * sin(_age * pulse_speed))


func _on_collected(collector: Node3D) -> void:
	var health := Health.find_in(collector)
	if health != null:
		# Health.heal clamps to max_hp (no overheal) and no-ops once dead.
		health.heal(health.max_hp * heal_fraction)
	Sfx.play(&"heal")
