class_name LuckyBlock
extends Interactable
## A block that looks like a chest and is not one (iteration 56): free,
## rare, and it always pays SOMETHING. There is no price and no rarity
## roll — the whole item is the surprise, which is why every outcome is
## good and they differ in kind rather than in size.
##
## Rewards are a weighted table, one branch each. A tenth reward is a row
## plus a branch, never a special case somewhere else.

@export var sink_time: float = 0.55
@export var block_color: Color = Color(1.0, 0.85, 0.2)
## enemy_explosion reach, and what a boss loses instead of dying.
@export var explosion_radius: float = 12.0
@export var boss_hp_fraction: float = 0.15
@export var gem_count: int = 25
@export var gem_spread: float = 6.0
@export var points_reward: int = 80

## The table. Weights are relative; the well is the rarest because it is
## the only one that asks the player a question.
const LUCKY_REWARDS: Array[Dictionary] = [
	{"id": "enemy_explosion", "weight": 1.0},
	{"id": "gem_rain", "weight": 1.0},
	{"id": "points", "weight": 1.0},
	{"id": "free_chest", "weight": 1.0},
	{"id": "powerup", "weight": 1.0},
	{"id": "well", "weight": 0.7},
]

const CHEST_SCENE: PackedScene = preload("res://scenes/world/chests/Chest.tscn")
## Chance the well pays a power-up instead of the better item.
const WELL_POWERUP_CHANCE: float = 0.3
## Items the well offers at once, plus the "keep everything" card. TWO,
## not three: the card UI has exactly three slots and drops the surplus
## without a word, so three items plus the refusal made four options and
## the refusal was the one that fell off — a raider carrying three items
## was forced to give one away, in the one reward whose whole point is
## that it asks a question you may answer with no.
const WELL_OFFERS: int = 2
const WELL_TITLE: String = "El pozo pide una ofrenda"
const WELL_NOTHING: String = "Nada"
const WELL_NOTHING_LINE: String = "Te quedas con todo"
const WELL_GIVE_LINE: String = "Lo cambias por algo mejor"

## Harness override (ArenaProbe, BONK_LUCKY_REWARD): reward ids the next
## blocks pay instead of rolling. STATIC, because the roll is static and
## because the queue has to survive between blocks — a soak with six
## blocks in BONK_POI_NOW is how all six branches get executed in one run,
## and left to the weighted table that takes hundreds of blocks. The last
## entry repeats, so one id holds for every block. Empty in every real
## game: nothing but the probe ever writes it.
static var _forced_rewards: Array[String] = []

var _spent: bool = false
var _time: float = 0.0
var _body: MeshInstance3D = null


func _init() -> void:
	prompt_text = "[E] Abrir bloque de la suerte"
	marker_kind = &"lucky_block"
	prompt_height = 2.4
	# No meta counter: this is not a chest, and the quests that count
	# chests must not count these.
	meta_stat_id = ""
	collision_layer = 0
	collision_mask = 1


func _ready() -> void:
	# Detection ring BEFORE super(), which wires body_entered on this Area3D.
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 1.9
	cylinder.height = 2.6
	shape.shape = cylinder
	shape.position.y = 1.3
	add_child(shape)
	super()
	add_to_group(&"lucky_blocks")
	_build_visual()


func _build_visual() -> void:
	_body = MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = Vector3(0.9, 0.9, 0.9)
	_body.mesh = cube
	# Per-instance material: the bob writes emission energy, and a shared
	# resource would pulse every other block on the map with it.
	var gold := StandardMaterial3D.new()
	gold.albedo_color = block_color
	gold.metallic = 0.55
	gold.roughness = 0.35
	gold.emission_enabled = true
	gold.emission = block_color
	gold.emission_energy_multiplier = 0.7
	_body.material_override = gold
	_body.position.y = 0.65
	add_child(_body)
	var mark := Label3D.new()
	mark.text = "?"
	mark.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	mark.no_depth_test = true
	mark.font_size = 64
	mark.outline_size = 14
	mark.modulate = Color(0.25, 0.18, 0.05)
	mark.position.y = 0.65
	add_child(mark)
	var light := OmniLight3D.new()
	light.light_color = block_color
	light.light_energy = 1.6
	light.omni_range = 6.0
	light.position.y = 1.0
	add_child(light)


func _physics_process(delta: float) -> void:
	_time += delta
	if _body != null and available:
		_body.position.y = 0.65 + sin(_time * 2.0) * 0.06
		_body.rotate_y(delta * 0.9)


func _interact(player: Node) -> void:
	if _spent or not available:
		return
	_spent = true
	_emit_started()
	consume()
	var reward := _roll_reward()
	match reward:
		"enemy_explosion":
			_reward_explosion()
		"gem_rain":
			_reward_gems()
		"points":
			_reward_points(player)
		"free_chest":
			_reward_chest()
		"powerup":
			_reward_powerup(player)
		"well":
			# The ONE reward that asks a question. It logs its own line
			# once it resolves, and it always resolves — including when the
			# raider carries nothing.
			_reward_well(player)
			_finish()
			return
	print("Lucky block: %s" % reward)
	_finish()


func _finish() -> void:
	Juice.sparkle(global_position + Vector3.UP * 1.0)
	_emit_completed()
	_sink()


## Queues the reward ids the next blocks pay (harness only). An unknown
## id is a push_error and is dropped: a soak that believed it was testing
## the well while the table rolled points reports a green run about a
## branch it never ran.
static func force_rewards(ids: Array[String]) -> void:
	var known: Dictionary[String, bool] = {}
	for row: Dictionary in LUCKY_REWARDS:
		known[String(row.id)] = true
	_forced_rewards.clear()
	for id: String in ids:
		if known.has(id):
			_forced_rewards.append(id)
		else:
			push_error("LuckyBlock: unknown forced reward '%s'" % id)


static func _roll_reward() -> String:
	# The harness queue, when one is loaded: consumed front to back, and
	# the last entry stays so a one-id queue holds for every block.
	if not _forced_rewards.is_empty():
		var forced := _forced_rewards[0]
		if _forced_rewards.size() > 1:
			_forced_rewards.remove_at(0)
		return forced
	var total := 0.0
	for row: Dictionary in LUCKY_REWARDS:
		total += float(row.weight)
	var roll := randf() * total
	for row: Dictionary in LUCKY_REWARDS:
		roll -= float(row.weight)
		if roll <= 0.0:
			return String(row.id)
	return String(LUCKY_REWARDS[0].id)


## Everything nearby dies. Bosses are the exception: killing one outright
## would turn a free block into the answer to the fight it is standing in.
func _reward_explosion() -> void:
	var radius_sq := explosion_radius * explosion_radius
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		var body := node as Node3D
		if body == null or not body.is_inside_tree():
			continue
		if body.global_position.distance_squared_to(global_position) > radius_sq:
			continue
		var health := Health.find_in(body)
		if health == null or health.is_dead:
			continue
		Juice.burst(body.global_position + Vector3.UP * 0.6, block_color, 10)
		if body.is_in_group("boss"):
			health.take_damage(health.max_hp * boss_hp_fraction)
		else:
			health.take_damage(health.current_hp + health.armor)
	Juice.shake(0.3)


func _reward_gems() -> void:
	for i in gem_count:
		var gem := Pools.acquire_scene(Pools.XP_GEM_SCENE) as XpGem
		if gem == null:
			return
		var angle := randf() * TAU
		var distance := randf_range(1.0, gem_spread)
		gem.global_position = global_position \
				+ Vector3(cos(angle), 0.0, sin(angle)) * distance + Vector3.UP * 0.6


func _reward_points(player: Node) -> void:
	if player.has_method("add_points"):
		player.call("add_points", points_reward)


## A free chest beside the block. EnemyBase.spawn_chest is an INSTANCE
## method on an enemy, so these eight lines are copied rather than reached
## for; extracting a shared helper would mean touching the death path for
## one caller that is not a death.
func _reward_chest() -> void:
	var chest := CHEST_SCENE.instantiate() as Chest
	if chest == null:
		return
	chest.free_open = true
	var parent := RunRoot.stage_parent(get_tree())
	if parent == null:
		return
	parent.add_child(chest)
	chest.global_position = global_position + Vector3(1.6, 0.0, 0.0)


func _reward_powerup(player: Node) -> void:
	var powerups := PowerUps.find_in(player)
	if powerups != null:
		# Never the star: that one is found roaming the map, which is the
		# only thing that makes it rare.
		powerups.apply(PowerUpCatalog.roll_id(true))


## The well: give one item, get a better one. With nothing to give it pays
## a power-up outright rather than opening a menu with one dead card —
## open_choice returns early on an empty list, and a block that silently
## did nothing would read as broken.
func _reward_well(player: Node) -> void:
	var bag := ItemBag.find_in(player)
	var carried: Array[String] = bag.carried_ids() if bag != null else []
	if carried.is_empty():
		_reward_powerup(player)
		print("Lucky block: well (sin objetos -> power-up)")
		return
	carried.shuffle()
	var options: Array[Dictionary] = []
	for i in mini(WELL_OFFERS, carried.size()):
		var row := ItemCatalog.by_id(carried[i])
		options.append({
			"title": String(row.get("display_name", carried[i])),
			"description": WELL_GIVE_LINE,
			"color": ItemCatalog.rarity_color(String(row.get("rarity", "Common"))),
			"item_id": carried[i],
		})
	# The refusal is always on the shelf, so one carried item still makes a
	# real two-option choice.
	options.append({
		"title": WELL_NOTHING,
		"description": WELL_NOTHING_LINE,
		"color": UiTheme.TEXT_DIM,
		"item_id": "",
	})
	get_tree().call_group("upgrade_ui", "open_choice", WELL_TITLE, options,
			player, _on_well_pick.bind(player), "lucky_well")


func _on_well_pick(option: Dictionary, player: Node) -> void:
	var given := String(option.get("item_id", ""))
	if given.is_empty():
		print("Lucky block: well (nada)")
		return
	var bag := ItemBag.find_in(player)
	if bag == null or not bag.remove_item(given):
		print("Lucky block: well (nada)")
		return
	if randf() < WELL_POWERUP_CHANCE:
		_reward_powerup(player)
		print("Lucky block: well (%s -> power-up)" % given)
		return
	var paid := _next_rarity_item(String(ItemCatalog.by_id(given).get("rarity", "Common")))
	if paid.is_empty():
		_reward_powerup(player)
		print("Lucky block: well (%s -> power-up)" % given)
		return
	bag.add_item(paid)
	print("Lucky block: well (%s -> %s)" % [given, paid])


## One item of the tier above `rarity_name`; Legendary has no tier above,
## so it trades for another Legendary rather than for nothing.
static func _next_rarity_item(rarity_name: String) -> String:
	var index := UpgradePool.rarity_index(rarity_name)
	var better := mini(index + 1, UpgradePool.RARITIES.size() - 1)
	return ItemCatalog.roll_id(String(UpgradePool.RARITIES[better].name))


func _sink() -> void:
	set_physics_process(false)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * 0.05, sink_time) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
